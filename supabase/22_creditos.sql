-- =====================================================================
-- 22_creditos.sql — PAINEL: CONSUMO DO SUPABASE (plano grátis) NO MÊS
-- Rode DEPOIS do 20_ao_vivo.sql (usa a mesma chave do painel).
--
-- O banco não sabe o número EXATO de mensagens do Realtime e de tráfego (isso só o Supabase sabe,
-- em Settings > Usage). Aqui é uma ESTIMATIVA boa, feita com o que o jogo registra:
--   * Banco (MB) ............ exato
--   * Usuários ativos (MAU) . contas que entraram no mês (aproximado)
--   * Mensagens Realtime .... partidas online do mês x ~4.000 (Cerco online x 2)
--   * Tráfego (egress) ...... sinais "ao vivo" + registros + partidas (aproximado)
--   * Conexões ao mesmo tempo  pico de partidas online juntas x 2
-- =====================================================================

create or replace function public.painel_creditos(p_chave text) returns json
language plpgsql security definer set search_path = public as $$
declare
  tz text := 'America/Sao_Paulo';
  ini timestamptz := date_trunc('month', now() at time zone tz) at time zone tz;
  fim timestamptz := (date_trunc('month', now() at time zone tz) + interval '1 month') at time zone tz;
  msg_partida int := 4000;          -- mensagens Realtime numa partida online de ~3 min
  kb_ping numeric := 1.2;           -- cada sinal "ao vivo" (pedido + resposta)
  kb_evento numeric := 1.5;         -- cada registro
  kb_partida numeric := 600;        -- tráfego de uma partida online (Realtime + gravar o resultado)
  kb_jogador_dia numeric := 250;    -- abrir o jogo: perfil, personagens, ranking, social...
  mau int; segundos numeric; eventos_mes int; partidas int; cercos int; r json;
begin
  perform painel_checar(p_chave);
  begin
    select count(*) into mau from auth.users where coalesce(last_sign_in_at, created_at) >= ini;
  exception when others then mau := null;
  end;
  mau := greatest(coalesce(mau, 0), (select count(distinct jogador) from eventos where jogador is not null and criado_em >= ini));
  select coalesce(sum((dados->>'segundos')::numeric), 0) into segundos from eventos where tipo = 'sessao' and criado_em >= ini;
  select count(*) into eventos_mes from eventos where criado_em >= ini;
  select count(*) filter (where coalesce(modo, 'normal') <> 'cerco'), count(*) filter (where modo = 'cerco')
    into partidas, cercos from partidas_pvp where criada_em >= ini;

  with dias as (
    select d::date as dia from generate_series((ini at time zone tz)::date, (now() at time zone tz)::date, interval '1 day') d
  ), por_dia as (
    select x.dia,
      (select count(*) filter (where coalesce(modo,'normal') <> 'cerco') * msg_partida + count(*) filter (where modo = 'cerco') * msg_partida * 2
         from partidas_pvp where (criada_em at time zone tz)::date = x.dia) as msgs,
      (select count(*) from partidas_pvp where (criada_em at time zone tz)::date = x.dia) as partidas,
      round((
        coalesce((select sum((dados->>'segundos')::numeric) from eventos where tipo = 'sessao' and (criado_em at time zone tz)::date = x.dia), 0) / 30 * kb_ping
        + (select count(*) from eventos where (criado_em at time zone tz)::date = x.dia) * kb_evento
        + (select count(*) from partidas_pvp where (criada_em at time zone tz)::date = x.dia) * kb_partida
        + (select count(distinct coalesce(jogador::text, aparelho)) from eventos where (criado_em at time zone tz)::date = x.dia) * kb_jogador_dia
      ) / 1024, 1) as egress_mb
    from dias x
  )
  select json_build_object(
    'agora', now(), 'inicio_mes', ini, 'fim_mes', fim,
    'dias_passados', greatest(1, extract(epoch from now() - ini) / 86400),
    'dias_mes', extract(epoch from fim - ini) / 86400,
    'banco_mb', round(pg_database_size(current_database()) / 1048576.0, 1),
    'mau', mau,
    'partidas_online', partidas, 'cercos_online', cercos,
    'msgs', partidas * msg_partida + cercos * msg_partida * 2,
    'egress_mb', (select coalesce(sum(egress_mb), 0) from por_dia),
    'pico_conexoes', coalesce((select max(n) * 2 from (
        select count(*) n from partidas_pvp where criada_em >= ini
        group by date_trunc('hour', criada_em), floor(extract(minute from criada_em) / 5)) z), 0),
    'por_dia', (select json_agg(por_dia order by dia) from por_dia),
    'banco_partes', (select json_agg(x order by x.mb desc) from (
        select relname as tabela, round(pg_total_relation_size(c.oid) / 1048576.0, 2) as mb
          from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind = 'r'
         order by pg_total_relation_size(c.oid) desc limit 8) x)
  ) into r;
  return r;
end $$;
revoke all on function public.painel_creditos(text) from public;
grant execute on function public.painel_creditos(text) to anon, authenticated;
notify pgrst, 'reload schema';
