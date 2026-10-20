extends Control
## MENU DO PERSONAGEM (campanha e PvP): tocar numa tropa sua abre uma pílula pequena em cima da cabeça dela.
## Só ícones (nada de texto na arena): PARAR · ANDAR · VOLTAR | PODER AZUL · PODER VERMELHO.
## DOIS TOQUES rápidos na tropa = remove ela da arena.
##  - Azul = o golpe principal; cada toque acelera os ataques (tocar várias vezes = bem mais rápido, depois volta).
##  - Vermelho = o 2º poder (só quem tem: Darian, Golem, Aura, Místico, Sentinela, Titã, Arqueiros e a
##    SOBRECARGA DE ENERGIA da Elara / Esqueleto Black); gasta moedas da conta.
##  - Remover (dois toques) = tira da arena (não devolve energia).
## Some sozinho depois de uns segundos sem tocar, ou tocando no chão vazio. Quem decide o que cada um faz é a
## arena (arena.comando): na campanha vale na hora; no PvP online vai pela rede para os dois aparelhos.

## Moedas da conta por uso do poder vermelho: o preço SOBE a cada uso na mesma partida (o 1º é barato, usar
## muitos sai caro) e volta ao começo na partida seguinte. O servidor aceita até 500 por uso (32_poder_preco.sql).
const PRECOS_PODER2: Array[int] = [25, 50, 100, 150, 200]
var usos_poder2 := 0                           ## quantos poderes vermelhos já usou nesta partida

## Preço do PRÓXIMO poder vermelho.
func custo_poder2() -> int:
	return PRECOS_PODER2[mini(usos_poder2, PRECOS_PODER2.size() - 1)]

## Partida / nível novo: o preço volta ao começo.
func zerar_preco() -> void:
	usos_poder2 = 0
const FECHA_SOZINHO := 6.0
const D := 46.0                                ## diâmetro de cada botão
const GAP := 8.0
const SEP := 14.0                              ## espaço entre os grupos
const CONTORNO := Color("120c1e")

var arena: Node
var u: Unidade = null
var _t := 0.0                                  # segundos sem tocar
var _abre := 0.0
var _botoes: Array = []                        # [{id, c (centro local)}]
var _aperto := {}                              # id -> 1..0 (animação do toque)
var _aviso := ""                               # "Sem moedas" / "-15"
var _aviso_t := 0.0
var _aviso_cor := Color.WHITE
var _aviso_id := ""
var _relogio := 0.0
var _ultimo_toque_u: Unidade = null           # (dois toques rápidos na mesma tropa = remover)
var _ultimo_toque_t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 5

func aberto() -> bool:
	return visible and u != null

## A arena chama quando tocam numa tropa: abre (ou fecha, se tocou na mesma).
func tocou(x: Unidade) -> void:
	var agora := Time.get_ticks_msec() / 1000.0
	if x == _ultimo_toque_u and agora - _ultimo_toque_t < 0.4:   # DOIS TOQUES rápidos: remove da arena
		_ultimo_toque_u = null
		Sons.tocar("Jogo/som/clique", 0.5)
		arena.comando(x, "remover")
		fechar()
		return
	_ultimo_toque_u = x
	_ultimo_toque_t = agora
	if x == u and visible:
		fechar()
		return
	if u and is_instance_valid(u):
		u.selecionado = false
	u = x
	u.selecionado = true
	_t = 0.0
	_abre = 0.0
	_aviso = ""
	visible = true
	Sons.tocar("Jogo/som/clique", 0.4)

func fechar() -> void:
	visible = false
	if u and is_instance_valid(u):
		u.selecionado = false
	u = null

# ------------------------------------------------------------------ posição
func _tela(p: Vector2) -> Vector2:
	return arena.para_tela(p) if arena.has_method("para_tela") else p

func _lista() -> Array:
	var l := ["parar", "andar", "voltar", "|", "azul"]
	if u.tem_poder2() and Perfil.moedas >= custo_poder2():   # (só aparece se tiver as moedas)
		l.append("vermelho")
	return l

func _ordem_ativa() -> String:
	if arena.get("pvp") == true:
		return "andar" if u.ordem == "" else u.ordem
	return u.ordem if u.ordem in ["andar", "voltar"] else "parar"

