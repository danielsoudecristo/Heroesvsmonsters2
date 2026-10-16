extends Control
## JANELA DE SELEÇÃO DE CARTAS — aparece antes da partida (campanha e PvP).
## O jogador escolhe de 3 a 7 cartas para levar para a batalha.
## Cartas bloqueadas (desbloqueio_trofeus > 0 e troféus abaixo) mostram o selo da liga
## (a imagem de assets/liga/) e não podem ser escolhidas; tocar nelas mostra um alerta.

const HUD := preload("res://scripts/arena/hud.gd")
const CA := preload("res://scripts/arena/config_arena.gd")

const MIN_CARTAS := 3
const MAX_CARTAS := 7

# ---------- medidas (tela 1280x720) ----------
const JANELA := Rect2(70, 22, 1140, 674)
const CARTA_TAM := Vector2(184, 210)
const ESPACO := Vector2(18, 12)
const GRADE_TOPO := 106.0
const COLUNAS := 5

# ---------- cores (as mesmas do HUD do jogo) ----------
const COR_CREME := Color("f1e2c0")
const COR_CONTORNO := Color("2a1a10")
const COR_OURO := Color("f2c14e")
const COR_OURO_ESCURO := Color("b07a1a")
const COR_CUSTO := Color("5a2a10")

var arena: Node                                  # arena.gd ou arena_pvp.gd
var escolheu: Callable                           # chamado com Array[PersonagemDados] quando confirma
var sair: Callable                               # "← MENU": volta para o menu principal
var cartas: Array[PersonagemDados] = []          # todas as cartas do lado (inclui bloqueadas)
var selecionadas: Array[PersonagemDados] = []
var _abre := 0.0
var _relogio := 0.0
var _apertado := -1
var _tocou_aqui := false
var _quadro_abriu := -1
var _alerta := ""                                # texto de alerta (carta bloqueada / mínimo)
var _alerta_t := 0.0                             # tempo restante do alerta
var _retratos: Dictionary = {}                   # id -> [textura, região, x dos pés]
var _selos := {}                                 # liga.img -> ImageTexture limpa (sem "quadrado branco")
var f_titulo: Font
var f_texto: Font
## CAMPANHA: níveis em que dá para começar (1 e depois de cada marco vencido) e o escolhido.
## Vazio = não mostra o seletor (PvP). info_nivel(n) devolve a dica do nível (tema e quem é forte).
var inicios: Array = []
var inicio := 1
var info_nivel: Callable
## CRONÔMETRO: quem demora não segura a partida. Acabou o tempo = completa com as cartas liberadas e começa.
const TEMPO := 30.0
var falta := TEMPO
var _ultimo_tique := -1
## FUNDO: o cenário do jogo, desfocado e com zoom lento (no lugar do preto).
const FUNDO_RESERVA := "res://assets/Menu/escolher_lado_largo.jpg"
var _fundo: TextureRect
const SHADER_DESFOQUE := """
shader_type canvas_item;
uniform float raio = 2.2;
void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * raio;
	vec4 s = vec4(0.0);
	float peso = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			float w = 1.0 / (1.0 + float(x * x + y * y));
			s += texture(TEXTURE, UV + vec2(float(x), float(y)) * px) * w;
			peso += w;
		}
	}
	COLOR = s / peso;
}
"""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	f_titulo = _fonte(["Fontes/lilita-one-latin-400-normal.woff2"])
	f_texto = _fonte(["Fontes/fredoka-latin-700-normal.woff2", "Fontes/fredoka-latin-600-normal.woff2"])
	_fundo = TextureRect.new()
	_fundo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fundo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fundo.show_behind_parent = true                   # (fica ATRÁS do painel desenhado no _draw)
	var sh := Shader.new()
	sh.code = SHADER_DESFOQUE
	var m := ShaderMaterial.new()
	m.shader = sh
	_fundo.material = m
	add_child(_fundo)

func _fonte(opcoes: Array) -> Font:
	for o in opcoes:
		var c: String = "res://assets/" + o
		if ResourceLoader.exists(c):
			return load(c)
	return ThemeDB.fallback_font

