extends Control
## REPLAYS (36_replays.sql): as batalhas online das últimas 24 horas — as SUAS e as dos seus AMIGOS.
## Tocar em ASSISTIR abre a partida de novo, igualzinha (a arena roda a "receita": semente + jogadas).
## Depois de 24 horas o replay some sozinho.

const PALCO := Vector2(1280, 720)
const CONTORNO := Color("120c04")
const OURO := Color("f6c343")
const COR_NOME := {"heroes": Color("ffa23a"), "monsters": Color("7ee04a")}   ## Heroes laranja / Monsters verde
const POR_PAGINA := 5

var f_titulo: Font
var f_texto: Font
var lista: Array = []
var estado := "carregando"                   ## carregando / ok / vazio / erro / abrindo
var erro := ""
var pagina := 0
var _relogio := 0.0
var _apertado := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	f_titulo = load("res://assets/Fontes/lilita-one-latin-400-normal.woff2")
	f_texto = load("res://assets/Fontes/fredoka-latin-700-normal.woff2")
	Conta.estou("replays")
	_carregar()

func _carregar() -> void:
	estado = "carregando"
	if not Conta.logado():
		estado = "erro"
		erro = "Entre com a sua conta para ver os replays."
		return
	var r: Dictionary = await Conta.chamar("listar_replays")
	if not is_inside_tree():
		return
	if not r.ok or not (r.dados is Array):
		estado = "erro"
		erro = "Não deu para carregar. Confira a internet."
		return
	lista = r.dados
	pagina = 0
	estado = "vazio" if lista.is_empty() else "ok"

func _process(dt: float) -> void:
	_relogio += dt
	queue_redraw()

# ------------------------------------------------------------------ toques
func _O() -> Vector2:
	return (size - PALCO) / 2.0

func _rets() -> Dictionary:
	var r := {"voltar": Rect2(18, 14, 150, 50)}
	if estado == "ok":
		for i in _da_pagina().size():
			r["ver%d" % i] = _ret_ver(i)
		if pagina > 0:
			r["ant"] = Rect2(PALCO.x / 2.0 - 190, 650, 170, 48)
		if (pagina + 1) * POR_PAGINA < lista.size():
			r["prox"] = Rect2(PALCO.x / 2.0 + 20, 650, 170, 48)
	return r

func _gui_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton) or ev.button_index != MOUSE_BUTTON_LEFT:
		return
	var p: Vector2 = get_local_mouse_position() - _O()
	var b := ""
	var r := _rets()
	for k in r:
		if r[k].has_point(p):
			b = k
	if ev.pressed:
		_apertado = b
	else:
		if b != "" and b == _apertado:
			_tocar(b)
		_apertado = ""
	accept_event()

func _tocar(b: String) -> void:
	Sons.tocar("Jogo/som/clique", 0.6)
	if b == "voltar":
		_voltar()
	elif b == "ant":
		pagina -= 1
	elif b == "prox":
		pagina += 1
	elif b.begins_with("ver") and estado == "ok":
		_assistir(_da_pagina()[int(b.substr(3))])

func _unhandled_key_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel"):
		_voltar()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_voltar()

func _voltar() -> void:
	get_tree().change_scene_to_file("res://cenas/sala_entrada.tscn")

func _assistir(item: Dictionary) -> void:
	estado = "abrindo"
	var r: Dictionary = await Conta.chamar("ver_replay", {"p_sala": str(item.get("sala", ""))})
	if not is_inside_tree():
		return
	if not r.ok or not (r.dados is Dictionary):
		estado = "erro"
		erro = "Esse replay não existe mais (some depois de 24 horas)."
		return
	var d: Dictionary = r.dados
	d["lado_ver"] = str(item.get("lado_ver", "heroes"))
	Perfil.pvp_replay = d
	Perfil.pvp_sala = {}
	get_tree().change_scene_to_file("res://cenas/pvp.tscn")

func _da_pagina() -> Array:
	return lista.slice(pagina * POR_PAGINA, mini(lista.size(), (pagina + 1) * POR_PAGINA))

func _ret_linha(i: int) -> Rect2:
	return Rect2(150, 150 + i * 96, 980, 82)

func _ret_ver(i: int) -> Rect2:
	var l := _ret_linha(i)
	return Rect2(l.end.x - 200, l.position.y + 16, 180, 50)

