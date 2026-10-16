-- =====================================================================
-- 16_painel.sql — PAINEL DO DONO (analisar os jogadores)
-- Rode DEPOIS dos arquivos 11 a 15.
--
-- O que este arquivo faz:
--   1) cria a tabela "eventos" (o jogo registra: abriu o jogo, tempo jogado,
--      cada nível da campanha, cada partida contra o bot);
--   2) registra sozinho: cadastro, mudança de liga e evolução de personagem;
--   3) cria a função "painel_dados" que o painel.html usa. Ela só responde
--      para quem tiver a CHAVE DO PAINEL (o banco guarda só o "hash" dela).
--
-- A CHAVE do painel está na linha marcada com  <<< CHAVE  (não mostre para ninguém).
-- =====================================================================

-- ---------------------------------------------------------------- tabela
create table if not exists public.eventos (
  id bigint generated always as identity primary key,
  jogador uuid references public.perfis(id) on delete set null,
  aparelho text,                       -- id aleatório do celular (para quem joga sem conta)
  tipo text not null,                  -- abriu, sessao, campanha, pvp_bot, tutorial, cadastro, liga, evoluiu
  dados jsonb not null default '{}',
  versao text,
  criado_em timestamptz not null default now()
);
create index if not exists eventos_data on public.eventos (criado_em desc);
create index if not exists eventos_jogador on public.eventos (jogador, criado_em desc);
create index if not exists eventos_tipo on public.eventos (tipo, criado_em desc);
create index if not exists eventos_aparelho on public.eventos (aparelho, criado_em desc);
alter table public.eventos enable row level security;      -- ninguém lê direto: só pelas funções

-- ------------------------------------------------- o jogo registra eventos
create or replace function public.registrar_evento(p_tipo text, p_dados jsonb default '{}',
  p_aparelho text default null, p_versao text default null) returns void
language plpgsql security definer set search_path = public as $$
declare eu uuid := (select id from perfis where id = auth.uid());
        ap text := left(coalesce(p_aparelho, ''), 64);
begin
  if p_tipo not in ('abriu', 'sessao', 'campanha', 'pvp_bot', 'tutorial') then return; end if;
  if pg_column_size(coalesce(p_dados, '{}'::jsonb)) > 2000 then return; end if;
  if eu is null and ap = '' then return; end if;
  -- limite: 400 eventos por dia por pessoa/aparelho (evita lixo)
  if (select count(*) from eventos
        where criado_em > now() - interval '1 day'
          and ((eu is not null and jogador = eu) or (ap <> '' and aparelho = ap))) >= 400 then
    return;
  end if;
  insert into eventos (jogador, aparelho, tipo, dados, versao)
  values (eu, nullif(ap, ''), p_tipo, coalesce(p_dados, '{}'::jsonb), left(p_versao, 20));
end $$;
revoke all on function public.registrar_evento(text, jsonb, text, text) from public;
grant execute on function public.registrar_evento(text, jsonb, text, text) to anon, authenticated;

-- ------------------------------------------- registros automáticos (gatilhos)
create or replace function public.liga_de(t integer) returns text language sql immutable as $$
  select case when t >= 8000 then 'Leões FC' when t >= 6000 then 'Lendas' when t >= 4000 then 'Campeão'
              when t >= 2500 then 'Mestre' when t >= 1500 then 'Diamante' when t >= 800 then 'Ouro'
              when t >= 400 then 'Prata' else 'Bronze' end;
$$;

create or replace function public.ev_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into eventos (jogador, tipo, dados) values (new.id, 'cadastro', jsonb_build_object('nome', new.nome));
  elsif liga_de(coalesce(new.trofeus, 0)) <> liga_de(coalesce(old.trofeus, 0)) then
    insert into eventos (jogador, tipo, dados) values (new.id, 'liga',
      jsonb_build_object('de', liga_de(coalesce(old.trofeus, 0)), 'para', liga_de(coalesce(new.trofeus, 0)),
                         'trofeus', new.trofeus, 'subiu', coalesce(new.trofeus, 0) > coalesce(old.trofeus, 0)));
  end if;
  return new;
