-- =====================================================================
-- Heroes vs Monsters — SOCIAL: conversa com amigo, duelo PvP entre amigos e o contador de avisos
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Rode DEPOIS do 3_social.sql e do 8_pvp_godot.sql.
-- Pode rodar de novo sem problema.
--
-- ECONOMIA (para caber no plano grátis): nada aqui usa o "Realtime" (que tem limite de mensagens por mês).
-- O jogo pergunta ao servidor só de vez em quando (a cada 20 s no menu; a cada 3 s com a conversa aberta),
-- e as mensagens velhas são apagadas sozinhas (conversas: 30 dias; chat geral: 7 dias).
-- =====================================================================

alter table public.perfis add column if not exists visto_em timestamptz;          -- último sinal de vida (online = últimos 60 s)
alter table public.partidas_pvp add column if not exists amistoso boolean not null default false;   -- duelo entre amigos
-- APOSTA do duelo: quem vencer leva do outro (0 = sem aposta). Só estes valores são aceitos:
--   moedas: 0, 25, 50, 100, 200, 500 · troféus: 0, 10, 20, 30, 50
alter table public.partidas_pvp add column if not exists aposta_moedas integer not null default 0;
alter table public.partidas_pvp add column if not exists aposta_trofeus integer not null default 0;

-- ---------- CONVERSA PARTICULAR (só entre amigos) ----------
create table if not exists public.mensagens_privadas (
  id bigint generated always as identity primary key,
  de uuid not null references public.perfis(id) on delete cascade,
  para uuid not null references public.perfis(id) on delete cascade,
  texto text not null check (char_length(texto) between 1 and 200),
  lida boolean not null default false,
  criado_em timestamptz not null default now()
);
create index if not exists privadas_para_lida on public.mensagens_privadas (para, lida);
create index if not exists privadas_par on public.mensagens_privadas (least(de, para), greatest(de, para), id desc);
alter table public.mensagens_privadas enable row level security;     -- só pelas funções

create or replace function public.sao_amigos(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from amizades where status = 'aceita' and ((de = a and para = b) or (de = b and para = a)));
$$;

create or replace function public.enviar_privada(p_para uuid, p_texto text) returns bigint
language plpgsql security definer set search_path = public as $$
declare t text := trim(p_texto); ultima timestamptz; novo bigint;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if not sao_amigos(auth.uid(), p_para) then raise exception 'só dá para conversar com amigos'; end if;
  if char_length(t) < 1 or char_length(t) > 200 then raise exception 'mensagem de 1 a 200 letras'; end if;
  select max(criado_em) into ultima from mensagens_privadas where de = auth.uid();
  if ultima > now() - interval '1 second' then raise exception 'calma! espere um pouquinho'; end if;
  insert into mensagens_privadas (de, para, texto) values (auth.uid(), p_para, t) returning id into novo;
  if random() < 0.02 then                                              -- faxina de vez em quando
    delete from mensagens_privadas where criado_em < now() - interval '30 days';
    delete from mensagens where criado_em < now() - interval '7 days';
  end if;
  return novo;
end $$;

