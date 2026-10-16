-- =====================================================================
-- Heroes vs Monsters — RECORDE DA CAMPANHA (até que nível cada um chegou) + RANKING da campanha
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Pode rodar de novo sem problema.
-- Um recorde por dificuldade (facil, medio, dificil, hardcore). Só sobe: nunca diminui.
-- =====================================================================

create table if not exists public.recordes_campanha (
  jogador uuid not null references public.perfis(id) on delete cascade,
  dificuldade text not null check (dificuldade in ('facil','medio','dificil','hardcore')),
  nivel integer not null default 0,
  atualizado_em timestamptz not null default now(),
  primary key (jogador, dificuldade)
);
create index if not exists recordes_campanha_ranking on public.recordes_campanha (dificuldade, nivel desc, atualizado_em);
alter table public.recordes_campanha enable row level security;
drop policy if exists "ver meus recordes" on public.recordes_campanha;
create policy "ver meus recordes" on public.recordes_campanha for select using (auth.uid() = jogador);

-- o jogo manda o nível que a pessoa COMPLETOU; fica o maior. Devolve o recorde atual.
create or replace function public.registrar_recorde_campanha(p_dificuldade text, p_nivel integer) returns integer
language plpgsql security definer set search_path = public as $$
declare r integer;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  if p_dificuldade not in ('facil','medio','dificil','hardcore') then raise exception 'dificuldade inválida'; end if;
  if p_nivel is null or p_nivel < 1 or p_nivel > 2000 then raise exception 'nível inválido'; end if;
  insert into recordes_campanha (jogador, dificuldade, nivel) values (auth.uid(), p_dificuldade, p_nivel)
  on conflict (jogador, dificuldade) do update
    set nivel = greatest(recordes_campanha.nivel, excluded.nivel),
        atualizado_em = case when excluded.nivel > recordes_campanha.nivel then now() else recordes_campanha.atualizado_em end
  returning nivel into r;
  return r;
end $$;

-- RANKING da campanha: quem chegou mais longe (empate: quem chegou primeiro). Igual ao ranking() do 2_ranking.sql.
create or replace function public.ranking_campanha(p_dificuldade text, p_limite integer default 100)
returns table (posicao bigint, nome text, avatar_url text, valor bigint, trofeus integer, eu boolean)
language sql stable security definer set search_path = public as $$
  with lista as (
    select row_number() over (order by r.nivel desc, r.atualizado_em) as posicao,
           pe.id, pe.nome, pe.avatar_url, r.nivel::bigint as valor, pe.trofeus
      from recordes_campanha r join perfis pe on pe.id = r.jogador
     where r.dificuldade = p_dificuldade and r.nivel > 0
  )
  select l.posicao,
         split_part(l.nome, ' ', 1) || coalesce(' ' || nullif(left(split_part(l.nome, ' ', 2), 1), '') || '.', ''),
         l.avatar_url, l.valor, l.trofeus, coalesce(l.id = auth.uid(), false)
    from lista l
   where l.posicao <= greatest(1, least(coalesce(p_limite, 100), 200)) or l.id = auth.uid()
   order by l.posicao;
$$;

revoke all on function public.registrar_recorde_campanha(text, integer) from public, anon;
grant execute on function public.registrar_recorde_campanha(text, integer) to authenticated;
grant execute on function public.ranking_campanha(text, integer) to anon, authenticated;
notify pgrst, 'reload schema';
