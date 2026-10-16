extends Control
## TELA DE DERROTA da campanha: o castelo caiu. Em vez de um texto solto, um painel bonito que mostra
## até onde a pessoa chegou, quanto faltou, QUEM derrubou o castelo e QUEM usar contra ele (com os retratos),
## e um botão grande de TENTAR DE NOVO pulsando — é o que faz a pessoa querer jogar mais uma.

const C := preload("res://scripts/arena/config_arena.gd")

const PAINEL := Rect2(C.W / 2.0 - 330, 70, 660, 470)
const COR_CONTORNO := Color("24130a")
const COR_CREME := Color("fff4d6")
const COR_OURO := Color("f2c14e")

var arena: Node
var hud: Control
var d: Dictionary = {}                 # o que mostrar (arena._dados_derrota())
var t := 0.0
var bt_tentar: Button
var bt_menu: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP          # a arena atrás não recebe toque
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(C.W, C.H)
	visible = false
	bt_tentar = _botao("↻  TENTAR DE NOVO", Color("3fae3a"), Color("0f3a12"), Rect2(PAINEL.get_center().x - 175, PAINEL.end.y - 92, 250, 66), 28)
	bt_menu = _botao("MENU", Color("4a5fae"), Color("141a36"), Rect2(PAINEL.get_center().x + 89, PAINEL.end.y - 86, 104, 58), 22)
	bt_tentar.pressed.connect(func():
		Sons.tocar("Jogo/som/clique", 0.6)
		arena._tentar_de_novo())
	bt_menu.pressed.connect(func():
		Sons.tocar("Jogo/som/clique", 0.5)
		arena._menu_ir())

func _botao(txt: String, cor: Color, borda: Color, r: Rect2, tam: int) -> Button:
	var b := Button.new()
	b.text = txt
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	if hud and hud.f_titulo:
		b.add_theme_font_override("font", hud.f_titulo)
	b.add_theme_font_size_override("font_size", tam)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_color_override("font_outline_color", COR_CONTORNO)
	b.add_theme_constant_override("outline_size", 7)
	for estado in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = cor.lightened(0.12 if estado == "hover" else 0.0).darkened(0.12 if estado == "pressed" else 0.0)
		sb.set_corner_radius_all(20)
		sb.set_border_width_all(3)
		sb.border_color = borda
		sb.border_width_bottom = 3 if estado == "pressed" else 8
		sb.content_margin_top = 4 if estado == "pressed" else 0
		sb.anti_aliasing = true
		b.add_theme_stylebox_override(estado, sb)
	add_child(b)
	return b

## Mostra a tela. dados = arena._dados_derrota().
func mostrar(dados: Dictionary) -> void:
	d = dados
	t = 0.0
	bt_tentar.text = "↻  RECOMEÇAR" if d.get("perde_tudo", false) else "↻  TENTAR DE NOVO"
	visible = true
	queue_redraw()

func esconder() -> void:
	visible = false

func _process(dt: float) -> void:
	if not visible:
		return
	t += dt
	# o painel cai de cima e quica; os botões aparecem junto
	var k := _entrada()
	var dy := (1.0 - k) * -420.0
	bt_tentar.position.y = PAINEL.end.y - 92 + dy
	bt_menu.position.y = PAINEL.end.y - 86 + dy
	var pulso := 1.0 + 0.035 * sin(t * 5.0) * clampf(t - 0.8, 0.0, 1.0)
	bt_tentar.pivot_offset = bt_tentar.size / 2.0
	bt_tentar.scale = Vector2.ONE * pulso
	queue_redraw()

## 0 → 1 com um quique no fim (o painel "pousa").
func _entrada() -> float:
	var x := clampf((t - 0.25) / 0.55, 0.0, 1.0)
	var c1 := 1.70158 * 1.2
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)