-- as últimas 50 mensagens com um amigo (e marca como lidas as que vieram dele)
create or replace function public.conversa(p_outro uuid)
returns table (id bigint, minha boolean, texto text, criado_em timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  update mensagens_privadas set lida = true where de = p_outro and para = auth.uid() and not lida;
  return query
    select m.id, m.de = auth.uid(), m.texto, m.criado_em from (
      select * from mensagens_privadas
       where least(de, para) = least(auth.uid(), p_outro) and greatest(de, para) = greatest(auth.uid(), p_outro)
       order by id desc limit 50) m
     order by m.id;
end $$;

-- amigos com "online" e quantas mensagens não lidas de cada um
create or replace function public.meus_amigos_godot()
returns table (id uuid, nome text, avatar_url text, trofeus integer, lado_atual text, status text, pedido_meu boolean,
               online boolean, nao_lidas integer)
language sql stable security definer set search_path = public as $$
  select pe.id, split_part(pe.nome, ' ', 1) || coalesce(' ' || nullif(left(split_part(pe.nome, ' ', 2), 1), '') || '.', ''),
         pe.avatar_url, pe.trofeus, pe.lado_atual, a.status, (a.de = auth.uid()),
         coalesce(pe.visto_em > now() - interval '60 seconds', false),
         (select count(*)::integer from mensagens_privadas m where m.de = pe.id and m.para = auth.uid() and not m.lida)
    from amizades a join perfis pe on pe.id = case when a.de = auth.uid() then a.para else a.de end
   where auth.uid() in (a.de, a.para)
   order by a.status, coalesce(pe.visto_em > now() - interval '60 seconds', false) desc, pe.nome;
$$;

-- ---------- DUELO (amigo convida, o outro aceita: PvP online; pode ter APOSTA de moedas e/ou troféus) ----------
create table if not exists public.duelos (
  id uuid primary key default gen_random_uuid(),
  de uuid not null references public.perfis(id) on delete cascade,
  para uuid not null references public.perfis(id) on delete cascade,
  lado_de text not null check (lado_de in ('heroes','monsters')),
  status text not null default 'pendente' check (status in ('pendente','aceito','recusado','cancelado')),
  sala uuid,
  criado_em timestamptz not null default now()
);
alter table public.duelos add column if not exists aposta_moedas integer not null default 0;
alter table public.duelos add column if not exists aposta_trofeus integer not null default 0;
alter table public.duelos add column if not exists sala_origem uuid;                   -- REVANCHE: a partida de onde veio (15_fim_partida.sql)
alter table public.duelos add column if not exists ranqueada boolean not null default false;   -- revanche de PvP normal: vale troféus
create index if not exists duelos_para on public.duelos (para, status);
alter table public.duelos enable row level security;

drop function if exists public.convidar_duelo(uuid, text);
create or replace function public.convidar_duelo(p_para uuid, p_lado text, p_moedas integer default 0, p_trofeus integer default 0) returns uuid
language plpgsql security definer set search_path = public as $$
declare novo uuid; eu public.perfis;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_lado not in ('heroes','monsters') then raise exception 'lado inválido'; end if;
  if not sao_amigos(auth.uid(), p_para) then raise exception 'só dá para chamar amigos para duelo'; end if;
  if coalesce(p_moedas, 0) not in (0, 25, 50, 100, 200, 500) or coalesce(p_trofeus, 0) not in (0, 10, 20, 30, 50) then
    raise exception 'aposta inválida';
  end if;
  select * into eu from perfis where id = auth.uid();
  if eu.moedas < coalesce(p_moedas, 0) then raise exception 'você não tem moedas suficientes para essa aposta'; end if;
  if eu.trofeus < coalesce(p_trofeus, 0) then raise exception 'você não tem troféus suficientes para essa aposta'; end if;
  update duelos set status = 'cancelado' where de = auth.uid() and status = 'pendente';    -- um convite por vez
  delete from duelos where criado_em < now() - interval '1 day';
  insert into duelos (de, para, lado_de, aposta_moedas, aposta_trofeus)
  values (auth.uid(), p_para, p_lado, coalesce(p_moedas, 0), coalesce(p_trofeus, 0)) returning id into novo;
  return novo;
end $$;

-- quem foi convidado responde. Aceitou = cria a sala do PvP online (o outro lado da escolha de quem convidou)
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
  -- os DOIS precisam ter o que foi apostado (confere na hora de aceitar)
  if (select moedas from perfis where id = d.para) < d.aposta_moedas then raise exception 'você não tem moedas suficientes para essa aposta'; end if;
  if (select trofeus from perfis where id = d.para) < d.aposta_trofeus then raise exception 'você não tem troféus suficientes para essa aposta'; end if;
  if (select moedas from perfis where id = d.de) < d.aposta_moedas or (select trofeus from perfis where id = d.de) < d.aposta_trofeus then
    update duelos set status = 'cancelado' where id = d.id;
    raise exception 'seu amigo não tem mais o que apostou';
  end if;
  h := case when d.lado_de = 'heroes' then d.de else d.para end;
  m := case when d.lado_de = 'heroes' then d.para else d.de end;
  insert into partidas_pvp (heroes, monsters, semente, niveis_heroes, niveis_monsters, plataforma, amistoso, aposta_moedas, aposta_trofeus)
  values (h, m, floor(random() * 4294967295)::bigint,
          coalesce((select jsonb_object_agg(personagem, nivel) from personagens_jogador where jogador = h), '{}'::jsonb),
          coalesce((select jsonb_object_agg(personagem, nivel) from personagens_jogador where jogador = m), '{}'::jsonb),
          'godot', not d.ranqueada, d.aposta_moedas, d.aposta_trofeus)
  returning * into s;
  update duelos set status = 'aceito', sala = s.id where id = d.id;
  return sala_json(s);
end $$;

-- quem convidou fica perguntando: {status, sala}
create or replace function public.ver_duelo(p_id uuid) returns json
language plpgsql security definer set search_path = public as $$
declare d public.duelos; s public.partidas_pvp;
begin
  select * into d from duelos where id = p_id and auth.uid() in (de, para);
  if d.id is null then return null; end if;
  if d.status = 'pendente' and d.criado_em < now() - interval '90 seconds' then
    update duelos set status = 'cancelado' where id = d.id;
    d.status := 'cancelado';
  end if;
  if d.sala is not null then select * into s from partidas_pvp where id = d.sala; end if;
  return json_build_object('status', d.status, 'sala', case when s.id is not null then sala_json(s) end);
end $$;

create or replace function public.cancelar_duelo(p_id uuid) returns void
language sql security definer set search_path = public as $$
  update duelos set status = 'cancelado' where id = p_id and de = auth.uid() and status = 'pendente';
$$;

-- ---------- RESUMO (o número no botão de amigos) — também marca você como "online" ----------
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
                    'aposta_moedas', d.aposta_moedas, 'aposta_trofeus', d.aposta_trofeus,
                    'nome', split_part(p.nome, ' ', 1), 'avatar_url', p.avatar_url) order by d.criado_em desc)
                   from duelos d join perfis p on p.id = d.de
                  where d.para = auth.uid() and d.status = 'pendente' and d.sala_origem is null
                    and d.criado_em > now() - interval '90 seconds'), '[]'::json)
  ) into r;
  return r;
