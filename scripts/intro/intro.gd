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
	"Cada nível começa com o campo limpo: monte seu time de novo!",
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

## BATALHA DO MENU: uma partida rodando sem parar no fundo, como se alguém estivesse jogando.
## O SEU lado entra pela esquerda (o seu castelo) e o outro pela direita: andam, param no alcance, atacam
## (golpe, flecha, magia, raio, bomba), perdem vida, morrem — e novas tropas entram no lugar.
const RAIAS := [Vector2(352, 0.74), Vector2(440, 0.82), Vector2(528, 0.9), Vector2(616, 0.98)]   ## y dos pés, tamanho
const TIRO := {"arqueiro": "flecha", "esqueletoArqueiro": "flechaM", "mago": "magia", "esqueletoMago": "magiaM", "magoFogo": "fogo",
	"engenheiro": "energia", "esqueletoBombardeiro": "bomba"}
const COR_TIRO := {"flecha": Color("fff2c4"), "flechaM": Color("e8dfc8"), "magia": Color("7fd2ff"), "magiaM": Color("c08cff"), "fogo": Color("ff8a2a"),
	"energia": Color("40eaff"), "bomba": Color("ff9a3c")}
const SEM_ANDAR := ["elara", "esqueletoBlack"]     ## geradores de energia: não marcham
const MAX_POR_LADO := 7
const ENTRA_CADA := Vector2(1.2, 2.6)              ## segundos entre uma tropa nova e outra (de cada lado)
const RITMO := 1.3                                 ## a batalha do menu anda um pouco mais rápida que a partida
const ESCURECER := 0.1

## BOTÕES DO MENU (coluna da esquerda). "principal" = o grande; "meio" = metade da largura (lado a lado).
const BOTOES := [
	{"id": "novo", "txt": "Novo jogo", "icone": "espada", "principal": true},
	{"id": "pvp", "txt": "Batalha PvP", "icone": "espadas"},
	{"id": "personagens", "txt": "Personagens", "icone": "elmo"},
	{"id": "ranking", "txt": "Ranking e ligas", "icone": "barras"},
	{"id": "opcoes", "txt": "Opções", "icone": "engrenagem", "meio": true},
	{"id": "lado", "txt": "Trocar lado", "icone": "trocar", "meio": true},
]
const COL_W := 392.0                               ## largura da coluna de botões
const COL_Y := 202.0                               ## onde começa o botão grande

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
		"p1": Color("ffe98a"), "p2": Color("f0a21c"), "pc": Color("4a2a06"), "pico1": Color("fff6c8"), "pico2": Color("d08a12"),
		"acento": Color("f6c343"), "vidro1": Color("343d78"), "vidro2": Color("12152e")},
	"monsters": {"b1": Color("8a6fc9"), "b2": Color("523a8f"), "ico1": Color("c9b3ff"), "ico2": Color("3a2768"), "foco": Color(0.667, 0.941, 0.431, 0.55),
		"p1": Color("e2ff9e"), "p2": Color("6fc72a"), "pc": Color("123006"), "pico1": Color("f2ffd6"), "pico2": Color("4a9e1f"),
		"acento": Color("8be03c"), "vidro1": Color("2f3a52"), "vidro2": Color("0f1520")},
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
var tochas_m: Node2D
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
var ranking: Control                     # janela de Ranking e ligas (scripts/intro/ranking.gd)
var personagens: Control                 # janela de Personagens: evoluir (scripts/intro/personagens.gd)
var social: Control                      # Social: amigos, conversa, chat, duelo (scripts/intro/social.gd)
var modo_pvp: Control                    # escolha do modo: Batalha ou Cerco (scripts/intro/modo_pvp.gd)
var convidar: Control                    # CONVIDE AMIGOS: código de indicação (scripts/intro/convidar.gd)
var loja: Control                        # LOJA DE MOEDAS: abre tocando nas moedas do perfil (scripts/intro/loja.gd)
var _ret_moedas := Rect2()               # onde a pílula de moedas do perfil foi desenhada (toque = abre a loja)
var atualizacao: Control                 # ATUALIZAÇÃO pela Play Store dentro do jogo (scripts/intro/atualizacao.gd)
var tour: Control                        # TUTORIAL do menu com a mãozinha (scripts/intro/tour_menu.gd)
var dificuldade: Control                 # janela do Novo jogo: Fácil / Médio / Difícil / HardCore (scripts/intro/dificuldade.gd)
var modo_senha := false                  # tela de login mostrando "nome e senha"
var form_senha: Control                  # os dois campos de texto (nome e senha)
var campo_nome: LineEdit
var campo_senha: LineEdit
var msg_senha := ""
var senha_ocupado := false
var lutadores: Array = []                 # batalha do menu (cada um é um Dictionary)
var tiros: Array = []
var faiscas: Array = []
var _entra_t := [0.0, 0.0]
var _saco := [[], []]                     # personagens que ainda vão entrar (cada lado), embaralhados
var ondas_m: Array = []                   # ondas de terra / ossos
var espinhos: Array = []                  # pedras e ossos saindo do chão atrás da onda
var correntes_m: Array = []               # raio da Sobrecarga saltando
var orbes: Array = []                     # energia da Elara / Esqueleto Black
var circulos: Array = []                  # anéis no chão (impacto, invocação, explosão)
var _clarao_bomba: Array = []
var _tremor := 0.0
var _sacode := Vector2.ZERO
var fx_chao_m: FxExplosao                 # efeitos do jogo na batalha do menu (chão / ar)
var fx_ar_m: FxExplosao
var _hov_evento := 0.0
var _evento_em_foco := false
var logo_x := W / 2.0
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
	tochas_m = preload("res://scripts/arena/tochas_fundo.gd").new()   # fogo vivo nas tochas do fundo
	fundo.add_child(tochas_m)

	brasas = _criar_brasas()
	brasas.show_behind_parent = true
	add_child(brasas)

	# EFEITOS DA BATALHA DO MENU: as MESMAS camadas da partida (raio, fogo, portal, cura, luz, martelada...)
	fx_chao_m = FxExplosao.new()
	fx_chao_m.camada = "chao"
	fx_chao_m.show_behind_parent = true             # no chão: atrás dos personagens
	add_child(fx_chao_m)
	fx_ar_m = FxExplosao.new()
	fx_ar_m.camada = "ar"
	fx_ar_m.par_chao = fx_chao_m
	add_child(fx_ar_m)

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
	ranking = preload("res://scripts/intro/ranking.gd").new()
	ranking.intro = self
	add_child(ranking)
	personagens = preload("res://scripts/intro/personagens.gd").new()
	personagens.intro = self
	add_child(personagens)
	social = preload("res://scripts/intro/social.gd").new()
	social.intro = self
	add_child(social)
	dificuldade = preload("res://scripts/intro/dificuldade.gd").new()
	dificuldade.intro = self
	dificuldade.escolheu = _comecar_campanha
	add_child(dificuldade)
	_criar_form_senha()
	modo_pvp = preload("res://scripts/intro/modo_pvp.gd").new()
	modo_pvp.intro = self
	add_child(modo_pvp)
	convidar = preload("res://scripts/intro/convidar.gd").new()
	convidar.intro = self
	add_child(convidar)
	loja = preload("res://scripts/intro/loja.gd").new()
	loja.intro = self
	add_child(loja)
	tour = preload("res://scripts/intro/tour_menu.gd").new()     # (por último: fica por cima de tudo)
	tour.intro = self
	add_child(tour)
	atualizacao = preload("res://scripts/intro/atualizacao.gd").new()   # (por cima de tudo, até do tutorial)
	atualizacao.intro = self
	add_child(atualizacao)
	atualizacao.verificar.call_deferred()      # já no carregamento: tem versão nova? só entra depois de atualizar

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

	if Perfil.ja_entrou and Perfil.login_campeonato:   # veio do Campeonato para entrar na conta
		_entrar(Tela.LOGIN)
		logo_y = 26.0
		logo_a = 1.0
	elif Perfil.ja_entrou:               # voltou do jogo: direto para o menu
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
			_montar_batalha()                  # (de novo a cada entrada: o lado pode ter mudado)
	for p in placas:
		p.visible = tela == Tela.LADO
	tochas_m.usar(fundo.texture if tela == Tela.MENU else null, true)
	RenderingServer.set_default_clear_color(Color("05040a"))

func _ir(nova: int, depois := Callable()) -> void:
	if _indo_para >= 0:
		return
	_indo_para = nova
	_depois_cortina = depois

var _sobe_login := 0.0
func _process(dt: float) -> void:
	relogio += dt
	# LOGIN com nome e senha: o teclado do celular cobre os campos -> a tela toda sobe até o campo ficar à vista
	var alvo_sobe := 0.0
	if tela == Tela.LOGIN and modo_senha and form_senha and form_senha.visible:
		var focado: Control = campo_senha if campo_senha.has_focus() else campo_nome
		alvo_sobe = subida_teclado(focado, _ret_campo(1).end.y)
	_sobe_login = lerpf(_sobe_login, alvo_sobe, minf(1.0, dt * 14.0))
	if absf(position.y + _sobe_login) > 0.5 or (alvo_sobe == 0.0 and position.y != 0.0):
		position.y = -roundf(_sobe_login) if _sobe_login > 0.5 else 0.0
	t_tela += dt
	O = ((size - Vector2(W, H)) / 2.0).floor()
	if tochas_m.visible and fundo.texture:              # a imagem cobre a tela (centrada): o fogo acompanha
		var kf := maxf(fundo.size.x / fundo.texture.get_width(), fundo.size.y / fundo.texture.get_height())
		tochas_m.position = fundo.size / 2.0
		tochas_m.scale = Vector2(kf, kf)
	if form_senha:
		form_senha.position = O
		var mostra := modo_senha and tela == Tela.LOGIN and _indo_para < 0
		if form_senha.visible != mostra:
			form_senha.visible = mostra
	if fx_ar_m:
		fx_ar_m.position = O + _sacode
		fx_chao_m.position = O + _sacode
		fx_ar_m.visible = tela == Tela.MENU
		fx_chao_m.visible = tela == Tela.MENU
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
	if atualizacao and (atualizacao.segurando() or atualizacao.bloqueando()):
		return                             # (esperando a Play Store / tem que atualizar antes)
	_clique(true)
	Perfil.ja_entrou = true
	if conta and not conta.logado() and conta.status != "carregando" and not Perfil.convidado_ok:
		_ir(Tela.LOGIN)                    # 1ª vez: entrar com Google ou jogar como convidado (igual ao site)
	else:
		_depois_da_conta()

func _depois_da_conta() -> void:
	if Perfil.login_campeonato:                  # entrou pelo Campeonato: volta para a árvore (agora online)
		Perfil.login_campeonato = false
		Perfil.sala_modo = "campeonato"
		_ir(Tela.MENU, func(): get_tree().change_scene_to_file("res://cenas/sala_entrada.tscn"))
		return
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
	return Rect2(W / 2.0 - 190, 372, 380, 60)

func _ret_bt_senha() -> Rect2:
	return Rect2(W / 2.0 - 190, 444, 380, 54)

func _ret_bt_cancelar_login() -> Rect2:
	return Rect2(W / 2.0 - 120, 524, 240, 52)

func _ret_bt_convidado() -> Rect2:
	return Rect2(W / 2.0 - 190, 510, 380, 54)

# ---------------------------------------------------------------- LOGIN COM NOME E SENHA
func _ret_campo(i: int) -> Rect2:
	return Rect2(W / 2.0 - 230, 300 + i * 66, 460, 54)

func _ret_bt_entrar_senha() -> Rect2:
	return Rect2(W / 2.0 - 236, 468, 228, 56)

func _ret_bt_criar() -> Rect2:
	return Rect2(W / 2.0 + 8, 468, 228, 56)

func _ret_bt_voltar_senha() -> Rect2:
	return Rect2(W / 2.0 - 90, 540, 180, 46)

func _criar_form_senha() -> void:
	form_senha = Control.new()
	form_senha.mouse_filter = Control.MOUSE_FILTER_IGNORE
	form_senha.visible = false
	add_child(form_senha)
	campo_nome = _campo("Nome de usuário", false, 0)
	campo_senha = _campo("Senha (6 ou mais)", true, 1)
	campo_nome.text_submitted.connect(func(_t): campo_senha.grab_focus())
	campo_senha.text_submitted.connect(func(_t): _enviar_senha(false))

