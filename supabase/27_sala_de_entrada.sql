-- =====================================================================
-- 27_sala_de_entrada.sql — SALA DE ENTRADA do PvP (Batalha, Cerco e Campeonato)
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Rode DEPOIS do 26_campeonato.sql. Pode rodar de novo.
--
-- O QUE MUDA
-- 1) A pessoa escolhe o lado (Heroes ou Monsters) na própria sala, vendo QUEM está entrando de cada lado.
-- 2) BATALHA e CERCO: fila separada por modo (fila_pvp.modo). Cerco pela fila é amistoso (não vale troféu).
--    fila_lobby: quem está na fila agora, de cada lado (nome e foto).
-- 3) CAMPEONATO: a sala de espera dura 2 MINUTOS. Se demorar para lotar, os bots vão entrando aos poucos
--    (depois de 15 s) até completar as 16 vagas no fim dos 2 minutos. Quando uma pessoa entra num lado, um bot
--    daquele lado sai (pessoas reais nunca ficam de fora por causa de bot). Lado com 8 PESSOAS = lotado.
--    espiar_campeonato: mostra a sala aberta antes de entrar. entrar_campeonato também TROCA de lado.
-- 4) CHAT DA SALA: chat_sala_enviar / chat_sala_ler (salas 'batalha', 'cerco', 'campeonato').
-- =====================================================================

-- ---------------------------------------------------------------- BATALHA / CERCO: fila por modo
alter table public.fila_pvp add column if not exists modo text not null default 'normal';

-- (o antigo, usado pelo site e por versões antigas do jogo: agora só junta quem está no modo normal)
create or replace function public.procurar_partida_plat(p_lado text, p_niveis jsonb, p_plat text) returns json
language plpgsql security definer set search_path = public as $$
declare outro public.fila_pvp; s public.partidas_pvp;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_lado not in ('heroes','monsters') then raise exception 'lado inválido'; end if;
  select * into s from partidas_pvp
   where auth.uid() in (heroes, monsters) and not finalizada and plataforma = p_plat
     and criada_em > now() - interval '40 seconds'
   order by criada_em desc limit 1;
  if s.id is not null then delete from fila_pvp where jogador = auth.uid(); return sala_json(s); end if;
  delete from fila_pvp where criado_em < now() - interval '20 seconds';
  select * into outro from fila_pvp
   where lado <> p_lado and plataforma = p_plat and modo = 'normal' and jogador <> auth.uid()
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
  insert into fila_pvp (jogador, lado, niveis, plataforma, modo) values (auth.uid(), p_lado, coalesce(p_niveis, '{}'), p_plat, 'normal')
  on conflict (jogador) do update set lado = excluded.lado, niveis = excluded.niveis, plataforma = excluded.plataforma,
                                      modo = 'normal', criado_em = now();
  return null;
end $$;
revoke all on function public.procurar_partida_plat(text, jsonb, text) from public, anon, authenticated;

-- GODOT com modo: 'normal' (Batalha, vale troféus) ou 'cerco' (amistoso)
create or replace function public.procurar_partida_modo(p_lado text, p_modo text) returns json
language plpgsql security definer set search_path = public as $$
declare outro public.fila_pvp; s public.partidas_pvp; meus jsonb;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_lado not in ('heroes','monsters') then raise exception 'lado inválido'; end if;
  if p_modo not in ('normal','cerco') then raise exception 'modo inválido'; end if;
  select * into s from partidas_pvp
   where auth.uid() in (heroes, monsters) and not finalizada and plataforma = 'godot' and modo = p_modo
     and criada_em > now() - interval '40 seconds'
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

-- sai da fila (se alguém tinha acabado de te achar, devolve a sala)
create or replace function public.sair_da_fila_modo(p_modo text) returns json
language plpgsql security definer set search_path = public as $$
declare s public.partidas_pvp;
begin
  if auth.uid() is null then return null; end if;
  delete from fila_pvp where jogador = auth.uid();
  select * into s from partidas_pvp
   where auth.uid() in (heroes, monsters) and not finalizada and plataforma = 'godot' and modo = p_modo
     and criada_em > now() - interval '40 seconds'
   order by criada_em desc limit 1;
  if s.id is not null then return sala_json(s); end if;
  return null;
end $$;

-- quem está na fila agora (os dois lados), para a sala de entrada mostrar
create or replace function public.fila_lobby(p_modo text) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('nome', split_part(p.nome, ' ', 1), 'foto', p.avatar_url, 'lado', f.lado,
                                             'eu', f.jogador = auth.uid()) order by f.criado_em), '[]')
    from fila_pvp f join perfis p on p.id = f.jogador
   where auth.uid() is not null and f.plataforma = 'godot' and f.modo = p_modo
     and f.criado_em > now() - interval '8 seconds';
