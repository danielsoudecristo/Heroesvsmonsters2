extends Control
## ENTRADA DO JOGO, estilo cartoon (igual ao site, com mais capricho):
##   1) CARREGANDO: o logo desce, dicas trocando, barra dourada. Carrega o jogo DE VERDADE em segundo plano.
##      Quando termina: "Clique para começar".
##   2) ESCOLHA SEU LADO: Heroes x Monsters, com o raio no meio. (Só aparece se ainda não escolheu.)
##   3) MENU: cartão do jogador, 6 botões, bônus do dia, botão social e uma batalha acontecendo no fundo.
## LEVE: 1 imagem de fundo + 1 partícula (brasas). Todo o resto é desenhado à mão (sem dezenas de nós).
## Teclado: setas + Enter, Esc volta, F tela cheia. Celular: toque. Botão "voltar" do Android funciona.

const W := 1280.0
const H := 720.0
const CENA_JOGO := "res://cenas/campanha.tscn"
const CENA_PVP := "res://cenas/pvp.tscn"

# ---------------------------------------------------------------- AJUSTES (iguais ao intro.js)
const TEMPO_MINIMO_CARGA := 3.2          ## segundos mínimos da tela de carregamento
const TROCA_DICA := 3.5                  ## segundos de cada dica
const DICAS := [
	"Clique nas energias que caem do céu para ganhar mais guerreiros.",
	"A Elara gera energia sozinha: coloque ela primeiro.",
	"Clique num guerreiro na arena para evoluir; dois cliques rápidos tiram ele.",
	"O Esqueleto Titã aparece no fim de cada nível. Não deixe ele chegar ao portão!",
	"Tecla H mostra ou esconde as cartas. Tecla F deixa em tela cheia.",
]
const FUNDOS := {
	"carga": ["Menu/carregando_largo", "Menu/carregando"],
	"lado": ["Menu/escolher_lado_largo", "Menu/escolher_lado"],
	"heroes": ["Fundo/arena_guerreiro_noite_largo", "Fundo/arena_guerreiro_noite", "Fundo/fundo_do_jogo2"],
	"monsters": ["Fundo/arena_monsters_noite_largo", "Fundo/arena_monsters_noite", "Fundo/arena_guerreiro_noite_largo", "Fundo/arena_guerreiro_noite"],
}
## Raio da tela de lado: x no topo e embaixo (mesma diagonal da imagem escolher_lado).
const RAIO_TOPO := 0.546 * W
const RAIO_BAIXO := 0.452 * W

## BATALHA DO MENU (igual ao site): x, y = pés na tela de 1280x720; t = tamanho; alvo = em quem bate/atira.
const BATALHA := [
	{"id": "elara", "h": true, "x": 335, "y": 300, "t": 0.70},
	{"id": "arqueiro", "h": true, "x": 335, "y": 398, "t": 0.80, "alvo": "esqueletoArqueiro"},
	{"id": "mago", "h": true, "x": 322, "y": 500, "t": 0.90, "alvo": "esqueletoMago"},
	{"id": "nick", "h": true, "x": 300, "y": 615, "t": 1.02, "alvo": "esqueleto"},
	{"id": "esqueleto", "h": false, "x": 405, "y": 615, "t": 1.02, "alvo": "nick"},
	{"id": "magoFogo", "h": true, "x": 872, "y": 432, "t": 0.86, "alvo": "esqueletoFogo"},
	{"id": "esqueletoFogo", "h": false, "x": 1010, "y": 432, "t": 0.86, "alvo": "magoFogo"},
	{"id": "protetor", "h": true, "x": 895, "y": 542, "t": 0.96, "alvo": "esqueletoProtetor"},
	{"id": "esqueletoProtetor", "h": false, "x": 1000, "y": 542, "t": 0.96, "alvo": "protetor"},
	{"id": "sentinela", "h": true, "x": 935, "y": 655, "t": 1.08, "alvo": "esqueletoTita"},
	{"id": "esqueletoTita", "h": false, "x": 1092, "y": 655, "t": 1.08, "alvo": "sentinela"},
	{"id": "esqueletoArqueiro", "h": false, "x": 1215, "y": 360, "t": 0.76, "alvo": "arqueiro"},
	{"id": "esqueletoMago", "h": false, "x": 1228, "y": 478, "t": 0.86, "alvo": "mago"},
]
const TIRO := {"arqueiro": "flecha", "esqueletoArqueiro": "flechaM", "mago": "magia", "esqueletoMago": "magiaM", "magoFogo": "fogo"}
const COR_TIRO := {"flecha": Color("fff2c4"), "flechaM": Color("e8dfc8"), "magia": Color("7fd2ff"), "magiaM": Color("c08cff"), "fogo": Color("ff8a2a")}
const PAUSA_BATALHA := Vector2(0.6, 1.8)
const ESCURECER := 0.18

## BOTÕES DO MENU. "breve" = ainda não existe no Godot (mostra a etiqueta "em breve").
const BOTOES := [
	{"id": "novo", "txt": "Novo jogo", "icone": "espada", "principal": true},
	{"id": "pvp", "txt": "Batalha PvP", "icone": "espadas"},
	{"id": "personagens", "txt": "Personagens", "icone": "elmo", "breve": true},
	{"id": "ranking", "txt": "Ranking e ligas", "icone": "barras", "breve": true},
	{"id": "opcoes", "txt": "Opções", "icone": "engrenagem"},
	{"id": "lado", "txt": "Trocar de lado", "icone": "trocar"},
]
const BOT_W := 420.0
const BOT_H := 64.0
const BOT_Y0 := 222.0
const BOT_PASSO := 76.0

# ---------------------------------------------------------------- CORES
const CONTORNO := Color("24130a")
const CREME := Color("fff4d6")
const OURO1 := Color("fff3b0")
const OURO2 := Color("f6c343")
const OURO3 := Color("b8740f")
const VERDE1 := Color("eaffb0")
const VERDE2 := Color("8be03c")
const VERDE3 := Color("2f7d16")
const NAVY := Color("141a36")
const TEMA := {
	"heroes": {"b1": Color("6f86d6"), "b2": Color("3a4a91"), "ico1": Color("9fb2ff"), "ico2": Color("2c3874"), "foco": Color(1, 0.906, 0.549, 0.55),
		"p1": Color("ffe98a"), "p2": Color("f0a21c"), "pc": Color("4a2a06"), "pico1": Color("fff6c8"), "pico2": Color("d08a12")},
	"monsters": {"b1": Color("8a6fc9"), "b2": Color("523a8f"), "ico1": Color("c9b3ff"), "ico2": Color("3a2768"), "foco": Color(0.667, 0.941, 0.431, 0.55),
		"p1": Color("e2ff9e"), "p2": Color("6fc72a"), "pc": Color("123006"), "pico1": Color("f2ffd6"), "pico2": Color("4a9e1f")},
}

enum Tela { CARGA, LADO, MENU, LOGIN }

# ---------------------------------------------------------------- estado
var tela := Tela.CARGA
var t_tela := 0.0
var relogio := 0.0
var O := Vector2.ZERO                    # onde fica o "palco" 1280x720 dentro da tela (telas mais largas/altas)
var _ci: CanvasItem                      # em quem os ajudantes de desenho desenham agora

var f_titulo: Font
var f_texto: Font
var fundo: TextureRect
var brasas: CPUParticles2D
var logo: Node2D
var palavras: Array[Letreiro] = []
var placas: Array[Node2D] = []
var topo: Control
var _texturas := {}                      # caminho -> Texture2D (ou null)
var _sb_cache := {}

# carregamento
var _pedidos: Array[String] = []
var _cena_jogo: PackedScene
var progresso := 0.0
var pronta := false
var pronta_t := 0.0
var dica_i := 0
var dica_t := 0.0

# logo
var logo_y := -300.0
var logo_k := 1.0
var logo_a := 0.0
var brilho_t := -1.0                     # >= 0: brilho passando pelas letras

# fade (cortina preta entre as telas)
var cortina := 1.0
var _indo_para := -1
var _depois_cortina := Callable()
var clarao := 0.0                        # clarão branco do raio

# lado
var foco_lado := -1                      # -1 nenhum, 0 heroes, 1 monsters
var escolhendo := false
var raio_forca := 0.0
var _raio_t := 0.0
var _raio_brilho := PackedVector2Array()
var _raio_miolo := PackedVector2Array()
var _galhos: Array[PackedVector2Array] = []
var _escurece := [0.0, 0.0]
var _zoom_lado := 0.0

# menu
var foco := 0
var _hov: Array[float] = [0, 0, 0, 0, 0, 0]
var _aperto: Array[float] = [0, 0, 0, 0, 0, 0]
var _acao_pendente := ""
var _acao_t := 0.0
var aviso := ""
var aviso_t := 0.0
var opcoes_aberta := false
var conta: Node                          # autoload "Conta" (login com Google)
var _apagar_t := 0.0                     # confirmação do "Apagar conta" (toque 2 vezes)
var _saudou := false
var _espera_aberta := false              # login começou pelas Opções (mostra a janelinha no menu)
var busca_ativa := false                 # janela "Procurando adversário..."
var busca_t := 0.0
var busca_achou := -1.0                  # >= 0: já achou (segundos desde que achou)
var busca_nome := ""
var busca_online := false                # procurando uma pessoa de verdade no servidor (precisa estar com a conta)
var busca_pedindo := false               # tem uma pergunta ao servidor em andamento
var busca_prox := 0.0                    # tempo até perguntar de novo
var busca_desistiu := false              # o tempo acabou: saindo da fila para jogar contra o bot
var busca_sala := {}                     # sala achada (vazio = contra o bot)
var _sair_t := 0.0
var lutadores: Array[Dictionary] = []
var tiros: Array = []
var faiscas: Array = []
var icones := {}

# sons (feitos no código: clique e trovão, como no site — sem arquivos)
var _som_clique: AudioStreamPlayer
var _som_trovao: AudioStreamPlayer
var _wav_fraco: AudioStreamWAV
var _wav_forte: AudioStreamWAV
var _sons_prontos := false

# =================================================================== INÍCIO
func _ready() -> void:
	Perfil.carregar()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().quit_on_go_back = false
	f_titulo = _fonte(["Fontes/lilita-one-latin-400-normal.woff2"])
	f_texto = _fonte(["Fontes/fredoka-latin-700-normal.woff2", "Fontes/fredoka-latin-600-normal.woff2"])
	var s := get_node_or_null("/root/Sons")
	if s:
		s.ligado = Perfil.som

	fundo = TextureRect.new()
	fundo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fundo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fundo.show_behind_parent = true
	add_child(fundo)

	brasas = _criar_brasas()
	brasas.show_behind_parent = true
	add_child(brasas)

	_criar_logo()
	_criar_placas()
	conta = get_node_or_null("/root/Conta")
	if conta:
		conta.mudou.connect(_conta_mudou)
		conta.erro.connect(func(m: String): _avisar(m))

	topo = Control.new()
	topo.set_anchors_preset(Control.PRESET_FULL_RECT)
	topo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	topo.draw.connect(_desenhar_topo)
	add_child(topo)

	_som_clique = AudioStreamPlayer.new()
	_som_trovao = AudioStreamPlayer.new()
	add_child(_som_clique)
	add_child(_som_trovao)
	icones = _montar_icones()
	dica_i = randi() % DICAS.size()

	# carrega o jogo em segundo plano enquanto a barra anda (fichas + folhas dos personagens, a arena e os fundos)
	var cat := get_node_or_null("/root/Catalogo")
	if cat and cat.has_method("pedir_em_segundo_plano"):
		cat.pedir_em_segundo_plano()
	for c in [CENA_JOGO, CENA_PVP]:
		if ResourceLoader.exists(c) and ResourceLoader.load_threaded_request(c, "", true) == OK:
			_pedidos.append(c)
	for k in ["lado", "heroes", "monsters"]:
		var cam := _achar_imagem(FUNDOS[k])
		if cam != "" and not _pedidos.has(cam) and ResourceLoader.load_threaded_request(cam) == OK:
			_pedidos.append(cam)

	if Perfil.ja_entrou:                 # voltou do jogo: direto para o menu
		_entrar(Tela.MENU if Perfil.lado != "" else Tela.LADO)
		logo_y = 26.0
		logo_a = 1.0
	else:
		_entrar(Tela.CARGA)

func _exit_tree() -> void:
	get_tree().quit_on_go_back = true

func _fonte(opcoes: Array) -> Font:
	for o in opcoes:
		var c: String = "res://assets/" + o
		if ResourceLoader.exists(c):
			return load(c)
	return ThemeDB.fallback_font