func _process(dt: float) -> void:
	if not visible:
		return
	_relogio += dt
	_t += dt
	_abre = move_toward(_abre, 1.0, dt * 6.0)
	_aviso_t = maxf(0.0, _aviso_t - dt)
	for k in _aperto.keys():
		_aperto[k] = maxf(0.0, float(_aperto[k]) - dt * 5.0)
	var fim: bool = arena.get("fim") == true or str(arena.get("estado")) == "derrota"
	if u == null or not is_instance_valid(u) or u.morto or _t > FECHA_SOZINHO or fim:
		fechar()
		return
	# monta os botões e põe a pílula em cima da cabeça (ou embaixo dos pés, se não couber)
	var lista := _lista()
	var larg := 16.0
	for id in lista:
		larg += SEP if id == "|" else D + GAP
	larg -= GAP
	var alt := D + 18.0
	var pes := _tela(u.position)
	var topo := pes.y - (u.anim.ay * absf(u.scale.y) if u.anim else 120.0) + 14.0
	var y := topo - alt - 18.0
	if y < 6.0:
		y = pes.y + 22.0
	var x := clampf(pes.x - larg / 2.0, 6.0, 1274.0 - larg)
	position = Vector2(x, y)
	size = Vector2(larg, alt)
	_botoes.clear()
	var cx := 8.0 + D / 2.0
	for id in lista:
		if id == "|":
			cx += SEP - GAP
			continue
		_botoes.append({"id": id, "c": Vector2(cx, alt / 2.0)})
		cx += D + GAP
	queue_redraw()

# ------------------------------------------------------------------ toques
func _gui_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton) or ev.button_index != MOUSE_BUTTON_LEFT:
		if ev is InputEventScreenTouch or ev is InputEventMouseButton:
			accept_event()
		return
	accept_event()
	if not ev.pressed:
		return
	for b in _botoes:
		if (ev.position as Vector2).distance_to(b.c) <= D / 2.0 + 3.0:
			_apertar(str(b.id))
			return

func _apertar(id: String) -> void:
	_t = 0.0
	_aperto[id] = 1.0
	_aviso_id = id
	if id != "vermelho":
		_avisar(NOMES.get(id, id) if id != "azul" else "Mais rápido! x%s" % str(snappedf(1.0 + minf(1.0, u.pressa + 0.22) * 1.3, 0.1)).replace(".", ","), Color.WHITE)
	match id:
		"vermelho":
			if u.usando_poder2():
				return                                   # já está usando
			var custo := custo_poder2()
			if Perfil.moedas < custo:
				_avisar("Sem moedas", Color("ffd0c8"))
				Sons.tocar("Jogo/som/clique", 0.3)
				return
			_gastar_moedas(custo)
			usos_poder2 += 1
			var nome_poder := "Poder especial!"
			if u.p.id in u.FLECHAS_DE_FOGO:
				nome_poder = "Flechas de fogo!"
			elif u.p.comportamento == "gerador":
				nome_poder = "Sobrecarga de energia!"
			_avisar("%s  -%d" % [nome_poder, custo], Color("fff3c0"))
			Sons.tocar("Jogo/som/clique", 0.8)
			arena.comando(u, "vermelho")
		"remover":
			Sons.tocar("Jogo/som/clique", 0.5)
			arena.comando(u, "remover")
			fechar()
		"azul":
			Sons.tocar("Jogo/som/clique", 0.35)
			arena.comando(u, "azul")
		_:
			Sons.tocar("Jogo/som/clique", 0.45)
			arena.comando(u, id)

func _avisar(txt: String, cor: Color) -> void:
	_aviso = txt
	_aviso_cor = cor
	_aviso_t = 1.1

## Moedas da CONTA: desconta já (a tela mostra na hora) e confirma no servidor (30_poder_moedas.sql).
func _gastar_moedas(n: int) -> void:
	Perfil.moedas -= n
	Perfil.salvar()
	var conta := get_node_or_null("/root/Conta")
	if conta and conta.online_pronto():
		var r: Dictionary = await conta.chamar("gastar_moedas_poder", {"p_qtd": n})
		if r.ok and (r.dados is int or r.dados is float):
			Perfil.moedas = int(r.dados)
			Perfil.salvar()

