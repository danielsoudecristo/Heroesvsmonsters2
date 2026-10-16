-- =====================================================================
-- Heroes vs Monsters — PvP: ADVERSÁRIO COM TROFÉUS PARECIDOS (site e app)
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Rode DEPOIS do 8_pvp_godot.sql.
-- Pode rodar de novo sem problema. O jogo e o site NÃO precisam mudar nada.
--
-- Como funciona a procura (o jogo pergunta a cada 1,5 s; depois de 10 s sem ninguém, joga contra o bot):
-- 1) PERTO: procura alguém com troféus parecidos. "Parecido" = até 15% de diferença (no mínimo 40 troféus).
--    Ex.: 300 troféus encontra de 255 a 345. Não precisa ser igual: o jogo escolhe o MAIS PERTO que tiver.
-- 2) ABRINDO: a cada segundo esperando, aceita uma diferença um pouco maior (aos 6 s já é o triplo).
-- 3) QUALQUER UM: depois de 7 s esperando, aceita qualquer pessoa (melhor que jogar contra o bot).
-- 4) SEQUÊNCIA DE VITÓRIAS: quem vence 3 ou mais seguidas passa a procurar gente com MAIS troféus,
--    e quanto maior a sequência, maior a diferença: +1 faixa por vitória a partir da 3ª (até +3 faixas).
--    Quem perde 3 ou mais seguidas procura gente um pouco mais fraca (até −2 vezes a faixa), para não desanimar.
-- Proteção: ninguém recebe alguém MUITO mais forte do que procura (cada um com a faixa dele), menos depois de 7 s.
-- Ex.: 300 troféus com 4 vitórias seguidas procura perto de 390; 3 seguidas, perto de 345.
-- =====================================================================

alter table public.fila_pvp add column if not exists trofeus   integer not null default 0;
alter table public.fila_pvp add column if not exists alvo      integer not null default 0;     -- troféus que ele procura
alter table public.fila_pvp add column if not exists faixa     integer not null default 40;    -- diferença aceita no começo
alter table public.fila_pvp add column if not exists entrou_em timestamptz not null default now();

-- SEQUÊNCIA no PvP: +3 = venceu as 3 últimas; −2 = perdeu as 2 últimas; 0 = nunca jogou.
create or replace function public.sequencia_pvp(p_jogador uuid) returns integer
language sql stable security definer set search_path = public as $$
  with ult as (
    select venceu, row_number() over (order by criado_em desc) as n
      from (select venceu, criado_em from partidas where jogador = p_jogador and modo = 'pvp'
            order by criado_em desc limit 12) x
  ), primeira as (select venceu from ult where n = 1)
  select coalesce(
    (select case when p.venceu then 1 else -1 end *
            (coalesce((select min(n) from ult where venceu <> p.venceu), (select count(*) + 1 from ult)) - 1)
       from primeira p), 0)::integer;
$$;
revoke all on function public.sequencia_pvp(uuid) from public, anon, authenticated;

-- diferença aceita depois de t segundos esperando (null = qualquer um)
create or replace function public.faixa_agora(p_faixa integer, p_t double precision) returns double precision
language sql immutable as $$
  select case when p_t >= 7 then null else p_faixa * (1.0 + greatest(0.0, p_t - 2.0) * 0.5) end;
$$;

create or replace function public.procurar_partida_plat(p_lado text, p_niveis jsonb, p_plat text) returns json
language plpgsql security definer set search_path = public as $$
declare
  outro public.fila_pvp; s public.partidas_pvp;
  meus_trofeus integer; seq integer; base integer; meu_alvo integer; minha_faixa integer;
  entrei timestamptz; t_eu double precision; f_eu double precision;
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

  -- quem sou eu: troféus, sequência, o que procuro
  select coalesce(trofeus, 0) into meus_trofeus from perfis where id = auth.uid();
  meus_trofeus := coalesce(meus_trofeus, 0);
  seq := sequencia_pvp(auth.uid());
  base := greatest(40, round(meus_trofeus * 0.15))::integer;
  meu_alvo := meus_trofeus;
  minha_faixa := base;
  if seq >= 3 then                                   -- vencendo muito: adversário mais forte e faixa maior
    meu_alvo := meus_trofeus + least(base * 3, base * (seq - 2));
    minha_faixa := least(base * 2, round(base * (1 + 0.25 * (seq - 2))))::integer;
  elsif seq <= -3 then                               -- perdendo muito: adversário um pouco mais fraco
    meu_alvo := greatest(0, meus_trofeus - least(base * 2, round(base * 0.5 * (-seq - 2))::integer));
  end if;
  -- há quanto tempo estou procurando (a fila renova a cada 1,5 s; parou de renovar = começa de novo)
  select entrou_em into entrei from fila_pvp where jogador = auth.uid() and criado_em > now() - interval '5 seconds';
  t_eu := extract(epoch from now() - coalesce(entrei, now()));
  f_eu := faixa_agora(minha_faixa, t_eu);

  -- o MAIS PERTO do que eu procuro, que também me aceite
  select q.* into outro from fila_pvp q
   where q.lado <> p_lado and q.plataforma = p_plat and q.jogador <> auth.uid()
     and (
       (f_eu is null or abs(q.trofeus - meu_alvo) <= f_eu)
       and (faixa_agora(q.faixa, extract(epoch from now() - q.entrou_em)) is null
            or meus_trofeus - q.alvo <= faixa_agora(q.faixa, extract(epoch from now() - q.entrou_em)))
       or t_eu >= 7 or now() - q.entrou_em >= interval '7 seconds'
     )
   order by abs(q.trofeus - meu_alvo), q.entrou_em
   limit 1 for update skip locked;

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

  insert into fila_pvp (jogador, lado, niveis, plataforma, trofeus, alvo, faixa, entrou_em)
  values (auth.uid(), p_lado, coalesce(p_niveis, '{}'), p_plat, meus_trofeus, meu_alvo, minha_faixa, now())
  on conflict (jogador) do update set lado = excluded.lado, niveis = excluded.niveis, plataforma = excluded.plataforma,
    trofeus = excluded.trofeus, alvo = excluded.alvo, faixa = excluded.faixa,
    entrou_em = case when fila_pvp.criado_em > now() - interval '5 seconds' then fila_pvp.entrou_em else now() end,
    criado_em = now();
  return null;
end $$;
revoke all on function public.procurar_partida_plat(text, jsonb, text) from public, anon, authenticated;
notify pgrst, 'reload schema';
