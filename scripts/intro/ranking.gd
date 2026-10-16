extends Control
## RANKING E LIGAS (janela do menu). Igual ao site, mais caprichado:
## - abas Vitórias / Troféus / Ligas e período Hoje / Semana / Mês
## - PÓDIO com os 3 primeiros (1º no meio, mais alto, com coroa e luz girando)
## - embaixo do pódio, a LISTA do 4º lugar em diante (arrasta para rolar); a sua linha fica destacada
##   e, se você estiver fora da lista, ela fica presa embaixo
## - Ligas: as 8 ligas lado a lado (arrasta / setas) e a barra até a próxima
## Dados: função "ranking(p_periodo, p_tipo, p_limite)" do supabase/2_ranking.sql (funciona até sem conta).
## Desenha com os ajudantes da intro (mesmo estilo cartoon dos outros painéis).

const JANELA := Rect2(100, 40, 1080, 650)
const LISTA := Rect2(150, 414, 980, 220)          ## área que rola (do 4º em diante)
const LINHA_H := 54.0
const TIPOS := [["vitorias", "Vitórias"], ["trofeus", "Troféus"], ["campanha", "Campanha"], ["ligas", "Ligas"]]
## Campanha: recorde de cada dificuldade (supabase/13_recorde_campanha.sql, função ranking_campanha).
const DIFS := [["facil", "Fácil"], ["medio", "Médio"], ["dificil", "Difícil"], ["hardcore", "HardCore"]]
const PERIODOS := [["dia", "Hoje"], ["semana", "Semana"], ["mes", "Mês"]]
const CORES_LUGAR := {1: [Color("fff1a8"), Color("f6c343"), Color("a8680c")],
	2: [Color("f4f7fb"), Color("b9c3d3"), Color("5f6b80")],
	3: [Color("ffd0a0"), Color("d98b4a"), Color("7a4116")]}

var intro: Node                                    # a intro (dona dos ajudantes de desenho e das fontes)
var tipo := "vitorias"
var periodo := "dia"
var dif_rank := "medio"                          # aba Campanha: qual dificuldade
var estado := ""                                   # carregando / ok / erro
var erro_msg := ""
var linhas: Array = []                             # [{posicao, nome, avatar_url, valor, trofeus, eu}]
var _pedido := 0
var _cache := {}                                   # "tipo|periodo" -> {linhas, t}
var _abre := 0.0                                   # animação de abrir (0..1)
var _troca := 0.0                                  # animação ao trocar de aba (0..1)
var _rolagem := 0.0
var _rolagem_alvo := 0.0
var _arrasto := {}                                 # {y0, r0, x0, moveu}
var _liga_rol := 0.0                               # carrossel das ligas
var _liga_alvo := 0.0
var _fotos := {}                                   # url -> Texture2D (null = baixando)
var _lista: Control                                # área que rola (corta o que passa da borda)
var _relogio := 0.0
var _foto_conta: Texture2D
var _foto_conta_de: Texture2D

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # (ocupa a tela toda: senão os toques não chegam)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_lista = Control.new()
	_lista.clip_contents = true
	_lista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lista.draw.connect(_desenhar_lista)
	add_child(_lista)

func abrir(qual := "") -> void:
	_quadro_abriu = Engine.get_process_frames()       # (o mesmo toque que abriu não pode fechar)
	if qual != "":
		tipo = qual
	if Perfil.dificuldade in ["facil", "medio", "dificil", "hardcore"]:
		dif_rank = Perfil.dificuldade
	visible = true
	_abre = 0.0
	_arrasto = {}
	_rolagem = 0.0
	_rolagem_alvo = 0.0
	_carregar()

func fechar() -> void:
	visible = false
	_arrasto = {}

# =================================================================== DADOS
func _carregar() -> void:
	_troca = 0.0
	_rolagem = 0.0
	_rolagem_alvo = 0.0
	if tipo == "ligas":
		var idx := _indice_liga(Perfil.trofeus)
		_liga_alvo = clampf(idx * 168.0 - 300.0, 0.0, _liga_max())
		_liga_rol = _liga_alvo
		return
	var chave := tipo + "|" + (dif_rank if tipo == "campanha" else periodo)
	if tipo == "campanha":
		chave += "|" + (Perfil.lado if Perfil.lado in ["heroes", "monsters"] else "heroes")
	var c: Dictionary = _cache.get(chave, {})
	if not c.is_empty() and Time.get_ticks_msec() - int(c.t) < 30000:
		linhas = c.linhas
		estado = "ok"
		_rolar_para_mim()
		return
	_pedido += 1
	var meu := _pedido
	estado = "carregando"
	linhas = []
	var conta := get_node_or_null("/root/Conta")
	if conta == null:
		estado = "erro"
		erro_msg = "sem conta"
		return
	var r: Dictionary
	if tipo == "campanha":
		r = await conta.chamar("ranking_campanha", {"p_dificuldade": dif_rank, "p_limite": 100,
			"p_lado": Perfil.lado if Perfil.lado in ["heroes", "monsters"] else "heroes"})   # (24_recorde_por_lado.sql)
	else:
		r = await conta.chamar("ranking", {"p_periodo": periodo, "p_tipo": tipo, "p_limite": 100})
	if meu != _pedido or not is_inside_tree():
		return                                     # trocou de aba enquanto carregava
	if not r.ok or not (r.dados is Array):
		estado = "erro"
		erro_msg = str(r.erro)
		return
	linhas = r.dados
	estado = "ok"
	_cache[chave] = {"linhas": linhas, "t": Time.get_ticks_msec()}
	for l in linhas:
		_baixar_foto(str(l.get("avatar_url", "")) if l.get("avatar_url") != null else "")
	_rolar_para_mim()

