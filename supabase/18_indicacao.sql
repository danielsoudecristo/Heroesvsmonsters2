-- =====================================================================
-- 18_indicacao.sql — CONVIDE AMIGOS (código de indicação)
-- Rode DEPOIS do 3_social.sql e do 14 ao 17.
--
-- Regras:
--   * Quem ENTRA com um código (conta nova, até 7 dias, uma vez só): +200 moedas e vira amigo de quem convidou.
--   * Quem CONVIDOU: +100 moedas na hora (até 30 convites)
--                    +300 quando o convidado jogar de verdade (nível 5 da campanha OU 3 vitórias no PvP).
--   * Metas de RECRUTADOR (convidados que jogaram de verdade): 3 = +300 · 10 = +1000 · 25 = +3000.
--   * Ninguém usa o próprio código. Contas criadas só para ganhar moedas não pagam os +300 (precisam jogar).
-- =====================================================================

alter table public.perfis add column if not exists indicacao_meta_paga boolean not null default false;
alter table public.perfis add column if not exists recrutador_nivel integer not null default 0;
alter table public.perfis add column if not exists indicacao_paga_entrada boolean not null default false;
update public.perfis set codigo_convite = upper(substr(md5(id::text || random()::text), 1, 7)) where codigo_convite is null;

-- metas de recrutador
create or replace function public.recrutador_metas() returns json language sql immutable as $$
  select '[{"qtd":3,"bonus":300,"titulo":"Recrutador"},{"qtd":10,"bonus":1000,"titulo":"Capitão Recrutador"},{"qtd":25,"bonus":3000,"titulo":"Lenda Recrutadora"}]'::json;
$$;

-- usar o código de um amigo
create or replace function public.usar_convite(p_codigo text) returns json
language plpgsql security definer set search_path = public as $$
declare eu public.perfis; dono public.perfis; qtd integer; cod text := upper(trim(coalesce(p_codigo, '')));
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  select * into eu from perfis where id = auth.uid();
  if eu.indicado_por is not null then raise exception 'você já usou um código de convite'; end if;
  if eu.criado_em < now() - interval '7 days' then raise exception 'o código só vale para contas novas (até 7 dias)'; end if;
  if char_length(cod) < 4 then raise exception 'código inválido'; end if;
  select * into dono from perfis where codigo_convite = cod;
  if dono.id is null then raise exception 'código não encontrado. Confira as letras!'; end if;
  if dono.id = eu.id then raise exception 'não dá para usar o seu próprio código'; end if;
  if dono.indicado_por = eu.id then raise exception 'vocês não podem se convidar um ao outro'; end if;

  update perfis set indicado_por = dono.id, moedas = moedas + 200, atualizado_em = now() where id = eu.id;
  select count(*) into qtd from perfis where indicado_por = dono.id and indicacao_paga_entrada;
  if qtd < 30 then
    update perfis set moedas = moedas + 100, atualizado_em = now() where id = dono.id;
    update perfis set indicacao_paga_entrada = true where id = eu.id;
  end if;
  -- viram amigos na hora
  delete from amizades where (de = eu.id and para = dono.id) or (de = dono.id and para = eu.id);
  insert into amizades (de, para, status) values (dono.id, eu.id, 'aceita');
  perform checar_indicacao();
  select * into eu from perfis where id = auth.uid();
  return json_build_object('ganhou', 200, 'amigo', split_part(dono.nome, ' ', 1), 'perfil', row_to_json(eu));
end $$;