# ================================================================= DESENHO
func _draw() -> void:
	if d.is_empty():
		return
	var ft: Font = hud.f_titulo
	var fx: Font = hud.f_texto
	# 1) a tela escurece puxando para o vermelho, com vinheta (o castelo caiu)
	var a := clampf(t / 0.4, 0.0, 1.0)
	var tt := C.tela_toda(self)                       # (celular largo: cobre as laterais também)
	draw_rect(tt, Color(0.07, 0.0, 0.03, 0.6 * a))
	var forte := Color(0.2, 0.0, 0.02, 0.55 * a)
	var nada := Color(0.2, 0.0, 0.02, 0.0)
	var L := 190.0
	var p0 := tt.position
	var p1 := tt.end
	for q in [[p0, Vector2(p1.x, p0.y), Vector2(p1.x, p0.y + L), Vector2(p0.x, p0.y + L)], [Vector2(p0.x, p1.y), p1, Vector2(p1.x, p1.y - L), Vector2(p0.x, p1.y - L)],
			[p0, Vector2(p0.x, p1.y), Vector2(p0.x + L, p1.y), Vector2(p0.x + L, p0.y)], [Vector2(p1.x, p0.y), p1, Vector2(p1.x - L, p1.y), Vector2(p1.x - L, p0.y)]]:
		draw_polygon(PackedVector2Array(q), PackedColorArray([forte, forte, nada, nada]))
	# brasas subindo
	for s in 26:
		var fase := fmod(t * 0.12 + s * 0.0385, 1.0)
		var px := fmod(s * 197.3, C.W) + sin(t * 1.3 + s) * 18.0
		var py := C.H + 10.0 - fase * (C.H + 40.0)
		draw_circle(Vector2(px, py), 2.4 * (1.0 - fase) + 0.8, Color(1.0, 0.55 + 0.3 * (1.0 - fase), 0.2, 0.75 * (1.0 - fase) * a))
	var k := _entrada()
	if k <= 0.0:
		return
	draw_set_transform(Vector2(0, (1.0 - k) * -420.0))
	var r := PAINEL
	# 2) painel: sombra, moldura dourada, fundo escuro em degradê e faixa de título vermelha
	_caixa(r.grow(10), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 34)
	_caixa(r.grow(4), Color("e0a93a"), COR_CONTORNO, 4, 30)
	_caixa(r, Color("2a1830"), Color("7a4a1a"), 2, 26)
	draw_polygon(PackedVector2Array([r.position + Vector2(6, 6), Vector2(r.end.x - 6, r.position.y + 6), r.end - Vector2(6, 6), Vector2(r.position.x + 6, r.end.y - 6)]),
		PackedColorArray([Color("3d2246"), Color("3d2246"), Color("160d1c"), Color("160d1c")]))
	var faixa := Rect2(r.position + Vector2(-26, 14), Vector2(r.size.x + 52, 74))
	_fita(faixa)
	# brasão: escudo rachado no topo
	_escudo_rachado(Vector2(r.get_center().x, r.position.y - 6), 1.0 + 0.04 * sin(t * 3.0))
	_texto(ft, Vector2(r.position.x, faixa.position.y + 56), "O CASTELO CAIU!", 46, COR_CREME, 12, Color("3a0608"), r.size.x)
	var sub := "%s · nível %d" % [str(d.get("dif_nome", "")), int(d.nivel)]
	if d.get("perde_tudo", false):
		sub += " · HardCore: volta para o nível 1"
	_texto(fx, Vector2(r.position.x, faixa.end.y + 30), sub, 19, Color("f5c9a8"), 5, COR_CONTORNO, r.size.x)
	# 3) quanto faltou: barra da horda derrotada
	var y := faixa.end.y + 50.0
	var feito: float = clampf(float(d.get("feito", 0.0)), 0.0, 1.0)
	var barra := Rect2(r.position.x + 60, y, r.size.x - 120, 26)
	_caixa(barra.grow(3), Color("120a10"), COR_CONTORNO, 3, 15)
	var cheio := feito * minf(1.0, maxf(0.0, (t - 0.7) / 0.9))
	if cheio > 0.01:
		var bc := Rect2(barra.position, Vector2(barra.size.x * cheio, barra.size.y))
		_caixa(bc, Color("e8562a").lerp(Color("f2c14e"), cheio), Color(0, 0, 0, 0), 0, 13)
		_caixa(Rect2(bc.position + Vector2(4, 3), Vector2(maxf(0.0, bc.size.x - 8), 7)), Color(1, 1, 1, 0.28), Color(0, 0, 0, 0), 0, 4)
	var frase := "FALTOU MUITO POUCO!" if feito >= 0.75 else ("Você derrubou metade da horda" if feito >= 0.45 else "A horda ainda estava forte")
	_texto(ft, Vector2(barra.position.x, barra.position.y + 20), "%s  ·  %d%%" % [frase, roundi(feito * 100.0)], 18, Color.WHITE, 6, COR_CONTORNO, barra.size.x)
	# 4) chips: nível alcançado e recorde
	y = barra.end.y + 18.0
	_chip(Rect2(r.position.x + 60, y, 260, 54), "NÍVEL ALCANÇADO", str(d.nivel), Color("5a3a8a"))
	_chip(Rect2(r.end.x - 320, y, 260, 54), "SEU RECORDE", str(d.recorde), Color("8a5a1a"))
	# 5) dica com retratos: quem derrubou o castelo → quem usar contra ele
	y += 70.0
	var caixa := Rect2(r.position.x + 30, y, r.size.x - 60, 122)
	_caixa(caixa, Color(0, 0, 0, 0.32), Color("6a4a2a"), 2, 16)
	var pior: PersonagemDados = d.get("pior")
	var fortes: Array = d.get("fortes", [])
	if pior and not fortes.is_empty():
		_retrato_moldura(pior, Rect2(caixa.position + Vector2(16, 12), Vector2(78, 78)), Color("c0392b"))
		_texto(fx, caixa.position + Vector2(4, 112), pior.nome_card(), 15, Color("ffb4a0"), 4, COR_CONTORNO, 102)
		_texto(ft, caixa.position + Vector2(104, 34), "QUEM DERRUBOU", 15, Color("ffb4a0"), 4, COR_CONTORNO, 140, HORIZONTAL_ALIGNMENT_LEFT)
		_texto(ft, caixa.position + Vector2(104, 52), "SEU CASTELO", 15, Color("ffb4a0"), 4, COR_CONTORNO, 140, HORIZONTAL_ALIGNMENT_LEFT)
		# seta animada
		var sx := caixa.position.x + 112 + 10.0 * sin(t * 4.0)
		var sy := caixa.position.y + 76
		draw_colored_polygon(PackedVector2Array([Vector2(sx, sy - 7), Vector2(sx + 70, sy - 7), Vector2(sx + 70, sy - 16), Vector2(sx + 96, sy), Vector2(sx + 70, sy + 16), Vector2(sx + 70, sy + 7), Vector2(sx, sy + 7)]), COR_OURO)
		var x0 := caixa.position.x + 262
		_texto(ft, Vector2(x0, caixa.position.y + 26), "USE CONTRA ELE:", 17, Color("b8f59a"), 5, COR_CONTORNO, 300, HORIZONTAL_ALIGNMENT_LEFT)
		for i in mini(2, fortes.size()):
			var pf: PersonagemDados = fortes[i]
			var rr := Rect2(Vector2(x0 + i * 160, caixa.position.y + 36), Vector2(62, 62))
			_retrato_moldura(pf, rr, Color("3fae3a"))
			_texto(ft, rr.position + Vector2(68, 30), pf.nome_card(), 17, Color.WHITE, 5, COR_CONTORNO, 96, HORIZONTAL_ALIGNMENT_LEFT)
			_texto(fx, rr.position + Vector2(68, 50), "Nv %d" % Perfil.nivel_de(pf.id), 14, Color("8fe36a"), 4, COR_CONTORNO, 90, HORIZONTAL_ALIGNMENT_LEFT)
		var ev: PersonagemDados = d.get("evoluir")
		if ev and int(d.get("custo", 0)) > 0:
			var tem := Perfil.moedas >= int(d.custo)
			var txt := "Evolua o %s para o Nv %d: %d moedas%s" % [ev.nome_card(), int(d.nv) + 1, int(d.custo), " ✔" if tem else ""]
			_texto(fx, Vector2(x0, caixa.end.y - 10), txt, 14, Color("ffe08a") if tem else Color("e8d8c0"), 4, COR_CONTORNO, caixa.end.x - x0 - 8, HORIZONTAL_ALIGNMENT_LEFT)
	else:
		_texto(ft, caixa.position + Vector2(0, 52), "DICA", 20, COR_OURO, 6, COR_CONTORNO, caixa.size.x)
		_texto(fx, caixa.position + Vector2(0, 84), str(d.get("dica", "Evolua suas cartas e use as que são fortes contra cada inimigo.")), 17, COR_CREME, 5, COR_CONTORNO, caixa.size.x)
	draw_set_transform(Vector2.ZERO)

