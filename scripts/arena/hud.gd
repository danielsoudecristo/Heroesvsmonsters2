extends Control
## (também serve para a BATALHA PvP: lá a 2ª barra é o castelo do adversário)
## HUD DA ARENA no estilo do site: painel de ENERGIA, cartas grandes embaixo (com número, nível, nome e custo),
## botão GUARDAR/CARTAS, barra do CASTELO e botões redondos no canto de cima.
## LEVE: tudo é desenhado num único _draw() (nenhum nó por carta). Só redesenha quando algo muda.

const C := preload("res://scripts/arena/config_arena.gd")

# ---------- medidas (tela 1280x720) ----------
const PAINEL := Rect2(10, 548, 116, 162)            ## painel de energia
const CARTA := Vector2(137, 200)                    ## tamanho de cada carta
const CARTA_X0 := 133.0
const CARTA_PASSO := 153.0
const CARTA_Y := 508.0
const GIROS := [-5.0, 2.5, -2.0, 1.5, -2.5, 2.0, -3.5]   ## inclinação de cada carta (graus), como no site
const BARRA := Rect2(138, 666, 584, 40)             ## barra do CASTELO (o seu)
const HORDA := Rect2(730, 666, 258, 40)             ## barra da HORDA (o "castelo" dos monstros: quanto falta do nível)
const ESPIAR := Rect2(996, 666, 196, 40)            ## botão ESPIAR
const BOTOES := {}                                  ## botões redondos do canto (removidos)
const BT_MENU_TAM := Vector2(84, 30)                ## botão ← MENU na barra do CASTELO
const BT_MENU := Rect2(143, 672, 84, 30)            ## à esquerda, no lugar de onde era o ícone

# ---------- cores ----------
const COR_CREME := Color("f1e2c0")
const COR_CONTORNO := Color("2a1a10")
const COR_OURO := Color("f2c14e")
const COR_OURO_ESCURO := Color("b07a1a")
const COR_NAVY := Color("2a2350")
const COR_VERMELHO := Color("d8452e")
const COR_CUSTO := Color("5a2a10")

var arena: Node
var f_titulo: Font
var f_texto: Font
var guardado := false
var vida_lag := 100.0                               # barra branca que "segue" o dano (efeito de golpe)
var horda_lag := 1.0
var desliza := 0.0                                  # 0 = cartas à mostra, 1 = guardadas
var _retratos: Dictionary = {}                      # id -> [textura, região recortada]
const ICONE_MONSTERS := "res://assets_otimizados/Jogo/icone_monsters.png"
const ICONE_GUERREIRO := "res://assets_otimizados/Jogo/icone_guerreiro.png"
const CASTELO_HEROES := "res://assets_otimizados/Jogo/castelo_heroes.png"       ## (ferramentas/icones_barra.gd)
const CASTELO_MONSTERS := "res://assets_otimizados/Jogo/castelo_monsters.png"
var _icones := {}                                   # caminho -> Texture2D (null = não existe)
var _sel_y: Array[float] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]   # quanto cada carta subiu (animação)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE      # toques: _input abaixo (o que não for do HUD segue para a arena)
	process_mode = Node.PROCESS_MODE_ALWAYS         # funciona mesmo com o jogo pausado (para despausar)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(C.W, C.H)
	f_titulo = _fonte(["Fontes/lilita-one-latin-400-normal.woff2"])
	f_texto = _fonte(["Fontes/fredoka-latin-700-normal.woff2", "Fontes/fredoka-latin-600-normal.woff2"])

func _fonte(opcoes: Array) -> Font:
	for o in opcoes:
		var c: String = "res://assets/" + o
		if ResourceLoader.exists(c):
			return load(c)
	return ThemeDB.fallback_font

func _process(dt: float) -> void:
	# escolheu uma carta: as cartas descem na hora para mostrar a arena inteira (fica só a miniatura da escolhida)
	vida_lag = move_toward(vida_lag, arena.vida_castelo, dt * (8.0 if vida_lag > arena.vida_castelo else 200.0))
	horda_lag = move_toward(horda_lag, arena.horda_restante(), dt * 0.25)
	desliza = move_toward(desliza, 1.0 if (guardado or arena.carta_sel >= 0) else 0.0, dt * 2.6)   # ~0,4 s para abrir/fechar o leque
	for i in arena.cartas_dados.size():
		_sel_y[i] = move_toward(_sel_y[i], 16.0 if i == arena.carta_sel else 0.0, dt * 120.0)
	queue_redraw()

# ================================================================= TOQUES
func _input(ev: InputEvent) -> void:
	var pos := C.pos_toque(self, ev)                # (um toque só, mesmo no celular; já no lugar certo da tela larga)
	if not pos.is_finite():
		return
	if toque(pos):
		get_viewport().set_input_as_handled()

