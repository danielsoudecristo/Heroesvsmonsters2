extends Control
## GUIA (tutorial): escurece a tela, deixa um "buraco" de luz no que importa, mostra a MÃOZINHA tocando
## e um BALÃO com título, texto, ilustração e botões. Usado pelo tutorial do menu (tour_menu.gd)
## e pelo tutorial da primeira batalha (tutorial_jogo.gd).
##
## Coordenadas: tudo em "palco" (1280x720). palco_offset = onde o palco fica dentro deste Control.

signal principal                                   ## apertou o botão do balão (Próximo / Começar...)
signal pulou                                       ## apertou "Pular tutorial"
signal tocou_alvo(p: Vector2)                      ## tocou dentro do alvo (o toque continua para o jogo)

const W := 1280.0
const H := 720.0
const CONTORNO := Color("24130a")
const OURO1 := Color("fff3b0")
const OURO2 := Color("f6c343")
const OURO3 := Color("b8740f")
const NAVY := Color("141a36")


var f_titulo: Font
var f_texto: Font
var palco_offset := Vector2.ZERO                   ## onde o palco começa (intro: intro.O; arena: 0)
var margem := 0.0                                  ## quanto o escuro passa do palco (arena: telas largas)
var ativo := false

# ----- o passo atual
var alvo := Rect2()                                ## tamanho 0 = sem luz (balão no meio)
var alvo_redondo := false
var mao := false                                   ## mostrar a mãozinha tocando
var mao_ponto := Vector2.INF                       ## onde a ponta do dedo toca (INF = meio do alvo)
var titulo := ""
var texto := ""
var bt_txt := "Próximo"                            ## "" = sem botão (espera o jogador fazer a ação)
var passo := 0
var total := 0
var pode_pular := true
var bloquear := true                               ## toques fora do alvo e do balão não passam
var deixar_alvo := true                            ## toques dentro do alvo passam para o jogo
var escuro := 0.62
var lado_balao := "auto"                           ## auto / cima / baixo / esquerda / direita / meio / topo
var extra := Callable()                            ## ilustração dentro do balão: extra.call(retângulo)
var extra_h := 0.0
var largura_balao := 470.0

# ----- animação
var _t := 0.0
var _troca := 0.0                                  ## 0 -> 1 quando entra um passo novo
var _desde := 0.0                                  ## segundos desde que o passo apareceu (evita toque duplo)
var _alvo_vis := Rect2()
var _mao_vis := Vector2.INF
var _balao := Rect2()
var _bt := Rect2()
var _bt_pular := Rect2()
var _apertado := ""
var _texto_h := 0.0
var _escuro: Control                               ## o escuro com o "buraco" de luz (irmão logo antes deste nó)
var _esc_a := 0.0
var _buraco := Rect2()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	if f_titulo == null:
		f_titulo = _fonte(["Fontes/lilita-one-latin-400-normal.woff2"])
	if f_texto == null:
		f_texto = _fonte(["Fontes/fredoka-latin-700-normal.woff2", "Fontes/fredoka-latin-600-normal.woff2"])
	_escuro = Control.new()
	_escuro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_escuro.visible = false
	_escuro.draw.connect(_desenhar_escuro)
	_inserir_escuro.call_deferred()
	visible = false

## O escuro fica num irmão logo ANTES deste nó (assim o balão e a mão ficam por cima dele).
func _inserir_escuro() -> void:
	var pai := get_parent()
	if pai == null or _escuro.get_parent() != null:
		return
	pai.add_child(_escuro)
	pai.move_child(_escuro, get_index())

func _exit_tree() -> void:
	if is_instance_valid(_escuro) and _escuro.get_parent() != null:
		_escuro.queue_free()

func _fonte(opcoes: Array) -> Font:
	for o in opcoes:
		var c: String = "res://assets/" + o
		if ResourceLoader.exists(c):
			return load(c)
	return ThemeDB.fallback_font

