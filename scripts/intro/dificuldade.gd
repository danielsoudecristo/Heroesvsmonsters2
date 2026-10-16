extends Control
## DIFICULDADE DA CAMPANHA (aparece no "Novo jogo"): Fácil, Médio, Difícil e HardCore.
## Os números ficam em ConfigArena.DIFICULDADES. Escolheu = salva no Perfil.dificuldade e começa a campanha.

const JANELA := Rect2(70, 50, 1140, 630)
const CARTA := Vector2(250, 470)
const ESPACO := 18.0
const C := preload("res://scripts/arena/config_arena.gd")
## Os textos são de propósito NEUTROS (inimigos): valem para os dois lados da campanha.
const TEXTOS := {
	"facil":    ["Inimigos 25% mais fracos", "Menos inimigos", "+100 energia · céu +20%", "Energia fica 12 s no chão"],
	"medio":    ["O jogo normal", "Hordas no fim de cada nível", "+50 energia no começo", "Energia fica 9 s no chão"],
	"dificil":  ["Inimigos 25% mais fortes", "20% mais inimigos", "+75 energia · céu +10%", "Mais montes de inimigos"],
	"hardcore": ["Inimigos 50% mais fortes", "35% mais inimigos", "+120 energia · céu +25%", "Perdeu = volta ao nível 1!"],
}

var intro: Node
var escolheu: Callable                              # chamado com o id depois de escolher
var _abre := 0.0
var _relogio := 0.0
var _apertado := -1

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # (ocupa a tela toda: senão os toques não chegam)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func abrir() -> void:
	_quadro_abriu = Engine.get_process_frames()       # (o mesmo toque que abriu não pode fechar)
	visible = true
	_abre = 0.0
	_tocou_aqui = false

func fechar() -> void:
	visible = false
	_apertado = -1

func _process(dt: float) -> void:
	if not visible:
		return
	_relogio += dt
	_abre = move_toward(_abre, 1.0, dt * 4.0)
	queue_redraw()

func _ret_carta(i: int) -> Rect2:
	var n := C.ORDEM_DIFICULDADES.size()
	var larg := n * CARTA.x + (n - 1) * ESPACO
	return Rect2(JANELA.get_center().x - larg / 2.0 + i * (CARTA.x + ESPACO), JANELA.position.y + 118, CARTA.x, CARTA.y)

func _ret_fechar() -> Rect2:
	return Rect2(JANELA.end.x - 92, JANELA.position.y + 30, 64, 60)

var _tocou_aqui := false

var _quadro_abriu := -1

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and Engine.get_process_frames() == _quadro_abriu:
		accept_event()
		return
	if not (ev is InputEventMouseButton) or ev.button_index != MOUSE_BUTTON_LEFT:
		return
	var p: Vector2 = ev.position - intro.O
	if ev.pressed:
		_tocou_aqui = true
		_apertado = -1
		for i in C.ORDEM_DIFICULDADES.size():
			if _ret_carta(i).has_point(p):
				_apertado = i
	else:
		_apertado = -1
		if _tocou_aqui:                                 # (o toque que abriu a janela não conta)
			_tocou_aqui = false
			_tocar(p)
	accept_event()

func _tocar(p: Vector2) -> void:
	if _ret_fechar().grow(6).has_point(p) or not JANELA.grow(10).has_point(p):
		intro._clique(false)
		fechar()
		return
	for i in C.ORDEM_DIFICULDADES.size():
		if _ret_carta(i).has_point(p):
			var id: String = C.ORDEM_DIFICULDADES[i]
			intro._clique(true)
			Perfil.dificuldade = id
			Perfil.salvar()
			fechar()
			if escolheu.is_valid():
				escolheu.call(id)
			return

# =================================================================== DESENHO
static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

func _draw() -> void:
	intro._ci = self
	var O: Vector2 = intro.O
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.05, 0.62 * _abre))
	var k := 0.92 + 0.08 * _ease(_abre)
	draw_set_transform(O + JANELA.get_center() - JANELA.get_center() * k, 0.0, Vector2(k, k))
	var j := JANELA
	var NAVY: Color = intro.NAVY
	intro._caixa(Rect2(j.position + Vector2(0, 12), j.size).grow(10), Color(0, 0, 0, 0.45), 40)
	intro._caixa(j.grow(10), Color("4a2a06"), 38)
	intro._caixa(j.grow(8), Color("b8740f"), 36)
	intro._caixa(Rect2(j.position.x - 8, j.position.y - 8, j.size.x + 16, j.size.y * 0.5), Color("f6c343"), 36)
	intro._caixa(j.grow(3), NAVY, 31)
	intro._painel(j, Color("3e4f96"), Color("1f2754"), 29)
	intro._texto_cartoon(Vector2(j.position.x + 40, j.position.y + 78), "Escolha a dificuldade", 44, Color("ffd34d"), intro.f_titulo, 2.5, false)
	var f := _ret_fechar()
	intro._caixa(Rect2(f.position + Vector2(0, 5), f.size).grow(3), NAVY, 18)
	intro._caixa(f.grow(3), NAVY, 18)
	intro._botao_degrade(f, Color("7f95e6"), Color("4a5fae"), Color("2c3874"), 16)
	var fc := f.get_center()
	for s in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(fc - s * 11, fc + s * 11, intro.CONTORNO, 7.0, true)
		draw_line(fc - s * 11, fc + s * 11, Color.WHITE, 4.0, true)
	for i in C.ORDEM_DIFICULDADES.size():
		_carta(i)
	draw_set_transform(Vector2.ZERO)