func _campo(dica: String, secreto: bool, i: int) -> LineEdit:
	var c := LineEdit.new()
	var r := _ret_campo(i)
	c.position = r.position
	c.size = r.size
	c.placeholder_text = dica
	c.secret = secreto
	c.max_length = 16 if not secreto else 64
	c.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD if secreto else LineEdit.KEYBOARD_TYPE_DEFAULT
	c.add_theme_font_override("font", f_texto)
	c.add_theme_font_size_override("font_size", 24)
	c.add_theme_color_override("font_color", Color("1c1630"))
	c.add_theme_color_override("font_placeholder_color", Color(0.11, 0.09, 0.19, 0.45))
	c.add_theme_color_override("caret_color", Color("2c3874"))
	for estado in ["normal", "focus", "read_only"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("fff8e6")
		sb.set_corner_radius_all(16)
		sb.set_border_width_all(3)
		sb.border_color = Color("f6c343") if estado == "focus" else Color("141a36")
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		c.add_theme_stylebox_override(estado, sb)
	form_senha.add_child(c)
	return c

func _abrir_senha() -> void:
	_clique(true)
	modo_senha = true
	msg_senha = ""
	form_senha.visible = true
	campo_nome.grab_focus()

func _fechar_senha() -> void:
	modo_senha = false
	form_senha.visible = false
	campo_nome.release_focus()
	campo_senha.release_focus()
	DisplayServer.virtual_keyboard_hide()

func _enviar_senha(criar: bool) -> void:
	if senha_ocupado or conta == null:
		return
	_clique(true)
	senha_ocupado = true
	msg_senha = "Criando sua conta..." if criar else "Entrando..."
	DisplayServer.virtual_keyboard_hide()
	var e: String = await conta.entrar_com_senha(campo_nome.text, campo_senha.text, criar)
	senha_ocupado = false
	msg_senha = e
	if e == "":
		campo_senha.text = ""
		_fechar_senha()
		Perfil.convidado_ok = true
		Perfil.salvar()
		if tela == Tela.LOGIN and _indo_para < 0:
			_depois_da_conta()

func _desenhar_form_senha(j: Rect2) -> void:
	var cx := j.get_center().x
	_texto_cartoon(Vector2(cx, j.position.y + 56), "Entrar com nome e senha", 34, CREME, f_titulo, 2.0, true)
	for i in 2:                                       # sombra atrás dos campos
		var r := _ret_campo(i)
		_caixa(Rect2(r.position + Vector2(0, 5), r.size), Color(0, 0, 0, 0.35), 16)
	if msg_senha != "":
		var cor := CREME if senha_ocupado else Color("ffb3a8")
		_texto_cartoon(Vector2(cx, 452), msg_senha, 17, cor, f_texto, 1.2, true)
	_botao_simples(_ret_bt_entrar_senha(), "Entrar", Color("ffe98a"), Color("c97a0c"), Color("4a2a06"))
	_botao_simples(_ret_bt_criar(), "Criar conta", Color("b6ff6a"), Color("3f8f1a"), Color("123006"))
	_botao_simples(_ret_bt_voltar_senha(), "Voltar", Color("6f86d6"), Color("2c3874"), NAVY)
	_texto_cartoon(Vector2(cx, j.end.y - 12), "Nome: 3 a 16 letras, números ou _ · use o mesmo nome e senha em qualquer aparelho", 13, Color("cfc8e8"), f_texto, 1.0, true)

func _desenhar_login() -> void:
	_degrade(Rect2(-O.x, -O.y, size.x, size.y), Color(0.02, 0.016, 0.047, 0.35), Color(0.02, 0.016, 0.047, 0.75))
	var j := _ret_login()
	_caixa(j.grow(9), Color(0, 0, 0, 0.35), 34, 0, Color(), 18, Vector2(0, 10), Color(0, 0, 0, 0.5))
	_caixa(j.grow(7), Color("4a2a06"), 32)
	_caixa(j.grow(5), OURO2, 30)
	_caixa(j.grow(1), Color("141a36"), 26)
	_painel(j, Color("3b4a8c"), Color("232c5c"), 25)
	var cx := j.get_center().x
	if modo_senha:
		_desenhar_form_senha(j)
		return
	_texto_cartoon(Vector2(cx, j.position.y + 64), "Bem-vindo, guerreiro!", 42, CREME, f_titulo, 2.0, true)
	_texto_cartoon(Vector2(cx, j.position.y + 110), "Entre na sua conta para salvar troféus, vitórias,", 19, Color("eef0ff"), f_texto, 1.5, true)
	_texto_cartoon(Vector2(cx, j.position.y + 136), "moedas e personagens, e jogar de qualquer lugar.", 19, Color("eef0ff"), f_texto, 1.5, true)
	var esperando: bool = conta != null and (conta.esperando_login or conta.status == "carregando")
	if esperando:
		_roda(Vector2(cx, j.position.y + 204))
		var t := "Escolha a conta no navegador..." if conta.esperando_login else "Carregando sua conta..."
		if conta.aviso_login != "":
			t = conta.aviso_login
		_texto_cartoon(Vector2(cx, j.position.y + 266), t, 21 if t.length() < 50 else 16, CREME, f_texto, 1.5, true)
		if conta.esperando_login and OS.has_feature("mobile"):   # no celular o jogo para enquanto o navegador está na frente
			_texto_cartoon(Vector2(cx, j.position.y + 292), "Depois de escolher, VOLTE PARA O JOGO para terminar.", 17, Color("ffd34d"), f_texto, 1.3, true)
		if conta.esperando_login:
			_botao_simples(_ret_bt_cancelar_login(), "Cancelar", Color("6f86d6"), Color("2c3874"), NAVY)
		return
	# botão do Google (branco, com o "G" colorido) — logo + texto centralizados juntos
	var g := _ret_bt_google()
	_caixa(Rect2(g.position + Vector2(0, 5), g.size).grow(3), Color("141a36"), 18)
	_caixa(g.grow(3), Color("141a36"), 18)
	_caixa(g, Color.WHITE, 16)
	_degrade(Rect2(g.position.x + 14, g.position.y + 4, g.size.x - 28, g.size.y * 0.35), Color(1, 1, 1, 0), Color(0, 0, 0, 0.04))
	var txt_g := "Entrar com Google"
	var r_logo := 16.0
	var espaco := 12.0
	var total := r_logo * 2.0 + espaco + _larg(f_titulo, txt_g, 26)
	var x0 := g.get_center().x - total / 2.0
	var cy := g.position.y + g.size.y / 2.0
	_logo_google(Vector2(x0 + r_logo, cy), r_logo)
	_texto(Vector2(x0 + r_logo * 2.0 + espaco, cy + 9), txt_g, 26, Color("3c4043"), f_titulo)
	_botao_simples(_ret_bt_senha(), "Entrar com nome e senha", Color("ffe98a"), Color("c97a0c"), Color("4a2a06"))
	_botao_simples(_ret_bt_convidado(), "Jogar como convidado", Color("6f86d6"), Color("2c3874"), NAVY)
	if conta and conta.aviso_login != "":                  # o que deu errado no último login (fica na tela)
		_texto_cartoon(Vector2(cx, j.position.y + 176), conta.aviso_login, 16, Color("ffb3a8"), f_texto, 1.2, true)
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
	if modo_senha:
		if senha_ocupado:
			return
		if _ret_bt_entrar_senha().has_point(p):
			_enviar_senha(false)
		elif _ret_bt_criar().has_point(p):
			_enviar_senha(true)
		elif _ret_bt_voltar_senha().has_point(p):
			_clique(false)
			_fechar_senha()
		return
	if conta and conta.esperando_login:
		if _ret_bt_cancelar_login().has_point(p):
			conta.cancelar_login()
			_clique(false)
		return
	if conta and conta.status == "carregando":
		return
	if _ret_bt_google().has_point(p):
		_entrar_google()
	elif _ret_bt_senha().has_point(p):
		_abrir_senha()
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
	var t := "Escolha a conta no navegador..." if conta.esperando_login else "Carregando sua conta..."
	_texto_cartoon(Vector2(j.get_center().x, j.position.y + 134), t, 21, CREME, f_texto, 1.5, true)
	if conta.esperando_login and OS.has_feature("mobile"):
		_texto_cartoon(Vector2(j.get_center().x, j.position.y + 160), "Depois de escolher, VOLTE PARA O JOGO.", 17, Color("ffd34d"), f_texto, 1.3, true)
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
		var ax := W / 2.0
		if tela == Tela.LADO:
			ay = -4.0
			aa = 0.0
		elif tela == Tela.MENU:                   # no menu: em cima da coluna de botões
			ak = 0.5
			ay = 104.0
			ax = _col_x() + COL_W / 2.0
		elif tela == Tela.LOGIN:
			ak = 0.8
		var s := 1.0 - exp(-dt * 7.0)
		logo_y = lerpf(logo_y, ay, s)
		logo_k = lerpf(logo_k, ak, s)
		logo_x = lerpf(logo_x, ax, s)
		logo_a = move_toward(logo_a, aa, dt * 2.6)
	logo.position = O + Vector2(logo_x, logo_y)
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
	if conta and conta.logado():
		conta.chamar("definir_lado", {"p_lado": Perfil.lado})   # (17_chat_duelo.sql) o selo do lado no chat/amigos
	get_tree().create_timer(1.0).timeout.connect(func(): _ir(Tela.MENU))

# ---------------------------------------------------------------- 3) menu
## REGISTRO (painel): que janela abriu (uma vez por abertura) e o "ao vivo" (o que está fazendo agora).
var _telas_abertas := {}
func _vigiar_telas() -> void:
	var telas := {"Ranking": ranking, "Personagens": personagens, "Social": social, "Convidar amigos": convidar,
		"Modo PvP": modo_pvp, "Dificuldade": dificuldade, "Loja": loja}
	var aberta := ""
	for nome in telas:
		var n: Control = telas[nome]
		var vis: bool = n != null and n.visible and (nome != "Social" or social._modo_janela)
		if vis:
			aberta = nome
		if vis and not _telas_abertas.get(nome, false):
			Conta.registrar("tela", {"nome": nome})
		_telas_abertas[nome] = vis
	if opcoes_aberta and not _telas_abertas.get("Opções", false):
		Conta.registrar("tela", {"nome": "Opções"})
	_telas_abertas["Opções"] = opcoes_aberta
	if opcoes_aberta:
		aberta = "Opções"
	if busca_ativa:
		aberta = "Procurando adversário"
	if tour and tour.ativo:
		aberta = "Tutorial"
	Conta.estou("menu", aberta)

func _atualizar_menu(dt: float) -> void:
	_vigiar_telas()
	if t_tela > 0.8 and atualizacao:
		atualizacao.verificar()            # (só uma vez por abertura do jogo)
	if not Perfil.tutorial_menu and tour and not tour.ativo and t_tela > 1.2 and _indo_para < 0 and not _janela_aberta() \
			and not busca_ativa and not opcoes_aberta and _acao_pendente == "" and not (conta and conta.esperando_login):
		tour.comecar()                     # 1ª vez no menu: mostra tudo com a mãozinha
	for i in BOTOES.size():
		_hov[i] = move_toward(_hov[i], 1.0 if (i == foco and not opcoes_aberta and not busca_ativa) else 0.0, dt * 7.0)
		_aperto[i] = move_toward(_aperto[i], 0.0, dt * 5.0)
	if _acao_pendente != "":
		_acao_t -= dt
		if _acao_t <= 0:
			var a := _acao_pendente
			_acao_pendente = ""
			_fazer(a)
	_hov_evento = move_toward(_hov_evento, 1.0 if _evento_em_foco else 0.0, dt * 7.0)
	_atualizar_busca(dt)
	_atualizar_batalha(dt)

## x da coluna de botões (colada na borda esquerda da tela, também em telas mais largas).
func _col_x() -> float:
	return _borda_esq() + 36.0

## Borda esquerda útil da tela: respeita o recorte da câmera / cantos arredondados (área segura do
## celular) e ainda deixa um respiro — em qualquer tamanho de celular o menu não fica colado na borda.
const RESPIRO_ESQ := 26.0
func _borda_esq() -> float:
	var inset := 0.0
	var janela := DisplayServer.window_get_size()
	if janela.x > 0 and OS.has_feature("mobile"):
		var seguro := DisplayServer.get_display_safe_area()
		var px := float(seguro.position.x - DisplayServer.window_get_position().x)
		inset = clampf(px, 0.0, janela.x * 0.12) * size.x / float(janela.x)   # (px da tela -> unidades do jogo)
	return -O.x + inset + RESPIRO_ESQ

func _ret_botao(i: int) -> Rect2:
	var x := _col_x()
	if i == 0:
		return Rect2(x, COL_Y, COL_W, 96)
	if BOTOES[i].get("meio", false):
		var j := i - 4
		return Rect2(x + j * (COL_W / 2.0 + 6.0), COL_Y + 110 + 3 * 66, COL_W / 2.0 - 6.0, 54)
	return Rect2(x, COL_Y + 110 + (i - 1) * 66, COL_W, 58)

## Cartão do CAMPEONATO embaixo da coluna (chama a atenção de quem chega).
func _ret_evento() -> Rect2:
	var u := _ret_botao(5)
	return Rect2(_col_x(), u.end.y + 16, COL_W, 74)

func _ret_perfil() -> Rect2:
	return Rect2(_borda_esq() + 22, -O.y + 20, 352, 86)

func _ret_bonus() -> Rect2:
	return Rect2(W + O.x - 22 - 262, -O.y + 96, 262, 64)

func _ret_convidar() -> Rect2:
	return Rect2(W + O.x - 22 - 262, H + O.y - 26 - 72, 262, 72)     # canto de baixo, à direita

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
			dificuldade.abrir()
		"opcoes":
			opcoes_aberta = true
		"lado":
			_ir(Tela.LADO)
		"pvp":
			modo_pvp.abrir()                  # Batalha (procura alguém) ou Cerco (contra o bot)
		"personagens":
			personagens.abrir()
		"ranking":
			ranking.abrir()

## Escolheu o modo na janela do PvP.
## Todos abrem a SALA DE ENTRADA (scripts/pvp/sala_entrada.gd): escolhe o lado vendo quem está entrando.
## Campeonato sem conta que ainda está no meio: volta direto para a árvore.
func _escolheu_modo_pvp(id: String) -> void:
	Perfil.pvp_sala = {}
	Perfil.pvp_adversario = ""
	Perfil.sala_modo = "batalha" if id == "normal" else id
	if id == "campeonato" and not Conta.online_pronto():
		Campeonato.carregar()
		if Campeonato.ativo and not Campeonato.online and Campeonato.fase <= 3 and not Campeonato.eliminado():
			_ir(Tela.MENU, func(): get_tree().change_scene_to_file("res://cenas/campeonato.tscn"))
			return
	_ir(Tela.MENU, func(): get_tree().change_scene_to_file("res://cenas/sala_entrada.tscn"))

func _comecar_campanha(_id: String) -> void:
	_ir(Tela.MENU, _abrir_jogo)                    # (a campanha já abre no lado escolhido no menu)

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

## Ranking ou Personagens aberto (eles cuidam dos próprios toques).
## TECLADO DO CELULAR: altura dele em unidades do jogo (0 = fechado). As janelas com campo de texto sobem
## para o campo ficar logo acima do teclado (senão o teclado cobre o que você está escrevendo).
func altura_teclado() -> float:
	var kb := DisplayServer.virtual_keyboard_get_height()
	if kb <= 0:
		return 0.0
	var ws := DisplayServer.window_get_size()
	return float(kb) * get_viewport_rect().size.y / maxf(1.0, float(ws.y))

## Quanto uma janela precisa subir para a linha "fundo_palco_y" (no palco) ficar acima do teclado.
func subida_teclado(campo: Control, fundo_palco_y: float) -> float:
	if campo == null or not campo.visible or not campo.has_focus():
		return 0.0
	var kb := altura_teclado()
	if kb <= 0.0:
		return 0.0
	return maxf(0.0, O.y + fundo_palco_y + 12.0 - (get_viewport_rect().size.y - kb))

func _janela_aberta() -> bool:
	return (atualizacao != null and atualizacao.bloqueando()) or (modo_pvp != null and modo_pvp.visible) or (convidar != null and convidar.visible) or (loja != null and loja.visible) or (ranking != null and ranking.visible) or (personagens != null and personagens.visible) or (dificuldade != null and dificuldade.visible) or (social != null and social.visible)

func _avisar(txt: String) -> void:
	aviso = txt
	aviso_t = 2.6

func _voltar() -> void:
	if tour and tour.ativo:
		return
	if modo_pvp and modo_pvp.visible:
		modo_pvp.fechar()
		_clique(false)
	elif convidar and convidar.visible:
		convidar.fechar()
		_clique(false)
	elif loja and loja.visible:
		loja.fechar()
		_clique(false)
	elif social and social.visible and social._modo_janela:
		social._modo_janela = false
		social.fechar()
		_clique(false)
	elif dificuldade and dificuldade.visible:
		dificuldade.fechar()
		_clique(false)
	elif personagens and personagens.visible:
		personagens.fechar()
		_clique(false)
	elif ranking and ranking.visible:
		ranking.fechar()
		_clique(false)
	elif busca_ativa:
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
	lutadores.clear()
	tiros.clear()
	faiscas.clear()
	ondas_m.clear()
	espinhos.clear()
	correntes_m.clear()
	orbes.clear()
	circulos.clear()
	_saco = [[], []]
	_entra_t = [0.2, 0.8]
	for i in 3:                                     # já abre com a luta acontecendo no meio
		_novo_lutador(0, true)
		_novo_lutador(1, true)

func _meu_lado() -> String:
	return "monsters" if Perfil.lado == "monsters" else "heroes"

func _lado_de(lado_i: int) -> String:
	return _meu_lado() if lado_i == 0 else ("heroes" if _meu_lado() == "monsters" else "monsters")

## SACO de personagens: todos aparecem na sua vez (embaralhados) — sempre algo diferente entrando.
func _proximo_do_saco(lado_i: int) -> String:
	var s: Array = _saco[lado_i]
	if s.is_empty():
		s.append_array(ConfigPvp.CARTAS_HEROES if _lado_de(lado_i) == "heroes" else ConfigPvp.CARTAS_MONSTERS)
		s.shuffle()
	return s.pop_back()

## Uma tropa nova. lado_i 0 = o seu (entra pela esquerda), 1 = o outro (entra pela direita).
## id/x/raia forçados: os esqueletos que o Esqueleto Mago invoca.
func _novo_lutador(lado_i: int, no_meio := false, id_forcado := "", x_forcado := INF, raia_forcada := -1) -> Dictionary:
	var cat := get_node_or_null("/root/Catalogo")
	if cat == null:
		return {}
	var id := id_forcado
	if id == "":
		for tentativa in 4:                         # gerador (Elara / Esqueleto Black): um por lado de cada vez
			id = _proximo_do_saco(lado_i)
			if not id in SEM_ANDAR or lutadores.filter(func(g): return g.lado_i == lado_i and g.gerador and g.estado != "morrer").is_empty():
				break
	var p: PersonagemDados = cat.get_p(id)
	if p == null:
		return {}
	var gerador := id in SEM_ANDAR
	var base := _anim_de(p, "parado" if gerador else "andar")
	if base == null:
		return {}
	var raia := raia_forcada
	if raia < 0 and id in ["aura", "esqueletoMistico"]:   # suporte: entra atrás de quem ele pode ajudar
		var amigos := [0, 0, 0, 0]
		for g in lutadores:
			if g.lado_i == lado_i and g.estado != "morrer":
				amigos[g.raia] += 1
		raia = amigos.find(amigos.max())
	if raia < 0:
		raia = randi() % RAIAS.size()
		if randf() < 0.75:                          # reforço onde o inimigo está em maior número
			var pontos := [0, 0, 0, 0]
			for f in lutadores:
				if f.estado != "morrer":
					pontos[f.raia] += 1 if f.lado_i != lado_i else -1
			var melhor := -99
			var opcoes: Array = []
			for k in RAIAS.size():
				if pontos[k] > melhor:
					melhor = pontos[k]
					opcoes = [k]
				elif pontos[k] == melhor:
					opcoes.append(k)
			raia = opcoes[randi() % opcoes.size()]
	var dir := 1.0 if lado_i == 0 else -1.0
	var x := (-O.x - 70.0) if dir > 0 else (W + O.x + 70.0)
	if gerador:                                     # gerador fica no posto, perto do castelo do lado dele
		x = (_col_x() + COL_W + 90.0) if dir > 0 else (W + O.x - 90.0)
	elif no_meio:
		x = W * 0.66 - dir * randf_range(60.0, 300.0)
	if x_forcado != INF:
		x = x_forcado
	var heroi := _lado_de(lado_i) == "heroes"
	var cfg := ConfigPvp.andar(p.id)
	var para: float = float(cfg.para) if heroi else (p.alcance if p.alcance > 0 else 45.0)
	if id == "esqueletoBombardeiro":
		para = 400.0                                # para longe e arremessa a bomba no primeiro da linha
	var vel: float = float(cfg.velocidade) if heroi else (p.velocidade if p.velocidade > 0 else 35.0)
	if p.extra.get("andar") is Dictionary:
		vel = float(p.extra.andar.get("velocidade", vel))
	var f := {"p": p, "id": p.id, "h": heroi, "lado_i": lado_i, "dir": dir, "x": x, "raia": raia,
		"y": RAIAS[raia].x + randf_range(-5.0, 5.0), "t": RAIAS[raia].y, "vida": float(p.vida), "vida_max": float(p.vida),
		"estado": "parado" if gerador else "andar", "tempo": randf(), "espera": 0.0, "flash": 0.0, "feitos": [], "alvo": null,
		"atq": "", "vel": vel, "para": clampf(para, 45.0, 400.0), "some": 0.0, "barra": 0.0, "gerador": gerador,
		"cd_esp": randf_range(0.5, 2.5), "tiros": 0, "q_ant": -1, "nasce": 1.0, "invocador": null, "escudo_t": 0.0,
		"estourou": false}
	lutadores.append(f)
	return f

func _anim_de(p: PersonagemDados, nome: String) -> AnimDados:
	var a: AnimDados = p.anim(nome)
	return a if (a and a.textura) else null

func _anim(f: Dictionary, nome: String) -> AnimDados:
	return _anim_de(f.p, nome)

## O inimigo mais perto na frente, na mesma raia.
func _inimigo_na_frente(f: Dictionary) -> Variant:
	var melhor: Variant = null
	var dist := INF
	for g in lutadores:
		if g.lado_i == f.lado_i or g.raia != f.raia or g.estado == "morrer":
			continue
		var d: float = (g.x - f.x) * f.dir
		if d > -12.0 and d < dist:
			dist = d
			melhor = g
	return melhor

## Um companheiro parado logo na frente (fila: ninguém passa por cima do outro).
func _amigo_na_frente(f: Dictionary) -> bool:
	for g in lutadores:
		if g == f or g.lado_i != f.lado_i or g.raia != f.raia or g.estado == "andar" or g.estado == "morrer":
			continue
		var d: float = (g.x - f.x) * f.dir
		if d > 0.0 and d < 58.0 * f.t:
			return true
	return false

func _atualizar_batalha(dt: float) -> void:
	dt *= RITMO
	_tremor = maxf(0.0, _tremor - dt * 18.0)
	_sacode = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _tremor
	var vivos := [0, 0]
	for f in lutadores:
		if f.estado != "morrer" and f.invocador == null:
			vivos[f.lado_i] += 1
	for i in 2:                                     # tropas novas dos dois lados (quem está perdendo manda mais rápido)
		_entra_t[i] -= dt
		if _entra_t[i] <= 0.0:
			_entra_t[i] = randf_range(ENTRA_CADA.x, ENTRA_CADA.y) * (0.6 if vivos[i] < vivos[1 - i] else 1.0)
			if vivos[i] < MAX_POR_LADO:
				_novo_lutador(i)
	for f in lutadores:
		f.tempo += dt
		f.flash = maxf(0.0, f.flash - dt * 4.0)
		f.barra = maxf(0.0, f.barra - dt)
		f.escudo_t = maxf(0.0, f.escudo_t - dt)
		f.cd_esp -= dt
		f.nasce = minf(1.0, f.nasce + dt * 1.8)
		if f.has("sobe") and float(f.sobe) < 1.0:     # invocado saindo do chão: ainda não age
			f.sobe = minf(1.0, float(f.sobe) + dt * 0.9)
			f.nasce = 1.0
			continue
		if f.has("voo"):                              # arremessado: voa e cai (não age)
			var v: Dictionary = f.voo
			v.t += dt
			var vk: float = clampf(float(v.t) / float(v.dur), 0.0, 1.0)
			f.x = lerpf(float(v.de), float(v.para), 1.0 - pow(1.0 - vk, 2.0))
			if vk >= 1.0:
				f.erase("voo")
				fx_ar_m.pouso(Vector2(f.x, f.y), f.t)
				fx_chao_m.pouso(Vector2(f.x, f.y), f.t)
				_tremor = maxf(_tremor, 5.0)
				_dano(f, float(v.dano))
			continue
		match f.estado:
			"morrer":
				var am := _anim(f, "morrer")
				if f.id == "esqueletoBombardeiro" and not f.estourou and am and int(f.tempo * am.fps) >= 38:
					f.estourou = true                       # o Bombardeiro explode quando cai
					_estouro_bomba(Vector2(f.x, f.y - 30.0 * f.t), f.t, true)
				if f.tempo > (am.duracao() + 0.5 if am else 0.25):
					f.some += dt * 1.8
			"atacar":
				var a := _anim(f, f.atq)
				if a == null:
					f.estado = "parado"
					continue
				var q := int(f.tempo * a.fps)
				if f.id == "darian" and f.atq == "especial" and q >= a.quadros - 2 and _ameaca_darian(f) < INF:
					f.tempo = float(a.quadros - 2) / a.fps          # segura o martelo na frente enquanto vem fogo
					continue
				if f.id == "darian" and f.atq == "atacar" and _ameaca_darian(f) < 600.0:
					_darian_bloquear(f)                              # fogo vindo: larga o golpe e bloqueia
					continue
				var momentos: Array = Array(a.quadros_acao) if a.quadros_acao.size() > 0 else [int(a.quadros * 0.55)]
				for k in momentos.size():
					if q >= momentos[k] and not f.feitos.has(k):
						f.feitos.append(k)
						_golpe(f, k)
				if q >= a.quadros:
					if f.atq == "especial":
						f.cd_esp = float(f.p.extra.get("recarga_terra", f.p.extra.get("recarga_ossos", f.p.extra.get("recarga_fogo", 6.0))))
					f.estado = "parado"
					f.tempo = 0.0
					f.espera = clampf((f.p as PersonagemDados).intervalo_ataque, 0.35, 1.4)
			_:
				if f.gerador:
					_gerar(f)
					continue
				if f.id == "darian" and _ameaca_darian(f) < 600.0:
					_darian_bloquear(f)
					continue
				if f.id in ["aura", "esqueletoMistico"] and _suporte_decide(f, dt):
					continue
				var alvo: Variant = _inimigo_na_frente(f)
				f.alvo = alvo
				var dist: float = absf(alvo.x - f.x) if alvo != null else INF
				var na_tela: bool = f.x > _col_x() + COL_W + 40.0 and f.x < W + O.x - 50.0
				var tem_invocado: bool = f.id == "aura" and not lutadores.filter(func(g): return g.lado_i != f.lado_i and g.invocador != null and g.estado != "morrer").is_empty()
				if tem_invocado and f.cd_esp <= 0.0 and _anim(f, "especial"):
					_comecar_ataque(f, "especial")      # Aura: abre o livro e a luz cai nos invocados
				elif f.cd_esp <= 0.0 and na_tela and f.id in ["sentinela", "esqueletoTita", "golemOssos"] and dist < 640.0 and _anim(f, "especial"):
					_comecar_ataque(f, "especial")      # o poder especial: onda de terra / ossos
				elif alvo != null and dist <= f.para * f.t + 18.0:
					if f.estado == "andar" or f.tempo >= f.espera:
						var nome := "atacar"
						if f.id == "esqueletoBombardeiro" and dist > 130.0 * f.t and _anim(f, "arremessar"):
							nome = "arremessar"
						_comecar_ataque(f, nome)
					elif f.estado != "parado":
						f.estado = "parado"
				elif _amigo_na_frente(f):
					if f.estado != "parado":
						f.estado = "parado"
						f.tempo = 0.0
				else:
					if f.estado != "andar":
						f.estado = "andar"
						f.tempo = 0.0
					f.x += f.dir * f.vel * f.t * dt
	# saiu do outro lado (entrou no castelo) ou terminou de sumir: sai da batalha
	lutadores = lutadores.filter(func(f): return f.some < 1.0 and f.x > -O.x - 140.0 and f.x < W + O.x + 140.0)
	_atualizar_tiros(dt)
	_atualizar_efeitos(dt)

## (Darian) Fogo / onda inimiga vindo pelo chão na raia dele (ou Golem inimigo preparando o fogo): distância.
func _ameaca_darian(f: Dictionary) -> float:
	var melhor := INF
	for o in ondas_m:
		if o.raia != f.raia or o.lado_i == f.lado_i:
			continue
		var d: float = (f.x - o.x) * o.dir
		if d > -10.0 and d < 900.0:
			melhor = minf(melhor, d)
	for g in lutadores:
		if g.lado_i != f.lado_i and g.raia == f.raia and g.id == "golemOssos" and g.estado == "atacar" and g.atq == "especial":
			melhor = minf(melhor, absf(g.x - f.x))
	return melhor

func _darian_bloquear(f: Dictionary) -> void:
	var a := _anim(f, "especial")
	if a == null:
		return
	if f.estado == "atacar" and f.atq == "especial":
		return
	f.estado = "atacar"
	f.atq = "especial"
	f.feitos = []
	f.tempo = float(58) / a.fps                    # já começa erguendo o martelo

func _darian_bloqueando(f: Dictionary) -> bool:
	if f.id != "darian" or f.estado != "atacar" or f.atq != "especial":
		return false
	var a := _anim(f, "especial")
	return a != null and int(f.tempo * a.fps) >= 72

## AURA / MÍSTICO no menu (iguais à partida): decidem curar / purificar / invocar; senão andam atrás da linha.
## Devolve true quando já resolveu este passo.
func _suporte_decide(f: Dictionary, dt: float) -> bool:
	f["cd_cura"] = float(f.get("cd_cura", 1.0)) - dt
	var ferido := false
	for g in lutadores:
		if g.lado_i == f.lado_i and g != f and g.raia == f.raia and g.estado != "morrer" and g.vida < g.vida_max * 0.9:
			var d: float = (g.x - f.x) * f.dir
			if d >= -10.0 and d <= 560.0:
				ferido = true
				break
	if f.id == "aura":
		var tem_inv := false
		for g in lutadores:
			if g.lado_i != f.lado_i and g.invocador != null and g.estado != "morrer":
				tem_inv = true
				break
		if tem_inv and f.cd_esp <= 0.0:
			_comecar_ataque(f, "especial")              # livro: a luz cai em TODOS os invocados
			return true
		if ferido and float(f.cd_cura) <= 0.0:
			_comecar_ataque(f, "atacar")                # cajado: cura quem está na frente
			return true
	else:
		var meus := 0
		for g in lutadores:
			if g.invocador == f and g.estado != "morrer":
				meus += 1
		var alvo: Variant = _inimigo_na_frente(f)
		if meus == 0 and f.cd_esp <= 0.0 and alvo != null and absf(alvo.x - f.x) < 700.0:
			_comecar_ataque(f, "atacar")                # portal de fogo: 3 esqueletos de fogo
			return true
		if ferido and float(f.cd_cura) <= 0.0:
			_comecar_ataque(f, "especial")              # cura os esqueletos na frente
			return true
	# nada a fazer: anda até ficar atrás da linha de frente
	var al: Variant = _inimigo_na_frente(f)
	if (al != null and absf(al.x - f.x) <= f.para * f.t + 18.0) or _amigo_na_frente(f):
		if f.estado != "parado":
			f.estado = "parado"
			f.tempo = 0.0
	else:
		if f.estado != "andar":
			f.estado = "andar"
			f.tempo = 0.0
		f.x += f.dir * f.vel * f.t * dt
	return true

func _comecar_ataque(f: Dictionary, nome: String) -> void:
	if _anim(f, nome) == null:
		return
	f.estado = "atacar"
	f.atq = nome
	f.tempo = 0.0
	f.feitos = []

## O momento do golpe (k = qual golpe da animação: o Titã e o Sentinela têm 2).
func _golpe(f: Dictionary, k: int) -> void:
	var p: PersonagemDados = f.p
	var dano := float(p.dano) * 1.5
	match f.id:
		"golemOssos":
			_golpe_golem(f, k)
			return
		"darian":
			_golpe_darian(f, k)
			return
		"aura":
			_golpe_aura(f)
			return
		"esqueletoMistico":
			_golpe_mistico(f)
			return
	if f.id in ["sentinela", "esqueletoTita"]:
		if f.atq == "especial":
			_onda(f)
		else:
			_golpe_area(f, dano)
		return
	var alvo: Variant = f.alvo
	if alvo == null or alvo.estado == "morrer":
		return
	match f.id:
		"esqueletoMago":
			_atirar(f, alvo, dano)
			f.tiros += 1
			if f.tiros % 3 == 0:
				_invocar(f)
		"engenheiro":
			f.tiros += 1
			_atirar(f, alvo, dano, f.tiros % 4 == 0)
		_:
			if TIRO.has(f.id):
				_atirar(f, alvo, dano)
				return
			_dano(alvo, dano)
			var cor := Color("ff9a3c") if f.id == "esqueletoFogo" else Color("fff2c4")
			_explosao(Vector2((f.x + alvo.x) / 2.0, f.y - 60.0 * f.t), cor, 12)
			if f.id == "esqueletoFogo":
				_explosao(Vector2(alvo.x, alvo.y - 40.0 * alvo.t), Color("ffcf5a"), 10)

## Escala com que a folha aparece no menu (para pôr os efeitos no lugar certo do desenho).
func _esc_folha(f: Dictionary, nome: String) -> float:
	var a := _anim(f, nome)
	return (f.p as PersonagemDados).escala * (a.escala if a else 1.0) * f.t

## Bordas da área da batalha (o raio vai até a ponta, sem passar por cima do menu).
func _ponta(sentido: float) -> float:
	return (W + O.x + 40.0) if sentido > 0.0 else (_col_x() + COL_W + 110.0)   # (o clarão da ponta não invade o menu)

## GOLEM (igual à partida): golpe 2 = raio para a FRENTE e depois para TRÁS (linha inteira);
## golpe 1 = coluna de fogo no chão e depois a parede de fogo correndo pela linha.
func _golpe_golem(f: Dictionary, k: int) -> void:
	var p: PersonagemDados = f.p
	var sc := _esc_folha(f, f.atq)
	if f.atq == "especial":
		var ponto := Vector2(f.x + f.dir * 75.0 * f.t, f.y)
		if k == 0:
			fx_ar_m.erupcao(ponto, f.t)
			fx_chao_m.erupcao(ponto, f.t)
			for g in lutadores:
				if g.lado_i != f.lado_i and g.raia == f.raia and g.estado != "morrer" and absf(g.x - ponto.x) < 110.0 * f.t:
					_dano(g, 60.0)
			_tremor = maxf(_tremor, 5.0)
		else:
			var p2 := Vector2(f.x + f.dir * 120.0 * f.t, f.y)
			fx_ar_m.erupcao(p2, f.t * 1.15)
			fx_chao_m.erupcao(p2, f.t * 1.15)
			_onda(f)
		return
	var tras := k == 1
	var s: float = -f.dir if tras else f.dir
	var ponto_r: Array = p.extra.get("raio_tras" if tras else "raio_frente", [50.0, 180.0])
	var dx := float(ponto_r[0]) * (0.35 if tras else 1.0)
	var de := Vector2(f.x + s * dx * sc, f.y - float(ponto_r[1]) * sc)
	fx_ar_m.raio(de, _ponta(s), 0.8 if tras else 0.6, f.t)
	for g in lutadores:
		if g.lado_i != f.lado_i and g.raia == f.raia and g.estado != "morrer" and (g.x - f.x) * s > -10.0:
			_dano(g, float(p.dano) * 1.5)
	_tremor = maxf(_tremor, 3.0)

## DARIAN (igual à partida): martelada (golpe 1 do ataque) e o golpe forte que ARREMESSA 5 casas para trás.
func _golpe_darian(f: Dictionary, k: int) -> void:
	if f.atq == "especial":
		return                                          # (bloqueio: quem para o fogo é a onda)
	var forte := k == 1
	var p: PersonagemDados = f.p
	var alcance: float = (p.alcance if p.alcance > 0 else 130.0) * f.t + 30.0
	var ponto := Vector2(f.x + f.dir * 85.0 * f.t, f.y)
	fx_ar_m.martelada(ponto, f.dir, forte)
	fx_chao_m.martelada(ponto, f.dir, forte)
	_tremor = maxf(_tremor, 7.0 if forte else 3.0)
	for g in lutadores:
		if g.lado_i == f.lado_i or g.raia != f.raia or g.estado == "morrer" or g.has("voo"):
			continue
		var d: float = (g.x - f.x) * f.dir
		if d < -10.0 or d > alcance:
			continue
		if forte:
			var pesado: bool = g.vida_max >= 1400.0
			var dist: float = 5.0 * 95.0 * f.t * (0.4 if pesado else 1.0)
			var para: float = clampf(g.x + f.dir * dist, _ponta(-1.0) + 20.0, _ponta(1.0) - 60.0)
			_dano(g, float(p.dano) * 0.6)
			if g.estado != "morrer":
				g["voo"] = {"de": g.x, "para": para, "t": 0.0, "dur": 0.25 + absf(para - g.x) / 900.0, "dano": float(p.dano) * 2.2}
		else:
			_dano(g, float(p.dano) * 1.5)
			g.flash = 1.0

## AURA (igual à partida): livro = LUZ DIVINA em todos os invocados; cajado = cura dourada nos da frente.
func _golpe_aura(f: Dictionary) -> void:
	var p: PersonagemDados = f.p
	if f.atq == "especial":
		f.cd_esp = float(p.extra.get("recarga_luz", 10.0)) * 0.6
		for g in lutadores:
			if g.lado_i != f.lado_i and g.invocador != null and g.estado != "morrer":
				fx_ar_m.luz_divina(Vector2(g.x, g.y))
				fx_chao_m.luz_divina(Vector2(g.x, g.y))
				_dano(g, float(p.extra.get("dano_sagrado", 220)))
		return
	f["cd_cura"] = float(p.extra.get("recarga_cura", 6.0)) * 0.6
	var sc := _esc_folha(f, "atacar")
	var cajado := Vector2(f.x + f.dir * 45.0 * sc, f.y - 330.0 * sc)
	_curar_frente(f, cajado, float(p.extra.get("cura", 110)), true)

## MÍSTICO (igual à partida): golpe 2 = portal de fogo com 3 esqueletos de fogo; golpe 1 = cura verde.
func _golpe_mistico(f: Dictionary) -> void:
	var p: PersonagemDados = f.p
	if f.atq == "atacar":
		f.cd_esp = float(p.extra.get("recarga_invocar", 16.0)) * 0.6
		_invocar(f, "esqueletoFogo")
		return
	f["cd_cura"] = float(p.extra.get("recarga_cura", 7.0)) * 0.6
	var sc := _esc_folha(f, "especial")
	var mao := Vector2(f.x + f.dir * 60.0 * sc, f.y - 150.0 * sc)
	_curar_frente(f, mao, float(p.extra.get("cura", 90)), false)

func _curar_frente(f: Dictionary, de: Vector2, valor: float, dourada: bool) -> void:
	for g in lutadores:
		if g.lado_i != f.lado_i or g == f or g.raia != f.raia or g.estado == "morrer" or g.vida >= g.vida_max:
			continue
		var d: float = (g.x - f.x) * f.dir
		if d < -10.0 or d > 560.0:
			continue
		g.vida = minf(g.vida_max, g.vida + valor)
		g.barra = 2.0
		fx_ar_m.cura(de, Vector2(g.x, g.y), dourada)
		fx_chao_m.cura(de, Vector2(g.x, g.y), dourada)
## Titã / Sentinela: o golpe pega TODOS na frente (e o chão treme).
func _golpe_area(f: Dictionary, dano: float) -> void:
	var p: PersonagemDados = f.p
	var alcance: float = (p.alcance if p.alcance > 0 else 130.0) * f.t + 24.0
	for g in lutadores:
		if g.lado_i != f.lado_i and g.raia == f.raia and g.estado != "morrer":
			var d: float = (g.x - f.x) * f.dir
			if d >= -10.0 and d <= alcance:
				_dano(g, dano)
	var pc := Vector2(f.x + f.dir * alcance * 0.6, f.y)
	circulos.append({"pos": pc, "t": 0.0, "dur": 0.45, "r": 70.0 * f.t, "cor": Color("e8d8b0"), "runa": false})
	_explosao(pc + Vector2(0, -10), Color("c8b088"), 16)
	_tremor = maxf(_tremor, 4.0)

## ONDA DE TERRA (Sentinela) / OSSOS (Titã): corre pela linha e acerta cada inimigo uma vez.
func _onda(f: Dictionary) -> void:
	var p: PersonagemDados = f.p
	var terra: bool = f.id == "sentinela"
	if f.id == "golemOssos":                         # o Golem varre o FOGO pela linha
		if f.feitos.size() < 2:
			circulos.append({"pos": Vector2(f.x + f.dir * 40.0 * f.t, f.y), "t": 0.0, "dur": 0.5, "r": 70.0 * f.t, "cor": Color("ff7a1a"), "runa": false})
			_explosao(Vector2(f.x + f.dir * 40.0 * f.t, f.y - 10.0), Color("ffb347"), 18)
			return
		ondas_m.append({"tipo": "fogo", "raia": f.raia, "y": f.y, "t": f.t, "lado_i": f.lado_i, "x0": f.x + f.dir * 60.0 * f.t,
			"x": f.x + f.dir * 60.0 * f.t, "dir": f.dir, "dist": 0.0, "prox": 9999.0, "atingidos": [], "idade": 0.0,
			"vel": float(p.extra.get("velocidade_fogo", 520.0)), "dano": float(p.extra.get("dano_fogo", 110.0)) * 1.3})
		_tremor = maxf(_tremor, 6.0)
		return
	ondas_m.append({"tipo": "terra" if terra else "ossos", "raia": f.raia, "y": f.y, "t": f.t, "lado_i": f.lado_i,
		"x": f.x + f.dir * 40.0 * f.t, "dir": f.dir, "dist": 0.0, "prox": 0.0, "atingidos": [],
		"vel": float(p.extra.get("velocidade_onda" if terra else "velocidade_ossos", 620.0)),
		"dano": float(p.extra.get("dano_terra" if terra else "dano_ossos", 100.0)) * 1.3})
	_tremor = maxf(_tremor, 7.0)
	circulos.append({"pos": Vector2(f.x + f.dir * 30.0 * f.t, f.y), "t": 0.0, "dur": 0.6, "r": 90.0 * f.t,
		"cor": Color("a8875a") if terra else Color("efe6d0"), "runa": false})

## ESQUELETO MAGO: invoca 3 esqueletos (na linha dele e nas vizinhas), na frente dele.
func _invocar(f: Dictionary, id := "esqueleto") -> void:
	var fogo := id == "esqueletoFogo"
	for d in [-1, 0, 1]:
		var r: int = f.raia + d
		if r < 0 or r >= RAIAS.size():
			continue
		var x: float = f.x + f.dir * 80.0 * f.t
		var m := _novo_lutador(f.lado_i, false, id, x, r)
		if m.is_empty():
			continue
		m.invocador = f
		m.nasce = 0.0
		m["sobe"] = 0.0                                 # sai de dentro do chão
		var pr := Vector2(x, m.y)
		fx_chao_m.invocacao(pr, "fogo" if fogo else "sombra")      # o mesmo portal da partida
		fx_ar_m.invocacao(pr, "fogo" if fogo else "sombra")
		if fogo:
			m.vida_max *= 0.5
			m.vida = m.vida_max

## ELARA / ESQUELETO BLACK: a energia sai da mão no quadro certo e voa para o lado dele.
func _gerar(f: Dictionary) -> void:
	var a := _anim(f, "parado")
	var em: Dictionary = f.p.extra.get("energia_mao", {})
	if a == null or em.is_empty():
		return
	var q := int((f.tempo + f.x * 0.01) * a.fps) % a.quadros
	var alvo_q := int(em.quadro)
	var passou: bool = f.q_ant >= 0 and ((q >= alvo_q and f.q_ant < alvo_q) or (q < f.q_ant and (f.q_ant < alvo_q or q >= alvo_q)))
	f.q_ant = q
	if passou:
		var pd: PersonagemDados = f.p
		var mao := Vector2(f.x + float(em.x) * f.t * f.dir, f.y + float(em.y) * f.t * 1.15)
		orbes.append({"pos": mao, "de": mao, "t": 0.0, "lado_i": f.lado_i})

func _dano(alvo: Dictionary, d: float) -> void:
	if d <= 0.0 or alvo.estado == "morrer":
		return
	# ESCUDO: o Protetor parado e o Sentinela no meio do golpe seguram parte do dano
	var bloq := false
	if alvo.id in ["protetor", "esqueletoProtetor"] and alvo.estado != "andar":
		d *= 1.0 - (alvo.p as PersonagemDados).defesa
		bloq = true
	elif alvo.id == "sentinela" and alvo.estado == "atacar" and alvo.atq == "atacar":
		var a := _anim(alvo, "atacar")
		var q := int(alvo.tempo * a.fps) if a else 0
		if q >= 64 and q <= 92:
			d *= 1.0 - (alvo.p as PersonagemDados).defesa
			bloq = true
	if bloq:
		alvo.escudo_t = 0.35
	alvo.vida -= d
	alvo.flash = 1.0
	alvo.barra = 2.5
	if alvo.vida <= 0.0:
		alvo.vida = 0.0
		alvo.estado = "morrer"
		alvo.tempo = 0.0
		_explosao(Vector2(alvo.x, alvo.y - 30.0 * alvo.t), Color("d8d0c0"), 14)
		if alvo.id in ["esqueletoMago", "esqueletoMistico"]:   # o Mago / Místico caiu: os que ele chamou somem
			for g in lutadores:
				if g.invocador == alvo and g.estado != "morrer":
					g.estado = "morrer"
					g.tempo = 0.0
					_explosao(Vector2(g.x, g.y - 30.0 * g.t), Color("9b6bff"), 14)

## Altura da cabeça (para a barra de vida e o número de dano).
func _altura(f: Dictionary) -> float:
	var a := _anim(f, "andar")
	if a == null:
		a = _anim(f, "parado")
		if a == null:
			return 90.0
	return a.ay * (f.p as PersonagemDados).escala * a.escala * f.t * 0.82


func _atirar(f: Dictionary, alvo: Dictionary, dano: float, sobrecarga := false) -> void:
	var tipo: String = TIRO[f.id]
	var x0: float = f.x + f.dir * 46.0 * f.t
	var y0: float = f.y - 88.0 * f.t
	var x1: float = alvo.x - f.dir * 14.0 * alvo.t
	var y1: float = alvo.y - 70.0 * alvo.t
	var longe: bool = f.atq == "arremessar"
	if tipo == "bomba":
		y0 = f.y - 110.0 * f.t
		y1 = alvo.y - 20.0 * alvo.t
	var vel := 620.0 if tipo.begins_with("flecha") else (330.0 if tipo == "bomba" else 440.0)
	var dur := absf(x1 - x0) / vel
	if tipo == "energia":
		dur = 0.12                                  # o raio do Engenheiro: chega na hora (o desenho é o da partida)
		fx_ar_m.raio_eletrico(Vector2(x0, y0), Vector2(alvo.x, alvo.y), _altura(alvo) * 1.1, 1.6 if sobrecarga else 1.0)
		fx_chao_m.raio_eletrico(Vector2(x0, y0), Vector2(alvo.x, alvo.y), _altura(alvo) * 1.1, 1.0)
	tiros.append({"tipo": tipo, "x0": x0, "y0": y0, "x1": x1, "y1": y1, "k": 0.0, "fim": false, "alvo": alvo, "dano": dano,
		"dur": maxf(0.14, dur), "cor": COR_TIRO[tipo], "sobre": sobrecarga, "dir": f.dir, "lado_i": f.lado_i,
		"raia": alvo.raia, "arco": (150.0 if longe else 70.0) if tipo == "bomba" else (28.0 if tipo.begins_with("flecha") else 10.0), "t": f.t})

func _atualizar_tiros(dt: float) -> void:
	for s in tiros:
		s.k += dt / s.dur
		if s.k < 1.0 or s.fim:
			continue
		s.fim = true
		var alvo: Variant = s.alvo
		var acertou: bool = alvo != null and alvo.estado != "morrer" and absf(alvo.x - s.x1) < 70.0
		if s.tipo == "bomba":                        # explode no chão: o primeiro leva tudo, os vizinhos o dano em área
			_estouro_bomba(Vector2(s.x1, s.y1), s.t, false)
			if acertou:
				_dano(alvo, s.dano)
			for g in lutadores:
				if g != alvo and g.lado_i != s.lado_i and g.raia == s.raia and g.estado != "morrer" and absf(g.x - s.x1) <= 95.0 * s.t:
					_dano(g, 90.0)
			continue
		if acertou:
			_dano(alvo, s.dano)
			if s.sobre:
				_sobrecarga(alvo, s.dano, s.dir, s.lado_i)
		if s.tipo == "magia" or s.tipo == "fogo":     # magia explode em área (o fogo espalha brasas)
			circulos.append({"pos": Vector2(s.x1, s.y1 + 50.0 * s.t), "t": 0.0, "dur": 0.4, "r": 50.0 * s.t, "cor": s.cor, "runa": false})
		_explosao(Vector2(s.x1, s.y1), s.cor, 14)
	tiros = tiros.filter(func(s): return not s.fim)

## SOBRECARGA do Engenheiro (a cada 4 tiros): o raio salta para mais 2 inimigos atrás do primeiro.
func _sobrecarga(alvo: Dictionary, dano: float, dir: float, lado_i: int) -> void:
	var atras: Array = []
	for g in lutadores:
		if g != alvo and g.lado_i != lado_i and g.raia == alvo.raia and g.estado != "morrer":
			var d: float = (g.x - alvo.x) * dir
			if d > 0.0 and d < 280.0:
				atras.append(g)
	atras.sort_custom(func(a, b): return absf(a.x - alvo.x) < absf(b.x - alvo.x))
	var de := Vector2(alvo.x, alvo.y - 60.0 * alvo.t)
	var parte := [0.6, 0.4]
	for i in mini(2, atras.size()):
		var g: Dictionary = atras[i]
		var para := Vector2(g.x, g.y - 60.0 * g.t)
		fx_ar_m.raio_eletrico(de, Vector2(g.x, g.y), _altura(g) * 1.1, 1.8)
		_dano(g, dano * parte[i])
		de = para

func _estouro_bomba(p: Vector2, t: float, grande: bool) -> void:
	var k := 1.5 if grande else 1.0
	var chao_y := p.y + 22.0 * t
	fx_ar_m.explodir(p, (1.55 if grande else 1.0) * t, chao_y)     # a explosão da partida
	fx_chao_m.explodir(Vector2(p.x, chao_y), (1.4 if grande else 1.0) * t)
	_tremor = maxf(_tremor, 6.0 * k)
	return
	_explosao(p, Color("ffb347"), int(26 * k))
	_explosao(p, Color("ffe08a"), int(12 * k))
	_explosao(p, Color("5a4a3a"), int(10 * k))
	circulos.append({"pos": p + Vector2(0, 16.0 * t), "t": 0.0, "dur": 0.5, "r": 85.0 * t * k, "cor": Color("ff9a3c"), "runa": false})
	_clarao_bomba.append({"pos": p, "t": 0.0, "r": 60.0 * t * k})
	_tremor = maxf(_tremor, 6.0 * k)

func _atualizar_efeitos(dt: float) -> void:
	# ondas de terra / ossos correndo pela linha
	for o in ondas_m:
		var passo: float = o.vel * dt
		o.x += o.dir * passo
		o["idade"] = float(o.get("idade", 0.0)) + dt
		o.dist += passo
		o.prox -= passo
		if o.prox <= 0.0:
			o.prox = 24.0 * o.t
			espinhos.append({"x": o.x + randf_range(-4.0, 4.0), "y": o.y + randf_range(-3.0, 3.0), "t": 0.0, "tipo": o.tipo,
				"h": randf_range(30.0, 50.0) * o.t, "w": randf_range(14.0, 22.0) * o.t, "inc": randf_range(-0.25, 0.25)})
			_explosao(Vector2(o.x, o.y - 6.0), Color("8a6a3a") if o.tipo == "terra" else Color("efe6d0"), 3)
		for g in lutadores:
			if g.lado_i != o.lado_i and g.raia == o.raia and _darian_bloqueando(g) and absf(g.x - o.x) < 34.0:
				# DARIAN com o martelo na frente: a onda PARA nele (escudo de luz e o fogo espirrando)
				var cor := Color(1.0, 0.55, 0.12) if o.tipo == "fogo" else (Color(0.95, 0.92, 0.82) if o.tipo == "ossos" else Color(0.65, 0.5, 0.3))
				fx_ar_m.bloqueio(Vector2(g.x, g.y), g.dir, cor)
				fx_chao_m.bloqueio(Vector2(g.x, g.y), g.dir, cor)
				if o.tipo == "fogo":
					fx_ar_m.apagar_fogo(o.x0, o.x, o.y - 2.0, float(o.get("idade", 0.0)), float(o.raia) * 1.3)
				o.dist = 99999.0
				break
		if o.dist > 9999.0:
			continue
		for g in lutadores:
			if g.lado_i != o.lado_i and g.raia == o.raia and g.estado != "morrer" and not o.atingidos.has(g) and absf(g.x - o.x) < 30.0:
				o.atingidos.append(g)
				_dano(g, o.dano)
	ondas_m = ondas_m.filter(func(o): return o.dist < 1000.0 and o.x > -O.x - 60.0 and o.x < W + O.x + 60.0)
	for e in espinhos:
		e.t += dt
	espinhos = espinhos.filter(func(e): return e.t < 0.8)
	for c in correntes_m:
		c.t += dt
	correntes_m = correntes_m.filter(func(c): return c.t < 0.4)
	for c in circulos:
		c.t += dt
	circulos = circulos.filter(func(c): return c.t < c.dur)
	for c in _clarao_bomba:
		c.t += dt
	_clarao_bomba = _clarao_bomba.filter(func(c): return c.t < 0.3)
	# energia: sobe da mão e voa para o lado de quem gerou
	for b in orbes:
		b.t += dt
		if b.t < 0.7:
			b.pos = b.de + Vector2(0, -50.0 * _ease_out(b.t / 0.7))
		else:
			var destino := (_ret_perfil().get_center()) if b.lado_i == 0 else Vector2(W + O.x - 40.0, -O.y + 40.0)
			var k := clampf((b.t - 0.7) / 0.8, 0.0, 1.0)
			b.pos = (b.de + Vector2(0, -50.0)).lerp(destino, k * k)
	for b in orbes:
		if b.t >= 1.5:
			_explosao(b.pos, Color("ffe066"), 10)
	orbes = orbes.filter(func(b): return b.t < 1.5)
	for p in faiscas:
		p.vida += dt
		p.pos += p.vel * dt
		p.vel.y += 260.0 * dt
	faiscas = faiscas.filter(func(p): return p.vida < p.max)

static func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 2.0)

