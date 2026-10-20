-- =====================================================================
-- 32_poder_preco.sql — PODER VERMELHO mais caro: o preço sobe a cada uso na mesma partida
-- (25 → 50 → 100 → 150 → 200; volta a 25 na partida seguinte — ver scripts/arena/menu_unidade.gd)
-- O 30_poder_moedas.sql só aceitava até 100 moedas por uso: aqui o limite vai para 500.
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Pode rodar de novo.
-- =====================================================================
create or replace function public.gastar_moedas_poder(p_qtd integer) returns integer
language plpgsql security definer set search_path = public as $$
declare novo integer;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_qtd is null or p_qtd < 1 or p_qtd > 500 then raise exception 'quantidade inválida'; end if;
  update perfis set moedas = moedas - p_qtd, atualizado_em = now()
   where id = auth.uid() and moedas >= p_qtd
  returning moedas into novo;
  if novo is null then raise exception 'moedas insuficientes'; end if;
  return novo;
end $$;
revoke all on function public.gastar_moedas_poder(integer) from public, anon;
grant execute on function public.gastar_moedas_poder(integer) to authenticated;
notify pgrst, 'reload schema';
