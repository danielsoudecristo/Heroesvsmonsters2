class_name ConfigArena
extends RefCounted
## NÚMEROS DA ARENA E DA CAMPANHA (os mesmos do jogo.js). Ajuste aqui.

const W := 1280.0
const H := 720.0
const HUD_H := 118.0
## Grade encaixada na terra da imagem de fundo: 5 linhas x 9 colunas.
## GRADE: 5 linhas x 9 colunas encaixadas na terra do fundo.
## Para alinhar: no Inspetor da Arena ligue "Mostrar Grade", rode, e ajuste left/top (posição) e cw/ch (tamanho da casa).
const G := {"left": 310.0, "top": 180.0, "cw": 100.0, "ch": 94.0, "rows": 5, "cols": 9}
const PES_DY := -14.0                    ## os pés ficam 14 px acima do fundo da casa
const ENTRADA_X := 1250.0                ## onde os inimigos das ondas entram (direita)
const INVADE_X := 310.0 - 26.0           ## passou daqui = chegou no castelo
const NUCLEO := Vector2(150, 405)        ## portão do castelo (efeitos de dano)
const CONTATO_MONSTRO := 50.0            ## distância em que o esqueleto para e bate no herói (igual ao site)
const ATK_MONSTRO := 1.0                 ## segundos entre um golpe e outro do esqueleto (igual ao site)

## CAMPANHA: cada nível começa com o campo LIMPO e só esta energia (+ o bônus da dificuldade: dif.energia_ini).
## Depois, energia só vem clicando nas energias (do céu e das Elaras). Nada passa de um nível para o outro.
const ENERGIA_INICIAL := 200
## Os níveis altos começam com mais energia (o campo começa limpo, mas os inimigos já vêm fortes):
## dá para montar a defesa antes da 1ª onda. +8 por nível, até +240 (nível 31).
const ENERGIA_POR_NIVEL := 8
const ENERGIA_POR_NIVEL_MAX := 240

static func energia_inicial(n: int) -> int:
	return ENERGIA_INICIAL + mini(ENERGIA_POR_NIVEL_MAX, (n - 1) * ENERGIA_POR_NIVEL)
