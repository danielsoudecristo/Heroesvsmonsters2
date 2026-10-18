-- =====================================================================
-- 36_replays.sql — REPLAY das batalhas online (você e seus AMIGOS assistem) · apaga sozinho depois de 24 horas
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Pode rodar de novo.
--
-- NÃO É VÍDEO: o jogo guarda só a "receita" da partida (a semente + a lista de jogadas, uns 10–50 KB).
-- Para assistir, o próprio jogo roda a partida de novo, igualzinha (a partida online já funciona assim).
--   guardar_replay(sala, dados)  — no fim da partida online (o 1º dos dois aparelhos que mandar fica)
--   listar_replays()             — os replays das últimas 24 h: os SEUS e os dos seus AMIGOS
--   ver_replay(sala)             — a receita para assistir (só você, quem jogou ou amigo de quem jogou)
-- Passou de 24 horas: some da lista e é apagado (a faxina roda sozinha quando alguém guarda ou lista).
-- =====================================================================

create table if not exists public.replays (
  sala uuid primary key,
  heroes uuid not null,
  monsters uuid not null,
  modo text not null default 'normal',
  vencedor text,
  dados jsonb not null,
  criado_em timestamptz not null default now()
);
create index if not exists replays_heroes_idx on public.replays (heroes, criado_em);
create index if not exists replays_monsters_idx on public.replays (monsters, criado_em);
create index if not exists replays_criado_idx on public.replays (criado_em);
alter table public.replays enable row level security;          -- (só pelas funções abaixo)

create or replace function public._faxina_replays() returns void
language sql security definer set search_path = public as $$
  delete from replays where criado_em < now() - interval '24 hours';
$$;

create or replace function public.guardar_replay(p_sala uuid, p_dados jsonb) returns boolean
language plpgsql security definer set search_path = public as $$
declare s public.partidas_pvp;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_dados is null or length(p_dados::text) > 400000 then raise exception 'replay grande demais'; end if;
  select * into s from partidas_pvp where id = p_sala;
  if s.id is null or auth.uid() not in (s.heroes, s.monsters) then raise exception 'você não está nesta partida'; end if;
  perform _faxina_replays();
  insert into replays (sala, heroes, monsters, modo, vencedor, dados)
  values (s.id, s.heroes, s.monsters, coalesce(s.modo, 'normal'), coalesce(s.vencedor, p_dados ->> 'vencedor'), p_dados)
  on conflict (sala) do nothing;
  return true;
end $$;

-- pode ver? (é você, quem jogou, ou amigo de quem jogou) e ainda está dentro das 24 h
create or replace function public._pode_ver_replay(r public.replays) returns boolean
language sql stable security definer set search_path = public as $$
  select r.criado_em > now() - interval '24 hours'
     and (auth.uid() in (r.heroes, r.monsters) or sao_amigos(auth.uid(), r.heroes) or sao_amigos(auth.uid(), r.monsters));
$$;

create or replace function public.listar_replays() returns json
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  perform _faxina_replays();
  return coalesce((
    select json_agg(x order by x.criado_em desc) from (
      select r.sala, r.modo, r.vencedor, r.criado_em,
             extract(epoch from (r.criado_em + interval '24 hours' - now()))::int as some_em,
             auth.uid() in (r.heroes, r.monsters) as minha,
             case when auth.uid() = r.heroes then 'heroes' when auth.uid() = r.monsters then 'monsters'
                  when sao_amigos(auth.uid(), r.heroes) then 'heroes' else 'monsters' end as lado_ver,
             split_part(ph.nome, ' ', 1) as nome_heroes, ph.avatar_url as foto_heroes,
             split_part(pm.nome, ' ', 1) as nome_monsters, pm.avatar_url as foto_monsters
        from replays r
        join perfis ph on ph.id = r.heroes
        join perfis pm on pm.id = r.monsters
       where _pode_ver_replay(r)
       order by r.criado_em desc
       limit 50) x), '[]'::json);
end $$;

create or replace function public.ver_replay(p_sala uuid) returns json
language plpgsql stable security definer set search_path = public as $$
declare r public.replays;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  select * into r from replays where sala = p_sala;
  if r.sala is null or not _pode_ver_replay(r) then raise exception 'replay não encontrado (some depois de 24 horas)'; end if;
  return r.dados;
end $$;

revoke all on function public._faxina_replays(), public._pode_ver_replay(public.replays) from public, anon, authenticated;
revoke all on function public.guardar_replay(uuid, jsonb), public.listar_replays(), public.ver_replay(uuid) from public, anon;
grant execute on function public.guardar_replay(uuid, jsonb), public.listar_replays(), public.ver_replay(uuid) to authenticated;
notify pgrst, 'reload schema';