func _explosao(p: Vector2, cor: Color, n: int) -> void:
	if faiscas.size() > 260:
		return
	for i in n:
		faiscas.append({"pos": p, "vel": Vector2((randf() - 0.5) * 260.0, -randf() * 220.0), "vida": 0.0,
			"max": 0.3 + randf() * 0.4, "cor": cor, "r": 1.5 + randf() * 2.5})

# =================================================================== ENTRADA (toque, mouse, teclado)
func _input(ev: InputEvent) -> void:
	if tour and tour.ativo:                # o tutorial cuida dos toques (o que ele deixa passar vai para as janelas)
		return
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
				if busca_ativa or _janela_aberta():
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
		if _janela_aberta():
			return
		var p: Vector2 = ev.position - position - O
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
					_evento_em_foco = _ret_evento().has_point(p)
					mao = mao or _evento_em_foco or _ret_convidar().has_point(p) or _ret_perfil().has_point(p)
				else:
					mao = true
			Tela.CARGA:
				mao = pronta
			Tela.LOGIN:
				mao = _ret_bt_google().has_point(p) or _ret_bt_convidado().has_point(p) or _ret_bt_senha().has_point(p)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if mao else Control.CURSOR_ARROW
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_tocar(ev.position - position - O)

func _tocar(p: Vector2) -> void:
	if _indo_para >= 0 or _janela_aberta():   # (o ranking / personagens cuidam dos toques deles)
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
			if atualizacao and atualizacao.tocar_faixa(p):
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
			if _ret_evento().has_point(p):              # cartão do Campeonato: direto para a sala de entrada
				_clique(true)
				_escolheu_modo_pvp("campeonato")
			elif _ret_convidar().has_point(p):
				_clique(true)
				convidar.abrir()
			elif _ret_moedas.grow(8).has_point(p):         # moedas do perfil: abre a LOJA
				_clique(true)
				loja.abrir()
			elif _ret_perfil().has_point(p):
				_clique(false)
				ranking.abrir("ligas")
			elif p.distance_to(_centro_social()) < 40:
				_clique(false)
				social.abrir()

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
	l.append({"id": "tutorial", "txt": "Como jogar (tutorial)", "bt": "Ver"})
	if conta and conta.logado():
		l.append({"id": "conta", "txt": "Conta: " + Perfil.nome.get_slice(" ", 0), "bt": "Sair"})
		l.append({"id": "apagar", "txt": "Apagar conta e dados", "bt": "Confirmar?" if _apagar_t > 0.0 else "Apagar"})
	else:
		l.append({"id": "conta", "txt": "Conta: convidado", "bt": "Sair", "vermelho": true})
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
				"tutorial":
					opcoes_aberta = false
					Perfil.tutorial_jogo = false       # a próxima campanha mostra a primeira batalha guiada de novo
					Perfil.salvar()
					tour.comecar()
				"conta":
					if conta and conta.logado():
						conta.sair()
						_avisar("Você saiu da conta. Agora é convidado.")
					else:
						opcoes_aberta = false
						_ir(Tela.LOGIN)                # escolhe: Google ou nome e senha
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
		if atualizacao and atualizacao.segurando():
			txt = "Procurando atualização..."
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
	var lado := "monsters" if Perfil.lado == "monsters" else "heroes"
	var tm: Dictionary = TEMA[lado]
	# luz de cinema: escurece em cima, embaixo e na esquerda (onde fica a coluna), a batalha fica viva no meio
	_degrade(Rect2(r.position.x, r.position.y, r.size.x, H * 0.3 + O.y), Color(0.02, 0.022, 0.05, 0.6), Color(0.02, 0.022, 0.05, 0))
	_degrade(Rect2(r.position.x, H * 0.78, r.size.x, r.end.y - H * 0.78), Color(0.02, 0.022, 0.05, 0), Color(0.02, 0.022, 0.05, 0.55))
	_desenhar_batalha()
	var cx := _col_x()
	var esq := Color(0.02, 0.022, 0.05, 0.78)
	var nada := Color(0.02, 0.022, 0.05, 0)
	_ci.draw_polygon(PackedVector2Array([Vector2(r.position.x, r.position.y), Vector2(cx + COL_W + 170, r.position.y),
		Vector2(cx + COL_W + 170, r.end.y), Vector2(r.position.x, r.end.y)]), PackedColorArray([esq, nada, nada, esq]))
	# a "janela" de vidro atrás dos botões
	var jan := Rect2(cx - 16, COL_Y - 16, COL_W + 32, _ret_evento().end.y - COL_Y + 32)
	_caixa(jan, Color(0.03, 0.035, 0.08, 0.55), 26, 1, Color(tm.acento, 0.22))
	_ci.draw_line(Vector2(jan.position.x + 26, jan.position.y + 1), Vector2(jan.end.x - 26, jan.position.y + 1), Color(tm.acento, 0.55), 2.0, true)
	for i in BOTOES.size():
		_desenhar_botao(i, tm)
	_desenhar_evento(tm)
	_desenhar_perfil(lado)
	_desenhar_bonus()
	_desenhar_convidar()
	_desenhar_social()
	if aviso_t <= 0 and not OS.has_feature("mobile"):
		var y := H - 14.0
		var txt := "para escolher  ·  Enter para confirmar"
		var w := _larg(f_texto, txt, 14) + 34.0
		var x0 := cx + COL_W / 2.0 - w / 2.0
		_seta(Vector2(x0 + 6, y - 6), 1)
		_seta(Vector2(x0 + 20, y - 6), -1)
		_texto_cartoon(Vector2(x0 + 34, y), txt, 14, Color(0.92, 0.9, 0.85, 0.7), f_texto, 1.0, false)