## Ordem das cartas na barra (igual ao site). Personagem novo que não estiver aqui vai para o fim.
const ORDEM_CARTAS := ["elara", "nick", "arqueiro", "protetor", "mago", "magoFogo", "sentinela", "engenheiro", "darian", "aura"]
## A mesma ordem do outro lado: quando o jogador é Monsters, a barra mostra os monstros nesta ordem.
const ORDEM_CARTAS_MONSTROS := ["esqueletoBlack", "esqueleto", "esqueletoFogo", "esqueletoArqueiro", "esqueletoBombardeiro", "esqueletoProtetor", "esqueletoMago", "esqueletoMistico", "esqueletoTita", "golemOssos"]
const ENERGIA_CEU := {"valor": 25, "intervalo_min": 6.0, "intervalo_max": 9.0, "duracao": 9.0}
const ENERGIA_TOQUE := 55.0              ## raio para pegar a energia com o dedo (px)
const ENERGIA_ZONA_SEGURA := 80.0        ## tocou até aqui de uma energia: não coloca herói (evita colocar sem querer)
const ESCONDER_CARTAS_AO_COLOCAR := true ## guarda as cartas depois de colocar um herói
const ESPIAR_CUSTO := 50                ## energia para espiar os próximos monstros
const ESPIAR_DURACAO := 6.0             ## segundos mostrando
## DIFICULDADE DA CAMPANHA (escolhe no Novo jogo; fica no Perfil.dificuldade).
## forca = vida e dano dos monstros · qtd = quantidade de monstros · energia_dura = segundos da energia no chão
## energia_ini = energia a mais no começo de cada nível (compensa os inimigos mais fortes) · ceu_mult = quanto vale cada orbe do céu
## chefe_extra = chefões a mais nos níveis com chefão · perde_tudo = perdeu volta para o nível 1 · moedas = multiplica as moedas
## MONTE (igual Plants vs Zombies): rajada = chance de vir um "monte" de monstros juntos · rajada_max = até quantos
## horda = a ÚLTIMA onda de cada nível é a GRANDE HORDA: tantas vezes mais monstros, vindo em montes
const DIFICULDADES := {
	"facil":    {"nome": "Fácil",    "forca": 0.75, "qtd": 0.8,  "energia_dura": 12.0, "energia_ini": 100, "ceu_mult": 1.2,  "chefe_extra": 0, "perde_tudo": false, "moedas": 0.75, "rajada": 0.04, "rajada_max": 3, "horda": 1.1,  "cor": Color("6fd64a")},
	"medio":    {"nome": "Médio",    "forca": 1.0,  "qtd": 1.0,  "energia_dura": 9.0,  "energia_ini": 50,  "ceu_mult": 1.0,  "chefe_extra": 0, "perde_tudo": false, "moedas": 1.0,  "rajada": 0.08, "rajada_max": 4, "horda": 1.2,  "cor": Color("f6c343")},
	"dificil":  {"nome": "Difícil",  "forca": 1.25, "qtd": 1.2,  "energia_dura": 7.0,  "energia_ini": 75,  "ceu_mult": 1.1,  "chefe_extra": 0, "perde_tudo": false, "moedas": 1.5,  "rajada": 0.12, "rajada_max": 5, "horda": 1.35, "cor": Color("ff8a3a")},
	"hardcore": {"nome": "HardCore", "forca": 1.4,  "qtd": 1.35, "energia_dura": 6.0,  "energia_ini": 120, "ceu_mult": 1.25, "chefe_extra": 1, "perde_tudo": true,  "moedas": 2.0,  "rajada": 0.16, "rajada_max": 6, "horda": 1.5,  "cor": Color("d63a5a")},
}
const ORDEM_DIFICULDADES := ["facil", "medio", "dificil", "hardcore"]
## CAMPANHA INFINITA: a força dos inimigos é poder_inimigo(n) (lá embaixo, "CURVA DE DIFICULDADE"):
## sobe a cada nível, salta nos marcos e depois do 60 acelera — sempre chega a hora em que não dá mais.

## A GRANDE HORDA cresce devagar com o nível (até +15%): o fim de cada nível fica cada vez mais épico.
static func horda_do_nivel(n: int) -> float:
	return 1.0 + minf(0.15, maxi(0, n - 1) * 0.008)

const RAJADA_INTERVALO := 0.35           ## dentro de um monte, os monstros vêm a cada 0,35 x o intervalo normal

static func dificuldade(id := "") -> Dictionary:
	if id == "":
		id = Perfil.dificuldade
	return DIFICULDADES.get(id, DIFICULDADES.medio)

## Segundos que a energia fica no chão agora (a campanha muda pela dificuldade; o PvP usa sempre ENERGIA_CEU.duracao).
static var energia_dura := 9.0

const COLETA_AUTOMATICA := 0.0           ## 0 = IGUAL PLANTS VS ZOMBIES: energia que ninguém clicou some (ENERGIA_CEU.duracao)
const ENERGIA_PISCA := 3.0               ## nos últimos segundos antes de sumir, a energia pisca (aviso)
const ENERGIA_MARGEM_ONLINE := 1.5       ## ONLINE: o clique leva um tempinho para chegar; a partida espera isso antes de apagar

## Visível agora? (pisca cada vez mais rápido perto de sumir)
static func energia_visivel(t: float, agora: float) -> bool:
	var falta := energia_dura - t
	if COLETA_AUTOMATICA > 0 or falta > ENERGIA_PISCA:
		return falta > 0 or COLETA_AUTOMATICA > 0
	if falta <= 0:
		return false
	var ritmo := lerpf(4.0, 10.0, 1.0 - falta / ENERGIA_PISCA)
	return fmod(agora * ritmo, 1.0) < 0.6

