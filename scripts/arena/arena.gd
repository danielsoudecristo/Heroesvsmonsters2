extends Node2D
## ARENA DA CAMPANHA (Heroes contra as ondas de esqueletos).
## OTIMIZAÇÕES:
## - A lógica roda em passos fixos de 1/60 s (_physics_process): mesma velocidade em qualquer celular.
## - Cada linha da arena tem a sua lista de heróis e de monstros: ninguém procura alvo no campo todo.
## - Projéteis, ondas, barras de vida, energia e textos são desenhados por UM nó só (poucas chamadas de desenho).
## - Projéteis e textos são reaproveitados (pool), sem criar memória nova durante a partida.

@export var nivel_inicial := 1             ## nível da campanha para começar (teste)
@export var nivel_herois := 1              ## nível da conta dos heróis (depois vem do Supabase)
@export var energia_infinita := false      ## teste
@export var mostrar_fps := true
@export var mostrar_grade := false         ## liga as linhas de todas as casas (para alinhar com a terra)

const C := preload("res://scripts/arena/config_arena.gd")
const DANO_CASTELO_TIRO := 2               ## flecha/magia de monstro que acerta o castelo
const DANO_CASTELO_PADRAO := 10            ## monstro que entra no castelo
## RAIO DO ENGENHEIRO: descarga que sai do canhão e eletrocuta quem acerta.
const RAIO_VEL := 3200.0                   ## px/s da ponta do raio (bem rápido: parece instantâneo)
const RAIO_RECUO := 48.0                   ## puxa o começo do raio para trás (até a boca do canhão no desenho)
const RAIO_SOME := 0.2                    ## segundos que o raio fica tremulando ligado ao alvo depois de acertar
const CHOQUE_PCT := 0.5                    ## choque elétrico: +50% do dano do tiro, em pulsos, enquanto o inimigo treme
const CHOQUE_DUR := 0.75                   ## segundos de choque no inimigo
const CHOQUE_PULSOS := 3                   ## em quantos pulsos o dano do choque é dividido
## SOBRECARGA do Engenheiro: a cada N raios a descarga salta em corrente para os inimigos de trás (mesma linha).
const SOBRECARGA_CADA := 4
const SOBRECARGA_SALTOS := [0.6, 0.4]        ## dano de cada salto (fração do tiro)
const SOBRECARGA_ALCANCE := 260.0            ## distância máxima de um inimigo para o próximo
const MARGEM_VISIVEL := 70.0              ## o inimigo precisa estar esta distância dentro da tela para o Engenheiro atirar

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
	var x_fim := 0.0                  # (energia) x do alvo no disparo (serve de referência da curva)
	var alvo_ref: Unidade = null      # (energia) quem a energia mira (acompanha a cabeça)
	var fixado := false               # (energia) já acertou: o feixe gruda no alvo e se apaga lá
	var t_fixado := 0.0               # (energia) quanto tempo faz que acertou
	var semente := 0                  # (energia) forma do raio (muda várias vezes por segundo: o raio tremula)
	var atirador: Unidade = null      # (energia) quem atirou (conta os tiros da SOBRECARGA)

class Onda:
	var tipo := ""
	var lado := ""
	var linha := 0
	var x := 0.0
	var vel := 0.0
	var dano := 0
	var atingidos: Dictionary = {}
	var x0 := 0.0                       # de onde saiu (o rastro de fogo do Golem)
	var idade := 0.0

class Texto:
	var ativo := false
	var pos := Vector2.ZERO
	var txt := ""
	var cor := Color.WHITE
	var t := 0.0
	var tam := 20

# ---------------------------------------------------------------- estado
var herois: Array = []                     # [linha] -> Array[Unidade]
var monstros: Array = []                   # [linha] -> Array[Unidade]
var casas: Array = []                      # [col][linha] -> Unidade ou null
var projeteis: Array[Projetil] = []
var ondas: Array[Onda] = []
var textos: Array[Texto] = []
var explosoes: Array = []                  # [pos, raio, t, cor]
var impactos: Array = []                   # {pos, t, lado} — flash do laser do Engenheiro na cabeça
var clarões: Array = []                    # {pos, t, dir} — clarão arcano no cano do Engenheiro ao atirar
var rastros: Array = []                    # {pos, t} — pontinhos do feixe arcano que ficam no ar
var choques: Array = []                    # {alvo, t, dano, pulsos} — inimigo eletrocutado pelo raio do Engenheiro
var sobrecarga := {}                       # id do Engenheiro -> raios que já acertaram
var correntes: Array = []                  # {de, para, t, semente} — raio da SOBRECARGA saltando entre inimigos
var _rng := RandomNumberGenerator.new()    # forma dos raios (com semente: o mesmo raio no mesmo quadro)
var orbes: Array = []                      # {pos, alvo_y, valor, t}

var energia := C.ENERGIA_INICIAL
var vida_castelo := float(C.VIDA_CASTELO)
var nivel := 1
var fase: Dictionary
var onda_idx := 0
var fila: Array[String] = []               # monstros que ainda vão entrar nesta onda
var espera := 0.0                          # tempo até o próximo evento da campanha
var estado := "preparo"                    # preparo / onda / pausa / fim_nivel / derrota
var ceu_t := 4.0
var abates := 0
var moedas_ganhas := 0
var noite := false
var dif: Dictionary = {}                   # dificuldade escolhida no Novo jogo (C.DIFICULDADES)
var rajada := 0                            # MONTE: quantos monstros ainda vêm colados
var mods: Array = []                       # modificadores deste nível (C.MODS): couraça, fúria, pressa...
var invasores := {}                        # id -> dano no castelo neste nível (a dica da derrota usa)
## CAMPANHA DOS DOIS LADOS: quem o jogador escolheu fica na grade (à esquerda, defendendo o castelo)
## e vem nas ondas o outro. Com "monsters" os papéis se trocam: os heróis passam a ser a horda.
var lado_jogador := "heroes"
var lado_inimigo := "monsters"

var cartas_dados: Array[PersonagemDados] = []
var cartas_todas: Array[PersonagemDados] = []       ## TODAS as cartas do lado (inclusive as bloqueadas) — a janela de seleção mostra todas
var selecao: Control                                 ## janela de escolha de cartas antes da partida (selecao_cartas.gd)
var recarga: Dictionary = {}               # id -> segundos restantes
var carta_sel := -1
var _uid_n := 0                            # número de cada tropa criada (o menu do personagem usa)
var menu_unidade: Control                   # menu do personagem (parar / andar / voltar / poderes / remover)
var ultimo_toque := {"casa": Vector2i(-1, -1), "t": 0.0}

# nós
var fundo: Sprite2D
var camada_unidades: Node2D
var desenho: Node2D
var fx_chao: FxExplosao
var fx_ar: FxExplosao
var fx_magia_chao: FxMagia
var fx_magia: FxMagia
var ui: CanvasLayer
var hud: Control
var lbl_banner: Label
var lbl_fps: Label
var bt_tentar: Button
var tela_derrota: Control                  # painel bonito do "O CASTELO CAIU!" (tela_derrota.gd)
var tochas: Node2D                         # fogo vivo nas tochas do fundo (tochas_fundo.gd)
var castelo_caiu: Node2D                   # castelo destruído com fogo e fumaça (castelo_caiu.gd)
var banner_t := 0.0
var segurar := false                        ## TUTORIAL: campanha parada (sem monstros e sem energia do céu)
var tutorial: Node = null
var espiar_t := 0.0                         # tempo que ainda mostra a espionagem
var cartas_usadas := {}                     ## REGISTRO: id -> quantas vezes colocou neste nível
var _t_nivel := 0.0
var painel_menu: Control
var painel_menu_bons: Array[Button] = []
var painel_menu_visivel := false

func _ready() -> void:
	randomize()
	Conta.tela_provedor = foto_ao_vivo              # (painel: assistir ao vivo)
	Engine.physics_ticks_per_second = 60
	Perfil.carregar()                               # garante o lado e a dificuldade (o menu já carrega antes)
	lado_jogador = "monsters" if Perfil.lado == "monsters" else "heroes"
	lado_inimigo = "heroes" if lado_jogador == "monsters" else "monsters"
	for i in C.G.rows:
		herois.append([])
		monstros.append([])
	for c in C.G.cols:
		var col_arr: Array = []
		col_arr.resize(C.G.rows)
		casas.append(col_arr)
	for i in 64:
		projeteis.append(Projetil.new())
	for i in 32:
		textos.append(Texto.new())
	dif = C.dificuldade()
	ConfigArena.energia_dura = dif.energia_dura
	energia = C.ENERGIA_INICIAL
	_montar_cena()
	_montar_hud()
	get_viewport().size_changed.connect(_centralizar)
	_centralizar()
	if not Perfil.tutorial_jogo and nivel_inicial == 1 and lado_jogador == "heroes":   # 1ª vez: batalha guiada com a mãozinha
		for p in cartas_todas:                          # o tutorial ensina com o baralho liberado inteiro (sem janela)
			if Perfil.personagem_liberado(p):
				cartas_dados.append(p)
		comecar_nivel(nivel_inicial)
		tutorial = preload("res://scripts/arena/tutorial_jogo.gd").new()
		tutorial.arena = self
		ui.add_child(tutorial)
		tutorial.comecar()
	else:                                               # toda partida: escolhe as cartas antes de começar
		segurar = true                                  # segura as ondas e a energia do céu até confirmar
		_preparar_inicios()
		selecao.abrir(cartas_todas)

## CONTINUAR: a campanha começa no nível depois do ÚLTIMO CONCLUÍDO (e dá para voltar para os marcos
## 11, 21, 31... ou o 1). No HardCore não: lá perder é voltar para o 1.
func _preparar_inicios() -> void:
	selecao.info_nivel = _info_nivel
	if nivel_inicial != 1 or dif.perde_tudo:
		selecao.inicios = []
		selecao.inicio = nivel_inicial
		return
	selecao.inicios = C.inicios_liberados(Perfil.recorde(Perfil.dificuldade, lado_jogador))
	selecao.inicio = int(selecao.inicios[-1])               # já sugere o nível depois do último concluído

## Uma linha sobre o nível n (aparece na janela de cartas para escolher o baralho certo).
func _info_nivel(n: int) -> String:
	var f := C.fase(n)
	var fase_atual = fase
	fase = f
	var fortes := _texto_fortes()
	fase = fase_atual
	var m := C.mods_do_nivel(n, Perfil.dificuldade)
	var lm: Array = m.map(func(k): return C.MODS[k].nome)
	return "Nível %d · %s%s%s" % [n, f.nome, ("  ·  " + fortes) if fortes != "" else "",
		("  ·  " + ", ".join(lm)) if not lm.is_empty() else ""]

## Jogador escolheu as cartas na janela: libera o campo e começa o nível.
func _cartas_escolhidas(escolhidas: Array) -> void:
	cartas_dados.clear()
	for p in escolhidas:
		cartas_dados.append(p)
	segurar = false
	comecar_nivel(selecao.inicio if not selecao.inicios.is_empty() else nivel_inicial)

## O tutorial terminou (ou foi pulado): começa o nível 1 de verdade (só aqui fica com os heróis e a energia do tutorial).
func tutorial_acabou() -> void:
	segurar = false
	tutorial = null
	comecar_nivel(nivel, false)

## Celular de tela larga: o jogo fica no meio e o fundo cobre as laterais.
func _centralizar() -> void:
	C.centralizar(self, [ui])
	if fundo.texture:
		var k := C.escala_fundo(self, fundo.texture)
		fundo.scale = Vector2(k, k)

func _registrar_cartas(venceu: bool) -> void:
	if not cartas_usadas.is_empty():
		Conta.registrar("cartas", {"modo": "campanha", "lado": lado_jogador, "venceu": venceu, "nivel": nivel, "cartas": cartas_usadas.duplicate()})
	cartas_usadas = {}

func _exit_tree() -> void:
	if estado in ["preparo", "onda", "pausa"] and _t_nivel > 5.0:     # saiu no meio do nível
		Conta.registrar("desistiu", {"modo": "campanha", "lado": lado_jogador, "nivel": nivel, "dif": Perfil.dificuldade, "minuto": snappedf(_t_nivel / 60.0, 0.1)})
	Conta.estou("menu")
	get_viewport().canvas_transform = Transform2D.IDENTITY

# ================================================================= CENA
## +1 = o inimigo está à direita; -1 = à esquerda. Quem defende a grade olha para a direita
## (as ondas sempre entram por lá) e quem vem na onda marcha para a esquerda (o castelo fica lá).
func dir_de(lado: String) -> float:
	return 1.0 if lado == lado_jogador else -1.0