## Devolve true se o toque foi no HUD (aí a arena não usa).
func toque(pos: Vector2) -> bool:
	# janelas de pausa/sair abertas (ou a tela de derrota): deixa os botões da janela receberem o toque
	if not visible or arena.get("painel_menu_visivel") == true:
		return false
	var painel_pvp: Variant = arena.get("painel")
	if painel_pvp is Control and (painel_pvp as Control).visible:
		return false
	var sel: Variant = arena.get("selecao")            # janela de escolha de cartas antes da partida
	if sel is Control and (sel as Control).visible:
		return false
	if arena.pegar_energia(pos):                    # energia vem antes de tudo (nunca coloca herói sem querer)
		return true
	for k in BOTOES:
		if pos.distance_to(BOTOES[k]) < 26:
			_botao(k)
			return true
	if ESPIAR.has_point(pos):
		if arena.has_method("pode_espiar"):           # PvP: o botão só existe com tropa sua na arena inimiga
			if not arena.pode_espiar():
				return false
			arena.espiar()
		return true                                   # (campanha: ali fica a barra das ondas)
	if _ret_bt_menu().has_point(pos):
		arena.mostrar_menu_pausa()
		Sons.tocar("Jogo/som/clique", 0.5)
		return true
	if PAINEL.grow(6).has_point(pos):              # o painel de ENERGIA inteiro mostra/guarda as cartas
		guardado = not guardado
		if guardado:
			arena.carta_sel = -1
		Sons.tocar("Jogo/som/clique", 0.5)
		return true
	if guardado and pos.y > C.H - 40 and pos.x < _fim_cartas():
		guardado = false                              # cartas guardadas: tocar na faixa de baixo também traz de volta
		return true
	if arena.carta_sel >= 0 and _ret_mini().has_point(pos):   # tocou na miniatura: cancela e mostra as cartas
		arena.carta_sel = -1
		guardado = false
		return true
	if desliza < 0.05 and arena.carta_sel < 0:
		for i in range(arena.cartas_dados.size() - 1, -1, -1):  # de trás para frente: a da direita fica por cima
			if _ret_carta(i).has_point(pos):
				arena.carta_sel = -1 if arena.carta_sel == i else i
				Sons.tocar("Jogo/som/clique", 0.5)
				return true
	return false

func _botao(k: String) -> void:
	match k:
		"tela":
			var m := DisplayServer.window_get_mode()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if m == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		"menu":
			get_tree().paused = not get_tree().paused
			arena.mostrar_banner("PAUSADO" if get_tree().paused else "", 999 if get_tree().paused else 0.01)
		"vel":
			Engine.time_scale = 2.0 if Engine.time_scale < 1.5 else 1.0

func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var n: int = ev.keycode - KEY_1
		if n >= 0 and n < arena.cartas_dados.size():
			arena.carta_sel = -1 if arena.carta_sel == n else n
			guardado = false
		elif ev.keycode == KEY_ESCAPE:
			arena.carta_sel = -1

## Retângulo de toque de uma carta (sem a inclinação; é perto o bastante).
func _ret_carta(i: int) -> Rect2:
	return Rect2(Vector2(CARTA_X0 + i * passo_carta(arena.cartas_dados.size()), CARTA_Y - _sel_y[i]), CARTA)

## Passo entre as cartas: com 8 ou mais elas se encostam um pouco para caber todas na tela.
func passo_carta(n: int) -> float:
	return minf(CARTA_PASSO, (C.W - CARTA_X0 - CARTA.x - 8.0) / float(maxi(n - 1, 1)))

## Onde termina a última carta da barra (para o toque que traz as cartas de volta).
func _fim_cartas() -> float:
	var n: int = arena.cartas_dados.size()
	if n <= 0:
		return CARTA_X0
	return CARTA_X0 + passo_carta(n) * (n - 1) + CARTA.x

## Abertura da carta i no "leque" (0 = guardada atrás do painel de energia, 1 = no lugar dela).
## As cartas saem uma depois da outra, deslizando para a direita como se fossem distribuídas.
func _abertura(i: int) -> float:
	var n := maxi(arena.cartas_dados.size(), 1)
	var abrir := 1.0 - desliza
	var t := clampf(abrir * 1.6 - float(i) / n * 0.6, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)                  # começa rápido e freia no lugar

## Centro do ícone de energia (para onde as bolas voam).
func alvo_energia() -> Vector2:
	return PAINEL.position + Vector2(58, 62)

## Retângulo de toque do botão ← MENU.
func _ret_bt_menu() -> Rect2:
	return BT_MENU.grow(6)

# ================================================================= DESENHO
func _draw() -> void:
	_desenhar_barra()
	# as que ainda estão no "monte" ficam por baixo; as que já foram distribuídas, por cima
	var ordem := range(arena.cartas_dados.size())
	ordem.sort_custom(func(a, b): return _abertura(a) < _abertura(b) or (_abertura(a) == _abertura(b) and a < b))
	for i in ordem:
		if i != arena.carta_sel:
			_desenhar_carta(i)
	if arena.carta_sel >= 0 and arena.carta_sel < arena.cartas_dados.size():
		_desenhar_carta(arena.carta_sel)            # a escolhida por cima das outras
	draw_set_transform(Vector2.ZERO)
	_desenhar_painel()
	_desenhar_mini()