const VIDA_CASTELO := 100
const CAMPANHA := {
	"preparo": 25.0, "preparo_nivel1": 50.0, "preparo_extra_nivel": 0.5, "preparo_extra_max": 10.0,
	"pausa_entre_ondas": 9.0, "pausa_entre_niveis": 6.0,
	"noite_valor_mult": 0.5, "noite_intervalo_mult": 1.6,
	"chefao": "esqueletoTita", "chefe_vida": 1.6, "chefe_dano": 1.3, "chefe_castelo": 60,   # chefão que entra tira 60 do castelo
	"estrelas_tres": 80, "estrelas_duas": 45,
}
const LETRA_MONSTRO := {"e": "esqueleto", "a": "esqueletoArqueiro", "f": "esqueletoFogo", "p": "esqueletoProtetor", "m": "esqueletoMago",
	"b": "esqueletoBombardeiro", "g": "golemOssos", "x": "esqueletoMistico"}

const FASES := [
	{"nome": "Primeiros Passos", "dica": "Coloque a Elara logo no começo: ela gera energia.", "ondas": [{"e": 3}, {"e": 4}]},
	{"nome": "Patrulha de Ossos", "dica": "Junte energia antes da segunda onda.", "ondas": [{"e": 4}, {"e": 6}]},
	{"nome": "Chuva de Flechas", "dica": "Arqueiros param perto do castelo e atiram: derrube-os!", "ondas": [{"e": 4, "a": 1}, {"e": 5, "a": 2}]},
	{"nome": "Marcha Sombria", "dica": "Três ondas: guarde energia entre elas.", "ondas": [{"e": 6, "a": 1}, {"e": 7, "a": 2}, {"e": 6, "a": 2}]},
	{"nome": "O Primeiro Titã", "dica": "No fim vem o chefão! A onda de ossos acerta a linha toda.", "ondas": [{"e": 6, "a": 2}, {"e": 8, "a": 2}], "chefes": 1},
	{"nome": "Fogo no Campo", "dica": "O Esqueleto de Fogo é forte: tenha defesa nas linhas.", "ondas": [{"e": 5, "f": 1}, {"e": 6, "f": 2, "a": 1}]},
	{"nome": "O Cerco", "dica": "Muitos arqueiros! Magos acertam vários de uma vez.", "ondas": [{"e": 6, "a": 3}, {"e": 6, "f": 2, "a": 2}, {"e": 8, "a": 3}]},
	{"nome": "Muralha de Escudos", "dica": "O Protetor bloqueia golpes: use magia e a onda de terra.", "ondas": [{"e": 6, "p": 1}, {"e": 6, "p": 2, "a": 2}, {"e": 8, "p": 2, "f": 2}]},
	{"nome": "Chuva de Bombas", "dica": "NOVO: o Bombardeiro joga bombas de longe! Nick e Sentinela chegam rápido nele.", "ondas": [{"e": 8, "b": 1}, {"e": 8, "a": 2, "b": 1}, {"e": 10, "p": 2, "b": 2}]},
	{"nome": "Rei dos Ossos", "dica": "Chefão de novo, agora mais forte!", "ondas": [{"e": 8, "a": 3, "f": 2}, {"e": 10, "p": 2, "a": 3, "f": 2}], "chefes": 1},
	{"nome": "Feitiçaria", "dica": "NOVO: o Esqueleto Místico CURA os esqueletos e invoca 3 de fogo do chão! Arqueiro e Nick derrubam ele primeiro.", "ondas": [{"e": 6, "m": 1}, {"e": 8, "a": 2, "m": 1}, {"e": 8, "p": 2, "f": 1, "x": 1}]},
	{"nome": "Noite Sem Fim", "dica": "De noite a energia do céu cai devagar e vale menos: leve a Elara.", "ondas": [{"e": 8, "a": 2}, {"e": 7, "f": 2, "m": 1}, {"e": 8, "p": 2, "a": 1, "b": 1}]},
	{"nome": "Paredão", "dica": "Escudos! Mago de Fogo e Engenheiro furam a defesa deles.", "ondas": [{"e": 5, "p": 3}, {"e": 3, "p": 3, "a": 3}, {"p": 4, "f": 2, "m": 1}]},
	{"nome": "Inferno", "dica": "Fogo em todas as linhas! Sentinela e Protetor seguram o fogo.", "ondas": [{"e": 5, "f": 4}, {"e": 3, "f": 4, "a": 2, "b": 1}, {"f": 5, "p": 2, "m": 1, "b": 1}]},
	{"nome": "Dois Titãs", "dica": "Agora são DOIS chefões: Engenheiro e Sentinela derrubam Titãs.", "ondas": [{"e": 8, "a": 3, "f": 2}, {"e": 8, "p": 2, "m": 1, "x": 1}], "chefes": 2},
]
const NOMES_EXTRAS := ["Vale dos Mortos", "Lua de Sangue", "Cripta Antiga", "Fúria dos Ossos", "Exército da Noite",
	"Tempestade de Flechas", "Portões do Abismo", "Névoa Maldita", "Marcha Final", "Coroa de Ossos"]