func _montar_cena() -> void:
	fundo = Sprite2D.new()
	fundo.centered = true
	fundo.position = Vector2(C.W / 2, C.H / 2)
	fundo.z_index = -10
	add_child(fundo)
	tochas = preload("res://scripts/arena/tochas_fundo.gd").new()
	fundo.add_child(tochas)
	castelo_caiu = preload("res://scripts/arena/castelo_caiu.gd").new()   # o castelo em ruínas pegando fogo (na derrota)
	fundo.add_child(castelo_caiu)
	castelo_caiu.limpar()
	camada_unidades = Node2D.new()
	camada_unidades.y_sort_enabled = true      # quem está mais embaixo fica na frente
	add_child(camada_unidades)
	_montar_chao_linhas()
	desenho = Node2D.new()
	desenho.z_index = 10
	desenho.draw.connect(_desenhar)
	add_child(desenho)
	fx_chao = FxExplosao.new()                  # explosões: marca/luz/onda no chão (embaixo de todos)...
	fx_chao.camada = "chao"
	fx_chao.z_index = -5
	add_child(fx_chao)
	fx_ar = FxExplosao.new()                    # ...e fogo, fumaça, brasas e terra por cima
	fx_ar.z_index = 9
	fx_ar.par_chao = fx_chao
	add_child(fx_ar)
	fx_magia_chao = FxMagia.new()               # magia: luz/onda/marca no chão (embaixo de todos)...
	fx_magia_chao.camada = "chao"
	fx_magia_chao.z_index = -5
	add_child(fx_magia_chao)
	fx_magia = FxMagia.new()                    # ...e a esfera voando + o impacto por cima
	fx_magia.z_index = 11
	fx_magia.par_chao = fx_magia_chao
	fx_magia.projeteis = projeteis
	add_child(fx_magia)

func _trocar_fundo() -> void:
	# o fundo do lado dos monstros tem o castelo dos monstros na esquerda (mesma geometria de sempre)
	var nome := ("arena_monsters_" if lado_jogador == "monsters" else "arena_guerreiro_") + ("noite" if noite else "dia")
	var tex: Texture2D = null
	var est := C.estacao(maxi(nivel, 1))
	var nomes: Array = [nome + "_largo", nome, "fundo_do_jogo"]
	if est != "":
		nomes.push_front(nome + "_largo_" + est)
	for n in nomes:
		for ext in ["jpg", "png", "webp"]:
			var c := "res://assets/Fundo/%s.%s" % [n, ext]
			if tex == null and ResourceLoader.exists(c):
				tex = load(c)
	fundo.texture = tex
	if tex:
		var k := C.escala_fundo(self, tex)        # cobre a tela inteira (a imagem "_largo" sobra dos lados)
		fundo.scale = Vector2(k, k)
	tochas.usar(tex, noite)                     # fogo vivo nas tochas pintadas no fundo
	if castelo_caiu:
		castelo_caiu.limpar()                   # (nível novo: o castelo está inteiro de novo)
	RenderingServer.set_default_clear_color(Color("07080d"))   # (se sobrar alguma borda, fica escura, nunca verde)

# ================================================================= HUD
func _label(pos: Vector2, tam: int, cor := Color.WHITE) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", cor)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _montar_hud() -> void:
	var todas := Catalogo.do_lado(lado_jogador)
	cartas_todas.clear()
	cartas_dados.clear()
	for p in todas:
		cartas_todas.append(p)
	var ordem: Array = C.ORDEM_CARTAS_MONSTROS if lado_jogador == "monsters" else C.ORDEM_CARTAS
	cartas_todas.sort_custom(func(a, b):                  # mesma ordem das cartas do site
		var ia := ordem.find(a.id); var ib := ordem.find(b.id)
		return (ia if ia >= 0 else 99) < (ib if ib >= 0 else 99))
	ui = CanvasLayer.new()
	add_child(ui)
	hud = preload("res://scripts/arena/hud.gd").new()
	hud.arena = self
	ui.add_child(hud)
	lbl_banner = _label(Vector2(0, 230), 38, Color("fff4d6"))
	lbl_banner.size = Vector2(C.W, 120)
	lbl_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_banner.add_theme_constant_override("outline_size", 10)
	if hud.f_titulo:
		lbl_banner.add_theme_font_override("font", hud.f_titulo)
	ui.add_child(lbl_banner)
	lbl_fps = _label(Vector2(C.W - 70, 8), 14, Color(1, 1, 1, 0.75))
	lbl_fps.visible = mostrar_fps
	ui.add_child(lbl_fps)
	bt_tentar = Button.new()
	bt_tentar.text = "Tentar de novo"
	bt_tentar.position = Vector2(C.W / 2 - 110, 380)
	bt_tentar.custom_minimum_size = Vector2(220, 60)
	bt_tentar.add_theme_font_size_override("font_size", 24)
	bt_tentar.visible = false
	bt_tentar.pressed.connect(_tentar_de_novo)
	ui.add_child(bt_tentar)
	menu_unidade = preload("res://scripts/arena/menu_unidade.gd").new()
	menu_unidade.arena = self
	ui.add_child(menu_unidade)
	tela_derrota = preload("res://scripts/arena/tela_derrota.gd").new()
	tela_derrota.arena = self
	tela_derrota.hud = hud
	ui.add_child(tela_derrota)
	# painel de pausa (menu) — fica por cima de tudo, funciona com o jogo parado
	painel_menu = Control.new()
	painel_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	painel_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	painel_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	painel_menu.draw.connect(_desenhar_painel_menu)
	painel_menu.visible = false
	ui.add_child(painel_menu)
	# janela de seleção de cartas (abre no _ready, antes do nível começar)
	selecao = preload("res://scripts/arena/selecao_cartas.gd").new()
	selecao.arena = self
	selecao.escolheu = _cartas_escolhidas
	selecao.sair = _menu_ir
	ui.add_child(selecao)

func _atualizar_hud() -> void:
	if mostrar_fps:
		lbl_fps.text = "%d fps" % Engine.get_frames_per_second()

func mostrar_banner(txt: String, tempo := 3.5) -> void:
	lbl_banner.text = txt
	lbl_banner.visible = true
	banner_t = tempo

# ================================================================= CAMPANHA
## Todo nível começa com a arena LIMPA (o jogador cria os guerreiros de novo) e a energia do começo (sem bônus).
func comecar_nivel(n: int, limpar := true) -> void:
	nivel = n
	cartas_usadas = {}
	_t_nivel = 0.0
	if menu_unidade:
		menu_unidade.zerar_preco()                              # nível novo: o poder vermelho volta ao preço inicial
	Conta.estou("campanha", "Nível %d · %s" % [n, str(dif.get("nome", ""))])
	fase = C.fase(n)
	mods = C.mods_do_nivel(n, Perfil.dificuldade)
	invasores = {}
	onda_idx = 0
	fila.clear()
	estado = "preparo"
	if nivel == 1:
		espera = C.CAMPANHA.preparo_nivel1                      # nível 1: tempo de sobra para montar o batalhão
	else:
		espera = C.CAMPANHA.preparo + minf(C.CAMPANHA.preparo_extra_max, (nivel - 1) * C.CAMPANHA.preparo_extra_nivel)
	vida_castelo = C.VIDA_CASTELO
	lbl_banner.position.y = 230                                 # (a derrota sobe o texto: volta ao lugar)
	noite = C.eh_noite(n)
	ceu_t = 4.0                                                 # o 1º orbe do céu sempre no mesmo tempo
	bt_tentar.visible = false
	tela_derrota.esconder()
	hud.visible = true
	if limpar:
		_limpar_tudo()
		energia = C.energia_inicial(n) + int(dif.energia_ini) + Perfil.energia_extra   # (painel: energia extra)
		energia = maxi(energia, 50)
	rajada = 0
	_trocar_fundo()
	var inimigos := 0
	for w in fase.ondas.size():
		for k in fase.ondas[w]:
			inimigos += _qtd(int(fase.ondas[w][k]), w == fase.ondas.size() - 1)
	inimigos += _chefes()
	_total_nivel = inimigos
	# começo do nível: só o essencial na tela (nível e ondas) — nada de texto cobrindo a arena
	var n_ondas: int = fase.ondas.size()
	mostrar_banner("NÍVEL %d\n%d %s" % [n, n_ondas, "ONDA" if n_ondas == 1 else "ONDAS"], 3.0)

## "Forte contra:" dos inimigos que mais vêm neste nível (ensina a usar cada carta).
func _texto_fortes() -> String:
	var cont := {}
	for o in fase.ondas:
		for k in o:
			var id: String = C.LETRA_MONSTRO[k]
			cont[id] = int(cont.get(id, 0)) + int(o[k])
	var ids := cont.keys()
	ids.sort_custom(func(a, b): return cont[a] > cont[b])
	var partes: Array = []
	for id in ids.slice(0, 2):
		var p_ini := Catalogo.get_p(_id_da_onda(id))
		var fortes: Array = []
		for f in C.fortes_contra(id):
			var pf := Catalogo.get_p(f if lado_jogador == "heroes" else (Catalogo.par_de(f).id if Catalogo.par_de(f) else f))
			if pf and not fortes.has(pf.nome_card()):
				fortes.append(pf.nome_card())
		if p_ini and not fortes.is_empty():
			partes.append("%s ← %s" % [p_ini.nome_card(), ", ".join(fortes.slice(0, 2))])
	return ("Forte contra: " + " · ".join(partes)) if not partes.is_empty() else ""

## Quantos monstros vêm (dificuldade; a última onda é a GRANDE HORDA, com mais ainda).
func _qtd(n: int, ultima: bool) -> int:
	if n <= 0:
		return 0
	return maxi(1, roundi(n * float(dif.qtd) * C.mod_mult(mods, "qtd") * ((float(dif.horda) * C.horda_do_nivel(nivel)) if ultima else 1.0)))

func _chefes() -> int:
	var c := int(fase.get("chefes", 0))
	return c + int(dif.chefe_extra) if c > 0 else 0

func _tentar_de_novo() -> void:
	comecar_nivel(1 if dif.perde_tudo else nivel, true)

func _limpar_tudo() -> void:
	for lista in [herois, monstros]:
		for l in lista:
			for u in l:
				u.queue_free()
			l.clear()
	for col_arr in casas:
		col_arr.fill(null)
	for pr in projeteis:
		pr.ativo = false
	ondas.clear()
	orbes.clear()
	explosoes.clear()
	choques.clear()
	correntes.clear()
	sobrecarga.clear()
	recarga.clear()

## Quem vem na onda. No lado invertido os esqueletos aparecem como o par do outro lado
## (esqueleto -> nick, esqueletoArqueiro -> arqueiro ...), na mesma ordem de força.
func _id_da_onda(id: String) -> String:
	if lado_inimigo == "monsters":
		return id
	var par := Catalogo.par_de(id)
	return par.id if par else id

func _montar_fila_da_onda() -> void:
	fila.clear()
	var o: Dictionary = fase.ondas[onda_idx]
	var ultima: bool = onda_idx == fase.ondas.size() - 1
	for letra in o:
		for i in _qtd(int(o[letra]), ultima):
			fila.append(_id_da_onda(C.LETRA_MONSTRO[letra]))
	fila.shuffle()
	if ultima:
		for i in _chefes():
			fila.append("!" + _id_da_onda(C.CAMPANHA.chefao))   # "!" = chefão, entra por último

func _passo_campanha(dt: float) -> void:
	if estado == "derrota":
		return
	espera -= dt
	match estado:
		"preparo", "pausa":
			if espera <= 0.0:
				_montar_fila_da_onda()
				estado = "onda"
				espera = 0.5
				if onda_idx == fase.ondas.size() - 1 and fase.ondas.size() > 1:
					mostrar_banner("⚠ UMA GRANDE HORDA ESTÁ CHEGANDO! ⚠", 2.6)
					Sons.tocar("Jogo/som/lutem", 0.9)
					rajada = int(dif.rajada_max)         # a horda já começa com um monte
				else:
					mostrar_banner("ONDA %d!" % (onda_idx + 1), 1.6)
		"onda":
			if fila.is_empty():
				if _monstros_vivos() == 0:
					if onda_idx + 1 < fase.ondas.size():
						onda_idx += 1
						estado = "pausa"
						espera = C.CAMPANHA.pausa_entre_ondas
					else:
						_fim_do_nivel()
			elif espera <= 0.0:
				var id: String = fila.pop_front()
				var chefe := id.begins_with("!")
				id = id.trim_prefix("!")
				var u := criar_unidade(id, lado_inimigo, randi() % C.G.rows, -1, C.nivel_monstros(nivel))
				if u:
					var f := float(dif.forca) * C.poder_inimigo(nivel)   # dificuldade x curva do nível
					u.vida_max = roundi(u.vida_max * f * C.mod_mult(mods, "vida") * (C.CAMPANHA.chefe_vida if chefe else 1.0))
					u.vida = u.vida_max
					u.dano = roundi(u.dano * f * C.mod_mult(mods, "dano") * (C.CAMPANHA.chefe_dano if chefe else 1.0))
					u.vel_mult = C.mod_mult(mods, "vel")
				if u and chefe:
					u.chefe = true
					u.scale *= 1.15
					u.reset_physics_interpolation()
				# MONTE (igual Plants vs Zombies): às vezes vários vêm colados
				var ultima: bool = onda_idx == fase.ondas.size() - 1
				if rajada <= 0 and fila.size() >= 2 and randf() < float(dif.rajada) * (3.0 if ultima else 1.0):
					rajada = randi_range(2, int(dif.rajada_max))
					if rajada >= 4:
						mostrar_banner("UM MONTE DE INIMIGOS!", 1.4)
				if rajada > 0:
					rajada -= 1
					espera = C.intervalo_monstros(nivel) * C.RAJADA_INTERVALO
				else:
					espera = C.intervalo_monstros(nivel)
		"fim_nivel":
			if espera <= 0.0:
				comecar_nivel(nivel + 1)