## Abre a janela com a lista completa de cartas do lado (incluindo bloqueadas).
func abrir(lista: Array[PersonagemDados]) -> void:
	if visible:
		return
	cartas = lista.duplicate()
	selecionadas.clear()
	_alerta = ""
	_alerta_t = 0.0
	for p in cartas:                              # aquece o selo das ligas (evita load dentro do _draw)
		if p != null and p.desbloqueio_trofeus > 0:
			_textura_liga(Perfil.liga_de(p.desbloqueio_trofeus))
	var tex: Texture2D = null
	var fa: Variant = arena.get("fundo") if arena else null
	if fa is Sprite2D and (fa as Sprite2D).texture:
		tex = (fa as Sprite2D).texture                 # o cenário da partida que vai começar
	elif ResourceLoader.exists(FUNDO_RESERVA):
		tex = load(FUNDO_RESERVA)
	_fundo.texture = tex
	falta = TEMPO
	_ultimo_tique = -1
	_quadro_abriu = Engine.get_process_frames()
	visible = true
	_abre = 0.0
	_tocou_aqui = false
	queue_redraw()

func fechar() -> void:
	visible = false

func _process(dt: float) -> void:
	if not visible:
		return
	_relogio += dt
	_abre = move_toward(_abre, 1.0, dt * 4.0)
	var tt := CA.tela_toda(self)                         # (celular largo: o cenário cobre as laterais também)
	_fundo.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fundo.position = tt.position
	_fundo.size = tt.size
	var z := 1.06 + 0.03 * sin(_relogio * 0.25)          # o cenário respira devagar atrás da janela
	_fundo.pivot_offset = tt.size / 2.0
	_fundo.scale = Vector2(z, z)
	_fundo.modulate = Color(1, 1, 1, _abre)
	falta = maxf(0.0, falta - dt)
	var seg := ceili(falta)
	if seg <= 5 and seg != _ultimo_tique and seg > 0:
		_ultimo_tique = seg
		Sons.tocar("Jogo/som/clique", 0.45)           # tique-taque nos últimos segundos
	if falta <= 0.0:
		_tempo_acabou()
		return
	if _alerta_t > 0.0:
		_alerta_t -= dt
		if _alerta_t <= 0.0:
			_alerta = ""
	queue_redraw()

func _ret_carta(i: int) -> Rect2:
	var n := cartas.size()
	if n == 0:
		return Rect2()
	var cols := mini(COLUNAS, n)
	var linha := i / cols
	var col := i % cols
	var total_larg := cols * CARTA_TAM.x + (cols - 1) * ESPACO.x
	var x0 := JANELA.get_center().x - total_larg / 2.0
	var y0 := JANELA.position.y + GRADE_TOPO + linha * (CARTA_TAM.y + ESPACO.y)
	return Rect2(x0 + col * (CARTA_TAM.x + ESPACO.x), y0, CARTA_TAM.x, CARTA_TAM.y)

func _ret_jogar() -> Rect2:
	return Rect2(JANELA.end.x - 74 - 240, JANELA.end.y - 80, 240, 56)

func _ret_menu() -> Rect2:
	return Rect2(JANELA.position.x + 24, JANELA.end.y - 76, 150, 46)

func _ret_inicio() -> Rect2:
	return Rect2(JANELA.position.x + 190, JANELA.end.y - 76, 250, 46)

func _bloqueada(p: PersonagemDados) -> bool:
	return p != null and p.desbloqueio_trofeus > 0 and Perfil.trofeus < p.desbloqueio_trofeus

func _pode_jogar() -> bool:
	return selecionadas.size() >= MIN_CARTAS and selecionadas.size() <= MAX_CARTAS

# =================================================================== INPUT
func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and Engine.get_process_frames() == _quadro_abriu:
		accept_event()
		return
	if not (ev is InputEventMouseButton) or ev.button_index != MOUSE_BUTTON_LEFT:
		return
	if ev.pressed:
		_tocou_aqui = true
		_apertado = -1
		for i in cartas.size():
			if _ret_carta(i).has_point(ev.position):
				_apertado = i
				break
		if _ret_jogar().has_point(ev.position):
			_apertado = -2
		elif _ret_menu().has_point(ev.position):
			_apertado = -4
		elif inicios.size() > 1 and _ret_inicio().has_point(ev.position):
			_apertado = -5
	else:
		_apertado = -1
		if _tocou_aqui:
			_tocou_aqui = false
			_tocar(ev.position)
	accept_event()