var _achados := {}
func _achar_imagem(nomes: Array) -> String:
	var chave := str(nomes)
	if _achados.has(chave):
		return _achados[chave]
	_achados[chave] = ""
	for n in nomes:
		for ext in ["jpg", "png", "webp"]:
			var c := "res://assets/%s.%s" % [n, ext]
			if ResourceLoader.exists(c):
				_achados[chave] = c
				return c
	return ""

func _textura(nomes: Array) -> Texture2D:
	var c := _achar_imagem(nomes)
	if c == "":
		return null
	if not _texturas.has(c):
		if _pedidos.has(c):
			_texturas[c] = ResourceLoader.load_threaded_get(c)   # já veio em segundo plano
			_pedidos.erase(c)
		else:
			_texturas[c] = load(c)
	return _texturas[c]

func _criar_brasas() -> CPUParticles2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0, 1) ** 1.6))
	var p := CPUParticles2D.new()
	p.texture = ImageTexture.create_from_image(img)
	p.amount = 34
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0, -1)
	p.spread = 22.0
	p.gravity = Vector2(6, -6)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 75.0
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.38
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.55, 0.15, 0))
	g.set_color(1, Color(1, 0.4, 0.1, 0))
	g.add_point(0.15, Color(1, 0.8, 0.35, 0.95))
	g.add_point(0.7, Color(1, 0.5, 0.15, 0.6))
	p.color_ramp = g
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = m
	return p

func _criar_logo() -> void:
	logo = Node2D.new()
	logo.draw.connect(_desenhar_battlefront)
	add_child(logo)
	var dados := [["Heroes", 86, Letreiro.Cor.OURO, 15, Color("1b0f06")], ["vs", 46, Letreiro.Cor.PRATA, 10, Color("1b0f06")],
		["Monsters", 86, Letreiro.Cor.VERDE, 15, Color("07140a")]]
	var larg: Array[float] = []
	for d in dados:
		var l := Letreiro.new()
		l.texto = d[0]
		l.tamanho = d[1]
		l.cor = d[2]
		l.contorno = d[3]
		l.cor_contorno = d[4]
		l.fonte = f_titulo
		logo.add_child(l)
		palavras.append(l)
		larg.append(l.largura())
	var total: float = larg[0] + larg[1] + larg[2] + 36.0
	var x := -total / 2.0
	for i in 3:
		palavras[i].position = Vector2(x + larg[i] / 2.0, 82.0 + (-10.0 if i == 1 else 0.0))
		x += larg[i] + 18.0
	palavras[1].rotation_degrees = -6.0

func _criar_placas() -> void:
	for i in 2:
		var n := Node2D.new()
		n.draw.connect(_desenhar_placa.bind(i))
		add_child(n)
		var l := Letreiro.new()
		l.texto = "Heroes" if i == 0 else "Monsters"
		l.tamanho = 70
		l.cor = Letreiro.Cor.OURO if i == 0 else Letreiro.Cor.VERDE
		l.contorno = 10
		l.cor_contorno = Color("120a04")
		l.sombra = 4.0
		l.fonte = f_titulo
		n.add_child(l)
		placas.append(n)

# =================================================================== TELAS
func _entrar(nova: int) -> void:
	tela = nova
	t_tela = 0.0
	match tela:
		Tela.CARGA, Tela.LOGIN:
			fundo.texture = _textura(FUNDOS.carga)
		Tela.LADO:
			fundo.texture = _textura(FUNDOS.lado)
			foco_lado = -1
			escolhendo = false
			_zoom_lado = 0.0
			_escurece = [0.0, 0.0]
		Tela.MENU:
			var lado := Perfil.lado if Perfil.lado != "" else "heroes"
			fundo.texture = _textura(FUNDOS[lado])
			if fundo.texture == null:
				fundo.texture = _textura(FUNDOS.heroes)
			foco = 0
			opcoes_aberta = false
			if lutadores.is_empty():
				_montar_batalha()
	for p in placas:
		p.visible = tela == Tela.LADO
	RenderingServer.set_default_clear_color(Color("05040a"))

func _ir(nova: int, depois := Callable()) -> void:
	if _indo_para >= 0:
		return
	_indo_para = nova
	_depois_cortina = depois

func _process(dt: float) -> void:
	relogio += dt
	t_tela += dt
	O = ((size - Vector2(W, H)) / 2.0).floor()
	brasas.position = Vector2(size.x / 2.0, size.y + 12)
	brasas.emission_rect_extents = Vector2(size.x / 2.0, 6)

	if not _sons_prontos and relogio > 0.15:
		_criar_sons()

	# cortina entre telas
	if _indo_para >= 0:
		cortina = move_toward(cortina, 1.0, dt * 3.5)
		if cortina >= 1.0:
			var n := _indo_para
			_indo_para = -1
			if _depois_cortina.is_valid():
				var c := _depois_cortina
				_depois_cortina = Callable()
				c.call()
				if not is_inside_tree():
					return
			_entrar(n)
	else:
		cortina = move_toward(cortina, 0.0, dt * 3.0)
	clarao = move_toward(clarao, 0.0, dt * 2.2)
	if aviso_t > 0:
		aviso_t -= dt
	if _sair_t > 0:
		_sair_t -= dt
	if _apagar_t > 0:
		_apagar_t -= dt
	if _espera_aberta and conta and not conta.esperando_login and conta.status != "carregando":
		_espera_aberta = false

	match tela:
		Tela.CARGA: _atualizar_carga(dt)
		Tela.LADO: _atualizar_lado(dt)
		Tela.MENU: _atualizar_menu(dt)
	_atualizar_logo(dt)

	# fundo: aproxima bem devagar (no lado escolhido, avança para o lado)
	var z := 1.0 + 0.025 * (0.5 - 0.5 * cos(relogio * 0.18))
	if tela == Tela.LADO:
		z = 1.0 + _zoom_lado * 0.08
		fundo.pivot_offset = Vector2(size.x * (0.25 if foco_lado == 0 else 0.75), size.y * 0.6)
	else:
		fundo.pivot_offset = size / 2.0
	fundo.scale = Vector2(z, z)

	queue_redraw()
	topo.queue_redraw()
	logo.queue_redraw()
	for p in placas:
		if p.visible:
			p.queue_redraw()

# ---------------------------------------------------------------- 1) carregamento
func _atualizar_carga(dt: float) -> void:
	var real := 1.0
	if not _pedidos.is_empty():
		var soma := 0.0
		var feitos := 0
		for c in _pedidos:
			var arr := []
			var st := ResourceLoader.load_threaded_get_status(c, arr)
			if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				soma += 1.0
				feitos += 1
			else:
				soma += float(arr[0]) if arr.size() > 0 else 0.0
		real = soma / _pedidos.size()
	var cat := get_node_or_null("/root/Catalogo")
	if cat and cat.has_method("progresso"):
		real = (real + 3.0 * cat.progresso()) / 4.0      # os personagens são a parte mais pesada
	var alvo := minf(real, t_tela / TEMPO_MINIMO_CARGA)
	progresso = move_toward(progresso, alvo, dt * 0.9)
	if not pronta and progresso >= 0.999:
		pronta = true
		pronta_t = 0.0
		if _cena_jogo == null and _pedidos.has(CENA_JOGO):
			_cena_jogo = ResourceLoader.load_threaded_get(CENA_JOGO)
			_pedidos.erase(CENA_JOGO)
		var cat2 := get_node_or_null("/root/Catalogo")
		if cat2:
			cat2.get_p("")                      # termina de pegar as fichas que vieram em segundo plano
	if pronta:
		pronta_t += dt
	dica_t += dt
	if dica_t >= TROCA_DICA:
		dica_t = 0.0
		dica_i = (dica_i + 1) % DICAS.size()
	if t_tela > 2.1 and brilho_t < 0 and t_tela < 3.0:
		brilho_t = 0.0

func _comecar() -> void:
	if not pronta or _indo_para >= 0:
		return
	_clique(true)
	Perfil.ja_entrou = true
	if conta and not conta.logado() and conta.status != "carregando" and not Perfil.convidado_ok:
		_ir(Tela.LOGIN)                    # 1ª vez: entrar com Google ou jogar como convidado (igual ao site)
	else:
		_depois_da_conta()

func _depois_da_conta() -> void:
	_ir(Tela.LADO if Perfil.lado == "" else Tela.MENU)

# ---------------------------------------------------------------- CONTA (login com Google)
func _conta_mudou() -> void:
	if conta.status == "conectado" and not _saudou:
		_saudou = true
		_avisar("Bem-vindo, %s!" % Perfil.nome.get_slice(" ", 0))
		if tela == Tela.LOGIN:
			_depois_da_conta()
	elif not conta.logado():
		_saudou = false

func _entrar_google() -> void:
	if conta == null:
		_avisar("Falta registrar o autoload \"Conta\" (veja o LEIA-ME)")
		return
	_clique(true)
	conta.entrar_google()

func _ret_login() -> Rect2:
	return Rect2(W / 2.0 - 320, 222, 640, 400)

func _ret_bt_google() -> Rect2:
	return Rect2(W / 2.0 - 180, 404, 360, 62)

func _ret_bt_cancelar_login() -> Rect2:
	return Rect2(W / 2.0 - 120, 524, 240, 52)

func _ret_bt_convidado() -> Rect2:
	return Rect2(W / 2.0 - 180, 486, 360, 54)

func _desenhar_login() -> void:
	_degrade(Rect2(-O.x, -O.y, size.x, size.y), Color(0.02, 0.016, 0.047, 0.35), Color(0.02, 0.016, 0.047, 0.75))
	var j := _ret_login()
	_caixa(j.grow(9), Color(0, 0, 0, 0.35), 34, 0, Color(), 18, Vector2(0, 10), Color(0, 0, 0, 0.5))
	_caixa(j.grow(7), Color("4a2a06"), 32)
	_caixa(j.grow(5), OURO2, 30)
	_caixa(j.grow(1), Color("141a36"), 26)
	_painel(j, Color("3b4a8c"), Color("232c5c"), 25)
	var cx := j.get_center().x
	_texto_cartoon(Vector2(cx, j.position.y + 64), "Bem-vindo, guerreiro!", 42, CREME, f_titulo, 2.0, true)
	_texto_cartoon(Vector2(cx, j.position.y + 110), "Entre com sua conta Google para salvar troféus, vitórias,", 19, Color("eef0ff"), f_texto, 1.5, true)
	_texto_cartoon(Vector2(cx, j.position.y + 136), "moedas e personagens, e jogar de qualquer lugar.", 19, Color("eef0ff"), f_texto, 1.5, true)
	var esperando: bool = conta != null and (conta.esperando_login or conta.status == "carregando")
	if esperando:
		_roda(Vector2(cx, j.position.y + 204))
		var t := "Termine o login no navegador..." if conta.esperando_login else "Carregando sua conta..."
		_texto_cartoon(Vector2(cx, j.position.y + 272), t, 21, CREME, f_texto, 1.5, true)
		if conta.esperando_login:
			_botao_simples(_ret_bt_cancelar_login(), "Cancelar", Color("6f86d6"), Color("2c3874"), NAVY)
		return
	# botão do Google (branco, com o "G" colorido)
	var g := _ret_bt_google()
	_caixa(Rect2(g.position + Vector2(0, 5), g.size).grow(3), Color("141a36"), 18)
	_caixa(g.grow(3), Color("141a36"), 18)
	_caixa(g, Color.WHITE, 16)
	_degrade(Rect2(g.position.x + 14, g.position.y + 4, g.size.x - 28, g.size.y * 0.35), Color(1, 1, 1, 0), Color(0, 0, 0, 0.04))
	_logo_google(g.position + Vector2(44, g.size.y / 2.0), 16.0)
	_texto(Vector2(g.position.x + 74, g.position.y + 40), "Entrar com Google", 26, Color("3c4043"), f_titulo)
	_botao_simples(_ret_bt_convidado(), "Jogar como convidado", Color("6f86d6"), Color("2c3874"), NAVY)
	_texto_cartoon(Vector2(cx, j.end.y - 26), "Como convidado, o progresso fica só neste aparelho.", 15, Color("cfc8e8"), f_texto, 1.0, true)

func _botao_simples(b: Rect2, txt: String, claro: Color, escuro: Color, contorno: Color) -> void:
	_caixa(Rect2(b.position + Vector2(0, 5), b.size).grow(3), contorno, 18)
	_caixa(b.grow(3), contorno, 18)
	_botao_degrade(b, claro, claro.lerp(escuro, 0.5), escuro, 16)
	_texto_cartoon(Vector2(b.get_center().x, b.position.y + b.size.y / 2.0 + 9), txt, 24, Color.WHITE, f_titulo, 2.0, true)

