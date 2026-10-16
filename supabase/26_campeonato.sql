-- =====================================================================
-- 26_campeonato.sql — CAMPEONATO PvP ONLINE (16 vagas: 8 Heroes + 8 Monsters, mata-mata)
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Rode DEPOIS do 19_cerco.sql. Pode rodar de novo.
--
-- COMO FUNCIONA
-- 1) SALA DE ESPERA: quem toca em "Campeonato" entra num campeonato ABERTO do lado dele (cada lado tem 8 vagas;
--    lado lotado = abre outro campeonato). O campeonato começa quando completar 16 pessoas OU 60 s depois de abrir.
-- 2) EQUILÍBRIO (de 1 a 16 pessoas): as pessoas reais são pareadas Heroes x Monsters nas oitavas primeiro; essas
--    lutas são espalhadas pela árvore (uma em cada quarto da chave: posições 0,4,2,6,1,5,3,7). Quem sobrar do lado
--    com mais gente pega um bot. BOTS SÓ COMPLETAM AS VAGAS QUE FALTAM (8 x 8 reais = nenhum bot).
-- 3) LUTAS: pessoa x pessoa = PvP online de verdade (amistoso: não mexe em troféus); pessoa x bot = o aparelho joga e
--    conta o resultado (campeonato_relatar_bot); bot x bot = o servidor decide.
-- 4) A FASE FECHA quando todas as lutas acabam ou no PRAZO (8 min): quem não jogou perde por W.O.
--    Bot x bot completa a dupla de lutas para a próxima ser Heroes x Monsters sempre que der.
--    Duas pessoas do MESMO lado se encontrando (fases adiante): a de baixo joga com o lado oposto naquela luta.
-- 5) PRÊMIO em moedas por fase vencida (pago aqui): 40 / 70 / 110 / 300 (campeão).
-- O estado avança "preguiçoso": cada vez que alguém pergunta (estado_campeonato, a cada 2 s na tela).
-- =====================================================================

create table if not exists public.campeonatos (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'aberto' check (status in ('aberto','andando','fim')),
  criado_em timestamptz not null default now(),
  comeca_em timestamptz not null default now() + interval '60 seconds',
  fase integer not null default 0,
  fase_ini timestamptz,
  vagas jsonb not null default '[]',          -- 16 x {jogador, nome, foto, lado, tipo ('pessoa'|'bot'), personagem}
  vencedores jsonb,                           -- [[8],[4],[2],[1]] índice da vaga vencedora (-1 = em aberto)
  lutas jsonb,                                -- mesma forma: {sala, relato ('venceu'|'perdeu')}
  atualizado_em timestamptz not null default now()
);
create table if not exists public.campeonato_inscritos (
  campeonato uuid not null references public.campeonatos(id) on delete cascade,
  jogador uuid not null references public.perfis(id) on delete cascade,
  lado text not null check (lado in ('heroes','monsters')),
  entrou_em timestamptz not null default now(),
  primary key (campeonato, jogador)
);
create index if not exists campeonatos_status on public.campeonatos (status, criado_em);
alter table public.campeonatos enable row level security;
alter table public.campeonato_inscritos enable row level security;

-- ---------------------------------------------------------------- ajudantes
create or replace function public._camp_lutadores(c public.campeonatos, f integer, m integer) returns integer[]
language sql immutable as $$
  select case when f = 0 then array[m * 2, m * 2 + 1]
              else array[(c.vencedores -> (f - 1) ->> (m * 2))::int, (c.vencedores -> (f - 1) ->> (m * 2 + 1))::int] end;
$$;

create or replace function public._camp_vazio() returns jsonb language sql immutable as $$
  select '[[-1,-1,-1,-1,-1,-1,-1,-1],[-1,-1,-1,-1],[-1,-1],[-1]]'::jsonb;
$$;
create or replace function public._camp_lutas_vazias() returns jsonb language sql immutable as $$
  select '[[{},{},{},{},{},{},{},{}],[{},{},{},{}],[{},{}],[{}]]'::jsonb;
$$;

-- bot com nome de gente e o retrato de um personagem do lado dele
create or replace function public._camp_bot(p_lado text) returns jsonb language plpgsql volatile as $$
declare
  nomes text[] := array['Lucas','Gabriel','Rafa','Bia','Pedro','Júlia','Davi','Mateus','Ana','Enzo','Lara','Theo',
                        'Guilherme','Sofia','Caio','Nina','Arthur','Malu','Bruno','Lívia','Igor','Yasmin','Vitor','Duda'];
  sobs text[] := array['','','_BR','Gamer','Pro','XD','07','99','_GG','Rei','TV','2010'];
  h text[] := array['elara','nick','arqueiro','protetor','mago','magoFogo','sentinela','engenheiro'];
  mo text[] := array['esqueletoBlack','esqueleto','esqueletoFogo','esqueletoArqueiro','esqueletoBombardeiro','esqueletoProtetor','esqueletoMago','esqueletoTita'];
  p text[] := case when p_lado = 'heroes' then h else mo end;
