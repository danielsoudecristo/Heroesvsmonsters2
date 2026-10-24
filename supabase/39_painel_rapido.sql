-- =====================================================================
-- 39_painel_rapido.sql — o PAINEL voltou a entrar ("canceling statement due to statement timeout")
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Pode rodar de novo.
--
-- Por quê: a função painel_dados (16_painel.sql) fazia, para CADA jogador, várias buscas na tabela inteira
-- de eventos. Com muitos jogadores e eventos passou do tempo que o Supabase deixa (poucos segundos) e o
-- painel não entrava. Esta versão faz as MESMAS contas de uma vez só (agrupando) — devolve os mesmos dados,
-- muitas vezes mais rápido. A chave do painel não muda.
-- =====================================================================

create index if not exists eventos_tipo_data on public.eventos (tipo, criado_em);

create or replace function public.painel_dados(p_chave text, p_dias integer default 30) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  dias int := least(greatest(coalesce(p_dias, 30), 1), 365);
  desde timestamptz := now() - make_interval(days => least(greatest(coalesce(p_dias, 30), 1), 365));
  tz text := 'America/Sao_Paulo';
  r json;
begin
  if encode(sha256(convert_to(coalesce(p_chave, ''), 'UTF8')), 'hex') is distinct from (select hash from painel_config where id = 1) then
    perform pg_sleep(1);
    raise exception 'chave errada';
  end if;

  with
  pvp as materialized (
    select id, criada_em, heroes, monsters, vencedor, finalizada, coalesce(amistoso, false) as amistoso, coalesce(divergente, false) as divergente
    from partidas_pvp
  ),
  pvp_j as (
    select heroes as jogador, 'heroes' as lado, (vencedor = 'heroes') as venceu, amistoso, finalizada from pvp
    union all
    select monsters, 'monsters', (vencedor = 'monsters'), amistoso, finalizada from pvp
  ),
  pvp_a as (     -- partidas online de cada jogador (uma passada só)
    select jogador,
      count(*) filter (where finalizada and not amistoso) as pvp_online,
      count(*) filter (where finalizada and not amistoso and venceu) as pvp_online_v,
      count(*) filter (where finalizada and amistoso) as duelos,
      count(*) filter (where lado = 'heroes') as on_heroes,
      count(*) filter (where lado = 'monsters') as on_monsters
    from pvp_j where jogador is not null group by jogador
  ),
  ev as materialized (select * from eventos),
  conv as (
    select e.aparelho from ev e where e.aparelho is not null
    group by e.aparelho having bool_and(e.jogador is null)
  ),
  ev_q as materialized (
    select coalesce(e.jogador::text, 'ap:' || e.aparelho) as chave, e.* from ev e
  ),
  ev_a as (      -- eventos de cada "quem" (uma passada só)
    select chave,
      min(criado_em) as primeiro,
      max(criado_em) as ultimo,
      count(*) filter (where tipo = 'abriu') as acessos,
      coalesce(sum((dados->>'segundos')::numeric) filter (where tipo = 'sessao'), 0)::bigint as segundos,
      count(*) filter (where tipo = 'pvp_bot') as pvp_bot,
      count(*) filter (where tipo = 'pvp_bot' and (dados->>'venceu')::boolean) as pvp_bot_v,
      max((dados->>'bot_nivel')::int) filter (where tipo = 'pvp_bot') as bot_nivel_max,
      count(*) filter (where tipo = 'campanha' and (dados->>'venceu')::boolean) as camp_niveis,
      count(*) filter (where tipo = 'campanha' and not (dados->>'venceu')::boolean) as camp_derrotas,
      count(*) filter (where tipo = 'pvp_bot' and dados->>'lado' = 'heroes') as bot_heroes,
      count(*) filter (where tipo = 'pvp_bot' and dados->>'lado' = 'monsters') as bot_monsters
    from ev_q group by chave
  ),
  camp_a as (
    select chave, json_object_agg(dif, mx) as camp_max from (
      select chave, dados->>'dif' as dif, max((dados->>'nivel')::int) as mx from ev_q where tipo = 'campanha' group by 1, 2) x
    group by chave
  ),
  plat_a as (select distinct on (chave) chave, dados->>'plataforma' as plataforma from ev_q where tipo = 'abriu' order by chave, criado_em desc),
  vers_a as (select distinct on (chave) chave, versao from ev_q where versao is not null order by chave, criado_em desc),
  tut_a as (
    select distinct on (chave) chave, dados->>'evento' as tutorial from ev_q
    where tipo = 'tutorial' and dados->>'parte' = 'jogo' and dados->>'evento' in ('terminou', 'pulou')
    order by chave, criado_em desc
  ),
  rec_a as (select jogador, json_object_agg(dificuldade, nivel) as recordes from recordes_campanha group by jogador),
  pers_a as (select jogador, json_object_agg(personagem, nivel) as personagens from personagens_jogador where nivel > 1 group by jogador),
  quem as (
    select p.id::text as chave, p.id as jogador, p.nome, p.avatar_url, p.trofeus, p.moedas,
           p.vitorias, p.derrotas, p.lado_atual, p.criado_em, p.visto_em
    from perfis p
    union all
    select 'ap:' || c.aparelho, null, 'Convidado ' || upper(left(c.aparelho, 4)), null, null, null, null, null, null,
           (select ea.primeiro from ev_a ea where ea.chave = 'ap:' || c.aparelho), null
    from conv c
  ),
  jog as (
    select q.chave, q.jogador, q.nome, q.avatar_url, q.trofeus, q.moedas, q.vitorias, q.derrotas, q.lado_atual, q.criado_em,
      greatest(q.visto_em, ea.ultimo) as ultimo,
      coalesce(ea.acessos, 0) as acessos,
      coalesce(ea.segundos, 0) as segundos,
      coalesce(pa.pvp_online, 0) as pvp_online,
      coalesce(pa.pvp_online_v, 0) as pvp_online_v,
      coalesce(pa.duelos, 0) as duelos,
      coalesce(ea.pvp_bot, 0) as pvp_bot,
      coalesce(ea.pvp_bot_v, 0) as pvp_bot_v,
      ea.bot_nivel_max,
      coalesce(ea.camp_niveis, 0) as camp_niveis,
      coalesce(ea.camp_derrotas, 0) as camp_derrotas,
      coalesce(ra.recordes, '{}'::json) as recordes,
      coalesce(ca.camp_max, '{}'::json) as camp_max,
      coalesce(pe.personagens, '{}'::json) as personagens,
      coalesce(pa.on_heroes, 0) + coalesce(ea.bot_heroes, 0) as jogou_heroes,
      coalesce(pa.on_monsters, 0) + coalesce(ea.bot_monsters, 0) as jogou_monsters,
      pl.plataforma,
      ve.versao,
      tu.tutorial
    from quem q
    left join ev_a ea on ea.chave = q.chave
    left join pvp_a pa on pa.jogador = q.jogador
    left join camp_a ca on ca.chave = q.chave
    left join plat_a pl on pl.chave = q.chave
    left join vers_a ve on ve.chave = q.chave
    left join tut_a tu on tu.chave = q.chave
    left join rec_a ra on ra.jogador = q.jogador
    left join pers_a pe on pe.jogador = q.jogador
  ),
  dias_s as (select generate_series((now() at time zone tz)::date - (dias - 1), (now() at time zone tz)::date, interval '1 day')::date as dia),
  ev_dia as (
    select (criado_em at time zone tz)::date as dia,
      count(*) filter (where tipo = 'abriu') as acessos,
      count(distinct coalesce(jogador::text, aparelho)) as ativos,
      count(*) filter (where tipo = 'pvp_bot') as pvp_bot,
      count(*) filter (where tipo = 'campanha' and (dados->>'venceu')::boolean) as camp_niveis,
      count(*) filter (where tipo = 'campanha' and not (dados->>'venceu')::boolean) as camp_derrotas,
      coalesce(sum((dados->>'segundos')::numeric) filter (where tipo = 'sessao'), 0)::bigint as segundos
    from ev where criado_em >= now() - make_interval(days => dias + 2) group by 1
  ),
  pvp_dia as (
    select (criada_em at time zone tz)::date as dia,
      count(*) filter (where finalizada and not amistoso) as pvp_online,
      count(*) filter (where finalizada and amistoso) as duelos
    from pvp where criada_em >= now() - make_interval(days => dias + 2) group by 1
  ),
  novos_dia as (
    select (criado_em at time zone tz)::date as dia, count(*) as novos
    from perfis where criado_em >= now() - make_interval(days => dias + 2) group by 1
  ),
  por_dia as (
    select d.dia,
      coalesce(e.acessos, 0) as acessos,
      coalesce(e.ativos, 0) as ativos,
      coalesce(n.novos, 0) as novos,
      coalesce(v.pvp_online, 0) as pvp_online,
      coalesce(v.duelos, 0) as duelos,
      coalesce(e.pvp_bot, 0) as pvp_bot,
      coalesce(e.camp_niveis, 0) as camp_niveis,
      coalesce(e.camp_derrotas, 0) as camp_derrotas,
      coalesce(e.segundos, 0) as segundos
    from dias_s d
    left join ev_dia e on e.dia = d.dia
    left join pvp_dia v on v.dia = d.dia
    left join novos_dia n on n.dia = d.dia
  )
  select json_build_object(
    'agora', now(),
    'dias', dias,
    'resumo', json_build_object(
      'contas', (select count(*) from perfis),
      'convidados', (select count(*) from conv),
      'novas_7d', (select count(*) from perfis where criado_em > now() - interval '7 days'),
      'ativos_hoje', (select count(*) from jog where ultimo > now() - interval '1 day'),
      'ativos_7d', (select count(*) from jog where ultimo > now() - interval '7 days'),
      'ativos_30d', (select count(*) from jog where ultimo > now() - interval '30 days'),
      'acessos', (select count(*) from ev where tipo = 'abriu' and criado_em > desde),
      'segundos', (select coalesce(sum((dados->>'segundos')::numeric), 0) from ev where tipo = 'sessao' and criado_em > desde)::bigint,
      'sessoes', (select count(*) from ev where tipo = 'sessao' and criado_em > desde),
      'pvp_online', (select count(*) from pvp where finalizada and not amistoso and criada_em > desde),
      'pvp_divergentes', (select count(*) from pvp where divergente and criada_em > desde),
      'pvp_abandonadas', (select count(*) from pvp where not finalizada and criada_em > desde and criada_em < now() - interval '1 hour'),
      'duelos', (select count(*) from pvp where finalizada and amistoso and criada_em > desde),
      'pvp_bot', (select count(*) from ev where tipo = 'pvp_bot' and criado_em > desde),
      'camp_niveis', (select count(*) from ev where tipo = 'campanha' and (dados->>'venceu')::boolean and criado_em > desde),
      'camp_derrotas', (select count(*) from ev where tipo = 'campanha' and not (dados->>'venceu')::boolean and criado_em > desde)
    ),
    'por_dia', (select json_agg(por_dia order by dia) from por_dia),
    'por_hora', (select json_agg(json_build_object('hora', g.h, 'acessos', coalesce(x.n, 0)) order by g.h)
        from generate_series(0, 23) g(h)
        left join (select extract(hour from criado_em at time zone tz)::int as h, count(*) as n
                   from ev where tipo = 'abriu' and criado_em > desde group by 1) x on x.h = g.h),
    'ligas', (select json_object_agg(l, n) from (select liga_de(coalesce(trofeus, 0)) l, count(*) n from perfis group by 1) x),
    'lados', json_build_object(
      'online_heroes_v', (select count(*) from pvp where finalizada and not amistoso and vencedor = 'heroes' and criada_em > desde),
      'online_monsters_v', (select count(*) from pvp where finalizada and not amistoso and vencedor = 'monsters' and criada_em > desde),
      'online_empates', (select count(*) from pvp where finalizada and not amistoso and vencedor = 'empate' and criada_em > desde),
      'bot_heroes', (select count(*) from ev where tipo = 'pvp_bot' and dados->>'lado' = 'heroes' and criado_em > desde),
      'bot_heroes_v', (select count(*) from ev where tipo = 'pvp_bot' and dados->>'lado' = 'heroes' and (dados->>'venceu')::boolean and criado_em > desde),
      'bot_monsters', (select count(*) from ev where tipo = 'pvp_bot' and dados->>'lado' = 'monsters' and criado_em > desde),
      'bot_monsters_v', (select count(*) from ev where tipo = 'pvp_bot' and dados->>'lado' = 'monsters' and (dados->>'venceu')::boolean and criado_em > desde),
      'perfil_heroes', (select count(*) from perfis where lado_atual = 'heroes'),
      'perfil_monsters', (select count(*) from perfis where lado_atual = 'monsters')
    ),
    'tutorial', (select coalesce(json_object_agg(parte, json_build_object('comecou', c, 'terminou', t, 'pulou', p)), '{}'::json) from (
        select dados->>'parte' as parte,
          count(distinct coalesce(jogador::text, aparelho)) filter (where dados->>'evento' = 'comecou') as c,
          count(distinct coalesce(jogador::text, aparelho)) filter (where dados->>'evento' = 'terminou') as t,
          count(distinct coalesce(jogador::text, aparelho)) filter (where dados->>'evento' = 'pulou') as p
        from ev where tipo = 'tutorial' and criado_em > desde group by 1) x),
    'tutorial_pulos', (select json_agg(x order by n desc) from (
        select dados->>'parte' as parte, dados->>'passo' as passo, count(*) as n
        from ev where tipo = 'tutorial' and dados->>'evento' = 'pulou' and criado_em > desde group by 1, 2) x),
    'bot_niveis', (select json_agg(x order by nv) from (
        select (dados->>'bot_nivel')::int nv, count(*) jogos, count(*) filter (where (dados->>'venceu')::boolean) vitorias
        from ev where tipo = 'pvp_bot' and criado_em > desde group by 1) x),
    'campanha', (select json_agg(x order by ordem) from (
        select dados->>'dif' as dif,
          case dados->>'dif' when 'facil' then 1 when 'medio' then 2 when 'dificil' then 3 when 'hardcore' then 4 else 5 end as ordem,
          count(*) filter (where (dados->>'venceu')::boolean) as niveis,
          count(*) filter (where not (dados->>'venceu')::boolean) as derrotas,
          count(distinct coalesce(jogador::text, aparelho)) as jogadores,
          round(avg((dados->>'nivel')::int) filter (where not (dados->>'venceu')::boolean), 1) as nivel_medio_derrota,
          max((dados->>'nivel')::int) as nivel_max
        from ev where tipo = 'campanha' and criado_em > desde group by 1) x),
    'camp_onde_perdem', (select json_agg(x order by derrotas desc, nivel) from (
        select (dados->>'nivel')::int nivel, count(*) derrotas from ev
        where tipo = 'campanha' and not (dados->>'venceu')::boolean and criado_em > desde
        group by 1 order by 2 desc, 1 limit 12) x),
    'personagens', (select json_agg(x order by evolucoes desc) from (
        select personagem, count(*) as jogadores, round(avg(nivel), 1) as nivel_medio, max(nivel) as nivel_max, sum(nivel - 1) as evolucoes
        from personagens_jogador where nivel > 1 group by 1) x),
    'jogadores', (select json_agg(j order by ultimo desc nulls last) from jog j),
    'registro', (select json_agg(x order by criado_em desc) from (
        select * from (
          select e.criado_em, e.tipo, e.dados, coalesce(p.nome, 'Convidado ' || upper(left(e.aparelho, 4))) as nome
          from eventos e left join perfis p on p.id = e.jogador
          where e.tipo <> 'sessao'
          order by e.criado_em desc limit 400) a
        union all
        select * from (
          select v.criada_em, 'pvp_online', json_build_object('vencedor', v.vencedor, 'amistoso', v.amistoso, 'divergente', v.divergente,
                   'heroes', ph.nome, 'monsters', pm.nome, 'finalizada', v.finalizada)::jsonb,
                 coalesce(ph.nome, '?') || ' x ' || coalesce(pm.nome, '?')
          from pvp v left join perfis ph on ph.id = v.heroes left join perfis pm on pm.id = v.monsters
          order by v.criada_em desc limit 100) b
      ) x)
  ) into r;
  return r;
end $$;
revoke all on function public.painel_dados(text, integer) from public;
grant execute on function public.painel_dados(text, integer) to anon, authenticated;

notify pgrst, 'reload schema';