func _roda(c: Vector2) -> void:
	_ci.draw_circle(c, 34, Color("141a36"))
	_ci.draw_arc(c, 26, 0, TAU, 32, Color(1, 1, 1, 0.1), 7, true)
	var a := relogio * 5.0
	_ci.draw_arc(c, 26, a, a + PI * 1.3, 24, OURO2, 7, true)

func _logo_google(c: Vector2, r: float) -> void:
	var cores := [Color("ea4335"), Color("fbbc05"), Color("34a853"), Color("4285f4")]
	var faixas := [[-PI * 0.75, -PI * 0.25], [PI * 0.75, PI * 1.25], [PI * 0.25, PI * 0.75], [-PI * 0.25, PI * 0.1]]
	for i in 4:
		_ci.draw_arc(c, r, faixas[i][0], faixas[i][1], 12, cores[i], r * 0.42, true)
	_ci.draw_line(c + Vector2(0, 0), c + Vector2(r * 1.05, 0), Color("4285f4"), r * 0.38)

func _tocar_login(p: Vector2) -> void:
	if conta and conta.esperando_login:
		if _ret_bt_cancelar_login().has_point(p):
			conta.cancelar_login()
			_clique(false)
		return
	if conta and conta.status == "carregando":
		return
	if _ret_bt_google().has_point(p):
		_entrar_google()
	elif _ret_bt_convidado().has_point(p):
		_clique(true)
		Perfil.convidado_ok = true
		Perfil.salvar()
		_depois_da_conta()

## Janelinha "Termine o login no navegador" quando o login começa pelas Opções.
func _ret_espera() -> Rect2:
	return Rect2(W / 2.0 - 260, 250, 520, 250)

func _ret_espera_cancelar() -> Rect2:
	var j := _ret_espera()
	return Rect2(j.get_center().x - 80, j.end.y - 76, 160, 52)

func _desenhar_espera() -> void:
	var j := _ret_espera()
	_caixa(j.grow(5), OURO2, 30)
	_caixa(j.grow(1), Color("141a36"), 26)
	_painel(j, Color("3b4a8c"), Color("232c5c"), 25)
	_roda(Vector2(j.get_center().x, j.position.y + 70))
	var t := "Termine o login no navegador..." if conta.esperando_login else "Carregando sua conta..."
	_texto_cartoon(Vector2(j.get_center().x, j.position.y + 140), t, 21, CREME, f_texto, 1.5, true)
	if conta.esperando_login:
		_botao_simples(_ret_espera_cancelar(), "Cancelar", Color("6f86d6"), Color("2c3874"), NAVY)

# ---------------------------------------------------------------- logo
func _atualizar_logo(dt: float) -> void:
	var ay := 26.0
	var ak := 1.0
	var aa := 1.0
	if tela == Tela.CARGA and not Perfil.ja_entrou:
		var p := clampf((t_tela - 0.35) / 1.9, 0.0, 1.0)
		logo_y = lerpf(-290.0, 26.0, _sai_com_folga(p))
		logo_a = clampf(p / 0.35, 0.0, 1.0)
		logo_k = 1.0
	else:
		if tela == Tela.LADO:
			ay = -4.0
			aa = 0.0
		elif tela == Tela.MENU:
			ak = 0.74
		elif tela == Tela.LOGIN:
			ak = 0.8
		var s := 1.0 - exp(-dt * 7.0)
		logo_y = lerpf(logo_y, ay, s)
		logo_k = lerpf(logo_k, ak, s)
		logo_a = move_toward(logo_a, aa, dt * 2.6)
	logo.position = O + Vector2(W / 2.0, logo_y)
	logo.scale = Vector2(logo_k, logo_k)
	logo.modulate.a = logo_a
	logo.visible = logo_a > 0.01
	# brilho passando pelas letras (de vez em quando no menu)
	if tela == Tela.MENU and brilho_t < 0 and fmod(relogio, 7.0) < dt:
		brilho_t = 0.0
	var bx := -9999.0
	if brilho_t >= 0:
		brilho_t += dt
		bx = lerpf(-520.0, 560.0, brilho_t / 1.2)
		if brilho_t > 1.2:
			brilho_t = -1.0
			bx = -9999.0
	for l in palavras:
		l.brilho = bx - l.position.x if bx > -9000 else -9999.0

static func _sai_com_folga(p: float) -> float:   # parecido com cubic-bezier(.18,.9,.28,1.06): desce rápido e assenta
	var s := 0.9
	var q := p - 1.0
	return 1.0 + (s + 1.0) * q * q * q + s * q * q

# ---------------------------------------------------------------- 2) escolha do lado
func _atualizar_lado(dt: float) -> void:
	raio_forca = move_toward(raio_forca, 0.0, dt * 1.4)
	_raio_t -= dt
	if _raio_t <= 0:
		_raio_t = 0.055
		_gerar_raio()
	for i in 2:
		var alvo := 0.0
		if escolhendo:
			alvo = 1.0 if i != foco_lado else 0.0
		elif foco_lado >= 0 and i != foco_lado:
			alvo = 1.0
		_escurece[i] = move_toward(_escurece[i], alvo, dt * 3.0)
	if escolhendo:
		_zoom_lado = move_toward(_zoom_lado, 1.0, dt * 1.2)
	for i in 2:
		var p := placas[i]
		var k := 1.08 if foco_lado == i else 1.0
		var a := 0.45 if (foco_lado >= 0 and foco_lado != i) else 1.0
		if escolhendo:
			a = 0.0
		var s := 1.0 - exp(-dt * 10.0)
		p.scale = p.scale.lerp(Vector2(k, k), s)
		p.modulate.a = move_toward(p.modulate.a, a, dt * 3.0)
		p.position = O + (Vector2(70, 680) if i == 0 else Vector2(W - 70, 680))

func _x_raio(y: float) -> float:
	return RAIO_TOPO + (RAIO_BAIXO - RAIO_TOPO) * (y / H)

func _gerar_raio() -> void:
	_raio_brilho = _pontos_raio(46.0)
	_raio_miolo = _pontos_raio(34.0)
	_galhos.clear()
	for i in 3:
		var t := randf()
		var y := t * H
		var x := _x_raio(y)
		var s := -1.0 if randf() < 0.5 else 1.0
		_galhos.append(PackedVector2Array([Vector2(x, y), Vector2(x + s * (20 + randf() * 40), y + 20 + randf() * 30),
			Vector2(x + s * (40 + randf() * 60), y + 50 + randf() * 40)]))

