-- =====================================================================
-- 38_replays_todos.sql — REPLAYS para TODO MUNDO ver (não só você e seus amigos) · continua apagando depois de 24 horas
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Rode DEPOIS do 36_replays.sql. Pode rodar de novo.
-- Não precisa atualizar o jogo: a tela de Replays que já está no celular passa a mostrar as batalhas de todos
-- (no jogo antigo as de desconhecidos aparecem escrito "de um amigo"; o replays_tela.gd novo escreve "online").
-- Ordem da lista: as SUAS primeiro, depois as dos seus AMIGOS, depois as de todo mundo (mais novas primeiro).
-- (Para voltar a ser só você e seus amigos: rode o 36_replays.sql de novo.)
-- =====================================================================

-- ENERGIA EXTRA do painel (37): no replay o jogo mostra a energia SÓ do lado que você assiste. Quem não jogou a partida
-- assiste sempre pelo lado SEM energia extra (assim ninguém vê o número turbinado). Se os dois lados tiverem energia
-- extra, o replay só aparece para quem jogou. (Quem jogou assiste pelo próprio lado, como antes.)
create or replace function public._extra_replay(r public.replays, p_lado text) returns boolean
language sql immutable as $$
  select coalesce(nullif(r.dados -> 'energia' ->> p_lado, '')::numeric, 0) <> 0;
$$;
revoke all on function public._extra_replay(public.replays, text) from public, anon, authenticated;

create or replace function public._pode_ver_replay(r public.replays) returns boolean
language sql stable security definer set search_path = public as $$
  select r.criado_em > now() - interval '24 hours' and auth.uid() is not null
     and (auth.uid() in (r.heroes, r.monsters)                   -- quem jogou sempre vê
          or not (_extra_replay(r, 'heroes') and _extra_replay(r, 'monsters')));   -- os 2 com energia extra: só quem jogou
$$;
revoke all on function public._pode_ver_replay(public.replays) from public, anon, authenticated;

create or replace function public.listar_replays() returns json
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  perform _faxina_replays();
  return coalesce((
    select json_agg(x order by x.ordem, x.criado_em desc) from (
      select r.sala, r.modo, r.vencedor, r.criado_em,
             extract(epoch from (r.criado_em + interval '24 hours' - now()))::int as some_em,
             auth.uid() in (r.heroes, r.monsters) as minha,
             (sao_amigos(auth.uid(), r.heroes) or sao_amigos(auth.uid(), r.monsters)) as amigo,
             case when auth.uid() in (r.heroes, r.monsters) then 0
                  when sao_amigos(auth.uid(), r.heroes) or sao_amigos(auth.uid(), r.monsters) then 1 else 2 end as ordem,
             case when auth.uid() = r.heroes then 'heroes' when auth.uid() = r.monsters then 'monsters'
                  when _extra_replay(r, 'heroes') then 'monsters'           -- (energia extra: assiste pelo outro lado)
                  when _extra_replay(r, 'monsters') then 'heroes'
                  when sao_amigos(auth.uid(), r.monsters) and not sao_amigos(auth.uid(), r.heroes) then 'monsters'
                  else 'heroes' end as lado_ver,
             split_part(ph.nome, ' ', 1) as nome_heroes, ph.avatar_url as foto_heroes,
             split_part(pm.nome, ' ', 1) as nome_monsters, pm.avatar_url as foto_monsters
        from replays r
        join perfis ph on ph.id = r.heroes
        join perfis pm on pm.id = r.monsters
       where _pode_ver_replay(r)
       order by ordem, r.criado_em desc
       limit 50) x), '[]'::json);
end $$;

revoke all on function public.listar_replays() from public, anon;
grant execute on function public.listar_replays() to authenticated;
notify pgrst, 'reload schema';
