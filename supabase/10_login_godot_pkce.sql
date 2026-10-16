-- =====================================================================
-- Heroes vs Monsters — LOGIN DO JOGO GODOT (funciona em qualquer celular)
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Pode rodar de novo sem problema.
--
-- Como funciona:
-- 1) o jogo abre o Google pelo Supabase com um "estado" (número secreto deste login) e um segredo PKCE;
-- 2) depois de escolher a conta, o Google volta para o site (godot-login.html?s=ESTADO&code=...)
--    e a página chama guardar_codigo_godot(estado, código);
-- 3) o jogo chama pegar_codigo_godot(estado) quando você volta para ele, e troca o código pela sessão.
-- Segurança: o código sozinho NÃO dá acesso a nada (só o aparelho que começou o login tem o segredo
-- para trocar). Cada código vale uma vez só e some em 10 minutos.
-- =====================================================================

create table if not exists public.login_godot_codigo (
  estado text primary key,
  codigo text not null,
  criado_em timestamptz not null default now()
);
alter table public.login_godot_codigo enable row level security;   -- ninguém lê/escreve direto: só pelas funções

-- a página do site guarda o código (ou o erro, começando com "erro:")
create or replace function public.guardar_codigo_godot(p_estado text, p_codigo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_estado is null or length(p_estado) < 32 or length(p_estado) > 128 then raise exception 'estado inválido'; end if;
  if p_codigo is null or length(p_codigo) < 1 or length(p_codigo) > 600 then raise exception 'código inválido'; end if;
  delete from login_godot_codigo where criado_em < now() - interval '10 minutes';
  insert into login_godot_codigo (estado, codigo) values (p_estado, p_codigo)
  on conflict (estado) do update set codigo = excluded.codigo, criado_em = now();
end $$;

-- o jogo pega o código (uma vez só: depois de pegar, ele é apagado)
create or replace function public.pegar_codigo_godot(p_estado text) returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  delete from login_godot_codigo
   where estado = p_estado and criado_em > now() - interval '10 minutes'
  returning codigo into c;
  return c;
end $$;

revoke all on function public.guardar_codigo_godot(text, text), public.pegar_codigo_godot(text) from public;
grant execute on function public.guardar_codigo_godot(text, text), public.pegar_codigo_godot(text) to anon, authenticated;
notify pgrst, 'reload schema';