## Mostra um passo. cfg pode ter: titulo, texto, alvo, redondo, mao, mao_ponto, bt, pular, bloquear, deixar,
## escuro, lado, extra, extra_h, largura.
func mostrar(cfg: Dictionary) -> void:
	ativo = true
	visible = true
	_escuro.visible = true
	titulo = cfg.get("titulo", "")
	texto = cfg.get("texto", "")
	var novo_alvo: Rect2 = cfg.get("alvo", Rect2())
	if _alvo_vis.size == Vector2.ZERO or alvo.size == Vector2.ZERO:
		_alvo_vis = novo_alvo
	alvo = novo_alvo
	alvo_redondo = cfg.get("redondo", false)
	mao = cfg.get("mao", false)
	mao_ponto = cfg.get("mao_ponto", Vector2.INF)
	bt_txt = cfg.get("bt", "Próximo")
	pode_pular = cfg.get("pular", true)
	bloquear = cfg.get("bloquear", true)
	deixar_alvo = cfg.get("deixar", true)
	escuro = cfg.get("escuro", 0.62)
	lado_balao = cfg.get("lado", "auto")
	extra = cfg.get("extra", Callable())
	extra_h = cfg.get("extra_h", 0.0)
	largura_balao = cfg.get("largura", 470.0)
	_troca = 0.0
	_desde = 0.0
	_apertado = ""
	_mao_vis = Vector2.INF

func esconder() -> void:
	ativo = false
	visible = false
	_escuro.visible = false

## Muda só o alvo (para alvos que andam, como a energia caindo ou um monstro).
func mover_alvo(r: Rect2, ponto := Vector2.INF) -> void:
	alvo = r
	mao_ponto = ponto

func _process(dt: float) -> void:
	if not ativo:
		return
	_t += dt
	_desde += dt
	_troca = move_toward(_troca, 1.0, dt * 3.2)
	var k := minf(1.0, dt * 9.0)
	_alvo_vis = Rect2(_alvo_vis.position.lerp(alvo.position, k), _alvo_vis.size.lerp(alvo.size, k))
	var ponta := _ponta()
	_mao_vis = ponta if not _mao_vis.is_finite() else _mao_vis.lerp(ponta, k)
	# escuro com buraco
	_escuro.position = position
	_escuro.size = size
	_esc_a = escuro * _ease(minf(1.0, _troca * 2.0 + (1.0 if alvo.size != Vector2.ZERO else 0.0)))
	_buraco = Rect2()
	if _alvo_vis.size != Vector2.ZERO and alvo.size != Vector2.ZERO:
		_buraco = _alvo_vis.grow(8)
		_buraco.position += palco_offset
	_escuro.queue_redraw()
	_layout()
	queue_redraw()

## Escurece tudo menos o buraco: 4 retângulos em volta + os 4 cantos arredondados.
func _desenhar_escuro() -> void:
	if _esc_a <= 0.005:
		return
	var cor := Color(0.015, 0.02, 0.06, _esc_a)
	var g := Rect2(-palco_offset - Vector2(margem + 50, margem + 50), Vector2(W, H) + Vector2(margem + 50, margem + 50) * 2.0)
	g = g.merge(Rect2(Vector2.ZERO, size).grow(50))
	var b := _buraco
	if b.size == Vector2.ZERO:
		_escuro.draw_rect(g, cor)
		return
	var raio := minf(b.size.x, b.size.y) * 0.5 if alvo_redondo else minf(20.0, minf(b.size.x, b.size.y) * 0.5)
	if alvo_redondo:
		var lado := maxf(b.size.x, b.size.y)
		b = Rect2(b.get_center() - Vector2(lado, lado) / 2.0, Vector2(lado, lado))
		raio = lado / 2.0
	_escuro.draw_rect(Rect2(g.position, Vector2(g.size.x, b.position.y - g.position.y)), cor)                 # cima
	_escuro.draw_rect(Rect2(g.position.x, b.end.y, g.size.x, g.end.y - b.end.y), cor)                       # baixo
	_escuro.draw_rect(Rect2(g.position.x, b.position.y, b.position.x - g.position.x, b.size.y), cor)        # esquerda
	_escuro.draw_rect(Rect2(b.end.x, b.position.y, g.end.x - b.end.x, b.size.y), cor)                       # direita
	var cantos := [[b.position, b.position + Vector2(raio, raio), PI, PI * 1.5],
		[Vector2(b.end.x, b.position.y), Vector2(b.end.x - raio, b.position.y + raio), PI * 1.5, TAU],
		[b.end, b.end - Vector2(raio, raio), 0.0, PI * 0.5],
		[Vector2(b.position.x, b.end.y), Vector2(b.position.x + raio, b.end.y - raio), PI * 0.5, PI]]
	for c in cantos:
		var pts := PackedVector2Array([c[0]])
		var n := 10
		for k in n + 1:
			var ang: float = lerpf(c[2], c[3], float(k) / n)
			pts.append(c[1] + Vector2(cos(ang), sin(ang)) * raio)
		_escuro.draw_colored_polygon(pts, cor)

