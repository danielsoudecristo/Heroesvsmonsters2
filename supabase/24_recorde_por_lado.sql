-- =====================================================================
-- Heroes vs Monsters — RECORDE DA CAMPANHA POR LADO (heróis e monstros separados)
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Pode rodar de novo sem problema.
-- Depois rode este arquivo: o jogo passa a mandar o lado em registrar_recorde_campanha
-- e a ler recordes_campanha com a coluna "lado" (scripts/sistema/conta.gd).
--
-- O que muda em relação ao 13_recorde_campanha.sql:
--   * cada linha agora é (jogador, dificuldade, LADO): quem joga de Heroes tem o seu recorde e
--     quem joga de Monsters tem o dele, sem misturar;
--   * quem tinha recorde antes fica com ele no lado que estava usando (perfis.lado_atual);
--   * ranking_campanha ganha p_lado (o ranking da campanha também é por lado).
-- =====================================================================

-- 1) coluna do lado + os recordes que já existiam guardados no lado da pessoa (só na 1ª vez)
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'recordes_campanha' and column_name = 'lado') then
    alter table public.recordes_campanha add column lado text not null default 'heroes';
    update public.recordes_campanha rc
       set lado = coalesce((select pe.lado_atual from public.perfis pe where pe.id = rc.jogador), 'heroes');
  end if;
end $$;

-- 2) uma linha por (jogador, dificuldade, lado)
alter table public.recordes_campanha drop constraint if exists recordes_campanha_pkey;
alter table public.recordes_campanha add constraint recordes_campanha_pkey primary key (jogador, dificuldade, lado);
alter table public.recordes_campanha drop constraint if exists recordes_campanha_lado;
alter table public.recordes_campanha add constraint recordes_campanha_lado check (lado in ('heroes','monsters'));

-- 3) ranking por lado (dificuldade + lado + maior nível primeiro)
drop index if exists public.recordes_campanha_ranking;
create index if not exists recordes_campanha_ranking on public.recordes_campanha (dificuldade, lado, nivel desc, atualizado_em);

-- 4) gravar o recorde: o jogo manda o nível COMPLETADO e o LADO; fica o maior. Devolve o recorde atual.
drop function if exists public.registrar_recorde_campanha(text, integer);
create or replace function public.registrar_recorde_campanha(p_dificuldade text, p_nivel integer, p_lado text default 'heroes')
returns integer
language plpgsql security definer set search_path = public as $$
declare r integer; l text;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_dificuldade not in ('facil','medio','dificil','hardcore') then raise exception 'dificuldade inválida'; end if;
  if p_nivel is null or p_nivel < 1 or p_nivel > 2000 then raise exception 'nível inválido'; end if;
  l := case when p_lado in ('heroes','monsters') then p_lado else 'heroes' end;
  insert into recordes_campanha (jogador, dificuldade, nivel, lado) values (auth.uid(), p_dificuldade, p_nivel, l)
  on conflict (jogador, dificuldade, lado) do update
    set nivel = greatest(recordes_campanha.nivel, excluded.nivel),
        atualizado_em = case when excluded.nivel > recordes_campanha.nivel then now() else recordes_campanha.atualizado_em end
  returning nivel into r;
  return r;
end $$;

-- 5) ranking da campanha por lado: quem chegou mais longe (empate: quem chegou primeiro).
drop function if exists public.ranking_campanha(text, integer);
create or replace function public.ranking_campanha(p_dificuldade text, p_limite integer default 100, p_lado text default 'heroes')
returns table (posicao bigint, nome text, avatar_url text, valor bigint, trofeus integer, eu boolean)
language sql stable security definer set search_path = public as $$
  with lista as (
    select row_number() over (order by r.nivel desc, r.atualizado_em) as posicao,
           pe.id, pe.nome, pe.avatar_url, r.nivel::bigint as valor, pe.trofeus
      from recordes_campanha r join perfis pe on pe.id = r.jogador
     where r.dificuldade = p_dificuldade
       and r.lado = case when p_lado in ('heroes','monsters') then p_lado else 'heroes' end
       and r.nivel > 0
  )
  select l.posicao,
         split_part(l.nome, ' ', 1) || coalesce(' ' || nullif(left(split_part(l.nome, ' ', 2), 1), '') || '.', ''),
         l.avatar_url, l.valor, l.trofeus, coalesce(l.id = auth.uid(), false)
    from lista l
   where l.posicao <= greatest(1, least(coalesce(p_limite, 100), 200)) or l.id = auth.uid()
   order by l.posicao;
$$;

revoke all on function public.registrar_recorde_campanha(text, integer, text) from public, anon;
grant execute on function public.registrar_recorde_campanha(text, integer, text) to authenticated;
grant execute on function public.ranking_campanha(text, integer, text) to anon, authenticated;

-- Observações:
--   * 18_indicacao.sql usa max(nivel) da tabela: continua válido (agora pega o melhor dos dois lados).
--   * 16_painel.sql junta os recordes em json por dificuldade; com dois lados podem sair duas chaves
--     iguais no mesmo objeto (o painel mostra uma das duas) — sem quebra de cadastro.
notify pgrst, 'reload schema';
