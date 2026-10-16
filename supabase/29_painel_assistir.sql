-- =====================================================================
-- 29_painel_assistir.sql — PAINEL AO VIVO PRO: o que cada um conseguiu NESTA sessão + ASSISTIR AO VIVO
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Rode DEPOIS do 20_ao_vivo.sql. Pode rodar de novo.
--
--   * painel_ao_vivo agora traz, para cada pessoa online, o que ela fez desde que abriu o jogo
--     (níveis vencidos, derrotas, PvP, evoluções, liga) — a "sessão".
--   * ASSISTIR: o painel chama painel_assistir(quem) a cada 2,5 s. Enquanto isso, o jogo daquela pessoa
--     (que pergunta "alguém está me assistindo?" no estou_aqui2) manda uma foto resumida da partida:
--     vida dos castelos, energia, onda, e onde está cada personagem em cada linha. Ninguém assistindo = o jogo
--     não manda nada a mais (não gasta).
-- =====================================================================

alter table public.ao_vivo add column if not exists tela jsonb;                 -- a última foto da partida
alter table public.ao_vivo add column if not exists tela_em timestamptz;
alter table public.ao_vivo add column if not exists assistir_ate timestamptz;   -- o painel está assistindo até
alter table public.ao_vivo add column if not exists v2 boolean not null default false;  -- o jogo dessa pessoa já sabe mandar a foto?

-- O jogo avisa o que está fazendo (+ a foto da partida, quando alguém assiste). Devolve true = "manda as fotos".
create or replace function public.estou_aqui2(p_aparelho text, p_atividade text, p_detalhe text default null,
  p_versao text default null, p_tela jsonb default null) returns boolean
language plpgsql security definer set search_path = public as $$
declare eu uuid := (select id from perfis where id = auth.uid());
        ap text := left(coalesce(p_aparelho, ''), 64);
        k text; a text := left(coalesce(p_atividade, 'menu'), 20); assiste timestamptz;
begin
  if eu is null and ap = '' then return false; end if;
  k := coalesce(eu::text, 'ap:' || ap);
  if eu is not null then
    update perfis set visto_em = now() where id = eu and visto_em < now() - interval '20 seconds';
    delete from ao_vivo where chave = 'ap:' || ap and ap <> '';
  end if;
  insert into ao_vivo (chave, jogador, aparelho, atividade, detalhe, versao, desde, visto_em, tela, tela_em, v2)
  values (k, eu, nullif(ap, ''), a, left(p_detalhe, 60), left(p_versao, 20), now(), now(),
          case when pg_column_size(p_tela) <= 6000 then p_tela end, case when p_tela is not null then now() end, true)
  on conflict (chave) do update set
    v2 = true, jogador = excluded.jogador, aparelho = excluded.aparelho, versao = excluded.versao, visto_em = now(),
    desde = case when ao_vivo.atividade is distinct from excluded.atividade then now() else ao_vivo.desde end,
    atividade = excluded.atividade, detalhe = excluded.detalhe,
    tela = case when excluded.tela is not null then excluded.tela when ao_vivo.atividade is distinct from excluded.atividade then null else ao_vivo.tela end,
    tela_em = coalesce(excluded.tela_em, ao_vivo.tela_em)
  returning assistir_ate into assiste;
  if random() < 0.02 then delete from ao_vivo where visto_em < now() - interval '1 day'; end if;
  return coalesce(assiste > now(), false);
end $$;
revoke all on function public.estou_aqui2(text, text, text, text, jsonb) from public;
grant execute on function public.estou_aqui2(text, text, text, text, jsonb) to anon, authenticated;

-- versões ANTIGAS do jogo continuam chamando o estou_aqui: marca que esse aparelho NÃO manda a foto (o painel avisa)
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
    delete from ao_vivo where chave = 'ap:' || ap and ap <> '';
  end if;
  insert into ao_vivo (chave, jogador, aparelho, atividade, detalhe, versao, desde, visto_em, v2)
  values (k, eu, nullif(ap, ''), a, left(p_detalhe, 60), left(p_versao, 20), now(), now(), false)
  on conflict (chave) do update set
    v2 = false, jogador = excluded.jogador, aparelho = excluded.aparelho, versao = excluded.versao, visto_em = now(),
    desde = case when ao_vivo.atividade is distinct from excluded.atividade then now() else ao_vivo.desde end,
    atividade = excluded.atividade, detalhe = excluded.detalhe, tela = null;
  delete from ao_vivo where visto_em < now() - interval '1 day';