end $$;

-- ---------- PROCURAR JOGADOR pelo nome (para adicionar amigo) ----------
create or replace function public.buscar_jogadores(p_texto text)
returns table (id uuid, nome text, avatar_url text, trofeus integer, situacao text)
language sql stable security definer set search_path = public as $$
  select pe.id, split_part(pe.nome, ' ', 1) || coalesce(' ' || nullif(left(split_part(pe.nome, ' ', 2), 1), '') || '.', ''),
         pe.avatar_url, pe.trofeus,
         coalesce((select a.status from amizades a where (a.de = auth.uid() and a.para = pe.id) or (a.de = pe.id and a.para = auth.uid()) limit 1), '')
    from perfis pe
   where auth.uid() is not null and pe.id <> auth.uid() and char_length(trim(p_texto)) >= 2
     and pe.nome ilike trim(p_texto) || '%'
   order by pe.trofeus desc
   limit 12;
$$;

-- APOSTA: quem perdeu passa para quem venceu (nunca fica negativo: passa só o que tiver). Empate = ninguém paga.
create or replace function public.pagar_aposta_duelo(p_venceu uuid, p_perdeu uuid, p_moedas integer, p_trofeus integer) returns void
language plpgsql security definer set search_path = public as $$
declare m integer; t integer;
begin
  select least(moedas, p_moedas), least(trofeus, p_trofeus) into m, t from perfis where id = p_perdeu for update;
  update perfis set moedas = moedas - m, trofeus = trofeus - t, atualizado_em = now() where id = p_perdeu;
  update perfis set moedas = moedas + m, trofeus = trofeus + t, atualizado_em = now() where id = p_venceu;
  if t > 0 then                                      -- entra no ranking de troféus do dia/semana/mês
    insert into partidas (jogador, modo, venceu, trofeus, moedas) values (p_venceu, 'duelo', true, t, m), (p_perdeu, 'duelo', false, -t, -m);
  end if;