func _carta(i: int) -> void:
	var id: String = C.ORDEM_DIFICULDADES[i]
	var d: Dictionary = C.DIFICULDADES[id]
	var cor: Color = d.cor
	var r := _ret_carta(i)
	var entra := clampf(_abre * 2.0 - i * 0.15, 0.0, 1.0)
	r.position.y += (1.0 - _ease(entra)) * 40.0
	if _apertado == i:
		r.position.y += 4
	var ultima := Perfil.dificuldade == id
	if ultima:
		var pul := 0.5 + 0.5 * sin(_relogio * 3.0)
		intro._caixa(r.grow(9), Color(cor, 0.25 + 0.15 * pul), 26)
	intro._caixa(Rect2(r.position + Vector2(0, 7), r.size), Color(0, 0, 0, 0.35), 22)
	intro._caixa(r.grow(3), intro.CONTORNO, 24)
	intro._painel(r, Color("34418a"), Color("1b2350"), 22)
	# faixa de cima com a cor
	var topo := Rect2(r.position + Vector2(8, 8), Vector2(r.size.x - 16, 112))
	intro._botao_degrade(topo, cor.lightened(0.35), cor, cor.darkened(0.35), 16)
	intro._texto_cartoon(Vector2(topo.get_center().x, topo.position.y + 42), d.nome, 32, Color.WHITE, intro.f_titulo, 2.0, true)
	# caveiras (1 a 4)
	var n := i + 1
	var cx := topo.get_center().x - (n - 1) * 17.0
	for q in n:
		_caveira(Vector2(cx + q * 34.0, topo.position.y + 80), 13.0)
	# o que muda
	var y := r.position.y + 160.0
	for linha in TEXTOS[id]:
		intro._caixa(Rect2(r.position.x + 18, y - 9, 8, 8), Color(cor, 0.9), 4)
		intro._texto_cartoon(Vector2(r.position.x + 34, y), linha, 16, Color("eef0ff"), intro.f_texto, 1.1, false)
		y += 36.0
	# recorde (um por lado: heróis e monstros não misturam)
	var rec := Perfil.recorde(id, Perfil.lado)
	intro._texto_cartoon(Vector2(r.get_center().x, r.end.y - 142), ("Recorde: nível %d" % rec) if rec > 0 else "Sem recorde ainda",
		18, Color("ffd34d") if rec > 0 else Color(1, 1, 1, 0.55), intro.f_titulo, 1.3, true)
	# moedas
	var mr := Rect2(r.position.x + 30, r.end.y - 128, r.size.x - 60, 44)
	intro._caixa(mr, Color(0.05, 0.06, 0.15, 0.7), 22)
	intro._moeda(Vector2(mr.position.x + 30, mr.get_center().y), 28)
	var mv := float(d.moedas)
	var mtxt := "Moedas ×%s" % (str(int(mv)) if is_equal_approx(mv, roundf(mv)) else str(mv).replace(".", ","))
	intro._texto_cartoon(Vector2(mr.position.x + 52, mr.position.y + 31), mtxt, 21, Color("fff6d0"), intro.f_titulo, 1.4, false)
	# botão
	var b := Rect2(r.position.x + 22, r.end.y - 68, r.size.x - 44, 50)
	intro._caixa(Rect2(b.position + Vector2(0, 5), b.size).grow(2), intro.CONTORNO, 18)
	intro._caixa(b.grow(2), intro.CONTORNO, 18)
	intro._botao_degrade(b, cor.lightened(0.4), cor, cor.darkened(0.3), 16)
	intro._texto_cartoon(Vector2(b.get_center().x, b.position.y + 35), "Jogar", 26, Color.WHITE, intro.f_titulo, 1.8, true)
	if ultima:
		var tag := Rect2(r.get_center().x - 52, r.position.y - 16, 104, 30)
		intro._caixa(tag.grow(2), intro.CONTORNO, 15)
		intro._botao_degrade(tag, Color("fff3b0"), Color("f6c343"), Color("b8740f"), 13)
		intro._texto_cartoon(Vector2(tag.get_center().x, tag.position.y + 22), "ÚLTIMA", 16, Color.WHITE, intro.f_titulo, 1.2, true)

func _caveira(c: Vector2, r: float) -> void:
	draw_circle(c + Vector2(0, 2), r + 2, Color(0, 0, 0, 0.35))
	draw_circle(c, r + 2, intro.CONTORNO)
	draw_circle(c, r, Color("fff6e6"))
	draw_rect(Rect2(c.x - r * 0.55, c.y + r * 0.45, r * 1.1, r * 0.75), intro.CONTORNO)
	draw_rect(Rect2(c.x - r * 0.45, c.y + r * 0.35, r * 0.9, r * 0.65), Color("fff6e6"))
	draw_circle(c + Vector2(-r * 0.38, -r * 0.05), r * 0.27, intro.CONTORNO)
	draw_circle(c + Vector2(r * 0.38, -r * 0.05), r * 0.27, intro.CONTORNO)
