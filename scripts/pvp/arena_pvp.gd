extends Node2D
## BATALHA PvP (igual ao site): os heróis de um lado contra os monstros do outro.
## Contra o BOT (com nome de gente quando a busca não acha ninguém) ou ONLINE contra uma pessoa.
##
## COMO FUNCIONA
## - Duas arenas no mesmo "mundo": a dos heróis (x 0..1280) e a dos monstros (espelhada, lá na direita).
##   As tropas andam até o portal da ponta, atravessam e aparecem na arena do outro, indo até o castelo dele.
## - Você vê só a SUA arena (quem é Monsters vê a dele espelhada: o castelo também fica à esquerda).
##   ESPIAR só aparece com tropa sua viva na arena inimiga: leva você até lá (grátis) e volta sozinho quando elas caem.
## - Cada lado tem a sua energia (do céu, da Elara / do Esqueleto Black) e as suas cartas.
## OTIMIZADO: passo fixo de 1/60 s, listas por linha, projéteis reaproveitados, tudo desenhado em poucos nós.
## ONLINE (lockstep, igual ao jogo.js): a sorte usa a MESMA semente nos dois aparelhos e eles só trocam as AÇÕES
## (colocar tropa, pegar energia, espiar). A partida anda em turnos de 10 passos; cada ação vale 3 turnos depois
## (0,5 s: dá tempo de chegar no outro). Um turno só roda quando as ações do adversário para ele já chegaram.
## No fim, os dois mandam o resultado para o servidor (finalizar_pvp): troféus e moedas são dados lá.

const C := preload("res://scripts/arena/config_arena.gd")
const ARENA_CAMPANHA := preload("res://scripts/arena/arena.gd")   # (desenho da flecha)
const P := preload("res://scripts/pvp/config_pvp.gd")
const PASSO := 1.0 / 60.0
## ONLINE: turno = passos por turno; atraso = turnos até a ação valer; desiste_em = segundos sem notícia = vitória por W.O.;
## repete = cada mensagem leva também os 2 turnos anteriores (se uma se perder, a próxima cobre).
const ONLINE := {"turno": 10, "atraso": 3, "desiste_em": 20.0, "pede_de_novo_em": 0.5, "repete": 2, "conectar_em": 25.0}
## PORTAL_TROPA (igual ao site): um portal redondo abre na LINHA de quem chega na ponta da arena,
## a tropa some dentro dele e sai por outro que abre na arena do inimigo. Só enfeite (não muda a partida).
const PORTAL := {"raio": 66.0, "achatado": 0.62, "abrir": 0.35, "fechar": 0.4, "aviso": 95.0, "some": 42.0}
const CORES_FENDA := {
	"heroes": {"a": Color("ffffff"), "b": Color("9fd8ff"), "c": Color("2f6bd6"), "d": Color("0b1640"), "brilho": Color(0.47, 0.75, 1.0), "faisca": Color("e8f6ff"), "runa": Color("ffd97a")},
	"monsters": {"a": Color("f4ffe0"), "b": Color("b6ff6a"), "c": Color("6d2fb8"), "d": Color("12051f"), "brilho": Color(0.59, 1.0, 0.35), "faisca": Color("e9ffd0"), "runa": Color("d6ff8a")},
}
## RAIO DO ENGENHEIRO (igual à campanha): descarga que sai do canhão e eletrocuta quem acerta.
## O choque é PARTIDA (dano): roda no passo fixo e nunca usa o rng compartilhado. O resto é só enfeite.
const RAIO_VEL := 3200.0                   ## px/s da ponta do raio (bem rápido: parece instantâneo)
const RAIO_RECUO := 48.0                   ## puxa o começo do raio para trás (até a boca do canhão no desenho)
const RAIO_SOME := 0.2                     ## segundos que o raio fica tremulando ligado ao alvo depois de acertar
const CHOQUE_PCT := 0.5                    ## choque elétrico: +50% do dano do tiro, em pulsos, enquanto o inimigo treme
const CHOQUE_DUR := 0.75                   ## segundos de choque no inimigo
const CHOQUE_PULSOS := 3                   ## em quantos pulsos o dano do choque é dividido
const MARGEM_VISIVEL := 70.0               ## o inimigo precisa estar esta distância dentro da arena para o Engenheiro atirar
## CERCO DO ENGENHEIRO: do 2º quadrado o raio vai até a PAREDE do castelo (não para na calçada).
const CASTELO_PAREDE_X := 195.0            ## x (na tela da arena) da parede do castelo, onde fica o portão
const CASTELO_Y := [240.0, 470.0]          ## faixa da parede que o raio pode acertar (de cima a baixo)
const RAIO_CASTELO_PCT := 0.3              ## o raio tira 30% do dano do tiro do castelo
const BOMBA_CASTELO_PCT := 0.15            ## a bomba do Bombardeiro tira 15% do dano dela do castelo (110 -> ~16)
const ENGENHEIRO_RECEBE := 0.4            ## o Engenheiro recebe só 40% do dano dos inimigos
const RESULTADO_ONLINE := {"vitoria": "+30 troféus · +50 moedas", "derrota": "−20 troféus · +15 moedas", "empate": "+25 moedas"}

@export var lado_local := ""                ## "heroes" ou "monsters" ("" = o lado escolhido no menu)
@export var nivel_conta := 1                ## nível da conta (depois vem do Supabase)
@export var energia_infinita := false       ## teste
@export var mostrar_fps := false

# ---------------------------------------------------------------- o que o HUD usa (mesmos nomes da campanha)
var pvp := true
var cartas_dados: Array[PersonagemDados] = []
var cartas_todas: Array[PersonagemDados] = []       ## TODAS as cartas do lado (inclusive as bloqueadas)
var selecao: Control                                 ## janela de escolha de cartas antes da partida (selecao_cartas.gd)
var escolhendo := true                               ## true até o jogador confirmar as cartas (trava o passo da partida)
var carta_sel := -1
var nivel_herois := 1
var espiar_t := 0.0
var energia: int:
	get: return int(energias[lado_local])
var vida_castelo: float:
	get: return vidas[lado_local]
var vida_inimigo: float:
	get: return vidas[outro]
var recarga: Dictionary:
	get: return recargas[lado_local]

# ---------------------------------------------------------------- partida
var outro := "monsters"
var energias := {"heroes": 0.0, "monsters": 0.0}
var vidas := {"heroes": P.VIDA_CASTELO, "monsters": P.VIDA_CASTELO}
var recargas := {"heroes": {}, "monsters": {}}
var herois: Array = []                      # [linha] -> Array[Unidade]
var monstros: Array = []
var tempo := 0.0                            # segundos de batalha (conta para CIMA: não tem relógio de fim)
var preparo := P.PREPARO
var mare := 1                               # MARÉ DE GUERRA (1..P.MARE.max): sobe com o tempo de batalha
var dano_feito := {"heroes": 0.0, "monsters": 0.0}   # dano que cada lado já deu no castelo do OUTRO (desempate)
var gasto := {"heroes": 0.0, "monsters": 0.0}        # energia gasta em tropas (CERCO: desempate da rodada)
var fim := false
var vencedor := ""
var abatidas := 0                           # monstros derrotados
var mortos_h := 0                           # heróis derrotados
var sol_t := 2.0
var bot_t := 4.0
var bot_nivel := 1
var campeonato := false                     # esta partida é uma luta do Campeonato (scripts/sistema/campeonato.gd)
var serie_bot := false                      # Batalha contra o BOT em SÉRIE (Perfil.serie_bot), igual à de pessoa real
var bot_estilo := ""                        # atacante / defensor / economista (sorteado por partida)
var bot_nivel_tropa := 1                    # nível das tropas do bot (perto da média dos seus)
var bot_horda := 0                          # tropas da horda que ainda vão sair
var hordas_bot := 0                         # quantas hordas o bot já mandou nesta partida
var adversario := ""
# ---------------------------------------------------------------- MODO CERCO (ConfigPvp.MODO_CERCO)
var modo := "normal"                        ## "normal" (os dois atacam e defendem) ou "cerco" (2 rodadas: um defende, o outro ataca)
var rodada := 1
var defensor := "heroes"                    ## CERCO: quem defende nesta rodada (as tropas dele ficam paradas)
var cerco_res := {}                         ## CERCO: lado -> {tempo, vida} de quando ele defendeu
var intervalo := 0.0                        ## CERCO: pausa entre as rodadas
var cartas_usadas := {}                     ## REGISTRO (painel): id -> quantas vezes você colocou nesta partida
var _t_partida := 0.0
var rng := RandomNumberGenerator.new()
var semente := 0
var passo_n := 0                            # passos da partida desde o começo (60 por segundo)
var prox_id_orbe := 1                       # cada energia tem um número (no online o "pegar" vai pela rede)

# ---------------------------------------------------------------- ONLINE
var rede := {}                              # vazio = contra o bot. Ver _preparar_online()
var canal: RedePvp
var fila_acoes: Array = []                  # ações (minhas e do adversário) esperando o passo delas
var seq_acao := 0
# ---------------------------------------------------------------- REPLAY (36_replays.sql) — só assistir, apaga em 24 h
var replay := {}                            ## assistindo: a "receita" (semente + jogadas). Vazio = jogando de verdade
var assistindo := false                     ## (o HUD lê: no replay os toques são da arena)
var replay_acoes: Array = []                ## online: as jogadas que aconteceram (dos dois lados), para o replay
var replay_vel := 1                         ## velocidade do replay (1x, 2x, 4x)
var ultimo_replay := {}                     ## (o que foi mandado para o servidor no fim da partida online)
var replay_foto := ""                       ## (assistindo) a "foto" do fim: igual à de quem jogou = replay fiel
var replay_alvo := -1                       ## BARRA DO REPLAY: passo para onde está indo (-1 = assistindo normal)
var replay_arrasto := -1                    ## BARRA DO REPLAY: passo embaixo do dedo enquanto arrasta (-1 = não está arrastando)
var barra_replay: Control                   ## BARRA DO REPLAY (desenhada por cima do jogo)
const REPLAY_PASSOS_POR_QUADRO := 600       ## avançando pela barra: quantos passos por quadro (10 s de partida)
var acumulado := 0.0

class Projetil:
	var ativo := false
	var tipo := ""
	var lado := ""
	var linha := 0
	var pos := Vector2.ZERO
	var vel := 0.0
	var dano := 0
	var dano_area := 0
	var raio := 0.0
	var origem_id := ""               # quem atirou (bônus de dano por personagem)
	var fogo := false                 # FLECHA DE FOGO (poder vermelho do Esqueleto Arqueiro): ponta em brasa, queima quem acerta
	var t := 0.0
	var origem := Vector2.ZERO        # (energia) onde o laser saiu do cano
	var mira_y := 0.0                 # (energia) altura da cabeça mirada
	var x_fim := 0.0                  # (energia) x do alvo no disparo (referência da curva)
	var alvo_ref: Unidade = null      # (energia) quem a energia mira (acompanha a cabeça)
	var fixado := false               # (energia) já acertou: o feixe gruda no alvo e se apaga lá
	var t_fixado := 0.0               # (energia) quanto tempo faz que acertou
	var semente := 0                  # (energia) forma do raio — só enfeite (não usa o rng da partida)
	var castelo := ""                 # (energia) cerco: lado do castelo que o raio vai acertar ("" = mira em tropa)

class Onda:
	var tipo := ""
	var lado := ""
	var linha := 0
	var x := 0.0
	var vel := 0.0
	var dano := 0
	var atingidos: Dictionary = {}
	var no_castelo := false
	var x0 := 0.0                       # de onde saiu (o rastro de fogo do Golem)
	var idade := 0.0

var projeteis: Array[Projetil] = []
var ondas: Array[Onda] = []
var textos: Array = []                      # {pos, txt, cor, t}
var explosoes: Array = []                   # [pos, raio, t, cor]
var impactos: Array = []                    # {pos, t} — flash do laser do Engenheiro na cabeça
var orbes: Array = []                       # {pos, alvo_y, valor, t, lado, x0}
var voos: Array = []                        # energia voando na tela até o painel {de, t, valor}
var faiscas: Array = []                     # brilho do portal {pos, vel, t, cor}
var choques: Array = []                     # {alvo, t, dano, pulsos, semente} — inimigo eletrocutado pelo Engenheiro
var fx_chao: FxExplosao
var fx_ar: FxExplosao
var clarões: Array = []                     # {pos, t, dir} — clarão no cano do Engenheiro (enfeite)
var golpes_castelo: Array = []              # {pos, t, semente, dir} — raio explodindo na parede do castelo (enfeite)
var estilhacos: Array = []                  # {pos, vel, t, giro, tam, cor} — pedras que voam da parede (enfeite)
var marcas: Array = []                      # {pos, t} — marca queimada com rachaduras brilhando na parede (enfeite)
var _rng_fx := RandomNumberGenerator.new()  # forma dos raios (enfeite: NUNCA o rng da partida)
var fendas: Array = []                      # PORTAL_TROPA: portais que abrem na linha de quem passa (só enfeite)

# ---------------------------------------------------------------- tela
var espiando := false
var mundo: Node2D
var camada_unidades: Node2D
var desenho: Node2D
var fenda_corpo: Node2D
var fenda_luz: Node2D
var desenho_tela: Node2D
var fundo: Sprite2D
var _uid_n := 0                                     # número de cada tropa criada (comandos do menu online)
var menu_unidade: Control                           # menu do personagem (parar / andar / voltar / poderes / remover)
var tochas: Node2D                                  # fogo vivo nas tochas do fundo (tochas_fundo.gd)
var _estacao_pvp := "?"                             # estação do fundo desta partida (sorteada uma vez)
var ui: CanvasLayer
var camada_painel: CanvasLayer
var hud: Control
var lbl_banner: Label
var banner_t := 0.0
var lbl_fps: Label
var painel: Control                         # fim de jogo / pausa
var painel_titulo := ""
var painel_texto := ""
var painel_bons: Array[Button] = []
var troca_t := 0.0                          # clarão da troca de arena (espiar)
var _avisou_invasao := false                # já avisou "sua tropa entrou na arena inimiga" nesta partida
var f_titulo: Font
var f_texto: Font

# =================================================================== INÍCIO
func _ready() -> void:
	Conta.tela_provedor = foto_ao_vivo              # (painel: assistir ao vivo)
	Perfil.carregar()
	Engine.physics_ticks_per_second = 60
	ConfigArena.energia_dura = C.ENERGIA_CEU.duracao      # PvP: sempre 9 s (igual nos dois aparelhos)
	get_tree().quit_on_go_back = false
	Campeonato.carregar()
	campeonato = Campeonato.em_partida and Campeonato.ativo and Campeonato.minha_luta() >= 0
	if campeonato:                                    # CAMPEONATO: o lado da sua vaga e o bot no nível da fase
		lado_local = str(Campeonato.vagas[Campeonato.voce].lado)
	if lado_local == "":
		lado_local = Perfil.lado if Perfil.lado != "" else "heroes"
	adversario = Perfil.pvp_adversario
	modo = Perfil.pvp_modo if Perfil.pvp_modo in ["normal", "cerco"] else "normal"
	Perfil.pvp_modo = "normal"
	bot_nivel = Perfil.bot_nivel
	if campeonato:
		modo = "normal"
		bot_nivel = Campeonato.BOT_NIVEL
	if not Perfil.pvp_replay.is_empty():
		_preparar_replay(Perfil.pvp_replay)
		Perfil.pvp_replay = {}
	if Perfil.pvp_sala.is_empty() and not campeonato and adversario == "" and replay.is_empty():
		adversario = P.nome_adversario()              # contra o bot aparece sempre um NOME de jogador (nunca "bot")
	if not campeonato and modo == "normal" and Perfil.pvp_sala.is_empty() and replay.is_empty():
		_iniciar_serie_bot()                          # (o mesmo nome a série toda)
	if replay.is_empty():
		semente = randi()                             # (REPLAY: a semente é a da partida gravada)
	if not Perfil.pvp_sala.is_empty():
		_preparar_online(Perfil.pvp_sala)
		Perfil.pvp_sala = {}
	outro = "monsters" if lado_local == "heroes" else "heroes"
	nivel_herois = nivel_conta
	rng.seed = semente
	for i in C.G.rows:
		herois.append([])
		monstros.append([])
	for i in 64:
		projeteis.append(Projetil.new())
	f_titulo = _fonte(["Fontes/lilita-one-latin-400-normal.woff2"])
	f_texto = _fonte(["Fontes/fredoka-latin-700-normal.woff2"])
	_montar_cena()
	_montar_hud()
	get_viewport().size_changed.connect(_centralizar)
	_centralizar()
	if not replay.is_empty():
		_iniciar_replay()
		return
	escolhendo = true                                 # a partida só começa depois das cartas escolhidas
	selecao.abrir(cartas_todas)

## Celular de tela larga: o jogo fica no meio e o fundo cobre as laterais.
func _centralizar() -> void:
	C.centralizar(self, [ui, camada_painel])
	if fundo.texture:
		var k := C.escala_fundo(self, fundo.texture)
		fundo.scale = Vector2(k, k)

func _exit_tree() -> void:
	get_tree().quit_on_go_back = true
	get_tree().paused = false
	get_viewport().canvas_transform = Transform2D.IDENTITY
	if canal:
		canal.fechar()

func _fonte(opcoes: Array) -> Font:
	for o in opcoes:
		var c: String = "res://assets/" + o
		if ResourceLoader.exists(c):
			return load(c)
	return ThemeDB.fallback_font

## Jogador escolheu as cartas na janela: libera o passo da partida e começa.
func _cartas_escolhidas(escolhidas: Array) -> void:
	cartas_dados.clear()
	for p in escolhidas:
		cartas_dados.append(p)
	escolhendo = false
	comecar()

func comecar() -> void:
	for lista in [herois, monstros]:
		for l in lista:
			for u in l:
				u.queue_free()
			l.clear()
	for pr in projeteis:
		pr.ativo = false
	ondas.clear(); orbes.clear(); voos.clear(); explosoes.clear(); textos.clear(); fendas.clear(); choques.clear(); clarões.clear()
	golpes_castelo.clear(); estilhacos.clear(); marcas.clear()
	recargas = {"heroes": {}, "monsters": {}}
	vidas = {"heroes": P.VIDA_CASTELO, "monsters": P.VIDA_CASTELO}
	energias = {"heroes": float(P.ENERGIA_INICIAL), "monsters": float(P.ENERGIA_INICIAL)}
	if online():
		rng.seed = semente                          # a MESMA sorte nos dois aparelhos
	else:
		energias[outro] += (bot_nivel - 1) * P.BOT.energia_inicial_por_nivel     # o bot começa um pouco mais forte a cada vitória
		_preparar_bot()
	passo_n = 0
	prox_id_orbe = 1
	fila_acoes.clear()
	acumulado = 0.0
	tempo = 0.0
	preparo = P.PREPARO
	mare = 1
	dano_feito = {"heroes": 0.0, "monsters": 0.0}
	gasto = {"heroes": 0.0, "monsters": 0.0}
	fim = false
	vencedor = ""
	abatidas = 0
	mortos_h = 0
	sol_t = 2.0
	bot_t = 4.0
	carta_sel = -1
	espiando = false
	espiar_t = 0.0
	_avisou_invasao = false
	intervalo = 0.0
	cartas_usadas = {}
	_t_partida = 0.0
	Conta.estou(_atividade(), ("contra " + adversario) if online() else "contra o bot %s (nível %d)" % [adversario, bot_nivel])   # (só o painel vê)
	if modo == "cerco":
		rodada = 1
		defensor = str(P.MODO_CERCO.primeiro_defende)
		cerco_res = {}
		_preparar_rodada()
	_aplicar_vista()
	_fechar_painel()
	if modo == "cerco":
		_banner_rodada()
		return
	var contra := " · Contra %s" % (adversario if adversario != "" else "o adversário")
	if online():
		contra = (" · Duelo contra %s" if rede.get("amistoso", false) else " · Você contra %s (online)") % adversario
		if rede.get("amistoso", false) and _texto_aposta(rede.get("aposta_moedas", 0), rede.get("aposta_trofeus", 0)) != "":
			contra += "\nValendo " + _texto_aposta(rede.get("aposta_moedas", 0), rede.get("aposta_trofeus", 0))
		if rede.get("em_serie", false):                  # SÉRIE: troféu só para quem vencer de Heroes E de Monsters
			contra += "\n" + _texto_serie()
	elif serie_bot:
		contra += "\n" + _texto_serie_bot()
	mostrar_banner("PREPARE SUA ARENA\nColoque suas tropas e pegue a energia do céu%s" % contra, 4.5)

# =================================================================== CENA E VISTA
func _montar_cena() -> void:
	fundo = Sprite2D.new()
	fundo.centered = true
	fundo.position = Vector2(C.W / 2, C.H / 2)
	fundo.z_index = -10
	add_child(fundo)
	mundo = Node2D.new()
	add_child(mundo)
	# PORTAL_TROPA: atrás das tropas. O miolo escuro (normal) e a luz (somando cor, brilha)
	fenda_corpo = Node2D.new()
	fenda_corpo.draw.connect(_desenhar_fendas_corpo)
	mundo.add_child(fenda_corpo)
	fenda_luz = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fenda_luz.material = mat
	fenda_luz.draw.connect(_desenhar_fendas_luz)
	mundo.add_child(fenda_luz)
	camada_unidades = Node2D.new()
	camada_unidades.y_sort_enabled = true
	mundo.add_child(camada_unidades)
	_montar_chao_linhas()
	desenho = Node2D.new()
	desenho.z_index = 10
	desenho.draw.connect(_desenhar)
	mundo.add_child(desenho)
	fx_chao = FxExplosao.new()                  # explosões: chão (embaixo de todos) e ar (por cima)
	fx_chao.camada = "chao"
	fx_chao.z_index = -5
	mundo.add_child(fx_chao)
	fx_ar = FxExplosao.new()
	fx_ar.z_index = 9
	fx_ar.par_chao = fx_chao
	mundo.add_child(fx_ar)
	desenho_tela = Node2D.new()
	desenho_tela.z_index = 11
	desenho_tela.draw.connect(_desenhar_tela)
	add_child(desenho_tela)
	RenderingServer.set_default_clear_color(Color("07080d"))   # (se sobrar alguma borda, fica escura, nunca verde)

## Qual arena aparece e se está espelhada. Por dentro: heróis à esquerda, monstros à direita.
func _arena_vista() -> String:
	return outro if espiando else lado_local

func _aplicar_vista() -> void:
	var a := _arena_vista()
	var esp := lado_local == "monsters"               # quem é Monsters vê tudo espelhado
	if a == "heroes":
		mundo.scale = Vector2(-1, 1) if esp else Vector2.ONE
		mundo.position = Vector2(C.W, 0) if esp else Vector2.ZERO
	else:
		mundo.scale = Vector2(-1, 1) if esp else Vector2.ONE
		mundo.position = Vector2(P.MW, 0) if esp else Vector2(-(P.MW - C.W), 0)
	# fundo: o castelo da arena vista fica à esquerda quando ela é a SUA; espiando, fica à direita
	var nomes := ["arena_guerreiro_dia_largo", "arena_guerreiro_dia", "arena_guerreiro_noite_largo", "arena_guerreiro_noite", "fundo_do_jogo"]
	if a == "monsters":
		nomes = ["arena_monsters_dia_largo", "arena_monsters_dia"] + nomes
	if _estacao_pvp == "?":                            # cada partida numa estação (só visual: não usa o rng da partida)
		_estacao_pvp = C.ESTACOES[randi() % C.ESTACOES.size()]
	if _estacao_pvp != "":
		nomes.push_front(nomes[0] + "_" + _estacao_pvp)
	var tex: Texture2D = null
	for n in nomes:
		for ext in ["jpg", "png", "webp"]:
			var c := "res://assets/Fundo/%s.%s" % [n, ext]
			if tex == null and ResourceLoader.exists(c):
				tex = load(c)
	fundo.texture = tex
	fundo.flip_h = espiando
	if tex:
		var k := C.escala_fundo(self, tex)
		fundo.scale = Vector2(k, k)
	if tochas == null:
		tochas = preload("res://scripts/arena/tochas_fundo.gd").new()
		fundo.add_child(tochas)
	tochas.usar(tex, false)                            # fogo vivo nas tochas do fundo
	tochas.scale = Vector2(-1, 1) if espiando else Vector2.ONE

func para_tela(p: Vector2) -> Vector2:
	return mundo.transform * p

func para_mundo(p: Vector2) -> Vector2:
	return mundo.transform.affine_inverse() * p

# =================================================================== HUD
func _montar_hud() -> void:
	var ids: Array = P.CARTAS_HEROES if lado_local == "heroes" else P.CARTAS_MONSTERS
	cartas_todas.clear()
	cartas_dados.clear()
	for id in ids:
		var p: PersonagemDados = Catalogo.get_p(id)
		if p:
			cartas_todas.append(p)
	ui = CanvasLayer.new()
	add_child(ui)
	hud = preload("res://scripts/arena/hud.gd").new()
	hud.arena = self
	ui.add_child(hud)
	menu_unidade = preload("res://scripts/arena/menu_unidade.gd").new()
	menu_unidade.arena = self
	ui.add_child(menu_unidade)
	lbl_banner = Label.new()
	lbl_banner.position = Vector2(80, 210)
	lbl_banner.size = Vector2(C.W - 160, 160)
	lbl_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_banner.add_theme_font_override("font", f_titulo)
	lbl_banner.add_theme_font_size_override("font_size", 34)
	lbl_banner.add_theme_color_override("font_color", Color("fff4d6"))
	lbl_banner.add_theme_color_override("font_outline_color", Color("24130a"))
	lbl_banner.add_theme_constant_override("outline_size", 12)
	lbl_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(lbl_banner)
	lbl_fps = Label.new()
	lbl_fps.position = Vector2(C.W - 70, 8)
	lbl_fps.visible = mostrar_fps
	ui.add_child(lbl_fps)
	# painel de fim de jogo / pausa
	painel = Control.new()
	painel.set_anchors_preset(Control.PRESET_FULL_RECT)
	painel.process_mode = Node.PROCESS_MODE_ALWAYS
	painel.mouse_filter = Control.MOUSE_FILTER_STOP
	painel.draw.connect(_desenhar_painel)
	painel.visible = false
	camada_painel = CanvasLayer.new()
	camada_painel.layer = 5
	add_child(camada_painel)
	camada_painel.add_child(painel)
	# janela de seleção de cartas (fica na camada de cima; abre no _ready e na revanche)
	selecao = preload("res://scripts/arena/selecao_cartas.gd").new()
	selecao.arena = self
	selecao.escolheu = _cartas_escolhidas
	selecao.sair = _ir_menu
	camada_painel.add_child(selecao)