func _fim_do_nivel() -> void:
	estado = "fim_nivel"
	espera = C.CAMPANHA.pausa_entre_niveis
	var estrelas := 3 if vida_castelo >= C.CAMPANHA.estrelas_tres else (2 if vida_castelo >= C.CAMPANHA.estrelas_duas else 1)
	var rec_antes := Perfil.recorde(Perfil.dificuldade, lado_jogador)
	var premio := premio_do_nivel(nivel, estrelas, nivel > rec_antes, cartas_usadas.size())
	moedas_ganhas += premio.total
	Perfil.ganhar_moedas(premio.total, lado_jogador)     # vai para o perfil (e para a conta, se estiver logado)
	var novo := Perfil.registrar_recorde(Perfil.dificuldade, nivel, lado_jogador)
	Conta.registrar("campanha", {"dif": Perfil.dificuldade, "nivel": nivel, "lado": lado_jogador, "venceu": true,
		"vida": int(vida_castelo), "estrelas": estrelas})
	_registrar_cartas(true)
	var txt := "NÍVEL %d CONCLUÍDO! %s\n+%d moedas" % [nivel, "★".repeat(estrelas) + "☆".repeat(3 - estrelas), premio.total]
	if premio.extras != "":
		txt += " (" + premio.extras + ")"
	if novo:
		txt += "  ·  ⭐ NOVO RECORDE!"
	if C.eh_marco(nivel):
		txt += "\nMARCO %d VENCIDO!" % nivel
	elif premio.variedade < C.PREMIO.variedade_max and cartas_usadas.size() < 7:
		txt += "\nUse mais cartas diferentes: +%d%% de moedas por carta!" % roundi(C.PREMIO.variedade_por_carta * 100)
	mostrar_banner(txt, 4.5)
	if (novo and nivel > 1) or C.eh_marco(nivel):
		Sons.tocar("Jogo/som/proximo_nivel", 0.9)

## Moedas do nível n: base que cresce com o nível + chefão + marco, e bônus de estrelas,
## recorde novo e baralho variado (quanto mais cartas diferentes usou, mais ganha).
func premio_do_nivel(n: int, estrelas: int, recorde_novo: bool, cartas_diferentes: int) -> Dictionary:
	var P: Dictionary = C.PREMIO
	var base := float(P.base) + float(P.por_nivel) * n
	if _chefes() > 0:
		base += float(P.chefe_por_nivel) * n
	if C.eh_marco(n):
		base += float(P.marco_por_nivel) * n
	var bonus := 0.0
	var extras: Array = []
	if estrelas == 3:
		bonus += float(P.estrela3); extras.append("★★★ +%d%%" % roundi(float(P.estrela3) * 100))
	elif estrelas == 2:
		bonus += float(P.estrela2)
	var variedade := clampf((cartas_diferentes - int(P.variedade_desde) + 1) * float(P.variedade_por_carta), 0.0, float(P.variedade_max))
	if variedade > 0.0:
		bonus += variedade; extras.append("%d cartas +%d%%" % [cartas_diferentes, roundi(variedade * 100)])
	if recorde_novo:
		bonus += float(P.recorde); extras.append("recorde +%d%%" % roundi(float(P.recorde) * 100))
	var total := roundi(base * (1.0 + bonus) * float(dif.moedas))
	return {"total": total, "extras": ", ".join(extras), "variedade": variedade}

func _derrota() -> void:
	var primeira := estado != "derrota"
	if primeira:
		Conta.registrar("campanha", {"dif": Perfil.dificuldade, "nivel": nivel, "lado": lado_jogador, "venceu": false})
		_registrar_cartas(false)
	estado = "derrota"
	vida_castelo = 0
	var dados := _dados_derrota()
	dados["nivel"] = nivel
	dados["recorde"] = maxi(nivel, Perfil.recorde(Perfil.dificuldade, lado_jogador))
	dados["dif_nome"] = dif.nome
	dados["perde_tudo"] = dif.perde_tudo
	dados["feito"] = 1.0 - horda_restante()
	lbl_banner.visible = false
	banner_t = 0.0
	carta_sel = -1
	hud.visible = false                                         # as cartas saem: o painel da derrota é o foco
	# o castelo DESABA: a arte vira a do castelo em ruínas pegando fogo — o painel espera a pessoa ver isso
	if primeira and castelo_caiu and castelo_caiu.cair():
		Sons.tocar("Castelo/som/caiu", 1.0)
		get_tree().create_timer(2.2).timeout.connect(func():
			if estado == "derrota" and not tela_derrota.visible:
				tela_derrota.mostrar(dados))
		return
	tela_derrota.mostrar(dados)

## DICA DA DERROTA: quem mais derrubou o castelo, quem é forte contra ele e quanto custa evoluir.
## É o que leva a pessoa a voltar: ela sabe exatamente o que fazer para passar.
func _dados_derrota() -> Dictionary:
	var pior := ""
	var maior := 0.0
	for id in invasores:
		if float(invasores[id]) > maior:
			maior = float(invasores[id]); pior = id
	if pior == "":
		return {"dica": "Evolua suas cartas e use as que são fortes contra cada inimigo."}
	var p_ini := Catalogo.get_p(pior)
	var base_id := pior if lado_inimigo == "monsters" else (Catalogo.par_de(pior).id if Catalogo.par_de(pior) else pior)
	var fortes: Array = []
	for f in C.fortes_contra(base_id):
		var id_meu: String = f if lado_jogador == "heroes" else (Catalogo.par_de(f).id if Catalogo.par_de(f) else f)
		var pf := Catalogo.get_p(id_meu)
		if pf:
			fortes.append(pf)
	if fortes.is_empty() or p_ini == null:
		return {"dica": "Evolua suas cartas para aguentar o nível %d." % nivel}
	var alvo: PersonagemDados = fortes[0]
	for f in fortes:                                  # sugere evoluir o mais fraco dos que servem
		if Perfil.nivel_de(f.id) < Perfil.nivel_de(alvo.id):
			alvo = f
	var nv := Perfil.nivel_de(alvo.id)
	return {"pior": p_ini, "fortes": fortes, "evoluir": alvo, "nv": nv, "custo": Progressao.custo_proximo(nv)}

func _monstros_vivos() -> int:
	var n := 0
	for l in monstros:
		n += l.size()
	return n

# ================================================================= UNIDADES
## Nível da conta do personagem (tela Personagens). nivel_herois serve para testar no editor.
func nivel_da_carta(id: String) -> int:
	return clampi(maxi(nivel_herois, Perfil.nivel_de(id)), 1, Progressao.NIVEL_MAX)

func criar_unidade(id: String, lado: String, linha: int, col: int, nv: int) -> Unidade:
	var p: PersonagemDados = Catalogo.get_p(id)
	if p == null:
		push_warning("Arena: não achei a ficha '%s'" % id)
		return null
	var u := Unidade.new()
	_uid_n += 1
	u.uid = _uid_n
	u.iniciar(self, p, lado, linha, nv)
	u.col = col
	if lado == lado_jogador:                        # quem está do meu lado defende a grade
		herois[linha].append(u)
	else:                                           # quem vem na onda
		monstros[linha].append(u)
	if col >= 0:                                    # posto numa casa (o defensor fica firme lá)
		u.position = Vector2(C.cel_x(col), C.linha_y(linha))
		casas[col][linha] = u
	else:                                           # entra pela direita
		u.position = Vector2(C.ENTRADA_X, C.linha_y(linha))
		Sons.do_personagem(p, "aparecer")
	camada_unidades.add_child(u)
	u.reset_physics_interpolation()                 # nasce no lugar (não desliza de (0,0) até aqui)
	return u

func colocar_heroi(casa: Vector2i) -> void:
	if carta_sel < 0 or estado == "derrota":
		return
	var p := cartas_dados[carta_sel]
	var ocupante: Unidade = casas[casa.x][casa.y]
	if ocupante != null:
		return
	if recarga.get(p.id, 0.0) > 0.0:
		_texto(Vector2(C.cel_x(casa.x), C.linha_y(casa.y) - 60), "recarregando", Color("cccccc"))
		return
	if not energia_infinita and energia < p.custo:
		_texto(Vector2(C.cel_x(casa.x), C.linha_y(casa.y) - 60), "falta energia", Color("ff8080"))
		return
	if not energia_infinita:
		energia -= p.custo
	recarga[p.id] = p.recarga
	criar_unidade(p.id, lado_jogador, casa.y, casa.x, nivel_da_carta(p.id))
	Sons.tocar("Jogo/som/terra", 0.9)            # bateu na terra: "tum"
	cartas_usadas[p.id] = int(cartas_usadas.get(p.id, 0)) + 1
	carta_sel = -1                                 # colocou: solta a carta
	if C.ESCONDER_CARTAS_AO_COLOCAR:
		hud.guardado = true                        # e guarda as cartas para ver a arena (▲ CARTAS ou teclas 1-7 trazem de volta)

## Pega a energia perto do toque. Também BLOQUEIA colocar herói se o toque foi quase em cima de uma energia.
func pegar_energia(pos: Vector2) -> bool:
	var perto := false
	for o in orbes:
		if o.voa or (C.COLETA_AUTOMATICA <= 0 and o.t > C.energia_dura and not o.get("fixo", false)):
			continue
		var d: float = o.pos.distance_to(pos)
		if d < C.ENERGIA_TOQUE:
			o.voa = true
			Sons.tocar("Jogo/som/energia", 0.6)
			return true
		if d < C.ENERGIA_ZONA_SEGURA:
			perto = true
	return perto                                   # tocou perto demais: não pega, mas também não coloca herói

## Texto da pílula ao lado da barra do castelo.
func texto_fase() -> String:
	var total: int = fase.ondas.size() if fase else 1
	match estado:
		"preparo": return "Nível %d · Preparo %ds" % [nivel, ceili(maxf(espera, 0.0))]
		"pausa": return "Próxima onda %ds" % ceili(maxf(espera, 0.0))
		"fim_nivel": return "Nível %d concluído!" % nivel
		"derrota": return "Nível %d" % nivel
	return "Nível %d · Onda %d/%d" % [nivel, mini(onda_idx + 1, total), total]

## Quanto ainda falta derrubar do nível (1 = tudo, 0 = acabou). É a "vida" da horda.
var _total_nivel := 1
func horda_restante() -> float:
	if fase.is_empty():
		return 1.0
	var vivos := _monstros_vivos()
	var futuros := fila.size()
	var de := onda_idx + 1 if estado == "onda" else onda_idx
	if estado == "fim_nivel":
		de = fase.ondas.size()
	for w in range(de, fase.ondas.size()):
		for k in fase.ondas[w]:
			futuros += _qtd(int(fase.ondas[w][k]), w == fase.ondas.size() - 1)
	if de < fase.ondas.size():
		futuros += _chefes()
	return clampf(float(vivos + futuros) / maxf(_total_nivel, 1), 0.0, 1.0)

## Barra de PROGRESSO do nível (estilo "a horda está chegando"): quanto do nível já foi vencido (0 → 1)
## e onde começa cada onda (bandeirinhas). O chefão vem junto com a última onda.
func progresso_nivel() -> float:
	return 1.0 - horda_restante()

func marcos_ondas() -> Array:
	var marcos: Array = []
	if fase.is_empty():
		return marcos
	var acum := 0.0
	for w in fase.ondas.size():
		if w > 0:
			marcos.append(acum / maxf(_total_nivel, 1))
		for k in fase.ondas[w]:
			acum += _qtd(int(fase.ondas[w][k]), w == fase.ondas.size() - 1)
	return marcos

