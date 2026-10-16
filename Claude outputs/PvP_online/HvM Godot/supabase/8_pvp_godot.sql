-- =====================================================================
-- Heroes vs Monsters — PvP ONLINE do jogo em GODOT
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run.
-- Rode DEPOIS do 4_pvp.sql e do 5_pvp_resultado.sql (e do 6_login_godot.sql). Pode rodar de novo sem problema.
--
-- O que muda:
-- 1) Fila separada por PLATAFORMA: quem joga no Godot só encontra quem joga no Godot
--    (o site e o Godot simulam a partida de jeitos diferentes; misturar daria partidas diferentes nos dois aparelhos).
--    O site continua igual (procurar_partida agora só junta "web" com "web").
-- 2) procurar_partida_godot: o NÍVEL dos personagens vem do servidor (não do aparelho) = sem trapaça.
-- 3) sair_da_fila_godot: sai da fila, mas se alguém tinha acabado de te achar, devolve a sala
--    (assim ninguém fica esperando sozinho).
-- O resultado continua no finalizar_pvp (vitória +30 troféus +50 moedas; derrota −20 troféus +15 moedas).
-- =====================================================================

alter table public.fila_pvp     add column if not exists plataforma text not null default 'web';
alter table public.partidas_pvp add column if not exists plataforma text not null default 'web';

-- procura (uso interno): igual ao 4_pvp.sql, mas só junta jogadores da MESMA plataforma
create or replace function public.procurar_partida_plat(p_lado text, p_niveis jsonb, p_plat text) returns json
language plpgsql security definer set search_path = public as $$
declare outro public.fila_pvp; s public.partidas_pvp;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_lado not in ('heroes','monsters') then raise exception 'lado inválido'; end if;
  -- alguém já me achou?
  select * into s from partidas_pvp
   where auth.uid() in (heroes, monsters) and not finalizada and plataforma = p_plat
     and criada_em > now() - interval '40 seconds'
   order by criada_em desc limit 1;
  if s.id is not null then delete from fila_pvp where jogador = auth.uid(); return sala_json(s); end if;
  delete from fila_pvp where criado_em < now() - interval '20 seconds';
  select * into outro from fila_pvp
   where lado <> p_lado and plataforma = p_plat and jogador <> auth.uid()
   order by criado_em limit 1 for update skip locked;
  if outro.jogador is not null then
    delete from fila_pvp where jogador in (outro.jogador, auth.uid());
    insert into partidas_pvp (heroes, monsters, semente, niveis_heroes, niveis_monsters, plataforma)
    values (case when p_lado = 'heroes' then auth.uid() else outro.jogador end,
            case when p_lado = 'monsters' then auth.uid() else outro.jogador end,
            floor(random() * 4294967295)::bigint,
            case when p_lado = 'heroes' then coalesce(p_niveis, '{}') else outro.niveis end,
            case when p_lado = 'monsters' then coalesce(p_niveis, '{}') else outro.niveis end,
            p_plat)
    returning * into s;
    return sala_json(s);
  end if;
  insert into fila_pvp (jogador, lado, niveis, plataforma) values (auth.uid(), p_lado, coalesce(p_niveis, '{}'), p_plat)
  on conflict (jogador) do update set lado = excluded.lado, niveis = excluded.niveis,
                                      plataforma = excluded.plataforma, criado_em = now();
  return null;
end $$;
revoke all on function public.procurar_partida_plat(text, jsonb, text) from public, anon, authenticated;

-- SITE (igual a antes, mas só com quem joga no site)
create or replace function public.procurar_partida(p_lado text, p_niveis jsonb default '{}') returns json
language sql security definer set search_path = public as $$
  select public.procurar_partida_plat(p_lado, p_niveis, 'web');
$$;

-- GODOT: os níveis vêm da tabela personagens_jogador (o aparelho não manda nada)
create or replace function public.procurar_partida_godot(p_lado text) returns json
language sql security definer set search_path = public as $$
  select public.procurar_partida_plat(p_lado,
    coalesce((select jsonb_object_agg(personagem, nivel) from personagens_jogador where jogador = auth.uid()), '{}'::jsonb),
    'godot');
$$;

-- GODOT: sai da fila. Se alguém já tinha criado a sala com você, devolve a sala (o jogo entra nela).
create or replace function public.sair_da_fila_godot() returns json
language plpgsql security definer set search_path = public as $$
declare s public.partidas_pvp;
begin
  if auth.uid() is null then return null; end if;
  delete from fila_pvp where jogador = auth.uid();
  select * into s from partidas_pvp
   where auth.uid() in (heroes, monsters) and not finalizada and plataforma = 'godot'
     and criada_em > now() - interval '40 seconds'
   order by criada_em desc limit 1;
  if s.id is not null then return sala_json(s); end if;
  return null;
end $$;

revoke all on function public.procurar_partida(text, jsonb), public.procurar_partida_godot(text), public.sair_da_fila_godot() from public, anon;
grant execute on function public.procurar_partida(text, jsonb), public.procurar_partida_godot(text), public.sair_da_fila_godot() to authenticated;
notify pgrst, 'reload schema';
