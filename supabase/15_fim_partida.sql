-- =====================================================================
-- Heroes vs Monsters — TELA DO FIM DA PARTIDA ONLINE (PvP e duelo)
-- Mostra os dois jogadores lado a lado: nome, foto, troféus, moedas (já com o resultado) e se já são amigos.
-- REVANCHE: no fim, qualquer um dos dois pede; o outro vê "Aceitar revanche!" na mesma tela. Mesmos lados.
--   PvP normal -> a revanche também vale troféus. Duelo -> a revanche vale a mesma aposta. (Não precisa ser amigo.)
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. (depois do 14_social_godot.sql) Pode rodar de novo.
-- Só quem jogou a partida consegue ver.
-- =====================================================================
create or replace function public.jogadores_da_sala(p_sala uuid) returns json
language plpgsql stable security definer set search_path = public as $$
declare s public.partidas_pvp;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  select * into s from partidas_pvp where id = p_sala;
  if s.id is null or auth.uid() not in (s.heroes, s.monsters) then raise exception 'você não está nesta partida'; end if;
  return (
    select json_agg(json_build_object(
      'id', pe.id,
      'lado', case when pe.id = s.heroes then 'heroes' else 'monsters' end,
      'nome', split_part(pe.nome, ' ', 1) || coalesce(' ' || nullif(left(split_part(pe.nome, ' ', 2), 1), '') || '.', ''),
      'avatar_url', pe.avatar_url,
      'trofeus', pe.trofeus,
      'moedas', pe.moedas,
      'vitorias', pe.vitorias,
      'derrotas', pe.derrotas,
      'eu', pe.id = auth.uid(),
      'amizade', coalesce((select a.status from amizades a
                            where (a.de = auth.uid() and a.para = pe.id) or (a.de = pe.id and a.para = auth.uid()) limit 1), '')
    ))
    from perfis pe where pe.id in (s.heroes, s.monsters)
  );
end $$;
-- REVANCHE: pede (ou, se o outro já pediu, devolve o pedido dele para você aceitar)
create or replace function public.pedir_revanche(p_sala uuid) returns json
language plpgsql security definer set search_path = public as $$
declare s public.partidas_pvp; outro uuid; meu_lado text; d public.duelos;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  select * into s from partidas_pvp where id = p_sala;
  if s.id is null or auth.uid() not in (s.heroes, s.monsters) then raise exception 'você não está nesta partida'; end if;
  outro := case when auth.uid() = s.heroes then s.monsters else s.heroes end;
  meu_lado := case when auth.uid() = s.heroes then 'heroes' else 'monsters' end;
  select * into d from duelos where sala_origem = p_sala and status = 'pendente' and criado_em > now() - interval '90 seconds'
   order by criado_em desc limit 1;
  if d.id is not null then
    return json_build_object('id', d.id, 'de_mim', d.de = auth.uid(), 'status', d.status);
  end if;
  insert into duelos (de, para, lado_de, aposta_moedas, aposta_trofeus, sala_origem, ranqueada)
  values (auth.uid(), outro, meu_lado, s.aposta_moedas, s.aposta_trofeus, p_sala, not s.amistoso)
  returning * into d;
  return json_build_object('id', d.id, 'de_mim', true, 'status', d.status);
end $$;

-- como está a revanche desta partida: {id, de_mim, status, sala} (null = ninguém pediu)
create or replace function public.ver_revanche(p_sala uuid) returns json
language plpgsql security definer set search_path = public as $$
declare d public.duelos; s2 public.partidas_pvp;
begin
  select * into d from duelos where sala_origem = p_sala and auth.uid() in (de, para) order by criado_em desc limit 1;
  if d.id is null then return null; end if;
  if d.status = 'pendente' and d.criado_em < now() - interval '90 seconds' then
    update duelos set status = 'cancelado' where id = d.id;
    d.status := 'cancelado';
  end if;
  if d.sala is not null then select * into s2 from partidas_pvp where id = d.sala; end if;
  return json_build_object('id', d.id, 'de_mim', d.de = auth.uid(), 'status', d.status,
    'sala', case when s2.id is not null then sala_json(s2) end);
end $$;

revoke all on function public.jogadores_da_sala(uuid), public.pedir_revanche(uuid), public.ver_revanche(uuid) from public, anon;
grant execute on function public.jogadores_da_sala(uuid), public.pedir_revanche(uuid), public.ver_revanche(uuid) to authenticated;
notify pgrst, 'reload schema';