func _resto() -> Array:                            # 4º em diante (até 100)
	return linhas.filter(func(l): return int(l.posicao) > 3 and int(l.posicao) <= 100)

func _eu() -> Dictionary:
	for l in linhas:
		if (l.get("eu") == true):
			return l
	return {}

func _rolar_para_mim() -> void:
	var eu := _eu()
	if eu.is_empty() or int(eu.posicao) <= 3 or int(eu.posicao) > 100:
		return
	var i := _resto().find(eu)
	_rolagem_alvo = clampf(i * LINHA_H - LISTA.size.y / 2.0 + LINHA_H / 2.0, 0.0, _rolagem_max())

func _rolagem_max() -> float:
	var eu := _eu()
	var fixa := 1 if (not eu.is_empty() and int(eu.posicao) > 100) else 0
	return maxf(0.0, (_resto().size() + fixa) * LINHA_H - LISTA.size.y + 6.0)

func _liga_max() -> float:
	return maxf(0.0, Perfil.LIGAS.size() * 168.0 - 12.0 - (JANELA.size.x - 140.0))

static func _indice_liga(t: int) -> int:
	var idx := 0
	for i in Perfil.LIGAS.size():
		if t >= int(Perfil.LIGAS[i].min):
			idx = i
	return idx

## Foto do Google: baixa uma vez e recorta redonda.
func _baixar_foto(url: String) -> void:
	if not url.begins_with("https://") or _fotos.has(url):
		return
	_fotos[url] = null
	var h := HTTPRequest.new()
	add_child(h)
	h.request(url)
	var res: Array = await h.request_completed
	h.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return
	var img := Image.new()
	var b: PackedByteArray = res[3]
	if img.load_jpg_from_buffer(b) != OK and img.load_png_from_buffer(b) != OK and img.load_webp_from_buffer(b) != OK:
		return
	_fotos[url] = _redonda(img)

static func _redonda(img: Image) -> Texture2D:
	var t := 96
	img.convert(Image.FORMAT_RGBA8)
	var lado := mini(img.get_width(), img.get_height())
	img = img.get_region(Rect2i((img.get_width() - lado) / 2, (img.get_height() - lado) / 2, lado, lado))
	img.resize(t, t, Image.INTERPOLATE_LANCZOS)
	var c := (t - 1) / 2.0
	for y in t:
		for x in t:
			var d := Vector2(x - c, y - c).length()
			if d > c - 1.0:
				var px := img.get_pixel(x, y)
				px.a *= clampf(c - d, 0.0, 1.0)
				img.set_pixel(x, y, px)
	return ImageTexture.create_from_image(img)

# =================================================================== QUADRO
func _process(dt: float) -> void:
	if not visible:
		return
	_relogio += dt
	_abre = move_toward(_abre, 1.0, dt * 4.0)
	_troca = move_toward(_troca, 1.0, dt * 2.5)
	if _arrasto.is_empty():
		_rolagem_alvo = clampf(_rolagem_alvo, 0.0, _rolagem_max())
		_liga_alvo = clampf(_liga_alvo, 0.0, _liga_max())
	_rolagem = lerpf(_rolagem, _rolagem_alvo, minf(1.0, dt * 14.0))
	_liga_rol = lerpf(_liga_rol, _liga_alvo, minf(1.0, dt * 12.0))
	var O: Vector2 = intro.O
	_lista.position = O + LISTA.position
	_lista.size = LISTA.size
	_lista.visible = tipo != "ligas" and estado == "ok"
	queue_redraw()
	_lista.queue_redraw()

# =================================================================== TOQUES
func _ret_aba(grupo: int, i: int) -> Rect2:
	if grupo == 0:
		return Rect2(JANELA.position.x + 214 + i * 104, JANELA.position.y + 38, 98, 48)
	if tipo == "campanha":
		return Rect2(JANELA.position.x + 640 + i * 86, JANELA.position.y + 38, 80, 48)
	return Rect2(JANELA.position.x + 650 + i * 104, JANELA.position.y + 38, 98, 48)

## Abas da direita: período (Hoje/Semana/Mês) ou, na Campanha, a dificuldade.
func _grupo1() -> Array:
	return DIFS if tipo == "campanha" else PERIODOS

func _valor1() -> String:
	return dif_rank if tipo == "campanha" else periodo

func _ret_fechar() -> Rect2:
	return Rect2(JANELA.end.x - 92, JANELA.position.y + 30, 64, 60)

func _ret_seta_liga(dir: int) -> Rect2:
	var y := JANELA.position.y + 250.0
	return Rect2(JANELA.position.x + 34, y, 48, 48) if dir < 0 else Rect2(JANELA.end.x - 82, y, 48, 48)