func _fita(f: Rect2) -> void:
	# pontas dobradas (mais escuras) e a faixa vermelha com brilho em cima
	var esc := Color("6a0e14")
	draw_colored_polygon(PackedVector2Array([f.position + Vector2(-18, 14), f.position + Vector2(30, 14), f.position + Vector2(30, f.size.y + 10), f.position + Vector2(-18, f.size.y + 10), f.position + Vector2(0, f.size.y * 0.5 + 12)]), esc)
	draw_colored_polygon(PackedVector2Array([Vector2(f.end.x + 18, f.position.y + 14), Vector2(f.end.x - 30, f.position.y + 14), Vector2(f.end.x - 30, f.end.y + 10), Vector2(f.end.x + 18, f.end.y + 10), Vector2(f.end.x, f.position.y + f.size.y * 0.5 + 12)]), esc)
	_caixa(f, Color("b3202a"), COR_CONTORNO, 4, 10)
	_caixa(Rect2(f.position + Vector2(8, 6), Vector2(f.size.x - 16, 14)), Color(1, 0.6, 0.55, 0.25), Color(0, 0, 0, 0), 0, 6)

func _escudo_rachado(c: Vector2, esc: float) -> void:
	var pts := PackedVector2Array()
	for p in [Vector2(-34, -40), Vector2(34, -40), Vector2(34, 2), Vector2(0, 42), Vector2(-34, 2)]:
		pts.append(c + p * esc)
	draw_circle(c, 52 * esc, Color(1, 0.4, 0.15, 0.18 + 0.08 * sin(t * 3.0)))
	var borda := PackedVector2Array(pts)
	borda.append(pts[0])
	draw_colored_polygon(pts, Color("6a6f86"))
	var dentro := PackedVector2Array()
	for p in [Vector2(-26, -32), Vector2(26, -32), Vector2(26, 0), Vector2(0, 32), Vector2(-26, 0)]:
		dentro.append(c + p * esc)
	draw_colored_polygon(dentro, Color("2b3a7a"))
	draw_polyline(borda, COR_CONTORNO, 4.0, true)
	# rachadura
	var rach := PackedVector2Array()
	for p in [Vector2(-4, -40), Vector2(6, -22), Vector2(-6, -6), Vector2(8, 10), Vector2(0, 26), Vector2(4, 40)]:
		rach.append(c + p * esc)
	draw_polyline(rach, Color("12081a"), 5.0, true)
	draw_polyline(rach, Color(1, 0.55, 0.2, 0.9), 1.6, true)

