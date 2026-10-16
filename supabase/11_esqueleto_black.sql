-- =====================================================================
-- Heroes vs Monsters — ESQUELETO BLACK pode evoluir (tela Personagens)
-- O 3_social.sql esqueceu o Esqueleto Black na lista de personagens que podem subir de nível.
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Pode rodar de novo sem problema.
-- (Vale para o site e para o app.)
-- =====================================================================
create or replace function public.personagem_valido(p text) returns boolean language sql immutable as $$
  select p = any(array['elara','nick','arqueiro','protetor','mago','magoFogo','sentinela','engenheiro',
                       'esqueletoBlack','esqueleto','esqueletoFogo','esqueletoArqueiro','esqueletoProtetor','esqueletoMago','esqueletoTita']);
$$;
notify pgrst, 'reload schema';
