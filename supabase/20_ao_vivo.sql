-- =====================================================================
-- 20_ao_vivo.sql — PAINEL: AO VIVO (quem está jogando agora e o quê) + O QUE A GALERA CURTE
-- Rode DEPOIS do 16_painel.sql (usa a mesma chave do painel).
--
--   * ao_vivo: cada aparelho avisa a cada 30 s o que está fazendo (menu, campanha nível X, PvP, Cerco...)
--   * novos registros: cartas (cartas usadas em cada partida), tela (janela aberta), desistiu (saiu no meio)
--   * painel_ao_vivo(chave) e painel_gosto(chave, dias) para o painel.html
-- =====================================================================

create table if not exists public.ao_vivo (
  chave text primary key,                 -- id da conta, ou "ap:<aparelho>" para convidado
  jogador uuid references public.perfis(id) on delete cascade,
  aparelho text,
  atividade text not null default 'menu', -- menu / campanha / pvp_bot / pvp_online / cerco / duelo / fora
  detalhe text,                           -- "Nível 7 · Médio", "contra Bia", "Ranking"...
  versao text,
  desde timestamptz not null default now(),   -- desde quando está nesta atividade
  visto_em timestamptz not null default now()
);
create index if not exists ao_vivo_visto on public.ao_vivo (visto_em desc);
alter table public.ao_vivo enable row level security;

create or replace function public.estou_aqui(p_aparelho text, p_atividade text, p_detalhe text default null, p_versao text default null)
returns void language plpgsql security definer set search_path = public as $$
declare eu uuid := (select id from perfis where id = auth.uid());
        ap text := left(coalesce(p_aparelho, ''), 64);
        k text; a text := left(coalesce(p_atividade, 'menu'), 20);
begin
  if eu is null and ap = '' then return; end if;
  k := coalesce(eu::text, 'ap:' || ap);
  if eu is not null then
    update perfis set visto_em = now() where id = eu;
    delete from ao_vivo where chave = 'ap:' || ap and ap <> '';       -- entrou na conta: some o "convidado"
  end if;
  insert into ao_vivo (chave, jogador, aparelho, atividade, detalhe, versao, desde, visto_em)
  values (k, eu, nullif(ap, ''), a, left(p_detalhe, 60), left(p_versao, 20), now(), now())
  on conflict (chave) do update set
    jogador = excluded.jogador, aparelho = excluded.aparelho, versao = excluded.versao, visto_em = now(),
    desde = case when ao_vivo.atividade is distinct from excluded.atividade then now() else ao_vivo.desde end,
    atividade = excluded.atividade, detalhe = excluded.detalhe;
  delete from ao_vivo where visto_em < now() - interval '1 day';
end $$;
revoke all on function public.estou_aqui(text, text, text, text) from public;
grant execute on function public.estou_aqui(text, text, text, text) to anon, authenticated;

-- registrar_evento: aceita os tipos novos
create or replace function public.registrar_evento(p_tipo text, p_dados jsonb default '{}',
  p_aparelho text default null, p_versao text default null) returns void
language plpgsql security definer set search_path = public as $$
declare eu uuid := (select id from perfis where id = auth.uid());
        ap text := left(coalesce(p_aparelho, ''), 64);
begin
  if p_tipo not in ('abriu', 'sessao', 'campanha', 'pvp_bot', 'tutorial', 'cartas', 'tela', 'desistiu') then return; end if;
  if pg_column_size(coalesce(p_dados, '{}'::jsonb)) > 2000 then return; end if;
  if eu is null and ap = '' then return; end if;
  if (select count(*) from eventos
        where criado_em > now() - interval '1 day'
          and ((eu is not null and jogador = eu) or (ap <> '' and aparelho = ap))) >= 600 then
    return;
  end if;
  insert into eventos (jogador, aparelho, tipo, dados, versao)
  values (eu, nullif(ap, ''), p_tipo, coalesce(p_dados, '{}'::jsonb), left(p_versao, 20));
end $$;