# ------------------------------------------------------------------ desenho
## Cor de cada botão: [clara, escura] (cada ação tem a sua cor: dá para reconhecer sem ler).
const CORES := {
	"parar": [Color("c9d6f2"), Color("3d4c78")],
	"andar": [Color("b8f27a"), Color("2f8a1e")],
	"voltar": [Color("ffe08a"), Color("c0661a")],
	"azul": [Color("b6ecff"), Color("1a52d0")],
	"vermelho": [Color("ffc49a"), Color("c81e12")],
	"remover": [Color("e09090"), Color("5a1a20")],
}
const NOMES := {"parar": "Parar", "andar": "Andar", "voltar": "Voltar", "azul": "Mais rápido!", "vermelho": "Poder especial!", "remover": "Remover"}

func _caixa(r: Rect2, cor: Color, raio: int, borda := 0, cor_borda := Color()) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = cor
	sb.set_corner_radius_all(raio)
	if borda > 0:
		sb.set_border_width_all(borda)
		sb.border_color = cor_borda
	sb.anti_aliasing = true
	draw_style_box(sb, r)

func _fonte() -> Font:
	var hud = arena.get("hud")
	if hud and hud.get("f_titulo"):
		return hud.f_titulo
	return ThemeDB.fallback_font

static func _ease_back(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	var c1 := 1.9
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)