func _pontos_raio(desvio: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 16
	for i in n + 1:
		var y := float(i) / n * (H + 40.0) - 20.0
		var x := _x_raio(y) + ((randf() - 0.5) * desvio if (i > 0 and i < n) else 0.0)
		pts.append(Vector2(x, y))
	return pts

func _lado_no_ponto(p: Vector2) -> int:
	return 0 if p.x < _x_raio(p.y) else 1

func _focar_lado(i: int) -> void:
	if i != foco_lado and not escolhendo:
		foco_lado = i
		_clique(false)

func _escolher_lado(i: int) -> void:
	if escolhendo or _indo_para >= 0:
		return
	escolhendo = true
	foco_lado = i
	raio_forca = 1.6
	clarao = 1.0
	_trovao()
	Perfil.lado = "heroes" if i == 0 else "monsters"
	Perfil.salvar()
	get_tree().create_timer(1.0).timeout.connect(func(): _ir(Tela.MENU))

# ---------------------------------------------------------------- 3) menu
func _atualizar_menu(dt: float) -> void:
	for i in BOTOES.size():
		_hov[i] = move_toward(_hov[i], 1.0 if (i == foco and not opcoes_aberta and not busca_ativa) else 0.0, dt * 7.0)
		_aperto[i] = move_toward(_aperto[i], 0.0, dt * 5.0)
	if _acao_pendente != "":
		_acao_t -= dt
		if _acao_t <= 0:
			var a := _acao_pendente
			_acao_pendente = ""
			_fazer(a)
	_atualizar_busca(dt)
	_atualizar_batalha(dt)

func _ret_botao(i: int) -> Rect2:
	return Rect2(W / 2.0 - BOT_W / 2.0, BOT_Y0 + i * BOT_PASSO, BOT_W, BOT_H)

func _ret_perfil() -> Rect2:
	return Rect2(-O.x + 22, -O.y + 20, 318, 86)

func _ret_bonus() -> Rect2:
	return Rect2(W + O.x - 22 - 262, -O.y + 96, 262, 64)

func _centro_social() -> Vector2:
	return Vector2(W + O.x - 22 - 29, -O.y + 22 + 29)

func _apertar(i: int) -> void:
	if _acao_pendente != "" or _indo_para >= 0:
		return
	foco = i
	_aperto[i] = 1.0
	_clique(true)
	_acao_pendente = BOTOES[i].id
	_acao_t = 0.13

func _fazer(acao: String) -> void:
	match acao:
		"novo":
			if Perfil.lado == "monsters":
				_avisar("Modo Monsters chega numa próxima parte — abrindo a campanha dos Heroes!")
			_ir(Tela.MENU, _abrir_jogo)
		"opcoes":
			opcoes_aberta = true
		"lado":
			_ir(Tela.LADO)
		"pvp":
			_abrir_busca()
		"personagens":
			_avisar("Tela de Personagens chega numa próxima parte!")
		"ranking":
			_avisar("Ranking e ligas chegam na próxima parte!")

func _abrir_jogo() -> void:
	if _cena_jogo == null and _pedidos.has(CENA_JOGO):
		_cena_jogo = ResourceLoader.load_threaded_get(CENA_JOGO)
		_pedidos.erase(CENA_JOGO)
	if _cena_jogo:
		get_tree().change_scene_to_packed(_cena_jogo)
	else:
		get_tree().change_scene_to_file(CENA_JOGO)

# ---------------------------------------------------------------- BATALHA PvP: procurando adversário
## Igual ao site: procura alguém do lado oposto (com a conta: no servidor, a cada 1,5 s).
## Se ninguém aparecer a tempo, começa contra o bot (com nome de gente). Sem conta: sempre o bot.
func _abrir_busca() -> void:
	busca_ativa = true
	busca_t = 0.0
	busca_achou = -1.0
	busca_nome = ""
	busca_online = Conta.online_pronto()
	busca_pedindo = false
	busca_prox = 0.0
	busca_desistiu = false
	busca_sala = {}

func _cancelar_busca() -> void:
	if busca_ativa and busca_achou < 0.0:
		busca_ativa = false
		if busca_online:
			Conta.chamar("sair_da_fila_godot")
		_clique(false)

func _lado_busca() -> String:
	return "monsters" if Perfil.lado == "monsters" else "heroes"

func _atualizar_busca(dt: float) -> void:
	if not busca_ativa:
		return
	if busca_achou < 0.0:
		busca_t += dt
		if busca_t >= ConfigPvp.BUSCA_ESPERA and not busca_pedindo and not busca_desistiu:
			if busca_online:
				_desistir_da_fila()
			else:
				_achou_bot()
		elif busca_online and not busca_desistiu:
			busca_prox -= dt
			if busca_prox <= 0.0 and not busca_pedindo:
				busca_prox = 1.5
				_procurar_no_servidor()
	else:
		busca_achou += dt
		if busca_achou >= 1.5 and _indo_para < 0:
			Perfil.pvp_adversario = busca_nome
			Perfil.pvp_sala = busca_sala
			_ir(Tela.MENU, _abrir_pvp)

func _achou_bot() -> void:
	busca_desistiu = true
	busca_sala = {}
	busca_achou = 0.0
	busca_nome = ConfigPvp.nome_adversario()
	_trovao()
	clarao = 0.5

## Pergunta ao servidor se tem alguém do outro lado (procurar_partida_godot, arquivo 8_pvp_godot.sql).
func _procurar_no_servidor() -> void:
	busca_pedindo = true
	var r: Dictionary = await Conta.chamar("procurar_partida_godot", {"p_lado": _lado_busca()})
	busca_pedindo = false
	if not busca_ativa or busca_achou >= 0.0:
		return
	if r.ok and r.dados is Dictionary and r.dados.has("id"):
		await _achou_pessoa(r.dados)
	elif not r.ok:
		push_warning("PvP: procurar_partida_godot falhou: %s" % r.erro)

## O tempo acabou: sai da fila. Se alguém acabou de te achar, joga contra ele; senão, contra o bot.
func _desistir_da_fila() -> void:
	busca_desistiu = true
	busca_pedindo = true
	var r: Dictionary = await Conta.chamar("sair_da_fila_godot")
	busca_pedindo = false
	if not busca_ativa or busca_achou >= 0.0:
		return
	if r.ok and r.dados is Dictionary and r.dados.has("id"):
		await _achou_pessoa(r.dados)
	else:
		_achou_bot()

func _achou_pessoa(sala: Dictionary) -> void:
	busca_pedindo = true
	var token: String = await Conta.token_fresco()       # o canal ao vivo da partida precisa dele
	busca_pedindo = false
	if not busca_ativa or busca_achou >= 0.0:
		return
	var s := sala.duplicate()
	s["token"] = token
	s["lado"] = "heroes" if str(s.get("heroes", "")) == Conta.meu_id() else "monsters"
	var outro := "monsters" if s.lado == "heroes" else "heroes"
	busca_nome = str(s.get("nome_" + outro, "")) if s.get("nome_" + outro) != null else ""
	if busca_nome == "":
		busca_nome = "Adversário"
	busca_sala = s
	busca_achou = 0.0                                 # mostra "Adversário encontrado!" e entra na partida
	_trovao()
	clarao = 0.5

func _abrir_pvp() -> void:
	busca_ativa = false
	Perfil.ja_entrou = true
	var cena: PackedScene = null
	if _pedidos.has(CENA_PVP):
		cena = ResourceLoader.load_threaded_get(CENA_PVP)
		_pedidos.erase(CENA_PVP)
	if cena:
		get_tree().change_scene_to_packed(cena)
	else:
		get_tree().change_scene_to_file(CENA_PVP)

func _ret_busca() -> Rect2:
	return Rect2(W / 2.0 - 360, 214, 720, 400)

func _ret_cancelar() -> Rect2:
	var j := _ret_busca()
	return Rect2(j.get_center().x - 76, j.end.y - 86, 152, 56)

func _desenhar_busca() -> void:
	var j := _ret_busca()
	var lado := "monsters" if Perfil.lado == "monsters" else "heroes"
	var nome_l := func(l: String) -> String: return "Heroes" if l == "heroes" else "Monsters"
	var outro := "heroes" if lado == "monsters" else "monsters"
	# moldura dourada + painel azul (igual ao site)
	_caixa(j.grow(9), Color(0, 0, 0, 0.35), 34, 0, Color(), 18, Vector2(0, 10), Color(0, 0, 0, 0.5))
	_caixa(j.grow(7), Color("4a2a06"), 32)
	_caixa(j.grow(5), OURO2, 30)
	_caixa(j.grow(1), Color("141a36"), 26)
	_painel(j, Color("3b4a8c"), Color("232c5c"), 25)
	var achou := busca_achou >= 0.0
	_texto_cartoon(Vector2(j.get_center().x, j.position.y + 74), "Adversário encontrado!" if achou else "Procurando adversário...", 42, CREME, f_titulo, 2.0, true)
	# roda: anel dourado enchendo e o tempo no meio
	var c := Vector2(j.get_center().x, j.position.y + 170)
	var k := clampf(busca_t / ConfigPvp.BUSCA_ESPERA, 0.0, 1.0)
	_ci.draw_circle(c, 66, Color(OURO2, 0.12 + 0.06 * sin(relogio * 4.0)))
	_ci.draw_circle(c, 58, Color("141a36"))
	_ci.draw_arc(c, 52, 0, TAU, 48, Color(1, 1, 1, 0.08), 9, true)
	_ci.draw_arc(c, 52, -PI / 2, -PI / 2 + TAU * (1.0 if achou else k), 48, OURO2, 9, true)
	_ci.draw_circle(c, 45, Color("1c1630"))
	if achou:
		_ci.draw_polyline(PackedVector2Array([c + Vector2(-18, 0), c + Vector2(-5, 14), c + Vector2(20, -14)]), VERDE2, 8, true)
	else:
		_texto_cartoon(c + Vector2(0, 15), str(ceili(ConfigPvp.BUSCA_ESPERA - busca_t)), 42, Color.WHITE, f_titulo, 2.0, true)
	var txt: String
	if achou:
		txt = "%s vai jogar de %s. Boa sorte!" % [busca_nome, nome_l.call(outro)]
	else:
		txt = "Você joga de %s. Procurando alguém de %s..." % [nome_l.call(lado), nome_l.call(outro)]
	_texto_cartoon(Vector2(j.get_center().x, j.position.y + 276), txt, 21, Color("eef0ff"), f_texto, 1.5, true)
	if not achou:
		var b := _ret_cancelar()
		_caixa(Rect2(b.position + Vector2(0, 5), b.size).grow(3), NAVY, 18)
		_caixa(b.grow(3), NAVY, 18)
		_botao_degrade(b, Color("6f86d6"), Color("4a5fae"), Color("2c3874"), 16)
		_texto_cartoon(Vector2(b.get_center().x, b.position.y + 37), "Cancelar", 25, Color.WHITE, f_titulo, 2.0, true)

func _avisar(txt: String) -> void:
	aviso = txt
	aviso_t = 2.6

func _voltar() -> void:
	if busca_ativa:
		_cancelar_busca()
	elif opcoes_aberta:
		opcoes_aberta = false
		_clique(false)
	elif tela == Tela.LADO and Perfil.lado != "" and not escolhendo:
		_ir(Tela.MENU)
	elif tela == Tela.MENU or tela == Tela.CARGA:
		if _sair_t > 0:
			get_tree().quit()
		else:
			_sair_t = 2.0
			_avisar("Aperte voltar de novo para sair")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_voltar()

# ---------------------------------------------------------------- batalha do fundo do menu
func _montar_batalha() -> void:
	var cat := get_node_or_null("/root/Catalogo")
	if cat == null:
		return
	lutadores.clear()
	for c: Dictionary in BATALHA:
		var p: PersonagemDados = cat.get_p(c.id)
		if p == null:
			continue
		var f := c.duplicate()
		f.p = p
		f.estado = "espera"
		f.tempo = randf() * 1.5
		f.espera = 0.3 + randf() * 1.5
		f.flash = 0.0
		f.atq = ""
		f.feitos = []
		f.parado = _anim_espera(f)
		lutadores.append(f)
	for f in lutadores:
		var alvo := -1
		for j in lutadores.size():
			if lutadores[j].id == f.get("alvo", ""):
				alvo = j
		f.alvo_i = alvo
	lutadores.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	# os índices de alvo mudaram com a ordenação: refaz
	for f in lutadores:
		f.alvo_i = -1
		for j in lutadores.size():
			if lutadores[j].id == f.get("alvo", ""):
				f.alvo_i = j

func _anim(f: Dictionary, nome: String) -> AnimDados:
	var p: PersonagemDados = f.p
	var a: AnimDados = p.anim(nome)
	return a if (a and a.textura) else null

func _anim_espera(f: Dictionary) -> AnimDados:
	if f.h:
		return _anim(f, "defender" if f.id == "protetor" else "parado")
	return _anim(f, "parado")

func _ataque_de(f: Dictionary) -> String:
	if f.alvo_i < 0:
		return ""
	if f.h:
		if f.id == "protetor" or f.id == "elara":
			return ""
		if f.id == "sentinela" and randf() < 0.25 and _anim(f, "especial"):
			return "especial"
	elif f.id == "esqueletoTita" and randf() < 0.3 and _anim(f, "especial"):
		return "especial"
	return "atacar" if _anim(f, "atacar") else ""

func _atualizar_batalha(dt: float) -> void:
	for f in lutadores:
		f.tempo += dt
		f.flash = maxf(0.0, f.flash - dt * 4.0)
		if f.estado == "espera" and f.tempo > f.espera:
			var nome := _ataque_de(f)
			f.tempo = 0.0
			if nome != "":
				f.estado = "ataque"
				f.atq = nome
				f.feitos = []
			else:
				f.espera = 2.0
		elif f.estado == "ataque":
			var a := _anim(f, f.atq)
			if a == null:
				f.estado = "espera"
				continue
			var q := int(f.tempo * a.fps)
			var momentos: Array = Array(a.quadros_acao) if a.quadros_acao.size() > 0 else [int(a.quadros * 0.55)]
			for k in momentos:
				if q >= k and not f.feitos.has(k):
					f.feitos.append(k)
					if TIRO.has(f.id):
						_atirar(f)
					else:
						_acertar(f)
			if q >= a.quadros:
				f.estado = "espera"
				f.tempo = 0.0
				f.espera = PAUSA_BATALHA.x + randf() * (PAUSA_BATALHA.y - PAUSA_BATALHA.x)
	for s in tiros:
		s.k += dt / s.dur
		if s.k >= 1.0 and not s.fim:
			s.fim = true
			if s.alvo_i >= 0:
				lutadores[s.alvo_i].flash = 1.0
			_explosao(Vector2(s.x1, s.y1), s.cor, 14)
	tiros = tiros.filter(func(s): return not s.fim)
	for p in faiscas:
		p.vida += dt
		p.pos += p.vel * dt
		p.vel.y += 260.0 * dt
	faiscas = faiscas.filter(func(p): return p.vida < p.max)

func _acertar(f: Dictionary) -> void:
	var a: Dictionary = lutadores[f.alvo_i]
	a.flash = 1.0
	var forte: bool = f.id == "esqueletoTita" or f.id == "sentinela"
	var cor := Color("ff9a3c") if f.id == "esqueletoFogo" else (Color("e8dfc8") if forte else Color("fff2c4"))
	_explosao(Vector2((f.x + a.x) / 2.0, f.y - 70.0 * f.t), cor, 22 if forte else 12)

func _atirar(f: Dictionary) -> void:
	var a: Dictionary = lutadores[f.alvo_i]
	var tipo: String = TIRO[f.id]
	var dir := 1.0 if f.h else -1.0
	var x0: float = f.x + dir * 60.0 * f.t
	var y0: float = f.y - 95.0 * f.t
	var x1: float = a.x - dir * 20.0 * a.t
	var y1: float = a.y - 80.0 * a.t
	tiros.append({"tipo": tipo, "x0": x0, "y0": y0, "x1": x1, "y1": y1, "k": 0.0, "fim": false, "alvo_i": f.alvo_i,
		"dur": absf(x1 - x0) / (620.0 if tipo.begins_with("flecha") else 420.0), "cor": COR_TIRO[tipo]})

func _explosao(p: Vector2, cor: Color, n: int) -> void:
	if faiscas.size() > 160:
		return
	for i in n:
		faiscas.append({"pos": p, "vel": Vector2((randf() - 0.5) * 260.0, -randf() * 220.0), "vida": 0.0,
			"max": 0.3 + randf() * 0.4, "cor": cor, "r": 1.5 + randf() * 2.5})

# =================================================================== ENTRADA (toque, mouse, teclado)
func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_F:
			var cheia := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if cheia else DisplayServer.WINDOW_MODE_FULLSCREEN)
			return
		if ev.is_action("ui_cancel"):
			_voltar()
			return
		match tela:
			Tela.CARGA:
				_comecar()
			Tela.LOGIN:
				if ev.is_action("ui_accept") and conta and not conta.esperando_login:
					_entrar_google()
			Tela.LADO:
				if ev.is_action("ui_left"):
					_focar_lado(0)
				elif ev.is_action("ui_right"):
					_focar_lado(1)
				elif ev.is_action("ui_accept") and foco_lado >= 0:
					_escolher_lado(foco_lado)
			Tela.MENU:
				if busca_ativa:
					return
				if opcoes_aberta:
					if ev.is_action("ui_accept"):
						opcoes_aberta = false
					return
				if ev.is_action("ui_up"):
					foco = (foco - 1 + BOTOES.size()) % BOTOES.size()
					_clique(false)
				elif ev.is_action("ui_down"):
					foco = (foco + 1) % BOTOES.size()
					_clique(false)
				elif ev.is_action("ui_accept"):
					_apertar(foco)
		return
	if ev is InputEventMouseMotion:
		var p: Vector2 = ev.position - O
		var mao := false
		match tela:
			Tela.LADO:
				_focar_lado(_lado_no_ponto(p))
				mao = true
			Tela.MENU:
				if busca_ativa:
					mao = _ret_cancelar().has_point(p)
				elif not opcoes_aberta:
					for i in BOTOES.size():
						if _ret_botao(i).grow(4).has_point(p):
							if i != foco:
								foco = i
								_clique(false)
							mao = true
				else:
					mao = true
			Tela.CARGA:
				mao = pronta
			Tela.LOGIN:
				mao = _ret_bt_google().has_point(p) or _ret_bt_convidado().has_point(p)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if mao else Control.CURSOR_ARROW
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_tocar(ev.position - O)

func _tocar(p: Vector2) -> void:
	if _indo_para >= 0:
		return
	match tela:
		Tela.CARGA:
			_comecar()
		Tela.LOGIN:
			_tocar_login(p)
		Tela.LADO:
			var i := _lado_no_ponto(p)
			_focar_lado(i)
			_escolher_lado(i)
		Tela.MENU:
			if conta and (conta.esperando_login or (conta.status == "carregando" and _espera_aberta)):
				if conta.esperando_login and _ret_espera_cancelar().has_point(p):
					conta.cancelar_login()
				return
			if busca_ativa:
				if _ret_cancelar().has_point(p):
					_cancelar_busca()
				return
			if opcoes_aberta:
				_tocar_opcoes(p)
				return
			for i in BOTOES.size():
				if _ret_botao(i).grow(4).has_point(p):
					_apertar(i)
					return
			if _ret_perfil().has_point(p):
				_clique(false)
				_avisar("Ranking e ligas chegam na próxima parte!")
			elif p.distance_to(_centro_social()) < 34:
				_clique(false)
				_avisar("Amigos e chat chegam numa próxima parte!")