create or replace function public.painel_checar(p_chave text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if encode(sha256(convert_to(coalesce(p_chave, ''), 'UTF8')), 'hex') is distinct from (select hash from painel_config where id = 1) then
    perform pg_sleep(1);
    raise exception 'chave errada';
  end if;
end $$;
revoke all on function public.painel_checar(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- AO VIVO
create or replace function public.painel_ao_vivo(p_chave text) returns json
language plpgsql security definer set search_path = public as $$
declare r json;
begin
  perform painel_checar(p_chave);
  with on_ as (
    select v.*, coalesce(p.nome, 'Convidado ' || upper(left(v.aparelho, 4))) as nome, p.trofeus, p.lado_atual, p.moedas
      from ao_vivo v left join perfis p on p.id = v.jogador
     where v.visto_em > now() - interval '75 seconds' and v.atividade <> 'fora')
  select json_build_object(
    'agora', now(),
    'total', (select count(*) from on_),
    'por_atividade', coalesce((select json_object_agg(atividade, n) from (select atividade, count(*) n from on_ group by 1) x), '{}'::json),
    'lista', coalesce((select json_agg(json_build_object('nome', nome, 'conta', jogador is not null, 'atividade', atividade, 'detalhe', detalhe,
                 'desde', desde, 'visto_em', visto_em, 'trofeus', trofeus, 'lado', lado_atual, 'moedas', moedas, 'versao', versao)
                 order by desde) from on_), '[]'::json),
    'hoje', (select count(*) from ao_vivo where visto_em > date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo'),
    'pico_24h', (select max(n) from (select date_trunc('hour', criado_em) h, count(distinct coalesce(jogador::text, aparelho)) n
                   from eventos where criado_em > now() - interval '24 hours' group by 1) x)
  ) into r;
  return r;
end $$;

-- ---------------------------------------------------------------- O QUE A GALERA CURTE
create or replace function public.painel_gosto(p_chave text, p_dias integer default 30) returns json
language plpgsql security definer set search_path = public as $$
declare desde timestamptz := now() - make_interval(days => least(greatest(coalesce(p_dias, 30), 1), 365)); r json;
begin
  perform painel_checar(p_chave);
  with cart as (
    select e.dados->>'modo' as modo, (e.dados->>'venceu')::boolean as venceu, c.key as carta, c.value::int as qtd,
           coalesce(e.jogador::text, e.aparelho) as quem
      from eventos e, jsonb_each_text(coalesce(e.dados->'cartas', '{}'::jsonb)) c
     where e.tipo = 'cartas' and e.criado_em > desde)
  select json_build_object(
    'cartas', coalesce((select json_agg(x order by x.usos desc) from (
        select carta, sum(qtd) as usos, count(distinct quem) as jogadores, count(*) as partidas,
               count(*) filter (where venceu) as vitorias
          from cart group by carta) x), '[]'::json),
    'cartas_por_modo', coalesce((select json_object_agg(modo, lst) from (
        select modo, json_agg(json_build_object('carta', carta, 'usos', usos) order by usos desc) lst from (
          select modo, carta, sum(qtd) usos from cart group by 1, 2) y group by modo) z), '{}'::json),
    'telas', coalesce((select json_agg(x order by x.n desc) from (
        select dados->>'nome' as tela, count(*) n, count(distinct coalesce(jogador::text, aparelho)) as pessoas
          from eventos where tipo = 'tela' and criado_em > desde group by 1) x), '[]'::json),
    'desistencias', coalesce((select json_agg(x order by x.n desc) from (
        select dados->>'modo' as modo, count(*) n, round(avg((dados->>'minuto')::numeric), 1) as minuto_medio,
               round(avg((dados->>'nivel')::numeric), 1) as nivel_medio
          from eventos where tipo = 'desistiu' and criado_em > desde group by 1) x), '[]'::json),
    'modos', json_build_object(
        'campanha', (select count(*) from eventos where tipo = 'campanha' and criado_em > desde),
        'batalha_bot', (select count(*) from eventos where tipo = 'pvp_bot' and coalesce(dados->>'modo', 'normal') = 'normal' and criado_em > desde),
        'cerco_bot', (select count(*) from eventos where tipo = 'pvp_bot' and dados->>'modo' = 'cerco' and criado_em > desde),
        'batalha_online', (select count(*) from partidas_pvp where finalizada and not amistoso and criada_em > desde),
        'duelo', (select count(*) from partidas_pvp where finalizada and amistoso and coalesce(modo, 'normal') = 'normal' and criada_em > desde),
        'cerco_duelo', (select count(*) from partidas_pvp where finalizada and modo = 'cerco' and criada_em > desde),
        'cerco_vitorias', (select count(*) from eventos where tipo = 'pvp_bot' and dados->>'modo' = 'cerco' and (dados->>'venceu')::boolean and criado_em > desde)),
    'social', json_build_object(
        'mensagens_chat', (select count(*) from mensagens where criado_em > desde),
        'mensagens_privadas', (select count(*) from mensagens_privadas where criado_em > desde),
        'convites_duelo', (select count(*) from duelos where criado_em > desde),
        'duelos_aceitos', (select count(*) from duelos where status = 'aceito' and criado_em > desde),
        'amizades', (select count(*) from amizades where status = 'aceita' and criado_em > desde))
  ) into r;
  return r;
end $$;

revoke all on function public.painel_ao_vivo(text), public.painel_gosto(text, integer) from public;
grant execute on function public.painel_ao_vivo(text), public.painel_gosto(text, integer) to anon, authenticated;
notify pgrst, 'reload schema';