$$;

-- ---------------------------------------------------------------- CAMPEONATO: 2 minutos + bots aos poucos
alter table public.campeonatos alter column comeca_em set default now() + interval '120 seconds';
alter table public.campeonatos add column if not exists bots jsonb not null default '[]';   -- bots que já entraram na sala

-- coloca/tira bots da sala conforme o tempo passa (15 s só pessoas; até 110 s completa as vagas)
create or replace function public._camp_encher(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c public.campeonatos; e float; ld text; reais int; tem int; alvo int; b jsonb; i int; tirar int;
begin
  select * into c from campeonatos where id = p_id;
  if c.id is null or c.status <> 'aberto' then return; end if;
  e := greatest(0.0, least(1.0, (extract(epoch from now() - c.criado_em)::float - 15.0) / 95.0));
  b := c.bots;
  foreach ld in array array['heroes','monsters'] loop
    select count(*) into reais from campeonato_inscritos ci where ci.campeonato = p_id and ci.lado = ld;
    select count(*) into tem from jsonb_array_elements(b) x where x ->> 'lado' = ld;
    alvo := floor((8 - least(reais, 8)) * e);
    -- uma pessoa entrou e não cabe mais: o bot mais novo daquele lado sai
    while tem > 8 - least(reais, 8) loop
      tirar := -1;
      for i in reverse jsonb_array_length(b) - 1 .. 0 loop
        if tirar < 0 and b -> i ->> 'lado' = ld then tirar := i; end if;
      end loop;
      exit when tirar < 0;
      b := b - tirar;
      tem := tem - 1;
    end loop;
    while tem < alvo loop
      b := b || jsonb_build_array(_camp_bot(ld));
      tem := tem + 1;
    end loop;
  end loop;
  if b is distinct from c.bots then
    update campeonatos set bots = b, atualizado_em = now() where id = p_id;
  end if;
end $$;

-- começar: igual ao 26, mas os bots que estavam na sala ficam com os mesmos nomes na árvore
create or replace function public._camp_comecar(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare
  ordem int[] := array[0,4,2,6,1,5,3,7];
  hs jsonb; ms jsonb; nh int; nm int; v jsonb := '[]'; i int; m int; bs jsonb; bh int := 0; bm int := 0; x jsonb;
begin
  select coalesce(jsonb_agg(x2 order by x2.entrou_em), '[]') into hs from (
    select i2.jogador, i2.entrou_em, p.nome, p.avatar_url from campeonato_inscritos i2 join perfis p on p.id = i2.jogador
     where i2.campeonato = p_id and i2.lado = 'heroes') x2;
  select coalesce(jsonb_agg(x2 order by x2.entrou_em), '[]') into ms from (
    select i2.jogador, i2.entrou_em, p.nome, p.avatar_url from campeonato_inscritos i2 join perfis p on p.id = i2.jogador
     where i2.campeonato = p_id and i2.lado = 'monsters') x2;
  select bots into bs from campeonatos where id = p_id;
  nh := least(jsonb_array_length(hs), 8); nm := least(jsonb_array_length(ms), 8);
  for i in 0..15 loop                                   -- começa tudo com bot (pares = Heroes, ímpares = Monsters)
    v := v || jsonb_build_array(_camp_bot(case when i % 2 = 0 then 'heroes' else 'monsters' end));
  end loop;
  for i in 1..nh loop
    m := ordem[i];
    v := jsonb_set(v, array[(m * 2)::text], (v -> (m * 2)) || jsonb_build_object('jogador', hs -> (i - 1) ->> 'jogador',
      'nome', coalesce(nullif(split_part(hs -> (i - 1) ->> 'nome', ' ', 1), ''), 'Jogador'), 'foto', coalesce(hs -> (i - 1) ->> 'avatar_url', ''), 'tipo', 'pessoa'));
  end loop;
  for i in 1..nm loop
    m := ordem[i];
    v := jsonb_set(v, array[(m * 2 + 1)::text], (v -> (m * 2 + 1)) || jsonb_build_object('jogador', ms -> (i - 1) ->> 'jogador',
      'nome', coalesce(nullif(split_part(ms -> (i - 1) ->> 'nome', ' ', 1), ''), 'Jogador'), 'foto', coalesce(ms -> (i - 1) ->> 'avatar_url', ''), 'tipo', 'pessoa'));
  end loop;
  -- as vagas de bot recebem os bots que já estavam na sala (mesmo nome e retrato)
  for x in select * from jsonb_array_elements(coalesce(bs, '[]')) loop
    for i in 0..15 loop
      if v -> i ->> 'tipo' = 'bot' and v -> i ->> 'lado' = x ->> 'lado' and not coalesce((v -> i ->> 'da_sala')::boolean, false) then
        v := jsonb_set(v, array[i::text], (v -> i) || jsonb_build_object('nome', x ->> 'nome', 'personagem', x ->> 'personagem', 'da_sala', true));
        exit;
      end if;
    end loop;
  end loop;
  update campeonatos set status = 'andando', vagas = v, vencedores = _camp_vazio(), lutas = _camp_lutas_vazias(),
    fase = 0, fase_ini = now(), atualizado_em = now() where id = p_id;
end $$;

-- avançar: o pedaço da sala de espera ganhou os bots aos poucos (o resto é o mesmo do 26)
create or replace function public._camp_avancar(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare
  c public.campeonatos; f int; n int; m int; par int[]; va jsonb; vb jsonb; ra boolean; rb boolean;
  luta jsonb; s public.partidas_pvp; venc int; tudo boolean := true; prazo boolean; lado_a text; lado_quer text; j int;
  premios int[] := array[40, 70, 110, 300]; quem uuid; gente int;
begin
  select * into c from campeonatos where id = p_id for update;
  if c.id is null then return; end if;
  if c.status = 'aberto' then
    select count(*) into gente from campeonato_inscritos where campeonato = p_id;
    if gente = 0 and now() >= c.comeca_em then                 -- todo mundo saiu: a sala fecha
      delete from campeonatos where id = p_id;
      return;
    end if;
    if now() >= c.comeca_em or gente >= 16 then
      perform _camp_comecar(p_id);
    else
      perform _camp_encher(p_id);
    end if;
    return;
  end if;
  if c.status <> 'andando' then return; end if;
  f := c.fase; n := jsonb_array_length(c.vencedores -> f);
  prazo := now() > c.fase_ini + interval '8 minutes';
  for m in 0..n - 1 loop
    if (c.vencedores -> f ->> m)::int >= 0 then continue; end if;
    par := _camp_lutadores(c, f, m);
    va := c.vagas -> par[1]; vb := c.vagas -> par[2];
    ra := va ->> 'tipo' = 'pessoa'; rb := vb ->> 'tipo' = 'pessoa';
    luta := c.lutas -> f -> m;
    venc := -1;
    if ra and rb then
      if luta ? 'sala' then
        select * into s from partidas_pvp where id = (luta ->> 'sala')::uuid;
        if s.finalizada then
          if s.vencedor = 'empate' then venc := par[1 + floor(random() * 2)::int];
          else
            quem := case when s.vencedor = 'heroes' then s.heroes else s.monsters end;
            venc := case when (va ->> 'jogador')::uuid = quem then par[1] else par[2] end;
          end if;
        end if;
      end if;
      if venc < 0 and prazo then venc := par[1 + floor(random() * 2)::int]; end if;
    elsif ra or rb then
      if luta ? 'relato' then
        venc := case when (luta ->> 'relato' = 'venceu') = ra then par[1] else par[2] end;
      elsif prazo then
        venc := case when ra then par[2] else par[1] end;
      end if;
    else
      continue;
    end if;
    if venc >= 0 then
      c.vencedores := jsonb_set(c.vencedores, array[f::text, m::text], to_jsonb(venc));
    else
      tudo := false;
    end if;
  end loop;
  if not tudo then
    update campeonatos set vencedores = c.vencedores, atualizado_em = now() where id = p_id;
    return;
  end if;
  m := 0;
  while m < n loop
    if n = 1 then
      if (c.vencedores -> f ->> 0)::int < 0 then
        par := _camp_lutadores(c, f, 0);
        c.vencedores := jsonb_set(c.vencedores, '{3,0}', to_jsonb(par[1 + floor(random() * 2)::int]));
      end if;
      exit;
    end if;
    lado_a := null;
    if (c.vencedores -> f ->> m)::int >= 0 then lado_a := c.vagas -> ((c.vencedores -> f ->> m)::int) ->> 'lado';
    elsif (c.vencedores -> f ->> (m + 1))::int >= 0 then
      lado_a := case when c.vagas -> ((c.vencedores -> f ->> (m + 1))::int) ->> 'lado' = 'heroes' then 'monsters' else 'heroes' end;
    else lado_a := case when random() < 0.5 then 'heroes' else 'monsters' end; end if;
    for j in 0..1 loop
      if (c.vencedores -> f ->> (m + j))::int < 0 then
        par := _camp_lutadores(c, f, m + j);
        lado_quer := case when j = 0 then lado_a when lado_a = 'heroes' then 'monsters' else 'heroes' end;
        if c.vagas -> par[1] ->> 'lado' = lado_quer then venc := par[1]; else venc := par[2]; end if;
        c.vencedores := jsonb_set(c.vencedores, array[f::text, (m + j)::text], to_jsonb(venc));
      end if;
    end loop;
    m := m + 2;
  end loop;
  for m in 0..n - 1 loop
    va := c.vagas -> ((c.vencedores -> f ->> m)::int);
    if va ->> 'tipo' = 'pessoa' then
      update perfis set moedas = moedas + premios[f + 1], atualizado_em = now() where id = (va ->> 'jogador')::uuid;
    end if;
  end loop;
  update campeonatos set vencedores = c.vencedores, fase = f + 1, fase_ini = now(),
    status = case when f + 1 >= 4 then 'fim' else 'andando' end, atualizado_em = now() where id = p_id;
end $$;

-- o que a tela recebe: "inscritos" agora traz também os bots da sala (com o retrato do personagem)
create or replace function public._camp_json(p_id uuid) returns json language sql stable security definer set search_path = public as $$
  select json_build_object('id', c.id, 'status', c.status, 'fase', c.fase,
    'falta', greatest(0, extract(epoch from c.comeca_em - now()))::int,
    'prazo', case when c.fase_ini is null then 0 else greatest(0, extract(epoch from c.fase_ini + interval '8 minutes' - now()))::int end,
    'vagas', c.vagas, 'vencedores', c.vencedores, 'lutas', c.lutas,
    'reais', json_build_object(
       'heroes', (select count(*) from campeonato_inscritos i where i.campeonato = c.id and i.lado = 'heroes'),
       'monsters', (select count(*) from campeonato_inscritos i where i.campeonato = c.id and i.lado = 'monsters')),
    'inscritos', (select coalesce(json_agg(gg.g order by gg.ordem), '[]') from (
        select json_build_object('nome', split_part(p.nome, ' ', 1), 'foto', p.avatar_url, 'lado', i.lado,
                                 'eu', i.jogador = auth.uid(), 'personagem', '') as g, extract(epoch from i.entrou_em) as ordem
          from campeonato_inscritos i join perfis p on p.id = i.jogador where i.campeonato = c.id
        union all
        select json_build_object('nome', b ->> 'nome', 'foto', '', 'lado', b ->> 'lado', 'eu', false,
                                 'personagem', b ->> 'personagem'), extract(epoch from c.criado_em) + 15 + k
          from jsonb_array_elements(c.bots) with ordinality as t(b, k)) gg))
  from campeonatos c where c.id = p_id;
$$;

-- entrar (ou TROCAR de lado ainda na sala de espera). Lado com 8 pessoas = 'lado lotado'.
create or replace function public.entrar_campeonato(p_lado text) returns json
language plpgsql security definer set search_path = public as $$
declare cid uuid; st text; meu_lado text;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_lado not in ('heroes','monsters') then raise exception 'lado inválido'; end if;
  cid := _camp_meu();
  if cid is not null then
    select status into st from campeonatos where id = cid;
    if st = 'aberto' then
      select lado into meu_lado from campeonato_inscritos where campeonato = cid and jogador = auth.uid();
      if meu_lado is distinct from p_lado then
        if (select count(*) from campeonato_inscritos i where i.campeonato = cid and i.lado = p_lado) >= 8 then
          raise exception 'lado lotado';
        end if;
        update campeonato_inscritos set lado = p_lado, entrou_em = now() where campeonato = cid and jogador = auth.uid();
      end if;
      perform _camp_avancar(cid); return _camp_json(cid);
    end if;
    if st = 'andando' then perform _camp_avancar(cid); return _camp_json(cid); end if;
  end if;
  select c.id into cid from campeonatos c
   where c.status = 'aberto' and c.comeca_em > now() + interval '3 seconds'
     and (select count(*) from campeonato_inscritos i where i.campeonato = c.id and i.lado = p_lado) < 8
   order by c.criado_em limit 1 for update skip locked;
  if cid is null then
    if exists (select 1 from campeonatos c where c.status = 'aberto' and c.comeca_em > now() + interval '3 seconds'
                 and (select count(*) from campeonato_inscritos i where i.campeonato = c.id and i.lado = p_lado) >= 8
                 and (select count(*) from campeonato_inscritos i where i.campeonato = c.id and i.lado <> p_lado) < 8) then
      raise exception 'lado lotado';
    end if;
    insert into campeonatos default values returning id into cid;
  end if;
  insert into campeonato_inscritos (campeonato, jogador, lado) values (cid, auth.uid(), p_lado) on conflict do nothing;
  perform _camp_avancar(cid);
  return _camp_json(cid);
end $$;

-- ver a sala antes de entrar: o meu campeonato (se já entrei) ou o aberto mais antigo (ou uma sala vazia)
create or replace function public.espiar_campeonato() returns json
language plpgsql security definer set search_path = public as $$
declare cid uuid := _camp_meu(); st text;
begin
  if auth.uid() is null then return null; end if;
  if cid is not null then
    select status into st from campeonatos where id = cid;
    if st in ('aberto','andando') then perform _camp_avancar(cid); return _camp_json(cid); end if;
  end if;
  select c.id into cid from campeonatos c
   where c.status = 'aberto' and c.comeca_em > now() + interval '3 seconds' order by c.criado_em limit 1;
  if cid is null then
    return json_build_object('status', 'vazio', 'falta', 120, 'inscritos', '[]'::json,
                             'reais', json_build_object('heroes', 0, 'monsters', 0));
  end if;
  perform _camp_avancar(cid);
  return _camp_json(cid);
end $$;

-- ---------------------------------------------------------------- CHAT DA SALA DE ENTRADA
create table if not exists public.chat_sala (
  id bigserial primary key,
  sala text not null check (sala in ('batalha','cerco','campeonato')),
  autor uuid references public.perfis(id) on delete cascade,
  nome text not null,
  foto text,
  lado text,
  texto text not null,
  criado_em timestamptz not null default now()
);
create index if not exists chat_sala_sala_id on public.chat_sala (sala, id);
alter table public.chat_sala enable row level security;            -- só pelas funções

create or replace function public.chat_sala_enviar(p_sala text, p_texto text, p_lado text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare t text := trim(p_texto); ultima timestamptz; novo bigint; eu public.perfis;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_sala not in ('batalha','cerco','campeonato') then raise exception 'sala inválida'; end if;
  if char_length(t) < 1 or char_length(t) > 120 then raise exception 'mensagem de 1 a 120 letras'; end if;
  select max(criado_em) into ultima from chat_sala where autor = auth.uid();
  if ultima > now() - interval '1.5 seconds' then raise exception 'calma! espere um pouquinho'; end if;
  select * into eu from perfis where id = auth.uid();
  insert into chat_sala (sala, autor, nome, foto, lado, texto)
  values (p_sala, auth.uid(), coalesce(nullif(split_part(eu.nome, ' ', 1), ''), 'Jogador'), eu.avatar_url,
          case when p_lado in ('heroes','monsters') then p_lado else eu.lado_atual end, t)
  returning id into novo;
  if random() < 0.05 then delete from chat_sala where criado_em < now() - interval '2 hours'; end if;   -- faxina
  return novo;
end $$;

-- as mensagens novas (id > p_depois), no máximo as 30 últimas da última hora
create or replace function public.chat_sala_ler(p_sala text, p_depois bigint default 0) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', x.id, 'nome', x.nome, 'foto', x.foto, 'lado', x.lado, 'texto', x.texto,
                                             'eu', x.autor = auth.uid()) order by x.id), '[]')
    from (select * from chat_sala
           where auth.uid() is not null and sala = p_sala and id > coalesce(p_depois, 0)
             and criado_em > now() - interval '1 hour'
           order by id desc limit 30) x;
$$;

-- ---------------------------------------------------------------- permissões
revoke all on function public._camp_encher(uuid), public._camp_comecar(uuid), public._camp_avancar(uuid), public._camp_json(uuid)
  from public, anon, authenticated;
revoke all on function public.procurar_partida_modo(text, text), public.sair_da_fila_modo(text), public.fila_lobby(text),
  public.entrar_campeonato(text), public.espiar_campeonato(), public.chat_sala_enviar(text, text, text),
  public.chat_sala_ler(text, bigint) from public, anon;
grant execute on function public.procurar_partida_modo(text, text), public.sair_da_fila_modo(text), public.fila_lobby(text),
  public.entrar_campeonato(text), public.espiar_campeonato(), public.chat_sala_enviar(text, text, text),
  public.chat_sala_ler(text, bigint) to authenticated;
notify pgrst, 'reload schema';