func _tocar(p: Vector2) -> void:
	# voltar ao menu
	if _ret_menu().grow(6).has_point(p):
		if sair.is_valid():
			Sons.tocar("Jogo/som/clique", 0.5)
			fechar()
			sair.call()
		return
	# começar no nível (campanha): metade esquerda "<" volta um marco, metade direita ">" avança um
	var bi := _ret_inicio()
	if inicios.size() > 1 and bi.grow(6).has_point(p):
		var i := inicios.find(inicio)
		var novo := i - 1 if p.x < bi.get_center().x else i + 1
		if novo >= 0 and novo < inicios.size():
			inicio = int(inicios[novo])
			Sons.tocar("Jogo/som/clique", 0.5)
		return
	# cartas
	for i in cartas.size():
		if _ret_carta(i).has_point(p):
			_tocar_carta(i)
			return
	# jogar
	if _ret_jogar().has_point(p):
		if _pode_jogar():
			Sons.tocar("Jogo/som/clique", 0.5)
			fechar()
			if escolheu.is_valid():
				escolheu.call(selecionadas.duplicate())
		elif selecionadas.size() < MIN_CARTAS:
			_alerta = "Escolha pelo menos %d cartas para jogar!" % MIN_CARTAS
			_alerta_t = 2.5

## Acabou o tempo: fica com as escolhidas e completa até 7 com as liberadas (na ordem da barra); começa.
func _tempo_acabou() -> void:
	for p in cartas:
		if selecionadas.size() >= MAX_CARTAS:
			break
		if not _bloqueada(p) and not selecionadas.has(p):
			selecionadas.append(p)
	if selecionadas.is_empty():
		return
	Sons.tocar("Jogo/som/clique", 0.7)
	fechar()
	if escolheu.is_valid():
		escolheu.call(selecionadas.duplicate())

func _tocar_carta(i: int) -> void:
	var p: PersonagemDados = cartas[i]
	if _bloqueada(p):
		var liga := Perfil.liga_de(p.desbloqueio_trofeus)
		_alerta = "%s só desbloqueia na liga %s (%d troféus). Suba de liga para usar!" % [p.nome_card(), liga.nome, p.desbloqueio_trofeus]
		_alerta_t = 3.5
		Sons.tocar("Jogo/som/clique", 0.35)
		return
	Sons.tocar("Jogo/som/clique", 0.5)
	var idx := selecionadas.find(p)
	if idx >= 0:
		selecionadas.remove_at(idx)
	elif selecionadas.size() < MAX_CARTAS:
		selecionadas.append(p)
	else:
		_alerta = "Máximo de %d cartas! Retire uma para escolher outra." % MAX_CARTAS
		_alerta_t = 2.5

# =================================================================== DESENHO
static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

func _caixa(r: Rect2, fundo: Color, raio: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fundo
	sb.set_corner_radius_all(raio)
	draw_style_box(sb, r)

func _caixa_borda(r: Rect2, fundo: Color, borda: Color, esp: int, raio: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fundo
	sb.border_color = borda
	sb.set_border_width_all(esp)
	sb.set_corner_radius_all(raio)
	draw_style_box(sb, r)

func _texto(f: Font, pos: Vector2, txt: String, tam: int, cor: Color, contorno := 0, largura := -1.0, alinha := HORIZONTAL_ALIGNMENT_LEFT, cor_contorno := Color("24130a")) -> void:
	if contorno > 0:
		draw_string_outline(f, pos, txt, alinha, largura, tam, contorno, cor_contorno)
	draw_string(f, pos, txt, alinha, largura, tam, cor)

func _larg(f: Font, txt: String, tam: int) -> float:
	return f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x

## Losango dourado (ornamento dos cantos e do divisor).
func _diamante(c: Vector2, r: float, claro: Color, escuro: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c]), claro)
	draw_colored_polygon(PackedVector2Array([c, c + Vector2(r, 0), c + Vector2(0, r)]), escuro)
	draw_colored_polygon(PackedVector2Array([c, c + Vector2(0, r), c + Vector2(-r, 0)]), claro.darkened(0.25))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c, c + Vector2(-r, 0)]), claro.darkened(0.1))