var _quadro_abriu := -1

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and Engine.get_process_frames() == _quadro_abriu:
		accept_event()
		return
	var O: Vector2 = intro.O
	if ev is InputEventMouseButton:
		var p: Vector2 = ev.position - O
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if ev.pressed:
				var d := -1.0 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
				if tipo == "ligas":
					_liga_alvo += d * 168.0
				else:
					_rolagem_alvo += d * LINHA_H
			accept_event()
			return
		if ev.button_index != MOUSE_BUTTON_LEFT:
			return
		if ev.pressed:
			_arrasto = {"y0": p.y, "x0": p.x, "r0": _rolagem_alvo, "l0": _liga_alvo, "moveu": false,
				"lista": LISTA.has_point(p), "ligas": tipo == "ligas" and Rect2(JANELA.position.x + 30, JANELA.position.y + 110, JANELA.size.x - 60, 300).has_point(p)}
		else:
			if _arrasto.is_empty():
				return                                  # (o toque começou fora: ex. o mesmo toque que abriu a janela)
			var moveu: bool = _arrasto.get("moveu", false)
			_arrasto = {}
			if not moveu:
				_tocar(p)
		accept_event()
	elif ev is InputEventMouseMotion and not _arrasto.is_empty():
		var p2: Vector2 = ev.position - O
		var dy: float = p2.y - _arrasto.y0
		var dx: float = p2.x - _arrasto.x0
		if absf(dy) > 8.0 or absf(dx) > 8.0:
			_arrasto.moveu = true
		if _arrasto.lista:
			_rolagem_alvo = clampf(_arrasto.r0 - dy, -40.0, _rolagem_max() + 40.0)
			_rolagem = _rolagem_alvo
		elif _arrasto.ligas:
			_liga_alvo = clampf(_arrasto.l0 - dx, -60.0, _liga_max() + 60.0)
			_liga_rol = _liga_alvo
		accept_event()

func _tocar(p: Vector2) -> void:
	if _ret_fechar().grow(6).has_point(p) or not JANELA.grow(10).has_point(p):
		intro._clique(false)
		fechar()
		return
	for i in TIPOS.size():
		if _ret_aba(0, i).has_point(p) and tipo != TIPOS[i][0]:
			intro._clique(false)
			tipo = TIPOS[i][0]
			_carregar()
			return
	if tipo != "ligas":
		var g1 := _grupo1()
		for i in g1.size():
			if _ret_aba(1, i).has_point(p) and _valor1() != g1[i][0]:
				intro._clique(false)
				if tipo == "campanha":
					dif_rank = g1[i][0]
				else:
					periodo = g1[i][0]
				_carregar()
				return
	else:
		if _ret_seta_liga(-1).has_point(p):
			_liga_alvo -= 336.0
			intro._clique(false)
		elif _ret_seta_liga(1).has_point(p):
			_liga_alvo += 336.0
			intro._clique(false)

# =================================================================== DESENHO
func _draw() -> void:
	intro._ci = self
	var O: Vector2 = intro.O
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.05, 0.62 * _abre))
	var k := 0.92 + 0.08 * _ease(_abre)
	var c := O + JANELA.get_center()
	draw_set_transform(c - JANELA.get_center() * k, 0.0, Vector2(k, k))
	_desenhar_janela()
	match tipo:
		"ligas": _desenhar_ligas()
		_: _desenhar_ranking()
	_desenhar_abas()                                 # (por cima da luz do pódio)
	draw_set_transform(Vector2.ZERO)
	_lista.modulate.a = _abre

static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

static func _ease_back(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)

func _desenhar_janela() -> void:
	var j := JANELA
	var NAVY: Color = intro.NAVY
	# moldura dourada grossa (igual ao site) + painel azul
	intro._caixa(Rect2(j.position + Vector2(0, 12), j.size).grow(10), Color(0, 0, 0, 0.45), 40, 0, Color(), 24, Vector2(0, 10), Color(0, 0, 0, 0.5))
	intro._caixa(j.grow(10), Color("4a2a06"), 38)
	intro._caixa(j.grow(8), Color("b8740f"), 36)
	intro._caixa(Rect2(j.position.x - 8, j.position.y - 8, j.size.x + 16, j.size.y * 0.5), Color("f6c343"), 36)
	intro._caixa(j.grow(3), NAVY, 31)
	intro._painel(j, Color("3e4f96"), Color("1f2754"), 29)
	# luz de dentro
	intro._degrade(Rect2(j.position.x + 20, j.position.y + 6, j.size.x - 40, 70), Color(1, 1, 1, 0.08), Color(1, 1, 1, 0))
	intro._texto_cartoon(Vector2(j.position.x + 40, j.position.y + 78), "Ranking", 44, Color("ffd34d"), intro.f_titulo, 2.5, false)
	# fechar
	var f := _ret_fechar()
	intro._caixa(Rect2(f.position + Vector2(0, 5), f.size).grow(3), NAVY, 18)
	intro._caixa(f.grow(3), NAVY, 18)
	intro._botao_degrade(f, Color("7f95e6"), Color("4a5fae"), Color("2c3874"), 16)
	var fc := f.get_center()
	for s in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(fc - s * 11, fc + s * 11, intro.CONTORNO, 7.0, true)
		draw_line(fc - s * 11, fc + s * 11, Color.WHITE, 4.0, true)

