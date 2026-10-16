extends Control
## ESCOLHA DO MODO DA BATALHA PvP: "Batalha" (os dois atacam e defendem, vale troféus) ou
## "Cerco" (2 rodadas: você defende com os personagens parados e depois ataca; contra o bot, sem troféus).

const JANELA := Rect2(110, 46, 1060, 628)
const CARTA := Vector2(316, 470)
const ESPACO := 22.0
const MODOS := [
	{"id": "normal", "nome": "Batalha", "cor": Color("3a7bd5"), "tag": "VALE TROFÉUS",
	 "linhas": ["Atacam e defendem juntos", "Tropas marcham ao castelo", "3 min · derrube o castelo", "Duelo contra o mundo"]},
	{"id": "cerco", "nome": "Cerco", "cor": Color("c0392b"), "tag": "2 RODADAS",
	 "linhas": ["Rodada 1: você DEFENDE", "Rodada 2: você ATACA", "Aguente mais tempo", "Escolha Heroes ou Monsters"]},
	{"id": "campeonato", "nome": "Campeonato", "cor": Color("d68a1a"), "tag": "NOVO!",
	 "linhas": ["16 jogadores · mata-mata", "Heroes × Monsters sempre", "Oitavas até a FINAL", "Sala de 2 min com chat"]},
]

var intro: Node
var _abre := 0.0
var _relogio := 0.0
var _apertado := -1
var _quadro_abriu := -1
var _tocou_aqui := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func abrir() -> void:
	_quadro_abriu = Engine.get_process_frames()
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
	var larg := MODOS.size() * CARTA.x + (MODOS.size() - 1) * ESPACO
	return Rect2(JANELA.get_center().x - larg / 2.0 + i * (CARTA.x + ESPACO), JANELA.position.y + 122, CARTA.x, CARTA.y)

func _ret_fechar() -> Rect2:
	return Rect2(JANELA.end.x - 92, JANELA.position.y + 30, 64, 60)

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
		for i in MODOS.size():
			if _ret_carta(i).has_point(p):
				_apertado = i
	else:
		_apertado = -1
		if _tocou_aqui:
			_tocou_aqui = false
			_tocar(p)
	accept_event()

func _tocar(p: Vector2) -> void:
	if _ret_fechar().grow(6).has_point(p) or not JANELA.grow(10).has_point(p):
		intro._clique(false)
		fechar()
		return
	for i in MODOS.size():
		if _ret_carta(i).has_point(p):
			intro._clique(true)
			fechar()
			intro._escolheu_modo_pvp(str(MODOS[i].id))
			return

static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

func _draw() -> void:
	intro._ci = self
	var O: Vector2 = intro.O
	draw_rect(Rect2(-O, size), Color(0.02, 0.02, 0.05, 0.62 * _abre))
	var k := 0.92 + 0.08 * _ease(_abre)
	draw_set_transform(O + JANELA.get_center() - JANELA.get_center() * k, 0.0, Vector2(k, k))
	var j := JANELA
	intro._caixa(Rect2(j.position + Vector2(0, 12), j.size).grow(10), Color(0, 0, 0, 0.45), 40)
	intro._caixa(j.grow(10), Color("4a2a06"), 38)
	intro._caixa(j.grow(8), Color("b8740f"), 36)
	intro._caixa(Rect2(j.position.x - 8, j.position.y - 8, j.size.x + 16, j.size.y * 0.5), Color("f6c343"), 36)
	intro._caixa(j.grow(3), intro.NAVY, 31)
	intro._painel(j, Color("3e4f96"), Color("1f2754"), 29)
	intro._texto_cartoon(Vector2(j.position.x + 40, j.position.y + 80), "Escolha o modo de batalha", 44, Color("ffd34d"), intro.f_titulo, 2.5, false)
	var f := _ret_fechar()
	intro._caixa(Rect2(f.position + Vector2(0, 5), f.size).grow(3), intro.NAVY, 18)
	intro._caixa(f.grow(3), intro.NAVY, 18)
	intro._botao_degrade(f, Color("7f95e6"), Color("4a5fae"), Color("2c3874"), 16)
	var fc := f.get_center()
	for s in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(fc - s * 11, fc + s * 11, intro.CONTORNO, 7.0, true)
		draw_line(fc - s * 11, fc + s * 11, Color.WHITE, 4.0, true)
	for i in MODOS.size():
		_carta(i)
	draw_set_transform(Vector2.ZERO)