func _ponta() -> Vector2:
	if mao_ponto.is_finite():
		return mao_ponto
	return alvo.get_center()

static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

# =================================================================== BALÃO: onde fica
func _layout() -> void:
	var w := largura_balao
	var tw := w - 48.0
	_texto_h = f_texto.get_multiline_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, tw, 20).y if texto != "" else 0.0
	var h := 72.0 + _texto_h + (extra_h + 14.0 if extra.is_valid() else 0.0) + (34.0 if total > 1 else 14.0) + 46.0 + 22.0
	var a := alvo.grow(14)
	var lado := lado_balao
	if alvo.size == Vector2.ZERO and lado == "auto":
		lado = "meio"
	elif lado == "auto":
		if a.end.y + h + 10 < H - 8:
			lado = "baixo"
		elif a.position.y - h - 10 > 8:
			lado = "cima"
		elif a.end.x + w + 10 < W - 8:
			lado = "direita"
		else:
			lado = "esquerda"
	var p := Vector2.ZERO
	match lado:
		"meio": p = Vector2(W / 2.0 - w / 2.0, H / 2.0 - h / 2.0)
		"topo": p = Vector2(W / 2.0 - w / 2.0, 16)
		"baixo": p = Vector2(a.get_center().x - w / 2.0, a.end.y + 10)
		"cima": p = Vector2(a.get_center().x - w / 2.0, a.position.y - h - 10)
		"direita": p = Vector2(a.end.x + 10, a.get_center().y - h / 2.0)
		"esquerda": p = Vector2(a.position.x - w - 10, a.get_center().y - h / 2.0)
	var vis := size
	var min_x := -palco_offset.x + 12.0 if margem <= 0.0 else 12.0
	var max_x := vis.x - palco_offset.x - 12.0 if margem <= 0.0 else W - 12.0
	p.x = clampf(p.x, min_x, max_x - w)
	p.y = clampf(p.y, 10.0, H - h - 10.0)
	_balao = Rect2(p, Vector2(w, h))
	var by := _balao.end.y - 22.0 - 46.0
	if bt_txt != "":
		var bw := maxf(150.0, f_titulo.get_string_size(bt_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 56.0)
		_bt = Rect2(_balao.end.x - 22.0 - bw, by, bw, 46)
	else:
		_bt = Rect2()
	_bt_pular = Rect2(_balao.position.x + 16, by + 4, 150, 38) if pode_pular else Rect2()

# =================================================================== TOQUES
func _input(ev: InputEvent) -> void:
	if not ativo or not visible:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER or ev.keycode == KEY_SPACE):
		if bt_txt != "" and _desde > 0.3:
			principal.emit()
		get_viewport().set_input_as_handled()
		return
	var toque: bool = ev is InputEventScreenTouch or (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT)
	if not toque:
		if ev is InputEventScreenDrag or ev is InputEventMouseMotion:
			return
		return
	var real: bool = ev is InputEventScreenTouch or ev.device != InputEvent.DEVICE_ID_EMULATION
	var p: Vector2 = make_input_local(ev).position - palco_offset
	var no_alvo := alvo.size != Vector2.ZERO and (_dentro_redondo(p) if alvo_redondo else alvo.grow(6).has_point(p))
	# 1) botões do balão
	if _bt.size != Vector2.ZERO and _bt.grow(6).has_point(p):
		if real:
			if ev.pressed:
				_apertado = "bt"
			elif _apertado == "bt" and _desde > 0.3:
				_apertado = ""
				principal.emit()
		get_viewport().set_input_as_handled()
		return
	if _bt_pular.size != Vector2.ZERO and _bt_pular.grow(4).has_point(p):
		if real:
			if ev.pressed:
				_apertado = "pular"
			elif _apertado == "pular" and _desde > 0.3:
				_apertado = ""
				pulou.emit()
		get_viewport().set_input_as_handled()
		return
	if not ev.pressed:
		_apertado = ""
	if _balao.has_point(p) and not no_alvo:
		get_viewport().set_input_as_handled()
		return
	# 2) o alvo: o toque segue para o jogo
	if no_alvo and deixar_alvo:
		if real and ev.pressed:
			tocou_alvo.emit(p)
		return
	# 3) fora: segura (para a pessoa não se perder)
	if bloquear:
		get_viewport().set_input_as_handled()

