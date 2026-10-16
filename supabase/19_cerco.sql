-- =====================================================================
-- 19_cerco.sql — MODO CERCO nos DUELOS online (2 rodadas: um defende, o outro ataca, depois troca)
-- Rode DEPOIS do 14, 15 e 17.
--   * duelos.modo e partidas_pvp.modo ('normal' ou 'cerco')
--   * convidar_duelo ganha p_modo; responder_duelo e a revanche levam o modo para a sala
--   * Cerco é sempre amistoso (não vale troféu de ranking; a aposta, se tiver, vale)
-- =====================================================================

alter table public.duelos add column if not exists modo text not null default 'normal';
alter table public.partidas_pvp add column if not exists modo text not null default 'normal';

-- a sala também diz o modo
create or replace function public.sala_json(s public.partidas_pvp) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('id', s.id, 'semente', s.semente, 'heroes', s.heroes, 'monsters', s.monsters,
    'niveis_heroes', s.niveis_heroes, 'niveis_monsters', s.niveis_monsters,
    'nome_heroes', (select split_part(nome, ' ', 1) from perfis where id = s.heroes),
    'nome_monsters', (select split_part(nome, ' ', 1) from perfis where id = s.monsters),
    'foto_heroes', (select avatar_url from perfis where id = s.heroes),
    'foto_monsters', (select avatar_url from perfis where id = s.monsters),
    'vencedor', s.vencedor, 'finalizada', s.finalizada, 'amistoso', s.amistoso,
    'aposta_moedas', s.aposta_moedas, 'aposta_trofeus', s.aposta_trofeus, 'modo', s.modo);
$$;

drop function if exists public.convidar_duelo(uuid, text, integer, integer);
create or replace function public.convidar_duelo(p_para uuid, p_lado text, p_moedas integer default 0, p_trofeus integer default 0,
  p_modo text default 'normal') returns uuid
language plpgsql security definer set search_path = public as $$
declare novo uuid; eu public.perfis; ele public.perfis;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_lado not in ('heroes','monsters') then raise exception 'lado inválido'; end if;
  if coalesce(p_modo, 'normal') not in ('normal', 'cerco') then raise exception 'modo inválido'; end if;
  if p_para = auth.uid() then raise exception 'você não pode duelar com você mesmo'; end if;
  select * into ele from perfis where id = p_para;
  if ele.id is null then raise exception 'jogador não encontrado'; end if;
  if not sao_amigos(auth.uid(), p_para) and coalesce(ele.visto_em < now() - interval '2 minutes', true) then
    raise exception '% não está online agora', split_part(ele.nome, ' ', 1);
  end if;
  if coalesce(p_moedas, 0) not in (0, 25, 50, 100, 200, 500) or coalesce(p_trofeus, 0) not in (0, 10, 20, 30, 50) then
    raise exception 'aposta inválida';
  end if;
  select * into eu from perfis where id = auth.uid();
  if eu.moedas < coalesce(p_moedas, 0) then raise exception 'você não tem moedas suficientes para essa aposta'; end if;
  if eu.trofeus < coalesce(p_trofeus, 0) then raise exception 'você não tem troféus suficientes para essa aposta'; end if;
  if (select count(*) from duelos where para = p_para and status = 'pendente' and criado_em > now() - interval '2 minutes') >= 3 then
    raise exception '% já tem convites demais agora. Tente daqui a pouco.', split_part(ele.nome, ' ', 1);
  end if;
  update duelos set status = 'cancelado' where de = auth.uid() and status = 'pendente';
  delete from duelos where criado_em < now() - interval '1 day';
  update perfis set lado_atual = p_lado where id = auth.uid();
  insert into duelos (de, para, lado_de, aposta_moedas, aposta_trofeus, modo)
  values (auth.uid(), p_para, p_lado, coalesce(p_moedas, 0), coalesce(p_trofeus, 0), coalesce(p_modo, 'normal')) returning id into novo;
  return novo;
end $$;