begin
  return jsonb_build_object('jogador', null,
    'nome', nomes[1 + floor(random() * array_length(nomes, 1))::int] || sobs[1 + floor(random() * array_length(sobs, 1))::int]
            || case when random() < 0.35 then (10 + floor(random() * 90))::int::text else '' end,
    'foto', '', 'lado', p_lado, 'tipo', 'bot', 'personagem', p[1 + floor(random() * array_length(p, 1))::int]);
end $$;

-- ---------------------------------------------------------------- começar (monta a árvore equilibrada)
create or replace function public._camp_comecar(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare
  ordem int[] := array[0,4,2,6,1,5,3,7];
  hs jsonb; ms jsonb; nh int; nm int; k int; v jsonb := '[]'; i int; m int;
begin
  select coalesce(jsonb_agg(x order by x.entrou_em), '[]') into hs from (
    select i2.jogador, i2.entrou_em, p.nome, p.avatar_url from campeonato_inscritos i2 join perfis p on p.id = i2.jogador
     where i2.campeonato = p_id and i2.lado = 'heroes') x;
  select coalesce(jsonb_agg(x order by x.entrou_em), '[]') into ms from (
    select i2.jogador, i2.entrou_em, p.nome, p.avatar_url from campeonato_inscritos i2 join perfis p on p.id = i2.jogador
     where i2.campeonato = p_id and i2.lado = 'monsters') x;
  nh := jsonb_array_length(hs); nm := jsonb_array_length(ms); k := least(nh, nm);
  for i in 0..15 loop                                   -- começa tudo com bot (pares = Heroes, ímpares = Monsters)
    v := v || jsonb_build_array(_camp_bot(case when i % 2 = 0 then 'heroes' else 'monsters' end));
  end loop;
  for i in 1..nh loop                                   -- pessoas Heroes nas lutas espalhadas (as k primeiras contra pessoas)
    m := ordem[i];
    v := jsonb_set(v, array[(m * 2)::text], (v -> (m * 2)) || jsonb_build_object('jogador', hs -> (i - 1) ->> 'jogador',
      'nome', coalesce(nullif(split_part(hs -> (i - 1) ->> 'nome', ' ', 1), ''), 'Jogador'), 'foto', coalesce(hs -> (i - 1) ->> 'avatar_url', ''), 'tipo', 'pessoa'));
  end loop;
  for i in 1..nm loop
    m := ordem[i];
    v := jsonb_set(v, array[(m * 2 + 1)::text], (v -> (m * 2 + 1)) || jsonb_build_object('jogador', ms -> (i - 1) ->> 'jogador',
      'nome', coalesce(nullif(split_part(ms -> (i - 1) ->> 'nome', ' ', 1), ''), 'Jogador'), 'foto', coalesce(ms -> (i - 1) ->> 'avatar_url', ''), 'tipo', 'pessoa'));
  end loop;
  update campeonatos set status = 'andando', vagas = v, vencedores = _camp_vazio(), lutas = _camp_lutas_vazias(),
    fase = 0, fase_ini = now(), atualizado_em = now() where id = p_id;
end $$;

-- ---------------------------------------------------------------- avançar (chamado a cada pergunta)
create or replace function public._camp_avancar(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare
  c public.campeonatos; f int; n int; m int; par int[]; va jsonb; vb jsonb; ra boolean; rb boolean;
  luta jsonb; s public.partidas_pvp; venc int; tudo boolean := true; prazo boolean; lado_a text; lado_quer text; j int;
  premios int[] := array[40, 70, 110, 300]; quem uuid;
begin
  select * into c from campeonatos where id = p_id for update;
  if c.id is null then return; end if;
  if c.status = 'aberto' then
    if now() >= c.comeca_em or (select count(*) from campeonato_inscritos where campeonato = p_id) >= 16 then
      perform _camp_comecar(p_id);
    end if;
    return;
  end if;
  if c.status <> 'andando' then return; end if;
  f := c.fase; n := jsonb_array_length(c.vencedores -> f);
  prazo := now() > c.fase_ini + interval '8 minutes';
  -- 1) lutas com pessoa: resultado da sala (pessoa x pessoa) ou o relato (pessoa x bot)
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
      if venc < 0 and prazo then venc := par[1 + floor(random() * 2)::int]; end if;   -- ninguém terminou: sorteio
    elsif ra or rb then
      if luta ? 'relato' then
        venc := case when (luta ->> 'relato' = 'venceu') = ra then par[1] else par[2] end;
      elsif prazo then
        venc := case when ra then par[2] else par[1] end;                               -- não jogou: W.O. para o bot
      end if;
    else
      continue;                                                                          -- bot x bot: depois
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
  -- 2) bot x bot: completa cada dupla de lutas com um Heroes e um Monsters (quando der)
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
        -- (o lado que esta luta precisa: calculado antes do IF — CASE dentro da condição do IF quebra o PL/pgSQL)
        lado_quer := case when j = 0 then lado_a when lado_a = 'heroes' then 'monsters' else 'heroes' end;
        if c.vagas -> par[1] ->> 'lado' = lado_quer then venc := par[1]; else venc := par[2]; end if;
        c.vencedores := jsonb_set(c.vencedores, array[f::text, (m + j)::text], to_jsonb(venc));
      end if;
    end loop;
    m := m + 2;
  end loop;
  -- 3) prêmio para as pessoas que venceram esta fase
  for m in 0..n - 1 loop
    va := c.vagas -> ((c.vencedores -> f ->> m)::int);
    if va ->> 'tipo' = 'pessoa' then
      update perfis set moedas = moedas + premios[f + 1], atualizado_em = now() where id = (va ->> 'jogador')::uuid;
    end if;
  end loop;
  -- 4) próxima fase (ou fim)
  update campeonatos set vencedores = c.vencedores, fase = f + 1, fase_ini = now(),
    status = case when f + 1 >= 4 then 'fim' else 'andando' end, atualizado_em = now() where id = p_id;