func _dentro_redondo(p: Vector2) -> bool:
	return p.distance_to(alvo.get_center()) <= alvo.size.x * 0.5 + 10.0

# =================================================================== DESENHO
func _draw() -> void:
	if not ativo:
		return
	draw_set_transform(palco_offset)
	var e := _ease(_troca)
	# moldura brilhante em volta do alvo
	if _alvo_vis.size != Vector2.ZERO and alvo.size != Vector2.ZERO:
		var pul := 0.5 + 0.5 * sin(_t * 4.0)
		var r := _alvo_vis.grow(8)
		if alvo_redondo:
			var c := r.get_center()
			var rr := r.size.x * 0.5
			for i in 3:
				draw_arc(c, rr + 4 + i * 5 + pul * 4, 0, TAU, 48, Color(1, 0.85, 0.3, (0.35 - i * 0.1) * e), 3.0, true)
			draw_arc(c, rr, 0, TAU, 48, Color(OURO2, e), 4.0, true)
		else:
			for i in 3:
				_contorno(r.grow(4 + i * 5 + pul * 4), Color(1, 0.85, 0.3, (0.3 - i * 0.09) * e), 3.0, 20 + i * 5)
			_contorno(r, Color(CONTORNO, 0.8 * e), 7.0, 18)
			_contorno(r, Color(OURO2, e), 4.0, 18)
	# mãozinha
	if mao and _mao_vis.is_finite():
		_desenhar_mao(_mao_vis)
	# balão
	_desenhar_balao(e)
	draw_set_transform(Vector2.ZERO)