func _draw() -> void:
	if cartas.is_empty():
		return
	var k := 0.92 + 0.08 * _ease(_abre)
	_desenhar_fundo()
	draw_set_transform(JANELA.get_center() - JANELA.get_center() * k, 0.0, Vector2(k, k))
	_desenhar_janela()
	_desenhar_cabecalho()
	_desenhar_cronometro()
	for i in cartas.size():
		_desenhar_carta(i)
	_desenhar_rodape()
	draw_set_transform(Vector2.ZERO)

## Fundo: o cenário desfocado (nó _fundo, atrás) + véu azul-escuro em degradê, vinheta e brasas subindo.
func _desenhar_fundo() -> void:
	var a := _abre
	var tt := CA.tela_toda(self)
	var p0 := tt.position
	var p1 := tt.end
	if _fundo.texture == null:
		draw_rect(tt, Color("0b0d1a"))
	var topo := Color(0.04, 0.05, 0.16, 0.42 * a)
	var baixo := Color(0.02, 0.02, 0.07, 0.6 * a)
	draw_polygon(PackedVector2Array([p0, Vector2(p1.x, p0.y), p1, Vector2(p0.x, p1.y)]), PackedColorArray([topo, topo, baixo, baixo]))
	var forte := Color(0, 0, 0, 0.55 * a)
	var nada := Color(0, 0, 0, 0)
	var L := 220.0
	for q in [[p0, Vector2(p1.x, p0.y), Vector2(p1.x, p0.y + L), Vector2(p0.x, p0.y + L)], [Vector2(p0.x, p1.y), p1, Vector2(p1.x, p1.y - L), Vector2(p0.x, p1.y - L)],
			[p0, Vector2(p0.x, p1.y), Vector2(p0.x + L, p1.y), Vector2(p0.x + L, p0.y)], [Vector2(p1.x, p0.y), p1, Vector2(p1.x - L, p1.y), Vector2(p1.x - L, p0.y)]]:
		draw_polygon(PackedVector2Array(q), PackedColorArray([forte, forte, nada, nada]))
	# luz dourada atrás da janela
	var cj := JANELA.get_center()
	for i in 5:
		draw_circle(cj, 560.0 - i * 90.0, Color(1.0, 0.75, 0.3, 0.025 * a))
	# brasas subindo
	for s in 34:
		var fase := fmod(_relogio * 0.07 + s * 0.0297, 1.0)
		var px := p0.x + fmod(s * 211.7, maxf(tt.size.x, 1.0)) + sin(_relogio * 0.9 + s) * 16.0
		var py := p1.y + 10.0 - fase * (tt.size.y + 40.0)
		draw_circle(Vector2(px, py), 2.2 * (1.0 - fase) + 0.7, Color(1.0, 0.6 + 0.3 * (1.0 - fase), 0.25, 0.7 * (1.0 - fase) * a))

## CRONÔMETRO: anel que esvazia; fica vermelho e pulsa nos últimos 10 s.
func _desenhar_cronometro() -> void:
	var c := Vector2(JANELA.end.x - 92, JANELA.position.y + 56)
	var k := falta / TEMPO
	var urgente := falta <= 10.0
	var pul := (1.0 + 0.08 * sin(_relogio * 12.0)) if urgente else 1.0
	var r := 32.0 * pul
	var cor := Color("ff5a3a") if urgente else (Color("f6c343") if falta > 20.0 else Color("ffa23a"))
	draw_circle(c + Vector2(0, 4), r + 6, Color(0, 0, 0, 0.4))
	draw_circle(c, r + 6, COR_CONTORNO)
	draw_circle(c, r + 3, Color("1b2350"))
	draw_arc(c, r - 3, 0, TAU, 48, Color(1, 1, 1, 0.12), 6.0, true)
	if k > 0.0:
		draw_arc(c, r - 3, -PI / 2.0, -PI / 2.0 + TAU * k, 48, cor, 6.0, true)
	if urgente:
		draw_circle(c, r + 12, Color(1, 0.3, 0.2, 0.12 + 0.08 * sin(_relogio * 12.0)))
	_texto(f_titulo, Vector2(c.x - 40, c.y + 11), "%ds" % ceili(falta), 26, Color.WHITE, 6, 80, HORIZONTAL_ALIGNMENT_CENTER, COR_CONTORNO)