## O que aparece embaixo do nome de cada botão.
func _sub_botao(id: String) -> String:
	var lado := _meu_lado()
	match id:
		"novo":
			var rec := 0
			for d in ["facil", "medio", "dificil", "hardcore"]:
				rec = maxi(rec, Perfil.recorde(d, lado))
			return "Campanha infinita · Recorde: nível %d" % rec if rec > 0 else "Campanha infinita · comece agora!"
		"pvp":
			return "Batalha · Cerco · Campeonato"
		"personagens":
			return "Evolua seus %s até o nível 15" % ("heróis" if lado == "heroes" else "monstros")
		"ranking":
			return "Liga %s · %d troféus" % [str(Perfil.liga().nome), Perfil.trofeus]
	return ""

func _desenhar_botao(i: int, tm: Dictionary) -> void:
	var b: Dictionary = BOTOES[i]
	var r := _ret_botao(i)
	if b.get("principal", false):
		_botao_principal(r, b, tm, _hov[i], _aperto[i])
		return
	var hv := _hov[i]
	var ap := _aperto[i]
	var ac: Color = tm.acento
	var rr := Rect2(r.position + Vector2(5.0 * hv, 4.0 * ap), r.size)
	var raio := 16
	_caixa(Rect2(rr.position + Vector2(0, 6), rr.size), Color(0, 0, 0, 0.45), raio)
	if hv > 0.01:
		_caixa(rr.grow(6), Color(ac, 0.16 * hv), raio + 5)
	_caixa(rr.grow(2), Color(ac.darkened(0.55), 0.95).lerp(ac, hv * 0.85), raio + 2)
	_painel(rr, (tm.vidro1 as Color).lightened(0.12 * hv), tm.vidro2, raio)
	# faixa de cor do lado + brilho em cima
	_caixa(Rect2(rr.position.x + 3, rr.position.y + 10, 4, rr.size.y - 20), ac.lerp(Color.WHITE, 0.25 * hv), 2)
	_ci.draw_line(Vector2(rr.position.x + 16, rr.position.y + 2), Vector2(rr.end.x - 16, rr.position.y + 2), Color(1, 1, 1, 0.12 + 0.12 * hv), 1.5, true)
	var meio: bool = b.get("meio", false)
	var cy := rr.get_center().y
	# medalhão do ícone
	var ic := Vector2(rr.position.x + (30.0 if meio else 38.0), cy)
	var ri := 17.0 if meio else 21.0
	_ci.draw_circle(ic, ri + 3, CONTORNO)
	_bola(ic, ri + 1, ac.lightened(0.35), ac.darkened(0.5))
	_icone(b.icone, ic, ri * 1.15, Color("1c1206"), Color(0, 0, 0, 0))
	# texto
	var tx := ic.x + ri + 14
	var sub := "" if meio else _sub_botao(b.id)
	var tam := 19 if meio else 23
	_texto_cartoon(Vector2(tx, cy + (-3.0 if sub != "" else tam * 0.36)), b.txt, tam, Color.WHITE, f_titulo, 1.6, false)
	if sub != "":
		_texto(Vector2(tx + 1, cy + 18), sub, 13, Color(0.83, 0.86, 1.0, 0.78 + 0.2 * hv), f_texto, 3, Color(0, 0, 0, 0.55))
	if not meio:                                     # seta ">" (anda um pouco no foco)
		var sx := rr.end.x - 26 + 4.0 * hv
		_ci.draw_polyline(PackedVector2Array([Vector2(sx - 5, cy - 9), Vector2(sx + 4, cy), Vector2(sx - 5, cy + 9)]), Color(ac, 0.55 + 0.45 * hv), 3.5, true)