func mostrar_banner(txt: String, t := 3.2) -> void:
	lbl_banner.text = txt
	lbl_banner.visible = txt != ""
	banner_t = t

func texto_fase() -> String:
	if modo == "cerco":
		var papel := "DEFENDA" if defensor == lado_local else "ATAQUE"
		if intervalo > 0.0:
			return "Troca de papéis..."
		if preparo > 0.0:
			return "R%d · %s · prepare %ds" % [rodada, papel, ceili(preparo)]
		return "R%d · %s · %s%s" % [rodada, papel, _mmss(tempo), _txt_mare()]
	if preparo > 0.0:
		return "Preparo %ds" % ceili(preparo)
	return "%s%s" % [_mmss(tempo), _txt_mare()]       # (sem fim: só mostra quanto a batalha já dura)

## " · MARÉ x3" / " · MORTE SÚBITA" no relógio (nada na maré 1).
func _txt_mare() -> String:
	if tempo >= _t_morte_subita():
		return " · MORTE SÚBITA"
	return " · MARÉ x%d" % mare if mare > 1 else ""

func horda_restante() -> float:
	return clampf(vidas[outro] / P.VIDA_CASTELO, 0.0, 1.0)

## ESPIAR = ir junto com as suas tropas: o botão só aparece enquanto você tem tropa VIVA na arena inimiga
## (de graça e sem tempo). Lá, o mesmo botão vira "MINHA ARENA". Se todas as suas tropas de lá morrerem,
## você volta sozinho para a sua arena. Só muda a VISTA (não vai pela rede: não mexe na partida).
func espiar() -> void:
	if fim:
		return
	if espiando:
		_trocar_vista(false)
	elif tropas_na_arena_inimiga() > 0:
		_trocar_vista(true)
	else:
		return
	carta_sel = -1
	if banner_t > 0.0:
		mostrar_banner("")                             # (tira o aviso "toque em ESPIAR" da frente)
	if menu_unidade and menu_unidade.aberto():
		menu_unidade.fechar()
	Sons.tocar("Jogo/som/portal", 0.35)

## Quantas tropas SUAS (ou do lado pedido) estão vivas na arena do adversário (já passaram pelo portal).
func tropas_na_arena_inimiga(lado := "") -> int:
	if lado == "":
		lado = lado_local
	var n := 0
	for l in (herois if lado == "heroes" else monstros):
		for u in l:
			if u.atravessou and not u.morto:
				n += 1
	return n

## (HUD) O botão Espiar aparece? Só com tropa sua viva lá (ou quando você já está lá: vira "voltar").
func pode_espiar() -> bool:
	return not fim and (espiando or tropas_na_arena_inimiga() > 0)

func _trocar_vista(espiar_: bool) -> void:
	espiando = espiar_
	troca_t = 1.0
	_aplicar_vista()

# =================================================================== UNIDADES
func _lado_b(x: float) -> bool:
	return x > P.MW / 2.0

func criar_unidade(id: String, lado: String, linha: int, x: float, nv: int) -> Unidade:
	var p: PersonagemDados = Catalogo.get_p(id)
	if p == null:
		push_warning("PvP: não achei a ficha '%s'" % id)
		return null
	var u := Unidade.new()
	_uid_n += 1
	u.uid = _uid_n                                  # (igual nos dois aparelhos: as tropas nascem na mesma ordem)
	u.pvp = true
	u.fixo = preparo > 0.0
	u.iniciar(self, p, lado, linha, nv)
	u.position = Vector2(x, C.linha_y(linha))
	u.guarda = modo == "cerco" and lado == defensor     # CERCO: quem defende fica firme no lugar
	if lado == "heroes":
		u.anda = p.anims.has("andar") and p.comportamento != "gerador" and not u.guarda
		var cfg: Dictionary = P.andar(id)
		cfg.merge(p.extra.get("andar", {}), true)
		u.vel_andar = float(cfg.velocidade) * rng.randf_range(0.94, 1.06)
		u.para = float(cfg.para)
		u.pausa_parar = float(cfg.get("pausa", 0.35))
		herois[linha].append(u)
	else:
		monstros[linha].append(u)
		Sons.do_personagem(p, "aparecer")
	camada_unidades.add_child(u)
	u.reset_physics_interpolation()                 # nasce no lugar (não desliza de (0,0) até aqui)
	return u

## Por que não dá para colocar ("" = dá). reserva = energia já prometida em ações que ainda vão acontecer (online).
func _motivo_nao_pode(lado: String, p: PersonagemDados, linha: int, col: int, livre: bool, reserva := 0.0, inv := false) -> String:
	var x := _x_casa(lado, col, inv)
	if inv:                                             # INVASÃO: só com tropa sua viva lá, e só na metade do portal
		if tropas_na_arena_inimiga(lado) == 0:
			return "sem tropa sua aqui"
		if col < COL_MIN_INVASAO:
			return "perto demais do castelo"
		if col > COL_MAX_INVASAO:
			return "em cima do portal"
	var lista: Array = herois[linha] if lado == "heroes" else monstros[linha]
	for u in lista:
		if not u.morto and absf(u.position.x - x) < C.G.cw * 0.5:
			return "ocupado"
	if recargas[lado].get(p.id, 0.0) > 0.0:
		return "recarregando"
	if not livre and energias[lado] - reserva < p.custo:
		return "falta energia"
	return ""

## Nível da conta da tropa: online, cada lado usa o nível da PRÓPRIA conta (vem do servidor);
## contra o bot, você usa o seu e o bot usa nível 1.
## Nível que aparece na carta (o seu).
func nivel_da_carta(id: String) -> int:
	return _nivel_tropa(lado_local, id, true)

func _nivel_tropa(lado: String, id: String, local: bool) -> int:
	if online():
		var nv: Dictionary = rede.niveis.get(lado, {})
		return clampi(int(nv.get(id, 1)), 1, Progressao.NIVEL_MAX)
	return clampi(maxi(nivel_conta, Perfil.nivel_de(id)), 1, Progressao.NIVEL_MAX) if local else bot_nivel_tropa

## INVASÃO: na arena inimiga, dá para colocar da coluna COL_MIN_INVASAO (contando do castelo de lá) até o portal.
const COL_MIN_INVASAO := 4
## A última coluna (a 9ª, x 1160) é a BOCA DO PORTAL (x 1175): ali não dá (ficaria dentro do portal, por cima de quem chega).
const COL_MAX_INVASAO := 7

## X (no mundo) da casa col. Normal: na arena de quem coloca (col conta do castelo dele).
## inv = INVASÃO: na arena do OUTRO (col conta do castelo de lá) — a tropa sai de um portal ali mesmo.
func _x_casa(lado: String, col: int, inv := false) -> float:
	var na_dos_herois := (lado == "heroes") != inv
	return C.cel_x(col) if na_dos_herois else P.MW - C.cel_x(col)

## Casa na tela -> casa da arena que está aparecendo. Espiando, a arena inimiga aparece espelhada (castelo à direita).
func _casa_tela(pos: Vector2) -> Vector2i:
	return C.casa_em(Vector2(C.W - pos.x, pos.y)) if espiando else C.casa_em(pos)

## Onde fica na TELA o centro (pés) da casa col/linha da arena que está aparecendo.
func _pes_casa_tela(col: int, linha: int) -> Vector2:
	var x := C.cel_x(col)
	return Vector2(C.W - x if espiando else x, C.linha_y(linha))

## Coloca uma tropa (do jogador, do bot ou, no online, do adversário). col conta a partir do castelo de quem coloca.
## inv = INVASÃO (com tropa sua viva na arena inimiga): a tropa aparece lá, saindo de um portal.
func colocar(lado: String, id: String, linha: int, col: int, local: bool, inv := false) -> bool:
	if fim or intervalo > 0.0:
		return false
	var p: PersonagemDados = Catalogo.get_p(id)
	if p == null or linha < 0 or linha >= C.G.rows or col < 0 or col >= C.G.cols:
		return false
	if inv and preparo > 0.0:
		return false
	var livre := energia_infinita and local and not online()
	var motivo := _motivo_nao_pode(lado, p, linha, col, livre, 0.0, inv)
	if motivo != "":
		if local:
			_texto_tela(_pes_casa_tela(col, linha) - Vector2(0, 60), motivo, Color("cccccc") if motivo == "recarregando" else Color("ff8080"))
		return false
	if not livre:
		energias[lado] -= p.custo
	gasto[lado] += p.custo
	recargas[lado][id] = p.recarga
	var x := _x_casa(lado, col, inv)
	var u := criar_unidade(id, lado, linha, x, _nivel_tropa(lado, id, local))
	if lado == lado_local:
		cartas_usadas[id] = int(cartas_usadas.get(id, 0)) + 1
	if inv and u:                                       # já está do outro lado: não passa mais por portal
		u.atravessou = true
		u.x_saida = x - dir_de(lado) * PORTAL.some      # (aparece inteira: o portal de saída abre atrás dela)
		_abrir_fenda(x, u, true)
		for k in 10:                                    # faíscas do portal (enfeite: randf, nunca o rng da partida)
			faiscas.append({"pos": Vector2(x, C.linha_y(linha) - randf_range(20, 100)), "vel": Vector2(randf_range(-70, 70), randf_range(-80, 30)), "t": 0.0})
	explosoes.append([Vector2(x, C.linha_y(linha) - 10), 34.0, 0.0, Color("ffe08a") if lado == "heroes" else Color("9be05a")])
	return true

# =================================================================== COMANDOS DO JOGADOR (menu do personagem)
## No PvP as tropas andam sozinhas como sempre; o menu é uma OPÇÃO a mais (parar, andar, voltar, poderes, remover).
## Online: vira uma ação marcada para um passo lá na frente (os dois aparelhos aplicam juntos).
func comando(u: Unidade, tipo: String) -> void:
	if u == null or not is_instance_valid(u) or u.morto or fim:
		return
	if online():
		agendar({"tipo": "cmd", "uid": u.uid, "c": tipo})
		return
	_comando_sim(u, tipo)

func _comando_sim(u: Unidade, tipo: String) -> void:
	if u.morto:
		return
	match tipo:
		"azul":
			u.toque_azul()
		"vermelho":
			u.forcar2 = true
		"remover":
			u.morto = true
			u.livre = true
			u.ocupa_casa = false
			explosoes.append([u.position + Vector2(0, -40), 40.0, 0.0, Color("dfe4ff")])
		"parar":
			u.ordem = "parar"
		"andar":
			u.ordem = ""                                 # volta a marchar normalmente
			u._virar(false)
		"voltar":
			u.ordem = "voltar"

func _por_uid(id: int) -> Unidade:
	for lista in [herois, monstros]:
		for l in lista:
			for x in l:
				if x.uid == id and not x.morto:
					return x
	return null

## VOLTAR: até onde a tropa recua (o começo da arena em que ela está, do lado dela).
func limite_recuo(u: Unidade) -> float:
	if u.lado == "heroes":
		return C.cel_x(1) if not _lado_b(u.position.x) else P.PORTAO_B + 60.0
	return P.MW - C.cel_x(1) if _lado_b(u.position.x) else P.PORTAO_X - 60.0

## Tropa SUA mais perto do toque (pos na tela) — para abrir o menu dela.
func unidade_do_jogador_em(pos: Vector2) -> Unidade:
	var melhor: Unidade = null
	var melhor_d := 70.0
	var lista: Array = herois if lado_local == "heroes" else monstros
	for l in lista:
		for x in l:
			if x.morto or x.lado != lado_local:
				continue
			var tp := para_tela(x.position)
			var centro := tp + Vector2(0, -40.0)
			var d := pos.distance_to(centro)
			if absf(pos.x - tp.x) < 55.0 and pos.y < tp.y + 18.0 and pos.y > tp.y - 150.0:
				d = minf(d, absf(pos.x - tp.x))
			if d < melhor_d:
				melhor = x; melhor_d = d
	return melhor

## casa = casa da arena que está aparecendo (espiando = INVASÃO na arena inimiga; col conta do castelo de lá).
func colocar_local(casa: Vector2i) -> void:
	if carta_sel < 0 or carta_sel >= cartas_dados.size() or intervalo > 0.0:
		return
	var inv := espiando
	var p := cartas_dados[carta_sel]
	var onde := _pes_casa_tela(casa.x, casa.y) - Vector2(0, 60)
	if online():                                       # ONLINE: confere agora e manda; ela aparece daqui a 0,5 s
		for a in fila_acoes:
			if a.lado == lado_local and a.tipo == "colocar" and int(a.r) == casa.y and int(a.c) == casa.x and bool(a.get("inv", false)) == inv:
				return
			if a.lado == lado_local and a.tipo == "colocar" and a.id == p.id:
				_texto_tela(onde, "recarregando", Color("cccccc"))
				return
		var motivo := _motivo_nao_pode(lado_local, p, casa.y, casa.x, false, _energia_reservada(), inv)
		if motivo != "":
			_texto_tela(onde, motivo, Color("cccccc") if motivo == "recarregando" else Color("ff8080"))
			return
		var ac := {"tipo": "colocar", "id": p.id, "r": casa.y, "c": casa.x}
		if inv:
			ac.inv = true
		agendar(ac)
		carta_sel = -1
		if C.ESCONDER_CARTAS_AO_COLOCAR:
			hud.guardado = true
		return
	if colocar(lado_local, p.id, casa.y, casa.x, true, inv):
		carta_sel = -1
		if C.ESCONDER_CARTAS_AO_COLOCAR:
			hud.guardado = true

# --- perguntas que os personagens fazem (sempre só na própria linha e na mesma arena) ---
## +1 = o inimigo está à direita (sempre assim no PvP: heróis atacam o castelo da direita).
## Só existe para a Unidade achar o seu lado (o flip das folhas e o andar da campanha).
func dir_de(lado: String) -> float:
	return 1.0 if lado == "heroes" else -1.0

func alvo_na_frente(u: Unidade, alcance: float) -> Unidade:
	var melhor: Unidade = null
	var melhor_d := INF
	var b := _lado_b(u.position.x)
	var s := u._dir()                                    # (virado = mira para trás)
	if u.lado == "heroes":
		for m in monstros[u.linha]:
			if m.morto or _lado_b(m.position.x) != b:
				continue
			var d: float = (m.position.x - u.position.x) * s
			if d >= -10.0 and d <= alcance and d < melhor_d:
				melhor = m; melhor_d = d
	else:
		for h in herois[u.linha]:
			if not h.ocupa_casa or _lado_b(h.position.x) != b:
				continue
			var d: float = (h.position.x - u.position.x) * s
			if d >= -10.0 and d <= alcance and d < melhor_d:
				melhor = h; melhor_d = d
	return melhor

func todos_na_frente(u: Unidade, alcance: float) -> Array:
	var r := []
	var b := _lado_b(u.position.x)
	var lista: Array = monstros[u.linha] if u.lado == "heroes" else herois[u.linha]
	for o in lista:
		if o.morto or _lado_b(o.position.x) != b:
			continue
		var d: float = (o.position.x - u.position.x) * u._dir()
		if d >= -10.0 and d <= alcance:
			r.append(o)
	return r

## (Darian) Onda inimiga vindo na linha dele, na mesma arena (ou Golem inimigo preparando o fogo): distância; INF = nada.
func ameaca_no_chao(u: Unidade) -> float:
	var melhor := INF
	var b := _lado_b(u.position.x)
	for o in ondas:
		if o.linha != u.linha or o.lado == u.lado or _lado_b(o.x) != b:
			continue
		var d: float = (u.position.x - o.x) * signf(o.vel)
		if d > -10.0 and d < 900.0:
			melhor = minf(melhor, d)
	var lista: Array = monstros[u.linha] if u.lado == "heroes" else herois[u.linha]
	for m in lista:
		if not m.morto and _lado_b(m.position.x) == b and m.p.comportamento == "golem" and m.estado == "especial" \
				and absf(m.position.x - u.position.x) < 900.0:
			melhor = minf(melhor, absf(m.position.x - u.position.x))     # já se prepara enquanto o Golem carrega o fogo
	return melhor

## (Darian) Até onde o arremessado pode voar: dentro da arena onde está (sem atravessar o portal nem o castelo).
func limites_arremesso(u: Unidade) -> Vector2:
	if _lado_b(u.position.x):
		return Vector2(P.PORTAO_B + 30.0, P.CASTELO_MONSTERS_X - 30.0)
	return Vector2(P.CASTELO_HEROES_X + 30.0, P.PORTAO_X - 30.0)

## Até onde vai a linha (na arena onde ele está) para o lado "sentido": a borda daquela arena.
func ponta_da_linha(u: Unidade, sentido: float) -> float:
	var b := _lado_b(u.position.x)
	if sentido > 0.0:
		return (P.MW + 60.0) if b else (C.W + 60.0)
	return (P.MW - C.W - 60.0) if b else -60.0

## Todos os inimigos da linha (mesma arena) de "tras" px atrás até "frente" px na frente (raio do Golem).
func todos_na_linha(u: Unidade, frente: float, tras: float) -> Array:
	var r := []
	var b := _lado_b(u.position.x)
	var lista: Array = monstros[u.linha] if u.lado == "heroes" else herois[u.linha]
	for o in lista:
		if o.morto or _lado_b(o.position.x) != b or (u.lado == "monsters" and not o.ocupa_casa):
			continue
		var d: float = (o.position.x - u.position.x) * u._dir()
		if d >= -tras and d <= frente:
			r.append(o)
	return r

func tem_inimigo_na_linha(u: Unidade) -> bool:
	if no_cerco(u) and not u.virado:
		return true                                   # CERCO: o castelo inimigo também é alvo (só na FRENTE dele)
	var b := _lado_b(u.position.x)
	var lista: Array = monstros[u.linha] if u.lado == "heroes" else herois[u.linha]
	for o in lista:
		if o.morto or _lado_b(o.position.x) != b:
			continue
		if (o.position.x - u.position.x) * u._dir() > -10.0:
			return true
	return false

## Como tem_inimigo_na_linha, mas o inimigo já precisa ter APARECIDO (dentro da arena e fora do portal).
## Faz parte da partida: só usa estado do passo fixo (igual nos dois aparelhos).
func inimigo_visivel_na_linha(u: Unidade) -> bool:
	if no_cerco(u):
		return true
	var b := _lado_b(u.position.x)
	var s := u._dir()
	var borda_dir := P.MW if b else C.W
	var borda_esq := P.MW - C.W if b else 0.0
	var lista: Array = monstros[u.linha] if u.lado == "heroes" else herois[u.linha]
	for o in lista:
		if o.morto or _lado_b(o.position.x) != b:
			continue
		if (o.position.x - u.position.x) * s <= -10.0:
			continue
		if o.position.x > borda_dir - MARGEM_VISIVEL or o.position.x < borda_esq + MARGEM_VISIVEL:
			continue
		if _alfa_fenda(o) < 0.6:
			continue                                     # ainda saindo do portal
		return true
	return false

func contar_inimigos_na_linha(u: Unidade) -> int:
	var n := 0
	var b := _lado_b(u.position.x)
	var lista: Array = monstros[u.linha] if u.lado == "heroes" else herois[u.linha]
	for o in lista:
		if not o.morto and _lado_b(o.position.x) == b and (o.position.x - u.position.x) * u._dir() > 0.0:
			n += 1
	return n

## CERCO: até onde a tropa pode andar (2º quadrado antes do castelo inimigo) se não tiver ninguém na frente.
func limite_x(u: Unidade) -> float:
	var heroi := u.lado == "heroes"
	var id := u.p.id
	if u.chefe or not (id in P.DE_LONGE or id in P.PODER_NO_CASTELO):
		return INF if heroi else -INF
	if heroi:
		if not _lado_b(u.position.x):
			return INF
		for m in monstros[u.linha]:
			if not m.morto and _lado_b(m.position.x) and m.position.x - u.position.x > -5.0:
				return INF                               # alguém entre ele e o castelo: vai até lá lutar
		return maxf(P.x_cerco_herois(), u.position.x)
	if _lado_b(u.position.x):
		return -INF
	for h in herois[u.linha]:
		if h.ocupa_casa and not _lado_b(h.position.x) and u.position.x - h.position.x > -5.0:
			return -INF
	return minf(P.x_cerco_monstros(), u.position.x)

func no_cerco(u: Unidade) -> bool:
	var l := limite_x(u)
	return is_finite(l) and absf(u.position.x - l) < 1.5

func ferir(alvo: Unidade, valor: float, origem: Unidade = null, origem_id := "", cor_texto := Color(0, 0, 0, 0)) -> void:
	if alvo == null or alvo.morto:
		return
	var atq := origem.p.id if origem != null else origem_id
	if atq == "arqueiro" and alvo.p.id == "esqueleto":
		valor *= 1.3                          # o Arqueiro é forte contra o esqueleto normal
	elif atq == "esqueleto" and alvo.p.id == "arqueiro":
		valor *= 0.3                          # o esqueleto quase não fere o Arqueiro
	if alvo.p.id == "engenheiro":
		valor *= ENGENHEIRO_RECEBE            # armadura do Engenheiro: recebe só 40% do dano
	var antes := alvo.vida
	var morreu := alvo.receber(valor)
	var tirou := antes - maxf(alvo.vida, 0.0)
	if tirou >= 1.0:
		var cor_t := cor_texto if cor_texto.a > 0.0 else (Color("ffd36b") if alvo.lado == "monsters" else Color("ff6b6b"))
		_texto(alvo.position + Vector2(rng.randf_range(-12, 12), -alvo.anim.ay * alvo.scale.y - 6), "-%d" % roundi(tirou), cor_t)
	if morreu:
		if alvo.lado == "monsters":
			abatidas += 1
			if alvo.p.comportamento in ["necro", "mistico"]:   # o Mago / Místico morre: os invocados somem
				for l in monstros:
					for m in l:
						if m.invocador == alvo and not m.morto:
							m.morrer()
		else:
			mortos_h += 1

func ferir_castelo(lado: String, dano: float, pos: Vector2) -> void:
	if fim:
		return
	dano *= _mult_castelo()                               # MARÉ alta: o castelo leva mais dano
	vidas[lado] = maxf(0.0, vidas[lado] - dano)
	dano_feito["monsters" if lado == "heroes" else "heroes"] += dano
	explosoes.append([pos, 60.0, 0.0, Color("ff6b5e") if lado == lado_local else Color("ffd34d")])
	_texto(pos + Vector2(0, -60), "-%d" % roundi(dano), Color("ff6b5e") if lado == lado_local else Color("ffd34d"))
	if lado == _arena_vista():
		Sons.tocar("Castelo/som/dano", 0.8)

## Ponto da PAREDE do castelo (no mundo) que o raio do cerco acerta, na altura do cano (dentro da parede).
## Bomba do Bombardeiro acertou a PAREDE do castelo (PARTIDA: o dano; o resto é enfeite com randf global):
## pedras arrancadas, brasas e a marca queimada com rachaduras em brasa. A explosão de fogo já sai da bomba voando.
func bomba_no_castelo(u: Unidade, ponto: Vector2, lado_castelo: String) -> void:
	ferir_castelo(lado_castelo, float(u.dano) * BOMBA_CASTELO_PCT, ponto)
	var dir := 1.0 if lado_castelo == "monsters" else -1.0      # para onde a bomba ia: as pedras voltam
	marcas.append({"pos": ponto + Vector2(randf_range(-5, 5), randf_range(-5, 5)), "t": 0.0, "semente": randi(), "fogo": true})
	if marcas.size() > 12:
		marcas.pop_front()
	for k in 18:
		var ang := randf_range(-1.3, 1.3) + (PI if dir > 0.0 else 0.0)
		var vel := Vector2(cos(ang), sin(ang)) * randf_range(140.0, 420.0) + Vector2(0, -randf_range(80.0, 240.0))
		var cinza := randf_range(0.28, 0.55)
		estilhacos.append({"pos": ponto + Vector2(randf_range(-12, 12), randf_range(-12, 12)), "vel": vel, "t": 0.0,
			"giro": randf_range(-12.0, 12.0), "ang": randf() * TAU, "tam": randf_range(3.0, 7.5),
			"cor": Color(cinza, cinza * 0.95, cinza * 0.9), "chao": ponto.y + randf_range(60.0, 150.0), "fogo": true})

func _ponto_castelo(lado: String, y_cano: float) -> Vector2:
	var y := clampf(y_cano + 12.0, CASTELO_Y[0], CASTELO_Y[1])
	return Vector2(CASTELO_PAREDE_X, y) if lado == "heroes" else Vector2(P.MW - CASTELO_PAREDE_X, y)

## Castelo de cada lado no mundo (para os efeitos).
func _pos_castelo(lado: String, y: float) -> Vector2:
	return Vector2(C.G.left - 30.0, y - 40.0) if lado == "heroes" else Vector2(P.MW - C.G.left + 30.0, y - 40.0)

func soltar_energia(pos: Vector2, valor: int) -> void:     # (a campanha usa; aqui vem pelo soltar_energia_lado)
	soltar_energia_lado(pos, valor, "heroes")

## fonte = quem gerou (Elara / Esqueleto Black). Gerada na arena INIMIGA, a energia só existe enquanto
## quem gerou estiver vivo lá (você pega espiando; morreu = a energia dele some).
func soltar_energia_lado(pos: Vector2, valor: int, lado: String, fonte: Unidade = null) -> void:
	var o := {"id": prox_id_orbe, "pos": pos, "alvo_y": pos.y, "valor": valor, "t": 0.0, "lado": lado}
	if fonte and _lado_b(pos.x) != (lado == "monsters"):
		o.fonte = fonte
	orbes.append(o)
	prox_id_orbe += 1