# ---------------------------------------------------------------- janela de opções
func _ret_janela() -> Rect2:
	var h := 170.0 + _linhas_opcoes().size() * 62.0
	return Rect2(W / 2.0 - 260, maxf(150.0, H / 2.0 - h / 2.0 + 20.0), 520, h)

func _linhas_opcoes() -> Array:
	var l := [{"id": "som", "txt": "Som e música", "bt": "Ligado" if Perfil.som else "Desligado"}]
	if not OS.has_feature("mobile"):
		var cheia := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		l.append({"id": "tela", "txt": "Tela cheia (tecla F)", "bt": "Ligada" if cheia else "Desligada"})
	l.append({"id": "lado", "txt": "Lado: " + ("Monsters" if Perfil.lado == "monsters" else "Heroes"), "bt": "Trocar"})
	if conta and conta.logado():
		l.append({"id": "conta", "txt": "Conta: " + Perfil.nome.get_slice(" ", 0), "bt": "Sair"})
		l.append({"id": "apagar", "txt": "Apagar conta e dados", "bt": "Confirmar?" if _apagar_t > 0.0 else "Apagar"})
	else:
		l.append({"id": "conta", "txt": "Conta: convidado", "bt": "Entrar"})
	return l

func _ret_linha_bt(i: int) -> Rect2:
	var j := _ret_janela()
	return Rect2(j.end.x - 30 - 150, j.position.y + 84 + i * 62, 150, 46)

func _ret_fechar() -> Rect2:
	var j := _ret_janela()
	return Rect2(j.get_center().x - 90, j.end.y - 70, 180, 50)

func _tocar_opcoes(p: Vector2) -> void:
	var linhas := _linhas_opcoes()
	for i in linhas.size():
		if _ret_linha_bt(i).has_point(p):
			_clique(false)
			match linhas[i].id:
				"som":
					Perfil.som = not Perfil.som
					var s := get_node_or_null("/root/Sons")
					if s:
						s.ligado = Perfil.som
					Perfil.salvar()
				"tela":
					var cheia := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if cheia else DisplayServer.WINDOW_MODE_FULLSCREEN)
				"lado":
					opcoes_aberta = false
					_ir(Tela.LADO)
				"conta":
					if conta and conta.logado():
						conta.sair()
						_avisar("Você saiu da conta. Agora é convidado.")
					else:
						opcoes_aberta = false
						_espera_aberta = true
						_entrar_google()
				"apagar":
					if _apagar_t <= 0.0:
						_apagar_t = 4.0                # toque de novo em 4 s para confirmar
					else:
						_apagar_t = 0.0
						_apagar_conta()
			return
	if _ret_fechar().has_point(p) or not _ret_janela().has_point(p):
		_clique(false)
		opcoes_aberta = false

# =================================================================== DESENHO
func _draw() -> void:
	_ci = self
	draw_set_transform(O)
	var tela_toda := Rect2(-O, size)
	match tela:
		Tela.CARGA: _desenhar_carga(tela_toda)
		Tela.LADO: _desenhar_lado(tela_toda)
		Tela.MENU: _desenhar_menu(tela_toda)
		Tela.LOGIN: _desenhar_login()

func _desenhar_carga(r: Rect2) -> void:
	# sombras em cima e embaixo (como o site), para o logo e a barra aparecerem
	_degrade(Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.3), Color(0.02, 0.016, 0.047, 0.72), Color(0.02, 0.016, 0.047, 0.1))
	_degrade(Rect2(r.position.x, H * 0.6, r.size.x, r.end.y - H * 0.6), Color(0.02, 0.016, 0.047, 0.0), Color(0.02, 0.016, 0.047, 0.82))
	var some := clampf(pronta_t / 0.4, 0.0, 1.0) if pronta else 0.0
	if some < 1.0:
		var a := 1.0 - some
		# dica (troca com um fade)
		var fd := clampf(minf(dica_t / 0.4, (TROCA_DICA - dica_t) / 0.4), 0.0, 1.0)
		_texto_cartoon(Vector2(W / 2.0, 607), DICAS[dica_i], 17, Color(0.914, 0.886, 0.812, a * fd), f_texto, 1.5, true)
		_barra(Rect2(W / 2.0 - 300, 619, 600, 26), progresso, a)
		_texto_cartoon(Vector2(W / 2.0, 672), "Carregando %d%%" % roundi(progresso * 100), 20, Color(CREME, a), f_titulo, 1.5, true)
	if pronta:
		var a := clampf((pronta_t - 0.2) / 0.4, 0.0, 1.0)
		var pulso := 0.5 - 0.5 * cos(pronta_t * TAU / 1.6)
		var c := Vector2(W / 2.0, 644)
		_elipse_degrade(c + Vector2(0, -10), 250, 46, Color(0.03, 0.024, 0.063, 0.85 * a), Color(0.03, 0.024, 0.063, 0.0))
		var k := 0.97 + 0.06 * pulso
		draw_set_transform(O + c, 0, Vector2(k, k))
		var txt := "Toque para começar" if OS.has_feature("mobile") else "Clique para começar"
		for g: int in [26, 16]:
			_texto(Vector2(-_larg(f_titulo, txt, 32) / 2.0, 0), txt, 32, Color(OURO2, (0.16 + 0.14 * pulso) * a), f_titulo, g, Color(OURO2, (0.14 + 0.14 * pulso) * a))
		_texto_cartoon(Vector2.ZERO, txt, 32, Color(CREME, (0.55 + 0.45 * pulso) * a), f_titulo, 2.0, true)
		draw_set_transform(O)

func _barra(r: Rect2, k: float, a: float) -> void:
	var borda := Color("3a2c14")
	_caixa(r.grow(6), Color(borda, a), 20, 0, Color(), 12, Vector2(0, 8), Color(0, 0, 0, 0.6 * a))
	_caixa(r.grow(4), Color(Color("c9973b"), a), 18)
	_caixa(r.grow(2), Color(borda, a), 16)
	_caixa(r, Color(Color("151826"), a), 14)
	_degrade(Rect2(r.position.x + 8, r.position.y + 2, r.size.x - 16, r.size.y - 4), Color(Color("0d0f18"), a), Color(Color("1d2133"), a))
	var f := Rect2(r.position + Vector2(4, 4), Vector2((r.size.x - 8) * clampf(k, 0, 1), r.size.y - 8))
	if f.size.x > 4:
		_caixa(f, Color(OURO2, a), 9, 0, Color(), 8, Vector2.ZERO, Color(0.965, 0.765, 0.263, 0.45 * a))
		if f.size.x > 20:
			var meio := f.position.y + f.size.y * 0.45
			_degrade(Rect2(f.position.x + 6, f.position.y + 1, f.size.x - 12, meio - f.position.y - 1), Color(Color("fff0a8"), a), Color(OURO2, a))
			_degrade(Rect2(f.position.x + 6, meio, f.size.x - 12, f.end.y - meio - 1), Color(OURO2, a), Color(Color("c9820f"), a))
			# brilho correndo
			var bx := fmod(relogio / 1.4, 1.0) * (f.size.x + 160.0) - 80.0 + f.position.x
			var x0 := clampf(bx - 30, f.position.x + 4, f.end.x - 4)
			var x1 := clampf(bx + 30, f.position.x + 4, f.end.x - 4)
			if x1 - x0 > 1:
				var y0 := f.position.y + 1
				var y1 := f.end.y - 1
				draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2((x0 + x1) / 2, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2((x0 + x1) / 2, y1), Vector2(x0, y1)]),
					PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.7 * a), Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.7 * a), Color(1, 1, 1, 0)]))
	for lado: float in [-1.0, 1.0]:
		var c := Vector2(r.get_center().x + lado * (r.size.x / 2.0 + 6.0), r.get_center().y)
		_losango(c, 13.0, Color(borda, a))
		_losango(c, 10.0, Color(OURO2, a), Color(OURO1, a), Color(OURO3, a))