## Painel: sombra + moldura dourada em camadas + miolo azul royal (estilo das janelas do jogo).
func _desenhar_janela() -> void:
	var j := JANELA
	_caixa(Rect2(j.position + Vector2(0, 14), j.size).grow(10), Color(0, 0, 0, 0.5), 34)
	_caixa(j.grow(10), Color("6a3c08"), 30)
	_caixa(j.grow(6), COR_OURO, 28)
	_caixa(j.grow(3), Color("c8871a"), 26)
	_caixa(j, Color("2c3874"), 24)
	draw_rect(Rect2(j.position + Vector2(8, 8), Vector2(j.size.x - 16, 110)), Color(1, 1, 1, 0.05))   # brilho no topo
	_caixa_borda(Rect2(j.position + Vector2(10, 10), j.size - Vector2(20, 20)), Color(0, 0, 0, 0), Color("1f2754"), 3, 18)
	# área rebaixada onde ficam as cartas
	_caixa(Rect2(j.position + Vector2(16, 96), j.size - Vector2(32, 196)), Color(0.07, 0.09, 0.26, 0.55), 18)
	# ornamentos dos cantos
	for c in [j.position + Vector2(30, 30), Vector2(j.end.x - 30, j.position.y + 30),
			Vector2(j.position.x + 30, j.end.y - 30), j.end - Vector2(30, 30)]:
		_diamante(c, 9, Color("f6c343"), Color("8a5a10"))

