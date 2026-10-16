class_name Progressao
extends RefCounted
## PROGRESSÃO DA CONTA: níveis (força) e maestria (visual).
## Tudo que é número de balanceamento fica aqui. No futuro estes valores podem vir do Supabase
## (tabela config_app) para ajustar sem atualizar o app.
##
## IMPORTANTE: o servidor (Supabase) precisa cobrar os MESMOS preços. Quando mudar aqui, mude lá.

# ---------- NÍVEIS 1 a 15: deixam o personagem mais forte (IGUAL AO SITE: perfil.js PERSONAGENS_CONTA) ----------
## O servidor cobra os mesmos preços: supabase/3_social.sql (custo_nivel e subir_nivel).
const NIVEL_MAX := 15
const BONUS_POR_NIVEL := 0.08           ## +8% de vida e dano por nível (nível 15 = +112%): evoluir é o que faz passar dos marcos
## PRECOS[n-1] = moedas para ir do nível n para o n+1 (14 valores). Total até o 15: 81.400 moedas.
const PRECOS: Array[int] = [50, 100, 200, 350, 600, 1000, 1600, 2500, 4000, 6000, 9000, 13000, 18000, 25000]
const HABILIDADES_NOS: Array[int] = [5, 10, 15]   ## níveis em que abrem as habilidades (em breve)

# ---------- MAESTRIA: infinita, só visual (borda, aura, título, skins) ----------
const MAESTRIA_BASE := 200              ## XP para a 1ª estrela
const MAESTRIA_CURVA := 1.25            ## quanto cada estrela fica mais cara
const MAESTRIA_XP := {                  ## XP que o personagem ganha ao ser usado
	"partida_campanha": 10,
	"partida_pvp": 20,
	"vitoria_pvp": 15,                  ## a mais, quando vence
	"abate": 1                          ## por inimigo derrubado (com limite por partida)
}
const MAESTRIA_ABATES_MAX := 30         ## abates que contam por partida (evita farm)
## Recompensas visuais por estrela (o resto das estrelas só soma no contador).
const MAESTRIA_RECOMPENSAS := {
	1: "borda_bronze", 5: "borda_prata", 10: "borda_ouro", 25: "aura",
	50: "titulo_mestre", 100: "skin_lendaria", 250: "borda_lendaria", 500: "titulo_imortal"
}

# ---------- MOEDAS (as mesmas regras do perfil.js de hoje) ----------
const MOEDAS := {
	"iniciais": 100,
	"pvp_vitoria": 50, "pvp_derrota": 15,
	"trofeus_vitoria": 30, "trofeus_derrota": -20,
	"campanha_nivel": 20, "campanha_chefe": 40,
	"lado_em_alta": 0.5,                ## +50% no lado em alta do dia
	"dois_lados": 150                   ## jogar os dois lados no mesmo dia
}

## Multiplicador de vida/dano de um personagem no nível n.
static func multiplicador(nivel: int) -> float:
	return 1.0 + BONUS_POR_NIVEL * (clampi(nivel, 1, NIVEL_MAX) - 1)

## Moedas para subir do nível n para o n+1 (-1 = já está no máximo).
static func custo_proximo(nivel: int) -> int:
	if nivel >= NIVEL_MAX or nivel < 1:
		return -1
	return PRECOS[nivel - 1]

## Total de moedas para ir do nível 1 até o nível n.
static func custo_total_ate(nivel: int) -> int:
	var t := 0
	for i in range(1, mini(nivel, NIVEL_MAX)):
		t += PRECOS[i - 1]
	return t

## Quantas habilidades estão abertas no nível n.
static func habilidades_abertas(nivel: int) -> int:
	var n := 0
	for h in HABILIDADES_NOS:
		if nivel >= h:
			n += 1
	return n

## XP de maestria para passar da estrela e para a e+1.
static func maestria_xp_para(estrela: int) -> int:
	return roundi(MAESTRIA_BASE * pow(estrela + 1, MAESTRIA_CURVA))

## Converte o XP total em {estrela, xp_na_estrela, xp_para_proxima}.
static func maestria_de(xp_total: int) -> Dictionary:
	var e := 0
	var resto := xp_total
	while resto >= maestria_xp_para(e):
		resto -= maestria_xp_para(e)
		e += 1
	return {"estrela": e, "xp": resto, "proxima": maestria_xp_para(e)}

## Recompensa visual mais alta já liberada.
static func maestria_recompensa(estrela: int) -> String:
	var r := ""
	for k in MAESTRIA_RECOMPENSAS:
		if estrela >= k:
			r = MAESTRIA_RECOMPENSAS[k]
	return r