## O botão grande: NOVO JOGO (a campanha), dourado ou verde, pulsando com um brilho passando.
func _botao_principal(r: Rect2, b: Dictionary, tm: Dictionary, hv: float, ap: float) -> void:
	var pul := 0.5 + 0.5 * sin(relogio * 2.6)
	var k := 1.0 + 0.02 * hv - 0.03 * ap
	var c := r.get_center() + Vector2(0, 5.0 * ap - 2.0 * hv)
	draw_set_transform(O + c, 0, Vector2(k, k))
	var rr := Rect2(-r.size / 2.0, r.size)
	var p2: Color = tm.p2
	for g in 3:
		_caixa(rr.grow(5 + g * 6 + pul * 3), Color(p2, 0.13 - g * 0.035 + 0.06 * hv), 26 + g * 5)
	_caixa(Rect2(rr.position + Vector2(0, 9), rr.size).grow(3), Color(0, 0, 0, 0.5), 24)
	_caixa(Rect2(rr.position + Vector2(0, 6), rr.size).grow(3), tm.pc, 24)
	_caixa(rr.grow(3), tm.pc, 24)
	_botao_degrade(rr, (tm.p1 as Color).lightened(0.06 * hv), (tm.p1 as Color).lerp(p2, 0.45), p2, 21)
	# brilho passando
	var sh := fmod(relogio * 0.45, 1.7) - 0.35
	if sh > 0.0 and sh < 1.0:
		var x := rr.position.x + 20 + (rr.size.x - 40) * sh
		var x0 := maxf(rr.position.x + 18, x - 30)
		var x1 := minf(rr.end.x - 18, x + 20)
		if x1 > x0 + 4:
			_ci.draw_colored_polygon(PackedVector2Array([Vector2(x0 + 14, rr.position.y + 4), Vector2(x1 + 14, rr.position.y + 4),
				Vector2(x1 - 6, rr.end.y - 5), Vector2(x0 - 6, rr.end.y - 5)]), Color(1, 1, 1, 0.22))
	# medalhão com o "play"
	var ic := Vector2(rr.position.x + 52, 0)
	_ci.draw_circle(ic, 34, tm.pc)
	_bola(ic, 31, Color("3a2a12") if _meu_lado() == "heroes" else Color("173a0c"), Color("120a02") if _meu_lado() == "heroes" else Color("061204"))
	_ci.draw_arc(ic, 31, 0, TAU, 40, Color(tm.p1, 0.55), 2.0, true)
	var tri := PackedVector2Array([ic + Vector2(-9, -15), ic + Vector2(17, 0), ic + Vector2(-9, 15)])
	_ci.draw_colored_polygon(tri, Color(tm.p1).lightened(0.2))
	# texto
	var tx := rr.position.x + 100
	_texto_cartoon(Vector2(tx, -2), b.txt.to_upper(), 34, Color.WHITE, f_titulo, 2.2, false)
	_texto(Vector2(tx + 2, 26), _sub_botao(b.id), 14, Color(tm.pc).lerp(Color.BLACK, 0.1), f_texto)
	draw_set_transform(O)