func _desenhar_abas() -> void:
	for grupo in 2:
		var lista: Array = TIPOS if grupo == 0 else _grupo1()
		var a := _ret_aba(grupo, 0)
		var b := _ret_aba(grupo, lista.size() - 1)
		var fundo := Rect2(a.position - Vector2(8, 7), Vector2(b.end.x - a.position.x + 16, a.size.y + 14))
		intro._caixa(fundo, Color(0.05, 0.06, 0.14, 0.7), 22)
		var desligado := grupo == 1 and tipo == "ligas"
		for i in lista.size():
			var r := _ret_aba(grupo, i)
			var on: bool = (tipo if grupo == 0 else _valor1()) == lista[i][0]
			if on and not desligado:
				intro._caixa(Rect2(r.position + Vector2(0, 4), r.size).grow(2), Color("4a2a06"), 17)
				intro._caixa(r.grow(2), Color("4a2a06"), 17)
				intro._botao_degrade(r, Color("ffe98a"), Color("ffc43a"), Color("c97a0c"), 15)
			else:
				intro._caixa(Rect2(r.position + Vector2(0, 4), r.size), Color(0.03, 0.04, 0.1, 0.6), 15)
				intro._botao_degrade(r, Color("5d6fb8"), Color("3d4c8f"), Color("2a356b"), 15)
			var cor := Color(1, 1, 1, 0.35) if desligado else Color.WHITE
			intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 33), lista[i][1], (17 if (grupo == 1 and tipo == "campanha") else 20), cor, intro.f_titulo, 1.5, true)

# ------------------------------------------------------------------- vitórias / troféus
func _unidade() -> String:
	if tipo == "campanha":
		return "nível"
	return "vitórias" if tipo == "vitorias" else "troféus"

func _per() -> String:
	if tipo == "campanha":
		for d in DIFS:
			if d[0] == dif_rank:
				return "no " + str(d[1])
	return {"dia": "hoje", "semana": "nesta semana", "mes": "neste mês"}[periodo]

func _desenhar_ranking() -> void:
	var j := JANELA
	var cx := j.get_center().x
	var conta := get_node_or_null("/root/Conta")
	var logado: bool = conta != null and conta.logado()
	if estado == "carregando":
		var cc := Vector2(cx, j.position.y + 320)
		draw_arc(cc, 30, 0, TAU, 40, Color(1, 1, 1, 0.12), 8, true)
		draw_arc(cc, 30, _relogio * 5.0, _relogio * 5.0 + 4.2, 32, intro.OURO2, 8, true)
		intro._texto_cartoon(Vector2(cx, cc.y + 70), "Carregando o ranking...", 22, intro.CREME, intro.f_texto, 1.5, true)
		return
	if estado == "erro":
		intro._texto_cartoon(Vector2(cx, j.position.y + 300), "Não deu para carregar o ranking agora.", 24, intro.CREME, intro.f_titulo, 2.0, true)
		intro._texto_cartoon(Vector2(cx, j.position.y + 340), "Confira a internet e abra de novo.", 18, Color("c9d2ff"), intro.f_texto, 1.5, true)
		return
	_desenhar_podio()
	# nota de baixo
	var eu := _eu()
	var verbo := "venceu" if tipo == "vitorias" else ("chegou longe" if tipo == "campanha" else "ganhou troféus")
	var nota := "Quem mais %s %s (horário de Brasília)." % [verbo, _per()]
	if tipo == "campanha":
		nota = "Quem chegou mais longe na campanha %s." % _per()
	if not eu.is_empty():
		nota += " Você está em %dº lugar." % int(eu.posicao)
	elif logado:
		nota += " Você ainda não %s %s." % [verbo, _per()]
	else:
		nota += " Entre com o Google para aparecer no ranking."
	intro._texto_cartoon(Vector2(cx, j.end.y - 18), nota, 16, Color("dfe4ff"), intro.f_texto, 1.2, true)
	if linhas.is_empty():
		intro._texto_cartoon(Vector2(cx, LISTA.position.y + 70), "Ninguém %s %s ainda." % [verbo, _per()], 22, intro.CREME, intro.f_titulo, 1.8, true)
		intro._texto_cartoon(Vector2(cx, LISTA.position.y + 108), "Seja o primeiro!", 26, Color("ffd34d"), intro.f_titulo, 2.0, true)
	elif _resto().is_empty() and (eu.is_empty() or int(eu.posicao) <= 100):
		intro._texto_cartoon(Vector2(cx, LISTA.position.y + 90), "Só 3 jogadores %s. Jogue e entre na lista!" % _per(), 18, Color("c9d2ff"), intro.f_texto, 1.4, true)
	else:
		# moldura da lista + "sombras" em cima e embaixo indicando que rola
		var lr := LISTA.grow(6)
		intro._caixa(lr, Color(0.04, 0.05, 0.12, 0.45), 18)
		if _rolagem_max() > 1.0:
			var k := clampf(_rolagem / maxf(1.0, _rolagem_max()), 0.0, 1.0)
			var trilho := Rect2(lr.end.x - 9, lr.position.y + 10, 5, lr.size.y - 20)
			intro._caixa(trilho, Color(1, 1, 1, 0.08), 3)
			var alt := maxf(30.0, trilho.size.y * LISTA.size.y / (LISTA.size.y + _rolagem_max()))
			intro._caixa(Rect2(trilho.position.x, trilho.position.y + (trilho.size.y - alt) * k, 5, alt), Color(1, 0.83, 0.3, 0.8), 3)