func _desenhar_lado(r: Rect2) -> void:
	# escurece o lado que não está em foco
	for i in 2:
		if _escurece[i] > 0.01:
			var pts: PackedVector2Array
			if i == 0:
				pts = PackedVector2Array([Vector2(r.position.x, r.position.y), Vector2(_x_raio(r.position.y), r.position.y), Vector2(_x_raio(r.end.y), r.end.y), Vector2(r.position.x, r.end.y)])
			else:
				pts = PackedVector2Array([Vector2(_x_raio(r.position.y), r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Vector2(_x_raio(r.end.y), r.end.y)])
			draw_colored_polygon(pts, Color(0.02, 0.02, 0.06, 0.42 * _escurece[i]))
	# sombra embaixo (placas) e em cima (título)
	_degrade(Rect2(r.position.x, H - 300, r.size.x, 135), Color(0.016, 0.016, 0.04, 0), Color(0.016, 0.016, 0.04, 0.55))
	_degrade(Rect2(r.position.x, H - 165, r.size.x, r.end.y - (H - 165)), Color(0.016, 0.016, 0.04, 0.55), Color(0.016, 0.016, 0.04, 0.85))
	_degrade(Rect2(r.position.x, r.position.y, r.size.x, 170 + O.y), Color(0.016, 0.016, 0.04, 0.6), Color(0.016, 0.016, 0.04, 0))
	# raio
	var cor := Color("6fb8ff") if foco_lado == 0 else (Color("ff6a3a") if foco_lado == 1 else Color("c9e4ff"))
	var f := 0.55 + raio_forca * 0.45
	if _raio_brilho.size() > 1:
		draw_polyline(_raio_brilho, Color(cor, 0.16 * f), 36.0 * f, true)
		draw_polyline(_raio_brilho, Color(cor, 0.4 * f), 16.0 * f, true)
		draw_polyline(_raio_miolo, Color(1, 1, 1, minf(1.0, 0.85 * f)), 2.6 + 2.0 * f, true)
		for g in _galhos:
			draw_polyline(g, Color(cor, minf(1.0, 0.5 * f)), 2.0, true)
	# título
	var a := 0.0 if escolhendo else 1.0
	_texto_cartoon(Vector2(W / 2.0, 82), "Escolha seu lado", 52, Color(CREME, a), f_titulo, 2.0, true)
	var sub := "Toque num dos lados" if OS.has_feature("mobile") else "Use as setas e aperte Enter, ou clique num dos lados"
	_texto_cartoon(Vector2(W / 2.0, 112), sub, 17, Color(0.91, 0.894, 0.957, a), f_texto, 1.5, true)

## Placa de cada lado (nome em degradê + frase + botão). i = 0 Heroes (esquerda), 1 Monsters (direita).
func _desenhar_placa(i: int) -> void:
	var n := placas[i]
	_ci = n
	var dir := 1.0 if i == 0 else -1.0
	var frase := "Defenda o castelo contra as hordas de esqueletos." if i == 0 else "Comande os esqueletos e derrube o castelo dos heróis."
	var bt := "Entrar como Heroes" if i == 0 else "Entrar como Monsters"
	var bw := _larg(f_titulo, bt, 22) + 52.0
	var br := Rect2(0.0 if i == 0 else -bw, -46, bw, 46)
	var c1 := OURO1 if i == 0 else VERDE1
	var c2 := OURO2 if i == 0 else VERDE2
	var c3 := OURO3 if i == 0 else VERDE3
	var cc := Color("3a2610") if i == 0 else Color("0e2a09")
	var pulso := 0.5 + 0.5 * sin(relogio * 4.0) if foco_lado == i else 0.0
	if pulso > 0:
		_caixa(br.grow(6), Color(c2, 0.25 + 0.25 * pulso), 22)
	_caixa(Rect2(br.position + Vector2(0, 5), br.size).grow(2), cc, 18, 0, Color(), 10, Vector2(0, 4), Color(0, 0, 0, 0.6))
	_caixa(br.grow(2), cc, 18)
	_botao_degrade(br, c1, c2, c3, 16)
	_texto_cartoon(Vector2(br.get_center().x, br.position.y + 31), bt, 22, Color.WHITE, f_titulo, 1.5, true)
	# frase (até 2 linhas, alinhada ao lado)
	var largura := 400.0
	var alinha := HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	var alt := f_texto.get_multiline_string_size(frase, alinha, largura, 18).y
	var py := -46.0 - 14.0 - alt + 16.0
	var px := 0.0 if i == 0 else -largura
	for camada in 2:
		var off := Vector2(0, 2.5) if camada == 0 else Vector2.ZERO
		n.draw_multiline_string_outline(f_texto, Vector2(px, py) + off, frase, alinha, largura, 18, -1, 4, CONTORNO)
	n.draw_multiline_string(f_texto, Vector2(px, py), frase, alinha, largura, 18, -1, Color("f2eee6"))
	var l: Letreiro = n.get_child(0)
	l.position = Vector2(dir * l.largura() / 2.0, py - 30.0)

func _desenhar_menu(r: Rect2) -> void:
	# escurece o fundo: oval no meio (atrás dos botões) + em cima e embaixo
	_degrade(Rect2(r.position.x, r.position.y, r.size.x, H * 0.32 + O.y), Color(0.024, 0.027, 0.055, 0.55), Color(0.024, 0.027, 0.055, 0))
	_degrade(Rect2(r.position.x, H * 0.8, r.size.x, r.end.y - H * 0.8), Color(0.024, 0.027, 0.055, 0), Color(0.024, 0.027, 0.055, 0.6))
	_desenhar_batalha()
	_elipse_degrade(Vector2(W / 2.0, H * 0.55), W * 0.36, H * 0.7, Color(0.024, 0.027, 0.055, 0.62), Color(0.024, 0.027, 0.055, 0))
	var lado := "monsters" if Perfil.lado == "monsters" else "heroes"
	var tm: Dictionary = TEMA[lado]
	for i in BOTOES.size():
		_desenhar_botao(i, tm)
	_desenhar_perfil(lado)
	_desenhar_bonus()
	_desenhar_social()
	if aviso_t <= 0 and not OS.has_feature("mobile"):
		var y := H - 18.0
		var txt := "para escolher  ·  Enter para confirmar"
		var w := _larg(f_texto, txt, 15) + 34.0
		var x0 := W / 2.0 - w / 2.0
		_seta(Vector2(x0 + 6, y - 6), 1)
		_seta(Vector2(x0 + 20, y - 6), -1)
		_texto_cartoon(Vector2(x0 + 34, y), txt, 15, Color(0.92, 0.9, 0.85, 0.85), f_texto, 1.0, false)

func _desenhar_botao(i: int, tm: Dictionary) -> void:
	var b: Dictionary = BOTOES[i]
	var r := _ret_botao(i)
	var principal: bool = b.get("principal", false)
	var hv := _hov[i]
	var ap := _aperto[i]
	var k := 1.0 + 0.04 * hv - 0.05 * ap
	if principal and hv < 0.5:
		k *= 1.0 + 0.025 * (0.5 - 0.5 * cos(relogio * TAU / 2.4))
	var dy := -3.0 * hv + 7.0 * ap
	var c := r.get_center() + Vector2(0, dy)
	draw_set_transform(O + c, 0, Vector2(k, k))
	var rr := Rect2(-r.size / 2.0, r.size)
	var cc: Color = tm.pc if principal else NAVY
	var labio := 7.0 + 3.0 * hv - 5.0 * ap
	if hv > 0.01:
		_caixa(rr.grow(7), Color(tm.foco, (tm.foco as Color).a * hv), 27)
	_caixa(Rect2(rr.position + Vector2(0, labio), rr.size).grow(3), cc, 23, 0, Color(), 9, Vector2(0, 5), Color(0, 0, 0, 0.5))
	_caixa(rr.grow(3), cc, 23)
	var claro: Color = tm.p1 if principal else tm.b1
	var escuro: Color = tm.p2 if principal else tm.b2
	if hv > 0.01:
		claro = claro.lightened(0.08 * hv)
		escuro = escuro.lightened(0.08 * hv)
	_botao_degrade(rr, claro, claro.lerp(escuro, 0.5), escuro, 20)
	# ícone redondo
	var ic := Vector2(rr.position.x + 10 + 23, 0)
	draw_circle(ic, 26.0, cc)
	_bola(ic, 23.0, tm.pico1 if principal else tm.ico1, tm.pico2 if principal else tm.ico2)
	var cor_ico := Color("2a1804") if principal else OURO2
	_icone(b.icone, ic, 26.0, cor_ico, cc)
	# texto
	var tx := rr.position.x + 56.0 + (rr.size.x - 56.0 - 30.0) / 2.0
	_texto_cartoon(Vector2(tx, 10), b.txt, 27, Color.WHITE, f_titulo, 2.0, true)
	if b.get("breve", false):
		var er := Rect2(rr.end.x - 74, -11, 62, 22)
		_caixa(er.grow(2), Color("24130a"), 12)
		_caixa(er, Color(0.07, 0.06, 0.12, 0.9), 11)
		_texto(Vector2(er.get_center().x - _larg(f_texto, "em breve", 12) / 2.0, er.position.y + 16), "em breve", 12, Color("ffe7a6"), f_texto)
	draw_set_transform(O)

func _desenhar_perfil(lado: String) -> void:
	var r := _ret_perfil()
	_caixa(Rect2(r.position + Vector2(0, 6), r.size).grow(3), NAVY, 21, 0, Color(), 9, Vector2(0, 4), Color(0, 0, 0, 0.45))
	_caixa(r.grow(3), NAVY, 21)
	_painel(r, Color("3b4a8c"), Color("232c5c"), 18)
	# brasão
	var b := Rect2(r.position + Vector2(10, 16), Vector2(54, 54))
	_caixa(b, Color("c9973b"), 8)
	var c1 := Color("3f5a24") if lado == "monsters" else Color("2e3a6a")
	var c2 := Color("101a0a") if lado == "monsters" else Color("10142a")
	_caixa(b.grow(-2), c2, 7)
	_bola(b.get_center() + Vector2(-2, -3), 22, c1, c2)
	if conta and conta.logado():
		if conta.foto:                     # foto do Google
			draw_texture_rect(conta.foto, b.grow(-3), false)
		else:                              # sem foto: a letra do nome (como no site)
			_caixa(b.grow(-3), Color("2f7fd6"), 6)
			_texto_cartoon(Vector2(b.get_center().x, b.position.y + 40), Perfil.nome.left(1).to_upper(), 30, Color.WHITE, f_titulo, 1.5, true)
	else:
		_brasao(lado, b.get_center(), 38.0)
	# nome, lado, troféus e moedas
	var x := b.end.x + 12
	_texto_cartoon(Vector2(x, r.position.y + 32), Perfil.nome, 21, Color.WHITE, f_titulo, 1.5, false)
	var tl := "Lado: "
	_texto(Vector2(x, r.position.y + 52), tl, 14, Color("eef0ff"), f_texto, 3, CONTORNO)
	_texto(Vector2(x + _larg(f_texto, tl, 14), r.position.y + 52), "Monsters" if lado == "monsters" else "Heroes", 14,
		VERDE2 if lado == "monsters" else OURO2, f_texto, 3, CONTORNO)
	var y := r.position.y + 72
	_trofeu(Vector2(x + 9, y - 5), 18)
	var t1 := str(Perfil.trofeus)
	_texto(Vector2(x + 22, y), t1, 14, Color.WHITE, f_texto, 3, CONTORNO)
	var x2 := x + 22 + _larg(f_texto, t1, 14) + 14
	_moeda(Vector2(x2 + 9, y - 5), 18)
	_texto(Vector2(x2 + 22, y), str(Perfil.moedas), 14, Color.WHITE, f_texto, 3, CONTORNO)
	# liga
	var lg := Perfil.liga()
	var lc := Vector2(r.end.x - 40, r.position.y + 36)
	var tex := _textura(["liga/" + str(lg.img), "liga/" + str(lg.nome), "liga/" + str(lg.nome).to_lower()])
	if tex:
		var s := 50.0 / maxf(tex.get_width(), tex.get_height())
		var tam := Vector2(tex.get_width(), tex.get_height()) * s
		draw_texture_rect(tex, Rect2(lc - tam / 2.0 + Vector2(0, 3), tam), false, Color(0, 0, 0, 0.5))
		draw_texture_rect(tex, Rect2(lc - tam / 2.0, tam), false)
	else:
		_escudo(lc, 22.0, lg.cor)
	var ln: String = lg.nome
	_texto(Vector2(lc.x - _larg(f_texto, ln, 12) / 2.0, r.end.y - 6), ln, 12, Color("ffe7a6"), f_texto, 3, CONTORNO)

func _desenhar_bonus() -> void:
	var r := _ret_bonus()
	var b := Perfil.bonus_hoje()
	_caixa(Rect2(r.position + Vector2(0, 5), r.size).grow(3), NAVY, 19)
	_caixa(r.grow(3), NAVY, 19)
	_painel(r, Color("3b4a8c"), Color("232c5c"), 16)
	var nome := func(l: String) -> String: return "Heroes" if l == "heroes" else "Monsters"
	var x := r.position.x + 12
	var t1: String = "Hoje: %s em alta" % nome.call(b.em_alta)
	_texto(Vector2(x, r.position.y + 24), t1, 14, Color("ffe7a6"), f_texto, 3, CONTORNO)
	_texto(Vector2(x + _larg(f_texto, t1, 14), r.position.y + 24), " · +50% moedas", 13, Color("e9e4f2"), f_texto, 3, CONTORNO)
	var y := r.position.y + 48
	if b.pago:
		_texto(Vector2(x, y), "Bônus dos dois lados recebido! (+%d)" % b.valor, 13, VERDE2, f_texto, 3, CONTORNO)
	else:
		var t2 := "2 lados: +%d" % b.valor
		_texto(Vector2(x, y), t2, 13, Color("e9e4f2"), f_texto, 3, CONTORNO)
		var xx := x + _larg(f_texto, t2, 13) + 8
		for l: String in ["heroes", "monsters"]:
			var ok: bool = (b.lados as Array).has(l)
			var cor := VERDE2 if ok else Color("9a93a8")
			if ok:
				draw_polyline(PackedVector2Array([Vector2(xx, y - 5), Vector2(xx + 3.5, y - 1.5), Vector2(xx + 10, y - 9)]), cor, 2.4, true)
			else:
				draw_arc(Vector2(xx + 5, y - 5), 4.5, 0, TAU, 16, cor, 1.6, true)
			var nm: String = nome.call(l)
			_texto(Vector2(xx + 14, y), nm, 13, cor, f_texto, 3, CONTORNO)
			xx += 14 + _larg(f_texto, nm, 13) + 8

func _desenhar_social() -> void:
	var c := _centro_social()
	draw_circle(c + Vector2(0, 6), 34, Color(0, 0, 0, 0.35))
	draw_circle(c, 34, Color("0c0e17"))
	draw_circle(c, 32, Color("8a6526"))
	draw_circle(c, 29, Color("0c0e17"))
	_bola(c, 27, Color("ffe58a"), Color("d8921a"))
	_icone("pessoas", c, 30, Color("2a1804"), Color(0, 0, 0, 0))
	var on := Rect2(c + Vector2(-12, 22), Vector2(24, 16))
	_caixa(on.grow(2), Color("0c0e17"), 10)
	_caixa(on, VERDE2, 8)
	_texto(Vector2(c.x - _larg(f_texto, "0", 12) / 2.0, on.end.y - 3), "0", 12, Color("0c1a06"), f_texto)

func _desenhar_batalha() -> void:
	var esc := Color(1.0 - ESCURECER, 1.0 - ESCURECER, 1.0 - ESCURECER * 0.7)
	for f in lutadores:
		_desenhar_lutador(f, esc)
	for s in tiros:
		var k: float = s.k
		var flecha: bool = (s.tipo as String).begins_with("flecha")
		var p := Vector2(lerpf(s.x0, s.x1, k), lerpf(s.y0, s.y1, k) - sin(k * PI) * (28.0 if flecha else 10.0))
		if flecha:
			var ang := atan2(s.y1 - s.y0 - cos(k * PI) * 28.0 * PI, s.x1 - s.x0)
			draw_set_transform(O + p, ang)
			draw_line(Vector2(-18, 0), Vector2(12, 0), Color("5a3b1f"), 2.4, true)
			draw_colored_polygon(PackedVector2Array([Vector2(16, 0), Vector2(9, -3.5), Vector2(9, 3.5)]), Color("d8dde6"))
			draw_rect(Rect2(-20, -3, 5, 6), s.cor)
			draw_set_transform(O)
		else:
			var rr := 13.0 if s.tipo == "fogo" else 10.0
			var cor: Color = s.cor
			draw_circle(p, rr * 2.4, Color(cor, 0.18))
			draw_circle(p, rr * 1.5, Color(cor, 0.45))
			draw_circle(p, rr * 0.8, Color(cor.lightened(0.5), 0.9))
			draw_circle(p, rr * 0.4, Color.WHITE)
	for q in faiscas:
		draw_circle(q.pos, q.r, Color(q.cor, 1.0 - q.vida / q.max))

func _desenhar_lutador(f: Dictionary, esc: Color) -> void:
	var a: AnimDados = null
	var q := 0
	if f.estado == "ataque":
		a = _anim(f, f.atq)
		if a:
			q = mini(a.quadros - 1, int(f.tempo * a.fps))
	var parado: AnimDados = f.parado
	var resp := 1.0
	if a == null:
		a = parado
		if a:
			var trecho: Array = []
			var p: PersonagemDados = f.p
			if p.extra.has("trechos") and (p.extra.trechos as Dictionary).has("parado"):
				trecho = p.extra.trechos.parado        # protetor: só o pedaço "parado" da folha de defesa
			if trecho.size() == 2:
				var n: int = int(trecho[1]) - int(trecho[0]) + 1
				q = int(trecho[0]) - 1 + int((f.tempo + f.x) * a.fps) % n
			else:
				q = int((f.tempo + f.x) * a.fps) % a.quadros
		else:
			a = _anim(f, "parado" if f.h else "atacar")
			if a == null:
				return
			q = 0
			resp = 1.0 + sin(f.tempo * 2.4 + f.x) * 0.015
	var pd: PersonagemDados = f.p
	var e: float = pd.escala * a.escala * f.t
	var vira := (-1.0 if a.olha_direita else 1.0) if not f.h else 1.0
	var pe := Vector2(f.x, f.y)
	# sombra no chão
	draw_set_transform(O + pe, 0, Vector2(1, 0.235))
	draw_circle(Vector2.ZERO, 34.0 * f.t, Color(0, 0, 0, 0.35))
	draw_set_transform(O + pe, 0, Vector2(e * vira, e * resp))
	var m := 2.0
	var reg := a.retangulo(q)
	var mod := esc
	if f.flash > 0:
		mod = esc.lerp(Color(2.2, 2.2, 2.2), f.flash)
	draw_texture_rect_region(a.textura, Rect2(-a.ax + m, -a.ay + m, a.cw - 2 * m, a.ch - 2 * m), reg.grow(-m), mod)
	draw_set_transform(O)

func _desenhar_battlefront() -> void:
	_ci = logo
	var txt := "Battlefront"
	var tam := 30
	var esp := 6.0
	var larg := 0.0
	for ch in txt:
		larg += _larg(f_titulo, ch, tam) + esp
	larg -= esp
	var y := 136.0
	var x := -larg / 2.0
	for ch in txt:
		_texto_cartoon(Vector2(x, y), ch, tam, CREME, f_titulo, 2.0, false)
		x += _larg(f_titulo, ch, tam) + esp
	for lado: float in [-1.0, 1.0]:
		var xi := lado * (larg / 2.0 + 18.0)
		var xf := lado * (larg / 2.0 + 18.0 + 92.0)
		var yy := y - 11.0
		logo.draw_polygon(PackedVector2Array([Vector2(xi, yy - 2), Vector2(xf, yy - 2), Vector2(xf, yy + 2), Vector2(xi, yy + 2)]),
			PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1)]))
		var lc := Vector2(lado * (larg / 2.0 + 8.0), yy)
		_losango(lc, 8.5, CONTORNO)
		_losango(lc, 6.0, Color.WHITE)

