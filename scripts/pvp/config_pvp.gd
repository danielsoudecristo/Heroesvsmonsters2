class_name ConfigPvp
extends RefCounted
## NÚMEROS DA BATALHA PvP (os mesmos do jogo.js do site). Ajuste aqui.
##
## COMO FUNCIONA (igual ao site):
## - Cada lado tem a SUA arena e o SEU castelo. As tropas andam até o PORTAL da ponta da arena,
##   atravessam e aparecem na arena do outro, indo até o castelo dele.
## - Por dentro a partida é sempre igual (heróis na arena da esquerda, monstros na da direita);
##   quem joga de Monsters só vê a tela espelhada (o castelo dele também fica à esquerda).
## - Só vence quem DERRUBA o castelo do outro (PvP, Cerco e Campeonato). Não conta quem matou mais,
##   NÃO tem relógio de fim e NÃO tem empate. O relógio da tela só conta quanto tempo a batalha já dura.
## - MARÉ DE GUERRA (ver MARE abaixo): a cada minuto a batalha esquenta — cai mais energia do céu, as cartas
##   recarregam mais rápido e (das marés altas em diante) o castelo leva mais dano. Resultado: cada vez MAIS
##   personagens na arena, até um castelo cair. Se ainda assim demorar, vem a MORTE SÚBITA (só o castelo mais fraco desmorona).

const C := preload("res://scripts/arena/config_arena.gd")

# ---------------------------------------------------------------- mapa (duas arenas)
const VAZIO := 1200.0                              ## distância entre as duas arenas (ninguém ataca de uma para a outra)
const MW := C.W * 2.0 + VAZIO                      ## largura do mundo: arena A (0..1280) + vazio + arena B
const PORTAO_X := C.W - 105.0                      ## portal da arena dos heróis (no mundo)
const PORTAO_B := MW - PORTAO_X                    ## portal da arena dos monstros (no mundo)
const CASTELO_HEROES_X := C.G.left - 26.0          ## passou daqui = entrou no castelo dos heróis
const CASTELO_MONSTERS_X := MW - C.G.left + 26.0   ## passou daqui = entrou no castelo dos monstros

# ---------------------------------------------------------------- partida
## MARÉ DE GUERRA: sobe 1 nível a cada "a_cada" segundos de batalha (depois do preparo), até "max".
## Por nível (o índice 0 é a maré 1): quantas vezes MAIS energia cai do céu (mais rápido), energia a mais em
## cada gota, quantas vezes mais rápido as cartas recarregam e o dano que o castelo leva.
## MORTE SÚBITA: depois de "morte_subita" s de batalha, o castelo com MENOS vida perde "desmorona" por segundo
## (se os dois estiverem iguais, os dois). Sempre termina com um castelo no chão — e sem empate (ver _desempate).
const MARE := {
	"a_cada": 60.0, "max": 5,
	"sol_ritmo":   [1.0, 1.35, 1.7, 2.1, 2.5],
	"sol_extra":   [0, 5, 10, 15, 25],
	"recarga":     [1.0, 1.2, 1.4, 1.65, 1.9],
	"dano_castelo": [1.0, 1.0, 1.5, 2.0, 3.0],
	"morte_subita": 330.0, "desmorona": 1.5,
}
const PREPARO := 25.0                              ## segundos para montar a arena (ninguém anda até acabar)
const ENERGIA_INICIAL := 150                       ## energia de cada lado no começo
const SOL := {"cada_min": 5.0, "cada_max": 8.0, "valor": 25}   ## energia que cai do céu em CADA arena
const VIDA_CASTELO := 100.0
const MOEDAS := {"vitoria": 30, "derrota": 10, "empate": 15}    ## contra o bot (no online também valem troféus; "empate" não acontece mais)
const BUSCA_ESPERA := 10.0                         ## segundos procurando adversário antes de cair no bot
## TROFÉUS CONTRA O BOT (só na Batalha; derrota não tira). Com conta quem manda é o servidor
## (supabase/34_trofeus_bot.sql, com os MESMOS números); convidado soma no aparelho.
const TROFEUS_BOT := {"facil": 5, "medio": 10, "dificil": 15, "hardcore": 20, "dia": 100}

