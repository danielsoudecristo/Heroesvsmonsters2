-- =====================================================================
-- 37_painel_admin.sql — ADMINISTRAR jogadores pelo PAINEL (aba "Administrar" do painel/painel.html)
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Rode DEPOIS do 16_painel.sql, 28_serie_pvp.sql e
-- 35_mesmo_ip.sql. Pode rodar de novo.
--
-- Só funciona com a CHAVE DO PAINEL (a mesma do 16_painel.sql). Tudo o que for mudado fica anotado em admin_log.
--   painel_admin_ver(chave, jogador)                         — os números de agora de um jogador
--   painel_admin_alterar(chave, jogador, campo, modo, valor, motivo)
--        campo: 'trofeus' | 'moedas' | 'energia_extra'      modo: 'somar' (pode ser negativo = tirar) | 'definir'
--   painel_admin_banir(chave, jogador, banido, motivo)        — bloqueia a Batalha online e os troféus do bot
--   painel_admin_log(chave)                                   — as últimas 100 mudanças
--
-- ENERGIA EXTRA: energia a mais (ou a menos, se negativo) no COMEÇO de cada partida desse jogador:
-- campanha, contra o bot, Cerco e PvP online (no online os dois celulares recebem o número pela sala).
-- =====================================================================

alter table public.perfis add column if not exists energia_extra integer not null default 0;
alter table public.perfis add column if not exists banido boolean not null default false;

create table if not exists public.admin_log (
  id bigint generated always as identity primary key,
  em timestamptz not null default now(),
  jogador uuid,
  nome text,
  acao text not null,
  antes jsonb,
  depois jsonb,
  motivo text
);
alter table public.admin_log enable row level security;        -- (só pelas funções abaixo)

create or replace function public._painel_ok(p_chave text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if encode(sha256(convert_to(coalesce(p_chave, ''), 'UTF8')), 'hex') is distinct from (select hash from painel_config where id = 1) then
    perform pg_sleep(1);
    raise exception 'chave errada';
  end if;
end $$;
revoke all on function public._painel_ok(text) from public, anon, authenticated;

create or replace function public._admin_json(p public.perfis) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', p.id, 'nome', p.nome, 'trofeus', p.trofeus, 'moedas', p.moedas,
    'energia_extra', p.energia_extra, 'banido', p.banido, 'vitorias', p.vitorias, 'derrotas', p.derrotas,
    'lado_atual', p.lado_atual, 'avatar_url', p.avatar_url);
$$;
revoke all on function public._admin_json(public.perfis) from public, anon, authenticated;

