-- =====================================================================
-- 30_poder_moedas.sql — PODER VERMELHO (2º poder do personagem) gasta MOEDAS DA CONTA
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Pode rodar de novo.
-- (nome próprio: o banco já tem uma gastar_moedas antiga, do site, que continua igual)
-- O jogo chama gastar_moedas_poder(p_qtd) quando o jogador toca no poder vermelho: tira as moedas (se tiver)
-- e devolve o saldo novo. Sem moedas suficientes = erro (o jogo já confere antes).
-- =====================================================================
create or replace function public.gastar_moedas_poder(p_qtd integer) returns integer
language plpgsql security definer set search_path = public as $$
declare novo integer;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_qtd is null or p_qtd < 1 or p_qtd > 100 then raise exception 'quantidade inválida'; end if;
  update perfis set moedas = moedas - p_qtd, atualizado_em = now()
   where id = auth.uid() and moedas >= p_qtd
  returning moedas into novo;
  if novo is null then raise exception 'moedas insuficientes'; end if;
  return novo;
end $$;
revoke all on function public.gastar_moedas_poder(integer) from public, anon;
grant execute on function public.gastar_moedas_poder(integer) to authenticated;
notify pgrst, 'reload schema';