## Cartão do CAMPEONATO: troféu, "ao vivo", botão JOGAR — o convite para o modo novo.
func _desenhar_evento(tm: Dictionary) -> void:
	var r0 := _ret_evento()
	var hv := _hov_evento
	var r := Rect2(r0.position + Vector2(5.0 * hv, 0), r0.size)
	var pul := 0.5 + 0.5 * sin(relogio * 3.0)
	_caixa(Rect2(r.position + Vector2(0, 6), r.size), Color(0, 0, 0, 0.45), 16)
	_caixa(r.grow(4 + pul * 2), Color(OURO2, 0.1 + 0.08 * hv), 20)
	_caixa(r.grow(2), Color(OURO3, 0.95).lerp(OURO2, hv), 18)
	_painel(r, Color("5a3a12").lightened(0.1 * hv), Color("1c1006"), 16)
	var sh := fmod(relogio * 0.35 + 0.5, 1.8) - 0.4
	if sh > 0.0 and sh < 1.0:
		var x := r.position.x + 16 + (r.size.x - 60) * sh
		_ci.draw_colored_polygon(PackedVector2Array([Vector2(x + 12, r.position.y + 3), Vector2(x + 40, r.position.y + 3),
			Vector2(x + 22, r.end.y - 3), Vector2(x - 6, r.end.y - 3)]), Color(1, 0.95, 0.7, 0.13))
	var ti := Vector2(r.position.x + 40, r.get_center().y + 1)
	for g in 6:                                    # raios atrás do troféu
		var a := relogio * 0.6 + g * TAU / 6.0
		_ci.draw_colored_polygon(PackedVector2Array([ti, ti + Vector2(cos(a), sin(a)) * 34, ti + Vector2(cos(a + 0.3), sin(a + 0.3)) * 34]), Color(1, 0.85, 0.3, 0.12))
	_trofeu(ti, 40)
	_texto_cartoon(Vector2(r.position.x + 74, r.position.y + 32), "CAMPEONATO", 22, OURO2, f_titulo, 1.6, false)
	_ci.draw_circle(Vector2(r.position.x + 80, r.position.y + 52), 4 + pul, Color(1, 0.25, 0.2, 0.35))
	_ci.draw_circle(Vector2(r.position.x + 80, r.position.y + 52), 3.5, Color("ff4a3a"))
	_texto(Vector2(r.position.x + 90, r.position.y + 57), "16 jogadores · Heroes × Monsters", 13, Color("ffe7b0"), f_texto, 3, Color(0, 0, 0, 0.55))
	var bt := Rect2(r.end.x - 98, r.get_center().y - 19, 84, 38)
	_caixa(bt.grow(2 + pul * 2), Color(VERDE2, 0.2), 14)
	_caixa(Rect2(bt.position + Vector2(0, 4), bt.size).grow(2), VERDE3.darkened(0.5), 13)
	_caixa(bt.grow(2), VERDE3.darkened(0.5), 13)
	_botao_degrade(bt, VERDE1, VERDE2, VERDE3, 12)
	_texto_cartoon(Vector2(bt.get_center().x, bt.position.y + 27), "JOGAR", 19, Color.WHITE, f_titulo, 1.4, true)
	var tag := Rect2(r.end.x - 66, r.position.y - 11, 58, 22)
	_caixa(tag.grow(2), CONTORNO, 11)
	_botao_degrade(tag, Color("ffb4a0"), Color("ff5a3a"), Color("a82010"), 10)
	_texto_cartoon(Vector2(tag.get_center().x, tag.position.y + 17), "NOVO", 14, Color.WHITE, f_titulo, 1.0, true)