## Miniatura da carta escolhida, ao lado do painel de energia (tocar nela cancela).
func _ret_mini() -> Rect2:
	return Rect2(PAINEL.end.x + 10, 518, 96, 140)

func _desenhar_mini() -> void:
	var i: int = arena.carta_sel
	if i < 0 or i >= arena.cartas_dados.size() or desliza < 0.6:
		return
	var p: PersonagemDados = arena.cartas_dados[i]
	var r := _ret_mini()
	_caixa(r.grow(4), Color(1, 0.85, 0.3, 0.9), Color(1, 0.95, 0.6), 2, 14)
	_caixa(r, COR_CREME, COR_CONTORNO, 3, 12)
	var ret := Rect2(r.position + Vector2(7, 7), Vector2(r.size.x - 14, 88))
	var c1: Color = p.cores[1] if p.cores.size() > 1 else Color.GRAY
	_caixa(ret, c1, COR_CONTORNO, 2, 8)
	var rt := _retrato(p)
	if not rt.is_empty():
		var q: Rect2 = rt[1]
		var k := minf((ret.size.x - 6) / q.size.x, (ret.size.y - 6) / q.size.y)
		var tam := q.size * k
		draw_texture_rect_region(rt[0], Rect2(ret.position + Vector2((ret.size.x - tam.x) / 2, ret.size.y - tam.y - 2), tam), q)
	_texto(f_titulo, r.position + Vector2(0, 114), p.nome_card(), 15, COR_CONTORNO, 0, COR_CONTORNO, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_texto(f_titulo, r.position + Vector2(0, 134), "✕ cancelar", 12, Color("8a4a2a"), 0, COR_CONTORNO, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)

func _texto(f: Font, pos: Vector2, txt: String, tam: int, cor: Color, contorno := 0, cor_contorno := COR_CONTORNO, largura := -1.0, alinha := HORIZONTAL_ALIGNMENT_LEFT) -> void:
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

## Ícone de energia: círculo vermelho com aro dourado e raio amarelo (o mesmo das bolas do céu).
static func icone_energia(ci: CanvasItem, c: Vector2, r: float, alfa := 1.0) -> void:
	ci.draw_circle(c, r * 1.12, Color(1, 0.75, 0.2, 0.25 * alfa))
	ci.draw_circle(c, r, Color(COR_OURO, alfa))
	ci.draw_circle(c, r * 0.84, Color(COR_VERMELHO, alfa))
	ci.draw_circle(c + Vector2(-r * 0.22, -r * 0.25), r * 0.38, Color(1, 0.55, 0.45, 0.35 * alfa))
	var raio := PackedVector2Array([Vector2(0.14, -0.62), Vector2(-0.34, 0.1), Vector2(-0.02, 0.1),
		Vector2(-0.16, 0.62), Vector2(0.34, -0.1), Vector2(0.02, -0.1)])
	for k in raio.size():
		raio[k] = c + raio[k] * r
	ci.draw_colored_polygon(raio, Color(1, 0.93, 0.45, alfa))

func _desenhar_painel() -> void:
	var r := PAINEL
	var t := Time.get_ticks_msec() / 1000.0
	var forte := 1.0 if (guardado or arena.carta_sel >= 0) else 0.55   # com as cartas guardadas, chama mais atenção
	var pulso := 0.5 + 0.5 * sin(t * 3.2)
	# brilho dourado pulsando em volta do painel
	for k in 4:
		_caixa(r.grow(6 + k * 4 + pulso * 3), Color(1, 0.78, 0.25, (0.16 - k * 0.035) * forte * (0.6 + pulso * 0.4)), Color(0, 0, 0, 0), 0, 20 + k * 3)
	_caixa(r.grow(3), COR_OURO.lerp(Color("fff1a8"), pulso * 0.5 * forte), COR_CONTORNO, 3, 16)
	_caixa(r.grow(-4), COR_NAVY, Color(0, 0, 0, 0), 0, 12)
	_texto(f_titulo, r.position + Vector2(0, 30), "ENERGIA", 19, COR_OURO, 5, COR_CONTORNO, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	# raios de luz girando atrás do ícone
	var c := alvo_energia()
	for k in 10:
		var a0 := t * 0.8 + k * TAU / 10.0
		var p1 := c + Vector2.from_angle(a0 - 0.12) * 46
		var p2 := c + Vector2.from_angle(a0 + 0.12) * 46
		draw_colored_polygon(PackedVector2Array([c, p1, p2]), Color(1, 0.9, 0.45, 0.10 + 0.08 * pulso * forte))
	icone_energia(self, c, 28 * (1.0 + 0.06 * pulso * forte))
	# brilho que passa de vez em quando no ícone
	var fase_brilho := fmod(t, 2.6) / 2.6
	if fase_brilho < 0.25:
		var kb := fase_brilho / 0.25
		draw_circle(c + Vector2(-14 + kb * 28, -10 + kb * 20), 6.0 * sin(kb * PI), Color(1, 1, 1, 0.8))
	var txt := "∞" if arena.energia_infinita else str(arena.energia)
	_texto(f_titulo, r.position + Vector2(0, 126), txt, 40, Color.WHITE, 8, COR_CONTORNO, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var bt := Rect2(r.position + Vector2(12, 136), Vector2(92, 22))
	_caixa(bt, COR_OURO, COR_CONTORNO, 2, 11)
	_texto(f_titulo, bt.position + Vector2(0, 17), "▲ CARTAS" if (guardado or arena.carta_sel >= 0) else "▼ GUARDAR", 14, COR_CONTORNO, 0, COR_CONTORNO, bt.size.x, HORIZONTAL_ALIGNMENT_CENTER)

func _desenhar_carta(i: int) -> void:
	var p: PersonagemDados = arena.cartas_dados[i]
	var r := _ret_carta(i)
	var e := _abertura(i)
	if e <= 0.01:
		return                                        # guardada atrás do painel
	var sel: bool = i == arena.carta_sel
	var pode: bool = arena.energia_infinita or arena.energia >= p.custo
	var rec: float = arena.recarga.get(p.id, 0.0)
	var de := PAINEL.get_center() + Vector2(10, 10)  # sai de trás do painel de energia
	var centro := de.lerp(r.get_center(), e)
	var giro := lerpf(-18.0, GIROS[i % GIROS.size()] * (0.3 if sel else 1.0), e)
	draw_set_transform(centro, deg_to_rad(giro), Vector2.ONE * lerpf(0.55, 1.0, e))
	var o := -CARTA / 2                               # canto da carta, já no sistema girado
	# moldura
	if sel:
		_caixa(Rect2(o, CARTA).grow(6), Color(1, 0.85, 0.3, 0.9), Color(1, 0.95, 0.6), 3, 20)
	_caixa(Rect2(o, CARTA), COR_CREME, COR_CONTORNO, 4, 16)
	# retrato com o fundo nas cores do personagem
	var ret := Rect2(o + Vector2(10, 12), Vector2(CARTA.x - 20, 118))
	var c0: Color = p.cores[0] if p.cores.size() > 0 else Color.WHITE
	var c1: Color = p.cores[1] if p.cores.size() > 1 else Color.GRAY
	draw_polygon(PackedVector2Array([ret.position, ret.position + Vector2(ret.size.x, 0), ret.end, ret.position + Vector2(0, ret.size.y)]),
		PackedColorArray([c0.lerp(c1, 0.25), c0.lerp(c1, 0.25), c1, c1]))
	var rt := _retrato(p)
	if not rt.is_empty():
		var q: Rect2 = rt[1]
		var cx: float = rt[2]                         # centro do corpo (x) dentro do recorte
		var area := ret.size - Vector2(8, 6)
		var k := area.y / q.size.y                    # o personagem ocupa a altura toda do retrato
		if q.size.x * k > area.x:                     # mais largo que a carta (espada, escudo): corta os lados, centrado no corpo
			var w := area.x / k
			var x0 := clampf(cx - w / 2.0, q.position.x, q.end.x - w)
			q = Rect2(x0, q.position.y, w, q.size.y)
		var tam := q.size * k
		var dest := Rect2(ret.position + Vector2((ret.size.x - tam.x) / 2, ret.size.y - tam.y - 2), tam)
		draw_texture_rect_region(rt[0], dest, q)
	if not pode or rec > 0.0:
		draw_rect(ret, Color(0, 0, 0, 0.45))
	if rec > 0.0:
		var fr := rec / maxf(p.recarga, 0.01)
		draw_rect(Rect2(ret.position, Vector2(ret.size.x, ret.size.y * fr)), Color(0, 0, 0, 0.35))
		_texto(f_titulo, ret.position + Vector2(0, 70), "%d" % ceili(rec), 34, Color.WHITE, 7, COR_CONTORNO, ret.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_caixa(ret, Color(0, 0, 0, 0), COR_CONTORNO, 3, 10)
	# nível
	var nv: int = arena.nivel_da_carta(p.id)
	_texto(f_titulo, ret.position + Vector2(6, ret.size.y - 8), "Nv %d" % nv, 20, Color("6be04a"), 6, COR_CONTORNO)
	# nome
	var placa := Rect2(o + Vector2(8, 128), Vector2(CARTA.x - 16, 32))
	_caixa(placa, Color("2b2622"), COR_CONTORNO, 2, 8)
	var tam_nome := 22 if p.nome_card().length() <= 9 else 18
	_texto(f_titulo, placa.position + Vector2(0, 24), p.nome_card(), tam_nome, COR_CREME, 0, COR_CONTORNO, placa.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	# custo
	icone_energia(self, o + Vector2(34, 180), 14)
	_texto(f_titulo, o + Vector2(54, 194), str(p.custo), 32, COR_CUSTO if pode else Color("c0392b"), 0)
	# número (atalho do teclado)
	var nc := o + Vector2(6, 4)
	draw_circle(nc, 19, COR_OURO)
	draw_circle(nc, 16, Color("1c1630"))
	_texto(f_titulo, nc + Vector2(-20, 9), str(i + 1), 24, Color.WHITE, 0, COR_CONTORNO, 40, HORIZONTAL_ALIGNMENT_CENTER)

## Retrato da carta: o 1º quadro da pose parada, recortado só na parte desenhada (calculado uma vez).
func _retrato(p: PersonagemDados) -> Array:
	if _retratos.has(p.id):
		return _retratos[p.id]
	var r: Array = []
	var a := p.anim_qualquer(["parado", "defender", "andar"])
	if a and a.textura:
		var q := a.retangulo(int(p.extra.get("quadro_retrato", 0)))
		var cx := q.position.x + a.ax                 # x dos pés = centro do corpo
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

func _desenhar_barra() -> void:
	# ---------- CASTELO ----------
	var r := BARRA
	var pvp: bool = arena.get("pvp") == true
	_moldura_barra(r)
	# o SEU castelo (colado na barra de vida, que começa em +126): castelo dos Heroes ou o castelo roxo dos Monsters
	var meu_lado: String = str(arena.get("lado_local")) if pvp else str(arena.lado_jogador)
	if not _icone_png(CASTELO_MONSTERS if meu_lado == "monsters" else CASTELO_HEROES, r.position + Vector2(108, 18), 38.0):
		_icone_castelo(r.position + Vector2(110, 20))
	# botão ← MENU por cima do texto CASTELO (um pouco maior que o texto, sem cobrir a barra)
	_caixa(BT_MENU, Color("3a2850"), COR_OURO, 2, 8)
	_texto(f_titulo, BT_MENU.position + Vector2(0, 21), "← MENU", 15, COR_CREME, 4, COR_CONTORNO, BT_MENU.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var b := Rect2(r.position + Vector2(126, 9), Vector2(300, 22))
	_barra_cheia(b, arena.vida_castelo / C.VIDA_CASTELO, vida_lag / C.VIDA_CASTELO, Color("ff6a55"), Color("c42a22"))
	_texto(f_titulo, b.position + Vector2(0, 17), "%d / %d" % [roundi(arena.vida_castelo), C.VIDA_CASTELO], 15, Color.WHITE, 4, COR_CONTORNO, b.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var pill := Rect2(r.position + Vector2(436, 7), Vector2(140, 26))
	_caixa(pill, Color("2a1830"), COR_OURO_ESCURO, 2, 12)
	_texto(f_titulo, pill.position + Vector2(0, 19), arena.texto_fase(), 13, COR_OURO, 0, COR_CONTORNO, pill.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if not pvp:                                     # CAMPANHA: barra das ondas chegando (no lugar da horda + espiar)
		_desenhar_progresso(Rect2(HORDA.position, Vector2(ESPIAR.end.x - HORDA.position.x, HORDA.size.y)))
		return
	# ---------- HORDA (o "castelo" dos monstros) ----------
	var h := HORDA
	_moldura_barra(h)
	if arena.get("pvp") == true:                  # PvP: é o castelo do adversário
		var o := CASTELO_HEROES if str(arena.get("lado_local")) == "monsters" else CASTELO_MONSTERS
		if not _icone_png(o, h.position + Vector2(22, 18), 38.0):
			_icone_castelo(h.position + Vector2(22, 20), Color("c8f0a8"), Color("3f7a2a"), Color("8a4fe0"))
	else:
		_icone_caveira(h.position + Vector2(22, 20))
	var hb := Rect2(h.position + Vector2(42, 9), Vector2(h.size.x - 54, 22))
	var resto: float = arena.horda_restante()
	_barra_cheia(hb, resto, horda_lag, Color("b483ff"), Color("6a3fd0"))
	_texto(f_titulo, hb.position + Vector2(0, 17), "%d" % roundi(resto * 100), 15, Color.WHITE, 4, COR_CONTORNO, hb.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	# ---------- ESPIAR ----------
	if arena.has_method("pode_espiar"):              # PvP: só com tropa sua viva na arena inimiga (lá vira "MINHA ARENA")
		_botao_espiar_pvp()
		return
	var e := ESPIAR
	var custo: int = arena.custo_espiar() if arena.has_method("custo_espiar") else C.ESPIAR_CUSTO
	var pode: bool = arena.espiar_t <= 0.0 and (arena.energia_infinita or arena.energia >= custo)
	var cor := Color("8a4fe0") if arena.espiar_t <= 0.0 else Color("4a2f7a")
	_caixa(e.grow(2), Color(0, 0, 0, 0), COR_CONTORNO, 2, 22)
	_caixa(e, cor if pode or arena.espiar_t > 0 else Color("5a4a6e"), Color("c8a8ff"), 2, 20)
	_caixa(Rect2(e.position + Vector2(6, 3), Vector2(e.size.x - 12, e.size.y * 0.4)), Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 14)
	var rot := ("ESPIAR · %d" % custo if custo > 0 else "ESPIAR · GRÁTIS") if arena.espiar_t <= 0.0 else "ESPIANDO %ds" % ceili(arena.espiar_t)
	_icone_olho(e.position + Vector2(25, 20))
	# o texto fica entre o olho e o raio (sem raio quando é grátis) e diminui se não couber
	var com_raio: bool = arena.espiar_t <= 0.0 and custo > 0
	var x0 := 46.0
	var larg := e.size.x - x0 - (34.0 if com_raio else 12.0)
	var tam := 18
	while tam > 12 and f_titulo.get_string_size(rot, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x > larg:
		tam -= 1
	_texto(f_titulo, e.position + Vector2(x0, 27), rot, tam, Color.WHITE, 5, COR_CONTORNO, larg, HORIZONTAL_ALIGNMENT_CENTER)
	if com_raio:
		icone_energia(self, e.position + Vector2(e.size.x - 20, 20), 9)

## PvP: ESPIAR (roxo, pulsando) quando você tem tropa viva lá; estando lá, MINHA ARENA (verde) para voltar.
func _botao_espiar_pvp() -> void:
	if not arena.pode_espiar():
		return
	var e := ESPIAR
	var la: bool = arena.espiando
	var pulso := 0.0 if la else 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
	if not la:                                        # brilho em volta chamando o toque
		_caixa(e.grow(3.0 + pulso * 4.0), Color(0.78, 0.6, 1.0, 0.18 + pulso * 0.22), Color(0, 0, 0, 0), 0, 26)
	_caixa(e.grow(2), Color(0, 0, 0, 0), COR_CONTORNO, 2, 22)
	_caixa(e, Color("2f8a3c") if la else Color("8a4fe0").lightened(pulso * 0.12), Color("b8f5a8") if la else Color("c8a8ff"), 2, 20)
	_caixa(Rect2(e.position + Vector2(6, 3), Vector2(e.size.x - 12, e.size.y * 0.4)), Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 14)
	if la:
		var meu := CASTELO_MONSTERS if str(arena.get("lado_local")) == "monsters" else CASTELO_HEROES
		if not _icone_png(meu, e.position + Vector2(25, 20), 30.0):
			_icone_castelo(e.position + Vector2(25, 22))
	else:
		_icone_olho(e.position + Vector2(25, 20))
	var rot := "MINHA ARENA" if la else "ESPIAR"
	var x0 := 46.0
	var larg := e.size.x - x0 - 12.0
	var tam := 18
	while tam > 12 and f_titulo.get_string_size(rot, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x > larg:
		tam -= 1
	_texto(f_titulo, e.position + Vector2(x0, 27), rot, tam, Color.WHITE, 5, COR_CONTORNO, larg, HORIZONTAL_ALIGNMENT_CENTER)

## BARRA DAS ONDAS (campanha): enche da direita para a esquerda conforme o nível avança — a cabeça do
## inimigo (caveira, ou o escudo dos heróis na campanha dos esqueletos) vai andando em direção ao castelo
## e cada bandeira marca onde começa uma onda; a bandeira SOBE quando aquela onda chega. A última é a
## bandeira grande da horda final.
var _prog_vis := 0.0
func _desenhar_progresso(r: Rect2) -> void:
	_moldura_barra(r)
	var t := Time.get_ticks_msec() / 1000.0
	var herois_vem: bool = arena.lado_jogador == "monsters"
	var trilho := Rect2(r.position + Vector2(16, 12), Vector2(r.size.x - 32, 16))
	var alvo: float = arena.progresso_nivel()
	_prog_vis = move_toward(_prog_vis, alvo, get_process_delta_time() * 0.5) if _prog_vis <= alvo else alvo
	# trilho (fundo escuro com textura de terra)
	_caixa(trilho, Color("1a1020"), COR_CONTORNO, 2, 8)
	var dentro := Rect2(trilho.position + Vector2(2, 2), trilho.size - Vector2(4, 4))
	var w := dentro.size.x * clampf(_prog_vis, 0.0, 1.0)
	if w > 1.0:
		var ench := Rect2(Vector2(dentro.end.x - w, dentro.position.y), Vector2(w, dentro.size.y))
		var c1 := Color("4fc24a") if not herois_vem else Color("4a8ae0")
		var c2 := Color("2a7a26") if not herois_vem else Color("2a4f9a")
		_caixa(ench, c2, Color(0, 0, 0, 0), 0, 6)
		_caixa(Rect2(ench.position, Vector2(ench.size.x, ench.size.y * 0.5)), c1, Color(0, 0, 0, 0), 0, 6)
		_caixa(Rect2(ench.position + Vector2(3, 1), Vector2(maxf(ench.size.x - 6, 0), 2)), Color(1, 1, 1, 0.35), Color(0, 0, 0, 0), 0, 2)
	# bandeiras das ondas (a última é a da horda final)
	var marcos: Array = arena.marcos_ondas()
	var iniciadas: int = arena.ondas_iniciadas()
	# cabeça de quem está vindo, andando no trilho (balança como no andar)
	var cx := dentro.end.x - w
	var bal := sin(t * 6.0) * 0.12 if arena.estado == "onda" else 0.0
	var c := Vector2(cx, trilho.get_center().y + sin(t * 6.0) * (1.5 if arena.estado == "onda" else 0.0))
	draw_set_transform(c, bal)
	if not _icone_png(ICONE_GUERREIRO if herois_vem else ICONE_MONSTERS, Vector2(0, -1), 44.0):
		if herois_vem:
			_icone_escudo_heroi(Vector2.ZERO, 1.15)
		else:
			_icone_caveira(Vector2(0, 2), 1.25)
	draw_set_transform(Vector2.ZERO)
	# bandeiras por cima (a cabeça não esconde a bandeira que acabou de subir)
	for i in marcos.size():
		var fx: float = dentro.end.x - dentro.size.x * float(marcos[i])
		var final := i == marcos.size() - 1
		var subiu := iniciadas >= i + 2                 # a onda i+1 (0 = a primeira) já começou
		_bandeira(Vector2(fx, trilho.end.y + 1), subiu, final, t)

## Desenha um ícone PNG (assets_otimizados/Jogo) centrado em c, com lado `tam`. false = não tem o arquivo.
func _icone_png(caminho: String, c: Vector2, tam: float) -> bool:
	if not _icones.has(caminho):
		_icones[caminho] = load(caminho) if ResourceLoader.exists(caminho) else null
	var tex: Texture2D = _icones[caminho]
	if tex == null:
		return false
	draw_texture_rect(tex, Rect2(c - Vector2(tam, tam) / 2.0 + Vector2(1.5, 2.5), Vector2(tam, tam)), false, Color(0, 0, 0, 0.45))   # sombra
	draw_texture_rect(tex, Rect2(c - Vector2(tam, tam) / 2.0, Vector2(tam, tam)), false)
	return true
func _bandeira(base: Vector2, subiu: bool, final: bool, t: float) -> void:
	var alt := 30.0 if final else 25.0
	draw_line(base, base + Vector2(0, -alt), COR_CONTORNO, 3.0)
	draw_line(base, base + Vector2(0, -alt), Color("d8c8a8"), 1.4)
	var topo := base + Vector2(0, -alt + (0.0 if subiu else alt * 0.45))
	var lar := 17.0 if final else 13.0
	var ond := sin(t * 5.0 + base.x) * 2.0 if subiu else 0.0
	var cor := Color("e8402e") if subiu else Color("a07a6a")
	var pts := PackedVector2Array([topo, topo + Vector2(lar, 3 + ond), topo + Vector2(lar * 0.8, 6 + ond * 0.5), topo + Vector2(lar, 10 + ond), topo + Vector2(0, 11)])
	draw_colored_polygon(pts, cor)
	pts.append(pts[0])
	draw_polyline(pts, COR_CONTORNO, 1.6, true)
	if final:
		draw_circle(topo + Vector2(5.5, 5.5), 2.6, Color.WHITE if subiu else Color("c8b8b8"))
	draw_circle(base + Vector2(0, -alt), 2.4, COR_OURO)

func _icone_escudo_heroi(c: Vector2, esc := 1.0) -> void:
	var pts := PackedVector2Array()
	for p in [Vector2(-10, -11), Vector2(10, -11), Vector2(10, 1), Vector2(0, 12), Vector2(-10, 1)]:
		pts.append(c + p * esc)
	var borda := PackedVector2Array(pts)
	borda.append(pts[0])
	draw_polyline(borda, COR_CONTORNO, 5.0 * esc, true)
	draw_colored_polygon(pts, Color("2f5fd0"))
	draw_polyline(borda, COR_OURO, 2.2 * esc, true)
	# flor-de-lis simplificada
	draw_line(c + Vector2(0, -7) * esc, c + Vector2(0, 6) * esc, COR_OURO, 2.2 * esc)
	draw_line(c + Vector2(-5, -1) * esc, c + Vector2(5, -1) * esc, COR_OURO, 2.0 * esc)
	draw_circle(c + Vector2(0, -7) * esc, 2.0 * esc, COR_OURO)

func _moldura_barra(r: Rect2) -> void:
	_caixa(r.grow(2), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 16)
	_caixa(r, Color("2b1a3a"), COR_OURO, 3, 14)
	_caixa(Rect2(r.position + Vector2(4, 3), Vector2(r.size.x - 8, 10)), Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 8)

## Barra com gomos, brilho em cima e a parte branca que segue o dano.
func _barra_cheia(b: Rect2, k: float, k_lag: float, cor_clara: Color, cor_escura: Color) -> void:
	k = clampf(k, 0.0, 1.0)
	k_lag = clampf(maxf(k_lag, k), 0.0, 1.0)
	_caixa(b, Color(0, 0, 0, 0.6), COR_CONTORNO, 2, 10)
	var dentro := Rect2(b.position + Vector2(2, 2), b.size - Vector2(4, 4))
	if k_lag > k:
		_caixa(Rect2(dentro.position, Vector2(dentro.size.x * k_lag, dentro.size.y)), Color(1, 1, 1, 0.75), Color(0, 0, 0, 0), 0, 8)
	if k > 0.0:
		var cheio := Rect2(dentro.position, Vector2(maxf(dentro.size.x * k, 8), dentro.size.y))
		_caixa(cheio, cor_escura, Color(0, 0, 0, 0), 0, 8)
		_caixa(Rect2(cheio.position, Vector2(cheio.size.x, cheio.size.y * 0.55)), cor_clara, Color(0, 0, 0, 0), 0, 8)
		_caixa(Rect2(cheio.position + Vector2(4, 2), Vector2(maxf(cheio.size.x - 8, 0), 3)), Color(1, 1, 1, 0.35), Color(0, 0, 0, 0), 0, 2)
	for i in range(1, 10):
		var x := dentro.position.x + dentro.size.x * i / 10.0
		draw_line(Vector2(x, dentro.position.y + 2), Vector2(x, dentro.end.y - 2), Color(0, 0, 0, 0.28), 1.5)

func _icone_castelo(c: Vector2, cor := Color("f4c6d8"), esc := Color("b05a86"), telhado := Color("e05a6a")) -> void:
	draw_rect(Rect2(c + Vector2(-12, -4), Vector2(24, 14)), cor)
	draw_rect(Rect2(c + Vector2(-14, -10), Vector2(7, 20)), cor)
	draw_rect(Rect2(c + Vector2(7, -10), Vector2(7, 20)), cor)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-15, -10), c + Vector2(-10.5, -17), c + Vector2(-6, -10)]), telhado)
	draw_colored_polygon(PackedVector2Array([c + Vector2(6, -10), c + Vector2(10.5, -17), c + Vector2(15, -10)]), telhado)
	draw_rect(Rect2(c + Vector2(-4, 2), Vector2(8, 8)), esc)
	draw_line(c + Vector2(0, -12), c + Vector2(0, -4), Color("ffd84a"), 2)

func _icone_olho(c: Vector2) -> void:
	var pts := PackedVector2Array()
	for i in 17:
		var a := PI * i / 16.0
		pts.append(c + Vector2(-cos(a) * 13, -sin(a) * 7))
	for i in range(1, 16):
		var a := PI * i / 16.0
		pts.append(c + Vector2(cos(a) * 13, sin(a) * 7))
	draw_colored_polygon(pts, Color.WHITE)
	draw_circle(c, 5, Color("4a2f7a"))
	draw_circle(c + Vector2(-1.5, -1.5), 1.6, Color.WHITE)

func _icone_caveira(c: Vector2, esc := 1.0) -> void:
	if esc != 1.0:                                  # (na barra das ondas ganha contorno para destacar)
		draw_circle(c + Vector2(0, -2) * esc, 13 * esc, COR_CONTORNO)
		draw_rect(Rect2(c + Vector2(-8, 4) * esc, Vector2(16, 9) * esc), COR_CONTORNO)
	draw_circle(c + Vector2(0, -2) * esc, 11 * esc, Color("eeeeee"))
	draw_rect(Rect2(c + Vector2(-6, 5) * esc, Vector2(12, 6) * esc), Color("eeeeee"))
	draw_circle(c + Vector2(-4.5, -2) * esc, 3.2 * esc, Color("2b1a3a"))
	draw_circle(c + Vector2(4.5, -2) * esc, 3.2 * esc, Color("2b1a3a"))
	for x: float in [-3.0, 0.0, 3.0]:
		draw_line(c + Vector2(x, 6) * esc, c + Vector2(x, 11) * esc, Color("2b1a3a"), 1.2)

func _desenhar_botoes() -> void:
	for k in BOTOES:
		var c: Vector2 = BOTOES[k]
		draw_circle(c, 25, COR_CONTORNO)
		draw_circle(c, 22, COR_OURO)
		draw_circle(c + Vector2(0, -4), 16, Color(1, 0.88, 0.5, 0.5))
		match k:
			"menu":
				for y: int in [-7, 0, 7]:
					draw_line(c + Vector2(-10, y), c + Vector2(10, y), COR_CONTORNO, 3.5)
			"tela":
				for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					var p0: Vector2 = c + s * 9
					draw_line(p0, p0 - Vector2(s.x * 6, 0), COR_CONTORNO, 3)
					draw_line(p0, p0 - Vector2(0, s.y * 6), COR_CONTORNO, 3)
			"vel":
				_texto(f_titulo, c + Vector2(-25, 8), "%dx" % int(Engine.time_scale), 20, COR_CONTORNO, 0, COR_CONTORNO, 50, HORIZONTAL_ALIGNMENT_CENTER)
