extends Control
## LOJA DE MOEDAS (janela do menu): 5 pacotes, preço que o Google manda (já na moeda da pessoa), selo de
## "mais popular" / "melhor valor" e a faixa "1ª compra em dobro". Quem compra e entrega é o autoload Loja
## (scripts/sistema/loja_moedas.gd). Abre tocando nas moedas do perfil no menu.

const JANELA := Rect2(90, 34, 1100, 652)
const OURO1 := Color("fff3a6")
const OURO2 := Color("f6c343")
const OURO3 := Color("9a5a0a")
## cores de cada cartão (clara, meio, escura), do menor para o maior pacote
const CORES := [
	[Color("bfe3ff"), Color("4a9be6"), Color("1d4f8a")],
	[Color("c8ffb0"), Color("4fc23a"), Color("1f6b14")],
	[Color("ffe9a0"), Color("f0a020"), Color("8a4a08")],
	[Color("f3c6ff"), Color("b05ae0"), Color("54207a")],
	[Color("ffc0b0"), Color("e8463a"), Color("7a1410")],
]

var intro: Node
var _abre := 0.0
var _relogio := 0.0
var _botoes: Array = []
var _apertado := -1
var _quadro_abriu := -1
var _tocou_aqui := false
var nota := ""
var nota_bom := false
var _nota_t := 0.0
var _festa := 0.0
var _confete: Array = []
var _ganhou := 0
var _ganhou_dobro := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	Loja.mudou.connect(queue_redraw)
	Loja.comprou.connect(_comprou)
	Loja.aviso.connect(func(t: String, bom: bool): _avisar(t, bom))

func abrir() -> void:
	_quadro_abriu = Engine.get_process_frames()
	visible = true
	_abre = 0.0
	_tocou_aqui = false
	nota = ""
	Loja.atualizar()

func fechar() -> void:
	visible = false

func _avisar(t: String, bom: bool) -> void:
	nota = t
	nota_bom = bom
	_nota_t = 5.0

func _comprou(moedas: int, em_dobro: bool) -> void:
	_ganhou = moedas
	_ganhou_dobro = em_dobro
	_festa = 3.5
	_confete.clear()
	var cores := [Color("ffd34d"), Color("fff3a6"), Color("f6c343"), Color("8be03c"), Color("ffffff")]
	for i in 110:
		_confete.append({"p": Vector2(intro.W / 2.0 + randf_range(-80, 80), 320), "v": Vector2(randf_range(-460, 460), randf_range(-680, -220)),
			"c": cores[i % cores.size()], "r": randf() * TAU, "w": randf_range(-8, 8), "moeda": i % 3 == 0})
	intro._trovao()
	_avisar("+%s moedas na sua conta!%s" % [_milhar(moedas), "  (1ª compra em dobro)" if em_dobro else ""], true)

func _process(dt: float) -> void:
	if not visible:
		return
	_relogio += dt
	_abre = move_toward(_abre, 1.0, dt * 4.0)
	_nota_t = maxf(0.0, _nota_t - dt)
	if _nota_t <= 0.0:
		nota = ""
	if _festa > 0.0:
		_festa -= dt
		for c in _confete:
			c.v.y += 900.0 * dt
			c.p += c.v * dt
			c.r += c.w * dt
	queue_redraw()