create or replace function public.responder_duelo(p_id uuid, p_aceitar boolean) returns json
language plpgsql security definer set search_path = public as $$
declare d public.duelos; s public.partidas_pvp; h uuid; m uuid;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  select * into d from duelos where id = p_id and para = auth.uid() for update;
  if d.id is null then raise exception 'convite não encontrado'; end if;
  if d.status <> 'pendente' or d.criado_em < now() - interval '90 seconds' then
    raise exception 'esse convite já acabou';
  end if;
  if not p_aceitar then
    update duelos set status = 'recusado' where id = d.id;
    return null;
  end if;
  if (select moedas from perfis where id = d.para) < d.aposta_moedas then raise exception 'você não tem moedas suficientes para essa aposta'; end if;
  if (select trofeus from perfis where id = d.para) < d.aposta_trofeus then raise exception 'você não tem troféus suficientes para essa aposta'; end if;
  if (select moedas from perfis where id = d.de) < d.aposta_moedas or (select trofeus from perfis where id = d.de) < d.aposta_trofeus then
    update duelos set status = 'cancelado' where id = d.id;
    raise exception 'seu amigo não tem mais o que apostou';
  end if;
  h := case when d.lado_de = 'heroes' then d.de else d.para end;
  m := case when d.lado_de = 'heroes' then d.para else d.de end;
  insert into partidas_pvp (heroes, monsters, semente, niveis_heroes, niveis_monsters, plataforma, amistoso, aposta_moedas, aposta_trofeus, modo)
  values (h, m, floor(random() * 4294967295)::bigint,
          coalesce((select jsonb_object_agg(personagem, nivel) from personagens_jogador where jogador = h), '{}'::jsonb),
          coalesce((select jsonb_object_agg(personagem, nivel) from personagens_jogador where jogador = m), '{}'::jsonb),
          'godot', (not d.ranqueada) or d.modo = 'cerco', d.aposta_moedas, d.aposta_trofeus, d.modo)
  returning * into s;
  update duelos set status = 'aceito', sala = s.id where id = d.id;
  return sala_json(s);
end $$;

create or replace function public.pedir_revanche(p_sala uuid) returns json
language plpgsql security definer set search_path = public as $$
declare s public.partidas_pvp; outro uuid; meu_lado text; d public.duelos;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  select * into s from partidas_pvp where id = p_sala;
  if s.id is null or auth.uid() not in (s.heroes, s.monsters) then raise exception 'você não está nesta partida'; end if;
  outro := case when auth.uid() = s.heroes then s.monsters else s.heroes end;
  meu_lado := case when auth.uid() = s.heroes then 'heroes' else 'monsters' end;
  select * into d from duelos where sala_origem = p_sala and status = 'pendente' and criado_em > now() - interval '90 seconds'
   order by criado_em desc limit 1;
  if d.id is not null then
    return json_build_object('id', d.id, 'de_mim', d.de = auth.uid(), 'status', d.status);
  end if;
  insert into duelos (de, para, lado_de, aposta_moedas, aposta_trofeus, sala_origem, ranqueada, modo)
  values (auth.uid(), outro, meu_lado, s.aposta_moedas, s.aposta_trofeus, p_sala, not s.amistoso, coalesce(s.modo, 'normal'))
  returning * into d;
  return json_build_object('id', d.id, 'de_mim', true, 'status', d.status);
end $$;

-- o aviso de duelo também diz o modo
create or replace function public.social_resumo() returns json
language plpgsql security definer set search_path = public as $$
declare r json;
begin
  if auth.uid() is null then return null; end if;
  update perfis set visto_em = now() where id = auth.uid();
  select json_build_object(
    'nao_lidas', (select count(*) from mensagens_privadas where para = auth.uid() and not lida),
    'pedidos',   (select count(*) from amizades where para = auth.uid() and status = 'pendente'),
    'online',    (select count(*) from amizades a join perfis p on p.id = case when a.de = auth.uid() then a.para else a.de end
                   where auth.uid() in (a.de, a.para) and a.status = 'aceita' and p.visto_em > now() - interval '60 seconds'),
    'duelos',    coalesce((select json_agg(json_build_object('id', d.id, 'de', d.de, 'lado_de', d.lado_de,
                    'aposta_moedas', d.aposta_moedas, 'aposta_trofeus', d.aposta_trofeus, 'modo', d.modo,
                    'nome', split_part(p.nome, ' ', 1), 'avatar_url', p.avatar_url) order by d.criado_em desc)
                   from duelos d join perfis p on p.id = d.de
                  where d.para = auth.uid() and d.status = 'pendente' and d.sala_origem is null
                    and d.criado_em > now() - interval '90 seconds'), '[]'::json)
  ) into r;
  return r;
end $$;

revoke all on function public.convidar_duelo(uuid, text, integer, integer, text) from public, anon;
grant execute on function public.convidar_duelo(uuid, text, integer, integer, text) to authenticated;
notify pgrst, 'reload schema';