## TOQUE/CLIQUE: posição no espaço do nó, ou Vector2.INF se não for um toque novo.
## No celular o Android manda o toque E um "mouse de mentira" junto: o de mentira é ignorado (senão conta 2 vezes).
static func pos_toque(no: CanvasItem, ev: InputEvent) -> Vector2:
	if ev is InputEventMouseButton:
		if not ev.pressed or ev.button_index != MOUSE_BUTTON_LEFT or ev.device == InputEvent.DEVICE_ID_EMULATION:
			return Vector2.INF
	elif ev is InputEventScreenTouch:
		if not ev.pressed:
			return Vector2.INF
	else:
		return Vector2.INF
	return no.make_input_local(ev).position

## TELAS LARGAS (celular): o jogo de 1280x720 fica no MEIO da tela e o fundo cobre as laterais.
## camadas = as CanvasLayer do HUD (andam junto). Devolve o deslocamento usado.
static func centralizar(no: Node, camadas: Array) -> Vector2:
	var vis := no.get_viewport().get_visible_rect().size
	var d := ((vis - Vector2(W, H)) / 2.0).max(Vector2.ZERO)
	no.get_viewport().canvas_transform = Transform2D(0.0, d)
	for c in camadas:
		if c:
			c.offset = d
	return d

## A TELA INTEIRA de verdade (nas coordenadas do próprio nó). No celular largo o jogo fica no meio (centralizar):
## quem pinta só Rect2(0, 0, size) deixa uma faixa vazia na lateral. Janelas por cima (cartas, pausa, derrota...)
## devem pintar o fundo com isto.
static func tela_toda(ci: CanvasItem) -> Rect2:
	var vis := ci.get_viewport().get_visible_rect()
	return (ci.get_global_transform_with_canvas().affine_inverse() * vis).grow(2.0)

## Escala do fundo para cobrir a tela inteira (com as laterais), sem deixar faixa vazia.
static func escala_fundo(no: Node, tex: Texture2D) -> float:
	var vis := no.get_viewport().get_visible_rect().size
	return maxf(maxf(H, vis.y) / tex.get_height(), maxf(W, vis.x) / tex.get_width())

static func cel_x(c: int) -> float:
	return G.left + c * G.cw + G.cw / 2.0

static func linha_y(r: int) -> float:
	return G.top + (r + 1) * G.ch + PES_DY

## Casa (coluna, linha) de um ponto da tela, ou (-1,-1) se estiver fora da grade.
static func casa_em(p: Vector2) -> Vector2i:
	var c := int(floor((p.x - G.left) / G.cw))
	var r := int(floor((p.y - G.top) / G.ch))
	if c < 0 or c >= G.cols or r < 0 or r >= G.rows:
		return Vector2i(-1, -1)
	return Vector2i(c, r)

static func eh_noite(n: int) -> bool:
	return int(floor((n - 1) / 2.0)) % 2 == 1