func _carta(i: int) -> void:
	var m: Dictionary = MODOS[i]
	var cor: Color = m.cor
	var r := _ret_carta(i)
	var entra := clampf(_abre * 2.0 - i * 0.2, 0.0, 1.0)
	r.position.y += (1.0 - _ease(entra)) * 40.0
	if _apertado == i:
		r.position.y += 4
	intro._caixa(Rect2(r.position + Vector2(0, 7), r.size), Color(0, 0, 0, 0.35), 24)
	intro._caixa(r.grow(3), intro.CONTORNO, 26)
	intro._painel(r, Color("34418a"), Color("1b2350"), 24)
	# faixa com a ilustração
	var topo := Rect2(r.position + Vector2(10, 10), Vector2(r.size.x - 20, 150))
	intro._botao_degrade(topo, cor.lightened(0.35), cor, cor.darkened(0.4), 18)
	var c := topo.get_center() + Vector2(0, -8)
	if m.id == "normal":
		_ilustra_batalha(c)
	elif m.id == "cerco":
		_ilustra_cerco(c)
	else:
		_ilustra_campeonato(c)
	intro._texto_cartoon(Vector2(topo.get_center().x, topo.end.y - 14), m.nome, 36, Color.WHITE, intro.f_titulo, 2.2, true)
	# etiqueta
	var tw: float = intro._larg(intro.f_titulo, m.tag, 16) + 28
	var tag := Rect2(r.get_center().x - tw / 2.0, r.position.y - 16, tw, 30)
	intro._caixa(tag.grow(2), intro.CONTORNO, 15)
	if m.id == "campeonato":
		var pul := 0.5 + 0.5 * sin(_relogio * 4.0)
		intro._caixa(tag.grow(4 + pul * 3), Color(1, 0.85, 0.3, 0.25), 18)
	intro._botao_degrade(tag, Color("fff3b0"), Color("f6c343"), Color("b8740f"), 13)
	intro._texto_cartoon(Vector2(tag.get_center().x, tag.position.y + 22), m.tag, 16, Color.WHITE, intro.f_titulo, 1.2, true)
	# o que é
	var y := topo.end.y + 40
	for ln in m.linhas:
		intro._caixa(Rect2(r.position.x + 22, y - 11, 10, 10), Color(cor.lightened(0.3), 0.95), 5)
		intro._texto_cartoon(Vector2(r.position.x + 40, y), ln, 17, Color("eef0ff"), intro.f_texto, 1.2, false)
		y += 42
	# botão
	var b := Rect2(r.position.x + 24, r.end.y - 76, r.size.x - 48, 56)
	intro._caixa(Rect2(b.position + Vector2(0, 5), b.size).grow(2), intro.CONTORNO, 18)
	intro._caixa(b.grow(2), intro.CONTORNO, 18)
	intro._botao_degrade(b, cor.lightened(0.45), cor.lightened(0.05), cor.darkened(0.35), 16)
	intro._texto_cartoon(Vector2(b.get_center().x, b.position.y + 39), "Jogar", 28, Color.WHITE, intro.f_titulo, 1.8, true)

## Troféu girando de leve entre os dois brasões (o campeonato).
func _ilustra_campeonato(c: Vector2) -> void:
	var pul := 0.5 + 0.5 * sin(_relogio * 2.5)
	for k in 6:
		var a := _relogio * 0.6 + k * TAU / 6.0
		draw_colored_polygon(PackedVector2Array([c + Vector2(cos(a), sin(a)) * 18, c + Vector2(cos(a + 0.25), sin(a + 0.25)) * 70,
			c + Vector2(cos(a - 0.25), sin(a - 0.25)) * 70]), Color(1, 0.9, 0.5, 0.12 + 0.06 * pul))
	intro._brasao("heroes", c + Vector2(-95, 6), 46.0)
	intro._brasao("monsters", c + Vector2(95, 6), 46.0)
	intro._trofeu(c + Vector2(0, -4), 86.0 + pul * 5.0)

## Duas espadas cruzadas com brasões dos dois lados.
func _ilustra_batalha(c: Vector2) -> void:
	intro._brasao("heroes", c + Vector2(-95, 0), 58.0)
	intro._brasao("monsters", c + Vector2(95, 0), 58.0)
	intro._icone("espadas", c, 74, Color.WHITE, Color(0, 0, 0, 0.35))
	for s: float in [-1.0, 1.0]:
		var x := c.x + s * 54.0
		draw_line(Vector2(x - s * 6, c.y - 8), Vector2(x + s * 10, c.y - 8), Color(1, 1, 1, 0.7), 3.0, true)
		draw_line(Vector2(x - s * 6, c.y + 8), Vector2(x + s * 10, c.y + 8), Color(1, 1, 1, 0.7), 3.0, true)

## Escudo grande (defesa) à esquerda, setas de ataque chegando da direita e o "troca" no meio.
func _ilustra_cerco(c: Vector2) -> void:
	var pul := 0.5 + 0.5 * sin(_relogio * 3.0)
	intro._escudo(c + Vector2(-90, 0), 36.0 + pul * 2.0, Color("ffd34d"))
	intro._brasao("monsters", c + Vector2(95, 0), 54.0)
	for k in 3:
		var y := c.y - 22 + k * 22
		var x0 := c.x + 50 - fmod(_relogio * 50.0 + k * 20.0, 50.0)
		draw_line(Vector2(x0, y), Vector2(x0 - 46, y), Color(1, 1, 1, 0.85), 4.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(x0 - 54, y), Vector2(x0 - 42, y - 7), Vector2(x0 - 42, y + 7)]), Color(1, 1, 1, 0.9))