end $$;

-- ---------------------------------------------------------------- o que a tela recebe
create or replace function public._camp_json(p_id uuid) returns json language sql stable security definer set search_path = public as $$
  select json_build_object('id', c.id, 'status', c.status, 'fase', c.fase,
    'falta', greatest(0, extract(epoch from c.comeca_em - now()))::int,
    'prazo', case when c.fase_ini is null then 0 else greatest(0, extract(epoch from c.fase_ini + interval '8 minutes' - now()))::int end,
    'vagas', c.vagas, 'vencedores', c.vencedores, 'lutas', c.lutas,
    'inscritos', (select coalesce(json_agg(json_build_object('nome', split_part(p.nome, ' ', 1), 'foto', p.avatar_url, 'lado', i.lado,
                    'eu', i.jogador = auth.uid()) order by i.entrou_em), '[]')
                  from campeonato_inscritos i join perfis p on p.id = i.jogador where i.campeonato = c.id))
  from campeonatos c where c.id = p_id;
$$;

-- meu campeonato atual (aberto, andando, ou que acabou há pouco)
create or replace function public._camp_meu() returns uuid language sql stable security definer set search_path = public as $$
  select c.id from campeonatos c join campeonato_inscritos i on i.campeonato = c.id and i.jogador = auth.uid()
   where c.status in ('aberto','andando') or c.atualizado_em > now() - interval '10 minutes'
   order by c.criado_em desc limit 1;
$$;

-- ---------------------------------------------------------------- chamadas do jogo
create or replace function public.entrar_campeonato(p_lado text) returns json
language plpgsql security definer set search_path = public as $$
declare cid uuid; st text;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_lado not in ('heroes','monsters') then raise exception 'lado inválido'; end if;
  cid := _camp_meu();
  if cid is not null then
    select status into st from campeonatos where id = cid;
    if st in ('aberto','andando') then perform _camp_avancar(cid); return _camp_json(cid); end if;
  end if;
  -- um campeonato aberto com vaga do meu lado (o mais antigo); senão, abre um novo
  select c.id into cid from campeonatos c
   where c.status = 'aberto' and c.comeca_em > now() + interval '3 seconds'
     and (select count(*) from campeonato_inscritos i where i.campeonato = c.id and i.lado = p_lado) < 8
   order by c.criado_em limit 1 for update skip locked;
  if cid is null then
    insert into campeonatos default values returning id into cid;
  end if;
  insert into campeonato_inscritos (campeonato, jogador, lado) values (cid, auth.uid(), p_lado) on conflict do nothing;
  perform _camp_avancar(cid);
  return _camp_json(cid);
end $$;

create or replace function public.sair_campeonato() returns void
language plpgsql security definer set search_path = public as $$
declare cid uuid := _camp_meu();
begin
  delete from campeonato_inscritos i using campeonatos c
   where i.campeonato = c.id and c.id = cid and c.status = 'aberto' and i.jogador = auth.uid();
end $$;

