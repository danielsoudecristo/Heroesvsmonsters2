-- =====================================================================
-- 31_personagens_novos.sql — o servidor passa a aceitar evoluir os personagens novos
-- (Esqueleto Bombardeiro, Guerreiro Darian, Guerreira Aura, Golem de Ossos e Esqueleto Místico).
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Pode rodar de novo.
-- =====================================================================
create or replace function public.personagem_valido(p text) returns boolean language sql immutable as $$
  select p = any(array['elara','nick','arqueiro','protetor','mago','magoFogo','sentinela','engenheiro','darian','aura',
                       'esqueletoBlack','esqueleto','esqueletoFogo','esqueletoArqueiro','esqueletoProtetor','esqueletoMago',
                       'esqueletoTita','esqueletoBombardeiro','golemOssos','esqueletoMistico']);
$$;
notify pgrst, 'reload schema';