## PÓDIO: 2º, 1º (no meio, mais alto) e 3º.
func _desenhar_podio() -> void:
	var cx := JANELA.get_center().x
	var base := LISTA.position.y - 16.0
	var cols := {1: cx, 2: cx - 250.0, 3: cx + 250.0}
	var alturas := {1: 94.0, 2: 72.0, 3: 56.0}
	var larg := {1: 230.0, 2: 210.0, 3: 210.0}
	# luz girando atrás do 1º
	var c1 := Vector2(cx, base - alturas[1] - 70.0)
	for i in 12:
		var a := _relogio * 0.35 + i * TAU / 12.0
		var p := PackedVector2Array([c1, c1 + Vector2(cos(a - 0.09), sin(a - 0.09)) * 190.0, c1 + Vector2(cos(a + 0.09), sin(a + 0.09)) * 190.0])
		draw_colored_polygon(p, Color(1, 0.85, 0.35, 0.07))
	intro._elipse_degrade(c1, 150, 120, Color(1, 0.86, 0.4, 0.22), Color(1, 0.86, 0.4, 0.0))
	for lugar in [2, 3, 1]:
		var d: Dictionary = {}
		for l in linhas:
			if int(l.posicao) == lugar:
				d = l
		var entra := _ease_back(clampf(_troca * 1.6 - (0.0 if lugar == 1 else (0.15 if lugar == 2 else 0.3)), 0.0, 1.0))
		_desenhar_lugar(lugar, d, Vector2(cols[lugar], base), alturas[lugar] * entra, larg[lugar], entra)

func _desenhar_lugar(lugar: int, d: Dictionary, base: Vector2, alt: float, larg: float, entra: float) -> void:
	var cores: Array = CORES_LUGAR[lugar]
	var vago := d.is_empty()
	var eu: bool = (d.get("eu") == true)
	# bloco do pódio (frente + tampa)
	var frente := Rect2(base.x - larg / 2.0, base.y - alt, larg, alt)
	if alt > 2.0:
		var tampa := PackedVector2Array([Vector2(frente.position.x, frente.position.y), Vector2(frente.end.x, frente.position.y),
			Vector2(frente.end.x - 16, frente.position.y - 14), Vector2(frente.position.x + 16, frente.position.y - 14)])
		draw_colored_polygon(tampa, (cores[0] as Color).darkened(0.05) if not vago else Color(0.5, 0.55, 0.7, 0.35))
		intro._caixa(Rect2(frente.position + Vector2(0, 6), frente.size), Color(0, 0, 0, 0.35), 6)
		if vago:
			intro._caixa(frente, Color(0.35, 0.4, 0.6, 0.35), 6)
		else:
			intro._caixa(frente, cores[2], 6)
			intro._degrade(Rect2(frente.position + Vector2(4, 2), Vector2(frente.size.x - 8, frente.size.y * 0.55)), cores[1], (cores[1] as Color).darkened(0.15))
			intro._degrade(Rect2(frente.position + Vector2(4, 2), Vector2(frente.size.x - 8, 8)), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0))
		# número grande gravado no bloco
		var num := str(lugar)
		intro._texto(Vector2(base.x - intro._larg(intro.f_titulo, num, 64) / 2.0, frente.position.y + minf(alt, 70.0) + 4),
			num, 64, Color(1, 1, 1, 0.14 * entra), intro.f_titulo)
	if entra <= 0.01:
		return
	var a := clampf(entra, 0.0, 1.0)
	# rosto em cima do bloco
	var r := 46.0 if lugar == 1 else 38.0
	var rc := Vector2(base.x, base.y - alt - 14 - r - 34)
	if vago:
		draw_circle(rc, r, Color(0.25, 0.3, 0.5, 0.5 * a))
		draw_arc(rc, r, 0, TAU, 40, Color(1, 1, 1, 0.25 * a), 3, true)
		intro._texto_cartoon(Vector2(rc.x, rc.y + 14), "?", 40, Color(1, 1, 1, 0.4 * a), intro.f_titulo, 1.5, true)
		intro._texto_cartoon(Vector2(rc.x, base.y - alt - 22), "vago", 18, Color(1, 1, 1, 0.45 * a), intro.f_texto, 1.2, true)
		_medalha(lugar, rc + Vector2(0, -r - 4), a)
		return
	if eu:                                          # você: brilho verde em volta
		for i in 4:
			draw_circle(rc, r + 16 - i * 3, Color(0.55, 0.88, 0.24, 0.08 * a))
	draw_circle(rc + Vector2(0, 5), r + 7, Color(0, 0, 0, 0.35 * a))
	draw_circle(rc, r + 7, Color(intro.CONTORNO, a))
	intro._bola(rc, r + 5, cores[0], cores[2])
	_rosto(d, rc, r - 1, a, lugar == 1)
	if lugar == 1:
		_coroa(rc + Vector2(0, -r - 16), 1.0, a)
	_medalha(lugar, rc + Vector2(r * 0.72, -r * 0.72) if lugar == 1 else rc + Vector2(0, -r - 6), a)
	# liga pequenina
	var lg := Perfil.liga_de(int(d.get("trofeus", 0)))
	_icone_liga(lg, rc + Vector2(r * 0.78, r * 0.62), 30.0, a)
	# nome em cima da tampa e o número no bloco
	var nome := "Você" if eu else str(d.get("nome", "?"))
	intro._texto_cartoon(Vector2(base.x, base.y - alt - 24), nome, 20 if lugar == 1 else 18, Color(Color("b6ff6a") if eu else Color.WHITE, a), intro.f_titulo, 1.6, true)
	if alt > 40.0:
		var v := _milhar(int(d.get("valor", 0)))
		intro._texto_cartoon(Vector2(base.x, base.y - alt + 40), v, 30 if lugar == 1 else 26, Color(Color("fff6d0"), a), intro.f_titulo, 2.0, true)
		intro._texto_cartoon(Vector2(base.x, base.y - alt + 62), _unidade(), 14, Color(1, 1, 1, 0.9 * a), intro.f_texto, 1.2, true)

