-- =====================================================================
-- 28_serie_pvp.sql — BATALHA ONLINE EM SÉRIE (vale troféus)
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Rode DEPOIS do 27_sala_de_entrada.sql. Pode rodar de novo.
--
-- A REGRA: para ganhar os troféus é preciso vencer DE HEROES E DE MONSTERS.
--   Partida 1: cada um no lado que escolheu.  Partida 2: os MESMOS dois, com os lados TROCADOS (o servidor cria sozinho).
--   2 x 0  -> quem venceu as duas leva os troféus (+30 / −20, como antes).
--   Não fechou 2 x 0 (1 x 1, empate...) -> Partida 3 de DESEMPATE, com o lado sorteado. Quem tiver mais pontos leva.
--   Ainda igual depois da 3ª -> empate (os dois ganham as moedas de empate).
--   W.O. (alguém saiu) -> a série acaba na hora: quem ficou leva.
-- Só vale para a Batalha do JOGO (plataforma 'godot', modo 'normal', não amistosa). O site, os duelos e o Cerco
-- continuam como antes (resultado na hora).
-- =====================================================================

create table if not exists public.series_pvp (
  id uuid primary key default gen_random_uuid(),
  a uuid not null,                                   -- Heroes na partida 1
  b uuid not null,                                   -- Monsters na partida 1
  pontos_a smallint not null default 0,
  pontos_b smallint not null default 0,
  jogo smallint not null default 1,                  -- partida que está valendo agora (1, 2 ou 3)
  status text not null default 'andando',            -- andando / fim
  vencedor uuid,                                     -- (fim) null = empate
  criada_em timestamptz not null default now()
);
alter table public.series_pvp enable row level security;   -- (só pelas funções abaixo)

alter table public.partidas_pvp add column if not exists serie uuid references public.series_pvp(id);
alter table public.partidas_pvp add column if not exists jogo smallint not null default 1;

-- a sala diz em que partida da série está e o placar (pontos de quem está de Heroes / de Monsters NESTA sala)
create or replace function public.sala_json(s public.partidas_pvp) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('id', s.id, 'semente', s.semente, 'heroes', s.heroes, 'monsters', s.monsters,
    'niveis_heroes', s.niveis_heroes, 'niveis_monsters', s.niveis_monsters,
    'nome_heroes', (select split_part(nome, ' ', 1) from perfis where id = s.heroes),
    'nome_monsters', (select split_part(nome, ' ', 1) from perfis where id = s.monsters),
    'foto_heroes', (select avatar_url from perfis where id = s.heroes),
    'foto_monsters', (select avatar_url from perfis where id = s.monsters),
    'vencedor', s.vencedor, 'finalizada', s.finalizada, 'amistoso', s.amistoso,
    'aposta_moedas', s.aposta_moedas, 'aposta_trofeus', s.aposta_trofeus, 'modo', s.modo,
    'serie', s.serie, 'jogo', s.jogo,
    'em_serie', (s.plataforma = 'godot' and coalesce(s.modo, 'normal') = 'normal' and not s.amistoso),
    'pontos_heroes', (select case when se.a = s.heroes then se.pontos_a else se.pontos_b end from series_pvp se where se.id = s.serie),
    'pontos_monsters', (select case when se.a = s.monsters then se.pontos_a else se.pontos_b end from series_pvp se where se.id = s.serie));
$$;

-- cria a próxima partida da série (lados: trocados na 2ª, sorteados na 3ª)
create or replace function public._serie_nova_partida(se public.series_pvp, ultima public.partidas_pvp) returns void
language plpgsql security definer set search_path = public as $$
declare h uuid; m uuid;
begin
  if se.jogo = 2 then
    h := ultima.monsters; m := ultima.heroes;
  elsif random() < 0.5 then
    h := se.a; m := se.b;
  else
    h := se.b; m := se.a;
  end if;
  insert into partidas_pvp (heroes, monsters, semente, niveis_heroes, niveis_monsters, plataforma, modo, amistoso, serie, jogo)
  values (h, m, floor(random() * 4294967295)::bigint,
          coalesce((select jsonb_object_agg(personagem, nivel) from personagens_jogador where jogador = h), '{}'::jsonb),
          coalesce((select jsonb_object_agg(personagem, nivel) from personagens_jogador where jogador = m), '{}'::jsonb),
          'godot', 'normal', false, se.id, se.jogo);