## Título + divisor dourado com gema.
func _desenhar_cabecalho() -> void:
	var j := JANELA
	_texto(f_titulo, Vector2(j.position.x, j.position.y + 58), "ESCOLHA SUAS CARTAS", 40, Color("ffd34d"), 7, j.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_texto(f_texto, Vector2(j.position.x, j.position.y + 84), "Mínimo %d cartas · Máximo %d" % [MIN_CARTAS, MAX_CARTAS], 17, Color("aab4e0"), 3, j.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var dy := j.position.y + 94
	var dx0 := j.get_center().x - 210.0
	draw_line(Vector2(dx0, dy), Vector2(dx0 + 190, dy), COR_OURO_ESCURO, 2.5)
	draw_line(Vector2(dx0 + 230, dy), Vector2(dx0 + 420, dy), COR_OURO_ESCURO, 2.5)
	_diamante(Vector2(dx0 + 210, dy), 7, COR_OURO, Color("8a5a10"))

## Rodapé: ← MENU · contador · JOGAR!
func _desenhar_rodape() -> void:
	var j := JANELA
	var rodape := Rect2(j.position.x + 16, j.end.y - 92, j.size.x - 32, 80)
	_caixa_borda(rodape, Color(0.06, 0.07, 0.18, 0.75), Color("1f2754"), 2, 18)
	# ← MENU
	var bm := _ret_menu()
	if _apertado == -4:
		bm.position.y += 2
	_caixa_borda(bm, Color("3a2850"), COR_OURO, 2, 10)
	_texto(f_titulo, Vector2(bm.position.x, bm.position.y + 31), "← MENU", 18, COR_CREME, 4, bm.size.x, HORIZONTAL_ALIGNMENT_CENTER, COR_CONTORNO)
	# começar no nível (só campanha, quando já venceu algum marco)
	if inicios.size() > 1:
		var bi := _ret_inicio()
		if _apertado == -5:
			bi.position.y += 2
		_caixa_borda(bi, Color("1d4a3a"), COR_OURO, 2, 10)
		_texto(f_titulo, Vector2(bi.position.x, bi.position.y + 21), "COMEÇAR NO NÍVEL", 13, Color("bfe8c8"), 3, bi.size.x, HORIZONTAL_ALIGNMENT_CENTER, COR_CONTORNO)
		_texto(f_titulo, Vector2(bi.position.x, bi.position.y + 41), str(inicio), 20, Color("ffd34d"), 4, bi.size.x, HORIZONTAL_ALIGNMENT_CENTER, COR_CONTORNO)
		# setas: apagadas quando não dá para ir mais para aquele lado
		var i_ini := inicios.find(inicio)
		var cor_v := COR_CREME if i_ini > 0 else Color(1, 1, 1, 0.2)
		var cor_p := COR_CREME if i_ini < inicios.size() - 1 else Color(1, 1, 1, 0.2)
		_texto(f_titulo, Vector2(bi.position.x + 14, bi.position.y + 36), "<", 30, cor_v, 4, -1.0, HORIZONTAL_ALIGNMENT_LEFT, COR_CONTORNO)
		_texto(f_titulo, Vector2(bi.end.x - 30, bi.position.y + 36), ">", 30, cor_p, 4, -1.0, HORIZONTAL_ALIGNMENT_LEFT, COR_CONTORNO)
	# dica do nível que vai começar (tema e quem é forte contra)
	if info_nivel.is_valid() and (_alerta == "" or _alerta_t <= 0.0):
		var dica: String = info_nivel.call(inicio)
		if dica != "":
			var ar := Rect2(j.position.x + 40, j.end.y - 134, j.size.x - 80, 34)
			_caixa_borda(ar, Color(0.05, 0.1, 0.22, 0.9), Color("4a6ad0"), 2, 14)
			_texto(f_texto, Vector2(ar.position.x, ar.position.y + 24), dica, 15, Color("d8e4ff"), 3, ar.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	# contador
	var cp := Rect2(j.get_center().x - 110, j.end.y - 76, 220, 40)
	_caixa_borda(cp, Color("2a1830"), COR_OURO_ESCURO, 2, 20)
	_texto(f_titulo, Vector2(cp.position.x, cp.position.y + 28), "%d / %d CARTAS" % [selecionadas.size(), MAX_CARTAS],
		20, Color("ffd34d") if _pode_jogar() else Color("ff9a7a"), 4, cp.size.x, HORIZONTAL_ALIGNMENT_CENTER, COR_CONTORNO)
	# JOGAR!
	var bj := _ret_jogar()
	var ativo := _pode_jogar()
	if _apertado == -2:
		bj.position.y += 3
	_caixa(Rect2(bj.position + Vector2(0, 6), bj.size).grow(2), Color(0, 0, 0, 0.45), 18)
	_caixa_borda(bj, Color("3a9e3a") if ativo else Color("5a5a5a"), COR_CONTORNO, 3, 18)
	_caixa(Rect2(bj.position + Vector2(7, 4), Vector2(bj.size.x - 14, bj.size.y * 0.42)), Color(1, 1, 1, 0.2 if ativo else 0.08), 12)
	_texto(f_titulo, Vector2(bj.position.x, bj.position.y + 39), "JOGAR!", 30,
		Color.WHITE if ativo else Color(1, 1, 1, 0.55), 5, bj.size.x, HORIZONTAL_ALIGNMENT_CENTER, COR_CONTORNO)
	# alerta
	if _alerta != "" and _alerta_t > 0.0:
		var alfa := clampf(_alerta_t, 0.0, 1.0)
		var ar := Rect2(j.get_center().x - 330, j.end.y - 134, 660, 34)
		_caixa_borda(ar, Color(0.15, 0.08, 0.05, 0.94 * alfa), Color("ff8a4a"), 2, 14)
		_texto(f_texto, Vector2(ar.position.x, ar.position.y + 24), _alerta, 16, Color("ffd0a0"), 3, ar.size.x, HORIZONTAL_ALIGNMENT_CENTER)

## Carta no MESMO estilo da barra do HUD: moldura creme, retrato recortado, placa de nome, custo e nível.
func _desenhar_carta(i: int) -> void:
	var p: PersonagemDados = cartas[i]
	var r := _ret_carta(i)
	var entra := clampf(_abre * 2.0 - i * 0.1, 0.0, 1.0)
	r.position.y += (1.0 - _ease(entra)) * 30.0
	if _apertado == i:
		r.position.y += 4
	var bloqueada := _bloqueada(p)
	var escolhida := selecionadas.has(p)
	# sombra
	_caixa(Rect2(r.position + Vector2(0, 7), r.size).grow(2), Color(0, 0, 0, 0.4), 18)
	# brilho dourado de selecionada (pulsa devagar)
	if escolhida:
		var pul := 0.5 + 0.5 * sin(_relogio * 3.2)
		_caixa_borda(r.grow(7), Color(1, 0.85, 0.3, 0.5 + 0.25 * pul), Color(1, 0.95, 0.6), 3, 20)
	# moldura (creme normal / acinzentada se bloqueada)
	_caixa_borda(r, COR_CREME if not bloqueada else Color("8f8a7a"), COR_CONTORNO if not bloqueada else Color("3a342c"), 4, 16)
	# retrato com o fundo nas cores do personagem (mesmo recorte do HUD)
	var ret := Rect2(r.position + Vector2(10, 12), Vector2(r.size.x - 20, 122))
	var c0: Color = p.cores[0] if p.cores.size() > 0 else Color.WHITE
	var c1: Color = p.cores[1] if p.cores.size() > 1 else Color.GRAY
	draw_polygon(PackedVector2Array([ret.position, ret.position + Vector2(ret.size.x, 0), ret.end, ret.position + Vector2(0, ret.size.y)]),
		PackedColorArray([c0.lerp(c1, 0.25), c0.lerp(c1, 0.25), c1, c1]))
	var rt := _retrato(p)
	if not rt.is_empty():
		var q: Rect2 = rt[1]
		var cx: float = rt[2]
		var area := ret.size - Vector2(10, 6)
		var k := area.y / q.size.y
		if q.size.x * k > area.x:
			var w := area.x / k
			var x0 := clampf(cx - w / 2.0, q.position.x, q.end.x - w)
			q = Rect2(x0, q.position.y, w, q.size.y)
		var tam := q.size * k
		var dest := Rect2(ret.position + Vector2((ret.size.x - tam.x) / 2, ret.size.y - tam.y - 2), tam)
		draw_texture_rect_region(rt[0], dest, q, Color(0.55, 0.55, 0.55) if bloqueada else Color.WHITE)
	if bloqueada:
		draw_rect(ret, Color(0, 0, 0, 0.35))
	_caixa_borda(ret, Color(0, 0, 0, 0), COR_CONTORNO, 3, 10)
	# nível (canto do retrato, igual ao HUD)
	_texto(f_titulo, ret.position + Vector2(8, ret.size.y - 10), "Nv %d" % Perfil.nivel_de(p.id), 18, Color("6be04a"), 5, -1.0, HORIZONTAL_ALIGNMENT_LEFT, COR_CONTORNO)
	# nome
	var placa := Rect2(r.position + Vector2(8, 142), Vector2(r.size.x - 16, 30))
	_caixa_borda(placa, Color("2b2622"), COR_CONTORNO, 2, 8)
	var tam_nome := 21 if p.nome_card().length() <= 10 else 17
	_texto(f_titulo, placa.position + Vector2(0, 23), p.nome_card(), tam_nome, COR_CREME, 0, placa.size.x, HORIZONTAL_ALIGNMENT_CENTER, COR_CONTORNO)
	# custo: ícone + número centralizados juntos
	var custo_txt := str(p.custo)
	var r_ic := 13.0
	var espaco := 6.0
	var total := r_ic * 2.0 + espaco + _larg(f_titulo, custo_txt, 28)
	var xc := r.get_center().x - total / 2.0
	var yc := r.position.y + 192.0
	HUD.icone_energia(self, Vector2(xc + r_ic, yc), r_ic)
	_texto(f_titulo, Vector2(xc + r_ic * 2.0 + espaco, yc + 10), custo_txt, 28, COR_CUSTO if not bloqueada else Color("6a5a4a"), 0)
	# medalha de selecionada
	if escolhida:
		var m := Vector2(r.end.x - 22, r.position.y + 22)
		draw_circle(m, 18, Color(0, 0, 0, 0.5))
		draw_circle(m, 16, COR_CONTORNO)
		draw_circle(m, 14, Color("3a9e3a"))
		draw_circle(m, 11, Color("4cbe4c"))
		_texto(f_titulo, m + Vector2(-14, 8), "✓", 22, Color.WHITE, 4, 28, HORIZONTAL_ALIGNMENT_CENTER, Color("1a4a1a"))
	# selo da liga (carta bloqueada)
	if bloqueada:
		_desenhar_selo_liga(p, Vector2(r.end.x - 32, r.position.y + 32))

## Textura do selo da liga, limpa: pixel transparente vira (0,0,0,0) de verdade.
## Sem isso, se algum render usar o RGB do fundo (branco lixo) no lugar do alfa,
## a medalha vira um QUADRADO BRANCO na carta.
func _textura_liga(liga: Dictionary) -> Texture2D:
	var chave := str(liga.img)
	if _selos.has(chave):
		return _selos[chave]
	_selos[chave] = null
	for nome in ["liga/" + str(liga.img), "liga/" + str(liga.nome), "liga/" + str(liga.nome).to_lower()]:
		for ext in ["png", "jpg", "webp"]:
			var cam := "res://assets/%s.%s" % [nome, ext]
			if not ResourceLoader.exists(cam):
				continue
			var tex: Texture2D = load(cam)
			if tex == null:
				continue
			var img := tex.get_image()
			if img == null:
				_selos[chave] = tex
				return tex
			if img.is_compressed():
				img.decompress()
			for y in img.get_height():
				for x in img.get_width():
					var c := img.get_pixel(x, y)
					if c.a < 0.02:
						img.set_pixel(x, y, Color(0, 0, 0, 0))
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			var it := ImageTexture.create_from_image(img)
			_selos[chave] = it
			return it
	return null

## Selo da liga: a imagem real de assets/liga/ pulsando de leve (sem cadeado).
func _desenhar_selo_liga(p: PersonagemDados, c: Vector2) -> void:
	var liga := Perfil.liga_de(p.desbloqueio_trofeus)
	var tex := _textura_liga(liga)
	if not tex:
		draw_circle(c, 18, liga.cor)
	else:
		var pul := 0.5 + 0.5 * sin(_relogio * 2.8)           # 0..1, devagar
		var base := 46.0 + 6.0 * pul                          # 46 → 52 px
		var t := Vector2(base, base)
		# sombra de contato
		draw_texture_rect(tex, Rect2(c - t / 2.0 + Vector2(0, 2), t), false, Color(0, 0, 0, 0.45))
		# o selo da liga
		draw_texture_rect(tex, Rect2(c - t / 2.0, t), false)

## Retrato da carta: 1º quadro da pose parada, recortado só na parte desenhada (igual ao HUD).
func _retrato(p: PersonagemDados) -> Array:
	if _retratos.has(p.id):
		return _retratos[p.id]
	var r: Array = []
	var a := p.anim_qualquer(["parado", "defender", "andar"])
	if a and a.textura:
		var q := a.retangulo(int(p.extra.get("quadro_retrato", 0)))
		var cx := q.position.x + a.ax
		var img := a.textura.get_image()
		if img:
			if img.is_compressed():
				img.decompress()
			var u := _area_visivel(img, Rect2i(q))
			if u.size.x > 4 and u.size.y > 4:
				q = Rect2(u)
		r = [a.textura, q, cx]
	_retratos[p.id] = r
	return r

## Parte do quadro com desenho de verdade (ignora brilhos quase transparentes).
static func _area_visivel(img: Image, q: Rect2i) -> Rect2i:
	q = q.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var x0 := q.end.x; var y0 := q.end.y; var x1 := q.position.x; var y1 := q.position.y
	for y in range(q.position.y, q.end.y, 2):
		for x in range(q.position.x, q.end.x, 2):
			if img.get_pixel(x, y).a > 0.35:
				x0 = mini(x0, x); x1 = maxi(x1, x); y0 = mini(y0, y); y1 = maxi(y1, y)
	if x1 <= x0 or y1 <= y0:
		return q
	return Rect2i(x0, y0, x1 - x0 + 2, y1 - y0 + 2)
