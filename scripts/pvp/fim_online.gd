extends Control
## FIM DA PARTIDA ONLINE (PvP e duelo): os dois jogadores lado a lado, bem caprichado.
## Cada cartão: lado (Heroes/Monsters), foto, nome, VENCEDOR com coroa, liga, troféus e moedas (já com o resultado,
## o número sobe/desce animado e mostra +30 / −20), vitórias e derrotas.
## No cartão do adversário: "+ Adicionar amigo" (ou "Amigos ✓" / "Pedido enviado").
## REVANCHE (botão vermelho): qualquer um pede; o outro vê "Aceitar revanche!" aqui mesmo. Mesmos lados; PvP normal vale
## troféus de novo, duelo vale a mesma aposta. Servidor: pedir_revanche / ver_revanche (15_fim_partida.sql) + responder_duelo.
## Dados: jogadores_da_sala(p_sala) do supabase/15_fim_partida.sql.

const W := 1280.0
const H := 720.0
const CARTA := Vector2(400, 470)
const CONTORNO := Color("24130a")
## PESSOA REAL (esta tela só aparece no online): contorno do perfil — Heroes LARANJA, Monsters VERDE.
const CONTORNO_REAL := {"heroes": Color("ff8c1a"), "monsters": Color("3ddc4a")}
const COR_LADO := {"heroes": [Color("ffe98a"), Color("f6c343"), Color("b8740f")], "monsters": [Color("d9ff9a"), Color("8be03c"), Color("3f8f1a")]}

var f_titulo: Font
var f_texto: Font
var titulo := ""                                   # VITÓRIA! / DERROTA / EMPATE
var subtitulo := ""                                # "Duelo valendo..." / "PvP online"
var jogadores: Array = []                          # [eu, adversário] (jogadores_da_sala)
var vencedor_lado := ""                            # heroes / monsters / "" (empate)
var deltas := {}                                   # id -> {trofeus, moedas}
var ao_menu: Callable
var _t := 0.0
var _fotos := {}                                   # url -> Texture2D
var _botoes: Array = []
var _amigo_estado := ""                            # "" / enviando / pendente / aceita
var _apertou := false
var sala_id := ""                                  # partida que acabou (para a revanche)
var rev := {}                                      # {id, de_mim, status} (vazio = ninguém pediu)
var _rev_t := 0.0                                  # tempo até perguntar de novo
var _rev_desde := 0.0                              # segundos desde o pedido
var _rev_ocupado := false
var _entrando := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

func mostrar(lista: Array) -> void:
	jogadores = lista.duplicate()
	jogadores.sort_custom(func(a, b): return a.get("eu", false) == true and b.get("eu", false) != true)   # você na esquerda
	if jogadores.size() > 1:
		_amigo_estado = str(jogadores[1].get("amizade", ""))
	for j in jogadores:
		var u := str(j.get("avatar_url", "")) if j.get("avatar_url") != null else ""
		_baixar_foto(u)
	_t = 0.0
	visible = true

func _process(dt: float) -> void:
	if visible:
		_t += dt
		queue_redraw()
	if sala_id == "" or _entrando:
		return
	if not rev.is_empty():
		_rev_desde += dt
	_rev_t -= dt
	if _rev_t <= 0.0:
		_rev_t = 2.0
		_ver_revanche()

# ------------------------------------------------------------------ REVANCHE
func _conta() -> Node:
	return get_node_or_null("/root/Conta")

func _ver_revanche() -> void:
	if _rev_ocupado:
		return
	_rev_ocupado = true
	var r: Dictionary = await _conta().chamar("ver_revanche", {"p_sala": sala_id})
	_rev_ocupado = false
	if not r.ok or _entrando or _pedindo:
		return
	if not (r.dados is Dictionary):
		return
	var antes := str(rev.get("status", ""))
	var novo_pedido: bool = rev.is_empty() or str(rev.get("id", "")) != str(r.dados.get("id", ""))
	rev = r.dados
	if novo_pedido:
		_rev_desde = 0.0
		if rev.get("de_mim", false) != true and str(rev.get("status", "")) == "pendente":
			Sons.tocar("Jogo/som/lutem", 0.7)
	if str(rev.get("status", "")) == "aceito" and rev.get("sala") is Dictionary:
		await _entrar(rev.sala)
	elif antes == "pendente" and str(rev.get("status", "")) != "pendente":
		pass

