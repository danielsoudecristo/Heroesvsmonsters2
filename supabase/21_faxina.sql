-- =====================================================================
-- 21_faxina.sql — FAXINA AUTOMÁTICA (o banco não enche)
-- Rode DEPOIS do 20_ao_vivo.sql. Só servidor: NÃO precisa mudar o jogo.
--
-- Apaga só coisas velhas:
--   * eventos (registros do painel) com mais de 90 dias
--   * ao_vivo de quem não aparece há mais de 1 dia
--   * chat geral com mais de 7 dias, mensagens privadas com mais de 30 dias
--   * convites de duelo com mais de 2 dias, fila de PvP parada
--   * partidas online com mais de 60 dias (o resultado já está nos troféus de cada um)
-- Troféus, moedas, ranking, personagens, amigos e recordes NUNCA são apagados.
--
-- Roda sozinha: no máximo 1 vez a cada 6 horas, "pegando carona" nos registros que o jogo já manda.
-- =====================================================================

create table if not exists public.faxina_config (id int primary key default 1 check (id = 1), ultima timestamptz not null default now());
alter table public.faxina_config enable row level security;
insert into public.faxina_config (id, ultima) values (1, now() - interval '1 day') on conflict (id) do nothing;

create or replace function public.faxina() returns json
language plpgsql security definer set search_path = public as $$
declare a int := 0; b int := 0; c int := 0; d int := 0; e int := 0; f int := 0;
begin
  delete from eventos where criado_em < now() - interval '90 days';           get diagnostics a = row_count;
  delete from ao_vivo where visto_em < now() - interval '1 day';              get diagnostics b = row_count;
  delete from mensagens where criado_em < now() - interval '7 days';          get diagnostics c = row_count;
  delete from mensagens_privadas where criado_em < now() - interval '30 days'; get diagnostics d = row_count;
  delete from duelos where criado_em < now() - interval '2 days';             get diagnostics e = row_count;
  delete from fila_pvp where criado_em < now() - interval '1 hour';
  delete from partidas_pvp where criada_em < now() - interval '60 days'
     and id not in (select sala from duelos where sala is not null)
     and id not in (select sala_origem from duelos where sala_origem is not null);
  get diagnostics f = row_count;
  update faxina_config set ultima = now() where id = 1;
  return json_build_object('eventos', a, 'ao_vivo', b, 'chat', c, 'privadas', d, 'duelos', e, 'partidas', f);
end $$;
revoke all on function public.faxina() from public, anon, authenticated;

-- gatilho: a cada evento novo, se a última faxina foi há mais de 6 horas, faz uma agora
create or replace function public.faxina_se_precisar() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select ultima from faxina_config where id = 1) < now() - interval '6 hours' then
    update faxina_config set ultima = now() where id = 1;      -- (marca antes: só um faz)
    perform faxina();
  end if;
  return null;
end $$;
drop trigger if exists faxina_auto on public.eventos;
create trigger faxina_auto after insert on public.eventos
  for each statement execute function public.faxina_se_precisar();

-- tamanho do banco (para o painel): painel_tamanho('sua chave')
create or replace function public.painel_tamanho(p_chave text) returns json
language plpgsql security definer set search_path = public as $$
begin
  perform painel_checar(p_chave);
  return json_build_object('banco_mb', round(pg_database_size(current_database()) / 1048576.0, 1),
    'eventos', (select count(*) from eventos), 'ultima_faxina', (select ultima from faxina_config where id = 1));
end $$;
revoke all on function public.painel_tamanho(text) from public;
grant execute on function public.painel_tamanho(text) to anon, authenticated;

select faxina();          -- já faz a primeira agora
notify pgrst, 'reload schema';
