-- =====================================================================
-- 35_mesmo_ip.sql — Série entre dois jogadores na MESMA INTERNET (mesmo Wi-Fi) não vale troféus
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Rode DEPOIS do 28_serie_pvp.sql
-- (e depois do 32_anti_farm.sql, se já tiver rodado). Pode rodar de novo.
--
-- A REGRA:
-- 1) Quem joga a Batalha online tem o IP da internet anotado (EMBARALHADO: um código md5 que não volta a ser o IP;
--    só serve para comparar se dois são iguais). O IP é o da rede (o roteador do Wi-Fi), não o do celular:
--    dois celulares diferentes no mesmo Wi-Fi têm o MESMO IP.
-- 2) Dois jogadores na MESMA REDE (em qualquer partida da série) valem troféu em até 2 séries a cada 24 horas.
--    Da 3ª em diante a série acaba SEM troféus e SEM moedas (sem_trofeus = true). Eles continuam jogando normal.
--    (O jogo não explica o motivo, para ninguém aprender a trocar para o 4G.)
-- 3) Em redes DIFERENTES não tem limite: revanche à vontade (tira o limite de 2 por dia do 32_anti_farm.sql).
-- =====================================================================

alter table public.series_pvp add column if not exists sem_trofeus boolean not null default false;
alter table public.series_pvp add column if not exists mesma_rede boolean not null default false;

create table if not exists public.ip_recente (
  jogador uuid primary key references public.perfis(id) on delete cascade,
  ip text not null,                                  -- md5 do IP (não guarda o IP de verdade)
  visto_em timestamptz not null default now()
);
alter table public.ip_recente enable row level security;      -- (só pelas funções abaixo)

-- IP de quem está chamando agora (o Supabase passa os cabeçalhos da requisição), já embaralhado. null = não deu para ver.
create or replace function public._meu_ip() returns text
language plpgsql stable security definer set search_path = public as $$
declare h json; ip text;
begin
  begin
    h := nullif(current_setting('request.headers', true), '')::json;
  exception when others then
    return null;
  end;
  ip := coalesce(nullif(h ->> 'cf-connecting-ip', ''), nullif(trim(split_part(coalesce(h ->> 'x-forwarded-for', ''), ',', 1)), ''),
                 nullif(h ->> 'x-real-ip', ''));
  if ip is null then return null; end if;
  return md5('hvm-ip-v1:' || ip);
end $$;

create or replace function public._anotar_ip() returns void
language plpgsql security definer set search_path = public as $$
declare ip text := _meu_ip();
begin
  if auth.uid() is null or ip is null then return; end if;
  insert into ip_recente (jogador, ip, visto_em) values (auth.uid(), ip, now())
  on conflict (jogador) do update set ip = excluded.ip, visto_em = now();
end $$;

-- os dois estão na mesma rede? (os dois vistos nos últimos 15 minutos com o mesmo IP)
create or replace function public._mesma_rede(p1 uuid, p2 uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select a.ip = b.ip from ip_recente a, ip_recente b
                    where a.jogador = p1 and b.jogador = p2
                      and a.visto_em > now() - interval '15 minutes' and b.visto_em > now() - interval '15 minutes'), false);
$$;
revoke all on function public._meu_ip(), public._anotar_ip(), public._mesma_rede(uuid, uuid) from public, anon, authenticated;

-- quantas séries NA MESMA REDE esses dois já terminaram valendo troféu nas últimas 24 h
create or replace function public._series_mesma_rede_hoje(p1 uuid, p2 uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from series_pvp
   where status = 'fim' and mesma_rede and not sem_trofeus and criada_em > now() - interval '24 hours'
     and ((a = p1 and b = p2) or (a = p2 and b = p1));
$$;
revoke all on function public._series_mesma_rede_hoje(uuid, uuid) from public, anon, authenticated;

-- (igual ao 28: série de 2 partidas + desempate; mesma rede = até 2 séries valendo por 24 h; redes diferentes = sem limite)
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
  if _mesma_rede(se.a, se.b) then se.mesma_rede := true; end if;     -- MESMA INTERNET em alguma partida da série
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
    if se.mesma_rede and _series_mesma_rede_hoje(se.a, se.b) >= 2 then
      se.sem_trofeus := true;                               -- 3ª série na mesma rede em 24 h: não vale nada
    end if;
    if not se.sem_trofeus then
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
                        vencedor = se.vencedor, sem_trofeus = se.sem_trofeus, mesma_rede = se.mesma_rede where id = se.id;
  if not acabou then
    perform _serie_nova_partida(se, s);
  end if;
end $$;
revoke all on function public._serie_registrar(public.partidas_pvp, text, boolean) from public, anon, authenticated;

-- (igual ao 28, anotando o IP de quem manda o resultado)
create or replace function public.finalizar_pvp(p_sala uuid, p_vencedor text, p_resumo text) returns json
language plpgsql security definer set search_path = public as $$
declare s public.partidas_pvp; v text := coalesce(p_vencedor, 'empate'); eu text;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if v not in ('heroes','monsters','empate') then raise exception 'resultado inválido'; end if;
  perform _anotar_ip();
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

-- (igual ao 28: SEM o limite do 32, anotando o IP de quem procura partida)
create or replace function public.procurar_partida_modo(p_lado text, p_modo text) returns json
language plpgsql security definer set search_path = public as $$
declare outro public.fila_pvp; s public.partidas_pvp; meus jsonb;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_lado not in ('heroes','monsters') then raise exception 'lado inválido'; end if;
  if p_modo not in ('normal','cerco') then raise exception 'modo inválido'; end if;
  perform _anotar_ip();
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

-- (igual ao 32: o jogo lê 'sem_trofeus' para mostrar o aviso no fim)
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

revoke all on function public.ver_serie(uuid) from public, anon;
grant execute on function public.ver_serie(uuid) to authenticated;
notify pgrst, 'reload schema';