func _rosto(d: Dictionary, c: Vector2, r: float, a: float, grande := false) -> void:
	var ci: CanvasItem = intro._ci
	var url: String = str(d.get("avatar_url", "")) if d.get("avatar_url") != null else ""
	var tex: Texture2D = _fotos.get(url)
	var conta := get_node_or_null("/root/Conta")
	if tex == null and (d.get("eu") == true) and conta and conta.foto:
		if _foto_conta_de != conta.foto:             # a foto da conta é quadrada: recorta redonda uma vez
			_foto_conta_de = conta.foto
			_foto_conta = _redonda(conta.foto.get_image())
		tex = _foto_conta
	if tex:
		ci.draw_texture_rect(tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, a))
		return
	var nome := str(d.get("nome", "?"))
	var cores := [Color("2f7fd6"), Color("1fa6a0"), Color("8a5ad6"), Color("d65a7a"), Color("d6862f"), Color("4aa83a")]
	var cor: Color = cores[absi(nome.hash()) % cores.size()]
	intro._bola(c, r, cor.lightened(0.25), cor.darkened(0.2))
	var letra := nome.left(1).to_upper()
	var tam := int(r * (1.1 if grande else 1.05))
	intro._texto_cartoon(Vector2(c.x, c.y + tam * 0.36), letra, tam, Color(1, 1, 1, a), intro.f_titulo, 1.5, true)

func _coroa(c: Vector2, k: float, a: float) -> void:
	var w := 44.0 * k
	var h := 26.0 * k
	var pts := PackedVector2Array([c + Vector2(-w / 2, h / 2), c + Vector2(-w / 2, -h / 4), c + Vector2(-w / 4, h / 8), c + Vector2(0, -h / 2),
		c + Vector2(w / 4, h / 8), c + Vector2(w / 2, -h / 4), c + Vector2(w / 2, h / 2)])
	var bob := Vector2(0, sin(_relogio * 3.0) * 2.0)
	var p2 := PackedVector2Array()
	for p in pts:
		p2.append(p + bob)
	draw_colored_polygon(p2, Color("ffd34d", a))
	var fecha := p2.duplicate()
	fecha.append(p2[0])
	draw_polyline(fecha, Color(intro.CONTORNO, a), 2.5, true)
	for i in [1, 3, 5]:
		draw_circle(p2[i], 4.0 * k, Color("fff6d0", a))
	draw_circle(c + bob + Vector2(0, h * 0.18), 4.0 * k, Color("e04a4a", a))

func _medalha(lugar: int, c: Vector2, a: float) -> void:
	var cores: Array = CORES_LUGAR[lugar]
	draw_circle(c + Vector2(0, 3), 17, Color(0, 0, 0, 0.35 * a))
	draw_circle(c, 17, Color(intro.CONTORNO, a))
	intro._bola(c, 15, cores[0], cores[2])
	intro._texto_cartoon(Vector2(c.x, c.y + 8), str(lugar), 20, Color(1, 1, 1, a), intro.f_titulo, 1.2, true)

func _icone_liga(lg: Dictionary, c: Vector2, tam: float, a: float) -> void:
	var ci: CanvasItem = intro._ci
	var tex: Texture2D = intro._textura(["liga/" + str(lg.img), "liga/" + str(lg.nome), "liga/" + str(lg.nome).to_lower()])
	if tex:
		var s := tam / maxf(tex.get_width(), tex.get_height())
		var t := Vector2(tex.get_width(), tex.get_height()) * s
		ci.draw_texture_rect(tex, Rect2(c - t / 2.0, t), false, Color(1, 1, 1, a))
	else:
		intro._escudo(c, tam * 0.45, lg.cor)

