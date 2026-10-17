-- =====================================================================
-- 34_trofeus_bot.sql — BATALHA PvP contra o BOT também vale TROFÉU (com limite por dia)
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Pode rodar de novo.
--
-- POR QUÊ: com pouca gente online, a busca cai quase sempre no bot e ninguém subia de liga
-- (e os personagens de Prata / Ouro / Diamante ficavam travados).
--
-- A REGRA (o servidor é quem manda; o jogo só pede):
--   Vitória contra o bot na Batalha: Fácil (nível 1-4) +5 · Médio (5-8) +10 · Difícil (9-12) +15 · HardCore (13+) +20
--   Derrota contra o bot: não tira troféu.
--   No máximo +100 troféus por dia vindos do bot (dia de Brasília). A Batalha contra pessoas continua sem esse limite.
--   No máximo 1 prêmio por minuto (uma partida leva bem mais que isso).
-- A vitória também entra no RANKING (tabela partidas), igual às do online.
-- =====================================================================

create table if not exists public.trofeus_bot_dia (
  jogador uuid not null references public.perfis(id) on delete cascade,
  dia date not null,
  ganho int not null default 0,
  ultimo timestamptz not null default now(),
  primary key (jogador, dia)
);
alter table public.trofeus_bot_dia enable row level security;     -- (só pela função abaixo)

create or replace function public.trofeus_contra_bot(p_nivel int) returns json
language plpgsql security definer set search_path = public as $$
declare
  limite constant int := 100;
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  premio int; ja int := 0; ult timestamptz; ganho int := 0; pe public.perfis;
begin
  if auth.uid() is null then raise exception 'precisa entrar'; end if;
  premio := case when p_nivel <= 4 then 5 when p_nivel <= 8 then 10 when p_nivel <= 12 then 15 else 20 end;
  if p_nivel is null or p_nivel < 1 or p_nivel > 15 then premio := 0; end if;

  select t.ganho, t.ultimo into ja, ult from trofeus_bot_dia t where t.jogador = auth.uid() and t.dia = hoje for update;
  ja := coalesce(ja, 0);
  if ult is null or ult < now() - interval '60 seconds' then
    ganho := greatest(0, least(premio, limite - ja));
  end if;

  if ganho > 0 then
    insert into trofeus_bot_dia (jogador, dia, ganho, ultimo) values (auth.uid(), hoje, ganho, now())
    on conflict (jogador, dia) do update set ganho = trofeus_bot_dia.ganho + excluded.ganho, ultimo = now();
    update perfis set trofeus = trofeus + ganho, atualizado_em = now() where id = auth.uid();
    begin                                                -- ranking (Hoje / Semana / Mês): igual a uma vitória online
      insert into partidas (jogador, trofeus, venceu) values (auth.uid(), ganho, true);
    exception when others then null;                     -- (se a tabela pedir outras colunas, o troféu vale mesmo assim)
    end;
    ja := ja + ganho;
  end if;

  select * into pe from perfis where id = auth.uid();
  return (to_jsonb(pe) || jsonb_build_object('ganho_bot', ganho, 'hoje_bot', ja, 'limite_bot', limite))::json;
end $$;
revoke all on function public.trofeus_contra_bot(int) from public, anon;
grant execute on function public.trofeus_contra_bot(int) to authenticated;
notify pgrst, 'reload schema';