## FUNDO DA CAMPANHA: a cada NIVEIS_POR_FUNDO níveis (um dia + uma noite) a arena muda de estação.
## Quem não tem a arte da estação (ex.: primavera de noite) usa o fundo normal daquele castelo.
const NIVEIS_POR_FUNDO := 4
const ESTACOES := ["", "primavera", "outono", "halloween", "inverno"]

static func estacao(n: int) -> String:
	return ESTACOES[int(floor((n - 1) / float(NIVEIS_POR_FUNDO))) % ESTACOES.size()]

static func intervalo_monstros(n: int) -> float:
	return maxf(1.1, 3.8 - n * 0.03)

## Nível dos monstros da campanha: sempre 1 — a força deles vem de poder_inimigo(n) (curva abaixo).
static func nivel_monstros(_n: int) -> int:
	return 1

static func fase(n: int) -> Dictionary:
	if n <= FASES.size():
		var f: Dictionary = FASES[n - 1].duplicate()
		f["tema"] = ""
		return f
	# DEPOIS DA FASE 15: cada nível tem um TEMA (um tipo de inimigo manda) — pede cartas diferentes
	var tema: Dictionary = TEMAS[tema_do_nivel(n)]
	var n_ondas := mini(5, 3 + int((n - FASES.size()) / 20.0))
	var ondas: Array = []
	for w in n_ondas:
		# a QUANTIDADE sobe devagar (energia é limitada); quem cresce mesmo é a FORÇA (poder_inimigo),
		# que se vence evoluindo as cartas — é isso que faz evoluir valer a pena
		var qtd := mini(int(QTD_ONDA.max), roundi(float(QTD_ONDA.base) + n * float(QTD_ONDA.por_nivel) + w * float(QTD_ONDA.por_onda)))
		var o := {}
		var resto := qtd
		var letras: Array = tema.peso.keys()
		for i in letras.size():
			var l: String = letras[i]
			var c := resto if i == letras.size() - 1 else mini(resto, roundi(qtd * float(tema.peso[l])))
			if c > 0:
				o[l] = o.get(l, 0) + c
				resto -= c
		ondas.append(o)
	return {"nome": tema.nome, "tema": tema.nome, "dica": tema.dica, "ondas": ondas,
		"chefes": (1 + int(n / 30.0)) if n % 5 == 0 else 0}

# ================================================================= ESTRATÉGIA
## VANTAGENS: quem bate -> em quem -> multiplicador do dano. É o que faz a pessoa usar TODAS as cartas:
## cada inimigo tem quem acaba com ele (o texto do nível mostra). Vale nos dois lados da campanha
## (jogando de Monsters, os monstros usam a vantagem do seu "par" herói contra o par do alvo).
const VANTAGEM := {
	"arqueiro": {"esqueleto": 1.3, "esqueletoMago": 1.4, "esqueletoMistico": 1.5},
	"nick": {"esqueletoArqueiro": 1.6, "esqueletoMago": 1.3, "esqueletoBombardeiro": 1.6, "esqueletoMistico": 1.5},
	"mago": {"esqueleto": 1.3, "esqueletoArqueiro": 1.4, "golemOssos": 1.5},
	"magoFogo": {"esqueletoProtetor": 1.7, "esqueletoMago": 1.3},
	"engenheiro": {"esqueletoProtetor": 1.5, "esqueletoTita": 1.4, "golemOssos": 1.3},
	"sentinela": {"esqueletoFogo": 1.6, "esqueletoTita": 1.3, "esqueletoBombardeiro": 1.4, "golemOssos": 1.3},
	"protetor": {"esqueletoFogo": 1.4},
	"darian": {"golemOssos": 1.5, "esqueletoTita": 1.4, "esqueletoProtetor": 1.3},
}
## RESISTÊNCIAS: o alvo aguenta mais de certos golpes (fogo não queima o Esqueleto de Fogo...).
const RESISTENCIA := {
	"esqueletoFogo": {"magoFogo": 0.4},
	"esqueletoBombardeiro": {"magoFogo": 0.6},       # vive no meio do fogo: a magia de fogo pega pouco
	"esqueletoProtetor": {"arqueiro": 0.6, "nick": 0.7},
	"esqueletoTita": {"arqueiro": 0.6, "nick": 0.6},
	"golemOssos": {"magoFogo": 0.5, "arqueiro": 0.6, "nick": 0.7},   # feito de ossos e fogo: flecha e espada pegam pouco
}