# ------------------------------------------------------------------ desenho
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("10142e"))
	for i in 10:                                       # brilho de fundo
		var c := Vector2(size.x * (0.1 + 0.09 * i), size.y * (0.5 + 0.3 * sin(_relogio * 0.4 + i)))
		draw_circle(c, 120, Color(0.25, 0.3, 0.7, 0.04))
	draw_set_transform(_O())
	_botao(Rect2(18, 14, 150, 50), "← VOLTAR", Color("4a5fae"), _apertado == "voltar")
	_texto(Vector2(PALCO.x / 2.0, 66), "▶ REPLAYS", 46, OURO, 7)
	_texto(Vector2(PALCO.x / 2.0, 104), "Suas batalhas e as dos seus amigos · somem depois de 24 horas", 18, Color(1, 1, 1, 0.75), 3)
	match estado:
		"carregando":
			_texto(Vector2(PALCO.x / 2.0, 360), "Carregando...", 28, Color.WHITE, 5)
		"abrindo":
			_texto(Vector2(PALCO.x / 2.0, 360), "Abrindo o replay...", 28, Color.WHITE, 5)
		"erro":
			_texto(Vector2(PALCO.x / 2.0, 360), erro, 24, Color("ff9a8a"), 5)
		"vazio":
			_texto(Vector2(PALCO.x / 2.0, 340), "Nenhuma batalha nas últimas 24 horas.", 26, Color.WHITE, 5)
			_texto(Vector2(PALCO.x / 2.0, 380), "Jogue online ou chame seus amigos para jogar!", 19, Color(1, 1, 1, 0.7), 3)
		"ok":
			var itens := _da_pagina()
			for i in itens.size():
				_linha(i, itens[i])
			if pagina > 0:
				_botao(Rect2(PALCO.x / 2.0 - 190, 650, 170, 48), "▲ Anteriores", Color("4a5fae"), _apertado == "ant", 18)
			if (pagina + 1) * POR_PAGINA < lista.size():
				_botao(Rect2(PALCO.x / 2.0 + 20, 650, 170, 48), "Mais ▼", Color("4a5fae"), _apertado == "prox", 18)
	draw_set_transform(Vector2.ZERO)

func _linha(i: int, it: Dictionary) -> void:
	var r := _ret_linha(i)
	_caixa(Rect2(r.position + Vector2(0, 5), r.size), Color(0, 0, 0, 0.4), 20)
	_caixa(r.grow(3), CONTORNO, 22)
	_caixa(r, Color("2a3570"), 20)
	_caixa(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)), Color("33418a"), 20)
	var nh := str(it.get("nome_heroes", "?"))
	var nm := str(it.get("nome_monsters", "?"))
	var v := str(it.get("vencedor", ""))
	var x := r.position.x + 28
	var y := r.position.y + 38
	x = _texto_esq(Vector2(x, y), ("👑 " if v == "heroes" else "") + nh, 26, COR_NOME.heroes)
	x = _texto_esq(Vector2(x + 14, y), "x", 22, Color.WHITE)
	_texto_esq(Vector2(x + 14, y), ("👑 " if v == "monsters" else "") + nm, 26, COR_NOME.monsters)
	var modo := "Cerco" if str(it.get("modo", "normal")) == "cerco" else "Batalha"
	var horas := maxi(1, ceili(float(it.get("some_em", 0)) / 3600.0))
	var info := "%s · %s · some em %dh" % [modo, "sua batalha" if it.get("minha", false) == true else "de um amigo", horas]
	_texto_esq(Vector2(r.position.x + 28, r.position.y + 68), info, 16, Color(1, 1, 1, 0.65))
	_botao(_ret_ver(i), "▶ ASSISTIR", Color("2fa84f"), _apertado == "ver%d" % i, 20)

func _botao(r: Rect2, txt: String, cor: Color, apertado := false, tam := 20) -> void:
	var rr := r
	if apertado:
		rr.position.y += 3
	_caixa(Rect2(r.position + Vector2(0, 5), r.size), Color(0, 0, 0, 0.45), 16)
	_caixa(rr.grow(3), CONTORNO, 16)
	_caixa(rr, cor.darkened(0.25), 14)
	_caixa(Rect2(rr.position, Vector2(rr.size.x, rr.size.y * 0.52)), cor.lightened(0.12), 14)
	_texto(Vector2(rr.get_center().x, rr.position.y + rr.size.y * 0.5 + tam * 0.38), txt, tam, Color.WHITE, 4)

func _caixa(r: Rect2, cor: Color, raio: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = cor
	sb.set_corner_radius_all(raio)
	sb.anti_aliasing = true
	draw_style_box(sb, r)

func _texto(pos: Vector2, txt: String, tam: int, cor: Color, contorno := 5) -> void:
	var w := f_titulo.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	_texto_esq(Vector2(pos.x - w / 2.0, pos.y), txt, tam, cor, contorno)

## Escreve a partir de pos (esquerda) e devolve onde o texto terminou.
func _texto_esq(pos: Vector2, txt: String, tam: int, cor: Color, contorno := 5) -> float:
	draw_string_outline(f_titulo, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, contorno, CONTORNO)
	draw_string(f_titulo, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)
	return pos.x + f_titulo.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