end $$;
drop trigger if exists ev_perfil on public.perfis;
create trigger ev_perfil after insert or update of trofeus on public.perfis
  for each row execute function public.ev_perfil();

create or replace function public.ev_personagem() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.nivel > old.nivel then
    if new.nivel > 1 then
      insert into eventos (jogador, tipo, dados) values (new.jogador, 'evoluiu',
        jsonb_build_object('personagem', new.personagem, 'nivel', new.nivel));
    end if;
  end if;
  return new;
end $$;
drop trigger if exists ev_personagem on public.personagens_jogador;
create trigger ev_personagem after insert or update of nivel on public.personagens_jogador
  for each row execute function public.ev_personagem();

-- ------------------------------------------------------------ chave do painel
create table if not exists public.painel_config (id int primary key default 1 check (id = 1), hash text not null);
alter table public.painel_config enable row level security;   -- ninguém lê
insert into public.painel_config (id, hash)
values (1, encode(sha256(convert_to('HVM-YPNRUDdWGQmCo6PD5uf8cIQBl8cW', 'UTF8')), 'hex'))          -- <<< CHAVE
on conflict (id) do update set hash = excluded.hash;

-- --------------------------------------------------------- dados do painel
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
  -- partidas online (sem duelo amistoso = valem troféu)
  pvp as (
    select id, criada_em, heroes, monsters, vencedor, finalizada, coalesce(amistoso, false) as amistoso, coalesce(divergente, false) as divergente
    from partidas_pvp
  ),
  pvp_j as (     -- uma linha por jogador por partida
    select heroes as jogador, 'heroes' as lado, (vencedor = 'heroes') as venceu, (vencedor = 'empate') as empate, amistoso, criada_em, finalizada from pvp
    union all
    select monsters, 'monsters', (vencedor = 'monsters'), (vencedor = 'empate'), amistoso, criada_em, finalizada from pvp
  ),
  -- aparelhos que nunca entraram numa conta = convidados
  conv as (
    select e.aparelho from eventos e where e.aparelho is not null
    group by e.aparelho having bool_and(e.jogador is null)
  ),
  ev as (select * from eventos),
  quem as (      -- todos (contas + convidados)
    select p.id::text as chave, p.id as jogador, null::text as aparelho, p.nome, p.avatar_url, p.trofeus, p.moedas,
           p.vitorias, p.derrotas, p.lado_atual, p.criado_em, p.visto_em
    from perfis p
    union all
    select 'ap:' || c.aparelho, null, c.aparelho, 'Convidado ' || upper(left(c.aparelho, 4)), null, null, null, null, null, null,
           (select min(criado_em) from ev where ev.aparelho = c.aparelho), null
    from conv c
  ),
  ev_q as (      -- eventos ligados a cada "quem"
    select coalesce(e.jogador::text, 'ap:' || e.aparelho) as chave, e.* from ev e
  ),
  jog as (
    select q.chave, q.jogador, q.nome, q.avatar_url, q.trofeus, q.moedas, q.vitorias, q.derrotas, q.lado_atual, q.criado_em,
      greatest(q.visto_em, (select max(criado_em) from ev_q where ev_q.chave = q.chave)) as ultimo,
      (select count(*) from ev_q where ev_q.chave = q.chave and tipo = 'abriu') as acessos,
      (select coalesce(sum((dados->>'segundos')::numeric), 0) from ev_q where ev_q.chave = q.chave and tipo = 'sessao')::bigint as segundos,
      (select count(*) from pvp_j where pvp_j.jogador = q.jogador and finalizada and not amistoso) as pvp_online,
      (select count(*) from pvp_j where pvp_j.jogador = q.jogador and finalizada and not amistoso and venceu) as pvp_online_v,
      (select count(*) from pvp_j where pvp_j.jogador = q.jogador and finalizada and amistoso) as duelos,
      (select count(*) from ev_q where ev_q.chave = q.chave and tipo = 'pvp_bot') as pvp_bot,
      (select count(*) from ev_q where ev_q.chave = q.chave and tipo = 'pvp_bot' and (dados->>'venceu')::boolean) as pvp_bot_v,
      (select max((dados->>'bot_nivel')::int) from ev_q where ev_q.chave = q.chave and tipo = 'pvp_bot') as bot_nivel_max,
      (select count(*) from ev_q where ev_q.chave = q.chave and tipo = 'campanha' and (dados->>'venceu')::boolean) as camp_niveis,
      (select count(*) from ev_q where ev_q.chave = q.chave and tipo = 'campanha' and not (dados->>'venceu')::boolean) as camp_derrotas,
      (select coalesce(json_object_agg(dificuldade, nivel), '{}'::json) from recordes_campanha rc where rc.jogador = q.jogador) as recordes,
      (select coalesce(json_object_agg(dif, mx), '{}'::json) from (
          select dados->>'dif' as dif, max((dados->>'nivel')::int) as mx from ev_q
          where ev_q.chave = q.chave and tipo = 'campanha' group by 1) x) as camp_max,
      (select coalesce(json_object_agg(personagem, nivel), '{}'::json) from personagens_jogador pj where pj.jogador = q.jogador and pj.nivel > 1) as personagens,
      (select count(*) from pvp_j where pvp_j.jogador = q.jogador and lado = 'heroes')
        + (select count(*) from ev_q where ev_q.chave = q.chave and tipo = 'pvp_bot' and dados->>'lado' = 'heroes') as jogou_heroes,
      (select count(*) from pvp_j where pvp_j.jogador = q.jogador and lado = 'monsters')
        + (select count(*) from ev_q where ev_q.chave = q.chave and tipo = 'pvp_bot' and dados->>'lado' = 'monsters') as jogou_monsters,
      (select dados->>'plataforma' from ev_q where ev_q.chave = q.chave and tipo = 'abriu' order by criado_em desc limit 1) as plataforma,
      (select versao from ev_q where ev_q.chave = q.chave and versao is not null order by criado_em desc limit 1) as versao,
      (select dados->>'evento' from ev_q where ev_q.chave = q.chave and tipo = 'tutorial' and dados->>'parte' = 'jogo'
         and dados->>'evento' in ('terminou', 'pulou') order by criado_em desc limit 1) as tutorial
    from quem q
  ),
  dias_s as (select generate_series((now() at time zone tz)::date - (dias - 1), (now() at time zone tz)::date, interval '1 day')::date as dia),
  por_dia as (
    select d.dia,
      (select count(*) from ev where tipo = 'abriu' and (criado_em at time zone tz)::date = d.dia) as acessos,
      (select count(distinct coalesce(jogador::text, aparelho)) from ev where (criado_em at time zone tz)::date = d.dia) as ativos,
      (select count(*) from perfis where (criado_em at time zone tz)::date = d.dia) as novos,
      (select count(*) from pvp where finalizada and not amistoso and (criada_em at time zone tz)::date = d.dia) as pvp_online,
      (select count(*) from pvp where finalizada and amistoso and (criada_em at time zone tz)::date = d.dia) as duelos,
      (select count(*) from ev where tipo = 'pvp_bot' and (criado_em at time zone tz)::date = d.dia) as pvp_bot,
      (select count(*) from ev where tipo = 'campanha' and (dados->>'venceu')::boolean and (criado_em at time zone tz)::date = d.dia) as camp_niveis,
      (select count(*) from ev where tipo = 'campanha' and not (dados->>'venceu')::boolean and (criado_em at time zone tz)::date = d.dia) as camp_derrotas,
      (select coalesce(sum((dados->>'segundos')::numeric), 0) from ev where tipo = 'sessao' and (criado_em at time zone tz)::date = d.dia)::bigint as segundos
    from dias_s d
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
    'por_hora', (select json_agg(json_build_object('hora', h, 'acessos', n) order by h) from (
        select g.h, (select count(*) from ev where tipo = 'abriu' and criado_em > desde
                      and extract(hour from criado_em at time zone tz) = g.h) as n
        from generate_series(0, 23) g(h)) x),
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
          from ev e left join perfis p on p.id = e.jogador
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