end $$;

-- uma partida da série acabou: soma o ponto, decide se tem próxima ou se a série acabou (aí paga os troféus)
create or replace function public._serie_registrar(s public.partidas_pvp, v text, wo boolean) returns void
language plpgsql security definer set search_path = public as $$
declare se public.series_pvp; quem uuid; acabou boolean := false; lado_a text; lado_b text;
begin
  if s.serie is null then                                   -- 1ª partida: a série nasce agora
    insert into series_pvp (a, b) values (s.heroes, s.monsters) returning * into se;
    update partidas_pvp set serie = se.id, jogo = 1 where id = s.id;
    s.serie := se.id; s.jogo := 1;
  end if;
  select * into se from series_pvp where id = s.serie for update;
  if se.status = 'fim' or s.jogo <> se.jogo then return; end if;
  quem := case v when 'heroes' then s.heroes when 'monsters' then s.monsters else null end;
  if quem = se.a then se.pontos_a := se.pontos_a + 1; elsif quem = se.b then se.pontos_b := se.pontos_b + 1; end if;

  if wo then
    acabou := true;
    se.vencedor := quem;
  elsif se.jogo = 1 then
    se.jogo := 2;
  elsif se.jogo = 2 then
    if se.pontos_a = 2 or se.pontos_b = 2 then
      acabou := true;
      se.vencedor := case when se.pontos_a = 2 then se.a else se.b end;
    else
      se.jogo := 3;                                         -- desempate
    end if;
  else
    acabou := true;
    se.vencedor := case when se.pontos_a > se.pontos_b then se.a when se.pontos_b > se.pontos_a then se.b else null end;
  end if;

  if acabou then
    se.status := 'fim';
    lado_a := case when s.heroes = se.a then 'heroes' else 'monsters' end;   -- (o lado de cada um na última partida)
    lado_b := case when lado_a = 'heroes' then 'monsters' else 'heroes' end;
    if se.vencedor is null then
      perform aplicar_resultado_pvp(se.a, 'empate', lado_a);
      perform aplicar_resultado_pvp(se.b, 'empate', lado_b);
    else
      perform aplicar_resultado_pvp(se.a, case when se.vencedor = se.a then 'vitoria' else 'derrota' end, lado_a);
      perform aplicar_resultado_pvp(se.b, case when se.vencedor = se.b then 'vitoria' else 'derrota' end, lado_b);
    end if;
  end if;
  update series_pvp set pontos_a = se.pontos_a, pontos_b = se.pontos_b, jogo = se.jogo, status = se.status,
                        vencedor = se.vencedor where id = se.id;
  if not acabou then
    perform _serie_nova_partida(se, s);
  end if;
end $$;
revoke all on function public._serie_nova_partida(public.series_pvp, public.partidas_pvp),
                        public._serie_registrar(public.partidas_pvp, text, boolean) from public, anon, authenticated;

-- RESULTADO: na série, a partida só soma ponto (os troféus saem quando a série acaba)
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
    update partidas_pvp set vencedor = v, finalizada = true where id = s.id;
    if s.amistoso then
      if v <> 'empate' and (s.aposta_moedas > 0 or s.aposta_trofeus > 0) then
        perform pagar_aposta_duelo(case v when 'heroes' then s.heroes else s.monsters end,
                                   case v when 'heroes' then s.monsters else s.heroes end, s.aposta_moedas, s.aposta_trofeus);
      end if;
    elsif s.plataforma = 'godot' and coalesce(s.modo, 'normal') = 'normal' then
      perform _serie_registrar(s, v, coalesce(p_resumo, '') = 'wo');
    else
      perform aplicar_resultado_pvp(s.heroes,   case v when 'heroes' then 'vitoria' when 'monsters' then 'derrota' else 'empate' end, 'heroes');
      perform aplicar_resultado_pvp(s.monsters, case v when 'monsters' then 'vitoria' when 'heroes' then 'derrota' else 'empate' end, 'monsters');
    end if;
  elsif s.vencedor is distinct from v and p_resumo <> 'wo' then
    update partidas_pvp set divergente = true where id = s.id;
  end if;
  select * into s from partidas_pvp where id = p_sala;
  return sala_json(s);
