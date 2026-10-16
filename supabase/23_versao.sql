-- =====================================================================
-- 23_versao.sql — ATUALIZAÇÃO DO JOGO: versão mínima e novidades
-- Rode DEPOIS do 20_ao_vivo.sql. O jogo lê isto ao abrir (função app_versao) e o painel muda (aba Ao vivo).
--
--   versao_minima = CÓDIGO da versão (o "Código" do Godot / Play Console). Quem tiver código MENOR
--                   é obrigado a atualizar (ex.: mudou algo no PvP online). 0 = nunca obriga.
--   versao_nome   = o nome que aparece na janela (ex.: "1.3")
--   novidades     = uma novidade por linha (aparece na janela "Nova atualização disponível!")
-- =====================================================================

create table if not exists public.app_config (
  id int primary key default 1 check (id = 1),
  versao_minima integer not null default 0,
  versao_nome text,
  novidades text,
  atualizado_em timestamptz not null default now()
);
alter table public.app_config enable row level security;
insert into public.app_config (id, versao_minima, versao_nome, novidades)
values (1, 0, '1.3', 'Tutorial com mãozinha para novatos
Novo modo CERCO: defenda e depois ataque
Convide amigos e ganhe moedas
Chat e login funcionando melhor no celular
Novo ícone e várias melhorias')
on conflict (id) do nothing;

create or replace function public.app_versao() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('versao_minima', versao_minima, 'versao_nome', versao_nome, 'novidades', novidades)
    from app_config where id = 1;
$$;
revoke all on function public.app_versao() from public;
grant execute on function public.app_versao() to anon, authenticated;

-- PAINEL: ver e mudar (com a chave do painel) + quantos estão em cada versão
create or replace function public.painel_versao(p_chave text) returns json
language plpgsql security definer set search_path = public as $$
begin
  perform painel_checar(p_chave);
  return json_build_object(
    'config', (select row_to_json(c) from app_config c where id = 1),
    'versoes', coalesce((select json_agg(x order by x.versao desc nulls last) from (
        select coalesce(versao, '?') as versao, count(*) as pessoas, count(*) filter (where visto_em > now() - interval '75 seconds') as online
          from ao_vivo where visto_em > now() - interval '30 days' group by 1) x), '[]'::json));
end $$;

create or replace function public.painel_definir_versao(p_chave text, p_minima integer, p_nome text, p_novidades text) returns json
language plpgsql security definer set search_path = public as $$
begin
  perform painel_checar(p_chave);
  update app_config set versao_minima = greatest(0, coalesce(p_minima, 0)), versao_nome = left(p_nome, 20),
         novidades = left(p_novidades, 600), atualizado_em = now() where id = 1;
  return (select row_to_json(c) from app_config c where id = 1);
end $$;
revoke all on function public.painel_versao(text), public.painel_definir_versao(text, integer, text, text) from public;
grant execute on function public.painel_versao(text), public.painel_definir_versao(text, integer, text, text) to anon, authenticated;
notify pgrst, 'reload schema';