func _contorno(r: Rect2, cor: Color, esp: float, raio: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(int(esp))
	sb.border_color = cor
	sb.set_corner_radius_all(raio)
	sb.anti_aliasing = true
	draw_style_box(sb, r)

func _caixa(r: Rect2, cor: Color, raio: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = cor
	sb.set_corner_radius_all(raio)
	sb.anti_aliasing = true
	draw_style_box(sb, r)

func _degrade_caixa(r: Rect2, cima: Color, baixo: Color, raio: int) -> void:
	_caixa(r, baixo, raio)
	var faixas := 6
	for i in range(1, faixas):
		var k := float(i) / faixas
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(cima, 0.32)
		sb.set_corner_radius_all(raio)
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(r.position, Vector2(r.size.x, r.size.y * (1.0 - k))))

func texto_contorno(pos: Vector2, txt: String, tam: int, cor: Color, f: Font, centro := false, grossura := 6) -> void:
	if centro:
		pos.x -= f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x / 2.0
	draw_string_outline(f, pos + Vector2(0, 3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, grossura, Color(CONTORNO, cor.a))
	draw_string(f, pos + Vector2(0, 3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, Color(CONTORNO, cor.a))
	draw_string_outline(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, grossura, Color(CONTORNO, cor.a))
	draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)

func _desenhar_balao(e: float) -> void:
	var b := _balao
	b.position.y += (1.0 - e) * 18.0
	var a := e
	# rabinho apontando para o alvo
	if alvo.size != Vector2.ZERO and lado_balao != "meio":
		var c := _alvo_vis.get_center()
		var base := Vector2(clampf(c.x, b.position.x + 40, b.end.x - 40), clampf(c.y, b.position.y + 40, b.end.y - 40))
		var lado := ""
		if c.y < b.position.y:
			base.y = b.position.y + 2
			lado = "cima"
		elif c.y > b.end.y:
			base.y = b.end.y - 2
			lado = "baixo"
		elif c.x < b.position.x:
			base.x = b.position.x + 2
			lado = "esq"
		else:
			base.x = b.end.x - 2
			lado = "dir"
		var dir := (c - base).normalized()
		var ponta := base + dir * 22.0
		var lat := Vector2(-dir.y, dir.x) * 16.0
		var tri := PackedVector2Array([base + lat, ponta, base - lat])
		draw_colored_polygon(PackedVector2Array([base + lat * 1.3, ponta + dir * 5, base - lat * 1.3]), Color(CONTORNO, a))
		draw_colored_polygon(tri, Color(OURO2, a))
	# corpo
	_caixa(Rect2(b.position + Vector2(0, 8), b.size).grow(4), Color(0, 0, 0, 0.35 * a), 26)
	_caixa(b.grow(5), Color(CONTORNO, a), 26)
	_caixa(b.grow(3), Color(OURO3, a), 24)
	_degrade_caixa(Rect2(b.position.x - 3, b.position.y - 3, b.size.x + 6, b.size.y * 0.5), Color(OURO1, a), Color(OURO2, a), 24)
	_degrade_caixa(b, Color(Color("41539c"), a), Color(Color("1b2350"), a), 22)
	# título
	var x := b.position.x + 24
	var y := b.position.y + 26 + 28
	texto_contorno(Vector2(x, y), titulo, 30, Color(Color("ffd34d"), a), f_titulo)
	# texto
	y += 18
	if texto != "":
		draw_multiline_string(f_texto, Vector2(x, y + 16), texto, HORIZONTAL_ALIGNMENT_LEFT, b.size.x - 48, 20, -1, Color(Color("f2f0ff"), a))
		y += _texto_h
	# ilustração
	if extra.is_valid():
		y += 14
		extra.call(Rect2(x, y, b.size.x - 48, extra_h))
		y += extra_h
	# pontinhos dos passos
	var by := b.end.y - 22 - 46
	if total > 1:
		var n := total
		var dw := 12.0
		var x0 := b.get_center().x - (n - 1) * dw / 2.0
		if _bt.size != Vector2.ZERO and _bt_pular.size != Vector2.ZERO:
			x0 = b.get_center().x - (n - 1) * dw / 2.0
		for i in n:
			var cc := Vector2(x0 + i * dw, by - 17)
			draw_circle(cc, 4.0 if i == passo else 3.0, Color(Color("ffd34d") if i == passo else Color(1, 1, 1, 0.3), a))
	# pular
	if _bt_pular.size != Vector2.ZERO:
		var pr := Rect2(_bt_pular.position + Vector2(0, (1.0 - e) * 18.0), _bt_pular.size)
		draw_string(f_texto, Vector2(pr.position.x + 6, pr.position.y + 26), "Pular tutorial", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(Color("b9c0ea"), a * 0.9))
		var lw := f_texto.get_string_size("Pular tutorial", HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_line(Vector2(pr.position.x + 6, pr.position.y + 30), Vector2(pr.position.x + 6 + lw, pr.position.y + 30), Color(Color("b9c0ea"), a * 0.5), 1.5)
	# botão principal
	if _bt.size != Vector2.ZERO:
		var r := Rect2(_bt.position + Vector2(0, (1.0 - e) * 18.0), _bt.size)
		var afunda := 3.0 if _apertado == "bt" else 0.0
		var pul := 0.5 + 0.5 * sin(_t * 5.0)
		_caixa(Rect2(r.position + Vector2(0, 5), r.size).grow(3), Color(CONTORNO, a), 18)
		r.position.y += afunda
		_caixa(r.grow(3), Color(CONTORNO, a), 18)
		_caixa(r, Color(Color("d98a12"), a), 16)
		_degrade_caixa(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.55)), Color(Color("fff3b0"), a), Color(Color("f6c343"), a), 16)
		_caixa(Rect2(r.position.x + 12, r.position.y + 4, r.size.x - 24, 8), Color(1, 1, 1, 0.3 * a), 4)
		_contorno(r.grow(2 + pul * 3), Color(1, 0.9, 0.4, 0.35 * a * (1.0 - pul)), 2.0, 18)
		texto_contorno(Vector2(r.get_center().x, r.position.y + 32), bt_txt, 22, Color(1, 1, 1, a), f_titulo, true, 6)

# =================================================================== MÃOZINHA (luva de desenho animado)
func _desenhar_mao(ponta: Vector2) -> void:
	var ciclo := fmod(_t, 1.3) / 1.3
	# vai até o alvo, aperta e volta
	var ida := 0.0
	if ciclo < 0.35:
		ida = _ease(ciclo / 0.35)
	elif ciclo < 0.55:
		ida = 1.0
	else:
		ida = 1.0 - _ease((ciclo - 0.55) / 0.45) * 0.85
	var aperta := 1.0 - 0.1 * clampf(1.0 - absf(ciclo - 0.45) / 0.1, 0.0, 1.0)
	# de onde vem: de baixo-direita (ou de cima, se o alvo estiver lá embaixo)
	var de_cima := ponta.y > 520.0
	var ang := deg_to_rad(-28.0) if not de_cima else deg_to_rad(208.0)
	if ponta.x > W - 160.0:
		ang = deg_to_rad(28.0) if not de_cima else deg_to_rad(152.0)
	var dir := Vector2(0, 1).rotated(ang)                       # do dedo para o pulso
	var pos := ponta + dir * (34.0 * (1.0 - ida) + 4.0)
	# círculo do toque
	if ciclo > 0.4 and ciclo < 1.0:
		var k := (ciclo - 0.4) / 0.6
		draw_arc(ponta, 10.0 + 34.0 * k, 0, TAU, 40, Color(1, 1, 1, 0.75 * (1.0 - k)), 4.0 * (1.0 - k) + 1.0, true)
		draw_arc(ponta, 6.0 + 18.0 * k, 0, TAU, 32, Color(1, 0.86, 0.35, 0.6 * (1.0 - k)), 3.0, true)
	var s := 1.05 * aperta
	draw_set_transform(palco_offset + pos + Vector2(7, 10), ang, Vector2(s, s * 1.1))
	draw_circle(Vector2(8, 60), 30.0, Color(0, 0, 0, 0.16))
	draw_circle(Vector2(8, 60), 22.0, Color(0, 0, 0, 0.1))
	draw_set_transform(palco_offset + pos, ang, Vector2(s, s))
	_forma_mao(Color.WHITE, CONTORNO, false)
	draw_set_transform(palco_offset)

func _capsula(a: Vector2, b: Vector2, r: float, cor: Color) -> void:
	draw_circle(a, r, cor)
	draw_circle(b, r, cor)
	var n := (b - a).normalized()
	var l := Vector2(-n.y, n.x) * r
	draw_colored_polygon(PackedVector2Array([a + l, b + l, b - l, a - l]), cor)

func _rret(r: Rect2, raio: float, cor: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = cor
	sb.set_corner_radius_all(int(raio))
	sb.anti_aliasing = true
	draw_style_box(sb, r)

## Desenha a mão com o dedo indicador apontando para cima; a ponta do dedo é (0, 0).
func _forma_mao(cor: Color, contorno: Color, so_sombra: bool) -> void:
	var g := 3.5 if not so_sombra else 0.0
	var corpos := func(c: Color, extra: float) -> void:
		_capsula(Vector2(0, 9), Vector2(0, 44), 9.0 + extra, c)                       # indicador
		_rret(Rect2(-13 - extra, 34 - extra, 44 + extra * 2, 50 + extra * 2), 14 + extra, c)   # palma
		draw_circle(Vector2(17, 40), 9.0 + extra, c)                                  # dedos dobrados
		draw_circle(Vector2(26, 50), 8.5 + extra, c)
		draw_circle(Vector2(29, 63), 8.0 + extra, c)
		_capsula(Vector2(-9, 66), Vector2(-22, 52), 7.5 + extra, c)                   # polegar
	if so_sombra:
		corpos.call(cor, 0.0)
		_rret(Rect2(-15, 82, 50, 18), 6, cor)
		return
	corpos.call(contorno, g)
	_rret(Rect2(-15 - g, 82 - g, 50 + g * 2, 18 + g * 2), 6 + g, contorno)             # punho (contorno)
	corpos.call(cor, 0.0)
	# punho da luva
	_rret(Rect2(-15, 82, 50, 18), 6, Color("dfe6ff"))
	draw_line(Vector2(-11, 88), Vector2(31, 88), Color("9aa6d6"), 2.0)
	draw_line(Vector2(-11, 94), Vector2(31, 94), Color("9aa6d6"), 2.0)
	# sombrinhas e vincos
	draw_arc(Vector2(17, 40), 9.0, deg_to_rad(110), deg_to_rad(200), 8, Color(contorno, 0.55), 2.0, true)
	draw_arc(Vector2(26, 50), 8.5, deg_to_rad(110), deg_to_rad(200), 8, Color(contorno, 0.55), 2.0, true)
	draw_arc(Vector2(29, 63), 8.0, deg_to_rad(110), deg_to_rad(200), 8, Color(contorno, 0.55), 2.0, true)
	draw_line(Vector2(-4, 30), Vector2(4, 30), Color(contorno, 0.35), 2.0)
	draw_line(Vector2(-2, 66), Vector2(-9, 58), Color(contorno, 0.4), 2.0)
	draw_line(Vector2(6, 4), Vector2(6, 16), Color(1, 1, 1, 0.0), 1.0)
	_capsula(Vector2(-4, 10), Vector2(-4, 26), 2.0, Color(1, 1, 1, 0.9))               # brilho do dedo