func _desenhar_perfil(lado: String) -> void:
	var r := _ret_perfil()
	var tm: Dictionary = TEMA[lado]
	var ac: Color = tm.acento
	_caixa(Rect2(r.position + Vector2(0, 6), r.size), Color(0, 0, 0, 0.45), 20)
	_caixa(r.grow(2), Color(ac.darkened(0.45), 0.95), 20)
	_painel(r, tm.vidro1, tm.vidro2, 18)
	_ci.draw_line(Vector2(r.position.x + 18, r.position.y + 2), Vector2(r.end.x - 18, r.position.y + 2), Color(1, 1, 1, 0.14), 1.5, true)
	# foto redonda com aro da cor do lado
	var c := Vector2(r.position.x + 44, r.get_center().y)
	_ci.draw_circle(c, 33, CONTORNO)
	_ci.draw_arc(c, 31, 0, TAU, 40, ac, 3.0, true)
	_ci.draw_circle(c, 29, Color("10142a") if lado == "heroes" else Color("0c1a08"))
	if conta and conta.logado() and conta.foto:
		var tex: Texture2D = conta.foto
		var ts := tex.get_size()
		var q := minf(ts.x, ts.y)
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in 32:
			var a := TAU * i / 32.0
			var d := Vector2(cos(a), sin(a))
			pts.append(c + d * 28)
			uvs.append((Vector2((ts.x - q) / 2.0, (ts.y - q) / 2.0) + (d * 0.5 + Vector2(0.5, 0.5)) * q) / ts)
		var cs := PackedColorArray()
		cs.resize(32)
		cs.fill(Color.WHITE)
		_ci.draw_polygon(pts, cs, uvs, tex)
	elif conta and conta.logado():
		_bola(c, 28, Color("4f9fff"), Color("1f5fb6"))
		_texto_cartoon(Vector2(c.x, c.y + 11), Perfil.nome.left(1).to_upper(), 30, Color.WHITE, f_titulo, 1.5, true)
	else:
		_brasao(lado, c, 40.0)
	# nome + selo do lado
	var x := c.x + 44
	# nome + crachá do lado: os dois têm que caber ANTES do selo da liga (que fica no canto direito)
	var sl := "MONSTERS" if lado == "monsters" else "HEROES"
	var sw := _larg(f_titulo, sl, 12) + 18
	var limite := r.end.x - 68.0                      # (começo do selo da liga)
	var nome := Perfil.nome
	var tam_n := 21
	while tam_n > 15 and x + _larg(f_titulo, nome, tam_n) > limite:
		tam_n -= 1                                     # primeiro diminui a letra...
	while nome.length() > 2 and x + _larg(f_titulo, nome, tam_n) > limite:
		nome = nome.left(nome.length() - 2) + "."      # ...depois abrevia o nome
	_texto_cartoon(Vector2(x, r.position.y + 30), nome, tam_n, Color.WHITE, f_titulo, 1.5, false)
	# troféus e moedas em "pílulas"
	var y := r.position.y + 50
	var t1 := str(Perfil.trofeus)
	var p1 := Rect2(x - 2, y, _larg(f_texto, t1, 14) + 38, 24)
	_caixa(p1, Color(0, 0, 0, 0.38), 12, 1, Color(1, 1, 1, 0.08))
	_trofeu(Vector2(p1.position.x + 13, p1.get_center().y), 17)
	_texto(Vector2(p1.position.x + 26, p1.position.y + 17.5), t1, 14, Color.WHITE, f_texto, 3, CONTORNO)
	var t2 := str(Perfil.moedas)
	var p2 := Rect2(p1.end.x + 6, y, _larg(f_texto, t2, 14) + 58, 24)
	_caixa(p2, Color(0, 0, 0, 0.38), 12, 1, Color(1, 1, 1, 0.08))
	_moeda(Vector2(p2.position.x + 13, p2.get_center().y), 17)
	_texto(Vector2(p2.position.x + 26, p2.position.y + 17.5), t2, 14, Color("ffe58a"), f_texto, 3, CONTORNO)
	# "+" verde: tocar nas moedas abre a LOJA (pulsa de leve para chamar atenção)
	var mais := Vector2(p2.end.x - 12, p2.get_center().y)
	var pul := 1.0 + 0.08 * sin(relogio * 4.0)
	_ci.draw_circle(mais, 10.5 * pul, CONTORNO)
	_bola(mais, 9.0 * pul, Color("d9ff9a"), Color("3f8f1a"))
	_ci.draw_line(mais - Vector2(4.5, 0), mais + Vector2(4.5, 0), Color.WHITE, 2.6, true)
	_ci.draw_line(mais - Vector2(0, 4.5), mais + Vector2(0, 4.5), Color.WHITE, 2.6, true)
	_ret_moedas = p2
	# crachá do lado (HEROES / MONSTERS) na mesma linha, antes do selo da liga — bem legível
	var tam_s := 12
	while tam_s > 9 and p2.end.x + 6 + _larg(f_titulo, sl, tam_s) + 14 > limite:
		tam_s -= 1                                     # (muitas moedas: o crachá diminui a letra para caber)
	sw = _larg(f_titulo, sl, tam_s) + (18 if tam_s == 12 else 14)
	if p2.end.x + 6 + sw > limite:
		sl = "H" if lado == "heroes" else "M"
		sw = _larg(f_titulo, sl, tam_s) + 14
	var sr := Rect2(p2.end.x + 6, y, sw, 24)
	_caixa(Rect2(sr.position + Vector2(0, 2), sr.size), Color(0, 0, 0, 0.35), 12)
	_caixa(sr, Color(ac.darkened(0.35), 0.95), 12, 2, ac.lightened(0.15))
	_texto(Vector2(sr.position.x + (sw - _larg(f_titulo, sl, tam_s)) / 2.0, sr.position.y + 12.0 + tam_s * 0.45), sl, tam_s, Color.WHITE, f_titulo, 3, CONTORNO)
	# liga
	var lg := Perfil.liga()
	var lc := Vector2(r.end.x - 38, r.position.y + 34)
	var tex2 := _textura(["liga/" + str(lg.img), "liga/" + str(lg.nome), "liga/" + str(lg.nome).to_lower()])
	_ci.draw_circle(lc, 30, Color(1, 0.85, 0.4, 0.07 + 0.04 * sin(relogio * 2.0)))
	if tex2:
		var s := 50.0 / maxf(tex2.get_width(), tex2.get_height())
		var tam := Vector2(tex2.get_width(), tex2.get_height()) * s
		draw_texture_rect(tex2, Rect2(lc - tam / 2.0 + Vector2(0, 3), tam), false, Color(0, 0, 0, 0.5))
		draw_texture_rect(tex2, Rect2(lc - tam / 2.0, tam), false)
	else:
		_escudo(lc, 22.0, lg.cor)
	var ln: String = lg.nome
	_texto(Vector2(lc.x - _larg(f_texto, ln, 12) / 2.0, r.end.y - 6), ln, 12, Color("ffe7a6"), f_texto, 3, CONTORNO)

func _desenhar_bonus() -> void:
	var r := _ret_bonus()
	var b := Perfil.bonus_hoje()
	var tm: Dictionary = TEMA[_meu_lado()]
	_caixa(Rect2(r.position + Vector2(0, 5), r.size), Color(0, 0, 0, 0.4), 16)
	_caixa(r.grow(2), Color((tm.acento as Color).darkened(0.5), 0.9), 17)
	_painel(r, tm.vidro1, tm.vidro2, 15)
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

## Botão CONVIDE AMIGOS (rosa, com presente, brilho passando e "NOVO!" até abrir a primeira vez).
func _desenhar_convidar() -> void:
	var r0 := _ret_convidar()
	var pul := 1.0 + 0.025 * sin(relogio * 3.2)
	var c0 := r0.get_center()
	var r := Rect2(c0 - r0.size * pul / 2.0, r0.size * pul)
	var brilho := 0.5 + 0.5 * sin(relogio * 3.2)
	for i in 3:
		_caixa(r.grow(4 + i * 5 + brilho * 3), Color(1, 0.4, 0.7, 0.10 - i * 0.03), 26 + i * 5)
	_caixa(Rect2(r.position + Vector2(0, 6), r.size).grow(3), Color(0, 0, 0, 0.45), 22)
	_caixa(r.grow(3), Color("3a0620"), 22)
	_botao_degrade(r, Color("ffb3d9"), Color("e0458f"), Color("7a1450"), 19)
	var sh := fmod(relogio * 0.5, 2.2) - 0.4                         # brilho passando
	if sh > 0.0 and sh < 1.0:
		var x := r.position.x + r.size.x * sh
		draw_colored_polygon(PackedVector2Array([Vector2(x, r.position.y + 3), Vector2(x + 34, r.position.y + 3), Vector2(x + 8, r.end.y - 3), Vector2(x - 26, r.end.y - 3)]), Color(1, 1, 1, 0.22))
	_presente(Vector2(r.position.x + 40, r.get_center().y - 2), 50.0, relogio)
	_texto_cartoon(Vector2(r.position.x + 74, r.position.y + 32), "CONVIDE AMIGOS", 21, Color.WHITE, f_titulo, 1.6, false)
	_texto(Vector2(r.position.x + 75, r.position.y + 55), "Ganhe até +400 moedas", 14, Color("fff0a8"), f_texto, 3, Color("4a0a2a"))
	for i in 3:                                                       # estrelinhas
		var a := relogio * 2.0 + i * 2.1
		var p := r.position + Vector2(r.size.x * (0.35 + 0.28 * i), 8 + 6 * sin(a))
		var k := 0.5 + 0.5 * sin(a * 1.7)
		_estrela(p, 5.0 + 3.0 * k, Color(1, 1, 0.85, 0.5 + 0.5 * k))
	if not Perfil.convite_visto:
		var tag := Rect2(r.end.x - 62, r.position.y - 12, 66, 24)
		_caixa(tag.grow(2), CONTORNO, 12)
		_botao_degrade(tag, Color("fff3b0"), Color("f6c343"), Color("b8740f"), 11)
		_texto_cartoon(Vector2(tag.get_center().x, tag.position.y + 18), "NOVO!", 15, Color.WHITE, f_titulo, 1.1, true)

func _estrela(c: Vector2, r: float, cor: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := i * PI / 4.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.35))
	_ci.draw_colored_polygon(pts, cor)

## PRESENTE (caixa com fita e laço). t = tempo (o laço balança).
func _presente(c: Vector2, tam: float, t := 0.0) -> void:
	var k := tam / 64.0
	var ci := _ci
	var corpo := Rect2(c + Vector2(-24, -6) * k, Vector2(48, 32) * k)
	var tampa := Rect2(c + Vector2(-28, -18) * k, Vector2(56, 13) * k)
	var g := 3.0 * k
	ci.draw_style_box(_sb(CONTORNO, int(6 * k)), corpo.grow(g))
	ci.draw_style_box(_sb(CONTORNO, int(5 * k)), tampa.grow(g))
	var bal := sin(t * 3.0) * 0.12
	for lado: float in [-1.0, 1.0]:                                    # laço
		var base := c + Vector2(0, -18) * k
		var ponta := base + Vector2(lado * 15, -13).rotated(bal * lado) * k
		ci.draw_circle(ponta, 9.5 * k, CONTORNO)
		ci.draw_circle(ponta, 7 * k, Color("ffd34d"))
		ci.draw_circle(ponta + Vector2(-lado * 2, 1) * k, 3 * k, Color("c98a12"))
	ci.draw_style_box(_sb(Color("e0458f"), int(6 * k)), corpo)
	ci.draw_rect(Rect2(corpo.position.x, corpo.position.y + corpo.size.y * 0.55, corpo.size.x, corpo.size.y * 0.45), Color(0.5, 0.05, 0.3, 0.35))
	ci.draw_style_box(_sb(Color("ff7ab8"), int(5 * k)), tampa)
	ci.draw_rect(Rect2(tampa.position.x + 4 * k, tampa.position.y + 2 * k, tampa.size.x - 8 * k, 3 * k), Color(1, 1, 1, 0.35))
	ci.draw_rect(Rect2(c.x - 5 * k, corpo.position.y, 10 * k, corpo.size.y), Color("ffd34d"))       # fita
	ci.draw_rect(Rect2(c.x - 5 * k, tampa.position.y, 10 * k, tampa.size.y), Color("ffd34d"))
	ci.draw_circle(c + Vector2(0, -18) * k, 5 * k, CONTORNO)
	ci.draw_circle(c + Vector2(0, -18) * k, 3.5 * k, Color("ffe58a"))

## BAÚ das metas de recrutador (aberto e brilhando quando já ganhou).
func _bau(c: Vector2, tam: float, aberto: bool, t := 0.0) -> void:
	var k := tam / 40.0
	var ci := _ci
	if aberto:
		var pul := 0.5 + 0.5 * sin(t * 4.0)
		ci.draw_circle(c, 24 * k + pul * 3, Color(1, 0.85, 0.3, 0.3))
	var corpo := Rect2(c + Vector2(-16, -4) * k, Vector2(32, 18) * k)
	var tampa := Rect2(c + Vector2(-16, -16) * k, Vector2(32, 12) * k)
	if aberto:
		tampa.position.y -= 7 * k
	ci.draw_style_box(_sb(CONTORNO, int(4 * k)), corpo.grow(2.5 * k))
	ci.draw_style_box(_sb(CONTORNO, int(5 * k)), tampa.grow(2.5 * k))
	ci.draw_style_box(_sb(Color("a0601a"), int(4 * k)), corpo)
	ci.draw_style_box(_sb(Color("c97a22"), int(5 * k)), tampa)
	if aberto:
		ci.draw_rect(Rect2(corpo.position.x + 3 * k, corpo.position.y - 4 * k, corpo.size.x - 6 * k, 6 * k), Color("ffd34d"))
	ci.draw_rect(Rect2(corpo.position.x, corpo.position.y + 5 * k, corpo.size.x, 3 * k), Color("ffd34d"))
	ci.draw_rect(Rect2(c.x - 3 * k, corpo.position.y, 6 * k, 8 * k), Color("ffe58a"))
	if not aberto:
		ci.draw_rect(Rect2(c.x - 2 * k, corpo.position.y + 1 * k, 4 * k, 5 * k), CONTORNO)

func _desenhar_social() -> void:
	var c := _centro_social()
	draw_circle(c + Vector2(0, 6), 34, Color(0, 0, 0, 0.35))
	draw_circle(c, 34, Color("0c0e17"))
	draw_circle(c, 32, Color("8a6526"))
	draw_circle(c, 29, Color("0c0e17"))
	_bola(c, 27, Color("ffe58a"), Color("d8921a"))
	_icone("pessoas", c, 30, Color("2a1804"), Color(0, 0, 0, 0))
	var n: int = social.avisos() if social else 0
	if n <= 0:                                       # nada novo: em verde, quantos amigos estão online
		var txt := str(social.online() if social else 0)
		var lw := maxf(24.0, _larg(f_texto, txt, 12) + 12)
		var on := Rect2(c + Vector2(-lw / 2.0, 22), Vector2(lw, 16))
		_caixa(on.grow(2), Color("0c0e17"), 10)
		_caixa(on, VERDE2, 8)
		_texto(Vector2(c.x - _larg(f_texto, txt, 12) / 2.0, on.end.y - 3), txt, 12, Color("0c1a06"), f_texto)
		return
	# TEM ALGO NOVO: número grande, vermelho, pulando, com brilho em volta
	var pul := 0.5 + 0.5 * sin(relogio * 6.0)
	for i in 3:
		draw_circle(c, 38 + i * 6 + pul * 6, Color(1, 0.3, 0.2, 0.10 - i * 0.03))
	var txt2 := str(n) if n < 100 else "99+"
	var pulo := absf(sin(relogio * 4.0)) * 6.0
	var k := 1.0 + 0.15 * pul
	var bc := c + Vector2(24, 22 - pulo)
	var br := 18.0 * k + (5.0 if txt2.length() > 1 else 0.0)
	draw_circle(bc + Vector2(0, 3), br + 3, Color(0, 0, 0, 0.35))
	draw_circle(bc, br + 3, Color("0c0e17"))
	_bola(bc, br, Color("ff7a6a"), Color("d61f1f"))
	_texto_cartoon(Vector2(bc.x, bc.y + 9 * k), txt2, int(26 * k), Color.WHITE, f_titulo, 1.4, true)