func _apagar_conta() -> void:
	_avisar("Apagando a sua conta...")
	var e: String = await conta.excluir_conta()
	_avisar("Conta apagada. Você agora é convidado." if e == "" else "Não deu para apagar: " + e)

func _desenhar_topo() -> void:
	_ci = topo
	topo.draw_set_transform(O)
	var r := Rect2(-O, size)
	if tela == Tela.MENU and opcoes_aberta:
		topo.draw_rect(r, Color(0.02, 0.02, 0.05, 0.6))
		_desenhar_opcoes()
	if tela == Tela.MENU and _espera_aberta and conta:
		topo.draw_rect(r, Color(0.02, 0.02, 0.05, 0.5))
		_desenhar_espera()
	if tela == Tela.MENU and busca_ativa:
		topo.draw_rect(r, Color(0.02, 0.02, 0.05, 0.45))
		_desenhar_busca()
	if aviso_t > 0:
		var a := clampf(aviso_t / 0.3, 0.0, 1.0) * clampf((2.6 - aviso_t) / 0.15, 0.0, 1.0)
		var w := _larg(f_texto, aviso, 17) + 48
		var ar := Rect2(W / 2.0 - w / 2.0, H - 52, w, 40)
		_caixa(ar.grow(3), Color(NAVY, a), 22)
		_caixa(ar, Color(Color("2a2350"), 0.95 * a), 20)
		_texto_cartoon(Vector2(W / 2.0, ar.position.y + 27), aviso, 17, Color(CREME, a), f_texto, 1.5, true)
	if clarao > 0.0:
		topo.draw_rect(r, Color(1, 1, 1, clarao * clarao * 0.85))
	if cortina > 0.0:
		topo.draw_rect(r, Color(0.02, 0.016, 0.04, cortina))

func _desenhar_opcoes() -> void:
	var j := _ret_janela()
	_caixa(Rect2(j.position + Vector2(0, 7), j.size).grow(3), NAVY, 25, 0, Color(), 14, Vector2(0, 6), Color(0, 0, 0, 0.55))
	_caixa(j.grow(3), NAVY, 25)
	_painel(j, Color("3b4a8c"), Color("232c5c"), 22)
	_texto_cartoon(Vector2(j.get_center().x, j.position.y + 52), "Opções", 38, CREME, f_titulo, 2.0, true)
	var linhas := _linhas_opcoes()
	for i in linhas.size():
		var b := _ret_linha_bt(i)
		_texto_cartoon(Vector2(j.position.x + 30, b.position.y + 31), linhas[i].txt, 19, Color.WHITE, f_texto, 1.5, false)
		_caixa(Rect2(b.position + Vector2(0, 4), b.size).grow(2), Color("4a2a06"), 16)
		_caixa(b.grow(2), Color("4a2a06"), 16)
		_botao_degrade(b, Color("ffe98a"), Color("ffc43a"), Color("c97a0c"), 14)
		_texto_cartoon(Vector2(b.get_center().x, b.position.y + 31), linhas[i].bt, 19, Color.WHITE, f_titulo, 1.5, true)
	var fr := _ret_fechar()
	_caixa(Rect2(fr.position + Vector2(0, 5), fr.size).grow(3), NAVY, 18)
	_caixa(fr.grow(3), NAVY, 18)
	_botao_degrade(fr, Color("6f86d6"), Color("4a5fae"), Color("2c3874"), 16)
	_texto_cartoon(Vector2(fr.get_center().x, fr.position.y + 34), "Fechar", 24, Color.WHITE, f_titulo, 2.0, true)

# =================================================================== AJUDANTES DE DESENHO
func _larg(f: Font, txt: String, tam: int) -> float:
	return f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x

func _texto(pos: Vector2, txt: String, tam: int, cor: Color, f: Font, contorno := 0, cor_c := CONTORNO) -> void:
	if contorno > 0:
		_ci.draw_string_outline(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, contorno, cor_c)
	_ci.draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)

## Letra cartoon do site: contorno escuro em volta + sombra dura embaixo + sombra macia.
func _texto_cartoon(pos: Vector2, txt: String, tam: int, cor: Color, f: Font, grossura := 2.0, centro := false) -> void:
	if centro:
		pos.x -= _larg(f, txt, tam) / 2.0
	var a := cor.a
	var o := int(grossura * 2.0 + 1.0)
	var c := Color(CONTORNO, a)
	_ci.draw_string_outline(f, pos + Vector2(0, grossura * 2.0 + 3.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, o + 6, Color(0, 0, 0, 0.22 * a))
	_ci.draw_string_outline(f, pos + Vector2(0, grossura * 2.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, o, c)
	_ci.draw_string(f, pos + Vector2(0, grossura * 2.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, c)
	_ci.draw_string_outline(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, o, c)
	_ci.draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)

func _sb(cor: Color, raio: int, borda := 0, cor_borda := Color(), sombra := 0, sombra_off := Vector2.ZERO, cor_sombra := Color()) -> StyleBoxFlat:
	var chave := "%s|%d|%d|%s|%d|%s|%s" % [cor.to_html(), raio, borda, cor_borda.to_html(), sombra, sombra_off, cor_sombra.to_html()]
	var sb: StyleBoxFlat = _sb_cache.get(chave)
	if sb == null:
		if _sb_cache.size() > 400:
			_sb_cache.clear()
		sb = StyleBoxFlat.new()
		sb.bg_color = cor
		sb.set_corner_radius_all(raio)
		sb.corner_detail = 6
		sb.anti_aliasing = true
		if borda > 0:
			sb.set_border_width_all(borda)
			sb.border_color = cor_borda
		if sombra > 0:
			sb.shadow_size = sombra
			sb.shadow_offset = sombra_off
			sb.shadow_color = cor_sombra
		_sb_cache[chave] = sb
	return sb

func _caixa(r: Rect2, cor: Color, raio: int, borda := 0, cor_borda := Color(), sombra := 0, sombra_off := Vector2.ZERO, cor_sombra := Color()) -> void:
	_ci.draw_style_box(_sb(cor, raio, borda, cor_borda, sombra, sombra_off, cor_sombra), r)

## Placa "gordinha" do site: metade de cima clara, metade de baixo escura, brilho em cima e sombra interna embaixo.
func _botao_degrade(r: Rect2, claro: Color, meio: Color, escuro: Color, raio: int) -> void:
	_caixa(r, escuro, raio)
	var sb := _sb_parcial(claro.lerp(meio, 0.55), raio, true)
	_ci.draw_style_box(sb, Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)))
	var g := Rect2(r.position.x + 14, r.position.y + 5, r.size.x - 28, r.size.y * 0.38)
	_degrade(g, Color(1, 1, 1, 0.38), Color(1, 1, 1, 0.0))
	_ci.draw_style_box(_sb_linha(raio), r)

## Painel do cartão/janela: degradê suave de cima (claro) para baixo (escuro) + brilho em cima.
func _painel(r: Rect2, claro: Color, escuro: Color, raio: int) -> void:
	_caixa(r, escuro, raio)
	var faixas := 6
	for i in range(1, faixas):             # degradê em faixas arredondadas (sem borda reta aparecendo)
		var k := float(i) / faixas
		var h := r.size.y * (1.0 - k)
		_ci.draw_style_box(_sb_parcial(Color(claro, 0.35), raio, true), Rect2(r.position, Vector2(r.size.x, h)))
	_degrade(Rect2(r.position.x + 14, r.position.y + 4, r.size.x - 28, minf(r.size.y * 0.3, 40.0)), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0))
	_ci.draw_style_box(_sb_linha(raio), r)

func _sb_parcial(cor: Color, raio: int, cima: bool) -> StyleBoxFlat:
	var chave := "p%s%d%s" % [cor.to_html(), raio, cima]
	var sb: StyleBoxFlat = _sb_cache.get(chave)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = cor
		sb.anti_aliasing = true
		sb.corner_detail = 6
		sb.corner_radius_top_left = raio if cima else 0
		sb.corner_radius_top_right = raio if cima else 0
		sb.corner_radius_bottom_left = 0 if cima else raio
		sb.corner_radius_bottom_right = 0 if cima else raio
		_sb_cache[chave] = sb
	return sb

func _sb_linha(raio: int) -> StyleBoxFlat:          # sombra interna embaixo + luz em cima
	var chave := "l%d" % raio
	var sb: StyleBoxFlat = _sb_cache.get(chave)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.draw_center = false
		sb.anti_aliasing = true
		sb.corner_detail = 6
		sb.set_corner_radius_all(raio)
		sb.border_width_bottom = 4
		sb.border_width_top = 2
		sb.border_color = Color(0, 0, 0, 0.25)
		_sb_cache[chave] = sb
	return sb

func _degrade(r: Rect2, c_cima: Color, c_baixo: Color) -> void:
	if r.size.x <= 0 or r.size.y <= 0:
		return
	_ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([c_cima, c_cima, c_baixo, c_baixo]))

func _elipse_degrade(c: Vector2, rx: float, ry: float, c_meio: Color, c_borda: Color, n := 32) -> void:
	var pts := PackedVector2Array([c])
	var cores := PackedColorArray([c_meio])
	for i in n + 1:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		cores.append(c_borda)
	var idx := PackedInt32Array()
	for i in n:
		idx.append_array([0, i + 1, i + 2])
	RenderingServer.canvas_item_add_triangle_array(_ci.get_canvas_item(), idx, pts, cores)