static func _milhar(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## LISTA do 4º em diante (desenhada numa área que corta as bordas).
func _desenhar_lista() -> void:
	intro._ci = _lista
	var resto := _resto()
	var eu := _eu()
	var fixa := not eu.is_empty() and int(eu.posicao) > 100
	var w := LISTA.size.x - 18.0
	for i in resto.size():
		var y := i * LINHA_H - _rolagem + 2.0
		if y < -LINHA_H or y > LISTA.size.y:
			continue
		var entra := clampf(_troca * 3.0 - i * 0.12, 0.0, 1.0)
		_linha(resto[i], Rect2(Vector2(40.0 * (1.0 - _ease(entra)), y + 3), Vector2(w, LINHA_H - 8)), _ease(entra))
	if fixa:                                          # você lá embaixo (fora dos 100)
		var yf := LISTA.size.y - LINHA_H + 2
		_lista.draw_rect(Rect2(0, yf - 8, LISTA.size.x, LINHA_H + 8), Color(0.08, 0.1, 0.22, 0.95))
		_linha(eu, Rect2(Vector2(0, yf), Vector2(w, LINHA_H - 8)), 1.0)

func _linha(d: Dictionary, r: Rect2, a: float) -> void:
	var eu: bool = (d.get("eu") == true)
	var pos := int(d.posicao)
	var fundo := Color(0.22, 0.28, 0.55, 0.9) if pos % 2 == 0 else Color(0.18, 0.23, 0.48, 0.9)
	intro._caixa(Rect2(r.position + Vector2(0, 3), r.size), Color(0, 0, 0, 0.3 * a), 14)
	intro._caixa(r, Color(fundo, fundo.a * a), 14, 3 if eu else 0, Color("8be03c", a))
	intro._degrade(Rect2(r.position.x + 10, r.position.y + 2, r.size.x - 20, r.size.y * 0.35), Color(1, 1, 1, 0.07 * a), Color(1, 1, 1, 0))
	var cy := r.get_center().y
	# posição
	var pc := Vector2(r.position.x + 34, cy)
	intro._caixa(Rect2(pc - Vector2(26, 16), Vector2(52, 32)), Color(0.06, 0.07, 0.16, 0.75 * a), 16)
	intro._texto_cartoon(Vector2(pc.x, cy + 8), "%dº" % pos, 20, Color(Color("ffd34d"), a), intro.f_titulo, 1.3, true)
	# rosto e nome
	var rc := Vector2(r.position.x + 92, cy)
	draw_circle_safe(rc, 21, Color(intro.CONTORNO, a))
	_rosto(d, rc, 19, a)
	var nome := "Você" if eu else str(d.get("nome", "?"))
	intro._texto_cartoon(Vector2(r.position.x + 124, cy + 8), nome, 21, Color(Color("b6ff6a") if eu else Color.WHITE, a), intro.f_titulo, 1.4, false)
	# liga
	var lg := Perfil.liga_de(int(d.get("trofeus", 0)))
	var lx := r.position.x + r.size.x * 0.56
	_icone_liga(lg, Vector2(lx, cy), 34.0, a)
	intro._texto_cartoon(Vector2(lx + 22, cy + 7), str(lg.nome), 17, Color((lg.cor as Color).lightened(0.3), a), intro.f_texto, 1.2, false)
	# valor
	var v := ("Nível %s" % _milhar(int(d.get("valor", 0)))) if tipo == "campanha" else "%s %s" % [_milhar(int(d.get("valor", 0))), _unidade()]
	intro._texto_cartoon(Vector2(r.end.x - 20 - intro._larg(intro.f_titulo, v, 21), cy + 8), v, 21, Color(Color("fff6d0"), a), intro.f_titulo, 1.4, false)

func draw_circle_safe(c: Vector2, r: float, cor: Color) -> void:
	intro._ci.draw_circle(c, r, cor)

# ------------------------------------------------------------------- ligas
func _desenhar_ligas() -> void:
	var j := JANELA
	var idx := _indice_liga(Perfil.trofeus)
	var area := Rect2(j.position.x + 70, j.position.y + 120, j.size.x - 140, 290)
	var x0 := area.position.x - _liga_rol
	for i in Perfil.LIGAS.size():
		var lg: Dictionary = Perfil.LIGAS[i]
		var r := Rect2(x0 + i * 168.0, area.position.y + 10, 156, 270)
		if r.end.x < area.position.x - 20 or r.position.x > area.end.x + 20:
			continue
		var borda := 0.0
		if r.position.x < area.position.x:
			borda = (area.position.x - r.position.x) / r.size.x
		elif r.end.x > area.end.x:
			borda = (r.end.x - area.end.x) / r.size.x
		var a := clampf(1.0 - borda * 1.6, 0.0, 1.0)
		if a <= 0.0:
			continue
		var atual := i == idx
		var alcancada := i < idx
		var entra := _ease_back(clampf(_troca * 2.2 - absf(i - idx) * 0.12, 0.0, 1.0))
		var rr := Rect2(r.position + Vector2(0, (1.0 - entra) * 30.0), r.size)
		if atual:                                    # liga atual: brilho e borda dourada pulsando
			var pul := 0.5 + 0.5 * sin(_relogio * 3.0)
			intro._caixa(rr.grow(10), Color(1, 0.83, 0.3, (0.12 + 0.1 * pul) * a), 26)
		intro._caixa(Rect2(rr.position + Vector2(0, 6), rr.size), Color(0, 0, 0, 0.3 * a), 20)
		intro._caixa(rr, Color(0.13, 0.16, 0.36, 0.95 * a) if (atual or alcancada) else Color(0.1, 0.12, 0.26, 0.8 * a), 20,
			4 if atual else 2, Color("f6c343", a) if atual else Color(1, 1, 1, 0.08 * a))
		var tex: Texture2D = intro._textura(["liga/" + str(lg.img), "liga/" + str(lg.nome), "liga/" + str(lg.nome).to_lower()])
		var ic := Vector2(rr.get_center().x, rr.position.y + 92 + (sin(_relogio * 2.0 + i) * 3.0 if atual else 0.0))
		var apagada := 1.0 if (atual or alcancada) else 0.45
		if tex:
			var s := 130.0 / maxf(tex.get_width(), tex.get_height())
			var t := Vector2(tex.get_width(), tex.get_height()) * s
			draw_texture_rect(tex, Rect2(ic - t / 2.0 + Vector2(0, 5), t), false, Color(0, 0, 0, 0.35 * a))
			draw_texture_rect(tex, Rect2(ic - t / 2.0, t), false, Color(apagada, apagada, apagada, a))
		else:
			intro._escudo(ic, 50.0, lg.cor)
		var prox: Dictionary = Perfil.LIGAS[i + 1] if i + 1 < Perfil.LIGAS.size() else {}
		var faixa := ("%d a %d" % [int(lg.min), int(prox.min) - 1]) if not prox.is_empty() else ("%d ou mais" % int(lg.min))
		intro._texto_cartoon(Vector2(rr.get_center().x, rr.position.y + 188), str(lg.nome), 22, Color(Color("ffd34d") if atual else Color.WHITE, a * (1.0 if atual or alcancada else 0.6)), intro.f_titulo, 1.6, true)
		intro._texto_cartoon(Vector2(rr.get_center().x, rr.position.y + 214), faixa, 16, Color(1, 1, 1, 0.85 * a * apagada), intro.f_texto, 1.2, true)
		intro._texto_cartoon(Vector2(rr.get_center().x, rr.position.y + 236), "troféus", 14, Color(1, 1, 1, 0.7 * a * apagada), intro.f_texto, 1.0, true)
		if atual:
			var tag := Rect2(rr.get_center().x - 40, rr.end.y - 22, 80, 28)
			intro._caixa(tag.grow(2), intro.CONTORNO, 14)
			intro._botao_degrade(tag, Color("b6ff6a"), Color("8be03c"), Color("4a9e1f"), 12)
			intro._texto_cartoon(Vector2(tag.get_center().x, tag.position.y + 20), "VOCÊ", 16, Color.WHITE, intro.f_titulo, 1.2, true)
		elif alcancada:
			var ck := Vector2(rr.end.x - 24, rr.position.y + 24)
			draw_circle(ck, 13, intro.CONTORNO)
			draw_circle(ck, 11, Color("8be03c"))
			draw_polyline(PackedVector2Array([ck + Vector2(-5, 0), ck + Vector2(-1, 4), ck + Vector2(6, -4)]), Color.WHITE, 2.6, true)
	# setas
	for dir in [-1, 1]:
		var pode := (_liga_alvo > 4.0) if dir < 0 else (_liga_alvo < _liga_max() - 4.0)
		if not pode:
			continue
		var s := _ret_seta_liga(dir)
		var sc := s.get_center()
		draw_circle(sc + Vector2(0, 4), 25, Color(0, 0, 0, 0.35))
		draw_circle(sc, 25, intro.CONTORNO)
		intro._bola(sc, 22, Color("ffe98a"), Color("d08a12"))
		var pts := PackedVector2Array([sc + Vector2(-5 * dir, -10), sc + Vector2(7 * dir, 0), sc + Vector2(-5 * dir, 10)])
		draw_polyline(pts, intro.CONTORNO, 5.0, true)
	# progresso até a próxima liga
	var atual_lg: Dictionary = Perfil.LIGAS[idx]
	var prox_lg: Dictionary = Perfil.LIGAS[idx + 1] if idx + 1 < Perfil.LIGAS.size() else {}
	var cr := Rect2(j.position.x + 40, j.position.y + 448, j.size.x - 80, 128)
	intro._caixa(cr, Color(0.05, 0.06, 0.15, 0.65), 20)
	_icone_liga(atual_lg, Vector2(cr.position.x + 58, cr.get_center().y), 86.0, 1.0)
	var tx := cr.position.x + 116
	var t1 := "Você: %s" % atual_lg.nome
	intro._texto_cartoon(Vector2(tx, cr.position.y + 38), t1, 24, Color("ffd34d"), intro.f_titulo, 1.6, false)
	intro._texto_cartoon(Vector2(tx + intro._larg(intro.f_titulo, t1, 24) + 14, cr.position.y + 38),
		"%s troféus · %d vitórias e %d derrotas" % [_milhar(Perfil.trofeus), Perfil.vitorias, Perfil.derrotas], 18, Color.WHITE, intro.f_texto, 1.3, false)
	var barra := Rect2(tx, cr.position.y + 56, cr.end.x - tx - 30, 24)
	intro._caixa(barra.grow(3), intro.CONTORNO, 14)
	intro._caixa(barra, Color(0.1, 0.08, 0.05), 12)
	var k := 1.0
	var txt := "Você está na liga mais alta!"
	if not prox_lg.is_empty():
		k = clampf(float(Perfil.trofeus - int(atual_lg.min)) / float(int(prox_lg.min) - int(atual_lg.min)), 0.0, 1.0)
		txt = "Faltam %s troféus para a liga %s" % [_milhar(int(prox_lg.min) - Perfil.trofeus), prox_lg.nome]
	k *= _ease(_troca)
	if k > 0.01:
		var cheia := Rect2(barra.position, Vector2(maxf(24.0, barra.size.x * k), barra.size.y))
		intro._botao_degrade(cheia, Color("fff3b0"), Color("f6c343"), Color("b8740f"), 12)
		var brilho := fmod(_relogio * 0.6, 1.0)
		intro._degrade(Rect2(cheia.position.x + cheia.size.x * brilho - 20, cheia.position.y + 3, 40, cheia.size.y - 6), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0))
	if not prox_lg.is_empty():
		_icone_liga(prox_lg, Vector2(barra.end.x + 4, barra.get_center().y), 40.0, 0.9)
	intro._texto_cartoon(Vector2(tx, cr.position.y + 108), txt, 17, Color("dfe4ff"), intro.f_texto, 1.2, false)
	intro._texto_cartoon(Vector2(j.get_center().x, j.end.y - 18), "A liga vem do total de troféus. Vencendo no PvP você ganha troféus; perdendo, perde alguns.", 16, Color("dfe4ff"), intro.f_texto, 1.2, true)