## Chama "quantos" monstros (linha do invocador e as vizinhas) saindo de um portal no chão. Devolve os criados.
func invocar(u: Unidade, id: String, quantos: int, vida_mult := 1.0) -> Array:
	var criados: Array = []
	var linhas := [u.linha, u.linha - 1, u.linha + 1]
	var tema := "fogo" if id == "esqueletoFogo" else "sombra"
	var n := 0
	for r in linhas:
		if n >= quantos:
			break
		if r < 0 or r >= C.G.rows:
			continue
		n += 1
		var m := criar_unidade(id, "monsters", r, u.position.x - C.G.cw, u.nivel)
		if m:
			m.invocador = u
			m.fixo = false
			if vida_mult != 1.0:
				m.vida_max = maxi(1, roundi(m.vida_max * vida_mult))
				m.vida = m.vida_max
			m.nascer(1.1)
			if fx_chao:
				fx_chao.invocacao(m.position, tema)
			if fx_ar:
				fx_ar.invocacao(m.position, tema)
			criados.append(m)
	return criados

## (Aura) Todos os inimigos INVOCADOS vivos na mesma arena que ela (qualquer linha).
func invocados_inimigos(u: Unidade) -> Array:
	var r := []
	var b := _lado_b(u.position.x)
	var listas: Array = monstros if u.lado == "heroes" else herois
	for l in listas:
		for o in l:
			if not o.morto and o.invocador != null and _lado_b(o.position.x) == b:
				r.append(o)
	return r

## Aliados na linha (mesma arena), na frente de u, até "alcance" px (a cura do Místico).
func aliados_na_frente(u: Unidade, alcance: float) -> Array:
	var r := []
	var b := _lado_b(u.position.x)
	var lista: Array = herois[u.linha] if u.lado == "heroes" else monstros[u.linha]
	for o in lista:
		if o == u or o.morto or _lado_b(o.position.x) != b:
			continue
		var d: float = (o.position.x - u.position.x) * u._dir()
		if d >= -10.0 and d <= alcance:
			r.append(o)
	return r

func disparar(tipo: String, u: Unidade, saida: Vector2, vel: float, dano_: int, dano_area := 0, raio := 0.0, alvo: Unidade = null) -> void:
	for pr in projeteis:
		if not pr.ativo:
			pr.ativo = true
			pr.tipo = tipo
			pr.lado = u.lado
			pr.linha = u.linha
			pr.pos = u.position + Vector2(saida.x * (-1.0 if u.virado else 1.0), saida.y)
			pr.vel = vel * (1.0 if u.lado == "heroes" else -1.0) * (-1.0 if u.virado else 1.0)   # (virado = atira para trás)
			pr.dano = dano_
			pr.dano_area = dano_area
			pr.raio = raio
			pr.origem_id = u.p.id
			pr.fogo = u.flechas_fogo > 0 and tipo.begins_with("flecha")
			if pr.fogo:
				u.flechas_fogo -= 1
			pr.t = 0.0
			pr.fixado = false
			pr.t_fixado = 0.0
			pr.castelo = ""
			# laser do Engenheiro: sai reta do cano e curva até a cabeça do alvo da frente
			pr.origem = pr.pos
			pr.alvo_ref = alvo if tipo == "energia" else null
			if pr.alvo_ref != null:
				pr.mira_y = alvo.posicao_cabeca().y
				pr.x_fim = alvo.position.x
			else:
				pr.mira_y = pr.pos.y
				pr.x_fim = pr.pos.x + 800.0 * signf(pr.vel)
			if tipo == "energia":
				var s := signf(pr.vel)
				pr.pos.x -= RAIO_RECUO * s                # nasce na boca do canhão (não solto no ar)
				pr.origem = pr.pos
				pr.vel = RAIO_VEL * s
				pr.semente = randi()                      # enfeite (rng global, não o da partida)
				if alvo == null and no_cerco(u):          # CERCO: sem tropa na frente, o raio vai na parede do castelo
					pr.castelo = "monsters" if u.lado == "heroes" else "heroes"
					var alvo_c := _ponto_castelo(pr.castelo, pr.origem.y)
					pr.x_fim = alvo_c.x
					pr.mira_y = alvo_c.y
				clarões.append({"pos": pr.pos, "t": 0.0, "dir": s})
				for k in 5:                               # faíscas que espirram do cano
					faiscas.append({"pos": pr.pos, "t": randf_range(0.0, 0.1),
						"vel": Vector2(s * randf_range(40.0, 160.0), randf_range(-140.0, 40.0)), "raio": true})
			return

## Bomba do Esqueleto Bombardeiro: explode no chão onde caiu (PARTIDA: dano decidido só pelas posições;
## o efeito usa o randf() global, nunca o rng da partida). Mais perto = dano cheio; resto no raio = área.
## A bomba que se VÊ voando até o chão (por cima de todos); ao cair ela explode na tela. O dano é o explodir_bomba.
func lancar_bomba(tex: Texture2D, de: Vector2, para: Vector2, dur: float, esc: float, flip: bool, fogo: Vector2, chao := Vector2.INF) -> void:
	fx_ar.voar_bomba(tex, de, para, dur, esc, flip, fogo, chao)

func explodir_bomba(u: Unidade, ponto: Vector2, dano_: int, dano_area: int, raio: float) -> void:
	var b := _lado_b(u.position.x)
	var lista: Array = herois[u.linha] if u.lado == "monsters" else monstros[u.linha]
	var perto: Array = []
	for o in lista:
		if o.morto or _lado_b(o.position.x) != b or (u.lado == "monsters" and not o.ocupa_casa):
			continue
		if absf(o.position.x - ponto.x) <= raio:
			perto.append(o)
	perto.sort_custom(func(a, c): return absf(a.position.x - ponto.x) < absf(c.position.x - ponto.x) or \
		(absf(a.position.x - ponto.x) == absf(c.position.x - ponto.x) and a.get_instance_id() < c.get_instance_id()))
	for i in perto.size():
		var o: Unidade = perto[i]
		ferir(o, dano_ if i == 0 else dano_area, u)
		o.levar_impacto(signf(o.position.x - ponto.x) if o.position.x != ponto.x else dir_de(u.lado), 1.0 if i == 0 else 0.6)

func onda(tipo: String, u: Unidade, dano_: int, vel: float) -> void:
	var o := Onda.new()
	o.tipo = tipo
	o.lado = u.lado
	o.linha = u.linha
	o.x = u.position.x
	o.vel = vel * u._dir()
	o.dano = dano_
	o.x0 = o.x
	ondas.append(o)

func _texto(pos: Vector2, txt: String, cor: Color) -> void:
	if textos.size() < 40:
		textos.append({"pos": pos, "txt": txt, "cor": cor, "t": 0.0, "tela": false})

func _texto_tela(pos: Vector2, txt: String, cor: Color) -> void:
	textos.append({"pos": pos, "txt": txt, "cor": cor, "t": 0.0, "tela": true})

# =================================================================== PASSO FIXO (60 por segundo)
func _physics_process(dt: float) -> void:
	if fim or online() or escolhendo:                 # (o online anda pelo _process, no ritmo dos dois aparelhos)
		return
	_passo_sim(dt)

## UM passo da partida (sempre igual em qualquer aparelho com a mesma semente e as mesmas ações).
func _passo_sim(dt: float) -> void:
	_t_partida += dt
	_aplicar_acoes_do_passo()
	_passo_partida(dt)
	for lado in recargas:
		var rec: Dictionary = recargas[lado]
		for k in rec.keys():
			rec[k] = maxf(0.0, rec[k] - dt * _mare_val("recarga"))   # MARÉ alta: as cartas voltam mais rápido
	_passo_unidades(dt)
	_passo_bonus_nick()
	_passo_projeteis(dt)
	_passo_choques(dt)
	_passo_ondas(dt)
	_passo_orbes(dt)
	passo_n += 1

## Energia do céu nas DUAS arenas (cada um pega a sua). Na MARÉ alta cai mais vezes e cada gota vale mais.
func _passo_sol(dt: float) -> void:
	sol_t -= dt * _mare_val("sol_ritmo")
	if sol_t <= 0.0:
		sol_t = rng.randf_range(P.SOL.cada_min, P.SOL.cada_max)
		var xa := rng.randf_range(C.G.left + 40, C.G.left + C.G.cw * C.G.cols - 40)
		var xb := P.MW - rng.randf_range(C.G.left + 40, C.G.left + C.G.cw * C.G.cols - 40)
		for par in [[xa, "heroes"], [xb, "monsters"]]:
			orbes.append({"id": prox_id_orbe, "pos": Vector2(par[0], -30), "x0": par[0], "alvo_y": rng.randf_range(C.G.top + 40, C.G.top + C.G.ch * C.G.rows - 20),
				"valor": P.SOL.valor + int(_mare_val("sol_extra")), "t": 0.0, "lado": par[1]})
			prox_id_orbe += 1

## Nick: +30% de vida enquanto houver esqueleto normal inimigo de pé (PvP).
func _passo_bonus_nick() -> void:
	var tem := false
	for r in C.G.rows:
		for m in monstros[r]:
			if not m.morto and m.p.id == "esqueleto":
				tem = true
				break
		if tem:
			break
	for r in C.G.rows:
		for h in herois[r]:
			if h.p.id == "nick":
				h.bonus_vida_esqueleto(tem)

func _passo_partida(dt: float) -> void:
	if modo == "cerco":
		_passo_cerco(dt)
		return
	_passo_sol(dt)                                      # energia do céu nas DUAS arenas
	# BOT (só quando não é online)
	if not online():
		var forca := _forca_bot()
		if preparo <= 0.0 and bot_nivel > 1:
			energias[outro] += dt * P.BOT.energia_por_segundo_por_nivel * (bot_nivel - 1)
		bot_t -= dt
		if bot_t <= 0.0:
			bot_t = rng.randf_range(lerpf(P.BOT.pensa_facil[0], P.BOT.pensa_dificil[0], forca), lerpf(P.BOT.pensa_facil[1], P.BOT.pensa_dificil[1], forca))
			_jogada_do_bot()
			if bot_horda > 0:
				bot_t = 0.3                             # HORDA: as tropas saem uma atrás da outra
	if preparo > 0.0:                                   # PREPARO: o relógio da batalha ainda não anda
		preparo -= dt
		if preparo <= 0.0:
			for lista in [herois, monstros]:
				for l in lista:
					for u in l:
						u.fixo = false
			mostrar_banner("LUTEM!\nSó vence quem derrubar o castelo inimigo!", 2.4)
			Sons.tocar("Jogo/som/lutem", 0.9)
		return
	tempo += dt
	_passo_mare(dt)
	if vidas.heroes <= 0.0 or vidas.monsters <= 0.0:    # SÓ VENCE QUEM DERRUBA O CASTELO (e nunca empata)
		if vidas.heroes <= 0.0 and vidas.monsters <= 0.0:
			_encerrar(_desempate())                        # (os dois caíram no mesmo passo: coisa rara)
		else:
			_encerrar("monsters" if vidas.heroes <= 0.0 else "heroes")

## MARÉ DE GUERRA (sem relógio de fim): a cada P.MARE.a_cada segundos a batalha esquenta (mais energia, cartas
## mais rápidas, castelo mais frágil = mais personagens na arena). Na MORTE SÚBITA o castelo mais fraco
## desmorona sozinho — sempre termina com um castelo no chão. (Passo fixo: igual nos dois aparelhos.)
func _passo_mare(dt: float) -> void:
	var nova := mini(int(P.MARE.max), 1 + int(floorf(tempo / float(P.MARE.a_cada))))
	if nova > mare:
		mare = nova
		var txt := "Mais energia do céu e cartas mais rápidas!\nEncha a arena!"
		if _mult_castelo() > 1.0:
			txt = "Os castelos levam x%s de dano!\nMande TUDO para cima do castelo!" % String.num(_mult_castelo(), 1).trim_suffix(".0")
		mostrar_banner("⚔ MARÉ DE GUERRA x%d ⚔\n%s" % [mare, txt], 2.8)
		Sons.tocar("Jogo/som/lutem", 0.8)
	var ms := _t_morte_subita()
	if tempo < ms:
		return
	if tempo - dt < ms:
		mostrar_banner("☠ MORTE SÚBITA ☠\nO castelo mais fraco está DESMORONANDO!", 3.0)
		Sons.tocar("Jogo/som/lutem", 1.0)
	var lados: Array = [defensor]
	if modo != "cerco":
		var dif: float = vidas.heroes - vidas.monsters
		lados = ["heroes", "monsters"] if absf(dif) < 0.01 else (["monsters"] if dif > 0.0 else ["heroes"])
	for l in lados:
		vidas[l] = maxf(0.0, vidas[l] - float(P.MARE.desmorona) * dt)

func _t_morte_subita() -> float:
	return float(P.MODO_CERCO.morte_subita) if modo == "cerco" else float(P.MARE.morte_subita)

## Valor da tabela P.MARE[chave] na maré de agora.
func _mare_val(chave: String) -> float:
	var tab: Array = P.MARE[chave]
	return float(tab[clampi(mare - 1, 0, tab.size() - 1)])

## Quanto o dano nos castelos multiplica agora (1 = normal; sobe nas marés altas).
func _mult_castelo() -> float:
	return _mare_val("dano_castelo")

## SEM EMPATE: os dois castelos caíram no mesmo passo. Vence (nesta ordem) quem deu mais dano no castelo
## do outro, quem tem mais tropas vivas; no impossível, os Heroes. (Tudo vem da partida: o mesmo nos dois aparelhos.)
func _desempate() -> String:
	if absf(float(dano_feito.heroes) - float(dano_feito.monsters)) > 0.001:
		return "heroes" if float(dano_feito.heroes) > float(dano_feito.monsters) else "monsters"
	var vivos := {"heroes": 0, "monsters": 0}
	for par in [[herois, "heroes"], [monstros, "monsters"]]:
		for l in par[0]:
			for u in l:
				if not u.morto:
					vivos[par[1]] += 1
	if vivos.heroes != vivos.monsters:
		return "heroes" if vivos.heroes > vivos.monsters else "monsters"
	return "heroes"

func _passo_unidades(dt: float) -> void:
	for r in C.G.rows:
		for lista_lado in [herois, monstros]:
			var l: Array = lista_lado[r]
			var i := l.size() - 1
			while i >= 0:
				var u: Unidade = l[i]
				u.passo(dt)
				if not u.morto:
					_portal_e_castelo(u)
				if u.livre:
					l[i] = l[l.size() - 1]; l.pop_back()     # tira sem empurrar a lista inteira
					u.queue_free()
				i -= 1

## PORTAL: chegou na ponta da arena, sai na arena do outro. CASTELO: quem luta de perto entra e dá dano.
func _portal_e_castelo(u: Unidade) -> void:
	var x := u.position.x
	if not u.atravessou and not u.fenda_aberta and not u.fixo:   # PORTAL_TROPA: chegando na ponta (andando), o portal abre na frente
		var d: float = (P.PORTAO_X - x) if u.lado == "heroes" else (x - P.PORTAO_B)
		if d > 0.0 and d < PORTAL.aviso and _lado_b(x) == (u.lado == "monsters"):
			u.fenda_aberta = true
			_abrir_fenda(P.PORTAO_X if u.lado == "heroes" else P.PORTAO_B, u, false)
	if u.lado == "heroes":
		if not _lado_b(x) and x >= P.PORTAO_X:
			_atravessar(u, P.PORTAO_B + 6.0)
		elif x > P.CASTELO_MONSTERS_X:
			ferir_castelo("monsters", P.DANO_ENTRAR_HEROI, _pos_castelo("monsters", u.position.y))
			u.morto = true; u.livre = true
	else:
		if _lado_b(x) and x <= P.PORTAO_B:
			_atravessar(u, P.PORTAO_X - 6.0)
		elif x < P.CASTELO_HEROES_X:
			var d: float = float(u.p.dano_castelo if u.p.dano_castelo > 0 else 10)
			ferir_castelo("heroes", d, _pos_castelo("heroes", u.position.y))
			u.morto = true; u.livre = true

func _atravessar(u: Unidade, para_x: float) -> void:
	for x in [u.position.x, para_x]:
		for i in 8:
			faiscas.append({"pos": Vector2(x, u.position.y - rng.randf_range(20, 90)), "vel": Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 30)), "t": 0.0})
	u.position.x = para_x
	u.reset_physics_interpolation()                 # atravessou o portal: aparece do outro lado (sem deslizar pelo mundo)
	u.atravessou = true
	u.x_saida = para_x
	if u.lado == lado_local and not espiando and not _avisou_invasao:   # 1ª vez na partida: avisa que dá para ir junto
		_avisou_invasao = true
		mostrar_banner("Sua tropa entrou na arena inimiga!\nToque em ESPIAR para ir junto e mandar mais tropas", 2.8)
	_abrir_fenda(para_x + (-6.0 if _lado_b(para_x) else 6.0), u, true)   # o portal de saída abre na outra arena

# =================================================================== PORTAL_TROPA (enfeite)
func _abrir_fenda(x: float, u: Unidade, saida: bool) -> void:
	fendas.append({"x": x, "y": u.position.y, "u": u, "t": 0.0, "saida": saida, "fase": "abrindo", "fim": 0.0,
		"cor": CORES_FENDA["monsters" if _lado_b(x) else "heroes"], "giro": randf() * TAU})
	if _lado_b(x) == (_arena_vista() == "monsters"):
		Sons.tocar("Jogo/som/portal", 0.5)

func _passo_fendas(dt: float) -> void:
	var i := fendas.size() - 1
	while i >= 0:
		var f: Dictionary = fendas[i]
		f.t += dt
		if f.fase == "abrindo" and f.t >= PORTAL.abrir:
			f.fase = "aberto"
		if f.fase == "aberto":
			var passou: bool
			if f.saida:
				passou = f.t > PORTAL.abrir + 0.7
			else:
				var u = f.u
				passou = not is_instance_valid(u) or u.atravessou or u.morto or f.t > 8.0
			if passou:
				f.fase = "fechando"
				f.fim = 0.0
		elif f.fase == "fechando":
			f.fim += dt
			if f.fim >= PORTAL.fechar:
				fendas.remove_at(i)
		i -= 1

## Quanto a tropa aparece: some ao entrar no portal e aparece aos poucos ao sair.
## (passo fixo: o alvo_visivel também usa) Saindo: aparece andando OU com o tempo (0,4 s) — quem para logo na
## saída do portal (lutando, virado, voltando) nunca fica invisível. Entrando: só some se estiver ANDANDO para dentro.
func _alfa_fenda(u: Unidade) -> float:
	if u.atravessou:
		return minf(1.0, maxf(absf(u.position.x - u.x_saida) / PORTAL.some, u.t_saida / 0.4))
	if not u.fenda_aberta or u.estado != "andar" or u.virado:
		return 1.0
	var alvo: float = P.PORTAO_B if _lado_b(u.position.x) else P.PORTAO_X
	return clampf(absf(alvo - u.position.x) / PORTAL.some, 0.0, 1.0)

static func _ease_out_back(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)

## Tamanho do portal agora: abre como uma fenda de luz em pé e depois alarga; fecha encolhendo com um clarão.
## Devolve [rx, ry, intensidade, clarão].
func _forma_fenda(f: Dictionary) -> Array:
	var sx: float
	var sy: float
	var flash := 0.0
	if f.fase == "fechando":
		var k: float = f.fim / PORTAL.fechar
		sx = maxf(0.0, 1.0 - k * 1.4)
		sy = 1.0 - k * k
		flash = 0.0 if k < 0.8 else (k - 0.8) * 5.0
	else:
		var k2: float = minf(1.0, f.t / PORTAL.abrir)
		sy = _ease_out_back(minf(1.0, k2 * 1.5))
		sx = 0.06 if k2 < 0.3 else _ease_out_back((k2 - 0.3) / 0.7)
	var r: float = PORTAL.raio
	return [r * PORTAL.achatado * maxf(0.04, sx), r * maxf(0.0, sy), clampf(sy, 0.0, 1.0), flash]

