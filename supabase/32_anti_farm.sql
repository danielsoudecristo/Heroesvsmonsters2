-- =====================================================================
-- 32_anti_farm.sql — PvP: ninguém sobe troféu perdendo de propósito com outra conta (2 celulares)
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Rode DEPOIS do 28_serie_pvp.sql. Pode rodar de novo.
--
-- O GOLPE: a pessoa abre o jogo em 2 celulares (2 contas), entra na Batalha nos dois ao mesmo tempo e
-- deixa uma conta perder toda vez para a outra ganhar troféus.
--
-- A REGRA (LIMITE abaixo = 2):
-- 1) Os MESMOS dois jogadores só valem troféu em 2 séries a cada 24 horas.
-- 2) Depois disso a busca NÃO junta mais esses dois na Batalha (cada um cai com outra pessoa ou com o bot).
-- 3) Se mesmo assim uma série passar do limite (ex.: as duas buscas no mesmo instante), ela acaba
--    SEM troféus e SEM moedas para os dois (sem_trofeus = true; o jogo mostra o aviso no fim).
-- Duelo entre amigos (amistoso) e Cerco continuam livres: não valem troféu da Batalha.
-- =====================================================================

alter table public.series_pvp add column if not exists sem_trofeus boolean not null default false;
create index if not exists series_pvp_par_idx on public.series_pvp (a, b, criada_em);

-- quantas séries QUE VALERAM TROFÉU esses dois já terminaram nas últimas 24 h (qualquer ordem: a x b ou b x a)
create or replace function public._series_valendo_hoje(p1 uuid, p2 uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from series_pvp
   where status = 'fim' and not sem_trofeus and criada_em > now() - interval '24 hours'
     and ((a = p1 and b = p2) or (a = p2 and b = p1));
$$;
revoke all on function public._series_valendo_hoje(uuid, uuid) from public, anon, authenticated;

-- (igual ao 28, mais o LIMITE no fim da série)
create or replace function public._serie_registrar(s public.partidas_pvp, v text, wo boolean) returns void
language plpgsql security definer set search_path = public as $$
declare se public.series_pvp; quem uuid; acabou boolean := false; lado_a text; lado_b text;
  limite constant int := 2;
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
    if _series_valendo_hoje(se.a, se.b) >= limite then
      se.sem_trofeus := true;                               -- ANTI-FARM: já valeu o bastante hoje entre esses dois
    else
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
  end if;
  update series_pvp set pontos_a = se.pontos_a, pontos_b = se.pontos_b, jogo = se.jogo, status = se.status,
                        vencedor = se.vencedor, sem_trofeus = se.sem_trofeus where id = se.id;
  if not acabou then
    perform _serie_nova_partida(se, s);
  end if;
end $$;
revoke all on function public._serie_registrar(public.partidas_pvp, text, boolean) from public, anon, authenticated;

-- (igual ao 28, mais 'sem_trofeus' para o jogo mostrar o aviso)
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
    'sem_trofeus', se.sem_trofeus,
    'proxima', case when prox.id is not null then sala_json(prox) end);
end $$;

-- (igual ao 28: na Batalha, a busca pula quem já jogou o LIMITE de séries com você nas últimas 24 h)
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
  select * into outro from fila_pvp f
   where f.lado <> p_lado and f.plataforma = 'godot' and f.modo = p_modo and f.jogador <> auth.uid()
     and (p_modo <> 'normal' or _series_valendo_hoje(auth.uid(), f.jogador) < 2)      -- ANTI-FARM
   order by f.criado_em limit 1 for update skip locked;
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

revoke all on function public.ver_serie(uuid) from public, anon;
grant execute on function public.ver_serie(uuid) to authenticated;
notify pgrst, 'reload schema';