## Quantas ondas já começaram (as bandeiras dessas sobem).
func ondas_iniciadas() -> int:
	if estado == "fim_nivel":
		return fase.ondas.size() if fase else 0
	return onda_idx + 1 if estado == "onda" else onda_idx

## ESPIAR: paga energia e mostra quais monstros ainda vêm (onda atual e a próxima).
func espiar() -> void:
	if espiar_t > 0.0 or estado == "derrota":
		return
	if not energia_infinita and energia < C.ESPIAR_CUSTO:
		mostrar_banner("Espiar custa %d de energia" % C.ESPIAR_CUSTO, 1.6)
		return
	if not energia_infinita:
		energia -= C.ESPIAR_CUSTO
	espiar_t = C.ESPIAR_DURACAO
	var contar := {}
	for id in fila:
		var nome := "CHEFÃO " + Catalogo.get_p(id.trim_prefix("!")).nome_card() if id.begins_with("!") else Catalogo.get_p(id).nome_card()
		contar[nome] = contar.get(nome, 0) + 1
	var agora := ", ".join(contar.keys().map(func(k): return "%d %s" % [contar[k], k])) if not contar.is_empty() else "nada"
	var prox := "—"
	var w := onda_idx + 1 if estado == "onda" else onda_idx
	if w < fase.ondas.size():
		var o: Dictionary = fase.ondas[w]
		prox = ", ".join(o.keys().map(func(l): return "%d %s" % [o[l], Catalogo.get_p(_id_da_onda(C.LETRA_MONSTRO[l])).nome_card()]))
		if w == fase.ondas.size() - 1 and fase.get("chefes", 0) > 0:
			prox += " + %d CHEFÃO %s" % [fase.chefes, Catalogo.get_p(_id_da_onda(C.CAMPANHA.chefao)).nome_card()]
	mostrar_banner("ESPIANDO\nAinda nesta onda: %s\nPróxima onda: %s" % [agora, prox], C.ESPIAR_DURACAO)

# ================================================================= COMANDOS DO JOGADOR (menu do personagem)
## O menu (scripts/arena/menu_unidade.gd) chama isto. tipo: parar / andar / voltar / azul / vermelho / remover.
## Na campanha a ordem vale na hora (o PvP online manda pela rede: ver arena_pvp.gd).
func comando(u: Unidade, tipo: String) -> void:
	if u == null or not is_instance_valid(u) or u.morto:
		return
	match tipo:
		"azul":
			u.toque_azul()
		"vermelho":
			u.forcar2 = true
		"remover":
			if u.col >= 0 and casas[u.col][u.linha] == u:
				_tirar_heroi(Vector2i(u.col, u.linha))
			explosoes.append([u.position + Vector2(0, -40), 40.0, 0.0, Color("dfe4ff")])
		"parar":
			u.ordem = "parar"                            # (se estava andando, termina a casa que já reservou)
		"andar", "voltar":
			u.ordem = tipo
			u._ordem_t = 0.0

## CAMPANHA: a tropa anda UMA casa por vez na própria linha (andar = para frente, voltar = para trás).
## Andando, para sozinha quando um inimigo entra no alcance (luta e depois continua); voltando, vai até a 1ª coluna.
## Casa ocupada ou fim da grade = para.
func proxima_casa(u: Unidade) -> void:
	if u.col < 0 or u.ordem not in ["andar", "voltar"]:
		return
	var passo := 1 if u.ordem == "andar" else -1
	if u.ordem == "andar":
		if alvo_na_frente(u, C.G.cw * 1.4) != null:
			return                                       # inimigo colado na casa da frente: luta (continua depois)
	var nova := u.col + passo
	if nova < 0 or nova >= C.G.cols or casas[nova][u.linha] != null:
		u.ordem = "parar"
		return
	casas[u.col][u.linha] = null
	casas[nova][u.linha] = u
	u.col = nova
	u.alvo_x = C.cel_x(nova)

## Tropa do jogador mais perto do toque (para abrir o menu dela).
func unidade_do_jogador_em(pos: Vector2) -> Unidade:
	var casa := C.casa_em(pos)
	if casa.x >= 0 and casas[casa.x][casa.y] != null and not casas[casa.x][casa.y].morto:
		return casas[casa.x][casa.y]
	return null

func _tirar_heroi(casa: Vector2i) -> void:
	var u: Unidade = casas[casa.x][casa.y]
	if u and not u.morto:
		u.morto = true
		u.livre = true
		u.ocupa_casa = false

# --- perguntas que os personagens fazem (sempre só na própria linha) ---
## Quem está na grade olha para a direita (as ondas entram por lá); quem vem na onda olha para a esquerda.
func alvo_na_frente(u: Unidade, alcance: float) -> Unidade:
	var melhor: Unidade = null
	var melhor_d := INF
	var s := u._dir()                                    # (virado = mira para trás)
	if u.lado == lado_jogador:
		for m in monstros[u.linha]:
			if m.morto:
				continue
			var d: float = (m.position.x - u.position.x) * s
			if d >= -10.0 and d <= alcance and d < melhor_d:
				melhor = m; melhor_d = d
	else:
		for h in herois[u.linha]:
			if not h.ocupa_casa:                           # quem defende ainda segura até bater no chão
				continue
			var d: float = (h.position.x - u.position.x) * s
			if d >= -10.0 and d <= alcance and d < melhor_d:
				melhor = h; melhor_d = d
	return melhor

func todos_na_frente(u: Unidade, alcance: float) -> Array:
	var r := []
	var lista: Array = monstros[u.linha] if u.lado == lado_jogador else herois[u.linha]
	for o in lista:
		if o.morto:
			continue
		var d: float = (o.position.x - u.position.x) * u._dir()
		if d >= -10.0 and d <= alcance:
			r.append(o)
	return r

## (Darian) Onda inimiga correndo pelo chão na linha dele, vindo na direção dele (ou um Golem inimigo
## preparando o fogo na linha): devolve a distância; INF = nada vindo.
func ameaca_no_chao(u: Unidade) -> float:
	var melhor := INF
	for o in ondas:
		if o.linha != u.linha or o.lado == u.lado:
			continue
		var d: float = (u.position.x - o.x) * signf(o.vel)        # > 0 = ainda vai chegar nele
		if d > -10.0 and d < 900.0:
			melhor = minf(melhor, d)
	var lista: Array = monstros[u.linha] if u.lado == lado_jogador else herois[u.linha]
	for m in lista:
		if not m.morto and m.p.comportamento == "golem" and m.estado == "especial" and absf(m.position.x - u.position.x) < 900.0:
			melhor = minf(melhor, absf(m.position.x - u.position.x))     # já se prepara enquanto o Golem carrega o fogo
	return melhor

## (Darian) Até onde o arremessado pode voar (dentro da arena).
func limites_arremesso(_u: Unidade) -> Vector2:
	return Vector2(C.G.left + 30.0, C.W - 30.0)

## Até onde vai a linha para o lado "sentido" (+1 direita, -1 esquerda): a parede do castelo ou a borda da tela.
func ponta_da_linha(_u: Unidade, sentido: float) -> float:
	return C.W + 60.0 if sentido > 0.0 else C.G.left - 20.0

## Todos os inimigos da linha de "tras" px atrás até "frente" px na frente (o raio do Golem vai para os dois lados).
func todos_na_linha(u: Unidade, frente: float, tras: float) -> Array:
	var r := []
	var lista: Array = monstros[u.linha] if u.lado == lado_jogador else herois[u.linha]
	for o in lista:
		if o.morto:
			continue
		var d: float = (o.position.x - u.position.x) * u._dir()
		if d >= -tras and d <= frente:
			r.append(o)
	return r

func tem_inimigo_na_linha(u: Unidade) -> bool:
	var lista: Array = monstros[u.linha] if u.lado == lado_jogador else herois[u.linha]
	for m in lista:
		if m.morto:
			continue
		var d: float = (m.position.x - u.position.x) * u._dir()
		if d >= -10.0 and d <= C.W + 20.0:
			return true
	return false

## Como tem_inimigo_na_linha, mas o inimigo já precisa ter APARECIDO na tela (Engenheiro não atira no escuro).
func inimigo_visivel_na_linha(u: Unidade) -> bool:
	var s := u._dir()
	var lista: Array = monstros[u.linha] if u.lado == lado_jogador else herois[u.linha]
	for m in lista:
		if m.morto:
			continue
		var d: float = (m.position.x - u.position.x) * s
		if d < -10.0:
			continue
		if s > 0.0 and m.position.x > C.W - MARGEM_VISIVEL:
			continue                                         # ainda entrando pela borda da direita
		if s < 0.0 and m.position.x < MARGEM_VISIVEL:
			continue
		return true
	return false

func contar_inimigos_na_linha(u: Unidade) -> int:
	var n := 0
	var lista: Array = monstros[u.linha] if u.lado == lado_jogador else herois[u.linha]
	for o in lista:
		if o.morto:
			continue
		var d: float = (o.position.x - u.position.x) * u._dir()
		if d > 0.0 and d < C.W:
			n += 1
	return n

func ferir(alvo: Unidade, valor: float, origem: Unidade = null, origem_id := "", cor_texto := Color(0, 0, 0, 0)) -> void:
	if alvo == null or alvo.morto:
		return
	var atq := origem.p.id if origem != null else origem_id
	if atq == "esqueleto" and alvo.p.id == "arqueiro":
		valor *= 0.3                          # o esqueleto quase não fere o Arqueiro
	var vant := C.vantagem(atq, alvo.p.id)    # ESTRATÉGIA: cada carta é forte contra certos inimigos
	valor *= vant
	var antes := alvo.vida
	var morreu := alvo.receber(valor)
	var tirou := antes - maxf(alvo.vida, 0.0)
	if tirou >= 1.0:
		var cor_t := cor_texto if cor_texto.a > 0.0 else (Color("ffd36b") if alvo.lado == lado_inimigo else Color("ff6b6b"))
		var txt := "-%d" % roundi(tirou)
		var tam := 20
		if vant >= 1.25:                      # golpe certeiro: laranja, maior e com "!"
			cor_t = Color("ff9a2a")
			txt += "!"
			tam = 26
		elif vant <= 0.75:                    # golpe fraco (resistiu): cinza e menor
			cor_t = Color("b8b8b8")
			tam = 16
		_texto(alvo.position + Vector2(randf_range(-12, 12), -alvo.anim.ay * alvo.scale.y - 6), txt, cor_t, tam)
	if morreu and alvo.p.comportamento in ["necro", "mistico"]:                # o Esqueleto Mago morre: os invocados somem
		for lista in [herois, monstros]:
			for l in lista:
				for m in l:
					if m.invocador == alvo and not m.morto:
						m.morrer()
	if morreu and alvo.lado == lado_inimigo:
		abates += 1

func soltar_energia(pos: Vector2, valor: int) -> void:
	orbes.append({"pos": pos, "alvo_y": pos.y, "valor": valor, "t": 0.0, "voa": false})

## Chama "quantos" monstros (na linha do invocador e nas vizinhas), um pouco à frente dele: o chão abre num
## portal e eles SOBEM de dentro dele. vida_mult < 1 = invocados mais fracos. Devolve os criados.
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
		var m := criar_unidade(id, u.lado, r, -1, u.nivel)
		if m:
			m.position.x = u.position.x + u._dir() * C.G.cw   # um pouco à frente do invocador
			m.reset_physics_interpolation()
			m.invocador = u
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

## (Aura) Todos os inimigos INVOCADOS vivos na arena (qualquer linha).
func invocados_inimigos(u: Unidade) -> Array:
	var r := []
	var listas: Array = monstros if u.lado == lado_jogador else herois
	for l in listas:
		for o in l:
			if not o.morto and o.invocador != null:
				r.append(o)
	return r

## Aliados na linha, NA FRENTE de u (entre ele e o inimigo), até "alcance" px (a cura do Místico).
func aliados_na_frente(u: Unidade, alcance: float) -> Array:
	var r := []
	var lista: Array = herois[u.linha] if u.lado == lado_jogador else monstros[u.linha]
	for o in lista:
		if o == u or o.morto:
			continue
		var d: float = (o.position.x - u.position.x) * u._dir()
		if d >= -10.0 and d <= alcance:
			r.append(o)
	return r