func _chip(r: Rect2, titulo: String, valor: String, cor: Color) -> void:
	_caixa(r, cor.darkened(0.35), COR_CONTORNO, 3, 14)
	_caixa(Rect2(r.position + Vector2(4, 4), Vector2(r.size.x - 8, 18)), Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 8)
	_texto(hud.f_texto, r.position + Vector2(14, 34), titulo, 16, Color("f0e0ff"), 4, COR_CONTORNO, r.size.x - 80, HORIZONTAL_ALIGNMENT_LEFT)
	_texto(hud.f_titulo, r.position + Vector2(0, 41), valor, 34, COR_OURO, 7, COR_CONTORNO, r.size.x - 14, HORIZONTAL_ALIGNMENT_RIGHT)

func _retrato_moldura(p: PersonagemDados, r: Rect2, cor: Color) -> void:
	_caixa(r.grow(3), cor, COR_CONTORNO, 3, 12)
	var c0: Color = p.cores[0] if p.cores.size() > 0 else Color.WHITE
	var c1: Color = p.cores[1] if p.cores.size() > 1 else Color.GRAY
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([c0.lerp(c1, 0.25), c0.lerp(c1, 0.25), c1, c1]))
	var rt: Array = hud._retrato(p)
	if not rt.is_empty():
		var q: Rect2 = rt[1]
		var k := minf((r.size.x - 4) / q.size.x, (r.size.y - 4) / q.size.y)
		var tam := q.size * k
		draw_texture_rect_region(rt[0], Rect2(r.position + Vector2((r.size.x - tam.x) / 2, r.size.y - tam.y - 2), tam), q)
	_caixa(r, Color(0, 0, 0, 0), COR_CONTORNO, 2, 10)

func _texto(f: Font, pos: Vector2, txt: String, tam: int, cor: Color, contorno := 0, cor_contorno := COR_CONTORNO, largura := -1.0, alinha := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	if contorno > 0:
		draw_string_outline(f, pos, txt, alinha, largura, tam, contorno, cor_contorno)
	draw_string(f, pos, txt, alinha, largura, tam, cor)

func _caixa(r: Rect2, fundo: Color, borda: Color, esp: int, raio: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fundo
	sb.border_color = borda
	sb.set_border_width_all(esp)
	sb.set_corner_radius_all(raio)
	sb.anti_aliasing = true
	draw_style_box(sb, r)