create or replace function public.painel_admin_ver(p_chave text, p_jogador uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.perfis;
begin
  perform _painel_ok(p_chave);
  select * into p from perfis where id = p_jogador;
  if p.id is null then raise exception 'jogador não encontrado'; end if;
  return _admin_json(p);
end $$;

create or replace function public.painel_admin_alterar(p_chave text, p_jogador uuid, p_campo text, p_modo text, p_valor integer, p_motivo text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.perfis; antes jsonb; atual integer; novo integer;
begin
  perform _painel_ok(p_chave);
  if p_campo not in ('trofeus', 'moedas', 'energia_extra') then raise exception 'campo inválido'; end if;
  if p_modo not in ('somar', 'definir') then raise exception 'modo inválido'; end if;
  if p_valor is null then raise exception 'valor vazio'; end if;
  select * into p from perfis where id = p_jogador for update;
  if p.id is null then raise exception 'jogador não encontrado'; end if;
  antes := _admin_json(p);
  atual := case p_campo when 'trofeus' then p.trofeus when 'moedas' then p.moedas else p.energia_extra end;
  novo := case p_modo when 'somar' then atual + p_valor else p_valor end;
  if p_campo = 'energia_extra' then
    novo := least(greatest(novo, -100), 2000);            -- (nunca deixa a partida começar sem energia nenhuma)
  else
    novo := least(greatest(novo, 0), 99999999);
  end if;
  if p_campo = 'trofeus' then update perfis set trofeus = novo, atualizado_em = now() where id = p.id;
  elsif p_campo = 'moedas' then update perfis set moedas = novo, atualizado_em = now() where id = p.id;
  else update perfis set energia_extra = novo, atualizado_em = now() where id = p.id; end if;
  select * into p from perfis where id = p_jogador;
  insert into admin_log (jogador, nome, acao, antes, depois, motivo)
  values (p.id, p.nome, p_campo || ' ' || p_modo || ' ' || p_valor, antes, _admin_json(p), nullif(trim(coalesce(p_motivo, '')), ''));
  return _admin_json(p);
end $$;

create or replace function public.painel_admin_banir(p_chave text, p_jogador uuid, p_banido boolean, p_motivo text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.perfis; antes jsonb;
begin
  perform _painel_ok(p_chave);
  select * into p from perfis where id = p_jogador for update;
  if p.id is null then raise exception 'jogador não encontrado'; end if;
  antes := _admin_json(p);
  update perfis set banido = coalesce(p_banido, false), atualizado_em = now() where id = p.id;
  delete from fila_pvp where jogador = p.id and coalesce(p_banido, false);
  select * into p from perfis where id = p_jogador;
  insert into admin_log (jogador, nome, acao, antes, depois, motivo)
  values (p.id, p.nome, case when p.banido then 'banir' else 'desbanir' end, antes, _admin_json(p), nullif(trim(coalesce(p_motivo, '')), ''));
  return _admin_json(p);
end $$;

create or replace function public.painel_admin_log(p_chave text) returns json
language plpgsql security definer set search_path = public as $$
begin
  perform _painel_ok(p_chave);
  return coalesce((select json_agg(x order by x.em desc) from (select * from admin_log order by em desc limit 100) x), '[]'::json);
end $$;

revoke all on function public.painel_admin_ver(text, uuid), public.painel_admin_alterar(text, uuid, text, text, integer, text),
  public.painel_admin_banir(text, uuid, boolean, text), public.painel_admin_log(text) from public;
grant execute on function public.painel_admin_ver(text, uuid), public.painel_admin_alterar(text, uuid, text, text, integer, text),
  public.painel_admin_banir(text, uuid, boolean, text), public.painel_admin_log(text) to anon, authenticated;

-- ---------------------------------------------------------------- o JOGO lê o ajuste de quem entrou
create or replace function public.meus_ajustes() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('energia_extra', coalesce(energia_extra, 0), 'banido', coalesce(banido, false))
    from perfis where id = auth.uid();
$$;
revoke all on function public.meus_ajustes() from public, anon;
grant execute on function public.meus_ajustes() to authenticated;

-- (igual ao 28) + a ENERGIA EXTRA de cada lado: os dois celulares recebem o mesmo número pela sala
create or replace function public.sala_json(s public.partidas_pvp) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('id', s.id, 'semente', s.semente, 'heroes', s.heroes, 'monsters', s.monsters,
    'niveis_heroes', s.niveis_heroes, 'niveis_monsters', s.niveis_monsters,
    'nome_heroes', (select split_part(nome, ' ', 1) from perfis where id = s.heroes),
    'nome_monsters', (select split_part(nome, ' ', 1) from perfis where id = s.monsters),
    'foto_heroes', (select avatar_url from perfis where id = s.heroes),
    'foto_monsters', (select avatar_url from perfis where id = s.monsters),
    'energia_heroes', (select coalesce(energia_extra, 0) from perfis where id = s.heroes),
    'energia_monsters', (select coalesce(energia_extra, 0) from perfis where id = s.monsters),
    'vencedor', s.vencedor, 'finalizada', s.finalizada, 'amistoso', s.amistoso,
    'aposta_moedas', s.aposta_moedas, 'aposta_trofeus', s.aposta_trofeus, 'modo', s.modo,
    'serie', s.serie, 'jogo', s.jogo,
    'em_serie', (s.plataforma = 'godot' and coalesce(s.modo, 'normal') = 'normal' and not s.amistoso),
    'pontos_heroes', (select case when se.a = s.heroes then se.pontos_a else se.pontos_b end from series_pvp se where se.id = s.serie),
    'pontos_monsters', (select case when se.a = s.monsters then se.pontos_a else se.pontos_b end from series_pvp se where se.id = s.serie));
$$;

-- (igual ao 35) + BANIDO não entra na fila da Batalha / Cerco online
create or replace function public.procurar_partida_modo(p_lado text, p_modo text) returns json
language plpgsql security definer set search_path = public as $$
declare outro public.fila_pvp; s public.partidas_pvp; meus jsonb;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if (select banido from perfis where id = auth.uid()) then raise exception 'conta bloqueada para o online'; end if;
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

-- (igual ao 34) + BANIDO não ganha troféu do bot
create or replace function public.trofeus_contra_bot(p_nivel int) returns json
language plpgsql security definer set search_path = public as $$
declare
  limite constant int := 100;
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  premio int; ja int := 0; ult timestamptz; ganho int := 0; pe public.perfis;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  premio := case when p_nivel <= 4 then 5 when p_nivel <= 8 then 10 when p_nivel <= 12 then 15 else 20 end;
  if p_nivel is null or p_nivel < 1 or p_nivel > 15 then premio := 0; end if;
  if (select banido from perfis where id = auth.uid()) then premio := 0; end if;

  select t.ganho, t.ultimo into ja, ult from trofeus_bot_dia t where t.jogador = auth.uid() and t.dia = hoje for update;
  ja := coalesce(ja, 0);
  if ult is null or ult < now() - interval '60 seconds' then
    ganho := greatest(0, least(premio, limite - ja));
  end if;

  if ganho > 0 then
    insert into trofeus_bot_dia (jogador, dia, ganho, ultimo) values (auth.uid(), hoje, ganho, now())
    on conflict (jogador, dia) do update set ganho = trofeus_bot_dia.ganho + excluded.ganho, ultimo = now();
    update perfis set trofeus = trofeus + ganho, atualizado_em = now() where id = auth.uid();
    begin
      insert into partidas (jogador, trofeus, venceu) values (auth.uid(), ganho, true);
    exception when others then null;
    end;
    ja := ja + ganho;
  end if;

  select * into pe from perfis where id = auth.uid();
  return (to_jsonb(pe) || jsonb_build_object('ganho_bot', ganho, 'hoje_bot', ja, 'limite_bot', limite))::json;
end $$;

notify pgrst, 'reload schema';