func disparar(tipo: String, u: Unidade, saida: Vector2, vel: float, dano_: int, dano_area := 0, raio := 0.0, alvo: Unidade = null) -> void:
	# "saida" é a boca do canhão sempre contada olhando para a direita: o lado joga do seu jeito
	var s := u._dir()
	for pr in projeteis:
		if not pr.ativo:
			pr.ativo = true
			pr.tipo = tipo
			pr.lado = u.lado
			pr.linha = u.linha
			pr.pos = u.position + Vector2(saida.x * s, saida.y)   # saída da flecha/magia, a partir dos pés
			pr.vel = vel * s
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
			# laser do Engenheiro: sai reta do cano e curva até a cabeça do alvo da frente
			pr.origem = pr.pos
			pr.alvo_ref = alvo if tipo == "energia" else null
			if pr.alvo_ref != null:
				pr.mira_y = alvo.posicao_cabeca().y
				pr.x_fim = alvo.position.x
			else:
				pr.mira_y = pr.pos.y
				pr.x_fim = pr.pos.x + 800.0 * s
			pr.atirador = u
			if tipo == "energia":
				pr.pos.x -= RAIO_RECUO * s                # nasce na boca do canhão (não solto no ar)
				pr.origem = pr.pos
				pr.vel = RAIO_VEL * s
				pr.semente = randi()
				_clarão_energia(pr.pos, s)
				# faíscas que espirram do cano
				for k in 5:
					rastros.append({"pos": pr.pos, "t": randf_range(0.0, 0.1),
						"vel": Vector2(s * randf_range(40.0, 160.0), randf_range(-140.0, 40.0))})
			return

## Bomba do Esqueleto Bombardeiro: explode no ponto onde caiu (no chão). Quem está mais perto leva o dano
## cheio, os outros da mesma linha dentro do raio levam o dano em área — e todo mundo leva o tranco.
## A bomba que se VÊ voando até o chão (por cima de todos); ao cair ela explode na tela. O dano é o explodir_bomba.
func lancar_bomba(tex: Texture2D, de: Vector2, para: Vector2, dur: float, esc: float, flip: bool, fogo: Vector2, chao := Vector2.INF) -> void:
	fx_ar.voar_bomba(tex, de, para, dur, esc, flip, fogo, chao)

func explodir_bomba(u: Unidade, ponto: Vector2, dano_: int, dano_area: int, raio: float) -> void:
	var lista: Array = monstros[u.linha] if u.lado == lado_jogador else herois[u.linha]
	var perto: Array = []
	for o in lista:
		if not o.morto and absf(o.position.x - ponto.x) <= raio:
			perto.append(o)
	perto.sort_custom(func(a, b): return absf(a.position.x - ponto.x) < absf(b.position.x - ponto.x))
	for i in perto.size():
		var o: Unidade = perto[i]
		ferir(o, dano_ if i == 0 else dano_area, u)
		o.levar_impacto(signf(o.position.x - ponto.x) if o.position.x != ponto.x else u._dir(), 1.0 if i == 0 else 0.6)

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

func _texto(pos: Vector2, txt: String, cor: Color, tam := 20) -> void:
	for tx in textos:
		if not tx.ativo:
			tx.ativo = true; tx.pos = pos; tx.txt = txt; tx.cor = cor; tx.t = 0.0; tx.tam = tam
			return

# ================================================================= PASSO FIXO (60 por segundo)
func _physics_process(dt: float) -> void:
	if selecao == null or not selecao.visible:          # contando só quando a partida de verdade começou
		_t_nivel += dt
	if not segurar:
		_passo_campanha(dt)
	for p_id in recarga.keys():
		recarga[p_id] = maxf(0.0, recarga[p_id] - dt)
	# energia do céu (de noite cai mais devagar e vale menos — nunca some por completo)
	if not segurar and estado != "derrota":
		ceu_t -= dt
		if ceu_t <= 0.0:
			var vm := float(dif.ceu_mult) * C.mod_mult(mods, "ceu") * (float(C.CAMPANHA.noite_valor_mult) if noite else 1.0)
			var im := float(C.CAMPANHA.noite_intervalo_mult) if noite else 1.0
			ceu_t = randf_range(C.ENERGIA_CEU.intervalo_min, C.ENERGIA_CEU.intervalo_max) * im
			var x := randf_range(C.G.left + 40, C.G.left + C.G.cw * C.G.cols - 40)
			orbes.append({"pos": Vector2(x, -30), "x0": x, "alvo_y": randf_range(C.G.top + 40, C.G.top + C.G.ch * C.G.rows - 20),
				"valor": maxi(1, roundi(C.ENERGIA_CEU.valor * vm)), "t": 0.0, "voa": false})
	_passo_unidades(dt)
	_passo_bonus_nick()
	_passo_projeteis(dt)
	_passo_choques(dt)
	_passo_ondas(dt)
	_passo_orbes(dt)

func _passo_unidades(dt: float) -> void:
	for r in C.G.rows:
		var lh: Array = herois[r]
		var i := lh.size() - 1
		while i >= 0:
			var u: Unidade = lh[i]
			u.passo(dt)
			if not u.ocupa_casa and u.col >= 0 and casas[u.col][r] == u:
				casas[u.col][r] = null
			if u.livre:
				lh[i] = lh[lh.size() - 1]; lh.pop_back()      # tira sem empurrar a lista inteira
				u.queue_free()
			i -= 1
		var lm: Array = monstros[r]
		i = lm.size() - 1
		while i >= 0:
			var m: Unidade = lm[i]
			m.passo(dt)
			if not m.morto and m.position.x < C.INVADE_X:
				_invadiu(m)
			if m.livre:
				lm[i] = lm[lm.size() - 1]; lm.pop_back()
				m.queue_free()
			i -= 1

## Nick: +30% de vida enquanto houver esqueleto normal inimigo de pé (campanha).
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

func _invadiu(m: Unidade) -> void:
	m.morto = true
	m.livre = true
	if estado == "derrota":
		return
	var d: float = float(C.CAMPANHA.chefe_castelo) if m.chefe else float(m.p.dano_castelo if m.p.dano_castelo > 0 else DANO_CASTELO_PADRAO)
	vida_castelo -= d
	invasores[m.p.id] = float(invasores.get(m.p.id, 0.0)) + d
	explosoes.append([C.NUCLEO, 70.0, 0.0, Color("ff6b5e")])
	_texto(C.NUCLEO + Vector2(20, -70), "-%d" % roundi(d), Color("ff6b5e"))
	Sons.tocar("Castelo/som/dano", 0.9)
	if vida_castelo <= 0.0:
		Sons.tocar("Castelo/som/caiu", 1.0)
		_derrota()

func _passo_projeteis(dt: float) -> void:
	for pr in projeteis:
		if not pr.ativo:
			continue
		pr.t += dt
		if pr.tipo == "energia" and pr.fixado:      # acertou: o feixe fica encostado no alvo e se apaga
			pr.t_fixado += dt
			if pr.t_fixado > RAIO_SOME:
				pr.ativo = false
			continue
		if pr.fixado:                                # flecha cravada no muro: fica um pouco e some
			pr.t_fixado += dt
			if pr.t_fixado > 1.6:
				pr.ativo = false
			continue
		var x0 := pr.pos.x
		pr.pos.x += pr.vel * dt
		if pr.tipo == "energia":                          # laser curva do cano até a cabeça
			if not is_instance_valid(pr.alvo_ref) or pr.alvo_ref.morto:
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
		var s := signf(pr.vel)                       # +1 = voou para a direita (também quem atirou virado para trás)
		var na_grade := pr.lado != lado_jogador      # quem vem na onda bate em quem está na grade
		var lista: Array = herois[pr.linha] if na_grade else monstros[pr.linha]
		var alvo: Unidade = null
		if s > 0.0:
			var melhor := INF
			for m in lista:
				if m.morto or (na_grade and not m.ocupa_casa):
					continue
				var mx: float = m.position.x
				if mx >= x0 - 20.0 and mx <= pr.pos.x + 20.0 and mx < melhor:
					alvo = m; melhor = mx
		else:
			var melhor_h := -INF
			for m in lista:
				if m.morto or (na_grade and not m.ocupa_casa):
					continue
				var mx: float = m.position.x
				if mx <= x0 + 20.0 and mx >= pr.pos.x - 20.0 and mx > melhor_h:
					alvo = m; melhor_h = mx
		if alvo:
			ferir(alvo, pr.dano, null, pr.origem_id)
			if pr.fogo:
				_acerto_fogo(pr, alvo)
			if pr.raio > 0.0:
				_explodir(pr, alvo)
				pr.ativo = false
			elif pr.tipo == "magia_sombra":
				_impacto_magia(pr, alvo)
				pr.ativo = false
			elif pr.tipo == "energia":
				# o feixe PARA no corpo do inimigo (na frente da cabeça) e se apaga encostado nele
				var s2 := dir_de(pr.lado)
				var contato := Vector2(alvo.position.x - s2 * 12.0, alvo.posicao_cabeca().y)
				pr.pos = contato
				pr.mira_y = contato.y
				pr.x_fim = contato.x
				pr.fixado = true
				pr.t_fixado = 0.0
				_impacto_energia(alvo, contato, pr.dano)
				_sobrecarga(pr, alvo)
			else:
				pr.ativo = false
		elif s > 0.0:
			if pr.pos.x > C.W + 40:
				pr.ativo = false
		elif pr.lado == lado_jogador and pr.pos.x < C.G.left - 10.0:
			pr.ativo = false                            # flecha nossa atirada para trás: some na beira (não acerta o próprio castelo)
		elif pr.lado != lado_jogador and pr.pos.x < _x_muro(pr.linha):
			# passou a calçada e chegou no MURO do castelo: a flecha crava na parede (a magia estoura nela)
			pr.pos.x = _x_muro(pr.linha)
			if pr.tipo in ["flecha", "flecha_inimiga"]:
				pr.fixado = true
				pr.t_fixado = 0.0
				explosoes.append([pr.pos, 16.0, 0.0, Color("c8b8a0")])   # poeirinha de pedra
			else:
				pr.ativo = false
				if FxMagia.eh_magia(pr.tipo) and fx_magia:   # a magia estoura na pedra com a cor dela
					fx_magia.impacto(pr.pos, signf(pr.vel), 30.0, pr.tipo, C.linha_y(pr.linha))
				else:
					explosoes.append([pr.pos, 26.0, 0.0, Color("ff6b5e")])
			if estado != "derrota":
				vida_castelo -= DANO_CASTELO_TIRO
				invasores[pr.origem_id] = float(invasores.get(pr.origem_id, 0.0)) + DANO_CASTELO_TIRO
				if vida_castelo <= 0.0:
					_derrota()

