-- =====================================================================
-- Heroes vs Monsters — O RECORDE ANTIGO VALE PARA OS DOIS LADOS
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Pode rodar de novo sem problema.
--
-- Problema: antes do 24_recorde_por_lado.sql o recorde era UM número só (valia para Heroes e
-- Monsters junto). Na virada para o recorde por lado, cada recorde existente ficou guardado só
-- no lado que a pessoa estava usando na hora (perfis.lado_atual). Quem trocou de lado — ou estava
-- com o lado vazio/trocado no cadastro — viu o recorde ZERAR na tela da dificuldade e sumiu do
-- ranking da campanha ("eu tinha batido recorde e zerou").
--
-- Este script espalha o recorde que já existe para OS DOIS lados (depois da cópia fica o MAIOR
-- dos dois). Daqui para frente cada lado guarda o seu, como manda o 24_recorde_por_lado.sql.
--
-- Rodar de novo não estraga: o "on conflict" deixa sempre o maior dos dois lados.
-- =====================================================================

insert into public.recordes_campanha (jogador, dificuldade, nivel, lado)
select r.jogador,
       r.dificuldade,
       r.nivel,
       case when r.lado = 'heroes' then 'monsters' else 'heroes' end
  from public.recordes_campanha r
on conflict (jogador, dificuldade, lado) do update
   set nivel = greatest(recordes_campanha.nivel, excluded.nivel),
       atualizado_em = greatest(recordes_campanha.atualizado_em, excluded.atualizado_em);

-- Conferida (opcional): cada jogador deve aparecer com as duas linhas por dificuldade.
-- select jogador, dificuldade, lado, nivel from public.recordes_campanha order by jogador, dificuldade, lado;