func _draw() -> void:
	if u == null or not is_instance_valid(u):
		return
	var a := clampf(_abre * 2.0, 0.0, 1.0)
	var pes := _tela(u.position) - position                # (a luz dourada nos pés é a própria tropa que desenha)
	# 2) faixa: moldura escura + borda dourada + vidro azul-noite, com a setinha apontando para a tropa
	var r := Rect2(Vector2.ZERO, size)
	var seta_x := clampf(pes.x, 24.0, size.x - 24.0)
	var em_cima := pes.y > size.y
	var sy := size.y if em_cima else 0.0
	var dy := 9.0 if em_cima else -9.0
	var tri := PackedVector2Array([Vector2(seta_x - 11, sy - signf(dy)), Vector2(seta_x + 11, sy - signf(dy)), Vector2(seta_x, sy + dy)])
	_caixa(Rect2(r.position + Vector2(0, 5), r.size).grow(3), Color(0, 0, 0, 0.35 * a), 30)
	draw_colored_polygon(PackedVector2Array([tri[0] + Vector2(-3, 0), tri[1] + Vector2(3, 0), tri[2] + Vector2(0, signf(dy) * 4.0)]), Color(CONTORNO, a))
	_caixa(r.grow(3), Color(CONTORNO, a), 30)
	_caixa(r.grow(1), Color(0.95, 0.72, 0.25, a), 28)
	_caixa(r, Color(0.09, 0.11, 0.26, 0.96 * a), 27)
	_caixa(Rect2(r.position + Vector2(4, 3), Vector2(r.size.x - 8, r.size.y * 0.45)), Color(1, 1, 1, 0.07 * a), 22)
	draw_colored_polygon(tri, Color(0.95, 0.72, 0.25, a))
	# 3) botões (entram um atrás do outro com um saltinho)
	var ativa := _ordem_ativa()
	var dir_tela := signf((_tela(u.position + Vector2(u._dir() * 10.0, 0)) - _tela(u.position)).x)
	for i in _botoes.size():
		var b: Dictionary = _botoes[i]
		var k := _ease_back(_abre * 1.8 - i * 0.09)
		if k <= 0.01:
			continue
		draw_set_transform(b.c * (1.0 - k), 0.0, Vector2(k, k))
		_botao(str(b.id), b.c, a, str(b.id) == ativa, dir_tela)
	draw_set_transform(Vector2.ZERO)
	# 4) separadores (traço dourado fininho entre os grupos)
	for k2 in range(1, _botoes.size()):
		var x0: float = _botoes[k2 - 1].c.x
		var x1: float = _botoes[k2].c.x
		if x1 - x0 > D + GAP + 1.0:
			var xm := (x0 + x1) / 2.0
			draw_line(Vector2(xm, 13), Vector2(xm, size.y - 13), Color(0.95, 0.72, 0.25, 0.4 * a), 2.0, true)
	# 5) rótulo de quem foi tocado (some sozinho): ensina sem poluir a arena
	if _aviso_t > 0.0:
		var f := _fonte()
		var kk := clampf(_aviso_t / 0.4, 0.0, 1.0)
		var bt: Dictionary = {}
		for b in _botoes:
			if b.id == _aviso_id:
				bt = b
		var cx: float = bt.c.x if not bt.is_empty() else size.x / 2.0
		var tam := 16
		var w := f.get_string_size(_aviso, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x + 22.0
		var tag := Rect2(Vector2(clampf(cx - w / 2.0, -20.0, size.x - w + 20.0), -34.0 - (1.0 - kk) * 6.0), Vector2(w, 26))
		var cor_t: Color = CORES.get(_aviso_id, [Color.WHITE, Color("3d4c78")])[1]
		_caixa(tag.grow(2), Color(CONTORNO, kk), 13)
		_caixa(tag, Color(cor_t.darkened(0.15), kk), 12)
		_caixa(Rect2(tag.position + Vector2(4, 2), Vector2(tag.size.x - 8, 9)), Color(1, 1, 1, 0.18 * kk), 6)
		draw_string_outline(f, tag.position + Vector2(11, 19), _aviso, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, 4, Color(CONTORNO, kk))
		draw_string(f, tag.position + Vector2(11, 19), _aviso, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, Color(_aviso_cor, kk))

## Botão redondo de jogo: sombra, contorno grosso, aro claro, corpo em degradê, brilho em cima e o ícone branco.
func _botao(id: String, c: Vector2, a: float, ativo: bool, dir_tela: float) -> void:
	var ap := float(_aperto.get(id, 0.0))
	var r := D / 2.0 * (0.82 if id == "remover" else 1.0)
	c.y += ap * 2.5                                       # afunda ao tocar
	var cores: Array = CORES[id]
	var clara: Color = cores[0]
	var escura: Color = cores[1]
	if ativo:                                            # ordem atual: brilho dourado em volta
		var p2 := 0.5 + 0.5 * sin(_relogio * 4.0)
		draw_circle(c, r + 8.0 + p2 * 2.0, Color(1.0, 0.82, 0.3, 0.22 * a))
	if id == "azul" and u.pressa > 0.0:                   # azul acelerado: aura pulsando
		draw_circle(c, r + 7.0 + sin(_relogio * 10.0) * 2.0, Color(0.4, 0.8, 1.0, 0.3 * u.pressa * a))
	draw_circle(c + Vector2(0, 3.5 - ap * 2.5), r + 3.0, Color(0, 0, 0, 0.45 * a))       # sombra
	draw_circle(c, r + 3.0, Color(CONTORNO, a))                                          # contorno
	draw_circle(c, r + 1.0, Color(1.0, 0.84, 0.35, a) if ativo else Color(clara.lightened(0.3), a))   # aro
	# corpo em degradê (de baixo escuro para cima claro)
	for k in 7:
		var t := float(k) / 6.0
		draw_circle(c + Vector2(0, -r * 0.22 * t), r * (1.0 - t * 0.42), Color(escura.lerp(clara, t * 0.85), a))
	draw_arc(c, r - 1.5, PI * 0.15, PI * 0.85, 16, Color(0, 0, 0, 0.22 * a), 3.0, true)          # fundo mais escuro
	# brilho de vidro em cima
	draw_set_transform(c + Vector2(-r * 0.12, -r * 0.48), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, r * 0.55, Color(1, 1, 1, 0.38 * a))
	draw_set_transform(Vector2.ZERO)
	# ícone (branco com contorno escuro)
	var w := Color(1, 1, 1, a)
	var sc := r / 23.0
	match id:
		"parar":
			_caixa(Rect2(c - Vector2(9, 9) * sc - Vector2(2, 2), Vector2(18, 18) * sc + Vector2(4, 4)), Color(CONTORNO, a), 5)
			_caixa(Rect2(c - Vector2(9, 9) * sc, Vector2(18, 18) * sc), w, 4)
		"andar":
			_setas(c, dir_tela, sc, a)
		"voltar":
			_setas(c, -dir_tela, sc, a)
		"azul":
			_raio(c, 13.0 * sc, a)
			if u.pressa > 0.0:                            # anel de quanto já acelerou
				draw_arc(c, r + 5.5, -PI / 2.0, -PI / 2.0 + TAU * u.pressa, 36, Color(CONTORNO, a), 6.0, true)
				draw_arc(c, r + 5.5, -PI / 2.0, -PI / 2.0 + TAU * u.pressa, 36, Color(0.5, 0.88, 1.0, a), 3.5, true)
		"vermelho":
			_chama(c + Vector2(0, 1) * sc, 13.0 * sc, a)
			_moeda(c + Vector2(r * 0.72, r * 0.72), a)
		"remover":
			var k2 := 6.5 * sc
			for cor_l in [[Color(CONTORNO, a), 6.5], [w, 3.5]]:
				draw_line(c + Vector2(-k2, -k2), c + Vector2(k2, k2), cor_l[0], cor_l[1], true)
				draw_line(c + Vector2(-k2, k2), c + Vector2(k2, -k2), cor_l[0], cor_l[1], true)

func _setas(c: Vector2, d: float, sc: float, a: float) -> void:
	for camada in [[Color(CONTORNO, a), 7.5], [Color(1, 1, 1, a), 4.0]]:
		for k in 2:
			var x := c.x + d * (-5.0 + k * 9.0) * sc
			draw_polyline(PackedVector2Array([Vector2(x - d * 5.0 * sc, c.y - 9.0 * sc), Vector2(x + d * 4.0 * sc, c.y), Vector2(x - d * 5.0 * sc, c.y + 9.0 * sc)]),
				camada[0], camada[1], true)

func _raio(c: Vector2, s: float, a: float) -> void:
	var pts := PackedVector2Array([Vector2(0.18, -1.0), Vector2(-0.5, 0.14), Vector2(-0.04, 0.14), Vector2(-0.22, 1.0), Vector2(0.52, -0.16), Vector2(0.06, -0.16)])
	var borda := PackedVector2Array()
	for i in pts.size():
		pts[i] = c + pts[i] * s
	borda = pts.duplicate()
	borda.append(pts[0])
	draw_colored_polygon(pts, Color(1, 1, 0.9, a))
	draw_polyline(borda, Color(CONTORNO, a), 2.5, true)

## Chama de fogo (gota com a ponta em cima, balançando), em 3 camadas: contorno, branco-amarelo e o miolo laranja.
func _chama(c: Vector2, s: float, a: float) -> void:
	var balanco := sin(_relogio * 7.0) * 0.12
	for cm in [[1.18, Color(CONTORNO, a)], [1.0, Color(1.0, 0.97, 0.82, a)], [0.62, Color(1.0, 0.62, 0.15, a)]]:
		var k: float = cm[0]
		var pts := PackedVector2Array()
		var n := 18
		for i in n + 1:
			var t := float(i) / n                       # 0..1 em volta da gota
			var ang := PI * 0.5 + t * TAU
			var base := Vector2(cos(ang), sin(ang))
			var y := base.y
			var larg := s * k * (0.62 if y > 0.0 else 0.62 * (1.0 + y * 0.85))   # afina para cima
			var alt := s * k * (0.55 if y > 0.0 else 1.25)
			pts.append(c + Vector2(base.x * larg + balanco * s * k * maxf(0.0, -y), y * alt + s * 0.28))
		draw_colored_polygon(pts, cm[1])
func _moeda(c: Vector2, a: float) -> void:
	draw_circle(c, 9.5, Color(CONTORNO, a))
	draw_circle(c, 8.0, Color("b8740f", a))
	draw_circle(c + Vector2(-0.5, -0.5), 6.5, Color("ffd34d", a))
	var f := _fonte()
	var txt := str(custo_poder2())
	var tam := 10 if txt.length() <= 2 else 8                # (3 dígitos: letra menor para caber na moeda)
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	draw_string(f, c + Vector2(-w / 2.0, 3.6 if tam == 10 else 3.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, Color("5a2a08", a))