end $$;
revoke all on function public.pagar_aposta_duelo(uuid, uuid, integer, integer) from public, anon, authenticated;

-- ---------- RESULTADO: duelo entre amigos só mexe no que foi APOSTADO ----------
create or replace function public.finalizar_pvp(p_sala uuid, p_vencedor text, p_resumo text) returns json
language plpgsql security definer set search_path = public as $$
declare s public.partidas_pvp; v text := coalesce(p_vencedor, 'empate'); eu text;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if v not in ('heroes','monsters','empate') then raise exception 'resultado inválido'; end if;
  select * into s from partidas_pvp where id = p_sala for update;
  if s.id is null then raise exception 'sala não encontrada'; end if;
  if auth.uid() = s.heroes then eu := 'heroes'; elsif auth.uid() = s.monsters then eu := 'monsters';
  else raise exception 'você não está nesta partida'; end if;

  if eu = 'heroes' then update partidas_pvp set rel_heroes = v, resumo_heroes = p_resumo where id = s.id;
  else update partidas_pvp set rel_monsters = v, resumo_monsters = p_resumo where id = s.id; end if;

  if not s.finalizada then
    if not s.amistoso then
      perform aplicar_resultado_pvp(s.heroes,   case v when 'heroes' then 'vitoria' when 'monsters' then 'derrota' else 'empate' end, 'heroes');
      perform aplicar_resultado_pvp(s.monsters, case v when 'monsters' then 'vitoria' when 'heroes' then 'derrota' else 'empate' end, 'monsters');
    elsif v <> 'empate' and (s.aposta_moedas > 0 or s.aposta_trofeus > 0) then
      perform pagar_aposta_duelo(case v when 'heroes' then s.heroes else s.monsters end,
                                 case v when 'heroes' then s.monsters else s.heroes end, s.aposta_moedas, s.aposta_trofeus);
    end if;
    update partidas_pvp set vencedor = v, finalizada = true where id = s.id;
  elsif s.vencedor is distinct from v and p_resumo <> 'wo' then
    update partidas_pvp set divergente = true where id = s.id;
  end if;
  select * into s from partidas_pvp where id = p_sala;
  return sala_json(s);
end $$;

-- a sala também diz se é duelo (o jogo mostra "Duelo amistoso" e não promete troféus)
create or replace function public.sala_json(s public.partidas_pvp) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('id', s.id, 'semente', s.semente, 'heroes', s.heroes, 'monsters', s.monsters,
    'niveis_heroes', s.niveis_heroes, 'niveis_monsters', s.niveis_monsters,
    'nome_heroes', (select split_part(nome, ' ', 1) from perfis where id = s.heroes),
    'nome_monsters', (select split_part(nome, ' ', 1) from perfis where id = s.monsters),
    'foto_heroes', (select avatar_url from perfis where id = s.heroes),
    'foto_monsters', (select avatar_url from perfis where id = s.monsters),
    'vencedor', s.vencedor, 'finalizada', s.finalizada, 'amistoso', s.amistoso,
    'aposta_moedas', s.aposta_moedas, 'aposta_trofeus', s.aposta_trofeus);
$$;

revoke all on function public.enviar_privada(uuid, text), public.conversa(uuid), public.meus_amigos_godot(),
  public.convidar_duelo(uuid, text, integer, integer), public.responder_duelo(uuid, boolean), public.ver_duelo(uuid),
  public.cancelar_duelo(uuid), public.social_resumo(), public.buscar_jogadores(text) from public, anon;
grant execute on function public.enviar_privada(uuid, text), public.conversa(uuid), public.meus_amigos_godot(),
  public.convidar_duelo(uuid, text, integer, integer), public.responder_duelo(uuid, boolean), public.ver_duelo(uuid),
  public.cancelar_duelo(uuid), public.social_resumo(), public.buscar_jogadores(text) to authenticated;
revoke all on function public.sao_amigos(uuid, uuid) from public, anon, authenticated;
notify pgrst, 'reload schema';
