-- =====================================================================
-- 33_loja_moedas.sql — LOJA DE MOEDAS (compra pela Google Play)
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Pode rodar de novo.
--
-- COMO A COMPRA FUNCIONA (ninguém cria moedas pelo app):
--   1. O jogo abre o pagamento do Google (plugin LojaPlay) e recebe um "token" da compra.
--   2. O jogo manda o token para a Edge Function verificar-compra (supabase/functions/verificar-compra).
--   3. Ela pergunta ao GOOGLE se a compra é verdadeira e paga, e de qual conta é.
--   4. Só então chama creditar_compra_moedas (aqui), que grava a compra e soma as moedas UMA vez por token.
--   5. O jogo "consome" a compra na Play Store (aí dá para comprar o mesmo pacote de novo).
-- =====================================================================

-- PACOTES: o que cada produto da Play Store dá. O jogo lê daqui (dá para mudar sem atualizar o app).
-- O id TEM que ser igual ao "ID do produto" criado no Play Console (Monetizar > Produtos > Produtos no app).
-- O preço quem define é o Play Console (o jogo mostra o preço que o Google mandar, já na moeda da pessoa).
create table if not exists public.loja_pacotes (
  id        text primary key,
  nome      text not null,
  moedas    integer not null check (moedas > 0),
  bonus     integer not null default 0,          -- % a mais (só para mostrar a etiqueta "+25%")
  selo      text not null default '',            -- '' / 'popular' / 'melhor'
  ordem     integer not null default 0,
  ativo     boolean not null default true
);
alter table public.loja_pacotes enable row level security;
drop policy if exists "loja_pacotes: todos leem" on public.loja_pacotes;
create policy "loja_pacotes: todos leem" on public.loja_pacotes for select using (true);

insert into public.loja_pacotes (id, nome, moedas, bonus, selo, ordem) values
  ('moedas_1000',  'Punhado',  1000,  0,  '',        1),
  ('moedas_2200',  'Saco',     2200,  10, '',        2),
  ('moedas_5000',  'Baú',      5000,  25, 'popular', 3),
  ('moedas_14000', 'Cofre',    14000, 40, '',        4),
  ('moedas_32000', 'Tesouro',  32000, 60, 'melhor',  5)
on conflict (id) do update set nome = excluded.nome, moedas = excluded.moedas, bonus = excluded.bonus,
  selo = excluded.selo, ordem = excluded.ordem;

-- COMPRAS: uma linha por compra paga (o token é único: a mesma compra nunca dá moedas duas vezes).
create table if not exists public.compras_moedas (
  token       text primary key,
  usuario     uuid not null references auth.users(id) on delete cascade,
  produto     text not null,
  pedido      text not null default '',          -- número do pedido do Google (GPA.xxxx): aparece no Play Console
  moedas      integer not null,
  em_dobro    boolean not null default false,    -- 1ª compra em dobro
  teste       boolean not null default false,    -- compra de TESTADOR DE LICENÇA (ninguém pagou)
  criado_em   timestamptz not null default now()
);
create index if not exists compras_moedas_usuario on public.compras_moedas (usuario);
alter table public.compras_moedas enable row level security;
drop policy if exists "compras_moedas: vejo as minhas" on public.compras_moedas;
create policy "compras_moedas: vejo as minhas" on public.compras_moedas for select using (usuario = auth.uid());

-- Só a Edge Function (chave service_role) chama: soma as moedas UMA vez por token.
-- Devolve {novo, moedas_ganhas, em_dobro, saldo}. Token de outra conta = erro.
create or replace function public.creditar_compra_moedas(p_usuario uuid, p_token text, p_produto text,
  p_pedido text, p_teste boolean) returns json
language plpgsql security definer set search_path = public as $$
declare
  pac public.loja_pacotes;
  dono uuid;
  primeira boolean;
  total integer;
  saldo integer;
begin
  select usuario into dono from compras_moedas where token = p_token;
  if dono is not null then
    if dono <> p_usuario then raise exception 'compra de outra conta'; end if;
    select moedas into saldo from perfis where id = p_usuario;
    return json_build_object('novo', false, 'moedas_ganhas', 0, 'em_dobro', false, 'saldo', saldo);
  end if;
  select * into pac from loja_pacotes where id = p_produto;
  if pac.id is null then raise exception 'pacote desconhecido: %', p_produto; end if;
  primeira := not exists (select 1 from compras_moedas where usuario = p_usuario);
  total := pac.moedas * (case when primeira then 2 else 1 end);
  insert into compras_moedas (token, usuario, produto, pedido, moedas, em_dobro, teste)
    values (p_token, p_usuario, p_produto, coalesce(p_pedido, ''), total, primeira, coalesce(p_teste, false))
    on conflict (token) do nothing;
  if not found then                                  -- (duas chamadas ao mesmo tempo: a outra já creditou)
    select moedas into saldo from perfis where id = p_usuario;
    return json_build_object('novo', false, 'moedas_ganhas', 0, 'em_dobro', false, 'saldo', saldo);
  end if;
  update perfis set moedas = moedas + total, atualizado_em = now() where id = p_usuario
    returning moedas into saldo;
  if saldo is null then raise exception 'perfil não encontrado'; end if;
  return json_build_object('novo', true, 'moedas_ganhas', total, 'em_dobro', primeira, 'saldo', saldo);
end $$;
revoke all on function public.creditar_compra_moedas(uuid, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.creditar_compra_moedas(uuid, text, text, text, boolean) to service_role;

-- O que a loja do jogo precisa saber da conta: a 1ª compra ainda sai em dobro?
create or replace function public.minha_loja() returns json
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  return json_build_object(
    'primeira_em_dobro', not exists (select 1 from compras_moedas where usuario = auth.uid()),
    'compras', (select count(*) from compras_moedas where usuario = auth.uid() and not teste));
end $$;
revoke all on function public.minha_loja() from public, anon;
grant execute on function public.minha_loja() to authenticated;

notify pgrst, 'reload schema';