static func _milhar(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out

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

func _ret_fechar() -> Rect2:
	return Rect2(JANELA.end.x - 92, JANELA.position.y + 28, 64, 60)

func _ir_login() -> void:
	intro._clique(true)
	fechar()
	intro._ir(intro.Tela.LOGIN)

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
	draw_rect(Rect2(-O, size), Color(0.02, 0.02, 0.05, 0.7 * _abre))
	var k := 0.92 + 0.08 * _ease(_abre)
	draw_set_transform(O + JANELA.get_center() - JANELA.get_center() * k, 0.0, Vector2(k, k))
	var j := JANELA
	# moldura dourada
	intro._caixa(Rect2(j.position + Vector2(0, 12), j.size).grow(10), Color(0, 0, 0, 0.45), 40)
	intro._caixa(j.grow(10), OURO3, 38)
	intro._caixa(j.grow(8), OURO2, 36)
	intro._caixa(Rect2(j.position.x - 8, j.position.y - 8, j.size.x + 16, j.size.y * 0.5), OURO1, 36)
	intro._caixa(j.grow(3), intro.NAVY, 31)
	intro._painel(j, Color("3b4fa8"), Color("1a1f4e"), 29)
	# título: monte de moedas + nome + saldo
	_monte(Vector2(j.position.x + 74, j.position.y + 78), 7, 1.25)
	intro._texto_cartoon(Vector2(j.position.x + 128, j.position.y + 72), "Loja de Moedas", 42, OURO2, intro.f_titulo, 2.5, false)
	intro._texto_cartoon(Vector2(j.position.x + 130, j.position.y + 98), "Evolua seus personagens e use os poderes especiais!", 17, Color("d6defa"), intro.f_texto, 1.2, false)
	var saldo := _milhar(Perfil.moedas)
	var sw: float = intro._larg(intro.f_titulo, saldo, 24) + 62
	var sr := Rect2(_ret_fechar().position.x - 16 - sw, j.position.y + 36, sw, 44)
	intro._caixa(sr.grow(2), intro.CONTORNO, 22)
	intro._caixa(sr, Color(0, 0, 0, 0.45), 20, 2, Color(1, 0.85, 0.4, 0.5))
	intro._moeda(Vector2(sr.position.x + 24, sr.get_center().y), 30)
	intro._texto_cartoon(Vector2(sr.position.x + 44, sr.position.y + 32), saldo, 24, Color("ffe58a"), intro.f_titulo, 1.5, false)
	# fechar
	var f := _ret_fechar()
	intro._caixa(Rect2(f.position + Vector2(0, 5), f.size).grow(3), intro.NAVY, 18)
	intro._caixa(f.grow(3), intro.NAVY, 18)
	intro._botao_degrade(f, Color("7f95e6"), Color("4a5fae"), Color("2c3874"), 16)
	var fc := f.get_center()
	for s in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(fc - s * 11, fc + s * 11, intro.CONTORNO, 7.0, true)
		draw_line(fc - s * 11, fc + s * 11, Color.WHITE, 4.0, true)
	if not Loja.logado():
		_sem_conta()
	else:
		_faixa_dobro()
		_cartoes()
		_rodape()
	# aviso
	if nota != "":
		var tw: float = intro._larg(intro.f_texto, nota, 17) + 40
		var nr := Rect2(j.get_center().x - tw / 2.0, j.end.y - 18, tw, 34)
		intro._caixa(nr.grow(2), intro.CONTORNO, 18)
		intro._caixa(nr, Color("2f7d16") if nota_bom else Color("8a2414"), 16)
		intro._texto_cartoon(Vector2(nr.get_center().x, nr.position.y + 24), nota, 17, Color.WHITE, intro.f_texto, 1.2, true)
	# esperando o Google / o servidor: véu por cima com a moeda girando
	if Loja.ocupado != "":
		intro._caixa(j, Color(0.02, 0.02, 0.08, 0.55), 29)
		var c := j.get_center()
		var gira := absf(cos(_relogio * 5.0))
		draw_set_transform(O + JANELA.get_center() * (1.0 - k) + (c + Vector2(0, -30)) * k, 0.0, Vector2(maxf(0.08, gira), 1.0) * k)
		intro._moeda(Vector2.ZERO, 90)
		draw_set_transform(O + JANELA.get_center() - JANELA.get_center() * k, 0.0, Vector2(k, k))
		var t := "Abrindo o pagamento do Google..." if Loja.ocupado == "abrindo" else "Confirmando sua compra..."
		intro._texto_cartoon(Vector2(c.x, c.y + 50), t, 26, intro.CREME, intro.f_titulo, 2.0, true)
	draw_set_transform(O)
	# festa da compra
	if _festa > 0.0:
		var a := clampf(_festa, 0.0, 1.0)
		var placa := Rect2(intro.W / 2.0 - 260, 250, 520, 140)        # fundo escuro atrás do "+X moedas" (lê bem)
		intro._caixa(placa.grow(3), Color(intro.CONTORNO, 0.9 * a), 30)
		intro._caixa(placa, Color(0.06, 0.07, 0.2, 0.92 * a), 28, 3, Color(OURO2, a))
		for c in _confete:
			draw_set_transform(O + c.p, c.r, Vector2.ONE)
			if c.moeda:
				draw_circle(Vector2.ZERO, 9, Color("8a5a12", a))
				draw_circle(Vector2.ZERO, 7, Color("f2b536", a))
			else:
				draw_rect(Rect2(-6, -3, 12, 6), Color(c.c, a))
		draw_set_transform(O)
		var esc := 1.0 + 0.25 * maxf(0.0, _festa - 3.0) * 4.0
		var cc := Vector2(intro.W / 2.0, 330)
		draw_set_transform(O + cc, 0.0, Vector2(esc, esc))
		intro._texto_cartoon(Vector2(0, 0), "+%s" % _milhar(_ganhou), 72, OURO2, intro.f_titulo, 3.5, true)
		intro._texto_cartoon(Vector2(0, 42), "MOEDAS!" if not _ganhou_dobro else "MOEDAS!  (EM DOBRO)", 30, Color.WHITE, intro.f_titulo, 2.0, true)
		draw_set_transform(O)

## Monte de moedas (quanto maior o pacote, mais moedas no monte).
func _monte(base: Vector2, n: int, esc := 1.0) -> void:
	var filas := [[0.0], [-0.5, 0.5], [-1.0, 0.0, 1.0], [-1.5, -0.5, 0.5, 1.5]]
	var por_nivel: Array = []
	var resto := n
	while resto > 0:                                   # base larga embaixo, afinando para cima
		var q := mini(resto, mini(4, maxi(1, int(ceil(sqrt(float(resto)))))))
		por_nivel.append(q)
		resto -= q
	por_nivel.sort()
	por_nivel.reverse()
	var nivel := 0
	for qn in por_nivel:
		for x in filas[qn - 1]:
			intro._moeda(base + Vector2(x * 22.0, -nivel * 15.0) * esc, 30.0 * esc)
		nivel += 1

func _sem_conta() -> void:
	var j := JANELA
	var c := j.get_center() + Vector2(0, 20)
	_monte(c + Vector2(0, -80), 10, 1.8)
	intro._texto_cartoon(Vector2(c.x, c.y + 20), "Entre com sua conta para comprar moedas", 30, intro.CREME, intro.f_titulo, 2.0, true)
	intro._texto_cartoon(Vector2(c.x, c.y + 56), "As moedas ficam salvas na sua conta, em qualquer celular.", 19, Color("c9d2ff"), intro.f_texto, 1.2, true)
	_botao(Rect2(c.x - 140, c.y + 86, 280, 62), "Entrar", Color("d9ff9a"), Color("8be03c"), Color("3f8f1a"), _ir_login, 26)

func _faixa_dobro() -> void:
	if not Loja.primeira_em_dobro:
		return
	var j := JANELA
	var r := Rect2(j.position.x + 34, j.position.y + 116, j.size.x - 68, 46)
	var pul := 0.5 + 0.5 * sin(_relogio * 4.0)
	intro._caixa(r.grow(4 + pul * 2), Color(1, 0.85, 0.3, 0.25), 24)
	intro._caixa(r.grow(2), intro.CONTORNO, 22)
	intro._botao_degrade(r, Color("ffb3d9"), Color("e0458f"), Color("7a1450"), 20)
	intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 32), "1ª COMPRA EM DOBRO!  Qualquer pacote vale 2x as moedas", 23, Color.WHITE, intro.f_titulo, 1.8, true)