## Multiplicador do dano de "atq" em "alvo" (1 = normal; >1 = forte contra; <1 = fraco contra).
static func vantagem(atq: String, alvo: String) -> float:
	if atq == "" or alvo == "":
		return 1.0
	if not VANTAGEM.has(atq) and not RESISTENCIA.has(alvo):   # monstro batendo em herói: usa os pares
		var pa := Catalogo.par_de(atq)
		var pb := Catalogo.par_de(alvo)
		if pa and pb:
			atq = pa.id
			alvo = pb.id
	return float(VANTAGEM.get(atq, {}).get(alvo, 1.0)) * float(RESISTENCIA.get(alvo, {}).get(atq, 1.0))

## Quem é forte contra o inimigo "alvo" (ids dos heróis, do mais forte para o menos).
static func fortes_contra(alvo: String) -> Array:
	var l: Array = []
	for atq in VANTAGEM:
		var m := float(VANTAGEM[atq].get(alvo, 1.0))
		if m >= 1.3:
			l.append([m, atq])
	l.sort_custom(func(a, b): return a[0] > b[0])
	return l.map(func(x): return x[1])

## TEMAS (níveis 16+): os pesos dizem quanto de cada inimigo vem. Gira para a pessoa trocar o baralho.
const TEMAS := [
	{"nome": "Horda de Ossos", "peso": {"e": 0.75, "a": 0.25}, "dica": "Muitos esqueletos: Arqueiro e Mago acabam com eles."},
	{"nome": "Muralha de Escudos", "peso": {"p": 0.4, "e": 0.4, "a": 0.2}, "dica": "Escudos! Mago de Fogo e Engenheiro furam a defesa."},
	{"nome": "Brasas", "peso": {"f": 0.4, "e": 0.45, "p": 0.15}, "dica": "Esqueletos de Fogo: Sentinela e Protetor seguram (fogo não queima fogo)."},
	{"nome": "Chuva de Flechas", "peso": {"a": 0.5, "e": 0.35, "f": 0.15}, "dica": "Arqueiros inimigos: o Nick e o Mago derrubam eles."},
	{"nome": "Feitiçaria", "peso": {"m": 0.15, "e": 0.55, "a": 0.3}, "dica": "Esqueletos Magos invocam: Arqueiro e Nick acabam com eles primeiro."},
	{"nome": "Bombardeio", "peso": {"b": 0.12, "e": 0.7, "a": 0.18}, "dica": "Bombardeiros atacam de longe: Nick e Sentinela chegam rápido neles."},
	{"nome": "Forja do Golem", "peso": {"g": 0.07, "e": 0.55, "p": 0.18, "a": 0.2}, "dica": "Golens de Ossos queimam a linha inteira: Mago, Sentinela e Engenheiro derrubam eles. Espalhe as defesas!"},
	{"nome": "Ritual Sombrio", "peso": {"x": 0.08, "m": 0.1, "e": 0.6, "a": 0.22}, "dica": "Místicos curam e abrem portais de fogo: derrube os suportes lá atrás primeiro (Arqueiro e Nick)! A Guerreira Aura purifica TODOS os invocados de uma vez."},
	{"nome": "Caos", "peso": {"e": 0.37, "a": 0.15, "f": 0.13, "p": 0.13, "m": 0.1, "b": 0.07, "x": 0.05}, "dica": "Um pouco de tudo: leve um baralho completo."},
]

static func tema_do_nivel(n: int) -> int:
	return (n * 5 + int(n / 6.0)) % TEMAS.size()           # gira sem repetir o mesmo tema seguido