func _desenhar_batalha() -> void:
	var o_antes := O
	O = O + _sacode                                  # o chão treme nos golpes fortes
	draw_set_transform(O)
	var esc := Color(1.0 - ESCURECER, 1.0 - ESCURECER, 1.0 - ESCURECER * 0.7)
	# anéis no chão (atrás de todos)
	for c in circulos:
		var k: float = c.t / c.dur
		var cor: Color = c.cor
		draw_set_transform(O + c.pos, 0, Vector2(1, 0.3))
		var rr: float = c.r * (0.35 + 0.65 * _ease_out(k))
		draw_circle(Vector2.ZERO, rr, Color(cor, 0.16 * (1.0 - k)))
		draw_arc(Vector2.ZERO, rr, 0, TAU, 40, Color(cor, 0.85 * (1.0 - k)), 4.0, true)
		if c.runa:                                   # círculo mágico da invocação, girando
			draw_arc(Vector2.ZERO, rr * 0.72, 0, TAU, 32, Color(cor.lightened(0.3), 0.7 * (1.0 - k)), 2.0, true)
			for j in 6:
				var a: float = relogio * 2.5 + j * TAU / 6.0
				draw_circle(Vector2(cos(a), sin(a)) * rr * 0.86, 3.5, Color(cor.lightened(0.5), 0.9 * (1.0 - k)))
	draw_set_transform(O)
	# luz da energia no chão sob a onda
	for o in ondas_m:
		if o.tipo == "fogo":                         # Golem: o fogo correndo pelo chão (o mesmo do jogo)
			draw_set_transform(O)
			FxExplosao.desenhar_onda_fogo(self, o.x0, o.x, o.y - 2.0, o.idade, float(o.raia) * 1.3)
			continue
		draw_set_transform(O + Vector2(o.x, o.y), 0, Vector2(1, 0.3))
		draw_circle(Vector2.ZERO, 40.0 * o.t, Color(Color("c89a5a") if o.tipo == "terra" else Color("fff2d8"), 0.22))
	draw_set_transform(O)
	# todos em ordem de profundidade (quem está mais embaixo fica na frente), com os espinhos da onda junto
	var lista: Array = []
	for f in lutadores:
		lista.append([f.y, 0, f])
	for e in espinhos:
		lista.append([e.y + 1.0, 1, e])
	lista.sort_custom(func(a, b): return a[0] < b[0])
	for it in lista:
		if it[1] == 0:
			_desenhar_lutador(it[2], esc)
		else:
			_desenhar_espinho(it[2])
	# tiros
	for s in tiros:
		var k: float = s.k
		var tipo: String = s.tipo
		if tipo == "energia":                       # (o raio é desenhado pela camada de efeitos, igual à partida)
			continue
		if false:
			var a0 := Vector2(s.x0, s.y0)
			var a1 := Vector2(s.x1, s.y1)
			var pts := _ziguezague(a0, a1, 8, 7.0)
			var grosso := 1.6 if s.sobre else 1.0
			draw_polyline(pts, Color(0.25, 0.9, 1.0, 0.35), 9.0 * grosso, true)
			draw_polyline(pts, Color(0.85, 1.0, 1.0, 0.95), 2.5 * grosso, true)
			draw_circle(a0, 9.0 * grosso, Color(0.4, 0.95, 1.0, 0.6))
			draw_circle(a1, 12.0 * grosso, Color(0.4, 0.95, 1.0, 0.5))
			continue
		var arco: float = s.arco
		var p := Vector2(lerpf(s.x0, s.x1, k), lerpf(s.y0, s.y1, k) - sin(k * PI) * arco)
		if tipo.begins_with("flecha"):
			var ang := atan2(s.y1 - s.y0 - cos(k * PI) * arco * PI, s.x1 - s.x0)
			draw_set_transform(O + p, ang)
			draw_line(Vector2(-18, 0), Vector2(12, 0), Color("5a3b1f"), 2.4, true)
			draw_colored_polygon(PackedVector2Array([Vector2(16, 0), Vector2(9, -3.5), Vector2(9, 3.5)]), Color("d8dde6"))
			draw_rect(Rect2(-20, -3, 5, 6), s.cor)
			draw_set_transform(O)
		elif tipo == "bomba":                        # bomba com pavio aceso girando no ar
			var gira: float = k * TAU * 1.5 * s.dir
			draw_circle(p + Vector2(0, 3), 11.0 * s.t + 2.0, Color(0, 0, 0, 0.3))
			draw_circle(p, 10.0 * s.t + 2.0, Color("1c1a1e"))
			draw_circle(p + Vector2(-3, -3), 3.0, Color(1, 1, 1, 0.25))
			var fa: Vector2 = p + Vector2(cos(gira - PI / 2), sin(gira - PI / 2)) * (12.0 * s.t + 2.0)
			draw_circle(fa, 5.0 + randf() * 2.5, Color(1, 0.55, 0.12, 0.55))
			draw_circle(fa, 2.5, Color(1, 0.95, 0.6))
		else:
			var rr := 13.0 if tipo == "fogo" else 10.0
			var cor: Color = s.cor
			for j in 4:                                # rastro
				var kk: float = maxf(0.0, k - j * 0.05)
				var pj := Vector2(lerpf(s.x0, s.x1, kk), lerpf(s.y0, s.y1, kk) - sin(kk * PI) * arco)
				draw_circle(pj, rr * (0.9 - j * 0.18), Color(cor, 0.25 - j * 0.05))
			draw_circle(p, rr * 2.4, Color(cor, 0.18))
			draw_circle(p, rr * 1.5, Color(cor, 0.45))
			draw_circle(p, rr * 0.8, Color(cor.lightened(0.5), 0.9))
			draw_circle(p, rr * 0.4, Color.WHITE)
	# SOBRECARGA: raio grosso saltando de um inimigo para o outro
	for c in correntes_m:
		if c.t < 0.0:
			continue
		var al: float = 1.0 - c.t / 0.4
		var pts := _ziguezague(c.de, c.para, 9, 14.0 * al + 4.0)
		draw_polyline(pts, Color(0.25, 0.9, 1.0, 0.4 * al), 12.0, true)
		draw_polyline(pts, Color(0.9, 1.0, 1.0, al), 3.0, true)
		for ponta in [c.de, c.para]:
			draw_circle(ponta, 18.0 * al + 5.0, Color(0.25, 0.92, 1.0, 0.35 * al))
	# clarão das bombas
	for c in _clarao_bomba:
		var k: float = c.t / 0.3
		draw_circle(c.pos, c.r * (0.5 + k), Color(1, 0.8, 0.4, 0.45 * (1.0 - k)))
		draw_circle(c.pos, c.r * 0.5 * (1.0 - k), Color(1, 1, 0.85, 0.8 * (1.0 - k)))
	# energia da Elara / Esqueleto Black
	for b in orbes:
		var pul := 1.0 + 0.15 * sin(b.t * 18.0)
		draw_circle(b.pos, 18.0 * pul, Color(1, 0.85, 0.2, 0.22))
		draw_circle(b.pos, 10.0 * pul, Color("ffd34d"))
		draw_circle(b.pos, 5.0, Color(1, 1, 0.85))
		draw_colored_polygon(PackedVector2Array([b.pos + Vector2(1, -7), b.pos + Vector2(-4, 1), b.pos + Vector2(0, 1),
			b.pos + Vector2(-1, 7), b.pos + Vector2(4, -1), b.pos + Vector2(0, -1)]), Color("b8740f"))
	for q in faiscas:
		draw_circle(q.pos, q.r, Color(q.cor, 1.0 - q.vida / q.max))
	O = o_antes
	draw_set_transform(O)

## Pedra (terra) ou osso saindo do chão: sobe rápido, fica um instante e afunda.
func _desenhar_espinho(e: Dictionary) -> void:
	var t: float = e.t
	var k := clampf(t / 0.08, 0.0, 1.0) if t < 0.08 else (1.0 if t < 0.4 else clampf(1.0 - (t - 0.4) / 0.4, 0.0, 1.0))
	var h: float = e.h * k
	if h < 3.0:
		return
	var w: float = e.w
	var b := Vector2(e.x, e.y)
	var topo := b + Vector2(w * e.inc, -h)
	if e.tipo == "terra":
		var pts := PackedVector2Array([b + Vector2(-w / 2.0, 0), b + Vector2(-w * 0.32, -h * 0.55), topo,
			b + Vector2(w * 0.36, -h * 0.5), b + Vector2(w / 2.0, 0)])
		draw_colored_polygon(pts, Color("6a4a26"))
		draw_colored_polygon(PackedVector2Array([b + Vector2(-w * 0.15, 0), b + Vector2(-w * 0.2, -h * 0.5), topo, b + Vector2(w * 0.1, 0)]), Color("a8875a"))
		pts.append(pts[0])
		draw_polyline(pts, Color("2a1a0a"), 2.0, true)
	else:
		var pts2 := PackedVector2Array([b + Vector2(-w * 0.28, 0), topo + Vector2(-w * 0.12, 4), topo + Vector2(w * 0.12, 4), b + Vector2(w * 0.28, 0)])
		draw_colored_polygon(pts2, Color("efe6d0"))
		pts2.append(pts2[0])
		draw_polyline(pts2, Color("5a4a3a"), 2.0, true)
		draw_circle(topo + Vector2(-w * 0.14, 2), w * 0.2, Color("efe6d0"))
		draw_circle(topo + Vector2(w * 0.14, 2), w * 0.2, Color("efe6d0"))
		draw_arc(topo + Vector2(-w * 0.14, 2), w * 0.2, PI * 0.9, PI * 2.1, 8, Color("5a4a3a"), 1.6, true)
		draw_arc(topo + Vector2(w * 0.14, 2), w * 0.2, PI * 0.9 - PI, PI * 1.1, 8, Color("5a4a3a"), 1.6, true)

func _ziguezague(a0: Vector2, a1: Vector2, n: int, amp: float) -> PackedVector2Array:
	var pts := PackedVector2Array([a0])
	for j in range(1, n):
		pts.append(a0.lerp(a1, float(j) / n) + Vector2(randf_range(-amp, amp) * 0.4, randf_range(-amp, amp)))
	pts.append(a1)
	return pts

func _desenhar_lutador(f: Dictionary, esc: Color) -> void:
	var a: AnimDados = null
	var q := 0
	match f.estado:
		"andar":
			a = _anim(f, "andar")
			if a:
				q = a.quadro_laco(f.tempo) if a.tem_laco() else int(f.tempo * a.fps) % a.quadros
		"atacar":
			a = _anim(f, f.atq)
			if a:
				q = mini(a.quadros - 1, int(f.tempo * a.fps))
		"morrer":
			a = _anim(f, "morrer")
			if a:
				q = mini(a.quadros - 1, int(f.tempo * a.fps))
	if a == null:
		a = _anim(f, "parado")
		if a == null:
			a = _anim(f, "andar")
			if a == null:
				return
		q = int((f.tempo + f.x * 0.01) * a.fps) % a.quadros
	var pd: PersonagemDados = f.p
	var nasce: float = f.nasce
	var e: float = pd.escala * a.escala * f.t * (0.75 + 0.25 * nasce)
	var vira: float = f.dir                          # (igual à partida: todas as folhas olham para a direita)
	var alfa: float = (1.0 - f.some) * nasce
	var pe := Vector2(f.x, f.y)
	var giro := 0.0
	if f.has("voo"):                                 # arremessado pelo martelo do Darian: voa em arco girando
		var vk: float = clampf(float(f.voo.t) / float(f.voo.dur), 0.0, 1.0)
		pe.y -= 85.0 * f.t * 4.0 * vk * (1.0 - vk)
		giro = signf(float(f.voo.para) - float(f.voo.de)) * 0.5 * sin(PI * vk)
	# sombra no chão
	draw_set_transform(O + Vector2(f.x, f.y), 0, Vector2(1, 0.235))
	draw_circle(Vector2.ZERO, 34.0 * f.t, Color(0, 0, 0, 0.35 * alfa))
	if f.gerador:                                    # brilho dourado do gerador
		draw_circle(Vector2.ZERO, 46.0 * f.t, Color(1, 0.85, 0.3, 0.1 + 0.05 * sin(relogio * 3.0)))
	draw_set_transform(O + pe, giro, Vector2(e * vira, e))
	var m := 2.0
	var reg := a.retangulo(q)
	var mod := Color(esc, alfa)
	if f.flash > 0:
		mod = Color(esc.lerp(Color(2.2, 2.2, 2.2), f.flash), alfa)
	if f.invocador != null:                          # invocado: um tom roxo
		mod = Color(mod.r * 0.85, mod.g * 0.75, mod.b * 1.1, alfa)
	var sobe: float = float(f.get("sobe", 1.0))
	if sobe < 1.0:                                   # saindo do chão: só aparece a parte de cima, subindo
		var ks := 1.0 - pow(1.0 - sobe, 2.2)
		var vis := maxf(1.0, (a.ay - m) * ks)
		var src := reg.grow(-m)
		src.size.y = vis
		draw_texture_rect_region(a.textura, Rect2(-a.ax + m, -vis, a.cw - 2 * m, vis), src, mod)
	else:
		draw_texture_rect_region(a.textura, Rect2(-a.ax + m, -a.ay + m, a.cw - 2 * m, a.ch - 2 * m), reg.grow(-m), mod)
	draw_set_transform(O)
	# escudo segurando o golpe: arco de luz na frente
	if f.escudo_t > 0.0:
		var al: float = f.escudo_t / 0.35
		var c := Vector2(f.x + f.dir * 26.0 * f.t, f.y - _altura(f) * 0.55)
		var a0 := -PI / 2.6 if f.dir > 0 else PI - PI / 2.6
		draw_arc(c, 34.0 * f.t, a0, a0 + PI / 1.3, 16, Color(0.55, 0.85, 1.0, 0.8 * al), 5.0, true)
		draw_arc(c, 34.0 * f.t, a0, a0 + PI / 1.3, 16, Color(1, 1, 1, 0.6 * al), 2.0, true)
	# barra de vida (aparece quando leva dano)
	if f.barra > 0.0 and f.estado != "morrer":
		var ba := clampf(f.barra / 0.4, 0.0, 1.0)
		var w: float = 46.0 * f.t
		var br := Rect2(f.x - w / 2.0, f.y - _altura(f) - 16.0, w, 6)
		draw_rect(br.grow(1.5), Color(0, 0, 0, 0.7 * ba))
		var cor := Color("5fe04a") if f.lado_i == 0 else Color("ff5a4a")
		draw_rect(Rect2(br.position, Vector2(w * f.vida / f.vida_max, br.size.y)), Color(cor, ba))
		draw_rect(Rect2(br.position, Vector2(w * f.vida / f.vida_max, 2)), Color(1, 1, 1, 0.35 * ba))

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
		if linhas[i].get("vermelho", false):
			_caixa(Rect2(b.position + Vector2(0, 4), b.size).grow(2), Color("4a0a06"), 16)
			_caixa(b.grow(2), Color("4a0a06"), 16)
			_botao_degrade(b, Color("ffb4a0"), Color("ff5a3a"), Color("a82010"), 14)
		else:
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