func _cartoes() -> void:
	var j := JANELA
	var topo := j.position.y + (178.0 if Loja.primeira_em_dobro else 128.0)
	var n := Loja.pacotes.size()
	if n == 0:
		return
	var gap := 14.0
	var w := (j.size.x - 68.0 - gap * (n - 1)) / n
	var h := j.end.y - 70.0 - topo
	for i in n:
		var p: Dictionary = Loja.pacotes[i]
		var r := Rect2(j.position.x + 34 + i * (w + gap), topo, w, h)
		_cartao(r, p, i)

func _cartao(r: Rect2, p: Dictionary, i: int) -> void:
	var cor: Array = CORES[mini(i, CORES.size() - 1)]
	var destaque := str(p.selo) != ""
	if destaque:                                          # cartão em destaque: brilho dourado pulsando
		var pul := 0.5 + 0.5 * sin(_relogio * 3.0 + i)
		intro._caixa(r.grow(6 + pul * 3), Color(1, 0.85, 0.3, 0.22 + 0.15 * pul), 26)
	intro._caixa(Rect2(r.position + Vector2(0, 6), r.size), Color(0, 0, 0, 0.35), 22)
	intro._caixa(r.grow(3), OURO2 if destaque else intro.CONTORNO, 24)
	intro._botao_degrade(r, cor[0], cor[1], cor[2], 22)
	intro._caixa(Rect2(r.position + Vector2(8, 8), Vector2(r.size.x - 16, r.size.y * 0.42)), Color(1, 1, 1, 0.12), 18)
	var cx := r.get_center().x
	# selo
	if destaque:
		var st := "MAIS POPULAR" if p.selo == "popular" else "MELHOR VALOR"
		var tw: float = intro._larg(intro.f_titulo, st, 15) + 26
		var sr := Rect2(cx - tw / 2.0, r.position.y - 14, tw, 28)
		intro._caixa(sr.grow(2), intro.CONTORNO, 14)
		intro._botao_degrade(sr, Color("fff3a6"), Color("f6c343"), Color("b8740f"), 12)
		intro._texto_cartoon(Vector2(cx, sr.position.y + 20), st, 15, Color("5a2a08"), intro.f_titulo, 0.0, true)
	# nome
	intro._texto_cartoon(Vector2(cx, r.position.y + 42), str(p.nome), 24, Color.WHITE, intro.f_titulo, 1.8, true)
	# monte de moedas (cresce com o pacote)
	var n_moedas: int = [3, 5, 7, 10, 14][mini(i, 4)]
	_monte(Vector2(cx, r.position.y + 150), n_moedas, 1.15)
	# quantidade
	var qtd := int(p.moedas)
	var y := r.position.y + 196.0
	if Loja.primeira_em_dobro:
		intro._texto_cartoon(Vector2(cx, y), _milhar(qtd), 20, Color(1, 1, 1, 0.75), intro.f_titulo, 1.2, true)
		var lw: float = intro._larg(intro.f_titulo, _milhar(qtd), 20)
		draw_line(Vector2(cx - lw / 2.0 - 4, y - 7), Vector2(cx + lw / 2.0 + 4, y - 7), Color("ff3b6b"), 3.0, true)
		intro._texto_cartoon(Vector2(cx, y + 36), _milhar(qtd * 2), 34, OURO1, intro.f_titulo, 2.2, true)
	else:
		intro._texto_cartoon(Vector2(cx, y + 20), _milhar(qtd), 36, OURO1, intro.f_titulo, 2.2, true)
	intro._texto_cartoon(Vector2(cx, y + 60), "moedas", 16, Color(1, 1, 1, 0.9), intro.f_texto, 1.0, true)
	# bônus
	if int(p.bonus) > 0:
		var bt := "+%d%% bônus" % int(p.bonus)
		var bw: float = intro._larg(intro.f_titulo, bt, 15) + 22
		var br := Rect2(cx - bw / 2.0, y + 72, bw, 26)
		intro._caixa(br.grow(2), intro.CONTORNO, 13)
		intro._caixa(br, Color("2f7d16"), 12)
		intro._texto_cartoon(Vector2(cx, br.position.y + 19), bt, 15, Color("d9ff9a"), intro.f_titulo, 0.0, true)
	# botão do preço
	var pr := Rect2(r.position.x + 12, r.end.y - 66, r.size.x - 24, 54)
	if Loja.disponivel() and p.get("tem_preco", false):
		_botao(pr, str(p.preco), Color("d9ff9a"), Color("8be03c"), Color("3f8f1a"), func(): _comprar(str(p.id)), 24)
	else:
		# sem a Play Store (PC / app instalado fora da loja) ou ainda buscando o preço: mostra o preço de referência
		var txt := str(p.preco) if str(p.preco) != "" else "..."
		_botao(pr, txt, Color("c9ccd8"), Color("8a8fa3"), Color("4a4e60"), func(): _comprar(str(p.id)), 22)

func _comprar(id: String) -> void:
	intro._clique(true)
	Loja.comprar(id)

func _rodape() -> void:
	var j := JANELA
	var t := "Pagamento seguro pela Google Play. As moedas vão direto para a sua conta."
	if not Loja.disponivel():
		t = "A compra funciona no app instalado pela Google Play."
	intro._texto_cartoon(Vector2(j.get_center().x, j.end.y - 34), t, 15, Color("c9d2ff"), intro.f_texto, 1.0, true)