func _losango(c: Vector2, r: float, cor: Color, c_cima := Color(0, 0, 0, 0), c_baixo := Color(0, 0, 0, 0)) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	if c_cima.a > 0:
		_ci.draw_polygon(pts, PackedColorArray([c_cima, cor, c_baixo, cor]))
	else:
		_ci.draw_colored_polygon(pts, cor)

## Bola com luz no canto de cima (imita o radial-gradient do site).
func _bola(c: Vector2, r: float, clara: Color, escura: Color) -> void:
	_ci.draw_circle(c, r, escura)
	for i in range(1, 6):
		var k := i / 6.0
		_ci.draw_circle(c + Vector2(-0.3, -0.4) * r * k * 0.75, r * (1.0 - k * 0.78), escura.lerp(clara, k))

func _seta(c: Vector2, dir: int) -> void:
	var pts := PackedVector2Array([c + Vector2(-5, 3 * dir), c + Vector2(5, 3 * dir), c + Vector2(0, -4 * dir)])
	_ci.draw_colored_polygon(pts, Color(0.92, 0.9, 0.85, 0.85))

static func _arco(c: Vector2, r: float, a0: float, a1: float, n := 10) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		p.append(c + Vector2(cos(a), sin(a)) * r)
	return p

## Ícones dos botões (os mesmos desenhos SVG do site, em linhas, numa caixa de 24x24).
func _montar_icones() -> Dictionary:
	var V := func(a: Array) -> PackedVector2Array:
		var p := PackedVector2Array()
		for i in range(0, a.size(), 2):
			p.append(Vector2(a[i], a[i + 1]))
		return p
	var elmo: PackedVector2Array = V.call([5, 20, 5, 12])
	elmo.append_array(_arco(Vector2(12, 12), 7, PI, TAU))
	elmo.append_array(V.call([19, 20, 5, 20]))
	var corpo := _arco(Vector2(9, 20.5), 6.5, PI, TAU, 8)
	var corpo2 := _arco(Vector2(17.6, 20.0), 4.6, PI * 1.12, TAU, 6)
	return {
		"espada": [V.call([14.5, 3.5, 20.5, 3.5, 20.5, 9.5, 9, 21, 3, 15, 14.5, 3.5]), V.call([5, 13, 11, 19]), V.call([3.5, 20.5, 5.5, 18.5])],
		"espadas": [V.call([4, 4, 17, 17]), V.call([20, 4, 7, 17]), V.call([5.5, 16.5, 7.5, 18.5]), V.call([18.5, 16.5, 16.5, 18.5])],
		"elmo": [elmo, V.call([5, 13, 19, 13]), V.call([12, 13, 12, 20]), V.call([9, 16.5, 15, 16.5])],
		"barras": [V.call([3, 20, 21, 20]), V.call([5, 20, 5, 11, 9, 11, 9, 20]), V.call([10, 20, 10, 6, 14, 6, 14, 20]), V.call([15, 20, 15, 14, 19, 14, 19, 20])],
		"engrenagem": [_arco(Vector2(12, 12), 3.2, 0, TAU, 14), _arco(Vector2(12, 12), 6.5, 0, TAU, 20),
			V.call([12, 2.5, 12, 5.5]), V.call([12, 18.5, 12, 21.5]), V.call([2.5, 12, 5.5, 12]), V.call([18.5, 12, 21.5, 12]),
			V.call([5.3, 5.3, 7.4, 7.4]), V.call([16.6, 16.6, 18.7, 18.7]), V.call([5.3, 18.7, 7.4, 16.6]), V.call([16.6, 7.4, 18.7, 5.3])],
		"trocar": [V.call([4, 8, 18, 8, 15, 5]), V.call([20, 16, 6, 16, 9, 19])],
		"pessoas": [_arco(Vector2(9, 8), 3.5, 0, TAU, 14), corpo, _arco(Vector2(17, 9), 2.6, 0, TAU, 12), corpo2],
	}

func _icone(nome: String, c: Vector2, tam: float, cor: Color, sombra: Color) -> void:
	var linhas: Array = icones.get(nome, [])
	var k := tam / 24.0
	var o := c - Vector2(12, 12) * k
	var larg := 2.2 * k
	for camada in 2:
		var off := Vector2(0, 2) if camada == 0 else Vector2.ZERO
		var cc := sombra if camada == 0 else cor
		if cc.a <= 0:
			continue
		for l: PackedVector2Array in linhas:
			var p := PackedVector2Array()
			for v in l:
				p.append(o + off + v * k)
			_ci.draw_polyline(p, cc, larg, true)
			if p.size() == 2:                       # pontas redondas
				_ci.draw_circle(p[0], larg / 2.0, cc)
				_ci.draw_circle(p[1], larg / 2.0, cc)

func _trofeu(c: Vector2, tam: float) -> void:
	var k := tam / 24.0
	var o := c - Vector2(12, 12) * k
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	var marrom := Color("8a5a12")
	for lado: float in [-1.0, 1.0]:
		var al := PackedVector2Array()
		for v in _arco(Vector2(12 + lado * 5, 7), 3, (-PI / 2 if lado > 0 else PI / 2), (PI / 2 if lado > 0 else PI * 1.5), 6):
			al.append(o + v * k)
		_ci.draw_polyline(al, Color("ffd34d"), 1.8 * k, true)
	var copo := PackedVector2Array([P.call(7, 3), P.call(17, 3)])
	for v in _arco(Vector2(12, 8), 5, 0, PI, 8):
		copo.append(o + v * k)
	_ci.draw_colored_polygon(copo, Color("ffd34d"))
	copo.append(copo[0])
	_ci.draw_polyline(copo, marrom, 1.5 * k, true)
	_ci.draw_rect(Rect2(P.call(10, 13), Vector2(4, 3) * k), Color("e0a52a"))
	var base := PackedVector2Array([P.call(7.5, 20), P.call(16.5, 20), P.call(15.5, 16), P.call(8.5, 16)])
	_ci.draw_colored_polygon(base, Color("e0a52a"))
	base.append(base[0])
	_ci.draw_polyline(base, marrom, 1.2 * k, true)

func _moeda(c: Vector2, tam: float) -> void:
	var k := tam / 24.0
	_ci.draw_circle(c, 11 * k, Color("8a5a12"))
	_ci.draw_circle(c, 9 * k, Color("f2b536"))
	_ci.draw_arc(c, 6.5 * k, 0, TAU, 16, Color(1, 0.94, 0.69, 0.8), 1.4 * k, true)
	var est := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + i * PI / 5
		est.append(c + Vector2(cos(a), sin(a)) * (4.6 if i % 2 == 0 else 2.0) * k)
	_ci.draw_colored_polygon(est, Color("fff6d0"))

func _escudo(c: Vector2, r: float, cor: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.9, -r * 0.6), c + Vector2(r * 0.8, r * 0.3), c + Vector2(0, r), c + Vector2(-r * 0.8, r * 0.3), c + Vector2(-r * 0.9, -r * 0.6)])
	_ci.draw_colored_polygon(pts, cor.darkened(0.45))
	var pts2 := PackedVector2Array()
	for p in pts:
		pts2.append(c + (p - c) * 0.8)
	_ci.draw_colored_polygon(pts2, cor)
	pts.append(pts[0])
	_ci.draw_polyline(pts, CONTORNO, 2.0, true)

## Brasão do cartão: escudo azul (Heroes) ou caveira de olhos verdes (Monsters). Desenho numa caixa 40x40.
func _brasao(lado: String, c: Vector2, tam: float) -> void:
	var k := tam / 40.0
	var o := c - Vector2(20, 20) * k
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	if lado == "monsters":
		var cab := PackedVector2Array()
		for v in _arco(Vector2(20, 16), 13, deg_to_rad(150), deg_to_rad(390), 16):
			cab.append(o + v * k)
		cab.append_array([P.call(28, 25), P.call(28, 30), P.call(12, 30), P.call(12, 25)])
		_ci.draw_colored_polygon(cab, Color("e8dfc8"))
		cab.append(cab[0])
		_ci.draw_polyline(cab, Color("1a1208"), 2 * k, true)
		_ci.draw_circle(P.call(14.5, 17), 3.4 * k, Color("8be03c"))
		_ci.draw_circle(P.call(25.5, 17), 3.4 * k, Color("8be03c"))
		_ci.draw_colored_polygon(PackedVector2Array([P.call(20, 21), P.call(18, 25), P.call(22, 25)]), Color("1a1208"))
		for x: float in [15, 20, 25]:
			_ci.draw_line(P.call(x, 27), P.call(x, 30), Color("1a1208"), 2 * k)
	else:
		var esc := PackedVector2Array([P.call(20, 3), P.call(34, 8), P.call(34, 18), P.call(33.3, 23), P.call(30.5, 28), P.call(26, 33), P.call(20, 37),
			P.call(14, 33), P.call(9.5, 28), P.call(6.7, 23), P.call(6, 18), P.call(6, 8)])
		_ci.draw_colored_polygon(esc, Color("2a4a9c"))
		esc.append(esc[0])
		_ci.draw_polyline(esc, OURO2, 2.5 * k, true)
		var ouro := OURO2
		_ci.draw_polyline(PackedVector2Array([P.call(20, 10), P.call(18.5, 14.5), P.call(20, 19), P.call(21.5, 14.5), P.call(20, 10)]), ouro, 2 * k, true)
		_ci.draw_polyline(PackedVector2Array([P.call(14, 17), P.call(15, 20), P.call(17.5, 21.6), P.call(20, 22), P.call(22.5, 21.6), P.call(25, 20), P.call(26, 17)]), ouro, 2 * k, true)
		_ci.draw_line(P.call(20, 22), P.call(20, 29), ouro, 2 * k, true)
		_ci.draw_line(P.call(16, 26), P.call(24, 26), ouro, 2 * k, true)

# =================================================================== SONS (feitos no código, como no site)
func _som_ok() -> bool:
	var s := get_node_or_null("/root/Sons")
	return Perfil.som and (s == null or s.ligado)

func _clique(forte: bool) -> void:
	if not _sons_prontos or not _som_ok():
		return
	_som_clique.stream = _wav_forte if forte else _wav_fraco
	_som_clique.play()

func _trovao() -> void:
	if _sons_prontos and _som_ok():
		_som_trovao.play()

func _criar_sons() -> void:
	_sons_prontos = true
	_wav_fraco = _wav_clique(980.0, 520.0, 0.08)
	_wav_forte = _wav_clique(720.0, 240.0, 0.22)
	# o trovão é maior: é feito numa thread separada para não travar a animação
	WorkerThreadPool.add_task(func():
		var w := _wav_trovao()
		_som_trovao.set_deferred("stream", w))

const TAXA := 22050

func _wav(bytes: PackedByteArray, taxa: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = taxa
	w.stereo = false
	w.data = bytes
	return w

func _wav_clique(f0: float, f1: float, ganho: float) -> AudioStreamWAV:
	var n := int(0.15 * TAXA)
	var b := PackedByteArray()
	b.resize(n * 2)
	var fase := 0.0
	var f := f0
	var rf := pow(f1 / f0, 1.0 / (0.09 * TAXA))     # a frequência cai um pouquinho a cada amostra
	var g := ganho * 2.5
	var rg := pow(0.001 / ganho, 1.0 / (0.14 * TAXA))
	for i in n:
		if i < 0.09 * TAXA:
			f *= rf
		fase += f / TAXA
		var tri := 4.0 * absf(fase - floorf(fase + 0.5)) - 1.0
		b.encode_s16(i * 2, int(clampf(tri * g, -1.0, 1.0) * 32000.0))
		if i < 0.14 * TAXA:
			g *= rg
	return _wav(b, TAXA)

func _wav_trovao() -> AudioStreamWAV:            # estalo + ronco grave (ruído filtrado que vai escurecendo)
	var taxa := 16000
	var n := int(2.2 * taxa)
	var b := PackedByteArray()
	b.resize(n * 2)
	var y := 0.0
	var y2 := 0.0
	var fc := 3200.0
	var rf := pow(140.0 / 3200.0, 1.0 / (1.6 * taxa))
	var subida := int(0.03 * taxa)
	var g := 0.55
	var rg := pow(0.001 / 0.55, 1.0 / (2.07 * taxa))
	var rng := RandomNumberGenerator.new()
	for i in n:
		if i < 1.6 * taxa:
			fc *= rf
		var x := TAU * fc / taxa
		var a := x - x * x * 0.5                 # = 1 - e^-x (aproximado, bem mais rápido)
		y += a * (rng.randf_range(-1.0, 1.0) - y)
		y2 += a * (y - y2)
		var ga := g * float(i) / subida if i < subida else g
		if i >= subida:
			g *= rg
		b.encode_s16(i * 2, int(clampf(y2 * ga * 3.2, -1.0, 1.0) * 32000.0))
	return _wav(b, taxa)