## FLECHA: haste de madeira com contorno, ponta de aço com brilho, penas e um rastro de vento.
## A do esqueleto é de osso escuro, ponta de osso afiada, penas pretas e rastro verde-fantasma.
## Cravada: a ponta some dentro do muro e ela treme um pouco.
static func desenhar_flecha(d: CanvasItem, pos: Vector2, dir: float, esqueleto: bool, alfa: float, cravada: bool, t: float, fogo := false) -> void:
	# cores: madeira clara e penas de ganso (herói) / madeira escura e penas de corvo (esqueleto)
	var madeira := Color("3a2e26") if esqueleto else Color("a8743e")
	var madeira_luz := Color("6a5a4c") if esqueleto else Color("dcae74")
	var madeira_sombra := Color("221a14") if esqueleto else Color("6e4720")
	var pena_a := Color("2a2430") if esqueleto else Color("f4f1ea")
	var pena_b := Color("6a1a22") if esqueleto else Color("c93a26")
	var linha_cor := Color("8a2a20") if esqueleto else Color("2a4fa8")     # linha enrolada (amarração)
	var aco_luz := Color("efe6d2") if esqueleto else Color("e8eef4")
	var aco_sombra := Color("9a8e78") if esqueleto else Color("6f7d8c")
	var contorno := Color(0.07, 0.05, 0.04, alfa)
	var L := 56.0
	# voando: a flecha "trepida" um pouco ao sair do arco (paradoxo do arqueiro) e estabiliza
	var giro := 0.0
	if cravada:
		giro = sin(t * 60.0) * 0.06 * clampf(1.0 - t * 2.0, 0.0, 1.0)
	else:
		giro = sin(t * 48.0) * 0.045 * exp(-t * 5.0)
	var eixo := Vector2(dir, 0).rotated(giro * dir)
	var nrm := eixo.orthogonal()
	var bico := pos if not cravada else pos - eixo * 9.0     # cravada: a ponta está dentro da parede
	var cauda := bico - eixo * L
	var pp := func(a: float, b: float) -> Vector2: return bico - eixo * a + nrm * b   # (a = px para trás, b = px para o lado)
	if fogo and not cravada:                                  # FLECHA DE FOGO: cauda de cometa em chamas + faíscas
		for k in 14:
			var f := float(k) / 14.0
			var p0: Vector2 = pp.call(6.0 + f * 95.0, sin(t * 26.0 + k * 1.3) * 4.0 * f)
			d.draw_circle(p0, 15.0 - f * 11.0, Color(1.0, 0.18, 0.0, 0.20 * (1.0 - f) * alfa))
			d.draw_circle(p0, 9.0 - f * 6.5, Color(1.0, 0.45 + 0.25 * (1.0 - f), 0.05, 0.55 * (1.0 - f) * alfa))
			d.draw_circle(p0, 4.0 - f * 3.0, Color(1.0, 0.9, 0.55, 0.8 * (1.0 - f) * alfa))
		for s in 8:
			var fs := fmod(t * 3.2 + s * 0.125, 1.0)
			var ps: Vector2 = pp.call(24.0 + fs * 80.0, sin(s * 2.3 + t * 9.0) * 12.0 * fs) + Vector2(0, fs * fs * 18.0)
			d.draw_circle(ps, 2.2 * (1.0 - fs) + 0.6, Color(1.0, 0.85 - fs * 0.4, 0.35, (1.0 - fs) * alfa))
	elif not cravada:                                         # ar cortado: riscos finos e transparentes atrás
		var rc := Color(1, 1, 1, 0.22 * alfa)
		d.draw_line(pp.call(L + 2.0, 0.0), pp.call(L + 34.0, 0.0), rc, 1.2, true)
		d.draw_line(pp.call(L - 6.0, 4.5), pp.call(L + 20.0, 5.5), Color(1, 1, 1, 0.13 * alfa), 1.0, true)
		d.draw_line(pp.call(L - 6.0, -4.5), pp.call(L + 20.0, -5.5), Color(1, 1, 1, 0.13 * alfa), 1.0, true)
	# ---- HASTE: madeira fina e reta, com luz em cima e sombra embaixo
	var h0: Vector2 = pp.call(L - 1.0, 0.0)
	var h1: Vector2 = pp.call(9.0, 0.0)
	d.draw_line(h0, h1, contorno, 4.4, true)
	d.draw_line(h0, h1, Color(madeira, alfa), 2.6, true)
	d.draw_line(h0 + nrm * -0.7, h1 + nrm * -0.7, Color(madeira_luz, alfa), 0.9, true)
	d.draw_line(h0 + nrm * 0.9, h1 + nrm * 0.9, Color(madeira_sombra, 0.7 * alfa), 0.8, true)
	if fogo:
		d.draw_line(pp.call(24.0, 0.0), h1, Color(1.0, 0.35, 0.05, 0.9 * alfa), 2.4, true)
	# ---- PENAS: duas penas curvas (corte de escudo) de cada lado + a do meio, com barbas finas
	for s in [-1.0, 1.0]:
		var cor: Color = pena_b if s < 0.0 else pena_a
		var pts := PackedVector2Array()
		var n := 8
		pts.append(pp.call(L - 2.0, s * 1.0))                 # atrás, rente à haste
		pts.append(pp.call(L - 3.5, s * 6.4))                 # traseira alta (corte reto, um pouco inclinado)
		for k in n + 1:                                       # borda: desce em curva suave até encostar na haste
			var u := float(k) / n
			var x := L - 3.5 - u * 18.0
			var alt := 5.4 * pow(1.0 - u, 0.7) + 1.0
			pts.append(pp.call(x, s * alt))
		d.draw_colored_polygon(pts, Color(cor, alfa))
		for k in 4:                                           # barbas da pena
			var u2 := 0.2 + k * 0.18
			d.draw_line(pp.call(L - 5.0 - u2 * 16.0, s * 1.3), pp.call(L - 3.0 - u2 * 16.0, s * (1.0 + 5.0 * pow(1.0 - u2, 0.7))), Color(cor.darkened(0.3), 0.6 * alfa), 0.7, true)
		var borda := PackedVector2Array(pts)
		borda.append(pts[0])
		d.draw_polyline(borda, contorno, 1.1, true)
	# amarração (linha enrolada) na frente das penas
	for k in 3:
		var xa := L - 21.0 - k * 1.8
		d.draw_line(pp.call(xa, -1.7), pp.call(xa, 1.7), Color(linha_cor, alfa), 1.1, true)
	# encaixe da corda (nock) na ponta de trás
	d.draw_line(pp.call(L - 1.0, 0.0), pp.call(L + 1.5, 0.0), contorno, 4.0, true)
	d.draw_line(pp.call(L + 1.5, -1.6), pp.call(L + 3.2, -2.2), Color(madeira_sombra, alfa), 1.2, true)
	d.draw_line(pp.call(L + 1.5, 1.6), pp.call(L + 3.2, 2.2), Color(madeira_sombra, alfa), 1.2, true)
	if not cravada:
		# ---- PONTA: anel de encaixe + lâmina triangular com nervura no meio (aço / osso afiado)
		d.draw_line(pp.call(13.0, 0.0), pp.call(8.5, 0.0), contorno, 4.6, true)
		d.draw_line(pp.call(13.0, 0.0), pp.call(8.5, 0.0), Color(aco_sombra, alfa), 3.0, true)
		var lam := PackedVector2Array([bico, pp.call(11.0, 4.6), pp.call(8.6, 1.4), pp.call(8.6, -1.4), pp.call(11.0, -4.6)])
		var lb := PackedVector2Array(lam)
		lb.append(lam[0])
		if fogo:                                              # ponta em BRASA
			var pul := 0.85 + 0.15 * sin(t * 40.0)
			d.draw_circle(pp.call(3.0, 0.0), 30.0 * pul, Color(1.0, 0.2, 0.0, 0.22 * alfa))
			d.draw_circle(pp.call(3.0, 0.0), 17.0 * pul, Color(1.0, 0.45, 0.05, 0.45 * alfa))
			d.draw_polyline(lb, contorno, 1.8, true)
			d.draw_colored_polygon(lam, Color(1.0, 0.25, 0.08, alfa))
			d.draw_colored_polygon(PackedVector2Array([pp.call(1.5, 0.0), pp.call(8.0, 2.2), pp.call(8.0, -2.2)]), Color(1.0, 0.92, 0.6, alfa))
			FxExplosao.desenhar_chama(d, pp.call(3.0, 0.0) + Vector2(0, 7), t * 2.0, 0.62, -dir * 34.0)
			d.draw_circle(pp.call(3.0, 0.0), 4.5, Color(1.0, 0.97, 0.75, alfa))
		else:
			d.draw_polyline(lb, contorno, 1.8, true)
			d.draw_colored_polygon(lam, Color(aco_sombra, alfa))
			d.draw_colored_polygon(PackedVector2Array([bico, pp.call(11.0, -4.6), pp.call(8.6, -1.4), pp.call(8.6, 0.0)]), Color(aco_luz, alfa))   # lado da luz
			d.draw_line(bico, pp.call(8.6, 0.0), Color(aco_sombra.darkened(0.35), alfa), 0.9, true)      # nervura
			d.draw_circle(pp.call(3.0, -1.6), 0.9, Color(1, 1, 1, 0.9 * alfa))                                # brilho
	else:                                                     # rachadinha e pó na pedra em volta do furo
		d.draw_line(pos, pos + Vector2(-dir * 3.0, -5.0), Color(0.1, 0.08, 0.06, 0.7 * alfa), 1.2)
		d.draw_line(pos, pos + Vector2(-dir * 4.0, 4.0), Color(0.1, 0.08, 0.06, 0.6 * alfa), 1.0)
## X do muro do castelo na altura de uma linha (o castelo está em perspectiva: embaixo ele vem mais
## para a esquerda). Medido nos fundos 2560x1080: a parede vai de ~190 px (linha de cima) a ~128 (de baixo).
func _x_muro(linha: int) -> float:
	var y := C.linha_y(linha) - 72.0
	var k := C.escala_fundo(self, fundo.texture) if fundo and fundo.texture else 0.667
	var ox := (C.W - 2560.0 * k) / 2.0
	var oy := (C.H - 1080.0 * k) / 2.0
	var orig_y := (y - oy) / k
	var orig_x := lerpf(600.0, 512.0, clampf((orig_y - 384.0) / (832.0 - 384.0), 0.0, 1.0))
	return orig_x * k + ox

## (energia) Próximo inimigo de pé na linha, à frente do feixe — usa quando quem mirava morreu no caminho.
func _proximo_alvo_energia(pr: Projetil) -> Unidade:
	var s := dir_de(pr.lado)
	var na_grade := pr.lado != lado_jogador
	var lista: Array = herois[pr.linha] if na_grade else monstros[pr.linha]
	var melhor: Unidade = null
	var melhor_d := INF
	for m in lista:
		if m.morto or (na_grade and not m.ocupa_casa):
			continue
		var d: float = (m.position.x - pr.pos.x) * s
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

## (energia) Pontos de um raio torto seguindo a curva do tiro, de x_ini até x_fim. Usa o _rng (já com semente).
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
			p += Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-amp, amp) * env)
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
			p += perp * _rng.randf_range(-amp, amp)
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
		_rng.seed = int(ch.semente) + int(float(ch.t) * 25.0) * 104729
		var n_arcos := 3 + int(2.0 * forca)
		for q in n_arcos:
			var p0 := Vector2(a.position.x + _rng.randf_range(-meia, meia), _rng.randf_range(topo.y, pe.y))
			var p1 := p0 + Vector2(_rng.randf_range(-meia, meia) * 1.4, _rng.randf_range(-alt, alt) * 0.35)
			_desenhar_raio(d, _raio_entre(p0, p1, 5, 5.0), forca * _rng.randf_range(0.6, 1.0), 0.45)
			d.draw_circle(p1, 2.2 * forca, Color.WHITE, forca)
		# um arco maior que escapa para fora do corpo de vez em quando
		if _rng.randf() < 0.45 * forca:
			var p0 := Vector2(a.position.x + _rng.randf_range(-meia, meia) * 0.5, _rng.randf_range(topo.y, pe.y))
			var ang := _rng.randf_range(0.0, TAU)
			_desenhar_raio(d, _raio_entre(p0, p0 + Vector2(cos(ang), sin(ang)) * _rng.randf_range(30.0, 55.0), 6, 7.0), forca * 0.8, 0.5)

func _explodir(pr: Projetil, alvo: Unidade) -> void:
	var centro := alvo.position + Vector2(0, -50)
	_impacto_magia(pr, alvo)
	var lista: Array = monstros if pr.lado == lado_jogador else herois   # explode nos inimigos do atirador
	for r in range(maxi(0, pr.linha - 1), mini(C.G.rows, pr.linha + 2)):
		for m in lista[r]:
			if m != alvo and not m.morto and (m.position + Vector2(0, -50)).distance_to(centro) <= pr.raio:
				ferir(m, pr.dano_area, null, pr.origem_id)
				m.levar_impacto(signf(m.position.x - centro.x) if m.position.x != centro.x else signf(pr.vel), 0.45)
	Sons.tocar(alvo.p.sons.get("impacto", "Mago/som/explosao"), 0.7)

## Efeito da magia acertando o corpo: estoura na FRENTE do inimigo, na altura em que a esfera voava,
## e o inimigo leva o tranco para trás (só visual).
func _impacto_magia(pr: Projetil, alvo: Unidade) -> void:
	var dir := signf(pr.vel)
	var ponto := Vector2(alvo.position.x - dir * 16.0, clampf(pr.pos.y, alvo.position.y - 110.0, alvo.position.y - 30.0))
	if fx_magia:
		fx_magia.impacto(ponto, dir, pr.raio, pr.tipo, alvo.position.y, alvo)
	else:
		explosoes.append([ponto, maxf(pr.raio, 34.0), 0.0, Color("7fb6ff")])
	alvo.levar_impacto(dir, 0.85 if pr.raio > 0.0 else 0.55)
	if pr.tipo == "magia_fogo":                       # a bola de fogo pega no inimigo: o mesmo som da flecha de fogo
		Sons.do_personagem(Catalogo.get_p(pr.origem_id), "fogo")

## Tiros do Engenheiro: clarão arcano no cano + flash na cabeça + rastros no ar
func _clarão_energia(pos: Vector2, dir: float) -> void:
	clarões.append({"pos": pos, "t": 0.0, "dir": dir})