var _pedindo := false
func _pedir_revanche() -> void:
	if _pedindo or sala_id == "":
		return
	_pedindo = true
	rev = {"id": "", "de_mim": true, "status": "pendente"}     # (já mostra "Esperando..." enquanto o servidor responde)
	_rev_desde = 0.0
	var r: Dictionary = await _conta().chamar("pedir_revanche", {"p_sala": sala_id})
	_pedindo = false
	if r.ok and r.dados is Dictionary:
		rev = r.dados
		if rev.get("de_mim", false) != true:          # o outro já tinha pedido: aceita direto
			await _aceitar_revanche()
	else:
		rev = {"status": "erro", "msg": str(r.erro)}

func _aceitar_revanche() -> void:
	if rev.is_empty() or _rev_ocupado:
		return
	_rev_ocupado = true
	var r: Dictionary = await _conta().chamar("responder_duelo", {"p_id": str(rev.id), "p_aceitar": true})
	_rev_ocupado = false
	if r.ok and r.dados is Dictionary and r.dados.has("id"):
		await _entrar(r.dados)
	else:
		rev = {"status": "erro", "msg": str(r.erro)}

func _recusar_revanche() -> void:
	if rev.is_empty():
		return
	var id := str(rev.id)
	rev = {"status": "recusado", "de_mim": false}
	_conta().chamar("responder_duelo", {"p_id": id, "p_aceitar": false})

## Entra na partida nova (mesmo caminho da busca do PvP).
func _entrar(sala: Dictionary) -> void:
	if _entrando:
		return
	_entrando = true
	var token: String = await _conta().token_fresco()
	var s := sala.duplicate()
	s["token"] = token
	s["lado"] = "heroes" if str(s.get("heroes", "")) == _conta().meu_id() else "monsters"
	Perfil.pvp_adversario = str(jogadores[1].get("nome", "Adversário")) if jogadores.size() > 1 else "Adversário"
	Perfil.pvp_sala = s
	get_tree().paused = false
	get_tree().change_scene_to_file("res://cenas/pvp.tscn")

# ------------------------------------------------------------------ toques
func _gui_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton) or ev.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if ev.pressed:
		_apertou = true
		return
	if not _apertou:
		return
	_apertou = false
	var p: Vector2 = get_local_mouse_position()
	for b in _botoes:
		if b.r.has_point(p):
			b.f.call()
			return

func _adicionar() -> void:
	if jogadores.size() < 2 or _amigo_estado != "":
		return
	_amigo_estado = "enviando"
	var conta := get_node_or_null("/root/Conta")
	var r: Dictionary = await conta.chamar("pedir_amizade", {"p_alvo": str(jogadores[1].id)})
	_amigo_estado = (str(r.dados) if r.dados is String else "pendente") if r.ok else ""

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
	var t := 128
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

# ------------------------------------------------------------------ ajudantes de desenho
func _caixa(r: Rect2, cor: Color, raio: int, borda := 0, cor_borda := Color()) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = cor
	sb.set_corner_radius_all(raio)
	if borda > 0:
		sb.set_border_width_all(borda)
		sb.border_color = cor_borda
	draw_style_box(sb, r)

## Caixa arredondada com degradê de cima (c1) para baixo (c2).
func _degrade(r: Rect2, c1: Color, c2: Color, raio: int) -> void:
	_caixa(r, c2, raio)
	var topo := StyleBoxFlat.new()
	topo.bg_color = c1
	topo.corner_radius_top_left = raio
	topo.corner_radius_top_right = raio
	draw_style_box(topo, Rect2(r.position, Vector2(r.size.x, raio + 1)))
	var y0 := r.position.y + raio
	var y1 := r.end.y - raio
	if y1 > y0:
		draw_polygon(PackedVector2Array([Vector2(r.position.x, y0), Vector2(r.end.x, y0), Vector2(r.end.x, y1), Vector2(r.position.x, y1)]),
			PackedColorArray([c1, c1, c2, c2]))