end $$;
revoke all on function public.estou_aqui(text, text, text, text) from public;
grant execute on function public.estou_aqui(text, text, text, text) to anon, authenticated;
-- O que a pessoa fez nesta SESSÃO (desde que abriu o jogo; no máximo as últimas 6 h)
create or replace function public._sessao_de(p_jogador uuid, p_aparelho text) returns json
language sql stable security definer set search_path = public as $$
  with ini as (
    select coalesce((select max(criado_em) from eventos
                      where tipo = 'abriu' and criado_em > now() - interval '6 hours'
                        and ((p_jogador is not null and jogador = p_jogador) or (p_jogador is null and aparelho = p_aparelho))),
                    now() - interval '2 hours') as t),
  ev as (
    select e.criado_em, e.tipo, e.dados from eventos e, ini
     where e.criado_em >= ini.t and e.tipo in ('campanha', 'pvp_bot', 'desistiu', 'tutorial', 'evoluiu', 'liga')
       and ((p_jogador is not null and e.jogador = p_jogador) or (p_jogador is null and e.aparelho = p_aparelho))
    union all
    select p.criada_em, 'pvp_online', json_build_object('venceu', p.vencedor = case when p.heroes = p_jogador then 'heroes' else 'monsters' end,
           'empate', p.vencedor = 'empate', 'lado', case when p.heroes = p_jogador then 'heroes' else 'monsters' end,
           'contra', (select split_part(nome, ' ', 1) from perfis where id = case when p.heroes = p_jogador then p.monsters else p.heroes end),
           'amistoso', p.amistoso, 'modo', p.modo, 'jogo', p.jogo)::jsonb
      from partidas_pvp p, ini
     where p_jogador is not null and p.finalizada and p.criada_em >= ini.t and p_jogador in (p.heroes, p.monsters)
    )
  select json_build_object(
    'desde', (select t from ini),
    'niveis', (select count(*) from ev where tipo = 'campanha' and (dados->>'venceu')::boolean),
    'nivel_max', (select max((dados->>'nivel')::int) from ev where tipo = 'campanha' and (dados->>'venceu')::boolean),
    'derrotas', (select count(*) from ev where tipo = 'campanha' and not (dados->>'venceu')::boolean),
    'pvp_v', (select count(*) from ev where tipo in ('pvp_bot', 'pvp_online') and (dados->>'venceu')::boolean),
    'evolucoes', (select count(*) from ev where tipo = 'evoluiu'),
    'pvp_d', (select count(*) from ev where tipo in ('pvp_bot', 'pvp_online') and not coalesce((dados->>'venceu')::boolean, false) and not coalesce((dados->>'empate')::boolean, false)),
    'ultimos', coalesce((select json_agg(json_build_object('em', criado_em, 'tipo', tipo, 'dados', dados) order by criado_em desc)
                           from (select * from ev order by criado_em desc limit 12) x), '[]'::json));
$$;
revoke all on function public._sessao_de(uuid, text) from public, anon, authenticated;

-- AO VIVO (agora com a sessão de cada um e se tem foto da partida)
create or replace function public.painel_ao_vivo(p_chave text) returns json
language plpgsql security definer set search_path = public as $$
declare r json;
begin
  perform painel_checar(p_chave);
  with on_ as (
    select v.*, coalesce(p.nome, 'Convidado ' || upper(left(v.aparelho, 4))) as nome, p.trofeus, p.lado_atual, p.moedas, p.avatar_url
      from ao_vivo v left join perfis p on p.id = v.jogador
     where v.visto_em > now() - interval '75 seconds' and v.atividade <> 'fora')
  select json_build_object(
    'agora', now(),
    'total', (select count(*) from on_),
    'por_atividade', coalesce((select json_object_agg(atividade, n) from (select atividade, count(*) n from on_ group by 1) x), '{}'::json),
    'lista', coalesce((select json_agg(json_build_object('chave', chave, 'nome', nome, 'conta', jogador is not null, 'atividade', atividade,
                 'detalhe', detalhe, 'desde', desde, 'visto_em', visto_em, 'trofeus', trofeus, 'lado', lado_atual, 'moedas', moedas,
                 'versao', versao, 'v2', v2, 'foto', avatar_url, 'sessao', _sessao_de(jogador, aparelho)) order by desde) from on_), '[]'::json),
    'hoje', (select count(*) from ao_vivo where visto_em > date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo'),
    'pico_24h', (select max(n) from (select date_trunc('hour', criado_em) h, count(distinct coalesce(jogador::text, aparelho)) n
                   from eventos where criado_em > now() - interval '24 hours' group by 1) x)
  ) into r;
  return r;
end $$;

-- ASSISTIR: marca que o painel está olhando (por 12 s) e devolve a última foto da partida + a sessão
create or replace function public.painel_assistir(p_chave text, p_quem text) returns json
language plpgsql security definer set search_path = public as $$
declare v public.ao_vivo; nome text; trof integer;
begin
  perform painel_checar(p_chave);
  update ao_vivo set assistir_ate = now() + interval '12 seconds' where chave = p_quem returning * into v;
  if v.chave is null then return null; end if;
  select coalesce(p.nome, 'Convidado ' || upper(left(v.aparelho, 4))), p.trofeus into nome, trof from perfis p where p.id = v.jogador;
  return json_build_object('chave', v.chave, 'nome', coalesce(nome, 'Convidado ' || upper(left(v.aparelho, 4))), 'trofeus', trof,
    'atividade', v.atividade, 'detalhe', v.detalhe, 'versao', v.versao, 'v2', v.v2, 'desde', v.desde, 'visto_em', v.visto_em, 'online', v.visto_em > now() - interval '75 seconds',
    'tela', v.tela, 'tela_em', v.tela_em, 'agora', now(), 'sessao', _sessao_de(v.jogador, v.aparelho));
end $$;

revoke all on function public.painel_ao_vivo(text), public.painel_assistir(text, text) from public;
grant execute on function public.painel_ao_vivo(text), public.painel_assistir(text, text) to anon, authenticated;
notify pgrst, 'reload schema';