## Impacto do laser do Engenheiro: descarga elétrica massiva + arcos + faíscas no ponto de contato.
func _impacto_energia(alvo: Unidade, ponto: Vector2, dano_tiro := 0) -> void:
	impactos.append({"pos": ponto, "t": 0.0, "lado": alvo.lado})
	# CHOQUE: o inimigo fica eletrocutado e leva +50% do dano do tiro em pulsos (tiro novo renova o choque)
	if dano_tiro > 0 and not alvo.morto:
		var extra := float(dano_tiro) * CHOQUE_PCT
		var achou := false
		for ch in choques:
			if ch.alvo == alvo:
				ch.dano = float(ch.dano) * (1.0 - float(ch.pulsos) / CHOQUE_PULSOS) + extra   # o que faltava + o novo
				ch.t = 0.0
				ch.pulsos = 0
				achou = true
				break
		if not achou:
			choques.append({"alvo": alvo, "t": 0.0, "dano": extra, "pulsos": 0, "semente": randi()})
	# faíscas extras que sobem
	for k in 3:
		rastros.append({"pos": ponto + Vector2(randf_range(-6, 6), randf_range(-2, 4)), "t": 0.0, "subindo": true})
	# faíscas arremessadas no sentido do tiro (o feixe atravessa o inimigo)
	var dir := signf(alvo.position.x - ponto.x)
	if dir == 0.0:
		dir = 1.0
	for k in 8:
		rastros.append({"pos": ponto, "t": randf_range(0.0, 0.08),
			"vel": Vector2(dir * randf_range(120.0, 300.0), randf_range(-120.0, 60.0))})
	# arcos elétricos que correm no corpo do inimigo
	for k in 4:
		var ang_arc := randf() * TAU
		var destino := ponto + Vector2(cos(ang_arc), sin(ang_arc)) * randf_range(15.0, 35.0)
		rastros.append({"pos": ponto, "t": randf_range(0.0, 0.04),
			"vel": (destino - ponto).normalized() * randf_range(60.0, 140.0), "eletrico": true})
	Sons.tocar("Elara/som/energia", 0.5)

## SOBRECARGA: a cada SOBRECARGA_CADA raios de um Engenheiro, a descarga salta do alvo para o próximo inimigo
## atrás dele (mesma linha) e depois para mais um — cada salto com choque e o raio ligando os dois.
func _sobrecarga(pr: Projetil, alvo: Unidade) -> void:
	if pr.origem_id != "engenheiro" or not is_instance_valid(pr.atirador):
		return
	var id := pr.atirador.get_instance_id()
	var n := int(sobrecarga.get(id, 0)) + 1
	sobrecarga[id] = n
	if n % SOBRECARGA_CADA != 0:
		return
	var s := dir_de(pr.lado)
	var na_grade := pr.lado != lado_jogador
	var lista: Array = herois[pr.linha] if na_grade else monstros[pr.linha]
	var de: Unidade = alvo
	var atingidos := [alvo]
	for k in SOBRECARGA_SALTOS.size():
		var prox: Unidade = null
		var melhor := INF
		for o in lista:
			if o.morto or o in atingidos or (na_grade and not o.ocupa_casa):
				continue
			var d: float = (o.position.x - de.position.x) * s
			if d > -10.0 and d <= SOBRECARGA_ALCANCE and d < melhor:
				melhor = d; prox = o
		if prox == null:
			break
		var dano_s := roundi(float(pr.dano) * float(SOBRECARGA_SALTOS[k]))
		correntes.append({"de": de.posicao_cabeca(), "para": prox.posicao_cabeca(), "t": -0.06 * k, "semente": randi()})
		ferir(prox, dano_s, null, "engenheiro", Color("5ff0ff"))
		_impacto_energia(prox, prox.posicao_cabeca(), dano_s)
		atingidos.append(prox)
		de = prox
	if atingidos.size() > 1:
		_texto(alvo.position + Vector2(0, -alvo.anim.ay * alvo.scale.y - 34), "SOBRECARGA!", Color("7ff7ff"), 24)
		Sons.tocar("Elara/som/energia", 0.8)

## Choque do raio: pulsos de dano elétrico (números azuis) enquanto o inimigo treme.
func _passo_choques(dt: float) -> void:
	var i := choques.size() - 1
	while i >= 0:
		var ch: Dictionary = choques[i]
		var a = ch.alvo
		if not is_instance_valid(a) or a.morto:
			if is_instance_valid(a):
				a.modulate = Color.WHITE
			choques.remove_at(i)
			i -= 1
			continue
		ch.t += dt
		# pulsos espalhados pela duração (o último no fim do choque)
		var devido := mini(CHOQUE_PULSOS, int(ch.t / (CHOQUE_DUR / CHOQUE_PULSOS) + 0.001))
		while ch.pulsos < devido:
			ch.pulsos += 1
			var cab: Vector2 = a.posicao_cabeca()
			for k in 4:                                    # faíscas que pulam do corpo a cada pulso
				rastros.append({"pos": Vector2(a.position.x + randf_range(-14, 14), lerpf(cab.y, a.position.y, randf())),
					"t": 0.0, "vel": Vector2(randf_range(-160, 160), randf_range(-220, -40))})
			ferir(a, float(ch.dano) / CHOQUE_PULSOS, null, "engenheiro", Color("5ff0ff"))
			if a.morto:
				break
		if (ch.t >= CHOQUE_DUR and ch.pulsos >= CHOQUE_PULSOS) or a.morto:
			a.modulate = Color.WHITE
			choques.remove_at(i)
		i -= 1

func _passo_ondas(dt: float) -> void:
	var i := ondas.size() - 1
	while i >= 0:
		var o: Onda = ondas[i]
		o.x += o.vel * dt
		o.idade += dt
		var lista: Array = monstros[o.linha] if o.lado == lado_jogador else herois[o.linha]
		var parou := false
		for alvo in lista:                               # DARIAN com o martelo na frente: a onda para nele
			if alvo.bloqueando() and absf(alvo.position.x - o.x) < 34.0:
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
			if alvo.morto or o.atingidos.has(alvo.get_instance_id()):
				continue
			if absf(alvo.position.x - o.x) < 30.0:
				o.atingidos[alvo.get_instance_id()] = true
				ferir(alvo, o.dano, null, "golemOssos" if o.tipo == "fogo" else "")
				if o.tipo == "fogo":                         # o fogo do Golem: labareda no corpo e o tranco
					explosoes.append([alvo.position + Vector2(0, -45), 44.0, 0.0, Color("ff7a1a")])
					alvo.levar_impacto(signf(o.vel), 0.8)
		if o.x > C.W + 40 or o.x < C.G.left - 40:
			if o.tipo == "fogo" and fx_ar:
				fx_ar.apagar_fogo(o.x0, o.x, C.linha_y(o.linha) - 2.0, o.idade, float(o.linha) * 1.3)
			ondas.remove_at(i)
		i -= 1

func _passo_orbes(dt: float) -> void:
	var i := orbes.size() - 1
	while i >= 0:
		var o: Dictionary = orbes[i]
		o.t += dt
		if o.voa:                                      # voando para o painel de energia
			var alvo: Vector2 = hud.alvo_energia()
			o.pos = o.pos.lerp(alvo, minf(1.0, dt * 8.0))
			if o.pos.distance_to(alvo) < 18:
				energia += int(o.valor)
				orbes.remove_at(i)
		else:
			if o.pos.y < o.alvo_y:                     # caindo do céu devagar, balançando
				o.pos.y = minf(o.alvo_y, o.pos.y + 75.0 * dt)
				if o.has("x0"):
					o.pos.x = o.x0 + sin(o.t * 2.2) * 14.0
				if o.pos.y >= o.alvo_y - 0.05:         # chegou (o Vector2 guarda menos casas que o alvo_y:
					o.alvo_y = o.pos.y                 # sem isso ele "nunca chegava" e a energia não sumia)
				o.t = 0.0 if o.pos.y < o.alvo_y else o.t
			if C.COLETA_AUTOMATICA > 0 and o.t > C.COLETA_AUTOMATICA:
				o.voa = true
			elif C.COLETA_AUTOMATICA <= 0 and o.t > C.energia_dura and not o.get("fixo", false):
				orbes.remove_at(i)
		i -= 1

# ================================================================= QUADRO (desenho e HUD)
func _process(dt: float) -> void:
	for tx in textos:
		if tx.ativo:
			tx.t += dt
			tx.pos.y -= 40.0 * dt
			if tx.t > 0.9:
				tx.ativo = false
	var i := explosoes.size() - 1
	while i >= 0:
		explosoes[i][2] += dt
		if explosoes[i][2] > 0.4:
			explosoes.remove_at(i)
		i -= 1
	var cr := correntes.size() - 1
	while cr >= 0:
		correntes[cr].t += dt
		if correntes[cr].t > 0.38:
			correntes.remove_at(cr)
		cr -= 1
	var ji := impactos.size() - 1
	while ji >= 0:
		impactos[ji].t += dt
		if impactos[ji].t > 0.42:
			impactos.remove_at(ji)
		ji -= 1
	var ci := clarões.size() - 1
	while ci >= 0:
		clarões[ci].t += dt
		if clarões[ci].t > 0.28:
			clarões.remove_at(ci)
		ci -= 1
	var ri := rastros.size() - 1
	while ri >= 0:
		rastros[ri].t += dt
		if rastros[ri].t > 0.55:
			rastros.remove_at(ri)
		else:
			if rastros[ri].get("subindo", false):
				rastros[ri].pos.y -= dt * 28.0
			if rastros[ri].has("vel"):                # faísca arremessada: anda e cai um pouco
				rastros[ri].vel.y += 260.0 * dt
				rastros[ri].pos += rastros[ri].vel * dt
		ri -= 1
	# eletrocutado: o corpo pisca azul / branco (tipo raio-x) e vai se acalmando
	for ch in choques:
		if is_instance_valid(ch.alvo) and not ch.alvo.morto:
			var forca := 1.0 - clampf(float(ch.t) / CHOQUE_DUR, 0.0, 1.0) * 0.6
			var pisca := int(float(ch.t) * 28.0) % 3
			ch.alvo.modulate = Color(1.7, 1.95, 2.0) if pisca == 0 else Color(1.0 - 0.35 * forca, 1.0 + 0.15 * forca, 1.0 + 0.6 * forca)
	if espiar_t > 0.0:
		espiar_t -= dt
	if banner_t > 0.0:
		banner_t -= dt
		lbl_banner.visible = banner_t > 0.0
	_atualizar_hud()
	desenho.queue_redraw()
	for n_l in _chao_linhas:
		n_l.queue_redraw()