## MODIFICADORES (a partir do nível 9): cada nível tem os seus (sempre os mesmos naquele nível,
## para o recorde ser justo). A dificuldade e o nível decidem quantos.
const MODS := {
	"couraca":    {"nome": "Couraça", "txt": "inimigos +20% de vida", "vida": 1.2},
	"furia":      {"nome": "Fúria", "txt": "inimigos +20% de dano", "dano": 1.2},
	"pressa":     {"nome": "Pressa", "txt": "inimigos 15% mais rápidos", "vel": 1.15},
	"enxame":     {"nome": "Enxame", "txt": "+30% de inimigos, um pouco mais fracos", "qtd": 1.3, "vida": 0.85},
	"nublado":    {"nome": "Céu Nublado", "txt": "energia do céu -30%", "ceu": 0.7},
	"bencao":     {"nome": "Bênção", "txt": "energia do céu +40%", "ceu": 1.4, "bom": true},
}
const MODS_RUINS := ["couraca", "furia", "pressa", "enxame", "nublado"]

## Nível em que os modificadores começam (1 no começo, +1 a cada MODS_CADA níveis, até 3).
const MODS_DESDE := {"facil": 20, "medio": 12, "dificil": 9, "hardcore": 6}
const MODS_CADA := 15

static func mods_do_nivel(n: int, dif_id: String) -> Array:
	var desde := int(MODS_DESDE.get(dif_id, 12))
	if n < desde:
		return []
	var qtd := clampi(1 + int((n - desde) / float(MODS_CADA)), 0, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = n * 7919 + 17
	var lista: Array = []
	var ruins := MODS_RUINS.duplicate()
	for i in qtd:
		var k: String = ruins[rng.randi() % ruins.size()]
		ruins.erase(k)
		lista.append(k)
	if rng.randf() < 0.18:                                  # de vez em quando uma ajuda
		lista.append("bencao")
	return lista

## Multiplicador de um atributo ("vida", "dano", "vel", "qtd", "ceu") somando os modificadores.
static func mod_mult(mods: Array, chave: String) -> float:
	var m := 1.0
	for k in mods:
		m *= float(MODS[k].get(chave, 1.0))
	return m

# ================================================================= CURVA DE DIFICULDADE
## Força dos inimigos no nível n (vida e dano). Sobe um pouco a cada nível e, de tempos em tempos,
## dá um salto (os MARCOS): é ali que a pessoa sente que precisa evoluir as cartas para passar.
const CURVA := {"por_nivel": 0.04, "salto_marco": 0.15, "depois_60": 0.035}
## Inimigos por onda nos níveis 16+ (base + por nível + por onda, até o máximo).
const QTD_ONDA := {"base": 8, "por_nivel": 0.18, "por_onda": 1.5, "max": 24}
const MARCO_CADA := 10                     ## a cada 10 níveis: chefão do marco, prêmio e ponto de partida

static func poder_inimigo(n: int) -> float:
	var p := 1.0 + CURVA.por_nivel * (n - 1)
	p *= pow(1.0 + CURVA.salto_marco, int((n - 1) / MARCO_CADA))
	p *= 1.0 + CURVA.depois_60 * maxi(0, n - 60)
	return p

# ================================================================= RECOMPENSAS
## Moedas por nível (antes da dificuldade): crescem com o nível — chegar mais longe paga mais,
## e é com elas que se evolui as cartas para ir ainda mais longe.
const PREMIO := {"base": 25, "por_nivel": 5.0, "chefe_por_nivel": 4.0, "marco_por_nivel": 15.0,
	"estrela3": 0.3, "estrela2": 0.1, "recorde": 0.5, "variedade_por_carta": 0.1, "variedade_desde": 3, "variedade_max": 0.5}

static func eh_marco(n: int) -> bool:
	return n % MARCO_CADA == 0

## Níveis em que dá para começar (1 e o nível depois de cada marco já vencido).
static func inicios_liberados(recorde: int) -> Array:
	var l: Array = [1]
	var m := MARCO_CADA
	while m <= recorde:
		l.append(m + 1)
		m += MARCO_CADA
	return l