func _elipse(c: Vector2, rx: float, ry: float, n := 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(n)
	for j in n:
		var a := TAU * j / n
		pts[j] = c + Vector2(cos(a) * rx, sin(a) * ry)
	return pts

## Miolo: túnel escuro com luz no fundo (camadas do escuro da borda até o branco do centro).
func _desenhar_fendas_corpo() -> void:
	var d := fenda_corpo
	if modo == "cerco":                                  # CERCO: um círculo de guarda no chão de cada defensor
		var tt := Time.get_ticks_msec() / 1000.0
		for lista in [herois, monstros]:
			for l in lista:
				for u in l:
					if u.guarda and not u.morto:
						var cor := Color("ffd34d") if u.lado == "heroes" else Color("9be05a")
						var pul := 0.5 + 0.5 * sin(tt * 2.4 + float(u.linha) * 1.3)
						var pe: Vector2 = u.position + Vector2(0, 3)
						d.draw_colored_polygon(_elipse(pe, 38.0, 12.0, 28), Color(cor, 0.14 + 0.08 * pul))
						var anel := _elipse(pe, 38.0 + pul * 3.0, 12.0 + pul, 28)
						anel.append(anel[0])
						d.draw_polyline(anel, Color(cor, 0.55 + 0.25 * pul), 2.0, true)
	for f in fendas:
		var fo := _forma_fenda(f)
		var rx: float = fo[0]
		var ry: float = fo[1]
		if ry < 1.0:
			continue
		var c: Dictionary = f.cor
		var cen := Vector2(f.x, f.y - PORTAL.raio - 6.0)
		d.draw_colored_polygon(_elipse(Vector2(f.x, f.y + 2.0), PORTAL.raio * 0.9, 12.0), Color(0, 0, 0, 0.28 * fo[2]))   # sombra no chão
		d.draw_colored_polygon(_elipse(cen, rx + 5.0, ry + 5.0), Color(c.d, 0.85))
		var passos := 9
		for k in passos:
			var u := 1.0 - float(k) / passos                  # 1 = borda, perto de 0 = centro
			var cor: Color
			if u > 0.5:
				cor = c.c.lerp(c.d, (u - 0.5) / 0.5)
			elif u > 0.18:
				cor = c.b.lerp(c.c, (u - 0.18) / 0.32)
			else:
				cor = c.a.lerp(c.b, u / 0.18)
			d.draw_colored_polygon(_elipse(cen, rx * u, ry * u, 32), cor)

## A luz (somando cor): brilho no chão, halo, redemoinho girando, pontinhos sugados, anel tremendo, faíscas e runas.
func _desenhar_fendas_luz() -> void:
	var d := fenda_luz
	var tempo := Time.get_ticks_msec() / 1000.0
	var R: float = PORTAL.raio
	for f in fendas:
		var fo := _forma_fenda(f)
		var rx: float = fo[0]
		var ry: float = fo[1]
		var sy: float = fo[2]
		if ry < 1.0:
			continue
		var c: Dictionary = f.cor
		var br: Color = c.brilho
		var cen := Vector2(f.x, f.y - R - 6.0)
		var tg: float = tempo + f.giro
		# luz no chão e halo em volta (camadas suaves)
		for k in 5:
			var e := 1.0 - k / 5.0
			d.draw_colored_polygon(_elipse(Vector2(f.x, f.y), R * 1.6 * e, R * 0.35 * e, 28), Color(br, 0.07 * sy))
			d.draw_colored_polygon(_elipse(cen, (rx + R * 0.9) * e, (ry + R * 0.6) * e, 28), Color(br, 0.06 * sy))
		# redemoinho: 4 braços em espiral
		for braco in 4:
			var pts := PackedVector2Array()
			for j in 31:
				var k := j / 30.0
				var ang := tg * 3.2 + braco * PI / 2.0 + k * 5.5
				var raio := (1.0 - k) * 0.98
				pts.append(cen + Vector2(cos(ang) * raio * rx, sin(ang) * raio * ry))
			d.draw_polyline(pts, Color(br, 0.55), 3.2, true)
			d.draw_polyline(pts, Color(1, 1, 1, 0.3), 1.0, true)
		# pontinhos sendo sugados para o centro
		for i in 18:
			var k3 := fmod(tg * 0.9 + i * 0.173, 1.0)
			var ang3 := i * 2.1 + tg * 2.4 + k3 * 3.0
			d.draw_circle(cen + Vector2(cos(ang3) * rx, sin(ang3) * ry) * (1.0 - k3), 1.6, Color(c.faisca, k3))
		# borda viva: anel de energia tremendo (grosso colorido + fino branco)
		for a2 in 2:
			var anel := PackedVector2Array()
			for j in 49:
				var ang4 := j / 48.0 * TAU
				var tre := 1.0 + sin(ang4 * 7.0 + tg * (9.0 + a2 * 4.0)) * 0.035 + sin(ang4 * 13.0 - tg * 7.0) * 0.02
				anel.append(cen + Vector2(cos(ang4) * rx * tre, sin(ang4) * ry * tre))
			if a2 == 0:
				d.draw_polyline(anel, Color(br, 0.25), 12.0, true)     # brilho largo
				d.draw_polyline(anel, Color(br, 0.9), 4.0, true)
			else:
				d.draw_polyline(anel, Color(1, 1, 1, 0.8), 1.4, true)
		# runas douradas girando em volta (o "mais bonito ainda")
		for i in 8:
			var ang5 := tg * 0.8 + i * TAU / 8.0
			var pr := cen + Vector2(cos(ang5) * (rx + 12.0), sin(ang5) * (ry + 12.0))
			var pisca := 0.55 + 0.45 * sin(tg * 4.0 + i)
			d.draw_circle(pr, 4.5, Color(c.runa, 0.18 * sy * pisca))
			d.draw_circle(pr, 2.2, Color(c.runa, 0.9 * sy * pisca))
		# faíscas soltando da borda
		for i in 8:
			var ang6 := i * 0.785 + tg * 1.7
			var k6 := fmod(tg * 1.3 + i * 0.37, 1.0)
			d.draw_circle(cen + Vector2(cos(ang6) * rx, sin(ang6) * ry) * 1.0 + Vector2(cos(ang6) * rx, sin(ang6) * ry) * k6 * 0.5, 1.8, Color(c.faisca, (1.0 - k6) * 0.9))
		# clarão final ao fechar
		if fo[3] > 0.0:
			for k in 4:
				d.draw_circle(cen, R * 1.2 * (1.0 - k / 4.0), Color(1, 1, 1, fo[3] * 0.25))

func _passo_projeteis(dt: float) -> void:
	var fim_a := C.W + 40.0
	var comeco_b := P.MW - C.W - 40.0
	for pr in projeteis:
		if not pr.ativo:
			continue
		pr.t += dt
		if pr.tipo == "energia" and pr.fixado:      # acertou: o feixe fica encostado no alvo e se apaga
			pr.t_fixado += dt
			if pr.t_fixado > RAIO_SOME:
				pr.ativo = false
			continue
		if pr.fixado:                                # flecha cravada na parede do castelo: fica um pouco e some
			pr.t_fixado += dt
			if pr.t_fixado > 1.6:
				pr.ativo = false
			continue
		var x0 := pr.pos.x
		pr.pos.x += pr.vel * dt
		if pr.tipo == "energia":                          # laser curva do cano até a cabeça
			if pr.castelo != "":                          # cerco: a curva vai do cano até a parede do castelo
				pass
			elif not is_instance_valid(pr.alvo_ref) or pr.alvo_ref.morto:
				pr.alvo_ref = _proximo_alvo_energia(pr)   # mirava quem morreu no caminho: mira no próximo de pé
				if pr.alvo_ref:
					pr.x_fim = pr.alvo_ref.position.x
			if is_instance_valid(pr.alvo_ref) and not pr.alvo_ref.morto:
				pr.mira_y = pr.alvo_ref.posicao_cabeca().y
				pr.x_fim = pr.alvo_ref.position.x
			var span := pr.x_fim - pr.origem.x
			if absf(span) > 1.0:
				var k := clampf((pr.pos.x - pr.origem.x) / span, 0.0, 1.0)
				pr.pos.y = lerpf(pr.origem.y, pr.mira_y, k * k)
		var b := _lado_b(pr.pos.x)
		var sv := signf(pr.vel)                          # sentido do voo (quem atirou virado: para trás)
		var lo := minf(x0, pr.pos.x) - 20.0
		var hi := maxf(x0, pr.pos.x) + 20.0
		if pr.lado == "heroes":
			var alvo: Unidade = null
			var melhor := INF
			for m in monstros[pr.linha]:
				if m.morto or _lado_b(m.position.x) != b:
					continue
				var mx: float = m.position.x
				if mx >= lo and mx <= hi and (mx - x0) * sv < melhor:
					alvo = m; melhor = (mx - x0) * sv
			if alvo:
				ferir(alvo, pr.dano, null, pr.origem_id)
				if pr.fogo:
					_acerto_fogo(pr, alvo)
				if pr.raio > 0.0:
					_explodir(pr, alvo)
					pr.ativo = false
				elif pr.tipo == "energia":
					var contato := Vector2(alvo.position.x - 12.0, alvo.posicao_cabeca().y)
					pr.pos = contato
					pr.mira_y = contato.y
					pr.x_fim = contato.x
					pr.fixado = true
					pr.t_fixado = 0.0
					_impacto_energia(alvo, contato, pr.dano)
				else:
					pr.ativo = false
			elif pr.castelo != "":
				if pr.pos.x >= pr.x_fim:                         # raio do cerco chegou na PAREDE do castelo
					_raio_no_castelo(pr)
			elif sv < 0.0:
				if pr.pos.x < (P.MW - C.W if b else C.G.left):
					pr.ativo = false                            # atirou para trás: some na beira (nunca no próprio castelo)
			elif b and pr.pos.x >= P.MW - x_muro(pr.linha):     # chegou na PAREDE do castelo dos monstros
				_tiro_no_castelo(pr, "monsters", P.MW - x_muro(pr.linha))
			elif not b and pr.pos.x > fim_a:
				pr.ativo = false
		else:
			var alvo_h: Unidade = null
			var melhor_h := -INF
			for h in herois[pr.linha]:
				if not h.ocupa_casa or _lado_b(h.position.x) != b:
					continue
				var hx: float = h.position.x
				if hx >= lo and hx <= hi and -(hx - x0) * sv > melhor_h:
					alvo_h = h; melhor_h = -(hx - x0) * sv
			if alvo_h:
				ferir(alvo_h, pr.dano, null, pr.origem_id)
				if pr.fogo:
					_acerto_fogo(pr, alvo_h)
				if pr.tipo == "magia_sombra":
					explosoes.append([alvo_h.position + Vector2(0, -50), 34.0, 0.0, Color("9b6bff")])
					pr.ativo = false
				elif pr.tipo == "energia":
					var contato2 := Vector2(alvo_h.position.x + 12.0, alvo_h.posicao_cabeca().y)
					pr.pos = contato2
					pr.mira_y = contato2.y
					pr.x_fim = contato2.x
					pr.fixado = true
					pr.t_fixado = 0.0
					_impacto_energia(alvo_h, contato2, pr.dano)
				else:
					pr.ativo = false
			elif pr.castelo != "":
				if pr.pos.x <= pr.x_fim:
					_raio_no_castelo(pr)
			elif sv > 0.0:
				if pr.pos.x > (P.MW - C.G.left if b else C.W):
					pr.ativo = false                            # atirou para trás: some na beira (nunca no próprio castelo)
			elif not b and pr.pos.x <= x_muro(pr.linha):      # chegou na PAREDE do castelo dos heróis
				_tiro_no_castelo(pr, "heroes", x_muro(pr.linha))
			elif b and pr.pos.x < comeco_b:
				pr.ativo = false

## (energia) Próximo inimigo de pé na linha, à frente do feixe — usa quando quem mirava morreu no caminho.
func _proximo_alvo_energia(pr: Projetil) -> Unidade:
	var dir := signf(pr.vel)
	var b := _lado_b(pr.pos.x)
	var lista: Array = monstros[pr.linha] if pr.lado == "heroes" else herois[pr.linha]
	var melhor: Unidade = null
	var melhor_d := INF
	for m in lista:
		if m.morto or _lado_b(m.position.x) != b:
			continue
		if pr.lado != "heroes" and not m.ocupa_casa:
			continue
		var d: float = (m.position.x - pr.pos.x) * dir
		if d > -30.0 and d < melhor_d:
			melhor = m; melhor_d = d
	return melhor

## (energia) Y da curva do feixe em qualquer x (cano -> cabeça do alvo, com a mesma parábola do voo).
func _y_curva_energia(pr: Projetil, x: float) -> float:
	var span := pr.x_fim - pr.origem.x
	if absf(span) <= 1.0:
		return pr.origem.y
	var k := clampf((x - pr.origem.x) / span, 0.0, 1.0)
	return lerpf(pr.origem.y, pr.mira_y, k * k)

## (energia) Pontos de um raio torto seguindo a curva do tiro, de x_ini até x_fim. Usa o _rng_fx (já com semente).
## As pontas ficam presas (cano e alvo) e o meio treme mais.
func _raio_curva(pr: Projetil, x_ini: float, x_fim: float, amp: float) -> PackedVector2Array:
	var n := clampi(int(absf(x_fim - x_ini) / 24.0), 2, 30)
	var pts := PackedVector2Array()
	pts.resize(n + 1)
	for i in n + 1:
		var k := float(i) / n
		var x := lerpf(x_ini, x_fim, k)
		var p := Vector2(x, _y_curva_energia(pr, x))
		if i > 0 and i < n:
			var env := minf(1.0, sin(PI * k) * 2.2)
			p += Vector2(_rng_fx.randf_range(-5.0, 5.0), _rng_fx.randf_range(-amp, amp) * env)
		pts[i] = p
	return pts

## Raio torto reto entre dois pontos (galhos e arcos no corpo).
func _raio_entre(a: Vector2, b: Vector2, n: int, amp: float) -> PackedVector2Array:
	var perp := (b - a).orthogonal().normalized()
	var pts := PackedVector2Array()
	pts.resize(n + 1)
	for i in n + 1:
		var k := float(i) / n
		var p := a.lerp(b, k)
		if i > 0 and i < n:
			p += perp * _rng_fx.randf_range(-amp, amp)
		pts[i] = p
	return pts

## Desenha um raio em camadas: brilho largo azul -> ciano -> miolo branco.
func _desenhar_raio(d: Node2D, pts: PackedVector2Array, alfa: float, largura: float) -> void:
	if pts.size() < 2 or alfa <= 0.01:
		return
	d.draw_polyline(pts, Color("1a6dff", 0.10 * alfa), 18.0 * largura)
	d.draw_polyline(pts, Color("22c8ff", 0.28 * alfa), 8.0 * largura)
	d.draw_polyline(pts, Color("8ff4ff", 0.80 * alfa), 3.4 * largura)
	d.draw_polyline(pts, Color(1, 1, 1, 0.95 * alfa), maxf(1.0, 1.5 * largura))

## Mancha de luz achatada no chão.
func _elipse_luz(d: Node2D, centro: Vector2, r: float, cor: Color) -> void:
	if cor.a <= 0.005:
		return
	d.draw_set_transform(centro, 0.0, Vector2(1.0, 0.32))
	d.draw_circle(Vector2.ZERO, r, Color(cor, cor.a * 0.6))
	d.draw_circle(Vector2.ZERO, r * 0.55, cor)
	d.draw_set_transform(Vector2.ZERO)

## Inimigo eletrocutado: arcos que correm pelo corpo, aura azul e luz no chão.
func _desenhar_choques(d: Node2D) -> void:
	for ch in choques:
		var a = ch.alvo
		if not is_instance_valid(a) or a.morto:
			continue
		var k := clampf(float(ch.t) / CHOQUE_DUR, 0.0, 1.0)
		var forca := 1.0 - k * 0.7
		var topo: Vector2 = a.posicao_cabeca() - Vector2(0, 14)
		var pe: Vector2 = a.position - Vector2(0, 6)
		var alt := pe.y - topo.y
		var meia := alt * 0.24
		var centro := Vector2(a.position.x, (topo.y + pe.y) * 0.5)
		_elipse_luz(d, Vector2(a.position.x, a.position.y - 2.0), 46.0, Color("2ab8ff", 0.16 * forca))
		# aura em volta do corpo
		d.draw_set_transform(centro, 0.0, Vector2(meia / alt * 2.2, 1.0))
		d.draw_circle(Vector2.ZERO, alt * 0.55, Color("1a8fff", 0.08 * forca))
		d.draw_circle(Vector2.ZERO, alt * 0.42, Color("40eaff", 0.07 * forca))
		d.draw_set_transform(Vector2.ZERO)
		# arcos pulando de um ponto do corpo para outro (mudam ~25x por segundo)
		_rng_fx.seed = int(ch.semente) + int(float(ch.t) * 25.0) * 104729
		var n_arcos := 3 + int(2.0 * forca)
		for q in n_arcos:
			var p0 := Vector2(a.position.x + _rng_fx.randf_range(-meia, meia), _rng_fx.randf_range(topo.y, pe.y))
			var p1 := p0 + Vector2(_rng_fx.randf_range(-meia, meia) * 1.4, _rng_fx.randf_range(-alt, alt) * 0.35)
			_desenhar_raio(d, _raio_entre(p0, p1, 5, 5.0), forca * _rng_fx.randf_range(0.6, 1.0), 0.45)
			d.draw_circle(p1, 2.2 * forca, Color.WHITE, forca)
		# um arco maior que escapa para fora do corpo de vez em quando
		if _rng_fx.randf() < 0.45 * forca:
			var p0 := Vector2(a.position.x + _rng_fx.randf_range(-meia, meia) * 0.5, _rng_fx.randf_range(topo.y, pe.y))
			var ang := _rng_fx.randf_range(0.0, TAU)
			_desenhar_raio(d, _raio_entre(p0, p0 + Vector2(cos(ang), sin(ang)) * _rng_fx.randf_range(30.0, 55.0), 6, 7.0), forca * 0.8, 0.5)

func _explodir(pr: Projetil, alvo: Unidade) -> void:
	var centro := alvo.position + Vector2(0, -50)
	explosoes.append([centro, pr.raio, 0.0, Color("ff8a2a") if pr.tipo == "magia_fogo" else Color("7fb6ff")])
	for r in range(maxi(0, pr.linha - 1), mini(C.G.rows, pr.linha + 2)):
		for m in monstros[r]:
			if m != alvo and not m.morto and (m.position + Vector2(0, -50)).distance_to(centro) <= pr.raio:
				ferir(m, pr.dano_area, null, pr.origem_id)
	Sons.tocar(alvo.p.sons.get("impacto", "Mago/som/explosao"), 0.7)

## Impacto do laser do Engenheiro: flash branco + anel + faíscas arremessadas pra frente no ponto de contato.
## Determinístico (sem rng): o sim de rede compartilha o rng e não pode ganhar chamadas extras.
func _impacto_energia(alvo: Unidade, ponto: Vector2, dano_tiro := 0) -> void:
	impactos.append({"pos": ponto, "t": 0.0})
	# CHOQUE (partida): +50% do dano do tiro em pulsos; tiro novo no mesmo alvo renova o choque
	if dano_tiro > 0 and not alvo.morto:
		var extra := float(dano_tiro) * CHOQUE_PCT
		var achou := false
		for ch in choques:
			if ch.alvo == alvo:
				ch.dano = float(ch.dano) * (1.0 - float(ch.pulsos) / CHOQUE_PULSOS) + extra
				ch.t = 0.0
				ch.pulsos = 0
				achou = true
				break
		if not achou:
			choques.append({"alvo": alvo, "t": 0.0, "dano": extra, "pulsos": 0, "semente": randi()})
	var dir := signf(alvo.position.x - ponto.x)
	if dir == 0.0:
		dir = 1.0
	for k in 5:                                  # faíscas arremessadas no sentido do tiro
		var ang: float = -1.1 + 0.45 * float(k) + sin(ponto.x * 0.17 + float(k)) * 0.15
		var v := Vector2(cos(ang), sin(ang)).rotated(0.0 if dir > 0.0 else PI) * (110.0 + 26.0 * float(k))
		faiscas.append({"pos": ponto, "t": 0.0, "vel": v})
	Sons.tocar("Elara/som/energia", 0.4)

## Marca do raio na parede: pedra queimada com rachaduras que brilham azul e depois esfriam.
func _desenhar_marcas(d: Node2D) -> void:
	for m in marcas:
		var k: float = float(m.t) / 5.0
		var some := 1.0 - k * k
		var fogo: bool = m.get("fogo", false)                # bomba: brasa laranja (e esfria mais devagar)
		var quente := clampf(1.0 - float(m.t) / (2.4 if fogo else 1.4), 0.0, 1.0)
		var c_largo := Color("ff5a10") if fogo else Color("22c8ff")
		var c_fino := Color("ffd27a") if fogo else Color("bff8ff")
		var c_meio := Color("ff7a20") if fogo else Color("40eaff")
		var esc := 1.35 if fogo else 1.0
		var p: Vector2 = m.pos
		d.draw_set_transform(p, 0.0, Vector2(1.0, 1.25))
		d.draw_circle(Vector2.ZERO, 30.0 * esc, Color(0.05, 0.05, 0.08, 0.30 * some))
		d.draw_circle(Vector2.ZERO, 17.0 * esc, Color(0.02, 0.02, 0.04, 0.45 * some))
		d.draw_set_transform(Vector2.ZERO)
		_rng_fx.seed = int(m.semente)
		for q in 7 if fogo else 6:                    # rachaduras saindo do centro
			var ang := TAU * q / (7.0 if fogo else 6.0) + _rng_fx.randf_range(-0.4, 0.4)
			var fim_r := p + Vector2(cos(ang), sin(ang)) * _rng_fx.randf_range(16.0, 38.0) * esc
			var pts := _raio_entre(p, fim_r, 4, 4.0)
			d.draw_polyline(pts, Color(0.03, 0.03, 0.05, 0.55 * some), 2.2)
			if quente > 0.0:
				d.draw_polyline(pts, Color(c_largo, 0.45 * quente), 4.0)
				d.draw_polyline(pts, Color(c_fino, 0.9 * quente), 1.3)
		if quente > 0.0:
			d.draw_circle(p, 9.0 * esc, Color(c_meio, 0.35 * quente))
			d.draw_circle(p, 4.0 * esc, Color(1, 0.95, 0.8, 0.8 * quente))

## Explosão elétrica na parede do castelo + pedras voando.
func _desenhar_golpes_castelo(d: Node2D) -> void:
	for g in golpes_castelo:
		var t: float = g.t
		var k := t / 0.9
		var a := 1.0 - k
		var p: Vector2 = g.pos
		# luz azul que ilumina a parede inteira em volta
		d.draw_set_transform(p, 0.0, Vector2(0.8, 1.2))
		d.draw_circle(Vector2.ZERO, 150.0, Color("1a8fff", 0.10 * a * a))
		d.draw_circle(Vector2.ZERO, 85.0, Color("40eaff", 0.16 * a * a))
		d.draw_set_transform(Vector2.ZERO)
		# clarão branco do impacto (bem no começo)
		var flash := clampf(1.0 - t / 0.12, 0.0, 1.0)
		if flash > 0.0:
			d.draw_circle(p, 80.0 * flash + 20.0, Color(1, 1, 1, 0.45 * flash))
			d.draw_circle(p, 40.0 * flash + 10.0, Color("e8ffff", 0.9 * flash))
		# fumaça escura subindo da pedra
		_rng_fx.seed = int(g.semente)
		for q in 6:
			var dx: float = _rng_fx.randf_range(-26.0, 26.0) - float(g.dir) * t * 30.0
			var sobe := t * _rng_fx.randf_range(50.0, 90.0) + q * 4.0
			var r := 12.0 + 40.0 * k * _rng_fx.randf_range(0.7, 1.2)
			var cinza := _rng_fx.randf_range(0.18, 0.3)
			d.draw_circle(p + Vector2(dx, -sobe), r, Color(cinza, cinza, cinza * 1.1, 0.32 * a * clampf(t / 0.08, 0.0, 1.0)))
		# ondas de choque achatadas na parede
		for q in 2:
			var kk := clampf((t - q * 0.08) / 0.5, 0.0, 1.0)
			if kk <= 0.0 or kk >= 1.0:
				continue
			var anel := PackedVector2Array()
			var rr := 18.0 + 130.0 * kk
			for j in 33:
				var ang := TAU * j / 32.0
				anel.append(p + Vector2(cos(ang) * rr * 0.75, sin(ang) * rr))
			d.draw_polyline(anel, Color("40eaff", 0.55 * (1.0 - kk)), 5.0 * (1.0 - kk) + 1.0)
			d.draw_polyline(anel, Color(1, 1, 1, 0.5 * (1.0 - kk)), 1.4)
		# raios correndo pela parede (mudam ~25x por segundo)
		if t < 0.6:
			var forca := 1.0 - t / 0.6
			_rng_fx.seed = int(g.semente) + int(t * 25.0) * 7919
			for q in 7:
				var alvo := p + Vector2(_rng_fx.randf_range(-95.0, 95.0), _rng_fx.randf_range(-140.0, 140.0))
				_desenhar_raio(d, _raio_entre(p, alvo, 7, 9.0), forca * _rng_fx.randf_range(0.5, 1.0), 0.6)
				if _rng_fx.randf() < 0.5:              # galho do galho
					var meio := p.lerp(alvo, 0.6)
					_desenhar_raio(d, _raio_entre(meio, meio + Vector2(_rng_fx.randf_range(-40, 40), _rng_fx.randf_range(-40, 40)), 3, 5.0), forca * 0.6, 0.35)
		# miolo de plasma
		d.draw_circle(p, 22.0 * a + 4.0, Color("40eaff", 0.45 * a))
		d.draw_circle(p, 10.0 * a + 2.0, Color(1, 1, 1, 0.95 * a))
	# pedras arrancadas (a borda brilha azul no começo, quente do raio)
	for e in estilhacos:
		var al := clampf((1.8 - float(e.t)) / 0.5, 0.0, 1.0)
		var tam: float = e.tam
		d.draw_set_transform(e.pos, e.ang)
		d.draw_colored_polygon(PackedVector2Array([Vector2(-tam, -tam * 0.6), Vector2(tam * 0.4, -tam), Vector2(tam, tam * 0.3),
			Vector2(-tam * 0.2, tam)]), Color(e.cor, al))
		var brasa := clampf(1.0 - float(e.t) / 0.35, 0.0, 1.0)
		if brasa > 0.0:
			d.draw_circle(Vector2.ZERO, tam * 0.9, Color("ff9a3a", 0.6 * brasa) if e.get("fogo", false) else Color("80f0ff", 0.55 * brasa))
	d.draw_set_transform(Vector2.ZERO)

## X da PAREDE do castelo dos heróis na altura de uma linha (no mundo; o dos monstros é MW - isto).
## O castelo está em perspectiva: embaixo a parede vem mais para a ponta. PARTIDA: número fixo (igual nos dois
## aparelhos, não depende do tamanho da tela). Medido nos fundos 2560x1080 (igual ao _x_muro da campanha).
func x_muro(linha: int) -> float:
	var k := C.H / 1080.0
	var ox := (C.W - 2560.0 * k) / 2.0
	var oy := (C.H - 1080.0 * k) / 2.0
	var orig_y := (C.linha_y(linha) - 72.0 - oy) / k
	return lerpf(600.0, 512.0, clampf((orig_y - 384.0) / (832.0 - 384.0), 0.0, 1.0)) * k + ox

## Flecha / magia chegou na PAREDE do castelo inimigo (atirada do cerco ou de longe).
## PARTIDA: o dano no castelo e a flecha cravada (o tempo dela). O resto é enfeite (randf global, nunca o rng).
func _tiro_no_castelo(pr: Projetil, lado_c: String, x_parede: float) -> void:
	pr.pos.x = x_parede
	var dano_c := float(P.DANO_TIRO_CASTELO)
	if pr.fogo:
		dano_c *= 1.6                                         # flecha de fogo queima a madeira / pedra: dói mais
	ferir_castelo(lado_c, dano_c, pr.pos)
	var dir := signf(pr.vel)
	var ponto := pr.pos
	var flecha := pr.tipo in ["flecha", "flecha_inimiga"]
	if flecha:
		pr.fixado = true                                      # a flecha CRAVA na parede (some depois de 1,6 s)
		pr.t_fixado = 0.0
	else:
		pr.ativo = false
	# --- enfeite ---
	var pedras := 5 if flecha else 12
	for k in pedras:                                          # lascas de pedra arrancadas da parede
		var ang := randf_range(-1.1, 1.1) + (PI if dir > 0.0 else 0.0)
		var vel := Vector2(cos(ang), sin(ang)) * randf_range(90.0, 260.0 if flecha else 380.0) + Vector2(0, -randf_range(50.0, 170.0))
		var cinza := randf_range(0.3, 0.55)
		estilhacos.append({"pos": ponto + Vector2(randf_range(-6, 6), randf_range(-6, 6)), "vel": vel, "t": 0.0,
			"giro": randf_range(-12.0, 12.0), "ang": randf() * TAU, "tam": randf_range(1.8, 3.6) if flecha else randf_range(2.5, 6.0),
			"cor": Color(cinza, cinza * 0.95, cinza * 0.9), "chao": ponto.y + randf_range(60.0, 140.0), "fogo": pr.fogo or pr.tipo == "magia_fogo"})
	if pr.fogo or pr.tipo == "magia_fogo":                    # FOGO: labareda na parede, brasas e a marca queimada
		if fx_ar:
			fx_ar.explodir(ponto, 0.42 if flecha else 0.6)
		marcas.append({"pos": ponto + Vector2(randf_range(-4, 4), randf_range(-4, 4)), "t": 0.0, "semente": randi(), "fogo": true})
		for k in 14:
			faiscas.append({"pos": ponto, "t": randf_range(0.0, 0.15), "raio": true, "cor": Color("ffb347"),
				"vel": Vector2(-dir * randf_range(60.0, 260.0), randf_range(-280.0, 40.0))})
		_som_fogo(pr.origem_id)
	elif flecha:                                              # flecha comum: poeira de pedra no furo
		explosoes.append([ponto, 18.0, 0.0, Color("c8b8a0")])
	else:                                                     # magia: estoura na pedra com a cor dela
		var cor := Color("9b6bff") if pr.tipo == "magia_sombra" else Color("7fb6ff")
		explosoes.append([ponto, 62.0, 0.0, cor])
		explosoes.append([ponto, 30.0, 0.0, Color(1, 1, 1)])
		for k in 10:
			faiscas.append({"pos": ponto, "t": randf_range(0.0, 0.12), "raio": true, "cor": cor.lightened(0.3),
				"vel": Vector2(-dir * randf_range(60.0, 240.0), randf_range(-240.0, 60.0))})
	if marcas.size() > 12:
		marcas.pop_front()

func _som_fogo(id: String) -> void:
	var quem: PersonagemDados = Catalogo.get_p(id)
	if quem and quem.sons.has("fogo"):
		Sons.do_personagem(quem, "fogo")

## Raio do cerco acertou a PAREDE do castelo: 30% do dano do tiro (partida) + explosão elétrica na pedra (enfeite).
func _raio_no_castelo(pr: Projetil) -> void:
	var ponto := Vector2(pr.x_fim, pr.mira_y)
	pr.pos = ponto
	pr.fixado = true
	pr.t_fixado = 0.0
	ferir_castelo(pr.castelo, float(pr.dano) * RAIO_CASTELO_PCT, ponto)
	# --- daqui para baixo é só enfeite (rng global, nunca o da partida) ---
	var dir := signf(pr.vel)                      # para onde o raio ia (a pedra voa de volta, para o lado dele)
	golpes_castelo.append({"pos": ponto, "t": 0.0, "semente": randi(), "dir": dir})
	marcas.append({"pos": ponto + Vector2(randf_range(-6, 6), randf_range(-6, 6)), "t": 0.0, "semente": randi()})
	if marcas.size() > 12:
		marcas.pop_front()
	for k in 14:                                  # pedaços de pedra arrancados da parede
		var ang := randf_range(-1.2, 1.2) + (PI if dir > 0.0 else 0.0)
		var vel := Vector2(cos(ang), sin(ang)) * randf_range(120.0, 360.0) + Vector2(0, -randf_range(60.0, 200.0))
		var cinza := randf_range(0.28, 0.55)
		estilhacos.append({"pos": ponto + Vector2(randf_range(-10, 10), randf_range(-10, 10)), "vel": vel, "t": 0.0,
			"giro": randf_range(-12.0, 12.0), "ang": randf() * TAU, "tam": randf_range(2.5, 6.5),
			"cor": Color(cinza, cinza * 0.97, cinza * 1.05), "chao": ponto.y + randf_range(60.0, 140.0)})
	for k in 12:                                  # faíscas elétricas espirrando da parede
		faiscas.append({"pos": ponto, "t": randf_range(0.0, 0.1), "raio": true,
			"vel": Vector2(-dir * randf_range(80.0, 320.0), randf_range(-260.0, 80.0))})
	Sons.tocar("Elara/som/energia", 0.5)

## Choque do raio (PARTIDA): pulsos de dano elétrico (números azuis). Só o estado do passo fixo decide —
## nada de rng da partida aqui, a não ser o do próprio ferir() (que roda igual nos dois aparelhos).
func _passo_choques(dt: float) -> void:
	var i := choques.size() - 1
	while i >= 0:
		var ch: Dictionary = choques[i]
		var a = ch.alvo
		if not is_instance_valid(a) or a.morto or a.livre:
			if is_instance_valid(a):
				a.modulate = Color(1, 1, 1, a.modulate.a)
			choques.remove_at(i)
			i -= 1
			continue
		ch.t += dt
		var devido := mini(CHOQUE_PULSOS, int(ch.t / (CHOQUE_DUR / CHOQUE_PULSOS) + 0.001))
		while ch.pulsos < devido:
			ch.pulsos += 1
			var cab: Vector2 = a.posicao_cabeca()
			for k in 4:                                    # faíscas que pulam do corpo (enfeite: rng global)
				faiscas.append({"pos": Vector2(a.position.x + randf_range(-14, 14), lerpf(cab.y, a.position.y, randf())),
					"t": 0.0, "vel": Vector2(randf_range(-160, 160), randf_range(-220, -40)), "raio": true})
			ferir(a, float(ch.dano) / CHOQUE_PULSOS, null, "engenheiro", Color("5ff0ff"))
			if a.morto:
				break
		if (ch.t >= CHOQUE_DUR and ch.pulsos >= CHOQUE_PULSOS) or a.morto:
			a.modulate = Color(1, 1, 1, a.modulate.a)
			choques.remove_at(i)
		i -= 1

func _passo_ondas(dt: float) -> void:
	var i := ondas.size() - 1
	while i >= 0:
		var o: Onda = ondas[i]
		o.x += o.vel * dt
		o.idade += dt
		var b := _lado_b(o.x)
		if b != _lado_b(o.x0):
			o.x0 = P.MW - C.W if b else C.W                 # passou pelo portal: o rastro recomeça do outro lado
		var lista: Array = monstros[o.linha] if o.lado == "heroes" else herois[o.linha]
		var parou := false
		for alvo in lista:                               # DARIAN com o martelo na frente: a onda para nele
			if alvo.bloqueando() and _lado_b(alvo.position.x) == b and absf(alvo.position.x - o.x) < 34.0:
				alvo.bloqueou_onda(o.tipo)
				if o.tipo == "fogo" and fx_ar:            # o rastro atrás da frente baixa e apaga
					fx_ar.apagar_fogo(o.x0, o.x, C.linha_y(o.linha) - 2.0, o.idade, float(o.linha) * 1.3)
				parou = true
				break
		if parou:
			ondas.remove_at(i)
			i -= 1
			continue
		for alvo in lista:
			if alvo.morto or _lado_b(alvo.position.x) != b or o.atingidos.has(alvo.get_instance_id()):
				continue
			if absf(alvo.position.x - o.x) < 30.0:
				o.atingidos[alvo.get_instance_id()] = true
				ferir(alvo, o.dano)
				if o.tipo == "fogo":                         # o fogo do Golem: labareda no corpo e o tranco (só visual)
					explosoes.append([alvo.position + Vector2(0, -45), 44.0, 0.0, Color("ff7a1a")])
					alvo.levar_impacto(signf(o.vel), 0.8)
		var some := false
		if o.lado == "heroes":
			if b and o.x >= P.MW - C.G.left - 30.0:
				ferir_castelo("monsters", P.DANO_PODER_CASTELO, Vector2(o.x, C.linha_y(o.linha) - 40))
				some = true
			elif not b and o.x > C.W + 40:
				some = true
		else:
			if not b and o.x <= C.G.left + 30.0:
				ferir_castelo("heroes", P.DANO_PODER_CASTELO, Vector2(o.x, C.linha_y(o.linha) - 40))
				some = true
			elif b and o.x < P.MW - C.W - 40:
				some = true
		if some:
			if o.tipo == "fogo" and fx_ar:               # (só visual) o rastro baixa e apaga
				fx_ar.apagar_fogo(o.x0, o.x, C.linha_y(o.linha) - 2.0, o.idade, float(o.linha) * 1.3)
			ondas.remove_at(i)
		i -= 1

func _passo_orbes(dt: float) -> void:
	var pega_bot := lerpf(P.BOT.pega_facil, P.BOT.pega_dificil, _forca_bot())
	var i := orbes.size() - 1
	while i >= 0:
		var o: Dictionary = orbes[i]
		o.t += dt
		var caindo: bool = o.pos.y < o.alvo_y
		if caindo:                                     # cai do céu devagar, balançando
			o.pos.y = minf(o.alvo_y, o.pos.y + 75.0 * dt)
			if o.has("x0"):
				o.pos.x = o.x0 + sin(o.t * 2.2) * 14.0
			if o.pos.y >= o.alvo_y - 0.05:             # chegou (o Vector2 guarda menos casas que o alvo_y:
				o.alvo_y = o.pos.y                     # sem isso ele "nunca chegava" e a energia não sumia)
			if o.pos.y < o.alvo_y:
				o.t = 0.0
		if o.has("fonte") and (not is_instance_valid(o.fonte) or o.fonte.morto):
			if o.lado == lado_local:                       # quem gerou na arena inimiga caiu: a energia dele some
				explosoes.append([o.pos, 26.0, 0.0, Color("ffe08a")])
			orbes.remove_at(i)
			i -= 1
			continue
		if online():                                # ONLINE: tudo aqui acontece igual nos dois aparelhos
			if C.COLETA_AUTOMATICA > 0 and o.t > C.COLETA_AUTOMATICA:
				_coletar_sim(i)
			elif C.COLETA_AUTOMATICA <= 0 and o.t > C.energia_dura + C.ENERGIA_MARGEM_ONLINE:
				orbes.remove_at(i)                     # ninguém clicou: sumiu (a margem espera o clique chegar)
		elif o.lado == outro:                          # o bot "clica" na energia dele
			if not caindo and o.t >= pega_bot:
				energias[outro] += o.valor
				orbes.remove_at(i)
			elif o.t > C.energia_dura:
				orbes.remove_at(i)
		elif C.COLETA_AUTOMATICA > 0 and o.t > C.COLETA_AUTOMATICA:
			_coletar(i)
		elif C.COLETA_AUTOMATICA <= 0 and o.t > C.energia_dura:
			orbes.remove_at(i)                         # não clicou a tempo: perdeu (igual Plants vs Zombies)
		i -= 1

func _coletar(i: int) -> void:
	var o: Dictionary = orbes[i]
	voos.append({"de": para_tela(o.pos), "t": 0.0, "valor": o.valor})
	orbes.remove_at(i)

## ONLINE: a energia entra no passo da partida (igual nos dois aparelhos). O voo até o painel é só enfeite.
func _coletar_sim(i: int) -> void:
	var o: Dictionary = orbes[i]
	energias[o.lado] += o.valor
	if o.lado == lado_local and not o.get("pega_local", false):
		voos.append({"de": para_tela(o.pos), "t": 0.0, "valor": 0})
	orbes.remove_at(i)

## "100 moedas e 20 troféus" ("" = sem aposta).
static func _texto_aposta(m: int, t: int) -> String:
	var p := []
	if m > 0:
		p.append("%d moedas" % m)
	if t > 0:
		p.append("%d troféus" % t)
	return " e ".join(p)

## Toque: pega a energia perto (só a sua). Também bloqueia colocar tropa se o toque foi quase em cima de uma.
## Espiando também vale: a energia que a SUA Elara / Esqueleto Black gera na arena inimiga é pega lá.
func pegar_energia(pos_tela: Vector2) -> bool:
	var p := para_mundo(pos_tela)
	var perto := false
	for i in orbes.size():
		var o: Dictionary = orbes[i]
		if o.lado != lado_local or o.get("pega_local", false):
			continue
		if C.COLETA_AUTOMATICA <= 0 and o.t > C.energia_dura:
			continue                                   # já acabou o tempo
		var d: float = o.pos.distance_to(p)
		if d < C.ENERGIA_TOQUE:
			if online():                               # ONLINE: já voa na sua tela; a energia entra quando a ação chegar
				o.pega_local = true
				voos.append({"de": para_tela(o.pos), "t": 0.0, "valor": 0})
				agendar({"tipo": "orbe", "id": o.id})
			else:
				_coletar(i)
			Sons.tocar("Jogo/som/energia", 0.6)
			return true
		if d < C.ENERGIA_ZONA_SEGURA:
			perto = true
	return perto

# =================================================================== BOT
func _forca_bot() -> float:
	return float(bot_nivel - 1) / float(P.BOT.maximo - 1)

func _linha_mais_cheia(lista_lado: Array) -> int:
	var n: Array[int] = []
	var maior := 0
	for r in C.G.rows:
		var c := 0
		for u in lista_lado[r]:
			if not u.morto:
				c += 1
		n.append(c)
		maior = maxi(maior, c)
	if maior == 0:
		return rng.randi() % C.G.rows
	var melhores := []
	for r in C.G.rows:
		if n[r] == maior:
			melhores.append(r)
	return melhores[rng.randi() % melhores.size()]

## Começo da partida contra o bot: jeito de jogar e nível das tropas dele.
func _preparar_bot() -> void:
	var estilos := P.ESTILOS.keys()
	bot_estilo = estilos[rng.randi() % estilos.size()]
	bot_horda = 0
	# tropas do bot: de 60% (nível 1) a 100% (nível máximo) da média dos SEUS níveis
	var ids: Array = P.CARTAS_HEROES if lado_local == "heroes" else P.CARTAS_MONSTERS
	var soma := 0
	for id in ids:
		soma += _nivel_tropa(lado_local, id, true)
	var media := float(soma) / maxf(1.0, ids.size())
	bot_nivel_tropa = clampi(roundi(media * _mistura(P.BOT.nivel_tropas)), 1, Progressao.NIVEL_MAX)

## Valor do bot entre o nível 1 ([0]) e o máximo ([1]).
func _mistura(par: Array) -> float:
	return lerpf(float(par[0]), float(par[1]), _forca_bot())

func _tropas_bot() -> Array:
	return monstros if outro == "monsters" else herois

func _tropas_jogador() -> Array:
	return herois if outro == "monsters" else monstros

## Quanto a tropa do jogador já andou dentro da arena do bot (0 = acabou de sair do portal, 1 = no castelo).
func _avanco(u: Unidade) -> float:
	if outro == "monsters":
		return clampf((u.position.x - P.PORTAO_B) / (P.CASTELO_MONSTERS_X - P.PORTAO_B), 0.0, 1.0)
	return clampf((P.PORTAO_X - u.position.x) / (P.PORTAO_X - P.CASTELO_HEROES_X), 0.0, 1.0)

## Perigo de cada linha (tropas do jogador na arena do bot) menos a defesa que o bot já tem nela.
func _perigo_linhas() -> Array:
	var r_out := []
	var meus := _tropas_bot()
	var deles := _tropas_jogador()
	for r in C.G.rows:
		var perigo := 0.0
		var perto := 0.0
		for u in deles[r]:
			if not u.morto and u.atravessou:
				var a := _avanco(u)
				perigo += float(u.p.custo) * (0.6 + a)
				perto = maxf(perto, a)
		var defesa := 0.0
		for u in meus[r]:
			if not u.morto and not u.atravessou and u.p.comportamento != "gerador":
				defesa += float(u.p.custo)
		r_out.append({"linha": r, "falta": perigo - defesa * 0.8, "perto": perto})
	return r_out

## Linha onde o jogador tem menos defesa na arena dele (boa para atacar).
func _linha_fraca() -> int:
	var deles := _tropas_jogador()
	var melhor := -1
	var menor := INF
	for r in C.G.rows:
		var d := rng.randf() * 40.0                      # um pouco de sorte para não ser sempre igual
		for u in deles[r]:
			if not u.morto and not u.atravessou:
				d += float(u.p.custo)
		if d < menor:
			menor = d
			melhor = r
	return melhor

func _colocar_bot(p: PersonagemDados, linha: int, perto_do_castelo: bool) -> bool:
	var n := roundi(lerpf(P.BOT.colunas, P.BOT.colunas_max, _forca_bot()))
	var cols := range(n)                                 # coluna 0 = do lado do castelo do bot
	if not perto_do_castelo:
		cols.reverse()                                   # ataque: o mais na frente possível
	for c in cols:
		if colocar(outro, p.id, linha, c, false):
			return true
	return false

## Escolhe a melhor tropa de um tipo (a mais cara que dá para pagar). Vazio = nenhuma.
func _melhor(opcoes: Array, tipos: Array) -> PersonagemDados:
	var esc: PersonagemDados = null
	for p in opcoes:
		if p.comportamento in tipos and (esc == null or p.custo > esc.custo):
			esc = p
	return esc

const _PERTO := ["escudo", "corpo_a_corpo", "tita", "necro", "golem", "darian"]
const _LONGE := ["atirador", "mago", "sentinela", "mistico", "aura"]

func _jogada_do_bot() -> void:
	if fim:
		return
	var ids: Array = P.CARTAS_MONSTERS if outro == "monsters" else P.CARTAS_HEROES
	var rec: Dictionary = recargas[outro]
	var opcoes: Array[PersonagemDados] = []
	for id in ids:
		var p: PersonagemDados = Catalogo.get_p(id)
		if p and p.custo <= energias[outro] and rec.get(id, 0.0) <= 0.0:
			opcoes.append(p)
	var est: Dictionary = P.ESTILOS.get(bot_estilo, P.ESTILOS.defensor)
	var f := _forca_bot()
	var esperto := rng.randf() < _mistura(P.BOT.esperto)
	# HORDA saindo: uma tropa de ataque atrás da outra, na linha mais fraca do jogador
	if bot_horda > 0:
		var atq: Array = opcoes.filter(func(p): return p.comportamento != "gerador")
		if atq.is_empty():
			bot_horda = 0
			return
		var e: PersonagemDados = atq[rng.randi() % atq.size()]
		if not _colocar_bot(e, _linha_fraca(), false):
			bot_horda = 0
			return
		bot_horda -= 1
		return
	if opcoes.is_empty():
		return
	# 1) ENERGIA: quer ter algumas Elaras / Esqueletos Black (lá atrás, perto do castelo)
	var ger_alvo := maxi(1, roundi(_mistura(P.BOT.geradores)) + int(est.geradores))
	var ger := 0
	for l in _tropas_bot():
		for u in l:
			if not u.morto and u.p.comportamento == "gerador":
				ger += 1
	var gerador := _melhor(opcoes, ["gerador"])
	if gerador and ger < ger_alvo and tempo < _t_morte_subita() * 0.4 and (esperto or rng.randf() < 0.5):
		var linhas := range(C.G.rows)
		linhas.shuffle()
		for r in linhas:
			if _colocar_bot(gerador, r, true):
				return
	if modo == "cerco" and defensor == outro:
		_jogada_bot_defesa(opcoes, est, esperto)
		return
	# 2) DEFESA: a linha com mais perigo (tropas do jogador chegando no castelo do bot)
	var perigos := _perigo_linhas()
	perigos.sort_custom(func(a, b): return a.falta > b.falta)
	if perigos[0].falta > 0.0 and rng.randf() < minf(0.98, _mistura(P.BOT.reage) * float(est.reage)):
		var r: int = perigos[0].linha
		var esc: PersonagemDados = null
		if esperto:                                      # perto do castelo: quem segura; longe: quem atira
			esc = _melhor(opcoes, _PERTO if perigos[0].perto > 0.55 else _LONGE)
			if esc == null:
				esc = _melhor(opcoes, _PERTO + _LONGE)
		if esc == null:
			var atq: Array = opcoes.filter(func(p): return p.comportamento != "gerador")
			if not atq.is_empty():
				esc = atq[rng.randi() % atq.size()]
		if esc and _colocar_bot(esc, r, true):
			return
	# 3) HORDA: a partir do nível 3, junta energia e manda um monte de tropas juntas
	if bot_nivel >= int(P.BOT.horda_a_partir):
		var limiar := _mistura(P.BOT.horda_energia) * float(est.horda_energia)
		if energias[outro] >= limiar:
			bot_horda = maxi(2, roundi(_mistura(P.BOT.horda_tamanho)) + int(est.horda_tamanho))
			hordas_bot += 1
			if bot_horda >= 3:
				var quem := ("O adversário" if adversario == "" else adversario)
				_aviso_horda(quem)
			_jogada_do_bot()
			return
		if rng.randf() < lerpf(0.5, 0.85, f):
			return                                       # guardando energia para a horda (a defesa continua acima)
	# 4) JOGADA NORMAL: uma tropa na linha mais fraca do jogador (no fácil, quase no sorteio)
	var atq2: Array = opcoes.filter(func(p): return p.comportamento != "gerador")
	if atq2.is_empty():
		return
	var esc2: PersonagemDados = atq2[rng.randi() % atq2.size()]
	if bot_nivel >= int(P.BOT.horda_a_partir):           # juntando para a horda: só tropa barata no meio tempo
		for p in atq2:
			if p.custo < esc2.custo:
				esc2 = p
	elif rng.randf() < f * 0.7:                          # mais forte: escolhe mais vezes a tropa mais cara
		for p in atq2:
			if p.custo > esc2.custo:
				esc2 = p
	var linha := _linha_fraca() if esperto else _linha_mais_cheia(herois if outro == "monsters" else monstros)
	_colocar_bot(esc2, linha, false)

func _aviso_horda(quem: String) -> void:
	mostrar_banner("⚠ UMA HORDA ESTÁ VINDO! ⚠\n%s juntou energia e mandou um monte de tropas" % quem, 2.6)
	Sons.tocar("Jogo/som/lutem", 0.8)

# =================================================================== REGISTRO (painel)
func _atividade() -> String:
	if not replay.is_empty():
		return "replay"
	if online():
		return "cerco" if modo == "cerco" else ("duelo" if rede.get("amistoso", false) else "pvp_online")
	return "cerco" if modo == "cerco" else "pvp_bot"

func _registrar_cartas(venceu: bool) -> void:
	if not cartas_usadas.is_empty():
		Conta.registrar("cartas", {"modo": _atividade(), "venceu": venceu, "lado": lado_local, "cartas": cartas_usadas.duplicate()})
	cartas_usadas = {}

# =================================================================== MODO CERCO
## Custo do Espiar (no Cerco é de graça: quem ataca precisa ver a arena do outro).
func custo_espiar() -> int:
	return 0 if modo == "cerco" else C.ESPIAR_CUSTO

## Quem ataca no Cerco marcha mais rápido dentro da própria arena (até o portal). Unidade chama.
func marcha(u: Unidade) -> float:
	if modo != "cerco" or u.lado == defensor or u.atravessou:
		return 1.0
	return float(P.MODO_CERCO.marcha)

func _atacante() -> String:
	return "monsters" if defensor == "heroes" else "heroes"

## Começo de uma rodada: castelos cheios, energia nova (quem defende ganha um extra), relógio e preparo.
func _preparar_rodada() -> void:
	vidas = {"heroes": P.VIDA_CASTELO, "monsters": P.VIDA_CASTELO}
	energias = {"heroes": float(P.ENERGIA_INICIAL), "monsters": float(P.ENERGIA_INICIAL)}
	energias[defensor] += float(P.MODO_CERCO.energia_defesa)
	if not online():
		energias[outro] += (bot_nivel - 1) * P.BOT.energia_inicial_por_nivel
		bot_estilo = "defensor" if defensor == outro else "atacante"
		bot_horda = 0
	recargas = {"heroes": {}, "monsters": {}}
	tempo = 0.0
	mare = 1
	gasto = {"heroes": 0.0, "monsters": 0.0}
	preparo = float(P.MODO_CERCO.preparo)
	sol_t = 2.0
	bot_t = 3.0

func _banner_rodada() -> void:
	var eu_defendo := defensor == lado_local
	if eu_defendo:
		mostrar_banner("CERCO · RODADA %d DE 2\nVOCÊ DEFENDE! Seus personagens ficam firmes guardando o castelo.\nAguente o ataque %s o máximo que puder" % [rodada, ("de " + adversario) if adversario != "" else "do adversário"], 5.0)
	else:
		mostrar_banner("CERCO · RODADA %d DE 2\nVOCÊ ATACA! Suas tropas marcham até o castelo %s.\nQuando elas entrarem lá, toque em ESPIAR para ir junto" %[rodada, ("de " + adversario) if adversario != "" else "do adversário"], 5.0)

## Um passo do Cerco (sempre igual nos dois aparelhos).
func _passo_cerco(dt: float) -> void:
	if intervalo > 0.0:
		intervalo -= dt
		if intervalo <= 0.0:
			rodada = 2
			defensor = _atacante()
			_preparar_rodada()
			_banner_rodada()
			Sons.tocar("Jogo/som/lutem", 0.7)
		return
	_passo_sol(dt)
	if not online():
		if preparo <= 0.0 and bot_nivel > 1:
			energias[outro] += dt * P.BOT.energia_por_segundo_por_nivel * (bot_nivel - 1)
		var forca := _forca_bot()
		bot_t -= dt
		if bot_t <= 0.0:
			bot_t = rng.randf_range(lerpf(P.BOT.pensa_facil[0], P.BOT.pensa_dificil[0], forca), lerpf(P.BOT.pensa_facil[1], P.BOT.pensa_dificil[1], forca))
			_jogada_do_bot()
			if bot_horda > 0:
				bot_t = 0.3
	if preparo > 0.0:
		preparo -= dt
		if preparo <= 0.0:
			for lista in [herois, monstros]:
				for l in lista:
					for u in l:
						u.fixo = false
			mostrar_banner("LUTEM!\n%s" % ("Segure o castelo!" if defensor == lado_local else "Derrube o castelo inimigo!"), 2.2)
			Sons.tocar("Jogo/som/lutem", 0.9)
		return
	tempo += dt                                         # a rodada só acaba quando o castelo CAIR (sem relógio de fim)
	_passo_mare(dt)
	if vidas[defensor] <= 0.0:
		_fim_rodada(tempo, 0.0)                         # quanto o castelo aguentou

func _fim_rodada(aguentou: float, vida: float) -> void:
	cerco_res[defensor] = {"tempo": aguentou, "vida": vida, "passos": roundi(aguentou * 60.0), "gasto": gasto[_atacante()]}
	if rodada == 1:
		var eu := defensor == lado_local
		var quem := "Você" if eu else (adversario if adversario != "" else "O adversário")
		mostrar_banner("FIM DA RODADA 1\n%s aguentou %s%s\nAgora os papéis trocam!" % [quem, _mmss(aguentou),
			(" com o castelo em %d" % ceili(vida)) if vida > 0.0 else ""], float(P.MODO_CERCO.intervalo))
		_limpar_campo()
		intervalo = float(P.MODO_CERCO.intervalo)
		Sons.tocar("Jogo/som/proximo_nivel", 0.7)
		return
	var h: Dictionary = cerco_res.get("heroes", {"tempo": 0.0, "vida": 0.0})
	var m: Dictionary = cerco_res.get("monsters", {"tempo": 0.0, "vida": 0.0})
	# vence quem DERRUBOU o castelo do outro mais rápido (= o castelo dele aguentou mais tempo). SEM EMPATE:
	# mesmo passo -> quem gastou menos energia atacando; nem isso -> quem atacou primeiro (às cegas, sem saber a marca).
	var v := str(P.MODO_CERCO.primeiro_defende)
	v = "monsters" if v == "heroes" else "heroes"
	if int(h.get("passos", 0)) != int(m.get("passos", 0)):
		v = "heroes" if int(h.get("passos", 0)) > int(m.get("passos", 0)) else "monsters"
	elif absf(float(h.get("gasto", 0.0)) - float(m.get("gasto", 0.0))) > 0.001:
		v = "heroes" if float(h.get("gasto", 0.0)) > float(m.get("gasto", 0.0)) else "monsters"   # (h.gasto = o que os Monsters gastaram atacando)
	_encerrar(v)

func _limpar_campo() -> void:
	for lista in [herois, monstros]:
		for l in lista:
			for u in l:
				u.queue_free()
			l.clear()
	for pr in projeteis:
		pr.ativo = false
	ondas.clear(); orbes.clear(); voos.clear(); fendas.clear()
	carta_sel = -1
	if espiando:
		espiar_t = 0.0
		_trocar_vista(false)

static func _mmss(seg: float) -> String:
	var t := maxi(0, roundi(seg))
	return "%d:%02d" % [t / 60, t % 60]

## Texto do fim: quanto cada um aguentou defendendo.
func _resumo_cerco() -> String:
	var meu: Dictionary = cerco_res.get(lado_local, {"tempo": 0.0, "vida": 0.0})
	var dele: Dictionary = cerco_res.get(outro, {"tempo": 0.0, "vida": 0.0})
	var nome := adversario if adversario != "" else "O adversário"
	var f := func(r: Dictionary) -> String:
		return _mmss(float(r.tempo)) + ((" (castelo %d)" % ceili(float(r.vida))) if float(r.vida) > 0.0 else " (castelo caiu)")
	return "Você defendeu: %s\n%s defendeu: %s" % [f.call(meu), nome, f.call(dele)]

## BOT defendendo no Cerco: gerador lá atrás, segura a linha em perigo e monta a defesa nas linhas vazias.
func _jogada_bot_defesa(opcoes: Array, est: Dictionary, esperto: bool) -> void:
	var defesa_tipos := _PERTO + _LONGE
	var perigos := _perigo_linhas()
	perigos.sort_custom(func(a, b): return a.falta > b.falta)
	if perigos[0].falta > 0.0 and rng.randf() < minf(0.98, _mistura(P.BOT.reage) * float(est.reage) + 0.2):
		var esc: PersonagemDados = _melhor(opcoes, _PERTO if perigos[0].perto > 0.55 else _LONGE) if esperto else null
		if esc == null:
			esc = _melhor(opcoes, defesa_tipos)
		if esc and _colocar_bot(esc, perigos[0].linha, true):
			return
	# sem perigo agora: reforça a linha com menos defesa (atirador atrás, quem segura na frente)
	var meus := _tropas_bot()
	var menor := INF
	var linha := 0
	for r in C.G.rows:
		var d := rng.randf() * 30.0
		for u in meus[r]:
			if not u.morto and u.p.comportamento != "gerador":
				d += float(u.p.custo)
		if d < menor:
			menor = d
			linha = r
	if rng.randf() < 0.35 and energias[outro] < 200.0:
		return                                          # guarda um pouco de energia para emergência
	var tipos := _LONGE if rng.randf() < 0.6 else _PERTO
	var e := _melhor(opcoes, tipos)
	if e == null:
		e = _melhor(opcoes, defesa_tipos)
	if e:
		_colocar_bot(e, linha, true)

# =================================================================== REPLAY (36_replays.sql)
## Fim da partida online: manda a "receita" para o servidor (o primeiro dos dois aparelhos que mandar fica).
func _guardar_replay(v: String) -> void:
	if rede.is_empty() or str(rede.get("sala", "")) == "":
		return
	var dados := {"v": 1, "semente": semente, "modo": modo, "niveis": rede.get("niveis", {}), "nomes": rede.get("nomes", {}),
		"amistoso": rede.get("amistoso", false), "passos": passo_n, "vencedor": v, "wo": rede.get("wo", false),
		"foto": foto_da_partida(), "acoes": replay_acoes}
	ultimo_replay = dados
	Conta.chamar("guardar_replay", {"p_sala": rede.sala, "p_dados": dados})   # (sem esperar)

## Abriu um replay: a partida roda como a online (mesma semente, mesmas jogadas), só que ninguém joga.
func _preparar_replay(d: Dictionary) -> void:
	replay = d
	assistindo = true
	lado_local = str(d.get("lado_ver", "heroes")) if str(d.get("lado_ver", "")) in ["heroes", "monsters"] else "heroes"
	var o := "monsters" if lado_local == "heroes" else "heroes"
	semente = int(d.get("semente", 0))
	modo = "cerco" if str(d.get("modo", "normal")) == "cerco" else "normal"
	var nomes: Dictionary = d.get("nomes", {}) if d.get("nomes") is Dictionary else {}
	adversario = str(nomes.get(o, "")) if str(nomes.get(o, "")) != "" else "Adversário"
	var nv: Dictionary = d.get("niveis", {}) if d.get("niveis") is Dictionary else {}
	rede = {"sala": "", "lado_outro": o, "recebidos": {}, "enviados": {}, "minhas": [], "esperando_desde": 0, "pediu_em": 0,
		"saiu": false, "wo": false, "finalizando": false, "conectou": true, "inicio": Time.get_ticks_msec(), "espiar_pedido": false,
		"niveis": {"heroes": nv.get("heroes", {}), "monsters": nv.get("monsters", {})}, "nomes": nomes,
		"amistoso": d.get("amistoso", false) == true, "replay": true}

func _iniciar_replay() -> void:
	escolhendo = false
	_recomecar_replay()
	barra_replay = Control.new()
	barra_replay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barra_replay.size = Vector2(C.W, C.H)
	barra_replay.draw.connect(_desenhar_barra_replay)
	ui.add_child(barra_replay)
	var nomes: Dictionary = rede.get("nomes", {})
	mostrar_banner("▶ REPLAY\n%s (Heroes) x %s (Monsters)\nArraste a barra para ir a qualquer momento · toque na tela: 1x / 2x / 4x" % [
		str(nomes.get("heroes", "Heroes")), str(nomes.get("monsters", "Monsters"))], 4.0)

## Volta a partida para o começo (com todas as jogadas guardadas de novo).
func _recomecar_replay() -> void:
	comecar()
	for a in replay.get("acoes", []):
		if a is Dictionary:
			var b: Dictionary = a.duplicate()
			b.passo = int(b.get("passo", 0))
			b.seq = int(b.get("seq", 0))
			b.lado = str(b.get("lado", ""))
			fila_acoes.append(b)

func _total_replay() -> int:
	return maxi(1, int(replay.get("passos", 1)))

## BARRA: ir para o passo "alvo". Para trás = recomeça do zero e corre até lá (a partida é sempre igual);
## para frente = corre daqui até lá. Correndo, o som fica mudo e a tela mostra "Indo para...".
func _ir_para_replay(alvo: int) -> void:
	alvo = clampi(alvo, 0, _total_replay())
	if alvo >= _total_replay():
		alvo = _total_replay() + 1                     # (o fim: o castelo cai DENTRO do último passo)
	if alvo < passo_n or fim:
		_recomecar_replay()
	replay_alvo = alvo
	AudioServer.set_bus_mute(0, true)

func _correr_replay() -> void:
	var n := 0
	while passo_n < replay_alvo and not fim and n < REPLAY_PASSOS_POR_QUADRO:
		_passo_sim(PASSO)
		n += 1
	if passo_n >= replay_alvo or fim:
		replay_alvo = -1
		acumulado = 0.0
		AudioServer.set_bus_mute(0, false)
		textos.clear()
		explosoes.clear()

func _ret_barra_replay() -> Rect2:
	return Rect2(270, C.H - 40, C.W - 410, 12)

func _passo_da_barra(x: float) -> int:
	var r := _ret_barra_replay()
	return roundi(clampf((x - r.position.x) / r.size.x, 0.0, 1.0) * _total_replay())

func _desenhar_barra_replay() -> void:
	var b := barra_replay
	var r := _ret_barra_replay()
	var total := _total_replay()
	var agora := replay_arrasto if replay_arrasto >= 0 else (replay_alvo if replay_alvo >= 0 else passo_n)
	var k := clampf(float(agora) / float(total), 0.0, 1.0)
	var fundo_r := Rect2(138, C.H - 70, C.W - 144, 66)            # (cobre a faixa de baixo do HUD, que no replay não serve)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.1, 0.96)
	sb.border_color = Color("2fd15a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(20)
	b.draw_style_box(sb, fundo_r)
	var trilho := StyleBoxFlat.new()
	trilho.bg_color = Color(1, 1, 1, 0.18)
	trilho.set_corner_radius_all(6)
	b.draw_style_box(trilho, r)
	if k > 0.0:
		var cheio := StyleBoxFlat.new()
		cheio.bg_color = Color("2fd15a")
		cheio.set_corner_radius_all(6)
		b.draw_style_box(cheio, Rect2(r.position, Vector2(r.size.x * k, r.size.y)))
	var bola := Vector2(r.position.x + r.size.x * k, r.get_center().y)
	b.draw_circle(bola, 15 if replay_arrasto >= 0 else 12, Color("120c04"))
	b.draw_circle(bola, 12 if replay_arrasto >= 0 else 9, Color.WHITE)
	var txt_t := "%s / %s" % [_mmss(agora / 60.0), _mmss(total / 60.0)]
	b.draw_string_outline(f_titulo, Vector2(fundo_r.position.x + 18, r.position.y + 13), txt_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color("120c04"))
	b.draw_string(f_titulo, Vector2(fundo_r.position.x + 18, r.position.y + 13), txt_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	var txt_v := "⏩ indo..." if replay_alvo >= 0 else "%dx" % replay_vel
	b.draw_string_outline(f_titulo, Vector2(r.end.x + 22, r.position.y + 13), txt_v, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color("120c04"))
	b.draw_string(f_titulo, Vector2(r.end.x + 22, r.position.y + 13), txt_v, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("ffd34d"))

## Toques no replay: arrastar na barra (embaixo) = ir para aquele momento; tocar no resto = velocidade.
func _toque_replay(ev: InputEvent) -> void:
	if barra_replay == null:
		return
	var apertou: bool = (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed)
	var soltou: bool = (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed) or (ev is InputEventScreenTouch and not ev.pressed)
	var moveu: bool = ev is InputEventMouseMotion or ev is InputEventScreenDrag
	if ev is InputEventMouseButton and ev.device == InputEvent.DEVICE_ID_EMULATION:
		return                                       # (o toque do celular já chega como ScreenTouch)
	if not (apertou or soltou or moveu):
		return
	var pos: Vector2 = barra_replay.make_input_local(ev).position
	var area := _ret_barra_replay().grow_individual(130, 34, 130, 40)
	if apertou:
		if area.has_point(pos):
			replay_arrasto = _passo_da_barra(pos.x)
		elif not (painel and painel.visible) and replay_alvo < 0:
			replay_vel = 2 if replay_vel == 1 else (4 if replay_vel == 2 else 1)
			mostrar_banner("REPLAY · velocidade %dx" % replay_vel, 1.2)
	elif moveu and replay_arrasto >= 0:
		replay_arrasto = _passo_da_barra(pos.x)
	elif soltou and replay_arrasto >= 0:
		var alvo := _passo_da_barra(pos.x)
		replay_arrasto = -1
		_ir_para_replay(alvo)

func _passo_replay(dt: float) -> void:
	if barra_replay:
		barra_replay.queue_redraw()
	if replay_arrasto >= 0:
		return                                       # (arrastando a barra: a partida espera)
	if replay_alvo >= 0:
		_correr_replay()
		return
	acumulado = minf(acumulado + dt * replay_vel, 0.25 * replay_vel)
	var n := 0
	while acumulado >= PASSO and n < 8 * replay_vel and not fim:
		_passo_sim(PASSO)
		acumulado -= PASSO
		n += 1
		if not fim and passo_n >= int(replay.get("passos", 0)) + 30:   # (W.O.: a partida parou antes de um castelo cair)
			_fim_replay(str(replay.get("vencedor", "")))

func _fim_replay(v: String) -> void:
	if fim and painel.visible:
		return
	if replay_alvo >= 0:                               # (arrastou a barra até o fim: terminou de correr)
		replay_alvo = -1
		AudioServer.set_bus_mute(0, false)
	fim = true
	vencedor = v
	replay_foto = foto_da_partida()
	if replay_foto != str(replay.get("foto", replay_foto)) and replay.get("wo", false) != true:
		Conta.registrar("replay_diferente", {"passos": passo_n, "esperado": replay.get("passos", 0)})   # (painel: para conferir)
	var nomes: Dictionary = rede.get("nomes", {})
	var quem := str(nomes.get(v, "")) if v in ["heroes", "monsters"] else ""
	painel_titulo = "FIM DO REPLAY"
	painel_texto = ("%s venceu de %s!" % [quem, "Heroes" if v == "heroes" else "Monsters"]) if quem != "" else "Fim da partida."
	if replay.get("wo", false) == true:
		painel_texto += "\n(o outro saiu da partida)"
	_abrir_painel([["Ver de novo", Color("ffc43a"), _replay_de_novo], ["Voltar", Color("4a5fae"), _ir_menu]])

func _replay_de_novo() -> void:
	Perfil.pvp_replay = replay
	get_tree().paused = false
	get_tree().change_scene_to_file("res://cenas/pvp.tscn")

# =================================================================== ONLINE (lockstep)
func online() -> bool:
	return not rede.is_empty()

## A busca do menu achou uma sala no servidor: {id, semente, heroes, monsters, niveis_*, nome_*, lado, token}.
func _preparar_online(sala: Dictionary) -> void:
	lado_local = str(sala.get("lado", lado_local))
	var o := "monsters" if lado_local == "heroes" else "heroes"
	semente = int(sala.get("semente", 0))
	adversario = str(sala.get("nome_" + o, "")) if sala.get("nome_" + o) != null else ""
	if adversario == "":
		adversario = "Adversário"
	var nh = sala.get("niveis_heroes", {})
	var nm = sala.get("niveis_monsters", {})
	rede = {"sala": str(sala.id), "lado_outro": o, "recebidos": {}, "enviados": {}, "minhas": [],
		"esperando_desde": 0, "pediu_em": 0, "saiu": false, "wo": false, "finalizando": false,
		"conectou": false, "inicio": Time.get_ticks_msec(), "espiar_pedido": false,
		"niveis": {"heroes": nh if nh is Dictionary else {}, "monsters": nm if nm is Dictionary else {}}}
	rede["nomes"] = {"heroes": str(sala.get("nome_heroes", "")) if sala.get("nome_heroes") != null else "",
		"monsters": str(sala.get("nome_monsters", "")) if sala.get("nome_monsters") != null else ""}
	rede["amistoso"] = sala.get("amistoso", false) == true      # DUELO entre amigos: não vale troféu
	modo = "cerco" if str(sala.get("modo", "normal")) == "cerco" else "normal"   # (19_cerco.sql)
	rede["aposta_moedas"] = int(sala.get("aposta_moedas", 0)) if sala.get("aposta_moedas") != null else 0
	rede["aposta_trofeus"] = int(sala.get("aposta_trofeus", 0)) if sala.get("aposta_trofeus") != null else 0
	# SÉRIE (28_serie_pvp.sql): partida 1 num lado, partida 2 no outro (e a 3ª de desempate). Troféu no fim da série.
	rede["em_serie"] = sala.get("em_serie", false) == true
	rede["jogo"] = int(sala.get("jogo", 1)) if sala.get("jogo") != null else 1
	rede["meus_pontos"] = int(sala.get("pontos_" + lado_local, 0)) if sala.get("pontos_" + lado_local) != null else 0
	rede["pontos_dele"] = int(sala.get("pontos_" + o, 0)) if sala.get("pontos_" + o) != null else 0
	canal = RedePvp.new()
	add_child(canal)
	canal.chegou.connect(_mensagem_rede)
	canal.conectou.connect(func(): rede.conectou = true)
	canal.abrir(Conta.endereco(), Conta.CHAVE, rede.sala, str(sala.get("token", "")))
	for t in ONLINE.atraso - 1:                      # os primeiros turnos não têm ações
		_enviar_turno(t)

func _turno_de(passo: int) -> int:
	return passo / ONLINE.turno

## Tudo o que o jogador faz online vira uma AÇÃO marcada para um passo lá na frente (vai também para o adversário).
func agendar(acao: Dictionary) -> void:
	if fim:
		return
	seq_acao += 1
	acao.seq = seq_acao
	acao.lado = lado_local
	acao.passo = passo_n + ONLINE.turno * ONLINE.atraso
	rede.minhas.append(acao)
	fila_acoes.append(acao)

## Energia que já está prometida em ações minhas que ainda não aconteceram.
func _energia_reservada() -> float:
	var r := 0.0
	for a in fila_acoes:
		if a.lado != lado_local:
			continue
		if a.tipo == "colocar":
			var p: PersonagemDados = Catalogo.get_p(a.id)
			if p:
				r += p.custo
		elif a.tipo == "espiar":
			r += C.ESPIAR_CUSTO
	return r

## Segurança: cada lado só coloca as tropas dele.
func _acao_valida(a: Dictionary, lado: String) -> bool:
	match str(a.get("tipo", "")):
		"colocar":
			return str(a.get("id", "")) in (P.CARTAS_HEROES if lado == "heroes" else P.CARTAS_MONSTERS)
		"orbe", "espiar":
			return true
		"cmd":                                         # menu do personagem: só os comandos que existem
			return str(a.get("c", "")) in ["azul", "vermelho", "remover", "parar", "andar", "voltar"]
	return false

func _mensagem_rede(m: Dictionary) -> void:
	if rede.is_empty():
		return
	var tipo := str(m.get("tipo", ""))
	if tipo == "turno":
		var lista: Array = [[m.get("t", -1), m.get("acoes", [])]]
		var ant = m.get("ant", [])
		if ant is Array:
			lista.append_array(ant)
		for par in lista:
			if not (par is Array) or par.size() < 2 or not (par[1] is Array):
				continue
			var t := int(par[0])
			if rede.recebidos.has(t):
				continue
			rede.recebidos[t] = true
			for a in par[1]:
				if a is Dictionary and _acao_valida(a, rede.lado_outro):
					var b: Dictionary = a.duplicate()
					b.lado = rede.lado_outro
					b.passo = int(b.get("passo", 0))
					b.seq = int(b.get("seq", 0))
					if _turno_de(b.passo) == t:      # a ação tem de ser do turno que veio
						fila_acoes.append(b)
	elif tipo == "pedir":                              # o outro perdeu algum turno: mando de novo
		var desde := int(m.get("t", 0))
		for t in rede.enviados:
			if t >= desde:
				canal.enviar({"tipo": "turno", "t": t, "acoes": rede.enviados[t]})
	elif tipo == "sair":
		rede.saiu = true

func _enviar_turno(t: int) -> void:
	if rede.enviados.has(t):
		return
	var acoes: Array = []
	var resto: Array = []
	for a in rede.minhas:
		if _turno_de(a.passo) == t:
			var c: Dictionary = a.duplicate()
			c.erase("lado")
			acoes.append(c)
		else:
			resto.append(a)
	rede.minhas = resto
	rede.enviados[t] = acoes
	var ant: Array = []
	for k in range(1, ONLINE.repete + 1):
		if rede.enviados.has(t - k):
			ant.append([t - k, rede.enviados[t - k]])
	canal.enviar({"tipo": "turno", "t": t, "acoes": acoes, "ant": ant})

## Antes de cada passo: no começo do turno manda o meu turno lá da frente e confere se o do adversário já chegou.
func _pode_avancar() -> bool:
	var t := _turno_de(passo_n)
	if passo_n % ONLINE.turno == 0:
		_enviar_turno(t + ONLINE.atraso - 1)
	if rede.recebidos.has(t):
		rede.esperando_desde = 0
		return true
	var agora := Time.get_ticks_msec()
	if rede.esperando_desde == 0:
		rede.esperando_desde = agora
	var esperou: float = (agora - rede.esperando_desde) / 1000.0
	if esperou > ONLINE.pede_de_novo_em and agora - rede.pediu_em > 1000:
		rede.pediu_em = agora
		canal.enviar({"tipo": "pedir", "t": t})
	if not rede.conectou:
		if (agora - rede.inicio) / 1000.0 > ONLINE.conectar_em:
			if rede.get("em_serie", false) and int(rede.get("jogo", 1)) > 1:
				_encerrar_online(lado_local, true)       # SÉRIE: o outro não voltou para a próxima partida = W.O.
			else:
				_sem_conexao()
	elif rede.saiu or esperou > ONLINE.desiste_em:
		_encerrar_online(lado_local, true)           # o outro sumiu: vitória por W.O.
	return false

func esperando_adversario() -> bool:
	return online() and not fim and rede.esperando_desde > 0 and Time.get_ticks_msec() - rede.esperando_desde > 600

func _passo_online(dt: float) -> void:
	acumulado = minf(acumulado + dt, 0.25)
	var n := 0
	while acumulado >= PASSO and n < 8 and not fim:
		if not _pode_avancar():
			acumulado = minf(acumulado, PASSO * 2.0)
			break
		_passo_sim(PASSO)
		acumulado -= PASSO
		n += 1

func _aplicar_acoes_do_passo() -> void:
	if fila_acoes.is_empty():
		return
	var agora: Array = []
	var resto: Array = []
	for a in fila_acoes:
		if int(a.passo) <= passo_n:
			agora.append(a)
		else:
			resto.append(a)
	if agora.is_empty():
		return
	fila_acoes = resto
	agora.sort_custom(func(a, b):
		if a.passo != b.passo:
			return a.passo < b.passo
		if a.lado != b.lado:
			return a.lado == "heroes"
		return a.seq < b.seq)
	for a in agora:
		if online() and replay.is_empty():            # REPLAY: guarda tudo o que aconteceu (dos dois lados)
			replay_acoes.append(a.duplicate())
		_aplicar_acao(a)

func _aplicar_acao(a: Dictionary) -> void:
	var lado: String = a.lado
	match str(a.tipo):
		"colocar":
			colocar(lado, str(a.id), int(a.r), int(a.c), false, bool(a.get("inv", false)))
		"orbe":
			var id := int(a.id)
			for i in orbes.size():
				if int(orbes[i].id) == id and orbes[i].lado == lado:
					_coletar_sim(i)
					break
		"cmd":                                      # COMANDO do menu do personagem (os dois aparelhos aplicam no mesmo passo)
			var u := _por_uid(int(a.uid))
			if u and u.lado == lado:
				_comando_sim(u, str(a.c))
		"espiar":
			if lado == lado_local:
				rede.espiar_pedido = false
			if energias[lado] >= custo_espiar():
				energias[lado] -= custo_espiar()
				if lado == lado_local:
					espiar_t = C.ESPIAR_DURACAO
					_trocar_vista(true)

## "Foto" do fim da partida: os dois aparelhos têm de ter a mesma (o servidor compara).
func foto_da_partida() -> String:
	var u := []
	for lista in [herois, monstros]:
		for l in lista:
			for x in l:
				if not x.morto:
					u.append([x.p.id, x.linha, roundi(x.position.x), roundi(x.vida)])
	var d := [passo_n, snappedf(vidas.heroes, 0.01), snappedf(vidas.monsters, 0.01), roundi(energias.heroes), roundi(energias.monsters),
		abatidas, mortos_h, vencedor, u]
	return JSON.stringify(d).md5_text().substr(0, 12)

func _sem_conexao() -> void:
	if fim:
		return
	fim = true
	carta_sel = -1
	painel_titulo = "SEM CONEXÃO"
	painel_texto = "Não deu para entrar na sala da partida.\nConfira a internet e tente de novo."
	if canal:
		canal.fechar()
	_abrir_painel([["Menu", Color("4a5fae"), _ir_menu]])

## Fim da partida online: mostra o resultado e grava no servidor (o primeiro aparelho que chega grava para os dois).
func _encerrar_online(v: String, wo := false) -> void:
	if rede.finalizando:
		return
	fim = true
	vencedor = v
	carta_sel = -1
	rede.wo = wo
	rede.finalizando = true
	_guardar_replay(v)
	var venceu := v == lado_local
	var empate := v == ""
	_registrar_cartas(venceu)
	painel_titulo = "VITÓRIA!" if venceu else ("EMPATE" if empate else "DERROTA")
	painel_texto = ("%s saiu da partida: vitória por W.O.!\n" % adversario) if wo and venceu else ""
	if modo == "cerco":
		painel_texto += _resumo_cerco() + "\nGravando o resultado..."
	else:
		painel_texto += ("Você derrubou o castelo inimigo!" if venceu else ("Seu castelo caiu." if not empate else "Os dois castelos caíram juntos!")) + "\nGravando o resultado..."
	_abrir_painel([["Menu", Color("4a5fae"), _ir_menu]])
	if venceu:
		Sons.tocar("Jogo/som/proximo_nivel", 0.9)
	elif not empate:
		Sons.tocar("Castelo/som/caiu", 1.0)
	canal.enviar({"tipo": "sair"})
	var sala = null
	for tentativa in 3:
		var r: Dictionary = await Conta.chamar("finalizar_pvp", {"p_sala": rede.sala, "p_vencedor": v if v != "" else "empate",
			"p_resumo": "wo" if wo else foto_da_partida()})
		if r.ok and r.dados is Dictionary:
			sala = r.dados
			break
		await get_tree().create_timer(1.5).timeout
	if not is_inside_tree():
		return
	canal.fechar()
	var linha := "(Sem internet para gravar o resultado.)"
	if sala != null and sala.get("finalizada", false):
		var sv := str(sala.get("vencedor", ""))
		linha = RESULTADO_ONLINE.vitoria if sv == lado_local else (RESULTADO_ONLINE.empate if sv == "empate" else RESULTADO_ONLINE.derrota)
		if rede.get("amistoso", false):
			var am: int = rede.get("aposta_moedas", 0)
			var at: int = rede.get("aposta_trofeus", 0)
			var oq := _texto_aposta(am, at)
			if oq == "":
				linha = "Duelo amistoso (sem aposta)."
			elif sv == "empate":
				linha = "Empate: ninguém perdeu nada."
			elif sv == lado_local:
				linha = "Você ganhou %s do seu amigo!" % oq
			else:
				linha = "Você perdeu %s para o seu amigo." % oq
		if rede.get("em_serie", false):
			linha = "Partida %d da série gravada. Vendo o placar..." % int(rede.get("jogo", 1))
		if sv != (v if v != "" else "empate"):
			linha += "\n(O servidor gravou o resultado do outro aparelho.)"
	painel_texto = painel_texto.replace("Gravando o resultado...", linha)
	painel.queue_redraw()
	Conta.no_servidor("meu_perfil")                     # troféus e moedas novos
	if sala != null and sala.get("finalizada", false):
		if rede.get("em_serie", false) and sala.get("serie") != null:
			await _seguir_serie(sala, venceu, empate)
		else:
			await _mostrar_fim_online(sala)

## SÉRIE: a partida acabou. Se a série continua, mostra o placar e entra sozinho na próxima (lados trocados /
## desempate); se acabou, mostra o fim com os troféus da série.
func _seguir_serie(sala: Dictionary, venceu: bool, empate: bool) -> void:
	var info: Dictionary = {}
	for tentativa in 10:
		var r: Dictionary = await Conta.chamar("ver_serie", {"p_serie": str(sala.serie)})
		if not is_inside_tree():
			return
		if r.ok and r.dados is Dictionary:
			info = r.dados
			if str(info.get("status", "")) == "fim" or info.get("proxima") is Dictionary:
				break
		await get_tree().create_timer(1.0).timeout
	if info.is_empty():
		await _mostrar_fim_online(sala)
		return
	rede["meus_pontos"] = int(info.get("meus_pontos", 0))
	rede["pontos_dele"] = int(info.get("pontos_dele", 0))
	if str(info.get("status", "")) == "fim":
		rede["serie_fim"] = info
		Conta.no_servidor("meu_perfil")                 # (os troféus saíram agora)
		await _mostrar_fim_online(sala)
		return
	if not (info.get("proxima") is Dictionary):
		await _mostrar_fim_online(sala)
		return
	var tela = preload("res://scripts/pvp/serie_intervalo.gd").new()
	tela.f_titulo = f_titulo
	tela.f_texto = f_texto
	tela.venci_partida = venceu
	tela.empate_partida = empate
	tela.jogo_que_acabou = int(rede.get("jogo", 1))
	tela.meus_pontos = rede.meus_pontos
	tela.pontos_dele = rede.pontos_dele
	tela.nome_dele = adversario
	tela.proxima = info.proxima
	tela.ao_sair = _ir_menu
	painel.visible = false
	ui.visible = false
	camada_painel.add_child(tela)

## "Partida 1 de 2 · Você 0 x 0 Fulano · troféu para quem vencer de Heroes E de Monsters"
func _texto_serie() -> String:
	var j: int = rede.get("jogo", 1)
	var qual := "Partida %d de 2" % j if j <= 2 else "DESEMPATE (partida 3)"
	return "%s · Você %d x %d %s · Troféu: vença de Heroes E de Monsters" % [qual, rede.get("meus_pontos", 0), rede.get("pontos_dele", 0), adversario]

## FIM BONITO: os dois jogadores lado a lado (scripts/pvp/fim_online.gd + 15_fim_partida.sql).
## Se o servidor ainda não tiver o 15_fim_partida.sql, fica o painel simples.
func _mostrar_fim_online(sala: Dictionary) -> void:
	var r: Dictionary = await Conta.chamar("jogadores_da_sala", {"p_sala": rede.sala})
	if not is_inside_tree() or not r.ok or not (r.dados is Array) or (r.dados as Array).size() < 2:
		return
	var sv := str(sala.get("vencedor", ""))
	var vl := sv if sv in ["heroes", "monsters"] else ""
	var serie: Dictionary = rede.get("serie_fim", {})
	if not serie.is_empty():                            # SÉRIE: quem leva é o vencedor da série, não só desta partida
		var venci = serie.get("venci")
		vl = "" if venci == null else (lado_local if venci == true else outro)
		painel_titulo = "SÉRIE EMPATADA" if vl == "" else ("VENCEU A SÉRIE!" if vl == lado_local else "PERDEU A SÉRIE")
	var amistoso: bool = rede.get("amistoso", false)
	var am: int = rede.get("aposta_moedas", 0)
	var at: int = rede.get("aposta_trofeus", 0)
	var sem_trofeus: bool = serie.get("sem_trofeus", false) == true   # MESMA INTERNET (35_mesmo_ip.sql): não pagou nada
	var deltas := {}
	for j in r.dados:
		var lado_j := str(j.get("lado", ""))
		var dm := 0
		var dtf := 0
		if sem_trofeus:
			pass
		elif amistoso:
			if vl != "":
				dm = am if lado_j == vl else -am
				dtf = at if lado_j == vl else -at
		elif vl == "":
			dm = 25
		elif lado_j == vl:
			dm = 50
			dtf = 30
		else:
			dm = 15
			dtf = -20 if int(j.get("trofeus", 0)) > 0 else 0
		deltas[str(j.get("id", ""))] = {"moedas": dm, "trofeus": dtf}
	var f = preload("res://scripts/pvp/fim_online.gd").new()
	f.f_titulo = f_titulo
	f.f_texto = f_texto
	f.titulo = painel_titulo
	var sub := ("Duelo · " + ("valendo " + _texto_aposta(am, at) if _texto_aposta(am, at) != "" else "sem aposta")) if amistoso else "PvP online"
	if not serie.is_empty():
		sub = "Série %d x %d" % [int(serie.get("meus_pontos", 0)), int(serie.get("pontos_dele", 0))]
		if vl == lado_local:
			sub += " · você venceu de Heroes e de Monsters!" if int(serie.get("pontos_dele", 0)) == 0 else " · você venceu o desempate!"
		elif vl == "":
			sub += " · ninguém ganhou troféu"
	if rede.get("wo", false) and vl == lado_local:
		sub += " · %s saiu: vitória por W.O." % adversario
	f.subtitulo = sub
	f.vencedor_lado = vl
	f.deltas = deltas
	f.ao_menu = _ir_menu
	f.sala_id = str(rede.sala)
	painel.visible = false
	ui.visible = false                                  # (as cartas e a energia saem da frente)
	camada_painel.add_child(f)
	f.mostrar(r.dados)

## Sair no meio da partida online = derrota (o adversário ganha por W.O.).
func _desistir_online() -> void:
	if not fim and _t_partida > 5.0:
		Conta.registrar("desistiu", {"modo": _atividade(), "minuto": snappedf(_t_partida / 60.0, 0.1)})
		_t_partida = 0.0
	if not fim:
		fim = true
		rede.finalizando = true
		canal.enviar({"tipo": "sair"})
		Conta.chamar("finalizar_pvp", {"p_sala": rede.sala, "p_vencedor": outro, "p_resumo": "wo"})
	_ir_menu()

# =================================================================== FIM
func _encerrar(v: String) -> void:
	if not replay.is_empty():
		_fim_replay(v)
		return
	if online():
		_encerrar_online(v)
		return
	fim = true
	vencedor = v
	carta_sel = -1
	var venceu := v == lado_local
	var empate := v == ""
	var minha: float = vidas[lado_local]
	var deles: float = vidas[outro]
	if campeonato:
		_encerrar_campeonato(venceu, empate, minha, deles)
		return
	# moedas (a cada partida; os troféus da série contra o bot saem no fim da série)
	var tab: Dictionary = P.MODO_CERCO.moedas if modo == "cerco" else P.MOEDAS
	var base: int = tab.vitoria if venceu else (tab.empate if empate else tab.derrota)
	var g: Dictionary = Perfil.ganhar_moedas(base, lado_local)    # +50% no lado em alta; +150 se jogou os dois lados hoje
	var ganho: int = g.ganho + g.duplo
	if serie_bot:
		_fim_partida_serie_bot(venceu, ganho, minha, deles)
		return
	# BOT_DIFICULDADE: vitória = bot mais difícil na próxima; derrota = mais fácil
	var nivel_antes := bot_nivel
	if not empate and modo != "cerco":                  # (o Cerco não mexe no nível do bot)
		bot_nivel = clampi(bot_nivel + (1 if venceu else -P.BOT.derrota_diminui), 1, P.BOT.maximo)
	Perfil.bot_nivel = bot_nivel
	Perfil.salvar()
	_registrar_cartas(venceu)
	Conta.registrar("pvp_bot", {"lado": lado_local, "venceu": venceu, "empate": empate, "bot_nivel": nivel_antes,
		"castelo": ceili(minha), "castelo_inimigo": ceili(deles), "modo": modo})
	painel_titulo = "VITÓRIA!" if venceu else ("EMPATE" if empate else "DERROTA")
	painel_texto = "%s\n+%d moedas" % ["Você derrubou o castelo inimigo!" if venceu else ("Seu castelo caiu." if not empate else "Os dois castelos caíram juntos!"), ganho]
	if modo == "cerco":
		painel_titulo = ("CERCO: " + painel_titulo) if not empate else "CERCO: EMPATE"
		painel_texto = "%s\n+%d moedas" % [_resumo_cerco(), ganho]
	_abrir_painel([["Jogar de novo", Color("ffc43a"), _jogar_de_novo], ["Menu", Color("4a5fae"), _ir_menu]])
	if venceu:
		Sons.tocar("Jogo/som/proximo_nivel", 0.9)
	elif not empate:
		Sons.tocar("Castelo/som/caiu", 1.0)

const TXT_TROFEU_BOT := "Somando os troféus..."

# =================================================================== SÉRIE CONTRA O BOT
## Igual à série online (28_serie_pvp.sql): partida 1 no seu lado, partida 2 com os lados TROCADOS e, se ficar
## 1 x 1, a partida 3 de desempate com o lado sorteado. O bot é o MESMO a série toda (nível e nome).
## Fim da série: troféus para quem venceu (pela dificuldade do bot) e a próxima dificuldade:
## venceu = sobe uma (Fácil -> Médio -> Difícil -> HardCore); perdeu = volta uma.
func _iniciar_serie_bot() -> void:
	serie_bot = true
	var s: Dictionary = Perfil.serie_bot
	if s.get("continua", false):                         # partida 2 ou 3 da mesma série
		s["continua"] = false
		bot_nivel = int(s.nivel)
		adversario = str(s.adversario)
		return
	Perfil.serie_bot = {"jogo": 1, "meus": 0, "dele": 0, "nivel": bot_nivel, "lado_original": lado_local,
		"adversario": adversario, "continua": false}

func _texto_serie_bot() -> String:
	var s: Dictionary = Perfil.serie_bot
	var j := int(s.get("jogo", 1))
	var qual := "Partida %d de 2" % j if j <= 2 else "DESEMPATE (partida 3)"
	var nome := adversario if adversario != "" else "Adversário"
	return "%s · Você %d x %d %s · Vença de Heroes E de Monsters" % [qual, int(s.get("meus", 0)), int(s.get("dele", 0)), nome]

func _fim_partida_serie_bot(venceu: bool, ganho: int, minha: float, deles: float) -> void:
	var s: Dictionary = Perfil.serie_bot
	var jogo := int(s.jogo)
	if venceu:
		s["meus"] = int(s.meus) + 1
	else:
		s["dele"] = int(s.dele) + 1
	_registrar_cartas(venceu)
	Conta.registrar("pvp_bot", {"lado": lado_local, "venceu": venceu, "empate": false, "bot_nivel": bot_nivel,
		"castelo": ceili(minha), "castelo_inimigo": ceili(deles), "modo": modo, "serie_jogo": jogo})
	var acabou := jogo >= 3 or (jogo == 2 and (int(s.meus) == 2 or int(s.dele) == 2))
	if acabou:
		_fim_serie_bot(int(s.meus) > int(s.dele), ganho)
		return
	s["jogo"] = jogo + 1
	var proximo := ("monsters" if lado_local == "heroes" else "heroes") if jogo == 1 else ("heroes" if randf() < 0.5 else "monsters")
	if venceu:
		Sons.tocar("Jogo/som/proximo_nivel", 0.9)
	else:
		Sons.tocar("Castelo/som/caiu", 1.0)
	var tela = preload("res://scripts/pvp/serie_intervalo.gd").new()
	tela.f_titulo = f_titulo
	tela.f_texto = f_texto
	tela.bot = true
	tela.venci_partida = venceu
	tela.jogo_que_acabou = jogo
	tela.meus_pontos = int(s.meus)
	tela.pontos_dele = int(s.dele)
	tela.nome_dele = adversario if adversario != "" else "Adversário"
	tela.proxima = {"jogo": jogo + 1}
	tela.proximo_lado = proximo
	tela.ao_entrar = _proxima_partida_serie_bot
	tela.ao_sair = _ir_menu                              # sair no intervalo = perde a série
	painel.visible = false
	ui.visible = false
	camada_painel.add_child(tela)

## Entra na próxima partida da série (a cena recarrega com o outro lado).
func _proxima_partida_serie_bot(lado: String) -> void:
	Perfil.serie_bot["continua"] = true
	Perfil.lado = lado
	Perfil.pvp_adversario = adversario
	Perfil.pvp_modo = "normal"
	Perfil.pvp_sala = {}
	get_tree().paused = false
	get_tree().change_scene_to_file("res://cenas/pvp.tscn")

## Acabou a série: volta o seu lado, troféus (se venceu) e a dificuldade do próximo bot.
func _fim_serie_bot(venceu_serie: bool, ganho: int) -> void:
	var s: Dictionary = Perfil.serie_bot
	var nivel_antes := int(s.nivel)
	_fechar_serie_bot(venceu_serie)
	var placar := "Série %d x %d" % [int(s.meus), int(s.dele)]
	if venceu_serie:
		placar += " · você venceu de Heroes e de Monsters!" if int(s.dele) == 0 else " · você venceu o desempate!"
	else:
		placar += " · %s venceu a série" % (adversario if adversario != "" else "o adversário")
	painel_titulo = "VENCEU A SÉRIE!" if venceu_serie else "PERDEU A SÉRIE"
	painel_texto = "%s\n+%d moedas" % [placar, ganho]
	if venceu_serie:
		painel_texto += "\n" + TXT_TROFEU_BOT
		_premio_trofeus_bot(nivel_antes)
	_abrir_painel([["Jogar de novo", Color("ffc43a"), _jogar_de_novo], ["Menu", Color("4a5fae"), _ir_menu]])
	if venceu_serie:
		Sons.tocar("Jogo/som/proximo_nivel", 0.9)
	else:
		Sons.tocar("Castelo/som/caiu", 1.0)

## Fecha a série: o seu lado de antes volta e o próximo bot sobe (venceu) ou desce (perdeu) uma dificuldade.
func _fechar_serie_bot(venceu_serie: bool) -> void:
	var s: Dictionary = Perfil.serie_bot
	if s.is_empty():
		return
	bot_nivel = P.proximo_nivel_bot(int(s.nivel), venceu_serie)
	Perfil.bot_nivel = bot_nivel
	Perfil.lado = str(s.get("lado_original", Perfil.lado))
	Perfil.serie_bot = {}
	Perfil.salvar()

## Venceu o bot na Batalha: troféus pela dificuldade dele, até o limite do dia (ConfigPvp.TROFEUS_BOT).
## Com conta o servidor confere e soma (34_trofeus_bot.sql); convidado soma no aparelho.
func _premio_trofeus_bot(nivel: int) -> void:
	var ganho := 0
	var hoje := 0
	var limite := int(P.TROFEUS_BOT.dia)
	var linha := ""
	if Perfil.com_conta() and Conta.logado():
		var r: Dictionary = await Conta.chamar("trofeus_contra_bot", {"p_nivel": nivel})
		if not is_inside_tree():
			return
		if r.ok and r.dados is Dictionary:
			Perfil.de_servidor(r.dados)
			Conta.mudou.emit()
			ganho = int(r.dados.get("ganho_bot", 0))
			hoje = int(r.dados.get("hoje_bot", 0))
			limite = int(r.dados.get("limite_bot", limite))
		else:
			linha = "(Sem internet: os troféus não foram somados.)"
	else:
		var g: Array = Perfil.ganhar_trofeus_bot(P.trofeus_bot(nivel), limite)
		ganho = g[0]
		hoje = g[1]
	if linha == "":
		if ganho > 0:
			linha = "+%d troféus" % ganho
		elif hoje >= limite:
			linha = "Você já ganhou o máximo de troféus de hoje. Volte amanhã!"
	painel_texto = painel_texto.replace("\n" + TXT_TROFEU_BOT, ("\n" + linha) if linha != "" else "")
	painel.queue_redraw()

## Fim de uma luta do CAMPEONATO: vence quem derrubou o castelo (os dois caindo juntos, coisa rara, conta como derrota).
## Não mexe no nível do bot do PvP normal. Prêmio em moedas por fase vencida.
func _encerrar_campeonato(venceu: bool, empate: bool, minha: float, deles: float) -> void:
	if empate:
		venceu = minha > deles
	var fase_antes := Campeonato.fase
	var ganho := Campeonato.registrar(venceu)
	if ganho > 0 and not Campeonato.online:          # (online o servidor paga quando a fase fecha)
		Perfil.ganhar_moedas(ganho, lado_local)
	_registrar_cartas(venceu)
	Conta.registrar("campeonato", {"lado": lado_local, "venceu": venceu, "fase": fase_antes, "bot_nivel": bot_nivel,
		"castelo": ceili(minha), "castelo_inimigo": ceili(deles)})
	painel_titulo = ("VITÓRIA!" if venceu else "ELIMINADO") if fase_antes < 3 else ("CAMPEÃO!" if venceu else "VICE-CAMPEÃO")
	painel_texto = "%s · %s" % [Campeonato.FASES[fase_antes], "Você derrubou o castelo inimigo!" if venceu else "Seu castelo caiu."]
	if ganho > 0:
		painel_texto += "\n+%d moedas" % ganho
	if venceu and fase_antes < 3:
		painel_texto += "\nPróxima fase: %s" % Campeonato.FASES[fase_antes + 1]
	_abrir_painel([["Ver campeonato", Color("ffc43a"), _ir_campeonato]])
	if venceu:
		Sons.tocar("Jogo/som/proximo_nivel", 0.9)
	else:
		Sons.tocar("Castelo/som/caiu", 1.0)

func _ir_campeonato() -> void:
	Conta.estou("campeonato")
	get_tree().paused = false
	Perfil.pvp_adversario = ""
	get_tree().change_scene_to_file("res://cenas/campeonato.tscn")

func _jogar_de_novo() -> void:
	if serie_bot:                                       # nova série (a cena recarrega no seu lado de sempre)
		Perfil.serie_bot = {}
		Perfil.pvp_adversario = ""
		Perfil.pvp_modo = "normal"
		get_tree().paused = false
		get_tree().change_scene_to_file("res://cenas/pvp.tscn")
		return
	adversario = P.nome_adversario()                   # revanche: outro "jogador"
	_fechar_painel()
	escolhendo = true                                   # escolhe as cartas de novo antes da nova partida
	selecao.abrir(cartas_todas)

func _ir_menu() -> void:
	if not replay.is_empty():                          # REPLAY: volta para a lista de replays
		AudioServer.set_bus_mute(0, false)
		get_tree().paused = false
		get_tree().change_scene_to_file("res://cenas/replays.tscn")
		return
	if not fim and _t_partida > 5.0:                    # saiu no meio da partida
		Conta.registrar("desistiu", {"modo": _atividade(), "minuto": snappedf(_t_partida / 60.0, 0.1), "rodada": rodada if modo == "cerco" else 0})
	if campeonato:                                     # saiu da luta do campeonato no meio: conta como derrota
		if not fim:
			Campeonato.desistiu()
		_ir_campeonato()
		return
	if serie_bot and not Perfil.serie_bot.is_empty():  # saiu no meio da série contra o bot = perdeu a série
		_fechar_serie_bot(false)
	Conta.estou("menu")
	get_tree().paused = false
	Perfil.pvp_adversario = ""
	get_tree().change_scene_to_file("res://cenas/intro.tscn")

func _pausar() -> void:
	if not replay.is_empty():                          # REPLAY: voltar sai
		_ir_menu()
		return
	if fim or painel.visible or escolhendo:
		return
	if online():                                       # ONLINE: a partida não para (o outro continua jogando)
		painel_titulo = "SAIR?"
		painel_texto = "A partida continua enquanto este aviso está aberto.\nSe sair agora, você perde (vitória do adversário por W.O.)."
		_abrir_painel([["Continuar", Color("ffc43a"), _continuar], ["Desistir", Color("c0463a"), _desistir_online]])
		return
	get_tree().paused = true
	painel_titulo = "PAUSA"
	painel_texto = "A batalha está parada."
	if campeonato:
		painel_texto = "A batalha está parada.\nSe desistir, você perde esta luta do campeonato."
	_abrir_painel([["Continuar", Color("ffc43a"), _continuar], ["Desistir" if campeonato else "Sair da partida", Color("c0463a") if campeonato else Color("4a5fae"), _ir_menu]])

func _continuar() -> void:
	get_tree().paused = false
	_fechar_painel()

## Botão ← MENU do HUD: abre a janela SEM parar o jogo (regra do PvP).
func mostrar_menu_pausa() -> void:
	if fim or painel.visible or escolhendo:
		return
	if online():                                       # ONLINE: a partida não para (o outro continua jogando)
		painel_titulo = "SAIR?"
		painel_texto = "A partida continua enquanto este aviso está aberto.\nSe voltar ao menu, você perde (vitória do adversário por W.O.)."
		_abrir_painel([["Continuar", Color("ffc43a"), _continuar], ["Voltar ao menu", Color("c0463a"), _desistir_online]])
		return
	painel_titulo = "SAIR DA PARTIDA?"
	painel_texto = "A partida continua enquanto este aviso está aberto.\nSe voltar ao menu, você perde."
	_abrir_painel([["Continuar", Color("ffc43a"), _continuar], ["Voltar ao menu", Color("c0463a"), _desistir_bot]])

## Sair no meio da partida contra o bot = derrota (mesma ideia do W.O. online).
func _desistir_bot() -> void:
	if not fim:
		_encerrar(outro)                               # registra a derrota (moedas, nível do bot, etc.)
	_ir_menu()

func _abrir_painel(botoes: Array) -> void:
	for b in painel_bons:
		b.queue_free()
	painel_bons.clear()
	var y := 420.0
	var x0 := C.W / 2.0 - (botoes.size() * 230.0 - 20.0) / 2.0
	for i in botoes.size():
		var d: Array = botoes[i]
		var b := Button.new()
		b.text = d[0]
		b.position = Vector2(x0 + i * 230.0, y)
		b.size = Vector2(210, 58)
		b.add_theme_font_override("font", f_titulo)
		b.add_theme_font_size_override("font_size", 24)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_outline_color", Color("24130a"))
		b.add_theme_constant_override("outline_size", 6)
		for estado_b in ["normal", "hover", "pressed", "focus"]:
			var sb := StyleBoxFlat.new()
			var cor: Color = d[1]
			sb.bg_color = cor.lightened(0.1 if estado_b == "hover" else 0.0).darkened(0.1 if estado_b == "pressed" else 0.0)
			sb.set_corner_radius_all(18)
			sb.set_border_width_all(3)
			sb.border_color = Color("141a36")
			sb.shadow_color = Color("141a36")
			sb.shadow_size = 0
			sb.shadow_offset = Vector2(0, 6)
			sb.border_width_bottom = 7
			b.add_theme_stylebox_override(estado_b, sb)
		b.pressed.connect(d[2])
		painel.add_child(b)
		painel_bons.append(b)
	painel.visible = true
	painel.queue_redraw()

func _fechar_painel() -> void:
	if painel:
		painel.visible = false

func _desenhar_painel() -> void:
	var tela := C.tela_toda(painel)                   # (celular largo: cobre as laterais também)
	painel.draw_rect(tela, Color(0.02, 0.02, 0.06, 0.6))
	var r := Rect2(C.W / 2.0 - 300, 170, 600, 330)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2c3874")
	sb.set_corner_radius_all(26)
	sb.set_border_width_all(4)
	sb.border_color = Color("f6c343") if painel_titulo == "VITÓRIA!" else Color("141a36")
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 8)
	painel.draw_style_box(sb, r)
	var cor := Color("ffd34d") if painel_titulo == "VITÓRIA!" else (Color("ff7a6a") if painel_titulo == "DERROTA" else Color("fff4d6"))
	painel.draw_string_outline(f_titulo, Vector2(r.position.x, r.position.y + 78), painel_titulo, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 58, 14, Color("24130a"))
	painel.draw_string(f_titulo, Vector2(r.position.x, r.position.y + 78), painel_titulo, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 58, cor)
	painel.draw_multiline_string_outline(f_texto, Vector2(r.position.x + 30, r.position.y + 130), painel_texto, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 60, 20, -1, 6, Color("24130a"))
	painel.draw_multiline_string(f_texto, Vector2(r.position.x + 30, r.position.y + 130), painel_texto, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 60, 20, -1, Color("eef0ff"))

# =================================================================== QUADRO (efeitos e desenho)
func _process(dt: float) -> void:
	if not replay.is_empty():
		if not fim or replay_alvo >= 0 or replay_arrasto >= 0:
			_passo_replay(dt)
		elif barra_replay:
			barra_replay.queue_redraw()
	elif online() and not fim and not escolhendo:
		_passo_online(dt)
	for tx in textos:
		tx.t += dt
		tx.pos.y -= 40.0 * dt
	textos = textos.filter(func(tx): return tx.t < 0.9)
	var i := explosoes.size() - 1
	while i >= 0:
		explosoes[i][2] += dt
		if explosoes[i][2] > 0.4:
			explosoes.remove_at(i)
		i -= 1
	var ji := impactos.size() - 1
	while ji >= 0:
		impactos[ji].t += dt
		if impactos[ji].t > 0.42:
			impactos.remove_at(ji)
		ji -= 1
	for f in faiscas:
		f.t += dt
		if f.get("raio", false):                         # faísca do raio: cai um pouco
			f.vel.y += 260.0 * dt
		f.pos += f.vel * dt
	faiscas = faiscas.filter(func(f): return f.t < 0.5)
	var ci := clarões.size() - 1
	while ci >= 0:
		clarões[ci].t += dt
		if clarões[ci].t > 0.28:
			clarões.remove_at(ci)
		ci -= 1
	# raio do cerco na parede do castelo: explosão, pedras que caem e a marca queimada
	for g in golpes_castelo:
		g.t += dt
	golpes_castelo = golpes_castelo.filter(func(g): return g.t < 0.9)
	for e in estilhacos:
		e.t += dt
		if e.pos.y < e.chao:                                  # voando: gravidade e girando
			e.vel.y += 900.0 * dt
			e.pos += e.vel * dt
			e.ang += e.giro * dt
		else:                                                  # caiu no chão: para (e some devagar)
			e.pos.y = e.chao
			e.vel = Vector2.ZERO
	estilhacos = estilhacos.filter(func(e): return e.t < 1.8)
	for m in marcas:
		m.t += dt
	marcas = marcas.filter(func(m): return m.t < 5.0)
	# eletrocutado: o corpo pisca azul / branco (tipo raio-x) — só cor, o alfa é do portal
	for ch in choques:
		if is_instance_valid(ch.alvo) and not ch.alvo.morto:
			var forca := 1.0 - clampf(float(ch.t) / CHOQUE_DUR, 0.0, 1.0) * 0.6
			var pisca := int(float(ch.t) * 28.0) % 3
			var al: float = ch.alvo.modulate.a
			ch.alvo.modulate = Color(1.7, 1.95, 2.0, al) if pisca == 0 else Color(1.0 - 0.35 * forca, 1.0 + 0.15 * forca, 1.0 + 0.6 * forca, al)
	if not get_tree().paused:
		_passo_fendas(dt)
	for lista in [herois, monstros]:                 # PORTAL_TROPA: some ao entrar, aparece ao sair
		for l in lista:
			for u in l:
				if u.fenda_aberta or u.atravessou:
					u.modulate.a = _alfa_fenda(u)
	fenda_corpo.queue_redraw()
	fenda_luz.queue_redraw()
	# energia voando até o painel
	i = voos.size() - 1
	while i >= 0:
		var v: Dictionary = voos[i]
		v.t += dt
		if v.t >= 0.45:
			energias[lado_local] += v.valor          # (online o valor é 0: a energia já entrou no passo da partida)
			voos.remove_at(i)
		i -= 1
	if espiando and not get_tree().paused and tropas_na_arena_inimiga() == 0:   # suas tropas de lá caíram: volta sozinho
		_trocar_vista(false)
		if not fim:
			mostrar_banner("Suas tropas caíram\nde volta à sua arena", 2.2)
	troca_t = maxf(0.0, troca_t - dt * 3.0)
	if banner_t > 0.0:
		banner_t -= dt
		lbl_banner.visible = banner_t > 0.0
	if mostrar_fps:
		lbl_fps.text = "%d fps" % Engine.get_frames_per_second()
	desenho.queue_redraw()
	for n_l in _chao_linhas:
		n_l.queue_redraw()
	desenho_tela.queue_redraw()

## Coisas que não podem ficar espelhadas (texto, barra de vida): desenha "de volta" no ponto p.
func _reto(p: Vector2) -> void:
	desenho.draw_set_transform(p, 0, Vector2(mundo.scale.x, 1))

func _desenhar() -> void:
	var d := desenho
	var tempo_s := Time.get_ticks_msec() / 1000.0
	# (os portais agora são PORTAL_TROPA: abrem na linha de quem passa — ver _desenhar_fendas_*)
	# barras de vida (só de quem levou golpe há pouco)
	for lista in [herois, monstros]:
		for l in lista:
			for u in l:
				if u.morto or u.mostra_barra <= 0.0:
					continue
				var alt: float = u.p.barra_y if u.p.barra_y > 0 else u.anim.ay * u.scale.y + 10.0
				_reto(u.position + Vector2(0, -alt))
				var w := 54.0
				var k: float = clampf(u.vida / u.vida_max, 0.0, 1.0)
				d.draw_rect(Rect2(Vector2(-w / 2, 0), Vector2(w, 7)), Color(0, 0, 0, 0.6))
				d.draw_rect(Rect2(Vector2(-w / 2 + 1, 1), Vector2((w - 2) * k, 5)), Color("5fd36b") if u.lado == lado_local else Color("ff5a4a"))
	d.draw_set_transform(Vector2.ZERO)
	_desenhar_marcas(d)                             # marcas queimadas na parede (embaixo de tudo)
	# projéteis
	for pr in projeteis:
		if not pr.ativo:
			continue
		match pr.tipo:
			"flecha", "flecha_inimiga":
				var alfa_f := 1.0 if not pr.fixado else clampf((1.6 - pr.t_fixado) / 0.4, 0.0, 1.0)   # cravada: some no fim
				ARENA_CAMPANHA.desenhar_flecha(d, pr.pos, signf(pr.vel), pr.lado == "monsters", alfa_f, pr.fixado, pr.t, pr.fogo)
				if pr.fixado and pr.fogo:                   # flecha de fogo cravada: continua queimando na parede
					FxExplosao.desenhar_chama(d, pr.pos + Vector2(-signf(pr.vel) * 6.0, 2.0), pr.t, 0.38 * alfa_f, 0.0)
			"energia":                                # CANHÃO ARCANO — descarga elétrica: raio torto com galhos, do cano até o inimigo
				var dir := signf(pr.vel)
				var somendo := pr.fixado              # acertou: o raio fica ligado ao alvo tremulando e se apaga
				var ka: float = clampf(pr.t_fixado / RAIO_SOME, 0.0, 1.0) if somendo else 0.0
				var alfa := 1.0 - ka * ka
				var quadro := int(pr.t / 0.034)       # o raio muda de forma ~30x por segundo (tremula)
				# luz que o raio joga no chão (embaixo do cano e do ponto de contato)
				var chao_y := C.linha_y(pr.linha) - 4.0
				_elipse_luz(d, Vector2(pr.origem.x + 30.0 * dir, chao_y), 70.0, Color("2ab8ff", 0.10 * alfa))
				_elipse_luz(d, Vector2(pr.pos.x, chao_y), 60.0 + 30.0 * ka, Color("2ab8ff", 0.14 * alfa))
				# RAIO PRINCIPAL (+ um segundo raio mais fino que se cruza com ele)
				_rng_fx.seed = pr.semente + quadro * 7919
				var amp := 11.0 * (0.6 + 0.4 * alfa)
				var pts := _raio_curva(pr, pr.origem.x, pr.pos.x, amp)
				_desenhar_raio(d, pts, alfa, 1.0)
				var pts2 := _raio_curva(pr, pr.origem.x, pr.pos.x, amp * 1.3)
				_desenhar_raio(d, pts2, alfa * 0.45, 0.55)
				# GALHOS: raiozinhos que escapam do raio principal
				var n_galhos := 4 if not somendo else 2
				for g in n_galhos:
					var idx := _rng_fx.randi_range(1, maxi(1, pts.size() - 2))
					var p0: Vector2 = pts[idx]
					var ang := _rng_fx.randf_range(-1.1, 1.1) + (0.0 if dir > 0.0 else PI)
					var comp_g := _rng_fx.randf_range(18.0, 46.0)
					var galho := _raio_entre(p0, p0 + Vector2(cos(ang), sin(ang)) * comp_g, 4, 6.0)
					_desenhar_raio(d, galho, alfa * 0.7, 0.4)
				# ponta do raio viajando: bola de plasma
				if not somendo:
					d.draw_circle(pr.pos, 16.0, Color("1a8fff", 0.18))
					d.draw_circle(pr.pos, 9.0, Color("40eaff", 0.55))
					d.draw_circle(pr.pos, 4.5, Color.WHITE)
				# boca do canhão acesa enquanto o raio está ligado
				var pulso_cano := 1.0 + 0.2 * sin(pr.t * 60.0)
				d.draw_circle(pr.origem, 15.0 * pulso_cano * alfa + 2.0, Color("00a0ff", 0.25 * alfa))
				d.draw_circle(pr.origem, 8.0 * pulso_cano * alfa + 1.0, Color("7ff7ff", 0.7 * alfa))
				d.draw_circle(pr.origem, 4.0 * alfa + 1.0, Color.WHITE, alfa)
			_:
				var cor := Color("7fb6ff")
				if pr.tipo == "magia_fogo": cor = Color("ff8a2a")
				elif pr.tipo == "magia_sombra": cor = Color("9b6bff")
				var pulso := 1.0 + 0.15 * sin(pr.t * 20.0)
				d.draw_circle(pr.pos, 16.0 * pulso, Color(cor, 0.25))
				d.draw_circle(pr.pos, 9.0 * pulso, cor)
				d.draw_circle(pr.pos, 4.0, Color.WHITE)
	# (as ondas de terra / ossos / fogo são desenhadas em _desenhar_ondas_linha: na ordem de profundidade)
	for e in explosoes:
		var kk: float = e[2] / 0.4
		d.draw_circle(e[0], e[1] * (0.4 + 0.6 * kk), Color(e[3], 0.45 * (1.0 - kk)))
	_desenhar_choques(d)
	_desenhar_golpes_castelo(d)
	# — clarão do cano ao disparar —
	for cl in clarões:
		var tc2: float = cl.t / 0.30
		var ac := 1.0 - tc2
		var p3: Vector2 = cl.pos
		var s3: float = cl.dir
		# expansão radial azul elétrico
		d.draw_circle(p3, 22.0 * (0.4 + 1.0 * tc2), Color("00a0ff", 0.22 * ac))
		d.draw_circle(p3, 13.0 * (0.5 + 0.7 * tc2), Color("40eaff", 0.55 * ac))
		d.draw_circle(p3, 5.5, Color.WHITE, 0.98 * ac)
		# estrelinha 4 pontas com brilho extra
		var h := 16.0 * ac + 6.0
		var w := 2.5 * ac + 1.0
		d.draw_line(p3 - Vector2(h, 0), p3 + Vector2(h, 0), Color("b0f8ff", 0.8 * ac), w)
		d.draw_line(p3 - Vector2(0, h), p3 + Vector2(0, h), Color("b0f8ff", 0.8 * ac), w)
		d.draw_line(p3 - Vector2(h, 0), p3 + Vector2(h, 0), Color.WHITE, w * 0.5)
		d.draw_line(p3 - Vector2(0, h), p3 + Vector2(0, h), Color.WHITE, w * 0.5)
		d.draw_line(p3 - Vector2(h * 0.7, h * 0.7), p3 + Vector2(h * 0.7, h * 0.7), Color("80f0ff", 0.5 * ac), 1.2)
		d.draw_line(p3 - Vector2(h * 0.7, -h * 0.7), p3 + Vector2(h * 0.7, -h * 0.7), Color("80f0ff", 0.5 * ac), 1.2)
		# arcos curtos estalando em volta da boca do canhão
		_rng_fx.seed = int(cl.t * 30.0) * 31337 + int(p3.x * 7.0 + p3.y)
		for q in 4:
			var ang_q := _rng_fx.randf_range(0.0, TAU)
			_desenhar_raio(d, _raio_entre(p3, p3 + Vector2(cos(ang_q), sin(ang_q)) * _rng_fx.randf_range(12.0, 28.0), 3, 4.0), ac, 0.35)
		# conezinho de saída elétrico
		d.draw_line(p3, p3 + Vector2(42 * s3, 0), Color("00a0ff", 0.40 * ac), 10.0 * ac + 3.0)
		d.draw_line(p3, p3 + Vector2(42 * s3, 0), Color("40eaff", 0.65 * ac), 5.0 * ac + 1.5)
		d.draw_line(p3, p3 + Vector2(42 * s3, 0), Color.WHITE, 2.0 * ac)
	# impacto do laser do Engenheiro — descarga elétrica massiva na cabeça do alvo
	for im in impactos:
		var tt: float = im.t / 0.50
		var a := pow(1.0 - tt, 0.8)
		var pi2: Vector2 = im.pos
		# flash branco inicial (0-15% do tempo)
		var flash := clampf(1.0 - tt * 6.0, 0.0, 1.0)
		if flash > 0.01:
			d.draw_circle(pi2, 35.0 * flash, Color("ffffff", 0.35 * flash))
			d.draw_circle(pi2, 20.0 * flash, Color("b0f8ff", 0.5 * flash))
		# halo grande suave azul elétrico
		d.draw_circle(pi2, 32.0 * (0.5 + 0.8 * tt), Color("00a0ff", 0.08 * a))
		d.draw_circle(pi2, 18.0 * (0.6 + 0.6 * tt), Color("00d4ff", 0.15 * a))
		# anel de choque que abre (2 camadas)
		for k in 2:
			var rr := (8.0 + 28.0 * tt) - k * 4.0
			var al2 := 0.7 * a * (1.0 - k * 0.4)
			var cols := PackedVector2Array()
			var N2 := 40
			cols.resize(N2 + 1)
			for j in N2 + 1:
				var ang2 := TAU * j / N2
				# ondulação no anel (parece energia elétrica)
				var wobble := 1.0 + 0.08 * sin(ang2 * 6.0 + im.t * 25.0)
				cols[j] = pi2 + Vector2(cos(ang2), sin(ang2)) * rr * wobble
			d.draw_polyline(cols, Color("40eaff", al2), 2.8 - k * 1.2, true)
			d.draw_polyline(cols, Color("ffffff", al2 * 0.5), 1.0 - k * 0.3, true)
		# ARCS ELÉTRICOS saindo do ponto (tipo raio)
		var seed_imp := int(im.t * 40.0)
		for q in 6:
			var ang_arc := TAU * q / 6.0 + 0.3 + sin(im.t * 15.0 + q) * 0.2
			var r_start := 6.0 + 14.0 * tt
			var r_end := r_start + randf_range(12.0, 22.0) * a
			var dir_q := Vector2(cos(ang_arc), sin(ang_arc))
			var arc_pts := PackedVector2Array()
			arc_pts.append(pi2 + dir_q * r_start)
			# meio torto (tipo raio)
			var meio := pi2 + dir_q * (r_start + r_end) * 0.5 + Vector2(randf_range(-4, 4), randf_range(-4, 4))
			arc_pts.append(meio)
			arc_pts.append(pi2 + dir_q * r_end)
			d.draw_polyline(arc_pts, Color("80f0ff", 0.65 * a), 1.4, false)
			d.draw_polyline(arc_pts, Color("ffffff", 0.4 * a), 0.7, false)
			# pontinha brilhante
			d.draw_circle(arc_pts[2], 1.8 * a, Color.WHITE, 0.9 * a)
		# núcleo central pulsante
		var pulso_imp := 1.0 + 0.15 * sin(im.t * 35.0)
		d.draw_circle(pi2, 14.0 * (1.0 - tt * 0.5) * pulso_imp, Color("b0f8ff", 0.50 * a))
		d.draw_circle(pi2, 7.0 * (1.0 - tt * 0.35), Color.WHITE, 0.95 * a)
		# cruz de luz com brilho
		d.draw_line(pi2 - Vector2(20, 0) * a, pi2 + Vector2(20, 0) * a, Color("80f0ff", 0.7 * a), 2.2 * a)
		d.draw_line(pi2 - Vector2(0, 20) * a, pi2 + Vector2(0, 20) * a, Color("80f0ff", 0.7 * a), 2.2 * a)
		d.draw_line(pi2 - Vector2(12, 0) * a, pi2 + Vector2(12, 0) * a, Color.WHITE, 1.2 * a)
		d.draw_line(pi2 - Vector2(0, 12) * a, pi2 + Vector2(0, 12) * a, Color.WHITE, 1.2 * a)
		# faíscas radiais rápidas
		for q in 10:
			var ang := TAU * q / 10.0 + 0.18 + tt * 1.2
			var r0 := 6.0 + 20.0 * tt
			var r1 := r0 + 14.0 * a
			var dir_q := Vector2(cos(ang), sin(ang))
			var col_f := Color("40eaff", 0.9 * a) if q % 2 == 0 else Color("ffe9a0", 0.85 * a)
			d.draw_line(pi2 + dir_q * r0, pi2 + dir_q * r1, col_f, 2.4 if q % 2 == 0 else 1.6)
			d.draw_circle(pi2 + dir_q * r1, 1.6 * a, Color.WHITE, 0.9 * a)
		# poeira de energia que sobe
		for q in 4:
			var ang3 := -PI/2 + (q - 1.5) * 0.45 + sin(im.t * 8.0 + q) * 0.12
			var d3 := 8.0 + tt * 18.0 + q * 5.0
			d.draw_circle(pi2 + Vector2(cos(ang3), sin(ang3)) * d3, 1.5 * a, Color("b0f8ff", 0.7 * a))
		# sombra de impacto no chão
		d.draw_circle(pi2 + Vector2(0, 10), 7.0 * a, Color(0, 0, 0, 0.12 * a))
	for f in faiscas:
		if f.get("raio", false):                  # faísca do raio: risco na direção do voo
			var ta: float = 1.0 - float(f.t) / 0.5
			var v: Vector2 = f.vel
			var traco: Vector2 = v.normalized() * minf(10.0, v.length() * 0.05) * ta
			var cf: Color = f.get("cor", Color("40eaff"))   # (brasa do fogo / faísca da magia: outra cor)
			d.draw_line(f.pos - traco, f.pos, Color(cf, 0.9 * ta), 2.0 * ta + 0.4)
			d.draw_circle(f.pos, 1.6 * ta + 0.3, Color(Color.WHITE.lerp(cf, 0.35 if f.has("cor") else 0.0), 0.95 * ta))
		else:
			d.draw_circle(f.pos, 2.5, Color(1, 1, 1, 1.0 - f.t / 0.5))
	# energia (só a sua aparece)
	for o in orbes:
		if o.lado == lado_local and not o.get("pega_local", false) and C.energia_visivel(o.t, tempo_s):
			hud.icone_energia(d, o.pos, 21.0 * (1.0 + 0.06 * sin(tempo_s * 6.0)))
	# textos de dano (sem espelhar)
	for tx in textos:
		if tx.tela:
			continue
		var a: float = 1.0 - tx.t / 0.9
		_reto(tx.pos)
		d.draw_string_outline(f_titulo, Vector2(-40, 0), tx.txt, HORIZONTAL_ALIGNMENT_CENTER, 80, 20, 5, Color(0, 0, 0, a))
		d.draw_string(f_titulo, Vector2(-40, 0), tx.txt, HORIZONTAL_ALIGNMENT_CENTER, 80, 20, Color(tx.cor, a))
	d.draw_set_transform(Vector2.ZERO)


## Coisas na tela (não no mundo): a luz da casa com o "fantasma" da tropa, energia voando, troca de arena.
func _desenhar_tela() -> void:
	var d := desenho_tela
	# (sem botão de pausa na tela: no celular é o "voltar" do Android; no PC, Esc)
	if carta_sel >= 0 and carta_sel < cartas_dados.size() and espiando and not fim:
		_desenhar_zona_invasao(d)                        # INVASÃO: onde dá para colocar na arena inimiga
	if carta_sel >= 0 and carta_sel < cartas_dados.size() and not fim:
		var g := C.G
		var c := _casa_tela(get_local_mouse_position())
		var pode_aqui := c.x >= 0 and (not espiando or (c.x >= COL_MIN_INVASAO and c.x <= COL_MAX_INVASAO))
		if pode_aqui:
			var cor := Color(1, 1, 1) if lado_local == "heroes" else Color(0.7, 1, 0.5)
			var cx: float = g.left + c.x * g.cw            # (espiando: a grade fica espelhada)
			if espiando:
				cx = C.W - cx - g.cw
			d.draw_rect(Rect2(g.left if not espiando else C.W - g.left - g.cw * g.cols, g.top + c.y * g.ch, g.cw * g.cols, g.ch), Color(cor, 0.12))
			d.draw_rect(Rect2(cx, g.top, g.cw, g.ch * g.rows), Color(cor, 0.10))
			var casa := Rect2(cx, g.top + c.y * g.ch, g.cw, g.ch)
			d.draw_rect(casa, Color(cor, 0.22))
			d.draw_rect(casa, Color(cor, 0.6), false, 2.0)
			var p := cartas_dados[carta_sel]
			var a := p.anim_qualquer(["parado", "defender", "andar"])
			if a and a.textura:
				var k := p.escala * a.escala
				var pes := _pes_casa_tela(c.x, c.y)
				# a folha olha para a direita: na sua tela a tropa sempre anda para a direita
				d.draw_texture_rect_region(a.textura, Rect2(pes - Vector2(a.ax, a.ay) * k, Vector2(a.cw, a.ch) * k), a.retangulo(0), Color(1, 1, 1, 0.5))
	for tx in textos:
		if tx.tela:
			var al: float = 1.0 - tx.t / 0.9
			d.draw_string_outline(f_titulo, tx.pos - Vector2(80, 0), tx.txt, HORIZONTAL_ALIGNMENT_CENTER, 160, 20, 5, Color(0, 0, 0, al))
			d.draw_string(f_titulo, tx.pos - Vector2(80, 0), tx.txt, HORIZONTAL_ALIGNMENT_CENTER, 160, 20, Color(tx.cor, al))
	var alvo: Vector2 = hud.alvo_energia()
	for v in voos:
		var k2: float = v.t / 0.45
		var e := 1.0 - pow(1.0 - k2, 3.0)
		var pos: Vector2 = v.de.lerp(alvo, e) - Vector2(0, sin(k2 * PI) * 60.0)
		hud.icone_energia(d, pos, 18.0 * (1.0 - k2 * 0.3))
	if online() and replay.is_empty():                 # ONLINE: tropa que você mandou e ainda vai aparecer (0,5 s)
		for ac in fila_acoes:
			if ac.lado != lado_local or ac.tipo != "colocar" or bool(ac.get("inv", false)) != espiando:
				continue
			var pa: PersonagemDados = Catalogo.get_p(ac.id)
			var an := pa.anim_qualquer(["parado", "defender", "andar"]) if pa else null
			if an and an.textura:
				var kk := pa.escala * an.escala
				var pe := _pes_casa_tela(int(ac.c), int(ac.r))
				d.draw_texture_rect_region(an.textura, Rect2(pe - Vector2(an.ax, an.ay) * kk, Vector2(an.cw, an.ch) * kk), an.retangulo(0), Color(1, 1, 1, 0.35))
	if esperando_adversario():
		var tw := "Esperando %s..." % adversario
		d.draw_string_outline(f_titulo, Vector2(0, 110), tw, HORIZONTAL_ALIGNMENT_CENTER, C.W, 26, 10, Color("24130a"))
		d.draw_string(f_titulo, Vector2(0, 110), tw, HORIZONTAL_ALIGNMENT_CENTER, C.W, 26, Color("fff4d6"))
	if troca_t > 0.0:
		d.draw_rect(Rect2(Vector2(-200, -200), Vector2(C.W + 2000, C.H + 400)), Color(1, 1, 1, troca_t * 0.6))

## INVASÃO (carta escolhida, espiando): a faixa do lado do portal onde dá para colocar brilha de leve,
## com borda tracejada e o aviso; perto do castelo fica um véu vermelho (ali não dá).
func _desenhar_zona_invasao(d: Node2D) -> void:
	var g := C.G
	var t := Time.get_ticks_msec() / 1000.0
	var x_fim: float = C.W - g.left - COL_MIN_INVASAO * g.cw      # (na tela: da beira do portal até aqui pode)
	var x_ini: float = C.W - g.left - g.cw * (COL_MAX_INVASAO + 1)
	var topo: float = g.top
	var alt: float = g.ch * g.rows
	var cor := Color("ffe08a") if lado_local == "heroes" else Color("b6ff6a")
	var pulso := 0.5 + 0.5 * sin(t * 3.0)
	d.draw_rect(Rect2(x_ini, topo, x_fim - x_ini, alt), Color(cor, 0.06 + 0.04 * pulso))
	d.draw_rect(Rect2(x_fim, topo, C.W - g.left - x_fim, alt), Color(0.9, 0.15, 0.1, 0.10))
	var y := topo
	while y < topo + alt:                                     # borda tracejada (até onde dá para colocar)
		d.draw_line(Vector2(x_fim, y), Vector2(x_fim, minf(y + 14.0, topo + alt)), Color(cor, 0.55 + 0.3 * pulso), 3.0)
		y += 28.0
	var txt := "COLOQUE AQUI · INVASÃO"
	d.draw_string_outline(f_titulo, Vector2(x_ini, topo - 10), txt, HORIZONTAL_ALIGNMENT_CENTER, x_fim - x_ini, 20, 8, Color("24130a"))
	d.draw_string(f_titulo, Vector2(x_ini, topo - 10), txt, HORIZONTAL_ALIGNMENT_CENTER, x_fim - x_ini, 20, cor)

# =================================================================== TOQUES
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
		if painel.visible and not fim:
			_continuar()
		else:
			_pausar()
		return
	if not replay.is_empty():                          # REPLAY: barra para arrastar e toque = velocidade
		_toque_replay(ev)
		return
	var pos := C.pos_toque(self, ev)
	if not pos.is_finite() or fim or (painel and painel.visible):
		return
	if pegar_energia(pos):
		return
	# tocou numa tropa sua (sem carta escolhida): abre o MENU dela
	if carta_sel < 0 and menu_unidade:
		var u := unidade_do_jogador_em(pos)
		if u:
			menu_unidade.tocou(u)
			return
		if menu_unidade.aberto():
			menu_unidade.fechar()
			return
	var casa := _casa_tela(pos)                     # (espiando: a casa da arena inimiga, para a INVASÃO)
	if casa.x >= 0:
		colocar_local(casa)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if painel and painel.visible and not fim:
			_continuar()
		else:
			_pausar()

## ONDAS (terra / ossos / fogo) de UMA linha: cada linha tem seu nó dentro da camada das unidades (y_sort),
## então quem está numa linha mais embaixo fica NA FRENTE dos espinhos/fogo — e não coberto por eles.
var _chao_linhas: Array = []
func _montar_chao_linhas() -> void:
	for r in C.G.rows:
		var n := Node2D.new()
		n.position = Vector2(0, C.linha_y(r) + 0.5)      # (+0,5: na frente de quem está na própria linha)
		n.draw.connect(_desenhar_ondas_linha.bind(n, r))
		camada_unidades.add_child(n)
		_chao_linhas.append(n)

func _desenhar_ondas_linha(n: Node2D, r: int) -> void:
	for o in ondas:
		if o.linha != r:
			continue
		if o.tipo == "fogo":                                 # Golem de Ossos: o fogo correndo pelo chão
			FxExplosao.desenhar_onda_fogo(n, o.x0, o.x, -2.5, o.idade, float(o.linha) * 1.3)
		else:
			FxExplosao.desenhar_onda_ossos(n, o.x0, o.x, -2.5, o.vel, o.idade, float(o.linha) * 1.7, o.tipo == "terra")

## FOTO PARA O PAINEL (assistir ao vivo — 29_painel_assistir.sql): os dois castelos, o tempo e cada personagem.
## x no mundo inteiro (0..MW: arena dos Heroes à esquerda, a dos Monsters à direita).
func foto_ao_vivo() -> Dictionary:
	var u: Array = []
	for lista in [herois, monstros]:
		for l in lista:
			for x in l:
				if is_instance_valid(x) and not x.morto and u.size() < 90:
					u.append([x.linha, roundi(x.position.x), 0 if x.lado == "heroes" else 1, x.p.id, roundi(100.0 * x.vida / maxf(1.0, x.vida_max))])
	return {"m": "cerco" if modo == "cerco" else ("campeonato" if campeonato else "pvp"), "w": P.MW, "aw": C.W, "gl": C.G.left, "gc": C.G.cw,
		"ll": lado_local, "adv": adversario, "online": online(), "vh": roundi(vidas.heroes), "vm": roundi(vidas.monsters), "vmax": P.VIDA_CASTELO,
		"t": floori(maxf(tempo, 0.0)), "prep": ceili(maxf(preparo, 0.0)), "e": energia, "fim": fim, "u": u}

## FLECHA DE FOGO acertou: estoura em chamas, dano extra e o inimigo fica QUEIMANDO por uns segundos.
func _acerto_fogo(pr, alvo: Unidade) -> void:
	if alvo == null or not is_instance_valid(alvo):
		return
	ferir(alvo, pr.dano * 0.6, null, pr.origem_id, Color("ffb347"))
	if not alvo.morto:
		alvo.queimar(3.0, maxf(4.0, pr.dano * 0.22), pr.origem_id)
	var quem: PersonagemDados = Catalogo.get_p(pr.origem_id)
	Sons.do_personagem(quem, "fogo")
	if fx_ar:
		fx_ar.explodir(alvo.position + Vector2(0, -55), 0.38)
	explosoes.append([alvo.position + Vector2(0, -50), 54.0, 0.0, Color("ff6a1a")])

## Inimigo mais perto que JÁ APARECEU na arena onde a tropa está (fora do portal, na linha e no lado para onde olha).
## Quem ataca DE LONGE começa a atacar assim que ele aparece. Só usa estado do passo fixo (igual nos dois aparelhos).
func alvo_visivel(u: Unidade) -> Unidade:
	var b := _lado_b(u.position.x)
	var s := u._dir()
	var borda_dir := P.MW if b else C.W
	var borda_esq := P.MW - C.W if b else 0.0
	var melhor: Unidade = null
	var melhor_d := INF
	var lista: Array = monstros[u.linha] if u.lado == "heroes" else herois[u.linha]
	for o in lista:
		if o.morto or _lado_b(o.position.x) != b or (u.lado == "monsters" and not o.ocupa_casa):
			continue
		if o.position.x > borda_dir - MARGEM_VISIVEL or o.position.x < borda_esq + MARGEM_VISIVEL or _alfa_fenda(o) < 0.6:
			continue
		var d: float = (o.position.x - u.position.x) * s
		if d >= -10.0 and d < melhor_d:
			melhor = o; melhor_d = d
	return melhor