create or replace function public.estado_campeonato() returns json
language plpgsql security definer set search_path = public as $$
declare cid uuid := _camp_meu();
begin
  if cid is null then return null; end if;
  perform _camp_avancar(cid);
  return _camp_json(cid);
end $$;

-- minha luta desta fase contra uma PESSOA: devolve a sala (cria na 1ª vez). O de cima fica com o lado dele;
-- se os dois forem do mesmo lado, o de baixo joga com o lado oposto.
create or replace function public.campeonato_sala() returns json
language plpgsql security definer set search_path = public as $$
declare c public.campeonatos; cid uuid := _camp_meu(); f int; m int; par int[]; va jsonb; vb jsonb;
  ja uuid; jb uuid; la text; s public.partidas_pvp; h uuid; mo uuid;
begin
  if cid is null then return null; end if;
  select * into c from campeonatos where id = cid for update;
  if c.status <> 'andando' then return null; end if;
  f := c.fase;
  for m in 0..jsonb_array_length(c.vencedores -> f) - 1 loop
    par := _camp_lutadores(c, f, m);
    va := c.vagas -> par[1]; vb := c.vagas -> par[2];
    if auth.uid()::text not in (coalesce(va ->> 'jogador', ''), coalesce(vb ->> 'jogador', '')) then continue; end if;
    if va ->> 'tipo' <> 'pessoa' or vb ->> 'tipo' <> 'pessoa' or (c.vencedores -> f ->> m)::int >= 0 then return null; end if;
    if c.lutas -> f -> m ? 'sala' then
      select * into s from partidas_pvp where id = (c.lutas -> f -> m ->> 'sala')::uuid;
      return sala_json(s);
    end if;
    ja := (va ->> 'jogador')::uuid; jb := (vb ->> 'jogador')::uuid; la := va ->> 'lado';
    h := case when la = 'heroes' then ja else jb end;
    mo := case when la = 'heroes' then jb else ja end;
    insert into partidas_pvp (heroes, monsters, semente, niveis_heroes, niveis_monsters, plataforma, amistoso, modo)
    values (h, mo, floor(random() * 4294967295)::bigint,
      coalesce((select jsonb_object_agg(personagem, nivel) from personagens_jogador where jogador = h), '{}'::jsonb),
      coalesce((select jsonb_object_agg(personagem, nivel) from personagens_jogador where jogador = mo), '{}'::jsonb),
      'godot', true, 'normal')
    returning * into s;
    update campeonatos set lutas = jsonb_set(lutas, array[f::text, m::text], jsonb_build_object('sala', s.id)), atualizado_em = now()
     where id = cid;
    return sala_json(s);
  end loop;
  return null;
end $$;

-- resultado da minha luta contra um BOT (o aparelho jogou)
create or replace function public.campeonato_relatar_bot(p_venceu boolean) returns json
language plpgsql security definer set search_path = public as $$
declare c public.campeonatos; cid uuid := _camp_meu(); f int; m int; par int[]; va jsonb; vb jsonb;
begin
  if cid is null then return null; end if;
  select * into c from campeonatos where id = cid for update;
  if c.status <> 'andando' then return _camp_json(cid); end if;
  f := c.fase;
  for m in 0..jsonb_array_length(c.vencedores -> f) - 1 loop
    par := _camp_lutadores(c, f, m);
    va := c.vagas -> par[1]; vb := c.vagas -> par[2];
    if auth.uid()::text in (coalesce(va ->> 'jogador', ''), coalesce(vb ->> 'jogador', ''))
       and (va ->> 'tipo' = 'bot' or vb ->> 'tipo' = 'bot') and not (c.lutas -> f -> m ? 'relato') then
      update campeonatos set lutas = jsonb_set(lutas, array[f::text, m::text],
        jsonb_build_object('relato', case when p_venceu then 'venceu' else 'perdeu' end)), atualizado_em = now() where id = cid;
    end if;
  end loop;
  perform _camp_avancar(cid);
  return _camp_json(cid);
end $$;

revoke all on function public._camp_lutadores(public.campeonatos, integer, integer), public._camp_bot(text),
  public._camp_comecar(uuid), public._camp_avancar(uuid), public._camp_json(uuid), public._camp_meu() from public, anon, authenticated;
revoke all on function public.entrar_campeonato(text), public.sair_campeonato(), public.estado_campeonato(),
  public.campeonato_sala(), public.campeonato_relatar_bot(boolean) from public, anon;
grant execute on function public.entrar_campeonato(text), public.sair_campeonato(), public.estado_campeonato(),
  public.campeonato_sala(), public.campeonato_relatar_bot(boolean) to authenticated;
notify pgrst, 'reload schema';
