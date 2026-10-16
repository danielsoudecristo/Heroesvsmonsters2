extends Control
## CONVIDE AMIGOS (indicação): seu código, enviar no WhatsApp, copiar, como funciona, metas de recrutador,
## seus convidados e "Tem um código?". Servidor: supabase/18_indicacao.sql.

const JANELA := Rect2(90, 34, 1100, 652)
const LINK_LOJA := "https://play.google.com/store/apps/details?id=com.danielsoucristo.heroesvsmonsters"
const ROSA1 := Color("ffb3d9")
const ROSA2 := Color("e0458f")
const ROSA3 := Color("7a1450")

var intro: Node
var dados := {}                                     # minhas_indicacoes
var carregando := false
var nota := ""
var nota_bom := false
var _abre := 0.0
var _relogio := 0.0
var _botoes: Array = []
var _apertado := -1
var _quadro_abriu := -1
var _tocou_aqui := false
var _festa := 0.0                                   # confete quando usa um código
var _confete: Array = []
var _copiou := 0.0
var campo: LineEdit
var _sobe := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	campo = LineEdit.new()
	campo.max_length = 10
	campo.placeholder_text = "Código do amigo"
	campo.alignment = HORIZONTAL_ALIGNMENT_CENTER
	campo.add_theme_font_override("font", intro.f_titulo)
	campo.add_theme_font_size_override("font_size", 24)
	campo.add_theme_color_override("font_color", Color("1c1630"))
	campo.add_theme_color_override("font_placeholder_color", Color(0.11, 0.09, 0.19, 0.4))
	campo.add_theme_color_override("caret_color", Color("2c3874"))
	for estado in ["normal", "focus", "read_only"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("fff8e6")
		sb.set_corner_radius_all(14)
		sb.set_border_width_all(3)
		sb.border_color = Color("f6c343") if estado == "focus" else Color("141a36")
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		campo.add_theme_stylebox_override(estado, sb)
	campo.text_submitted.connect(func(_t): _usar_codigo())
	campo.visible = false
	add_child(campo)

func _conta() -> Node:
	return get_node_or_null("/root/Conta")

func _logado() -> bool:
	var c := _conta()
	return c != null and c.online_pronto()

func abrir() -> void:
	_quadro_abriu = Engine.get_process_frames()
	visible = true
	_abre = 0.0
	_tocou_aqui = false
	nota = ""
	if not Perfil.convite_visto:
		Perfil.convite_visto = true
		Perfil.salvar()
	if _logado():
		_carregar()

func fechar() -> void:
	visible = false
	campo.visible = false
	campo.release_focus()
	_sobe = 0.0
	position.y = 0.0

func _carregar() -> void:
	if carregando:
		return
	carregando = true
	var r: Dictionary = await _conta().chamar("minhas_indicacoes")
	carregando = false
	if r.ok and r.dados is Dictionary:
		dados = r.dados
		if str(dados.get("codigo", "")) != "":
			Perfil.convite = str(dados.codigo)
	elif not r.ok:
		var e := str(r.erro).to_lower()
		nota = "Falta rodar o 18_indicacao.sql no Supabase." if ("function" in e or "could not find" in e) else "Sem internet. Tente de novo."
		nota_bom = false

func _codigo() -> String:
	var c := str(dados.get("codigo", Perfil.convite))
	return c if c != "" else "—"

func _texto_convite() -> String:
	return "Bora jogar Heroes vs Monsters comigo! Entra com o meu código %s e ganha 200 moedas de presente. Baixe aqui: %s" % [_codigo(), LINK_LOJA]

func _whatsapp() -> void:
	intro._clique(true)
	OS.shell_open("https://wa.me/?text=" + _texto_convite().uri_encode())
	Conta.registrar("tutorial", {"parte": "convite", "evento": "compartilhou"})

func _copiar() -> void:
	intro._clique(false)
	DisplayServer.clipboard_set(_texto_convite())
	_copiou = 2.0

func _usar_codigo() -> void:
	var cod := campo.text.strip_edges().to_upper()
	if cod.length() < 4:
		nota = "Digite o código que seu amigo mandou."
		nota_bom = false
		return
	if carregando:
		return
	carregando = true
	intro._clique(true)
	var r: Dictionary = await _conta().chamar("usar_convite", {"p_codigo": cod})
	carregando = false
	if r.ok and r.dados is Dictionary:
		if r.dados.get("perfil") is Dictionary:
			Perfil.de_servidor(r.dados.perfil)
		nota = "Você ganhou +200 moedas! Agora você e %s são amigos." % str(r.dados.get("amigo", "seu amigo"))
		nota_bom = true
		campo.text = ""
		campo.release_focus()
		_comemorar()
		_carregar()
	else:
		var e := str(r.erro)
		nota = e.left(90) if e != "" else "Não deu certo. Tente de novo."
		nota_bom = false

func _comemorar() -> void:
	_festa = 3.0
	_confete.clear()
	var cores := [Color("ffd34d"), Color("ff6fae"), Color("6bd8ff"), Color("8be03c"), Color("ffffff")]
	for i in 90:
		_confete.append({"p": Vector2(intro.W / 2.0 + randf_range(-60, 60), 300), "v": Vector2(randf_range(-420, 420), randf_range(-620, -200)),
			"c": cores[i % cores.size()], "r": randf() * TAU, "w": randf_range(-8, 8)})
	intro._trovao()

func _process(dt: float) -> void:
	if not visible:
		return
	_relogio += dt
	_abre = move_toward(_abre, 1.0, dt * 4.0)
	_copiou = maxf(0.0, _copiou - dt)
	if _festa > 0.0:
		_festa -= dt
		for c in _confete:
			c.v.y += 900.0 * dt
			c.p += c.v * dt
			c.r += c.w * dt
	var mostra: bool = _logado() and dados.get("pode_usar", false) == true and _abre > 0.6
	if campo.visible != mostra:
		campo.visible = mostra
	if mostra:
		var r := _ret_campo()
		if campo.position != intro.O + r.position:
			campo.position = intro.O + r.position
		if campo.size != r.size:
			campo.size = r.size
	_sobe = lerpf(_sobe, intro.subida_teclado(campo, _ret_campo().end.y), minf(1.0, dt * 14.0))
	if absf(position.y + _sobe) > 0.5:
		position.y = -roundf(_sobe)
	queue_redraw()

# =================================================================== TOQUES
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
		for i in _botoes.size():
			if _botoes[i].r.has_point(p):
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
	for b in _botoes:
		if b.r.has_point(p):
			b.f.call()
			return
	if campo.visible and not _ret_campo().has_point(p):
		campo.release_focus()

# =================================================================== LUGARES
func _ret_fechar() -> Rect2:
	return Rect2(JANELA.end.x - 92, JANELA.position.y + 28, 64, 60)

func _col_esq() -> Rect2:
	return Rect2(JANELA.position.x + 34, JANELA.position.y + 112, 520, JANELA.size.y - 140)

func _col_dir() -> Rect2:
	var e := _col_esq()
	return Rect2(e.end.x + 22, e.position.y, JANELA.end.x - 34 - e.end.x - 22, e.size.y)

func _ret_campo() -> Rect2:
	var d := _col_dir()
	return Rect2(d.position.x + 18, d.end.y - 66, d.size.x - 18 - 150, 50)

# =================================================================== DESENHO
static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

func _botao(r: Rect2, txt: String, c1: Color, c2: Color, c3: Color, f: Callable, tam := 22) -> void:
	var i := _botoes.size()
	var afunda := 3.0 if _apertado == i else 0.0
	intro._caixa(Rect2(r.position + Vector2(0, 5), r.size).grow(2), intro.CONTORNO, 16)
	var rr := Rect2(r.position + Vector2(0, afunda), r.size)
	intro._caixa(rr.grow(2), intro.CONTORNO, 16)
	intro._botao_degrade(rr, c1, c2, c3, 14)
	intro._texto_cartoon(Vector2(rr.get_center().x, rr.position.y + rr.size.y * 0.5 + tam * 0.36), txt, tam, Color.WHITE, intro.f_titulo, 1.5, true)
	_botoes.append({"r": r, "f": f})

func _draw() -> void:
	_botoes.clear()
	intro._ci = self
	var O: Vector2 = intro.O
	draw_rect(Rect2(-O, size), Color(0.02, 0.02, 0.05, 0.66 * _abre))
	var k := 0.92 + 0.08 * _ease(_abre)
	draw_set_transform(O + JANELA.get_center() - JANELA.get_center() * k, 0.0, Vector2(k, k))
	var j := JANELA
	# moldura (rosa e dourada: chama atenção)
	intro._caixa(Rect2(j.position + Vector2(0, 12), j.size).grow(10), Color(0, 0, 0, 0.45), 40)
	intro._caixa(j.grow(10), Color("4a0a2a"), 38)
	intro._caixa(j.grow(8), ROSA2, 36)
	intro._caixa(Rect2(j.position.x - 8, j.position.y - 8, j.size.x + 16, j.size.y * 0.5), Color("ffd34d"), 36)
	intro._caixa(j.grow(3), intro.NAVY, 31)
	intro._painel(j, Color("4a3f9c"), Color("1f2050"), 29)
	# título
	var pul := 1.0 + 0.05 * sin(_relogio * 4.0)
	intro._presente(Vector2(j.position.x + 70, j.position.y + 62), 64.0 * pul, _relogio)
	intro._texto_cartoon(Vector2(j.position.x + 116, j.position.y + 72), "Convide seus amigos", 42, Color("ffd34d"), intro.f_titulo, 2.5, false)
	intro._texto_cartoon(Vector2(j.position.x + 118, j.position.y + 98), "Jogar com amigos é muito melhor, e ainda dá moedas!", 17, Color("ffd0e8"), intro.f_texto, 1.2, false)
	var f := _ret_fechar()
	intro._caixa(Rect2(f.position + Vector2(0, 5), f.size).grow(3), intro.NAVY, 18)
	intro._caixa(f.grow(3), intro.NAVY, 18)
	intro._botao_degrade(f, Color("7f95e6"), Color("4a5fae"), Color("2c3874"), 16)
	var fc := f.get_center()
	for s in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(fc - s * 11, fc + s * 11, intro.CONTORNO, 7.0, true)
		draw_line(fc - s * 11, fc + s * 11, Color.WHITE, 4.0, true)
	if not _logado():
		_sem_conta()
	else:
		_coluna_codigo()
		_coluna_progresso()
	# aviso
	if nota != "":
		var tw: float = intro._larg(intro.f_texto, nota, 17) + 40
		var nr := Rect2(j.get_center().x - tw / 2.0, j.end.y - 16, tw, 34)
		intro._caixa(nr.grow(2), intro.CONTORNO, 18)
		intro._caixa(nr, Color("2f7d16") if nota_bom else Color("8a2414"), 16)
		intro._texto_cartoon(Vector2(nr.get_center().x, nr.position.y + 24), nota, 17, Color.WHITE, intro.f_texto, 1.2, true)
	draw_set_transform(O)
	# confete
	if _festa > 0.0:
		var a := clampf(_festa, 0.0, 1.0)
		for c in _confete:
			draw_set_transform(O + c.p, c.r, Vector2.ONE)
			draw_rect(Rect2(-6, -3, 12, 6), Color(c.c, a))
		draw_set_transform(O)

func _sem_conta() -> void:
	var j := JANELA
	var c := j.get_center() + Vector2(0, 20)
	intro._presente(c + Vector2(0, -90), 120.0, _relogio)
	intro._texto_cartoon(Vector2(c.x, c.y + 20), "Entre com sua conta para convidar amigos", 30, intro.CREME, intro.f_titulo, 2.0, true)
	intro._texto_cartoon(Vector2(c.x, c.y + 56), "Seu código de convite fica salvo na sua conta.", 19, Color("c9d2ff"), intro.f_texto, 1.2, true)
	_botao(Rect2(c.x - 140, c.y + 86, 280, 62), "Entrar", Color("d9ff9a"), Color("8be03c"), Color("3f8f1a"), _ir_login, 26)

func _ir_login() -> void:
	intro._clique(true)
	fechar()
	intro._ir(intro.Tela.LOGIN)

func _coluna_codigo() -> void:
	var e := _col_esq()
	# cartão do código
	var cc := Rect2(e.position.x, e.position.y, e.size.x, 196)
	intro._caixa(Rect2(cc.position + Vector2(0, 5), cc.size), Color(0, 0, 0, 0.35), 22)
	intro._caixa(cc.grow(3), intro.CONTORNO, 24)
	intro._botao_degrade(cc, ROSA1, ROSA2, ROSA3, 22)
	# brilho passando
	var sh := fmod(_relogio * 0.45, 1.6) - 0.3
	if sh > 0.0 and sh < 1.0:
		var x := cc.position.x + cc.size.x * sh
		draw_colored_polygon(PackedVector2Array([Vector2(x, cc.position.y + 4), Vector2(x + 40, cc.position.y + 4), Vector2(x + 10, cc.end.y - 4), Vector2(x - 30, cc.end.y - 4)]), Color(1, 1, 1, 0.16))
	intro._texto_cartoon(Vector2(cc.get_center().x, cc.position.y + 34), "SEU CÓDIGO DE CONVITE", 18, Color("fff0f7"), intro.f_titulo, 1.3, true)
	var cod := _codigo() if not carregando or dados.has("codigo") else "..."
	var placa := Rect2(cc.position.x + 70, cc.position.y + 48, cc.size.x - 140, 76)
	intro._caixa(placa.grow(3), intro.CONTORNO, 18)
	intro._caixa(placa, Color("fff8e6"), 16)
	var letras := PackedStringArray()
	for ch in cod:
		letras.append(ch)
	var espacado := " ".join(letras)
	intro._texto_cartoon(Vector2(placa.get_center().x, placa.position.y + 56), espacado, 46, Color("e0458f"), intro.f_titulo, 2.0, true)
	var bw := (cc.size.x - 60) / 2.0
	_botao(Rect2(cc.position.x + 20, cc.end.y - 60, bw + 30, 50), "Enviar no WhatsApp", Color("b7ffb0"), Color("25c25a"), Color("0d6b2c"), _whatsapp, 20)
	_botao(Rect2(cc.end.x - 20 - bw + 30, cc.end.y - 60, bw - 30, 50), "Copiado!" if _copiou > 0.0 else "Copiar", Color("9fd8ff"), Color("3a8ee0"), Color("1d4f8a"), _copiar, 20)
	# como funciona
	var y := cc.end.y + 30
	intro._texto_cartoon(Vector2(e.position.x + 4, y), "Como funciona", 24, Color("ffd34d"), intro.f_titulo, 1.6, false)
	y += 14
	var passos := [
		["1", "Mande seu código para os amigos", "pelo WhatsApp ou como quiser"],
		["2", "Seu amigo entra com o código", "ele ganha +200 moedas e vocês viram amigos"],
		["3", "Você ganha +100 moedas na hora", "e mais +300 quando ele chegar no nível 5 ou vencer 3 PvP"],
	]
	for p in passos:
		var r := Rect2(e.position.x, y, e.size.x, 62)
		intro._caixa(r, Color(0.05, 0.06, 0.18, 0.55), 16)
		var c := Vector2(r.position.x + 34, r.get_center().y)
		draw_circle(c, 21, intro.CONTORNO)
		intro._bola(c, 19, Color("ffe58a"), Color("d8921a"))
		intro._texto_cartoon(Vector2(c.x, c.y + 9), p[0], 24, Color.WHITE, intro.f_titulo, 1.4, true)
		intro._texto_cartoon(Vector2(r.position.x + 66, r.position.y + 27), p[1], 19, Color.WHITE, intro.f_titulo, 1.3, false)
		intro._texto_cartoon(Vector2(r.position.x + 66, r.position.y + 50), p[2], 14, Color("c9d2ff"), intro.f_texto, 1.0, false)
		y += 70

func _coluna_progresso() -> void:
	var d := _col_dir()
	var ativos := int(dados.get("ativos", 0))
	var total := int(dados.get("total", 0))
	var ganhou := int(dados.get("moedas_ganhas", 0))
	# números
	var nr := Rect2(d.position.x, d.position.y, d.size.x, 92)
	intro._caixa(nr, Color(0.05, 0.06, 0.18, 0.55), 18)
	var cols := [[str(total), "convidados"], [str(ativos), "já jogaram"], [str(ganhou), "moedas ganhas"]]
	var cw := nr.size.x / 3.0
	for i in 3:
		var cx := nr.position.x + cw * i + cw / 2.0
		if i == 2:
			intro._moeda(Vector2(cx - intro._larg(intro.f_titulo, cols[i][0], 34) / 2.0 - 18, nr.position.y + 36), 26)
		intro._texto_cartoon(Vector2(cx + (8 if i == 2 else 0), nr.position.y + 48), cols[i][0], 34, Color("ffd34d") if i == 2 else Color.WHITE, intro.f_titulo, 1.8, true)
		intro._texto_cartoon(Vector2(cx, nr.position.y + 76), cols[i][1], 15, Color("c9d2ff"), intro.f_texto, 1.0, true)
	# metas de recrutador
	var y := nr.end.y + 34
	intro._texto_cartoon(Vector2(d.position.x + 4, y), "Metas de recrutador", 22, Color("ffd34d"), intro.f_titulo, 1.5, false)
	var metas: Array = dados.get("metas", [{"qtd": 3, "bonus": 300, "titulo": "Recrutador"}, {"qtd": 10, "bonus": 1000, "titulo": "Capitão Recrutador"}, {"qtd": 25, "bonus": 3000, "titulo": "Lenda Recrutadora"}])
	var barra := Rect2(d.position.x + 20, y + 30, d.size.x - 60, 18)
	intro._caixa(barra.grow(3), intro.CONTORNO, 12)
	intro._caixa(barra, Color("1a1f40"), 10)
	var maxq := float(int(metas[-1].qtd))
	var kq := clampf(float(ativos) / maxq, 0.0, 1.0)
	if kq > 0.0:
		intro._botao_degrade(Rect2(barra.position, Vector2(maxf(18.0, barra.size.x * kq), barra.size.y)), Color("ffe58a"), Color("f0a21c"), Color("a0600a"), 10)
	for m in metas:
		var q := float(int(m.qtd))
		var px := barra.position.x + barra.size.x * (q / maxq)
		var feito := ativos >= int(m.qtd)
		var c := Vector2(px, barra.get_center().y)
		intro._bau(c + Vector2(0, -2), 40.0, feito, _relogio)
		intro._texto_cartoon(Vector2(px, barra.end.y + 40), "%d amigos" % int(m.qtd), 14, Color.WHITE if feito else Color(1, 1, 1, 0.7), intro.f_titulo, 1.1, true)
		intro._texto_cartoon(Vector2(px, barra.end.y + 58), "+%d" % int(m.bonus), 14, Color("ffd34d"), intro.f_titulo, 1.1, true)
	var nivel := int(dados.get("nivel", 0))
	var titulo := str(metas[nivel - 1].titulo) if nivel > 0 else "Ainda sem título"
	intro._texto_cartoon(Vector2(d.end.x - 4 - intro._larg(intro.f_texto, titulo, 15), y), titulo, 15, Color("ffd0e8"), intro.f_texto, 1.1, false)
	# lista de convidados
	y = barra.end.y + 92
	var lista: Array = dados.get("lista", [])
	intro._texto_cartoon(Vector2(d.position.x + 4, y), "Seus convidados", 20, Color("ffd34d"), intro.f_titulo, 1.4, false)
	y += 12
	var area_fim := (_ret_campo().position.y - 34.0) if dados.get("pode_usar", false) == true else (d.end.y - 56.0)
	if lista.is_empty():
		var r0 := Rect2(d.position.x, y, d.size.x, 58)
		intro._caixa(r0, Color(0.05, 0.06, 0.18, 0.45), 14)
		intro._texto_cartoon(Vector2(r0.get_center().x, r0.position.y + 36), "Ninguém ainda. Mande seu código!", 18, Color(1, 1, 1, 0.7), intro.f_texto, 1.1, true)
	else:
		var cabe := maxi(1, int((area_fim - y) / 46.0))
		if lista.size() > cabe:
			cabe = maxi(1, int((area_fim - y - 20.0) / 46.0))
		for i in mini(lista.size(), cabe):
			var a: Dictionary = lista[i]
			var r := Rect2(d.position.x, y, d.size.x, 40)
			intro._caixa(r, Color(0.2, 0.25, 0.52, 0.9), 12)
			intro._texto_cartoon(Vector2(r.position.x + 14, r.position.y + 27), str(a.nome), 18, Color.WHITE, intro.f_titulo, 1.2, false)
			var lado = a.get("lado_atual")
			if intro.social and lado != null:
				intro.social._selo_lado(r.position.x + 22 + intro._larg(intro.f_titulo, str(a.nome), 18), r.position.y + 28, lado, true)
			var st := "jogou ✓ +300" if a.get("jogou", false) == true else "começando..."
			intro._texto_cartoon(Vector2(r.end.x - 14 - intro._larg(intro.f_texto, st, 15), r.position.y + 26), st, 15,
				Color("b6ff6a") if a.get("jogou", false) == true else Color(1, 1, 1, 0.6), intro.f_texto, 1.0, false)
			y += 46
		if lista.size() > cabe:
			intro._texto_cartoon(Vector2(d.get_center().x, y + 10), "+%d convidados" % (lista.size() - cabe), 15, Color(1, 1, 1, 0.6), intro.f_texto, 1.0, true)
	# tem um código?
	if dados.get("pode_usar", false) == true:
		var rc := _ret_campo()
		intro._texto_cartoon(Vector2(d.position.x + 4, rc.position.y - 10), "Um amigo te convidou? Use o código dele:", 16, Color("ffd0e8"), intro.f_texto, 1.1, false)
		intro._caixa(Rect2(d.position.x, rc.position.y - 6, d.size.x, rc.size.y + 12), Color(0.05, 0.06, 0.18, 0.4), 16)
		_botao(Rect2(rc.end.x + 10, rc.position.y, d.end.x - rc.end.x - 18, rc.size.y), "Usar", Color("d9ff9a"), Color("8be03c"), Color("3f8f1a"), _usar_codigo, 22)
	elif dados.get("usei", false) == true:
		var r2 := Rect2(d.position.x, d.end.y - 50, d.size.x, 44)
		intro._caixa(r2, Color(0.1, 0.35, 0.15, 0.6), 14)
		intro._texto_cartoon(Vector2(r2.get_center().x, r2.position.y + 29), "Você entrou pelo convite de %s ✓" % str(dados.get("padrinho", "um amigo")), 17, Color("b6ff6a"), intro.f_texto, 1.1, true)