static func trofeus_bot(nivel: int) -> int:
	if nivel <= 4:
		return int(TROFEUS_BOT.facil)
	if nivel <= 8:
		return int(TROFEUS_BOT.medio)
	if nivel <= 12:
		return int(TROFEUS_BOT.dificil)
	return int(TROFEUS_BOT.hardcore)

# ---------------------------------------------------------------- CERCO (em todos os modos)
## Quem ataca de LONGE (e o Sentinela/Titã) para no 2º quadrado antes do castelo inimigo e ataca o castelo.
## Quem luta de PERTO entra no castelo e dá dano.
const DE_LONGE := ["arqueiro", "mago", "magoFogo", "engenheiro", "esqueletoArqueiro", "esqueletoMago", "esqueletoBombardeiro"]
const PODER_NO_CASTELO := ["sentinela", "esqueletoTita", "golemOssos"]
const DANO_TIRO_CASTELO := 3                       ## flecha / magia que acerta o castelo
const DANO_PODER_CASTELO := 8                      ## onda de terra / ossos que acerta o castelo
const DANO_ENTRAR_HEROI := 10                      ## herói de perto que entra no castelo dos monstros
const CERCO_CADA := 2.0                            ## tempo mínimo entre um ataque no castelo e outro

## Onde cada lado para no cerco (2º quadrado antes do castelo inimigo), no mundo.
static func x_cerco_herois() -> float:
	return MW - C.cel_x(1)

static func x_cerco_monstros() -> float:
	return C.cel_x(1)

# ---------------------------------------------------------------- heróis andando (MODO_MONSTERS.andar do site)
## velocidade (px/s) e "para" = a quantos pixels do inimigo ele para para lutar (quem atira para mais longe).
## Se a ficha tiver extra.andar (o medir_andar.gd grava), vale o da ficha.
const ANDAR := {
	"padrao": {"velocidade": 30.0, "para": 45.0, "pausa": 0.35},
	"nick": {"velocidade": 33.0, "para": 45.0},
	"arqueiro": {"velocidade": 52.0, "para": 330.0},
	"sentinela": {"velocidade": 44.0, "para": 60.0},
	"protetor": {"velocidade": 45.0, "para": 45.0},
	"mago": {"velocidade": 28.0, "para": 270.0},
	"magoFogo": {"velocidade": 39.0, "para": 270.0},
	"engenheiro": {"velocidade": 53.0, "para": 300.0},
	"darian": {"velocidade": 45.0, "para": 80.0},
	"aura": {"velocidade": 34.0, "para": 330.0},
}

static func andar(id: String) -> Dictionary:
	var d: Dictionary = ANDAR.padrao.duplicate()
	d.merge(ANDAR.get(id, {}), true)
	return d

# ---------------------------------------------------------------- cartas
const CARTAS_HEROES := ["elara", "nick", "arqueiro", "protetor", "mago", "magoFogo", "sentinela", "engenheiro", "darian", "aura"]
const CARTAS_MONSTERS := ["esqueletoBlack", "esqueleto", "esqueletoFogo", "esqueletoArqueiro", "esqueletoBombardeiro", "esqueletoProtetor", "esqueletoMago", "esqueletoMistico", "esqueletoTita", "golemOssos"]

