-- =====================================================================
-- 33_detectar_farm.sql — QUEM JÁ FEZ FARM DE TROFÉUS ANTES DO 32_anti_farm.sql (só CONSULTA: não muda nada)
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run. Pode rodar quantas vezes quiser.
--
-- Mostra os PARES de jogadores que mais se enfrentaram na Batalha valendo troféu (online, não amistoso),
-- do mais suspeito para o menos. Sinais de farm:
--   - muitas partidas entre os MESMOS dois (coluna partidas);
--   - quase sempre o MESMO vence (coluna pct_mesmo_vencedor perto de 100);
--   - o perdedor quase não joga com mais ninguém (coluna perdedor_outros_adversarios perto de 0);
--   - o perdedor está com 0 troféus (não tem mais o que perder) e o vencedor bem alto.
-- Nada é punido automaticamente: confira e decida (ver o fim do arquivo).
-- =====================================================================

with partidas as (                        -- cada partida da Batalha online que terminou com vencedor
  select least(heroes, monsters) as j1, greatest(heroes, monsters) as j2,
         case vencedor when 'heroes' then heroes when 'monsters' then monsters end as quem_venceu,
         case vencedor when 'heroes' then monsters when 'monsters' then heroes end as quem_perdeu,
         criada_em
    from partidas_pvp
   where finalizada and not amistoso and coalesce(modo, 'normal') = 'normal'
     and vencedor in ('heroes', 'monsters') and heroes is not null and monsters is not null
),
pares as (
  select j1, j2, count(*) as partidas,
         count(*) filter (where quem_venceu = j1) as vitorias_j1,
         count(*) filter (where quem_venceu = j2) as vitorias_j2,
         min(criada_em) as primeira, max(criada_em) as ultima
    from partidas group by j1, j2
),
adversarios as (                          -- com quantas pessoas DIFERENTES cada um já jogou
  select j, count(distinct o) as qtd from (
    select j1 as j, j2 as o from partidas union all select j2, j1 from partidas) x
   group by j
)
select pv.nome  as vencedor,  pv.trofeus as trofeus_vencedor,
       pp.nome  as perdedor,  pp.trofeus as trofeus_perdedor,
       p.partidas,
       round(100.0 * greatest(p.vitorias_j1, p.vitorias_j2) / p.partidas) as pct_mesmo_vencedor,
       coalesce(ap.qtd, 1) - 1 as perdedor_outros_adversarios,
       to_char(p.primeira at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as primeira,
       to_char(p.ultima   at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as ultima,
       case when p.vitorias_j1 >= p.vitorias_j2 then p.j1 else p.j2 end as id_vencedor,
       case when p.vitorias_j1 >= p.vitorias_j2 then p.j2 else p.j1 end as id_perdedor
  from pares p
  left join perfis pv on pv.id = case when p.vitorias_j1 >= p.vitorias_j2 then p.j1 else p.j2 end
  left join perfis pp on pp.id = case when p.vitorias_j1 >= p.vitorias_j2 then p.j2 else p.j1 end
  left join adversarios ap on ap.j = case when p.vitorias_j1 >= p.vitorias_j2 then p.j2 else p.j1 end
 where p.partidas >= 6                    -- (pares com poucas partidas não interessam)
 order by greatest(p.vitorias_j1, p.vitorias_j2) desc, p.partidas desc
 limit 50;

-- ---------------------------------------------------------------------
-- SE CONFIRMAR QUE É FARM (faça um de cada vez, conferindo o id na tabela acima):
-- Cada série vencida vale +30 troféus. Ex.: tirar 300 troféus (10 séries) do vencedor:
--
--   update perfis set trofeus = greatest(0, trofeus - 300) where id = 'COLE-O-id_vencedor-AQUI';
--
-- (Tire as duas linhas "--" do começo para rodar. Não tem como desfazer sozinho: anote o valor antes.)
-- ---------------------------------------------------------------------