-- o convidado jogou de verdade? paga quem convidou (o jogo chama ao entrar e ao vencer)
create or replace function public.checar_indicacao() returns json
language plpgsql security definer set search_path = public as $$
declare eu public.perfis; rec integer; ativos integer; metas json := recrutador_metas(); m json; i integer := 0; dono public.perfis;
begin
  if auth.uid() is null then return json_build_object('pago', false); end if;
  select * into eu from perfis where id = auth.uid();
  if eu.indicado_por is null or eu.indicacao_meta_paga then return json_build_object('pago', false); end if;
  select coalesce(max(nivel), 0) into rec from recordes_campanha where jogador = eu.id;
  if rec < 5 and coalesce(eu.vitorias, 0) < 3 then return json_build_object('pago', false); end if;
  update perfis set indicacao_meta_paga = true where id = eu.id;
  update perfis set moedas = moedas + 300, atualizado_em = now() where id = eu.indicado_por;
  -- metas de recrutador de quem convidou
  select count(*) into ativos from perfis where indicado_por = eu.indicado_por and indicacao_meta_paga;
  select * into dono from perfis where id = eu.indicado_por for update;
  for m in select * from json_array_elements(metas) loop
    i := i + 1;
    if ativos >= (m->>'qtd')::int and dono.recrutador_nivel < i then
      update perfis set moedas = moedas + (m->>'bonus')::int, recrutador_nivel = i where id = dono.id;
      dono.recrutador_nivel := i;
    end if;
  end loop;
  return json_build_object('pago', true);
end $$;

-- tela "Convide amigos"
create or replace function public.minhas_indicacoes() returns json
language plpgsql security definer set search_path = public as $$
declare eu public.perfis; total integer; ativos integer; pagos_entrada integer; padrinho text; r json;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  update perfis set codigo_convite = upper(substr(md5(id::text || random()::text), 1, 7)) where id = auth.uid() and codigo_convite is null;
  select * into eu from perfis where id = auth.uid();
  select count(*), count(*) filter (where indicacao_meta_paga), count(*) filter (where indicacao_paga_entrada)
    into total, ativos, pagos_entrada from perfis where indicado_por = eu.id;
  select split_part(nome, ' ', 1) into padrinho from perfis where id = eu.indicado_por;
  select json_build_object(
    'codigo', eu.codigo_convite,
    'total', total, 'ativos', ativos,
    'moedas_ganhas', pagos_entrada * 100 + ativos * 300
        + (select coalesce(sum((m->>'bonus')::int), 0) from (select m, row_number() over () as k from json_array_elements(recrutador_metas()) m) x where x.k <= eu.recrutador_nivel),
    'nivel', eu.recrutador_nivel, 'metas', recrutador_metas(),
    'usei', eu.indicado_por is not null, 'padrinho', padrinho,
    'pode_usar', eu.indicado_por is null and eu.criado_em > now() - interval '7 days',
    'lista', coalesce((select json_agg(x order by x.criado_em desc) from (
        select split_part(p.nome, ' ', 1) || coalesce(' ' || nullif(left(split_part(p.nome, ' ', 2), 1), '') || '.', '') as nome,
               p.lado_atual, p.criado_em, p.indicacao_meta_paga as jogou, coalesce(p.visto_em > now() - interval '90 seconds', false) as online
          from perfis p where p.indicado_por = eu.id order by p.criado_em desc limit 50) x), '[]'::json)
  ) into r;
  return r;
end $$;

-- PAINEL DO DONO: quem mais convida (usa a mesma chave do painel)
create or replace function public.painel_indicacoes(p_chave text) returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if encode(sha256(convert_to(coalesce(p_chave, ''), 'UTF8')), 'hex') is distinct from (select hash from painel_config where id = 1) then
    perform pg_sleep(1);
    raise exception 'chave errada';
  end if;
  return json_build_object(
    'total', (select count(*) from perfis where indicado_por is not null),
    'jogaram', (select count(*) from perfis where indicado_por is not null and indicacao_meta_paga),
    'top', coalesce((select json_agg(x order by x.total desc, x.jogaram desc) from (
        select d.nome, count(*) as total, count(*) filter (where p.indicacao_meta_paga) as jogaram, d.recrutador_nivel as nivel
          from perfis p join perfis d on d.id = p.indicado_por
         group by d.id, d.nome, d.recrutador_nivel order by count(*) desc limit 20) x), '[]'::json));
end $$;

revoke all on function public.usar_convite(text), public.checar_indicacao(), public.minhas_indicacoes() from public, anon;
grant execute on function public.usar_convite(text), public.checar_indicacao(), public.minhas_indicacoes() to authenticated;
revoke all on function public.painel_indicacoes(text) from public;
grant execute on function public.painel_indicacoes(text) to anon, authenticated;
notify pgrst, 'reload schema';