func _texto(pos: Vector2, txt: String, tam: int, cor: Color, f: Font, contorno := 8, centro := true) -> void:
	var x := pos.x - (f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x / 2.0 if centro else 0.0)
	draw_string_outline(f, Vector2(x, pos.y + 3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, contorno + 4, Color(0, 0, 0, 0.3 * cor.a))
	draw_string_outline(f, Vector2(x, pos.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, contorno, Color(CONTORNO, cor.a))
	draw_string(f, Vector2(x, pos.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)

func _bola(c: Vector2, r: float, clara: Color, escura: Color) -> void:
	draw_circle(c, r, escura)
	draw_circle(c + Vector2(-r * 0.12, -r * 0.14), r * 0.8, clara.lerp(escura, 0.35))
	draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.4, clara)

func _botao(r: Rect2, txt: String, c1: Color, c2: Color, f: Callable, tam := 22) -> void:
	_caixa(Rect2(r.position + Vector2(0, 6), r.size).grow(3), CONTORNO, 18)
	_caixa(r.grow(3), CONTORNO, 18)
	_degrade(r, c1, c2, 15)
	_caixa(Rect2(r.position.x + 10, r.position.y + 5, r.size.x - 20, r.size.y * 0.28), Color(1, 1, 1, 0.25), 10)
	_texto(Vector2(r.get_center().x, r.position.y + r.size.y * 0.5 + tam * 0.36), txt, tam, Color.WHITE, f_titulo, 6)
	_botoes.append({"r": r, "f": f})

func _moeda(c: Vector2, r: float) -> void:
	draw_circle(c, r + 2, CONTORNO)
	draw_circle(c, r, Color("f2b536"))
	draw_circle(c, r * 0.7, Color("ffd34d"))
	draw_arc(c, r * 0.7, 0, TAU, 20, Color("b8740f"), 2.0, true)

func _trofeu(c: Vector2, k: float) -> void:
	var copo := PackedVector2Array([c + Vector2(-11, -12) * k, c + Vector2(11, -12) * k, c + Vector2(8, 2) * k, c + Vector2(3, 5) * k,
		c + Vector2(-3, 5) * k, c + Vector2(-8, 2) * k])
	draw_arc(c + Vector2(-11, -6) * k, 5 * k, PI * 0.5, PI * 1.5, 10, CONTORNO, 5 * k, true)
	draw_arc(c + Vector2(11, -6) * k, 5 * k, -PI * 0.5, PI * 0.5, 10, CONTORNO, 5 * k, true)
	draw_arc(c + Vector2(-11, -6) * k, 5 * k, PI * 0.5, PI * 1.5, 10, Color("f6c343"), 2.5 * k, true)
	draw_arc(c + Vector2(11, -6) * k, 5 * k, -PI * 0.5, PI * 0.5, 10, Color("f6c343"), 2.5 * k, true)
	var borda := copo.duplicate()
	borda.append(copo[0])
	draw_colored_polygon(copo, Color("f6c343"))
	draw_polyline(borda, CONTORNO, 2.5 * k, true)
	draw_rect(Rect2(c + Vector2(-2, 5) * k, Vector2(4, 5) * k), Color("b8740f"))
	draw_rect(Rect2(c + Vector2(-8, 10) * k, Vector2(16, 4) * k), Color("b8740f"))

func _coroa(c: Vector2, k: float) -> void:
	var w := 54.0 * k
	var h := 32.0 * k
	var bob := Vector2(0, sin(_t * 3.0) * 3.0)
	var pts := PackedVector2Array([Vector2(-w / 2, h / 2), Vector2(-w / 2, -h / 4), Vector2(-w / 4, h / 8), Vector2(0, -h / 2),
		Vector2(w / 4, h / 8), Vector2(w / 2, -h / 4), Vector2(w / 2, h / 2)])
	for i in pts.size():
		pts[i] += c + bob
	var borda := pts.duplicate()
	borda.append(pts[0])
	draw_colored_polygon(pts, Color("ffd34d"))
	draw_polyline(borda, CONTORNO, 3.0, true)
	for i in [1, 3, 5]:
		draw_circle(pts[i], 5.0 * k, Color("fff6d0"))
	draw_circle(c + bob + Vector2(0, h * 0.2), 5.0 * k, Color("e04a4a"))

static func _milhar(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out

static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)

static func _ease_back(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)

# ------------------------------------------------------------------ desenho
func _draw() -> void:
	_botoes = []
	draw_rect(preload("res://scripts/arena/config_arena.gd").tela_toda(self), Color(0.02, 0.02, 0.06, 0.92 * _ease(_t * 3.0)))
	var ganhou := vencedor_lado != "" and jogadores.size() > 0 and str(jogadores[0].get("lado", "")) == vencedor_lado
	var cor_t := Color("ffd34d") if ganhou else (Color("fff4d6") if vencedor_lado == "" else Color("ff8a7a"))
	# raios atrás do título
	var tc := Vector2(W / 2.0, 70)
	if ganhou:
		for i in 14:
			var a := _t * 0.4 + i * TAU / 14.0
			draw_colored_polygon(PackedVector2Array([tc, tc + Vector2(cos(a - 0.08), sin(a - 0.08)) * 420.0, tc + Vector2(cos(a + 0.08), sin(a + 0.08)) * 420.0]),
				Color(1, 0.85, 0.35, 0.06))
	var k := _ease_back(_t * 2.5)
	draw_set_transform(tc * (1.0 - k), 0.0, Vector2(k, k))
	_texto(tc + Vector2(0, 26), titulo, 66, cor_t, f_titulo, 14)
	draw_set_transform(Vector2.ZERO)
	_texto(Vector2(W / 2.0, 124), subtitulo, 20, Color("dfe4ff"), f_texto, 6)
	if jogadores.size() < 2:
		var c := Vector2(W / 2.0, 360)
		draw_arc(c, 30, _t * 5.0, _t * 5.0 + 4.2, 32, Color("f6c343"), 8, true)
		_texto(c + Vector2(0, 70), "Carregando os jogadores...", 22, Color("fff4d6"), f_texto, 6)
		return
	# cartões
	var y := 140.0
	for i in 2:
		var x := W / 2.0 - CARTA.x - 50 if i == 0 else W / 2.0 + 50
		var entra := _ease_back(_t * 2.2 - 0.25 - i * 0.12)
		var r := Rect2(Vector2(x + (1.0 - entra) * (-120.0 if i == 0 else 120.0), y), CARTA)
		_cartao(jogadores[i], r, i == 1, clampf(entra, 0.0, 1.0))
	# VS no meio
	var vs := Vector2(W / 2.0, y + CARTA.y * 0.45)
	var kv := _ease_back(_t * 2.0 - 0.5)
	draw_circle(vs + Vector2(0, 4), 44 * kv, Color(0, 0, 0, 0.4))
	draw_circle(vs, 44 * kv, CONTORNO)
	_bola(vs, 40 * kv, Color("ff8a6a"), Color("b8261a"))
	if kv > 0.3:
		_texto(vs + Vector2(0, 14), "VS", int(36 * kv), Color.WHITE, f_titulo, 8)
	# botão
	_desenhar_revanche()
	_botao(Rect2(W / 2.0 + 16, 640, 250, 60), "Voltar ao menu", Color("9fb0f0"), Color("4a5fae"), _menu, 24)

func _desenhar_revanche() -> void:
	var b := Rect2(W / 2.0 - 266, 640, 250, 60)
	var nome := str(jogadores[1].get("nome", "Ele")) if jogadores.size() > 1 else "Ele"
	var st := str(rev.get("status", ""))
	var meu: bool = rev.get("de_mim", false) == true
	if _entrando or st == "aceito":
		_texto(Vector2(b.get_center().x, b.position.y + 40), "Começando...", 24, Color("ffd34d"), f_titulo, 6)
		return
	if st == "pendente" and not meu:                    # o outro pediu: botão grande pulsando
		var k := 1.0 + 0.06 * sin(_t * 8.0)
		var bb := Rect2(b.get_center() - b.size * k / 2.0, b.size * k)
		for i in 3:
			_caixa(bb.grow(6 + i * 6), Color(1, 0.3, 0.2, 0.14 - i * 0.04), 24)
		_botao(bb, "Aceitar revanche!", Color("ffb0a0"), Color("c0261a"), _aceitar_revanche, 23)
		_texto(Vector2(W / 2.0, 628), "%s quer revanche!" % nome, 22, Color("ffd34d"), f_titulo, 6)
		return
	if st == "pendente" and meu:
		_caixa(Rect2(b.position + Vector2(0, 6), b.size).grow(3), CONTORNO, 18)
		_caixa(b.grow(3), CONTORNO, 18)
		_degrade(b, Color("9a8f9a"), Color("6a5f6a"), 15)
		var falta := maxi(0, 90 - int(_rev_desde))
		_texto(Vector2(b.get_center().x, b.position.y + 39), "Esperando... %ds" % falta, 22, Color.WHITE, f_titulo, 6)
		_texto(Vector2(W / 2.0, 628), "Revanche pedida! Esperando %s aceitar." % nome, 19, Color("dfe4ff"), f_texto, 5)
		return
	if st in ["recusado", "cancelado"] and _rev_desde < 6.0:
		_texto(Vector2(W / 2.0, 628), "%s não quis a revanche agora." % nome if meu else "Revanche cancelada.", 19, Color("ffb0a0"), f_texto, 5)
	elif st == "erro":
		_texto(Vector2(W / 2.0, 628), str(rev.get("msg", "Não deu.")).left(70), 18, Color("ffb0a0"), f_texto, 5)
	_botao(b, "Revanche", Color("ffb0a0"), Color("c0261a"), _pedir_revanche, 26)

func _menu() -> void:
	if ao_menu.is_valid():
		ao_menu.call()

func _cartao(j: Dictionary, r: Rect2, adversario: bool, a: float) -> void:
	var lado := str(j.get("lado", "heroes"))
	var cores: Array = COR_LADO.get(lado, COR_LADO.heroes)
	var venceu := vencedor_lado != "" and lado == vencedor_lado
	if venceu:                                          # brilho do vencedor
		var pul := 0.5 + 0.5 * sin(_t * 3.0)
		for i in 3:
			_caixa(r.grow(10 + i * 7 + pul * 4), Color(1, 0.83, 0.3, (0.12 - i * 0.03) * a), 34)
	_caixa(Rect2(r.position + Vector2(0, 10), r.size).grow(6), Color(0, 0, 0, 0.45 * a), 32)
	_caixa(r.grow(6), CONTORNO, 32)
	var real: Color = CONTORNO_REAL.get(lado, CONTORNO_REAL.heroes)
	_caixa(r.grow(3), real, 30)                         # PESSOA REAL: borda laranja (Heroes) / verde (Monsters)
	_degrade(r, Color("3e4f96"), Color("1b2350"), 28)
	# faixa do lado
	var faixa := Rect2(r.position + Vector2(10, 10), Vector2(r.size.x - 20, 44))
	_degrade(faixa, cores[0], cores[2], 18)
	_texto(Vector2(faixa.get_center().x, faixa.position.y + 32), ("HEROES" if lado == "heroes" else "MONSTERS") + ("  ·  VOCÊ" if j.get("eu", false) == true else ""), 22, Color.WHITE, f_titulo, 6)
	# foto
	var fc := Vector2(r.get_center().x, r.position.y + 142)
	var fr := 52.0
	draw_circle(fc + Vector2(0, 5), fr + 8, Color(0, 0, 0, 0.35))
	var pul := 0.5 + 0.5 * sin(_t * 5.0)               # contorno de PESSOA REAL em volta da foto
	draw_arc(fc, fr + 17, 0, TAU, 56, Color(real, 0.25 + 0.2 * pul * a), 7, true)
	draw_circle(fc, fr + 14, CONTORNO)
	draw_circle(fc, fr + 11, real)
	draw_circle(fc, fr + 8, CONTORNO)
	_bola(fc, fr + 5, cores[0], cores[2])
	var url := str(j.get("avatar_url", "")) if j.get("avatar_url") != null else ""
	var tex: Texture2D = _fotos.get(url)
	if tex:
		draw_texture_rect(tex, Rect2(fc - Vector2(fr, fr), Vector2(fr, fr) * 2.0), false)
	else:
		var nome0 := str(j.get("nome", "?"))
		var paleta := [Color("2f7fd6"), Color("1fa6a0"), Color("8a5ad6"), Color("d65a7a"), Color("d6862f"), Color("4aa83a")]
		var cor: Color = paleta[absi(nome0.hash()) % paleta.size()]
		_bola(fc, fr, cor.lightened(0.25), cor.darkened(0.2))
		_texto(fc + Vector2(0, fr * 0.38), nome0.left(1).to_upper(), int(fr * 1.1), Color.WHITE, f_titulo, 8)
	if venceu:
		_coroa(fc + Vector2(0, -fr - 10), 0.9)
		var tag := Rect2(fc.x - 66, fc.y + fr - 4, 132, 28)
		_caixa(tag.grow(3), CONTORNO, 15)
		_degrade(tag, Color("fff3b0"), Color("d08a12"), 13)
		_texto(Vector2(tag.get_center().x, tag.position.y + 21), "VENCEDOR", 17, Color.WHITE, f_titulo, 5)
	# nome
	_texto(Vector2(r.get_center().x, r.position.y + 256), str(j.get("nome", "?")), 30, Color.WHITE, f_titulo, 8)
	# liga
	var trof := int(j.get("trofeus", 0))
	var lg := Perfil.liga_de(trof)
	var lt: Texture2D = load("res://assets/liga/%s.png" % lg.img) if ResourceLoader.exists("res://assets/liga/%s.png" % lg.img) else null
	var lc := Vector2(r.position.x + 66, r.position.y + 300)
	if lt:
		var s := 62.0 / maxf(lt.get_width(), lt.get_height())
		var tt := Vector2(lt.get_width(), lt.get_height()) * s
		draw_texture_rect(lt, Rect2(lc - tt / 2.0, tt), false)
	_texto(Vector2(lc.x + 46, lc.y - 4), "Liga", 15, Color(1, 1, 1, 0.6), f_texto, 4, false)
	_texto(Vector2(lc.x + 46, lc.y + 22), str(lg.nome), 26, (lg.cor as Color).lightened(0.25), f_titulo, 6, false)
	var vit := "%d V · %d D" % [int(j.get("vitorias", 0)), int(j.get("derrotas", 0))]
	_texto(Vector2(r.end.x - 24 - f_texto.get_string_size(vit, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, lc.y + 22), vit, 16, Color("c9d2ff"), f_texto, 4, false)
	# troféus e moedas (contam até o número novo)
	var d: Dictionary = deltas.get(str(j.get("id", "")), {})
	var conta_k := _ease(_t * 1.2 - 0.6)
	var linhas := [["trofeus", trof, int(d.get("trofeus", 0))], ["moedas", int(j.get("moedas", 0)), int(d.get("moedas", 0))]]
	var yy := r.position.y + 336
	for ln in linhas:
		var caixa := Rect2(r.position.x + 20, yy, r.size.x - 40, 38)
		_caixa(caixa, Color(0.05, 0.06, 0.15, 0.6), 14)
		var ic := Vector2(caixa.position.x + 26, caixa.get_center().y)
		if ln[0] == "trofeus":
			_trofeu(ic + Vector2(0, 1), 1.0)
		else:
			_moeda(ic, 12)
		var final: int = ln[1]
		var delta: int = ln[2]
		var mostra := roundi(lerpf(final - delta, final, conta_k))
		_texto(Vector2(ic.x + 24, caixa.position.y + 28), _milhar(mostra), 24, Color("fff6d0"), f_titulo, 6, false)
		if delta != 0:
			var dt := ("+" if delta > 0 else "−") + _milhar(absi(delta))
			var cor_d := Color("8be03c") if delta > 0 else Color("ff7a6a")
			var pulo := sin(clampf(_t * 2.0 - 1.2, 0.0, 1.0) * PI) * 6.0
			_texto(Vector2(caixa.end.x - 14 - f_titulo.get_string_size(dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x, caixa.position.y + 28 - pulo), dt, 22, cor_d, f_titulo, 6, false)
		yy += 44
	# adicionar amigo (só no adversário)
	if not adversario:
		_texto(Vector2(r.get_center().x, r.end.y - 20), "Sua conta agora", 18, Color(1, 1, 1, 0.55), f_texto, 4)
	else:
		var bb := Rect2(r.position.x + 40, r.end.y - 50, r.size.x - 80, 40)
		match _amigo_estado:
			"aceita":
				_texto(Vector2(bb.get_center().x, bb.position.y + 30), "Vocês são amigos ✓", 22, Color("b6ff6a"), f_titulo, 6)
			"pendente":
				_texto(Vector2(bb.get_center().x, bb.position.y + 30), "Pedido de amizade enviado ✓", 20, Color("dfe4ff"), f_titulo, 6)
			"enviando":
				_texto(Vector2(bb.get_center().x, bb.position.y + 30), "Enviando...", 20, Color("dfe4ff"), f_titulo, 6)
			_:
				_botao(bb, "+ Adicionar amigo", Color("d9ff9a"), Color("4a9e1f"), _adicionar, 20)