# ---------------------------------------------------------------- BOT
## Começa no FÁCIL. A cada vitória contra o bot ele sobe 1 nível e fica mais difícil (fica salvo no aparelho). Derrota: desce 1.
## A dificuldade vem de ele JOGAR MELHOR (não de trapaça): junta energia com a Elara, defende a linha em perigo,
## escolhe a tropa certa e, nos níveis altos, guarda energia e manda uma HORDA (um monte de tropas juntas).
## Os números vão do nível 1 (primeiro valor) ao nível máximo (segundo valor).
# ---------------------------------------------------------------- MODO CERCO (2 rodadas: um DEFENDE, o outro ATACA, depois troca)
## Quem defende: as tropas ficam PARADAS guardando o castelo. Quem ataca: as tropas marcham (rápido até o portal).
## A rodada só acaba quando o castelo de quem defende CAI (sem relógio de fim: a MARÉ sobe igual à da Batalha e,
## depois de "morte_subita" s, o castelo de quem defende desmorona). Ganha quem derrubou o castelo do outro
## mais rápido. Empatou no tempo? Ganha quem gastou MENOS energia no ataque (e, se nem isso, quem atacou primeiro, às cegas).
const MODO_CERCO := {
	"morte_subita": 210.0,   ## segundos de ataque até o castelo de quem defende começar a desmoronar sozinho
	"preparo": 15.0,         ## segundos para montar antes de cada rodada
	"intervalo": 5.0,        ## pausa entre a rodada 1 e a 2
	"energia_defesa": 100,   ## energia extra de quem defende (precisa montar a defesa logo)
	"marcha": 2.5,           ## quem ataca anda X vezes mais rápido na própria arena (até o portal)
	"primeiro_defende": "heroes",
	"moedas": {"vitoria": 40, "derrota": 15, "empate": 20},
}

const BOT := {
	"maximo": 15, "derrota_diminui": 1,
	"pensa_facil": [3.0, 6.0], "pensa_dificil": [1.1, 2.2],     ## segundos entre uma jogada e outra
	"pega_facil": 2.5, "pega_dificil": 0.6,                      ## segundos até ele pegar a energia que caiu
	"energia_inicial_por_nivel": 8,                              ## energia a mais no começo, por nível (pouca)
	"energia_por_segundo_por_nivel": 0.12,                       ## energia extra que ele ganha sozinho (pouca)
	"colunas": 3, "colunas_max": 5,                              ## em quantas colunas (perto do castelo dele) ele coloca tropas
	"nivel_tropas": [0.6, 1.0],                                  ## nível das tropas dele = isso x a média dos SEUS níveis
	"geradores": [1, 3],                                         ## quantas Elaras / Esqueletos Black ele quer ter
	"reage": [0.3, 0.95],                                        ## chance de defender a linha em perigo
	"esperto": [0.15, 0.95],                                     ## chance de escolher a tropa certa (o resto é sorteio)
	"horda_energia": [200, 380],                                 ## energia que ele junta antes de mandar uma horda
	"horda_tamanho": [2, 5],                                     ## quantas tropas vêm na horda
	"horda_a_partir": 3,                                         ## nível do bot em que as hordas começam
}
## Jeito de jogar (um por partida, sorteado): muda um pouco os números acima.
const ESTILOS := {
	"atacante":   {"nome": "Atacante",   "geradores": -1, "reage": 0.8, "horda_energia": 0.8, "horda_tamanho": 1},
	"defensor":   {"nome": "Defensor",   "geradores": 0,  "reage": 1.2, "horda_energia": 1.3, "horda_tamanho": 0},
	"economista": {"nome": "Economista", "geradores": 1,  "reage": 1.0, "horda_energia": 1.15, "horda_tamanho": 1},
}
## Nome da dificuldade do bot pelo nível (aparece na partida).
static func nome_nivel_bot(n: int) -> String:
	if n <= 4:
		return "Fácil"
	if n <= 8:
		return "Médio"
	if n <= 12:
		return "Difícil"
	return "HardCore"

## Nomes que aparecem quando a busca cai no bot (iguais aos do site).
const NOMES := ["Lucas", "Gabriel", "Rafa", "Bia", "Pedro", "Júlia", "Davi", "Mateus", "Ana", "Enzo", "Lara", "Theo",
	"Guilherme", "Sofia", "Caio", "Nina", "Arthur", "Malu", "Bruno", "Lívia", "Igor", "Yasmin", "Vitor", "Duda"]
const SOBRENOMES := ["", "", "_BR", "Gamer", "Pro", "XD", "07", "99", "_GG", "Rei", "TV", "2010"]

static func nome_adversario() -> String:
	var n: String = NOMES[randi() % NOMES.size()]
	var s: String = SOBRENOMES[randi() % SOBRENOMES.size()]
	return n + s + (str(randi_range(10, 99)) if randf() < 0.35 else "")
