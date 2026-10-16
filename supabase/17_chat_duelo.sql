-- =====================================================================
-- 17_chat_duelo.sql — DUELO PELO CHAT GERAL + LADO (Heroes/Monsters) DE CADA JOGADOR
-- Rode DEPOIS do 14_social_godot.sql (e do 15/16).
--
--   * definir_lado: o jogo avisa o servidor quando a pessoa troca de lado (aparece o selo certo para todo mundo)
--   * chat_geral: mensagens do chat com o lado, os troféus e se a pessoa está online
--   * buscar_jogadores: agora também devolve o lado e se está online
--   * convidar_duelo: dá para chamar QUALQUER pessoa (não só amigos), se ela estiver online
-- =====================================================================

create or replace function public.definir_lado(p_lado text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or p_lado not in ('heroes', 'monsters') then return; end if;
  update perfis set lado_atual = p_lado where id = auth.uid() and lado_atual is distinct from p_lado;
end $$;

create or replace function public.chat_geral()
returns table (id bigint, autor uuid, nome text, lado text, texto text, trofeus integer, online boolean, criado_em timestamptz)
language sql stable security definer set search_path = public as $$
  select * from (
    select m.id, m.autor, m.nome, coalesce(p.lado_atual, m.lado), m.texto, coalesce(p.trofeus, 0),
           coalesce(p.visto_em > now() - interval '90 seconds', false), m.criado_em
      from mensagens m left join perfis p on p.id = m.autor
     where auth.uid() is not null
     order by m.id desc
     limit 40) x
  order by x.id;
$$;

drop function if exists public.buscar_jogadores(text);
create or replace function public.buscar_jogadores(p_texto text)
returns table (id uuid, nome text, avatar_url text, trofeus integer, situacao text, lado_atual text, online boolean)
language sql stable security definer set search_path = public as $$
  select pe.id, split_part(pe.nome, ' ', 1) || coalesce(' ' || nullif(left(split_part(pe.nome, ' ', 2), 1), '') || '.', ''),
         pe.avatar_url, pe.trofeus,
         coalesce((select a.status from amizades a where (a.de = auth.uid() and a.para = pe.id) or (a.de = pe.id and a.para = auth.uid()) limit 1), ''),
         pe.lado_atual, coalesce(pe.visto_em > now() - interval '90 seconds', false)
    from perfis pe
   where auth.uid() is not null and pe.id <> auth.uid() and char_length(trim(p_texto)) >= 2
     and pe.nome ilike trim(p_texto) || '%'
   order by pe.trofeus desc
   limit 12;
$$;

create or replace function public.convidar_duelo(p_para uuid, p_lado text, p_moedas integer default 0, p_trofeus integer default 0) returns uuid
language plpgsql security definer set search_path = public as $$
declare novo uuid; eu public.perfis; ele public.perfis;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_lado not in ('heroes','monsters') then raise exception 'lado inválido'; end if;
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
  -- (anti-chatice) no máximo 3 convites pendentes para a mesma pessoa
  if (select count(*) from duelos where para = p_para and status = 'pendente' and criado_em > now() - interval '2 minutes') >= 3 then
    raise exception '% já tem convites demais agora. Tente daqui a pouco.', split_part(ele.nome, ' ', 1);
  end if;
  update duelos set status = 'cancelado' where de = auth.uid() and status = 'pendente';    -- um convite por vez
  delete from duelos where criado_em < now() - interval '1 day';
  update perfis set lado_atual = p_lado where id = auth.uid();
  insert into duelos (de, para, lado_de, aposta_moedas, aposta_trofeus)
  values (auth.uid(), p_para, p_lado, coalesce(p_moedas, 0), coalesce(p_trofeus, 0)) returning id into novo;
  return novo;
end $$;

revoke all on function public.definir_lado(text), public.chat_geral(), public.buscar_jogadores(text),
  public.convidar_duelo(uuid, text, integer, integer) from public, anon;
grant execute on function public.definir_lado(text), public.chat_geral(), public.buscar_jogadores(text),
  public.convidar_duelo(uuid, text, integer, integer) to authenticated;
notify pgrst, 'reload schema';