end $$;

-- como está a série (do meu ponto de vista): placar, se acabou, quem venceu e a PRÓXIMA sala (quando houver)
create or replace function public.ver_serie(p_serie uuid) returns json
language plpgsql stable security definer set search_path = public as $$
declare se public.series_pvp; prox public.partidas_pvp; sou_a boolean;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  select * into se from series_pvp where id = p_serie;
  if se.id is null or auth.uid() not in (se.a, se.b) then raise exception 'série não encontrada'; end if;
  sou_a := auth.uid() = se.a;
  if se.status = 'andando' then
    select * into prox from partidas_pvp where serie = se.id and jogo = se.jogo and not finalizada order by criada_em desc limit 1;
  end if;
  return json_build_object('id', se.id, 'jogo', se.jogo, 'status', se.status,
    'meus_pontos', case when sou_a then se.pontos_a else se.pontos_b end,
    'pontos_dele', case when sou_a then se.pontos_b else se.pontos_a end,
    'venci', case when se.status <> 'fim' or se.vencedor is null then null else se.vencedor = auth.uid() end,
    'proxima', case when prox.id is not null then sala_json(prox) end);
end $$;

-- a busca do PvP não pode "achar" a próxima partida da série como se fosse uma partida nova
create or replace function public.procurar_partida_modo(p_lado text, p_modo text) returns json
language plpgsql security definer set search_path = public as $$
declare outro public.fila_pvp; s public.partidas_pvp; meus jsonb;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_lado not in ('heroes','monsters') then raise exception 'lado inválido'; end if;
  if p_modo not in ('normal','cerco') then raise exception 'modo inválido'; end if;
  select * into s from partidas_pvp
   where auth.uid() in (heroes, monsters) and not finalizada and plataforma = 'godot' and modo = p_modo
     and coalesce(jogo, 1) = 1 and criada_em > now() - interval '40 seconds'
   order by criada_em desc limit 1;
  if s.id is not null then delete from fila_pvp where jogador = auth.uid(); return sala_json(s); end if;
  delete from fila_pvp where criado_em < now() - interval '20 seconds';
  meus := coalesce((select jsonb_object_agg(personagem, nivel) from personagens_jogador where jogador = auth.uid()), '{}'::jsonb);
  select * into outro from fila_pvp
   where lado <> p_lado and plataforma = 'godot' and modo = p_modo and jogador <> auth.uid()
   order by criado_em limit 1 for update skip locked;
  if outro.jogador is not null then
    delete from fila_pvp where jogador in (outro.jogador, auth.uid());
    insert into partidas_pvp (heroes, monsters, semente, niveis_heroes, niveis_monsters, plataforma, modo, amistoso)
    values (case when p_lado = 'heroes' then auth.uid() else outro.jogador end,
            case when p_lado = 'monsters' then auth.uid() else outro.jogador end,
            floor(random() * 4294967295)::bigint,
            case when p_lado = 'heroes' then meus else outro.niveis end,
            case when p_lado = 'monsters' then meus else outro.niveis end,
            'godot', p_modo, p_modo = 'cerco')
    returning * into s;
    return sala_json(s);
  end if;
  insert into fila_pvp (jogador, lado, niveis, plataforma, modo) values (auth.uid(), p_lado, meus, 'godot', p_modo)
  on conflict (jogador) do update set lado = excluded.lado, niveis = excluded.niveis, plataforma = 'godot',
                                      modo = excluded.modo, criado_em = now();
  return null;
end $$;

create or replace function public.sair_da_fila_modo(p_modo text) returns json
language plpgsql security definer set search_path = public as $$
declare s public.partidas_pvp;
begin
  if auth.uid() is null then return null; end if;
  delete from fila_pvp where jogador = auth.uid();
  select * into s from partidas_pvp
   where auth.uid() in (heroes, monsters) and not finalizada and plataforma = 'godot' and modo = p_modo
     and coalesce(jogo, 1) = 1 and criada_em > now() - interval '40 seconds'
   order by criada_em desc limit 1;
  if s.id is not null then return sala_json(s); end if;
  return null;
end $$;

revoke all on function public.ver_serie(uuid) from public, anon;
grant execute on function public.ver_serie(uuid) to authenticated;
notify pgrst, 'reload schema';