func _desenhar() -> void:
	var d := desenho
	# barras de vida (só de quem levou golpe há pouco)
	for lista in [herois, monstros]:
		for l in lista:
			for u in l:
				if u.morto or u.mostra_barra <= 0.0:
					continue
				var alt: float = u.p.barra_y if u.p.barra_y > 0 else u.anim.ay * u.scale.y + 10.0
				var w := 54.0
				var pos: Vector2 = u.position + Vector2(-w / 2, -alt)
				var k: float = clampf(u.vida / u.vida_max, 0.0, 1.0)
				d.draw_rect(Rect2(pos, Vector2(w, 7)), Color(0, 0, 0, 0.6))
				d.draw_rect(Rect2(pos + Vector2(1, 1), Vector2((w - 2) * k, 5)),
					Color("5fd36b") if u.lado == lado_jogador else Color("ff5a4a"))
	# projéteis
	for pr in projeteis:
		if not pr.ativo:
			continue
		match pr.tipo:
			"flecha", "flecha_inimiga":
				var alfa_f := 1.0 if not pr.fixado else clampf((1.6 - pr.t_fixado) / 0.4, 0.0, 1.0)
				desenhar_flecha(d, pr.pos, signf(pr.vel), pr.tipo == "flecha_inimiga", alfa_f, pr.fixado, pr.t, pr.fogo)
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
				_rng.seed = pr.semente + quadro * 7919
				var amp := 11.0 * (0.6 + 0.4 * alfa)
				var pts := _raio_curva(pr, pr.origem.x, pr.pos.x, amp)
				_desenhar_raio(d, pts, alfa, 1.0)
				var pts2 := _raio_curva(pr, pr.origem.x, pr.pos.x, amp * 1.3)
				_desenhar_raio(d, pts2, alfa * 0.45, 0.55)
				# GALHOS: raiozinhos que escapam do raio principal
				var n_galhos := 4 if not somendo else 2
				for g in n_galhos:
					var idx := _rng.randi_range(1, maxi(1, pts.size() - 2))
					var p0: Vector2 = pts[idx]
					var ang := _rng.randf_range(-1.1, 1.1) + (0.0 if dir > 0.0 else PI)
					var comp_g := _rng.randf_range(18.0, 46.0)
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
				if not (FxMagia.eh_magia(pr.tipo) and fx_magia):   # (a esfera da magia é desenhada no fx_magia, com luz aditiva)
					var cor := Color("7fb6ff")
					if pr.tipo == "magia_fogo": cor = Color("ff8a2a")
					elif pr.tipo == "magia_sombra": cor = Color("9b6bff")
					var pulso := 1.0 + 0.15 * sin(pr.t * 20.0)
					d.draw_circle(pr.pos, 16.0 * pulso, Color(cor, 0.25))
					d.draw_circle(pr.pos, 9.0 * pulso, cor)
					d.draw_circle(pr.pos, 4.0, Color.WHITE)
	# (as ondas de terra / ossos / fogo são desenhadas em _desenhar_ondas_linha: na ordem de profundidade)
	# explosões
	for e in explosoes:
		var kk: float = e[2] / 0.4
		d.draw_circle(e[0], e[1] * (0.4 + 0.6 * kk), Color(e[3], 0.45 * (1.0 - kk)))
	_desenhar_choques(d)
	# SOBRECARGA: raio grosso saltando de um inimigo para o outro (tremula e some)
	for co in correntes:
		var tc: float = co.t
		if tc < 0.0:
			continue
		var al := 1.0 - tc / 0.38
		_rng.seed = int(co.semente) + int(tc * 30.0) * 7919
		var pts := _raio_entre(co.de, co.para, 9, 16.0 * al + 4.0)
		_desenhar_raio(d, pts, al, 1.3)
		_desenhar_raio(d, _raio_entre(co.de, co.para, 7, 22.0), al * 0.45, 0.6)
		for ponta in [co.de, co.para]:
			d.draw_circle(ponta, 20.0 * al + 6.0, Color("40eaff", 0.35 * al))
			d.draw_circle(ponta, 8.0 * al + 2.0, Color(1, 1, 1, 0.9 * al))
	# — rastros do feixe (pontinhos que ficam no ar) —
	for r in rastros:
		var ta: float = 1.0 - float(r.t) / 0.55
		if r.get("subindo", false):
			d.draw_circle(r.pos, 2.5 * ta + 0.6, Color("80f0ff", 0.60 * ta))
			d.draw_circle(r.pos, 1.2 * ta + 0.4, Color.WHITE, 0.95 * ta)
		elif r.get("eletrico", false):                  # arco elétrico que corre no corpo
			var v: Vector2 = r.vel
			var traco: Vector2 = v.normalized() * minf(12.0, v.length() * 0.06) * ta
			# linha torta tipo raio
			var meio: Vector2 = r.pos + traco * 0.5 + Vector2(randf_range(-2, 2), randf_range(-2, 2))
			var pts := PackedVector2Array([r.pos, meio, r.pos + traco])
			d.draw_polyline(pts, Color("80f0ff", 0.8 * ta), 1.5, false)
			d.draw_polyline(pts, Color("ffffff", 0.5 * ta), 0.7, false)
			d.draw_circle(r.pos + traco, 1.5 * ta, Color.WHITE, 0.9 * ta)
		elif r.has("vel"):                          # faísca arremessada pelo impacto: risco na direção do voo
			var v: Vector2 = r.vel
			var traco: Vector2 = v.normalized() * minf(10.0, v.length() * 0.05) * ta
			d.draw_line(r.pos - traco, r.pos, Color("40eaff", 0.9 * ta), 2.0 * ta + 0.4)
			d.draw_line(r.pos - traco * 0.5, r.pos, Color("ffffff", 0.6 * ta), 1.0 * ta)
			d.draw_circle(r.pos, 1.6 * ta + 0.3, Color.WHITE, 0.95 * ta)
		else:
			d.draw_circle(r.pos, 3.2 * ta + 0.8, Color("00d4ff", 0.25 * ta))
			d.draw_circle(r.pos, 1.5 * ta + 0.4, Color("e8fffd", 0.7 * ta))
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
		_rng.seed = int(cl.t * 30.0) * 31337 + int(p3.x * 7.0 + p3.y)
		for q in 4:
			var ang_q := _rng.randf_range(0.0, TAU)
			_desenhar_raio(d, _raio_entre(p3, p3 + Vector2(cos(ang_q), sin(ang_q)) * _rng.randf_range(12.0, 28.0), 3, 4.0), ac, 0.35)
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
	# energia (o mesmo ícone do painel: círculo vermelho com raio)
	var agora := Time.get_ticks_msec() / 1000.0
	for o in orbes:
		if not o.voa and not o.get("fixo", false) and not C.energia_visivel(o.t, agora):
			continue                                   # piscando: vai sumir
		var pul := 1.0 + 0.06 * sin(Time.get_ticks_msec() / 160.0)
		hud.icone_energia(d, o.pos, 21.0 * pul)
	# textos de dano
	var fonte := ThemeDB.fallback_font
	for tx in textos:
		if tx.ativo:
			var a := 1.0 - tx.t / 0.9
			d.draw_string_outline(fonte, tx.pos, tx.txt, HORIZONTAL_ALIGNMENT_CENTER, -1, tx.tam, 5, Color(0, 0, 0, a))
			d.draw_string(fonte, tx.pos, tx.txt, HORIZONTAL_ALIGNMENT_CENTER, -1, tx.tam, Color(tx.cor, a))
	if mostrar_grade:
		var gg := C.G
		for r in gg.rows + 1:
			d.draw_line(Vector2(gg.left, gg.top + r * gg.ch), Vector2(gg.left + gg.cols * gg.cw, gg.top + r * gg.ch), Color(1, 1, 1, 0.5), 1.0)
		for cc in gg.cols + 1:
			d.draw_line(Vector2(gg.left + cc * gg.cw, gg.top), Vector2(gg.left + cc * gg.cw, gg.top + gg.rows * gg.ch), Color(1, 1, 1, 0.5), 1.0)
	# LUZ DA LINHA E DA COLUNA: mostra onde o herói vai ficar e qual linha ele vai defender
	if carta_sel >= 0:
		var c := C.casa_em(get_local_mouse_position())
		if c.x >= 0:
			var g := C.G
			var livre: bool = casas[c.x][c.y] == null
			var cor := Color(1, 1, 1) if livre else Color(1, 0.35, 0.3)
			d.draw_rect(Rect2(g.left, g.top + c.y * g.ch, g.cw * g.cols, g.ch), Color(cor, 0.12))      # linha
			d.draw_rect(Rect2(g.left + c.x * g.cw, g.top, g.cw, g.ch * g.rows), Color(cor, 0.10))      # coluna
			var casa := Rect2(g.left + c.x * g.cw, g.top + c.y * g.ch, g.cw, g.ch)
			d.draw_rect(casa, Color(cor, 0.22))
			d.draw_rect(casa, Color(cor, 0.6), false, 2.0)
			if livre:                                  # "fantasma" do herói na casa
				var p := cartas_dados[carta_sel]
				var a := p.anim_qualquer(["parado", "defender", "andar"])
				if a and a.textura:
					var k := p.escala * a.escala
					var pes := Vector2(C.cel_x(c.x), C.linha_y(c.y))
					d.draw_texture_rect_region(a.textura, Rect2(pes - Vector2(a.ax, a.ay) * k, Vector2(a.cw, a.ch) * k), a.retangulo(0), Color(1, 1, 1, 0.5))

# ================================================================= MENU (pausa)
## Abre a janela de pausa: o jogo para e aparecem os botões Continuar / Voltar ao menu.
func mostrar_menu_pausa() -> void:
	if painel_menu_visivel or estado in ["fim_nivel", "derrota"]:
		return
	if selecao != null and selecao.visible:            # janela de cartas aberta: ainda não começou
		return
	get_tree().paused = true
	painel_menu_visivel = true
	_montar_botoes_painel([["Continuar", Color("ffc43a"), _menu_continuar], ["Voltar ao menu", Color("4a5fae"), _menu_ir]])
	painel_menu.visible = true
	painel_menu.queue_redraw()

func _menu_continuar() -> void:
	get_tree().paused = false
	painel_menu_visivel = false
	painel_menu.visible = false

func _menu_ir() -> void:
	get_tree().paused = false
	painel_menu_visivel = false
	Conta.estou("menu")
	get_tree().change_scene_to_file("res://cenas/intro.tscn")

func _montar_botoes_painel(botoes: Array) -> void:
	for b in painel_menu_bons:
		b.queue_free()
	painel_menu_bons.clear()
	var y := 420.0
	var x0 := C.W / 2.0 - (botoes.size() * 230.0 - 20.0) / 2.0
	for i in botoes.size():
		var d: Array = botoes[i]
		var b := Button.new()
		b.text = d[0]
		b.position = Vector2(x0 + i * 230.0, y)
		b.size = Vector2(210, 58)
		b.add_theme_font_override("font", hud.f_titulo)
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
		painel_menu.add_child(b)
		painel_menu_bons.append(b)

func _desenhar_painel_menu() -> void:
	var tela := C.tela_toda(painel_menu)              # (celular largo: cobre as laterais também)
	painel_menu.draw_rect(tela, Color(0.02, 0.02, 0.06, 0.6))
	var r := Rect2(C.W / 2.0 - 300, 170, 600, 330)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2c3874")
	sb.set_corner_radius_all(26)
	sb.set_border_width_all(4)
	sb.border_color = Color("141a36")
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 8)
	painel_menu.draw_style_box(sb, r)
	painel_menu.draw_string_outline(hud.f_titulo, Vector2(r.position.x, r.position.y + 78), "PAUSA", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 58, 14, Color("24130a"))
	painel_menu.draw_string(hud.f_titulo, Vector2(r.position.x, r.position.y + 78), "PAUSA", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 58, Color("fff4d6"))
	painel_menu.draw_multiline_string_outline(hud.f_texto, Vector2(r.position.x + 30, r.position.y + 130), "A batalha está parada.", HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 60, 20, -1, 6, Color("24130a"))
	painel_menu.draw_multiline_string(hud.f_texto, Vector2(r.position.x + 30, r.position.y + 130), "A batalha está parada.", HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 60, 20, -1, Color("eef0ff"))

# ================================================================= TOQUES
func _unhandled_input(ev: InputEvent) -> void:
	var pos := C.pos_toque(self, ev)
	if not pos.is_finite():
		return
	# 1) pegar energia (o HUD já tentou; aqui é só segurança)
	if pegar_energia(pos):
		return
	# 2) casa da grade
	var casa := C.casa_em(pos)
	if casa.x < 0:
		return
	var agora := Time.get_ticks_msec() / 1000.0
	if casas[casa.x][casa.y] != null:
		# tocou num personagem: abre o MENU dele (tocar de novo fecha)
		if carta_sel < 0 and menu_unidade:
			menu_unidade.tocou(casas[casa.x][casa.y])
		ultimo_toque = {"casa": casa, "t": agora}
		return
	if menu_unidade and menu_unidade.aberto() and carta_sel < 0:
		menu_unidade.fechar()                            # tocou no chão vazio: fecha o menu
		return
	ultimo_toque = {"casa": casa, "t": agora}
	colocar_heroi(casa)

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

## FOTO PARA O PAINEL (assistir ao vivo — 29_painel_assistir.sql): castelo, energia, onda e cada personagem em campo.
## [linha, x, lado (0 heroes / 1 monsters), id, vida %]. Pequena (cabe em ~2 KB).
func foto_ao_vivo() -> Dictionary:
	var u: Array = []
	for lista in [herois, monstros]:
		for l in lista:
			for x in l:
				if is_instance_valid(x) and not x.morto and u.size() < 80:
					u.append([x.linha, roundi(x.position.x), 0 if x.lado == "heroes" else 1, x.p.id, roundi(100.0 * x.vida / maxf(1.0, x.vida_max))])
	return {"m": "campanha", "w": C.W, "gl": C.G.left, "gc": C.G.cw, "lj": lado_jogador, "cv": roundi(vida_castelo), "cm": C.VIDA_CASTELO,
		"e": energia, "n": nivel, "o": mini(onda_idx + 1, fase.ondas.size() if fase else 1), "ot": fase.ondas.size() if fase else 1,
		"st": estado, "p": snappedf(progresso_nivel(), 0.01),
		"fu": fundo.texture.resource_path.get_file().get_basename() if fundo and fundo.texture else "", "u": u}

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

## Inimigo mais perto que JÁ APARECEU na arena (na linha e no lado para onde a tropa olha). Quem ataca DE LONGE
## (arqueiros, magos, Engenheiro, Bombardeiro, Esqueleto Mago, raio do Golem) começa a atacar assim que ele aparece.
func alvo_visivel(u: Unidade) -> Unidade:
	var s := u._dir()
	var melhor: Unidade = null
	var melhor_d := INF
	var lista: Array = monstros[u.linha] if u.lado == lado_jogador else herois[u.linha]
	for o in lista:
		if o.morto or (u.lado != lado_jogador and not o.ocupa_casa):
			continue
		if o.position.x > C.W - MARGEM_VISIVEL or o.position.x < MARGEM_VISIVEL:
			continue                                         # ainda entrando pela borda
		var d: float = (o.position.x - u.position.x) * s
		if d >= -10.0 and d < melhor_d:
			melhor = o; melhor_d = d
	return melhor