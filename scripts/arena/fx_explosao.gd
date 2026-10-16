class_name FxExplosao
extends Node2D
## EXPLOSÃO DE BOMBA (Esqueleto Bombardeiro) — só enfeite, desenhado à mão (sem texturas), leve no celular.
## Duas camadas, cada uma num nó: "chao" (por baixo dos personagens: marca queimada, luz no chão, onda de
## choque) e "ar" (por cima: clarão, bola de fogo, brasas, terra voando, fumaça). A arena chama explodir()
## nas duas. No PvP é só visual: usa o randf() global (nunca o rng da partida).

const DURA := 1.8                      ## segundos da explosão (a marca no chão fica mais: MARCA_DURA)
const MARCA_DURA := 4.0

var camada := "ar"                     ## "ar" ou "chao"
var par_chao: FxExplosao               ## (camada "ar") a camada do chão: a bomba que cai explode nas duas
var _exps: Array = []                  ## {pos, t, esc, bolas, pedras, brasas, fumaca}
var _bombas: Array = []                ## bombas voando: {tex, de, para, t, dur, esc, flip, fogo, giro, altura}
var _raios: Array = []                 ## (Golem) raio de energia pela linha: {de, ate, t, dur, esc, semente}
var _erupcoes: Array = []              ## (Golem) fogo saindo do chão: {pos, t, dur, esc, semente}
var _apagando: Array = []              ## (Golem) rastro de fogo que chegou no fim da linha, baixando até apagar
var _fx: Array = []                    ## (Darian) {tipo: "martelo"|"bloqueio"|"pouso", pos, t, dur, esc, dir, semente}

## Martelada (Darian): clarão dourado, onda de choque, faíscas e lascas. forte = o golpe que arremessa.
func martelada(pos: Vector2, dir: float, forte := false) -> void:
	_fx.append({"tipo": "martelo", "pos": pos, "t": 0.0, "dur": 0.55 if forte else 0.4, "esc": 1.5 if forte else 1.0, "dir": dir, "semente": randf() * 100.0})

## Bloqueio (Darian): escudo de luz dourada na frente do martelo; o fogo bate e espirra para cima e para os lados.
func bloqueio(pos: Vector2, dir: float, cor := Color(1.0, 0.55, 0.12)) -> void:
	_fx.append({"tipo": "bloqueio", "pos": pos, "t": 0.0, "dur": 0.75, "esc": 1.0, "dir": dir, "semente": randf() * 100.0, "cor": cor})

## INVOCAÇÃO: o chão racha num círculo de runas, a luz sobe e o esqueleto sai lá de dentro.
## tema "fogo" (Esqueleto Místico: lava, chamas e brasas) ou "sombra" (Esqueleto Mago: roxo, névoa e almas).
func invocacao(pos: Vector2, tema := "sombra", dur := 1.5) -> void:
	_fx.append({"tipo": "portal", "pos": pos, "t": 0.0, "dur": dur, "esc": 1.0, "dir": 1.0, "semente": randf() * 100.0, "tema": tema})

## CURA (Esqueleto Místico): fio de luz da mão até o aliado, anel no chão e brilhos subindo nele.
func cura(de: Vector2, para: Vector2, dourada := false) -> void:
	_fx.append({"tipo": "cura", "pos": para, "de": de, "t": 0.0, "dur": 1.0, "esc": 1.0, "dir": 1.0, "semente": randf() * 100.0, "dourada": dourada})

## LUZ DIVINA (Guerreira Aura): um raio de luz desce do céu em cima do invocado, com anel sagrado no chão,
## clarão, penas e faíscas douradas subindo. Só visual (o dano é da partida).
func luz_divina(pos: Vector2) -> void:
	_fx.append({"tipo": "luz", "pos": pos, "t": 0.0, "dur": 1.1, "esc": 1.0, "dir": 1.0, "semente": randf() * 100.0})

## RAIO ELÉTRICO do Engenheiro (o mesmo visual da partida): sai do cano, corre até o alvo em curva torta com
## galhos, fica ligado tremendo, eletrocuta o corpo (arcos azuis) e apaga. grosso > 1 = SOBRECARGA.
func raio_eletrico(de: Vector2, para: Vector2, alt_alvo := 90.0, grosso := 1.0) -> void:
	_fx.append({"tipo": "eletrico", "pos": para, "de": de, "t": 0.0, "dur": 0.55, "esc": grosso, "dir": signf(para.x - de.x),
		"semente": randf() * 1000.0, "alt": alt_alvo})

## Queda de quem foi arremessado: poeira, terra e rachadura no chão.
func pouso(pos: Vector2, esc := 1.0) -> void:
	_fx.append({"tipo": "pouso", "pos": pos, "t": 0.0, "dur": 0.7, "esc": esc, "dir": 1.0, "semente": randf() * 100.0})

## A onda de fogo chegou no fim da linha: o rastro não some de uma vez, as chamas baixam e apagam.
func apagar_fogo(x0: float, x: float, y: float, idade: float, semente: float) -> void:
	_apagando.append({"x0": x0, "x": x, "y": y, "idade": idade, "semente": semente, "t": 0.0})

## RAIO DO GOLEM: sai de "de" e vai até ate_x (a ponta da linha), sem corte: nasce, cresce rápido, pulsa,
## solta raios finos e faíscas, explode na ponta e some devagar. Só visual (o dano é da partida).
func raio(de: Vector2, ate_x: float, dur: float, esc := 1.0) -> void:
	_raios.append({"de": de, "ate": ate_x, "t": 0.0, "dur": dur, "esc": esc, "semente": randf() * 100.0})

## ERUPÇÃO DE FOGO: o fogo cravado no chão vira uma coluna alta de chamas que sobe e baixa (com brasas).
func erupcao(pos: Vector2, esc := 1.0, dur := 1.3) -> void:
	_erupcoes.append({"pos": pos, "t": 0.0, "dur": dur, "esc": esc, "semente": randf() * 100.0})

## Bomba voando do arremesso até o chão (por cima de todos), girando, com o pavio pegando fogo e a sombra
## crescendo no chão. Quando toca o chão, explode (o dano é da partida; aqui é só o que se vê e se ouve).
## chao = onde fica a parte do chão da explosão (marca, onda, luz): INF = no próprio ponto de chegada.
## Com chao (arremesso longo) a bomba explode NO CORPO do alvo (fogo no peito) e o chão acende nos pés dele.
func voar_bomba(tex: Texture2D, de: Vector2, para: Vector2, dur: float, esc: float, flip: bool, fogo_na_tex: Vector2, chao := Vector2.INF) -> void:
	var longe := absf(para.x - de.x)
	_bombas.append({"tex": tex, "de": de, "para": para, "t": 0.0, "dur": maxf(0.05, dur), "esc": esc, "flip": flip,
		"fogo": fogo_na_tex, "giro": randf_range(1.2, 2.2) * (-1.0 if flip else 1.0) * (1.0 + longe / 200.0),
		"altura": 36.0 + longe * 0.35, "chao": para if chao == Vector2.INF else chao, "no_corpo": chao != Vector2.INF})

func explodir(pos: Vector2, esc := 1.0, chao_y := INF) -> void:
	if chao_y == INF:
		chao_y = pos.y
	var e := {"pos": pos, "t": 0.0, "esc": esc, "bolas": [], "pedras": [], "brasas": [], "fumaca": []}
	if camada == "ar":
		for i in 20:                    # bolas da bola de fogo (cada uma nasce, se espalha, sobe e esfria)
			var ang := randf_range(-PI, 0.15)
			var vel := Vector2(cos(ang), sin(ang) * 0.85) * randf_range(35.0, 120.0)
			e.bolas.append({"off": Vector2(randf_range(-8.0, 8.0), -randf_range(6.0, 18.0)), "vel": vel,
				"sobe": randf_range(30.0, 75.0), "r": randf_range(11.0, 21.0), "atraso": randf_range(0.0, 0.08),
				"vida": randf_range(0.5, 0.9)})
		for i in 16:                    # terra e pedrinhas arremessadas
			var ang2 := randf_range(-PI * 0.95, -PI * 0.05)
			e.pedras.append({"p": pos + Vector2(randf_range(-8, 8), -4), "v": Vector2(cos(ang2), sin(ang2)) * randf_range(140.0, 380.0),
				"giro": randf_range(-14.0, 14.0), "ang": randf() * TAU, "tam": randf_range(2.0, 5.5),
				"cor": Color(randf_range(0.28, 0.42), randf_range(0.2, 0.3), randf_range(0.12, 0.2)), "chao": chao_y + randf_range(-6.0, 10.0)})
		for i in 34:                    # brasas
			var ang3 := randf_range(-PI, 0.0)
			e.brasas.append({"p": pos + Vector2(0, -12), "v": Vector2(cos(ang3), sin(ang3) * 1.2) * randf_range(120.0, 460.0),
				"vida": randf_range(0.4, 1.1)})
		for i in 14:                    # fumaça: tufos que nascem quando o fogo esfria, sobem devagar e abrem
			e.fumaca.append({"off": Vector2(randf_range(-30.0, 30.0), randf_range(-44.0, -10.0)), "sobe": randf_range(22.0, 50.0),
				"deriva": randf_range(-16.0, 16.0), "r": randf_range(11.0, 18.0), "atraso": randf_range(0.2, 0.5), "cinza": randf_range(0.16, 0.3)})
	_exps.append(e)

func _process(dt: float) -> void:
	var bi := _bombas.size() - 1
	while bi >= 0:
		var bm: Dictionary = _bombas[bi]
		bm.t += dt
		if bm.t >= bm.dur:                                  # chegou: explode aqui
			explodir(bm.para, 1.15 if bm.no_corpo else 1.0, float(bm.chao.y))   # no corpo: maior (impacto); pedras caem no chão
			if par_chao:
				par_chao.explodir(bm.chao)
			Sons.tocar("Mago/som/explosao", 0.95)
			_bombas.remove_at(bi)
		bi -= 1
	var i := _exps.size() - 1
	while i >= 0:
		var e: Dictionary = _exps[i]
		e.t += dt
		for p in e.pedras:
			if p.p.y < p.chao or p.v.y < 0.0:
				p.v.y += 900.0 * dt
				p.p += p.v * dt
				p.ang += p.giro * dt
			else:
				p.p.y = p.chao
		for b in e.brasas:
			b.v *= pow(0.12, dt)        # o ar freia
			b.v.y += 260.0 * dt
			b.p += b.v * dt
		if e.t > (MARCA_DURA if camada == "chao" else DURA):
			_exps.remove_at(i)
		i -= 1
	for r in _raios:
		r.t += dt
	_raios = _raios.filter(func(r): return r.t < r.dur)
	for e2 in _erupcoes:
		e2.t += dt
	_erupcoes = _erupcoes.filter(func(e3): return e3.t < e3.dur)
	for f2 in _fx:
		f2.t += dt
	_fx = _fx.filter(func(f3): return f3.t < f3.dur)
	for a2 in _apagando:
		a2.t += dt
	_apagando = _apagando.filter(func(a3): return a3.t < 0.9)
	var tem := not _exps.is_empty() or not _bombas.is_empty() or not _raios.is_empty() or not _erupcoes.is_empty() or not _apagando.is_empty() or not _fx.is_empty()
	if tem or _tinha:
		queue_redraw()                 # (uma vez a mais depois da última: apaga o último quadro)
	_tinha = tem

var _tinha := false

func _draw() -> void:
	for e in _exps:
		if camada == "chao":
			_desenhar_chao(e)
		else:
			_desenhar_ar(e)
	for bm in _bombas:
		_desenhar_bomba(bm)
	for e2 in _erupcoes:
		if camada == "chao":
			_desenhar_erupcao_chao(e2)
		else:
			_desenhar_erupcao(e2)
	for f4 in _fx:
		match f4.tipo:
			"martelo": _desenhar_martelada(f4)
			"bloqueio": _desenhar_bloqueio(f4)
			"pouso": _desenhar_pouso(f4)
			"portal": _desenhar_portal(f4)
			"cura": _desenhar_cura(f4)
			"luz": _desenhar_luz_divina(f4)
			"eletrico": _desenhar_eletrico(f4)
	if camada == "ar":
		for a4 in _apagando:
			var kk: float = 1.0 - float(a4.t) / 0.9
			FxExplosao.desenhar_onda_fogo(self, a4.x0, a4.x, a4.y, a4.idade + a4.t, a4.semente, kk * kk)
		for r in _raios:
			_desenhar_raio(r)

# ------------------------------------------------------------------ DARIAN
func _desenhar_martelada(f: Dictionary) -> void:
	var k: float = f.t / f.dur
	var c: Vector2 = f.pos
	var e: float = f.esc
	var sem: float = f.semente
	var a := 1.0 - k
	if camada == "chao":                                    # onda de choque achatada no chão
		draw_colored_polygon(_pts_elipse(c, (30.0 + 120.0 * k) * e, (8.0 + 30.0 * k) * e), Color(1.0, 0.85, 0.45, 0.22 * a))
		draw_arc_elipse(c, (30.0 + 120.0 * k) * e, (8.0 + 30.0 * k) * e, Color(1.0, 0.95, 0.7, 0.8 * a), 3.0)
		return
	var p := c + Vector2(0, -55.0 * e)
	if k < 0.35:                                            # clarão
		var kk := k / 0.35
		draw_circle(p, (40.0 + 60.0 * kk) * e, Color(1.0, 0.9, 0.55, 0.35 * (1.0 - kk)))
		_estrela(p, (55.0 + 50.0 * kk) * e, sem, Color(1.0, 0.97, 0.8, 0.9 * (1.0 - kk)))
		draw_circle(p, 22.0 * e * (1.0 - kk), Color(1, 1, 1, 0.95))
	draw_arc(p, (20.0 + 110.0 * k) * e, 0, TAU, 40, Color(1.0, 0.9, 0.6, 0.7 * a), 4.0 * a + 1.0, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sem * 1000.0)
	for i in 18:                                            # faíscas voando para a frente do golpe
		var ang := rng.randf_range(-1.1, 1.1) + (0.0 if f.dir > 0 else PI)
		var vel := rng.randf_range(160.0, 420.0) * e
		var q: Vector2 = p + Vector2(cos(ang), sin(ang)) * vel * f.t + Vector2(0, 260.0 * f.t * f.t)
		var cauda := Vector2(cos(ang), sin(ang)) * 14.0 * a
		draw_line(q - cauda, q, Color(1.0, 0.85, 0.4, 0.9 * a), 2.5, true)
	for i in 8:                                             # lascas de pedra/osso
		var ang2 := rng.randf_range(-PI * 0.9, -PI * 0.1)
		var q2: Vector2 = c + Vector2(cos(ang2) * rng.randf_range(90.0, 220.0), sin(ang2) * rng.randf_range(150.0, 300.0)) * f.t * e + Vector2(0, 520.0 * f.t * f.t)
		draw_rect(Rect2(q2 - Vector2(3, 3), Vector2(6, 6)), Color(0.45, 0.36, 0.28, a))

func _desenhar_bloqueio(f: Dictionary) -> void:
	var t: float = f.t
	var k: float = t / f.dur
	var a := 1.0 - k * k
	var c: Vector2 = f.pos
	var d: float = f.dir
	var cor: Color = f.get("cor", Color(1.0, 0.55, 0.12))
	if camada == "chao":
		draw_colored_polygon(_pts_elipse(c, 90.0, 22.0), Color(1.0, 0.8, 0.35, 0.3 * a))
		return
	# escudo de luz: arco grosso na frente do martelo, pulsando
	var centro := c + Vector2(d * 5.0, -62.0)
	var r := 108.0 * (0.85 + 0.15 * minf(1.0, t / 0.08))
	# parede de luz atrás do arco (o escudo "segura" o fogo)
	draw_colored_polygon(_pts_elipse(centro + Vector2(d * r * 0.78, 0), 26.0, r * 0.95), Color(1.0, 0.85, 0.45, 0.22 * a))
	draw_colored_polygon(_pts_elipse(centro + Vector2(d * r * 0.82, 0), 10.0, r * 0.8), Color(1.0, 0.97, 0.8, 0.45 * a))
	var a0 := -1.0 if d > 0 else PI - 1.0                  # arco em pé, na FRENTE do martelo
	var a1 := a0 + 2.0
	for i in 4:
		draw_arc(centro, r + i * 8.0, a0, a1, 32, Color(1.0, 0.85, 0.4, (0.7 - i * 0.14) * a), 12.0 - i * 2.5, true)
	draw_arc(centro, r, a0, a1, 32, Color(1, 1, 0.9, 0.95 * a), 3.0, true)
	# runas/brilho no meio do escudo
	_estrela(centro + Vector2(d * r, 0), 34.0 * (1.0 - 0.3 * k), t * 4.0, Color(1, 0.95, 0.75, 0.8 * a))
	# o fogo batendo e espirrando (para cima e para trás de onde veio)
	for j in 5:
		var off := (float(j) - 2.0) * 16.0
		var tam := (1.6 - absf(float(j) - 2.0) * 0.35) * (1.0 - k)
		if tam > 0.1:
			desenhar_chama(self, c + Vector2(d * (75.0 + absf(off) * 0.4), off * 0.3), t * 2.2 + j, tam, d * 22.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f.semente * 1000.0)
	for i in 22:
		var ang := rng.randf_range(-PI * 0.95, -PI * 0.05)
		if d < 0:
			ang = PI - ang
		var vel := rng.randf_range(150.0, 380.0)
		var q: Vector2 = c + Vector2(d * 80.0, -40.0) + Vector2(cos(ang) * vel * t * 0.9 + d * vel * t * 0.3, sin(ang) * vel * t) + Vector2(0, 300.0 * t * t)
		draw_circle(q, 3.2 * a + 0.5, Color(cor.r, cor.g + 0.3 * (1.0 - k), cor.b, 0.9 * a))

func _desenhar_pouso(f: Dictionary) -> void:
	var k: float = f.t / f.dur
	var c: Vector2 = f.pos
	var e: float = f.esc
	var a := 1.0 - k
	if camada == "chao":
		draw_colored_polygon(_pts_elipse(c, (40.0 + 70.0 * k) * e, (10.0 + 16.0 * k) * e), Color(0.25, 0.18, 0.12, 0.35 * a))
		for r in 6:                                          # rachaduras
			var ang := PI * r / 5.0
			var p2: Vector2 = c + Vector2(cos(ang) * 60.0, sin(ang) * 0.0 + 4.0 * sin(r * 2.0)) * e * minf(1.0, k * 4.0)
			draw_line(c, p2, Color(0.15, 0.1, 0.07, 0.7 * a), 2.5, true)
		return
	for i in 12:                                            # nuvens de poeira abrindo para os lados
		var lado := -1.0 if i % 2 == 0 else 1.0
		var q: Vector2 = c + Vector2(lado * (20.0 + 110.0 * k) * (0.6 + 0.4 * (i / 12.0)), -12.0 - 30.0 * k * (i % 3)) * e
		draw_circle(q, (12.0 + 22.0 * k) * e, Color(0.6, 0.5, 0.4, 0.35 * a))

# ------------------------------------------------------------------ INVOCAÇÃO / CURA
func _desenhar_portal(f: Dictionary) -> void:
	var t: float = f.t
	var dur: float = f.dur
	var c: Vector2 = f.pos
	var sem: float = f.semente
	var fogo: bool = f.tema == "fogo"
	var abre := clampf(t / 0.3, 0.0, 1.0)
	abre = 1.0 - pow(1.0 - abre, 3.0)
	var fecha := clampf((dur - t) / 0.45, 0.0, 1.0)
	var a := abre * fecha
	var c1 := Color(1.0, 0.45, 0.08) if fogo else Color(0.6, 0.3, 1.0)        # cor forte
	var c2 := Color(1.0, 0.85, 0.35) if fogo else Color(0.85, 0.7, 1.0)       # cor clara
	var c3 := Color(0.35, 0.05, 0.0) if fogo else Color(0.12, 0.02, 0.25)     # buraco escuro
	var rx := 62.0 * abre
	var ry := 17.0 * abre
	if camada == "chao":
		# luz no chão, buraco escuro e o círculo de runas girando
		draw_colored_polygon(_pts_elipse(c, rx * 2.0, ry * 2.0), Color(c1, 0.16 * a))
		draw_colored_polygon(_pts_elipse(c, rx, ry), Color(c3, 0.85 * a))
		draw_colored_polygon(_pts_elipse(c, rx * 0.75, ry * 0.7), Color(c1, 0.55 * a))
		draw_colored_polygon(_pts_elipse(c, rx * 0.45, ry * 0.4), Color(c2, 0.7 * a))
		draw_arc_elipse(c, rx * 1.3, ry * 1.3, Color(c2, 0.9 * a), 3.0)
		draw_arc_elipse(c, rx * 1.5, ry * 1.5, Color(c1, 0.6 * a), 2.0)
		for i in 10:                                       # runas no anel (giram)
			var ang := t * (2.2 if fogo else -2.2) + i * TAU / 10.0
			var p := c + Vector2(cos(ang) * rx * 1.4, sin(ang) * ry * 1.4)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(4, 0), p + Vector2(0, 5), p + Vector2(-4, 0)]), Color(c2, a))
		# (atrás do esqueleto) coluna de luz e anel de chamas / névoa: ele sobe NA FRENTE disso
		var alt0 := 150.0 * abre
		draw_colored_polygon(PackedVector2Array([c + Vector2(-rx * 0.8, 0), c + Vector2(rx * 0.8, 0), c + Vector2(rx * 0.35, -alt0), c + Vector2(-rx * 0.35, -alt0)]), Color(c1, 0.16 * a))
		draw_colored_polygon(PackedVector2Array([c + Vector2(-rx * 0.4, 0), c + Vector2(rx * 0.4, 0), c + Vector2(rx * 0.12, -alt0 * 1.1), c + Vector2(-rx * 0.12, -alt0 * 1.1)]), Color(c2, 0.22 * a))
		if fogo:
			for j in 5:
				var off0 := (float(j) - 2.0) * 24.0 * abre
				var tam0 := (1.2 - absf(float(j) - 2.0) * 0.25) * a
				if tam0 > 0.1:
					desenhar_chama(self, c + Vector2(off0, -2), t * 1.8 + sem + j, tam0, sin(t * 4.0 + j) * 6.0)
		else:
			for j in 6:
				var fase0 := fmod(t * 0.8 + j * 0.166, 1.0)
				var p0 := c + Vector2(sin(fase0 * 9.0 + j) * 30.0, -fase0 * alt0)
				draw_circle(p0, (16.0 + 10.0 * fase0) * abre, Color(c1, 0.22 * (1.0 - fase0) * a))
				draw_circle(p0, 5.0 * (1.0 - fase0) + 1.0, Color(c2, 0.8 * (1.0 - fase0) * a))
		for r in 8:                                        # rachaduras em brasa saindo do buraco
			var ang2 := r * TAU / 8.0 + sin(sem + r) * 0.3
			var pts := PackedVector2Array([c + Vector2(cos(ang2) * rx * 0.8, sin(ang2) * ry * 0.8)])
			var p2 := pts[0]
			for s in 3:
				p2 += Vector2(cos(ang2 + sin(s * 2.1 + r) * 0.5) * 18.0, sin(ang2) * 5.0) * abre
				pts.append(p2)
			draw_polyline(pts, Color(c1, 0.85 * a), 3.0, true)
			draw_polyline(pts, Color(c2, 0.9 * a), 1.2, true)
		return
	# AR (na frente): faíscas, terra voando e o clarão
	var alt := 170.0 * abre
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sem * 1000.0)
	for i in 26:                                           # faíscas / brasas subindo
		var fase2 := fmod(t * rng.randf_range(0.7, 1.3) + rng.randf(), 1.0)
		var px := c.x + rng.randf_range(-rx, rx) + sin(fase2 * 6.0 + i) * 8.0
		var q := Vector2(px, c.y - fase2 * alt * rng.randf_range(0.6, 1.3))
		draw_circle(q, 2.6 * (1.0 - fase2) + 0.6, Color(c2, 0.95 * (1.0 - fase2) * a))
	if t < 0.5:                                            # terra e pedrinhas jogadas quando o chão abre
		for i in 10:
			var ang3 := rng.randf_range(-PI * 0.92, -PI * 0.08)
			var v := Vector2(cos(ang3), sin(ang3)) * rng.randf_range(120.0, 260.0)
			var q2 := c + v * t + Vector2(0, 520.0 * t * t)
			draw_rect(Rect2(q2 - Vector2(2.5, 2.5), Vector2(5, 5)), Color(0.32, 0.24, 0.18, 1.0 - t * 2.0))
	if t < 0.25:                                           # clarão de abertura
		var k := t / 0.25
		draw_circle(c + Vector2(0, -30), 70.0 * k + 10.0, Color(c2, 0.5 * (1.0 - k)))

func _desenhar_cura(f: Dictionary) -> void:
	var t: float = f.t
	var k: float = t / f.dur
	var a := 1.0 - k * k
	var c: Vector2 = f.pos
	var verde := Color(1.0, 0.82, 0.3) if f.get("dourada", false) else Color(0.35, 1.0, 0.7)
	var claro := Color(1.0, 0.97, 0.8) if f.get("dourada", false) else Color(0.85, 1.0, 0.95)
	if camada == "chao":
		var r := 30.0 + 40.0 * minf(1.0, k * 2.0)
		draw_colored_polygon(_pts_elipse(c, r, r * 0.28), Color(verde, 0.22 * a))
		draw_arc_elipse(c, r, r * 0.28, Color(claro, 0.85 * a), 2.5)
		return
	# fio de luz da mão do Místico até o aliado (ondulando)
	if t < 0.55:
		var de: Vector2 = f.de
		var para := c + Vector2(0, -55)
		var ka := 1.0 - t / 0.55
		var pts := PackedVector2Array()
		for i in 13:
			var s := float(i) / 12.0
			var p := de.lerp(para, s) + Vector2(0, -sin(PI * s) * 40.0 + sin(s * 18.0 + t * 30.0) * 4.0)
			pts.append(p)
		draw_polyline(pts, Color(verde, 0.35 * ka), 10.0, true)
		draw_polyline(pts, Color(claro, 0.9 * ka), 3.0, true)
	# brilhos e cruzes subindo pelo corpo
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f.semente * 1000.0)
	for i in 16:
		var fase := fmod(k * 1.3 + rng.randf(), 1.0)
		var q := c + Vector2(rng.randf_range(-24.0, 24.0), -10.0 - fase * 110.0)
		var tam := 3.5 * (1.0 - fase) + 1.0
		var cor := Color(claro if i % 3 == 0 else verde, (1.0 - fase) * a)
		if i % 4 == 0:
			draw_rect(Rect2(q - Vector2(tam, tam * 0.3), Vector2(tam * 2.0, tam * 0.6)), cor)
			draw_rect(Rect2(q - Vector2(tam * 0.3, tam), Vector2(tam * 0.6, tam * 2.0)), cor)
		else:
			draw_circle(q, tam, cor)
	draw_circle(c + Vector2(0, -50), 34.0 * (0.6 + 0.4 * k), Color(verde, 0.16 * a))

func _desenhar_luz_divina(f: Dictionary) -> void:
	var t: float = f.t
	var dur: float = f.dur
	var c: Vector2 = f.pos
	var desce := clampf(t / 0.12, 0.0, 1.0)                  # o raio chega do céu num instante
	var some := clampf((dur - t) / 0.5, 0.0, 1.0)
	var a := some
	var ouro := Color(1.0, 0.85, 0.35)
	var branco := Color(1.0, 0.98, 0.88)
	if camada == "chao":
		var r := 40.0 + 30.0 * minf(1.0, t * 3.0)
		draw_colored_polygon(_pts_elipse(c, r * 1.8, r * 0.5), Color(ouro, 0.22 * a))
		draw_colored_polygon(_pts_elipse(c, r, r * 0.28), Color(branco, 0.5 * a))
		draw_arc_elipse(c, r * 1.3, r * 0.36, Color(ouro, 0.9 * a), 3.0)
		for i in 8:                                           # estrela de luz no chão girando
			var ang := t * 1.5 + i * TAU / 8.0
			draw_line(c, c + Vector2(cos(ang) * r * 1.6, sin(ang) * r * 0.45), Color(branco, 0.5 * a), 2.0, true)
		return
	var topo := c.y - 720.0
	var y0 := lerpf(topo, c.y - 10.0, desce)
	var larg := 34.0 * (0.8 + 0.2 * sin(t * 30.0)) * (0.6 + 0.4 * some)
	# coluna de luz (camadas, do céu até o chão)
	draw_colored_polygon(PackedVector2Array([Vector2(c.x - larg * 2.2, topo), Vector2(c.x + larg * 2.2, topo), Vector2(c.x + larg * 1.3, y0), Vector2(c.x - larg * 1.3, y0)]), Color(ouro, 0.14 * a))
	draw_colored_polygon(PackedVector2Array([Vector2(c.x - larg, topo), Vector2(c.x + larg, topo), Vector2(c.x + larg * 0.7, y0), Vector2(c.x - larg * 0.7, y0)]), Color(ouro, 0.4 * a))
	draw_colored_polygon(PackedVector2Array([Vector2(c.x - larg * 0.35, topo), Vector2(c.x + larg * 0.35, topo), Vector2(c.x + larg * 0.25, y0), Vector2(c.x - larg * 0.25, y0)]), Color(branco, 0.9 * a))
	if t < 0.3:                                              # clarão do impacto
		var k := t / 0.3
		draw_circle(c + Vector2(0, -45), 50.0 + 70.0 * k, Color(branco, 0.6 * (1.0 - k)))
		_estrela(c + Vector2(0, -45), 70.0 + 40.0 * k, t * 4.0, Color(branco, 0.85 * (1.0 - k)))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f.semente * 1000.0)
	for i in 18:                                             # faíscas douradas subindo
		var fase := fmod(t * rng.randf_range(0.8, 1.4) + rng.randf(), 1.0)
		var q: Vector2 = c + Vector2(rng.randf_range(-40.0, 40.0) + sin(fase * 8.0 + i) * 6.0, -fase * 160.0)
		draw_circle(q, 2.6 * (1.0 - fase) + 0.6, Color(branco if i % 3 == 0 else ouro, (1.0 - fase) * a))
	for i in 5:                                              # penas caindo devagar, balançando
		var fase2 := fmod(t * 0.55 + i * 0.2, 1.0)
		var q2: Vector2 = c + Vector2(rng.randf_range(-55.0, 55.0) + sin(fase2 * 7.0 + i) * 14.0, -150.0 + fase2 * 140.0)
		var ang2 := sin(fase2 * 6.0 + i) * 0.7
		var d := Vector2(cos(ang2), sin(ang2))
		draw_colored_polygon(PackedVector2Array([q2 - d * 9.0, q2 + Vector2(-d.y, d.x) * 3.0, q2 + d * 9.0, q2 - Vector2(-d.y, d.x) * 3.0]), Color(1, 1, 1, 0.85 * a))

func _camadas_raio(pts: PackedVector2Array, alfa: float, larg: float) -> void:
	if pts.size() < 2 or alfa <= 0.01:
		return
	draw_polyline(pts, Color("1a6dff", 0.10 * alfa), 18.0 * larg)
	draw_polyline(pts, Color("22c8ff", 0.28 * alfa), 8.0 * larg)
	draw_polyline(pts, Color("8ff4ff", 0.80 * alfa), 3.4 * larg)
	draw_polyline(pts, Color(1, 1, 1, 0.95 * alfa), maxf(1.0, 1.5 * larg))

func _torto(rng: RandomNumberGenerator, a: Vector2, b: Vector2, n: int, amp: float) -> PackedVector2Array:
	var perp := (b - a).orthogonal().normalized()
	var pts := PackedVector2Array()
	for i in n + 1:
		var k := float(i) / n
		var p := a.lerp(b, k) + Vector2(0, -sin(PI * k) * 10.0)
		if i > 0 and i < n:
			p += perp * rng.randf_range(-amp, amp) * minf(1.0, sin(PI * k) * 2.2)
		pts.append(p)
	return pts

func _desenhar_eletrico(f: Dictionary) -> void:
	var t: float = f.t
	var de: Vector2 = f.de
	var c: Vector2 = f.pos
	var g: float = f.esc
	var alvo := c + Vector2(0, -float(f.alt) * 0.75)
	var chega := clampf(t / 0.09, 0.0, 1.0)                  # 3200 px/s: chega quase na hora
	var some := clampf((f.dur - t) / 0.3, 0.0, 1.0)
	var alfa := some * some
	if camada == "chao":
		draw_colored_polygon(_pts_elipse(Vector2(c.x, c.y), 60.0, 16.0), Color("2ab8ff", 0.16 * alfa))
		draw_colored_polygon(_pts_elipse(Vector2(de.x, c.y), 50.0, 14.0), Color("2ab8ff", 0.1 * alfa))
		return
	var ponta := de.lerp(alvo, chega)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f.semente) + int(t / 0.034) * 7919          # o raio muda de forma ~30x por segundo
	var n := clampi(int(de.distance_to(ponta) / 24.0), 2, 30)
	var pts := _torto(rng, de, ponta, n, 11.0 * (0.6 + 0.4 * alfa))
	_camadas_raio(pts, alfa, g)
	_camadas_raio(_torto(rng, de, ponta, n, 14.0), alfa * 0.45, 0.55 * g)
	for k in 4:                                               # galhos
		var p0: Vector2 = pts[rng.randi_range(1, maxi(1, pts.size() - 2))]
		var ang := rng.randf_range(-1.1, 1.1) + (0.0 if f.dir > 0 else PI)
		_camadas_raio(_torto(rng, p0, p0 + Vector2(cos(ang), sin(ang)) * rng.randf_range(18.0, 46.0), 4, 6.0), alfa * 0.7, 0.4)
	if chega < 1.0:                                           # bola de plasma viajando
		draw_circle(ponta, 16.0 * g, Color("1a8fff", 0.18))
		draw_circle(ponta, 9.0 * g, Color("40eaff", 0.55))
		draw_circle(ponta, 4.5 * g, Color.WHITE)
	# boca do canhão acesa
	var pul := 1.0 + 0.2 * sin(t * 60.0)
	draw_circle(de, 15.0 * pul * alfa + 2.0, Color("00a0ff", 0.25 * alfa))
	draw_circle(de, 8.0 * pul * alfa + 1.0, Color("7ff7ff", 0.7 * alfa))
	if chega >= 1.0:
		# impacto + o corpo eletrocutado (arcos pulando entre pontos do corpo)
		var k2 := clampf((t - 0.09) / 0.25, 0.0, 1.0)
		draw_circle(alvo, (22.0 + 30.0 * k2) * g, Color("40eaff", 0.35 * (1.0 - k2)))
		draw_circle(alvo, 10.0 * g * (1.0 - k2) + 2.0, Color(1, 1, 1, 0.9 * (1.0 - k2)))
		var alt := float(f.alt)
		for q in 4:
			var a1 := c + Vector2(rng.randf_range(-16.0, 16.0), -rng.randf_range(0.1, 0.95) * alt)
			var a2 := c + Vector2(rng.randf_range(-16.0, 16.0), -rng.randf_range(0.1, 0.95) * alt)
			_camadas_raio(_torto(rng, a1, a2, 5, 7.0), alfa * 0.8, 0.45)
		for s in 8:                                           # faíscas espirrando para trás do alvo
			var ang2 := rng.randf_range(-0.9, 0.5) + (0.0 if f.dir > 0 else PI)
			var q2 := alvo + Vector2(cos(ang2), sin(ang2)) * rng.randf_range(60.0, 200.0) * (t - 0.09) + Vector2(0, 200.0 * (t - 0.09) * (t - 0.09))
			draw_circle(q2, 1.8 * alfa + 0.4, Color(0.8, 1.0, 1.0, alfa))

## Contorno de elipse (para a onda de choque no chão).
func draw_arc_elipse(c: Vector2, rx: float, ry: float, cor: Color, larg: float) -> void:
	var pts := _pts_elipse(c, rx, ry)
	pts.append(pts[0])
	draw_polyline(pts, cor, larg, true)

# ------------------------------------------------------------------ RAIO DO GOLEM
func _desenhar_raio(r: Dictionary) -> void:
	var t: float = r.t
	var dur: float = r.dur
	var esc: float = r.esc
	var de: Vector2 = r.de
	var dir := signf(float(r.ate) - de.x) if float(r.ate) != de.x else 1.0
	var comp_total := absf(float(r.ate) - de.x)
	var cresce := clampf(t / 0.14, 0.0, 1.0)                     # atravessa a linha em 0,14 s
	cresce = 1.0 - pow(1.0 - cresce, 3.0)
	var comp := comp_total * cresce
	var some := clampf((dur - t) / 0.3, 0.0, 1.0)                 # some devagar no fim
	var forca := some * (0.9 + 0.1 * sin(t * 38.0))
	var larg := 38.0 * esc * (0.75 + 0.25 * some)
	var sem: float = r.semente
	# faixa com bordas que tremem, afinando no começo e sumindo suave na ponta (nunca corta reto)
	var faixa := func(meia: float, ondula: float) -> PackedVector2Array:
		var cima := PackedVector2Array(); var baixo := PackedVector2Array()
		var n := maxi(8, int(comp / 18.0))
		for i in n + 1:
			var k := float(i) / n
			var x := de.x + dir * comp * k
			var afina := clampf(k * comp / 26.0, 0.3, 1.0) * clampf((1.0 - k) * comp / 70.0, 0.06, 1.0)
			var onda := (sin(k * 23.0 - t * 34.0 + sem) * ondula + sin(k * 57.0 + t * 21.0) * ondula * 0.5) * afina * 0.6   # (nunca cruza o outro lado)
			cima.append(Vector2(x, de.y - meia * afina - onda))
			baixo.append(Vector2(x, de.y + meia * afina + onda * 0.8))
		baixo.reverse()
		cima.append_array(baixo)
		return cima
	if comp < 2.0:
		return
	draw_colored_polygon(faixa.call(larg * 2.9, 7.0), Color(0.55, 0.85, 0.15, 0.14 * forca))      # brilho largo (verde-amarelo)
	draw_colored_polygon(faixa.call(larg * 1.9, 5.5), Color(0.7, 0.95, 0.25, 0.32 * forca))
	draw_colored_polygon(faixa.call(larg * 1.25, 4.0), Color(0.95, 1.0, 0.45, 0.85 * forca))      # corpo amarelo forte
	draw_colored_polygon(faixa.call(larg * 0.8, 2.5), Color(1.0, 1.0, 0.75, 0.95 * forca))
	draw_colored_polygon(faixa.call(larg * 0.4, 1.0), Color(1.0, 1.0, 1.0, 1.0 * forca))          # miolo branco
	# riscos de energia correndo para a frente
	for i in 7:
		var fase := fmod(t * 2.6 + i * 0.37 + sem, 1.0)
		var x0 := de.x + dir * comp * fase
		var dy := sin(i * 2.3 + sem) * larg * 0.55
		draw_line(Vector2(x0, de.y + dy), Vector2(x0 + dir * 70.0 * esc, de.y + dy), Color(1, 1, 0.85, 0.55 * forca), 2.0, true)
	# raios finos que escapam do raio grosso (mudam de forma ~25x por segundo)
	var quadro := int(t * 25.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sem * 1000.0) + quadro * 7919
	for g in 6:
		var px := de.x + dir * comp * rng.randf_range(0.05, 0.95)
		var lado := -1.0 if rng.randf() < 0.5 else 1.0
		var pts := PackedVector2Array([Vector2(px, de.y + lado * larg * 0.6)])
		var p := pts[0]
		for k in 4:
			p += Vector2(dir * rng.randf_range(4.0, 22.0), lado * rng.randf_range(8.0, 18.0) * esc)
			pts.append(p)
		draw_polyline(pts, Color(0.9, 1.0, 0.55, 0.65 * forca), 2.4, true)
		draw_polyline(pts, Color(1, 1, 1, 0.8 * forca), 1.0, true)
	# clarão na saída (mãos) e explosão na ponta
	_estrela(de, larg * 2.2 * (0.9 + 0.2 * sin(t * 30.0)), t * 3.0 + sem, Color(1, 1, 0.8, 0.85 * forca))
	draw_circle(de, larg * 1.1, Color(1, 1, 0.9, 0.9 * forca))
	if cresce >= 1.0:
		var fim := Vector2(de.x + dir * comp, de.y)
		_estrela(fim, larg * 2.6 * (0.85 + 0.25 * sin(t * 26.0 + 1.0)), -t * 2.0 + sem, Color(1, 1, 0.7, 0.7 * forca))
		draw_circle(fim, larg * 1.3, Color(0.9, 1, 0.6, 0.35 * forca))
	# faíscas espirrando pelo caminho
	for s in 14:
		var fase2 := fmod(t * 1.8 + s * 0.071 + sem * 0.1, 1.0)
		var bx := de.x + dir * comp * fmod(s * 0.137 + sem * 0.01, 1.0)
		var sp := Vector2(bx + dir * fase2 * 40.0, de.y + sin(s * 1.7) * larg * 0.4 - fase2 * 46.0 * (1.0 if s % 2 == 0 else -0.7))
		draw_circle(sp, 2.6 * (1.0 - fase2) + 0.6, Color(1, 1, 0.75, 0.9 * (1.0 - fase2) * forca))

## Estrela de pontas finas (clarão de energia).
func _estrela(c: Vector2, r: float, giro: float, cor: Color) -> void:
	var pts := PackedVector2Array()
	var n := 14
	for i in n * 2:
		var a := giro + PI * i / n
		var rr := r if i % 2 == 0 else r * (0.32 + 0.12 * sin(i * 3.1 + giro * 2.0))
		if i % 4 == 0:
			rr *= 1.35
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, cor)

# ------------------------------------------------------------------ ERUPÇÃO DE FOGO (Golem)
func _desenhar_erupcao(e: Dictionary) -> void:
	var t: float = e.t
	var k := clampf(t / 0.18, 0.0, 1.0) * clampf((e.dur - t) / 0.5, 0.0, 1.0)   # sobe rápido, baixa devagar
	var esc: float = e.esc
	var c: Vector2 = e.pos
	var sem: float = e.semente
	draw_circle(c + Vector2(0, -70) * esc, 110.0 * esc * k, Color(1.0, 0.45, 0.1, 0.10))
	for j in 7:                                                 # coluna de chamas (as do meio mais altas)
		var off := (float(j) - 3.0) * 20.0 * esc
		var alt := (3.4 - absf(float(j) - 3.0) * 0.55) * esc * k
		FxExplosao.desenhar_chama(self, c + Vector2(off, 0), t * 1.7 + sem + j * 0.7, maxf(0.05, alt), sin(t * 5.0 + j) * 6.0)
	for s in 22:                                                # brasas subindo em espiral
		var fase := fmod(t * 0.9 + s * 0.0455 + sem * 0.01, 1.0)
		var p := c + Vector2(sin(s * 2.1 + t * 3.0) * 50.0 * esc * fase, -fase * 230.0 * esc)
		draw_circle(p, 2.8 * (1.0 - fase) + 0.6, Color(1.0, 0.8 - fase * 0.5, 0.3, (1.0 - fase) * 0.9 * minf(1.0, k * 2.0)))
	for f in 5:                                                 # fumaça escura saindo por cima
		var fase2 := fmod(t * 0.6 + f * 0.2, 1.0)
		draw_circle(c + Vector2(sin(f * 1.9) * 30.0, -150.0 - fase2 * 90.0) * esc, (18.0 + fase2 * 26.0) * esc,
			Color(0.18, 0.13, 0.12, 0.22 * (1.0 - fase2) * k))

func _desenhar_erupcao_chao(e: Dictionary) -> void:
	var t: float = e.t
	var k := clampf(t / 0.15, 0.0, 1.0) * clampf((e.dur - t) / 0.6, 0.0, 1.0)
	var c: Vector2 = e.pos
	var esc: float = e.esc
	draw_colored_polygon(FxExplosao._pts_elipse(c, 130.0 * esc, 34.0 * esc), Color(1.0, 0.35, 0.05, 0.25 * k))
	draw_colored_polygon(FxExplosao._pts_elipse(c, 70.0 * esc, 18.0 * esc), Color(1.0, 0.8, 0.3, 0.35 * k))
	# rachaduras em brasa saindo do ponto
	for r in 7:
		var a := PI + PI * r / 6.0 * -1.0 + 0.2
		var pts := PackedVector2Array([c])
		var p := c
		for s in 4:
			p += Vector2(cos(a + sin(s * 3.0 + r) * 0.4), sin(a) * 0.25) * 26.0 * esc
			pts.append(p)
		draw_polyline(pts, Color(1.0, 0.45, 0.08, 0.8 * k), 4.0, true)
		draw_polyline(pts, Color(1.0, 0.9, 0.5, 0.9 * k), 1.6, true)

func _desenhar_bomba(bm: Dictionary) -> void:
	var k: float = bm.t / bm.dur
	var de: Vector2 = bm.de
	var para: Vector2 = bm.para
	var esc: float = bm.esc
	var pos := de.lerp(para, k) + Vector2(0, -float(bm.altura) * 4.0 * k * (1.0 - k))
	# sombra no chão: aparece e cresce conforme a bomba desce
	var chao := Vector2(lerpf(de.x, para.x, k), float(bm.chao.y))
	draw_set_transform(chao, 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, 13.0 * (0.5 + 0.5 * k), Color(0, 0, 0, 0.12 + 0.25 * k))
	draw_set_transform(Vector2.ZERO)
	# a bomba girando
	var tex: Texture2D = bm.tex
	var tam := tex.get_size()
	var ang: float = float(bm.giro) * k
	var sx := -esc if bm.flip else esc
	draw_set_transform(pos, ang, Vector2(sx, esc))
	draw_texture(tex, -tam / 2.0)
	draw_set_transform(Vector2.ZERO)
	# fogo do pavio (sempre para cima; a bomba voando deixa a chama "deitada" para trás)
	var fogo_local: Vector2 = (bm.fogo - tam / 2.0) * Vector2(sx, esc)
	var ponta := pos + fogo_local.rotated(ang)
	var vento := (para.x - de.x) / maxf(1.0, absf(para.x - de.x)) * -9.0
	FxExplosao.desenhar_chama(self, ponta, Time.get_ticks_msec() / 1000.0 + float(bm.giro), esc * 0.9, vento)

## Chama de pavio realista (brilho + 4 línguas de fogo tremulando). Usada pela bomba na mão e voando.
## "tam" = escala (1 = tamanho da folha do personagem); "vento" deita a chama para um lado.
static func desenhar_chama(ci: CanvasItem, base: Vector2, t: float, tam: float, vento: float) -> void:
	if tam < 0.08:
		return                                          # pequena demais para desenhar (evita polígono degenerado)
	var tremor := 0.85 + 0.15 * sin(t * 23.0) * sin(t * 7.3 + 1.1)
	ci.draw_circle(base + Vector2(0, -10) * tam, 56.0 * tam * tremor, Color(1.0, 0.4, 0.08, 0.08))
	ci.draw_circle(base + Vector2(0, -10) * tam, 34.0 * tam * tremor, Color(1.0, 0.5, 0.12, 0.13))
	ci.draw_circle(base + Vector2(0, -8) * tam, 18.0 * tam * tremor, Color(1.0, 0.7, 0.3, 0.2))
	var camadas := [
		[23.0, 52.0, Color(0.85, 0.12, 0.02, 0.55), 1.0],
		[17.0, 42.0, Color(1.0, 0.42, 0.05, 0.85), 1.7],
		[11.5, 30.0, Color(1.0, 0.78, 0.2, 0.95), 2.6],
		[6.0, 16.0, Color(1.0, 0.97, 0.8, 1.0), 3.4],
	]
	for c in camadas:
		var larg: float = c[0] * tremor * tam
		var alt: float = c[1] * (0.9 + 0.2 * sin(t * (11.0 + c[3]) + c[3])) * tam
		ci.draw_colored_polygon(_gota(base, larg, alt, t * c[3], vento * tam), c[2])

## ONDA DE FOGO do Golem de Ossos: uma PAREDE de fogo alta correndo pelo chão da linha. Atrás dela fica uma
## rachadura em brasa e um rastro de chamas que vão baixando, com brasas e fumaça subindo. Nada de corte:
## tudo nasce e some aos poucos. x0 = de onde saiu, x = a frente agora.
static func desenhar_onda_fogo(ci: CanvasItem, x0: float, x: float, y: float, idade: float, semente: float, alfa := 1.0) -> void:
	var dir := signf(x - x0) if x != x0 else 1.0
	var dist := absf(x - x0)
	# 1) chão: luz larga + rachadura em brasa (mais quente perto da frente)
	var passo := 18.0
	var n := int(dist / passo)
	for i in n:
		var px := x - dir * i * passo
		var k := float(i) / maxf(1.0, float(n))
		var a := ((1.0 - k) * 0.7 + 0.15) * alfa
		ci.draw_colored_polygon(_pts_elipse(Vector2(px, y), 34.0, 9.0), Color(1.0, 0.3, 0.04, 0.13 * a))
	if n > 1:
		var rach := PackedVector2Array()
		for i in n + 1:
			var px2 := x - dir * i * passo
			rach.append(Vector2(px2, y - 1.0 + sin(i * 1.9 + semente) * 3.0 + sin(i * 4.3) * 1.5))
		ci.draw_polyline(rach, Color(0.55, 0.08, 0.02, 0.9 * alfa), 7.0, true)
		ci.draw_polyline(rach, Color(1.0, 0.45, 0.06, 0.9 * alfa), 4.0, true)
		ci.draw_polyline(rach, Color(1.0, 0.9, 0.55, 0.85 * alfa), 1.6, true)
	# 2) rastro: chamas que vão baixando atrás da frente
	for i in range(1, n, 2):
		var px3 := x - dir * i * passo
		var k2 := float(i) / maxf(1.0, float(n))
		var tam := lerpf(2.1, 0.45, minf(1.0, k2 * 1.3)) * alfa
		if tam > 0.3:
			desenhar_chama(ci, Vector2(px3 + sin(semente + i * 1.7) * 6.0, y), idade * 1.4 + semente + i * 0.37, tam, -dir * 10.0)
	# 3) brasas e fumaça subindo do rastro
	for s in 26:
		var fase := fmod(idade * 0.8 + s * 0.0385 + semente * 0.01, 1.0)
		var bx := x - dir * dist * fmod(s * 0.173 + semente * 0.013, 1.0) * 0.9
		var p := Vector2(bx + sin(s * 2.7 + idade * 2.0) * 14.0, y - 20.0 - fase * 170.0)
		ci.draw_circle(p, 2.6 * (1.0 - fase) + 0.5, Color(1.0, 0.85 - fase * 0.5, 0.35, 0.9 * (1.0 - fase) * alfa))
	for f in 6:
		var fase2 := fmod(idade * 0.5 + f * 0.166, 1.0)
		var fx := x - dir * (30.0 + f * 40.0)
		ci.draw_circle(Vector2(fx + sin(f * 1.3) * 10.0, y - 130.0 - fase2 * 80.0), 16.0 + fase2 * 26.0, Color(0.16, 0.12, 0.11, 0.2 * (1.0 - fase2) * alfa))
	# 4) a FRENTE: parede de fogo alta (as do meio passam de 170 px), com línguas escuras por trás dando volume
	if alfa < 0.999:                                  # apagando: só o rastro baixando (a frente já chegou)
		return
	ci.draw_circle(Vector2(x, y - 70.0), 90.0, Color(1.0, 0.4, 0.08, 0.06))
	for j in 7:
		var off := (float(j) - 3.0) * 15.0
		var alt := 3.5 - absf(float(j) - 3.0) * 0.5
		var fase := idade * 1.9 + semente + j * 0.83
		var trem := 0.9 + 0.1 * sin(fase * 9.0)
		ci.draw_colored_polygon(_gota(Vector2(x + off - dir * 18.0, y), maxf(2.0, 26.0 * alt * 0.42 * trem), maxf(4.0, 58.0 * alt * trem), fase, -dir * 18.0 * alt),
			Color(0.55, 0.06, 0.02, 0.55))                                  # sombra vermelha escura atrás
		desenhar_chama(ci, Vector2(x + off - dir * 10.0, y), fase, alt, -dir * 16.0)
	ci.draw_circle(Vector2(x + dir * 8.0, y - 12.0), 14.0, Color(1.0, 0.95, 0.75, 0.35))
## ONDA DE OSSOS (Titã) / DE TERRA (Sentinela): a terra RACHA pela linha e da rachadura brotam ossos
## (espinhos, costelas, fêmures e uma caveira na frente) — ou lascas de pedra, na terra. Cada osso nasce
## quando a frente passa, fica um instante e afunda de volta; na frente voam torrões e sobe poeira.
## Sem estado: tudo sai da posição (x0 → x), da velocidade e da idade da onda.
static func desenhar_onda_ossos(ci: CanvasItem, x0: float, x: float, y: float, vel: float, idade: float, semente: float, terra: bool) -> void:
	var dir := signf(x - x0) if x != x0 else 1.0
	var dist := absf(x - x0)
	vel = maxf(absf(vel), 60.0)
	var vida := 0.75                                   # quanto tempo cada osso fica à mostra
	var rastro := minf(dist, vel * vida)
	var terra_esc := Color("3a2414")
	# 1) chão: sombra/terra revirada e a RACHADURA que acompanha a onda
	var n_r := maxi(2, int(rastro / 12.0))
	var rach := PackedVector2Array()
	for i in n_r + 1:
		var k := float(i) / n_r
		var px := x - dir * rastro * k
		rach.append(Vector2(px, y + sin(px * 0.21 + semente) * 2.5 + sin(px * 0.057) * 1.5))
		var a := (1.0 - k) * 0.55
		ci.draw_colored_polygon(_pts_elipse(Vector2(px, y + 1.0), 22.0, 6.0), Color(0.16, 0.1, 0.05, 0.18 * a))
	if rach.size() > 1:
		ci.draw_polyline(rach, Color(terra_esc, 0.85), 8.0, true)
		ci.draw_polyline(rach, Color(0.08, 0.04, 0.02, 0.95), 3.5, true)
		if not terra:                                  # brilho fantasmagórico no fundo da fenda dos ossos
			ci.draw_polyline(rach, Color(0.85, 1.0, 0.75, 0.35), 1.0, true)
	# 2) os ossos/lascas: de trás (os mais velhos, já afundando) para a frente
	var passo := 15.0
	var n := int(dist / passo)
	var i0 := maxi(0, n - int(rastro / passo) - 1)
	for i in range(i0, n + 1):
		var h1 := _hash(i * 1.37 + semente)
		var h2 := _hash(i * 2.91 + semente * 3.1)
		var h3 := _hash(i * 4.17 + semente * 7.3)
		var d_i := i * passo + (h1 - 0.5) * 8.0
		if d_i > dist:
			continue
		var idade_i := (dist - d_i) / vel
		var k := 0.0
		if idade_i < 0.07:
			k = 1.0 - pow(1.0 - idade_i / 0.07, 3.0)    # brota rápido
		elif idade_i < 0.35:
			k = 1.0 + 0.08 * sin((idade_i - 0.07) * 30.0) * (0.35 - idade_i)   # treme ao sair
		else:
			k = 1.0 - (idade_i - 0.35) / (vida - 0.35)  # afunda de volta
		if k <= 0.02:
			continue
		var frente := i >= n - 1
		var base := Vector2(x0 + dir * d_i, y + (h2 - 0.5) * 8.0)
		var alt := (44.0 + 34.0 * h2 + (24.0 if frente else 0.0)) * k
		var inc := (h3 - 0.5) * 0.5 + dir * 0.18
		# monte de terra na base
		ci.draw_colored_polygon(_pts_elipse(base + Vector2(0, 1), 18.0 * minf(1.0, k + 0.3), 4.5), Color("4a301a"))
		ci.draw_colored_polygon(_pts_elipse(base + Vector2(-2, -1), 12.0 * minf(1.0, k + 0.3), 2.8), Color("7a5530"))
		if terra:
			_lasca(ci, base, alt, inc, 12.0 + 7.0 * h1)
		else:
			var tipo := int(h1 * 3.0)
			if frente and h3 > 0.45:
				tipo = 3
			_osso(ci, base, alt, inc, tipo, dir, h2)
		# terrinha caindo do osso que acabou de sair
		if idade_i < 0.2:
			for s in 3:
				var f := idade_i / 0.2
				var pp := base + Vector2((s - 1) * 5.0 + dir * f * 6.0, -alt * (0.8 - f * 0.7) - s * 3.0)
				ci.draw_circle(pp, 1.8, Color("5a3a1e", 1.0 - f))
	# 3) frente: torrões voando e poeira subindo
	for j in 9:
		var fase := fmod(idade * 3.2 + j * 0.111, 1.0)
		var hj := _hash(j * 3.3 + semente)
		var pj := Vector2(x - dir * (6.0 + fase * (20.0 + hj * 30.0)), y - sin(fase * PI) * (26.0 + hj * 34.0))
		var cor_t := Color("6a4a2a") if (terra or j % 3 != 0) else Color("efe6d0")
		ci.draw_rect(Rect2(pj - Vector2(2.2, 2.2), Vector2(4.4, 4.4) * (1.0 - fase * 0.4)), Color(cor_t, 1.0 - fase * 0.6))
	for j in 4:
		var fase2 := fmod(idade * 1.6 + j * 0.25, 1.0)
		var pd := Vector2(x - dir * (10.0 + fase2 * 50.0), y - 8.0 - fase2 * 22.0)
		ci.draw_circle(pd, 8.0 + fase2 * 16.0, Color(0.55, 0.45, 0.33, 0.28 * (1.0 - fase2)))

static func _hash(a: float) -> float:
	return fposmod(sin(a * 12.9898 + 4.1414) * 43758.5453, 1.0)

## Um osso saindo da terra: 0 = espinho curvo, 1 = costela, 2 = fêmur, 3 = caveira.
static func _osso(ci: CanvasItem, base: Vector2, alt: float, inc: float, tipo: int, dir: float, h: float) -> void:
	var claro := Color("f3ead6")
	var sombra := Color("c9b892")
	var linha := Color("3e2f22")
	if alt < 8.0:
		return
	match tipo:
		3:                                             # caveira brotando (só a de cima aparece)
			var r := clampf(alt * 0.36, 6.0, 25.0)
			var c := base + Vector2(inc * 6.0, -r * 0.9)
			ci.draw_circle(c, r + 1.6, linha)
			ci.draw_circle(c, r, claro)
			ci.draw_colored_polygon(_pts_elipse(c + Vector2(r * 0.25 * dir, r * 0.25), r * 0.75, r * 0.55), sombra)
			ci.draw_circle(c + Vector2(-r * 0.38, -r * 0.05), r * 0.27, Color("1a1008"))
			ci.draw_circle(c + Vector2(r * 0.38, -r * 0.05), r * 0.27, Color("1a1008"))
			ci.draw_circle(c + Vector2(-r * 0.38, -r * 0.05), r * 0.08, Color(0.8, 1.0, 0.7, 0.9))
			ci.draw_circle(c + Vector2(r * 0.38, -r * 0.05), r * 0.08, Color(0.8, 1.0, 0.7, 0.9))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, r * 0.18), c + Vector2(-r * 0.12, r * 0.42), c + Vector2(r * 0.12, r * 0.42)]), Color("1a1008"))
			for d in 4:
				ci.draw_line(c + Vector2(-r * 0.36 + d * r * 0.24, r * 0.62), c + Vector2(-r * 0.36 + d * r * 0.24, r * 0.92), linha, 1.2)
			_osso(ci, base + Vector2(-r * 1.3, 2), alt * 0.6, -0.5, 0, dir, h)
			_osso(ci, base + Vector2(r * 1.3, 2), alt * 0.55, 0.5, 0, dir, h)
		2:                                             # fêmur: haste reta com as duas cabeças em cima
			var topo := base + Vector2(inc * alt * 0.6, -alt)
			var lado := (topo - base).normalized().orthogonal()
			var w := 4.8
			var pts := PackedVector2Array([base + lado * w * 1.2, topo + lado * w, topo - lado * w, base - lado * w * 1.2])
			ci.draw_colored_polygon(pts, claro)
			pts.append(pts[0])
			ci.draw_polyline(pts, linha, 1.8, true)
			for s in [-1.0, 1.0]:
				var cb: Vector2 = topo + lado * s * w * 1.1 + (topo - base).normalized() * 1.5
				ci.draw_circle(cb, w * 1.25 + 1.4, linha)
				ci.draw_circle(cb, w * 1.25, claro)
			ci.draw_line(base + lado * w * 0.3, topo + lado * w * 0.2, Color(1, 1, 1, 0.6), 1.2)
		_:                                             # espinho curvo (0) ou costela larga e arqueada (1)
			var curva := (0.25 + 0.2 * h) if tipo == 0 else (0.75 + 0.2 * h)
			var larg := 8.5 if tipo == 0 else 6.0
			var lado_c := dir if tipo == 1 else signf(inc + 0.001)
			var esq := PackedVector2Array()
			var dirt := PackedVector2Array()
			var meio := PackedVector2Array()
			var m := 7
			for j in m + 1:
				var t := float(j) / m
				var p := base + Vector2(inc * alt * 0.4 * t + lado_c * curva * alt * 0.5 * sin(t * PI * 0.5) * t, -alt * t)
				var tg := Vector2(inc * alt * 0.4 + lado_c * curva * alt * 0.5, -alt).normalized()
				var nrm := tg.orthogonal()
				var w2 := larg * (1.0 - t * (0.9 if tipo == 0 else 0.55))
				esq.append(p + nrm * w2)
				dirt.append(p - nrm * w2)
				meio.append(p + nrm * w2 * 0.35)
			var poly := PackedVector2Array(esq)
			for j in range(dirt.size() - 1, -1, -1):
				poly.append(dirt[j])
			ci.draw_colored_polygon(poly, claro)
			var somb := PackedVector2Array(meio)
			for j in range(dirt.size() - 1, -1, -1):
				somb.append(dirt[j])
			ci.draw_colored_polygon(somb, sombra)
			poly.append(poly[0])
			ci.draw_polyline(poly, linha, 1.8, true)
			if tipo == 1:                              # ponta arredondada da costela
				ci.draw_circle(esq[m].lerp(dirt[m], 0.5), larg * 0.5, claro)

## Lasca de pedra saindo da terra (onda do Sentinela).
static func _lasca(ci: CanvasItem, base: Vector2, alt: float, inc: float, w: float) -> void:
	if alt < 4.0:
		return
	var topo := base + Vector2(clampf(inc * alt * 0.5, -w * 0.4, w * 0.6), -alt)
	var pts := PackedVector2Array([base + Vector2(-w, 0), base + Vector2(-w * 0.7, -alt * 0.5), topo, base + Vector2(w * 0.75, -alt * 0.42), base + Vector2(w, 0)])
	ci.draw_colored_polygon(pts, Color("4e3c2c"))
	ci.draw_colored_polygon(PackedVector2Array([base + Vector2(-w * 0.2, 0), base + Vector2(-w * 0.45, -alt * 0.5), topo, base + Vector2(w * 0.15, -alt * 0.1)]), Color("7d6a55"))
	ci.draw_line(base + Vector2(-w * 0.45, -alt * 0.5), topo, Color(1, 0.95, 0.8, 0.5), 1.2)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color("2a1a0c"), 2.0, true)

static func _pts_elipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

static func _gota(base: Vector2, larg: float, alt: float, fase: float, vento: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 9
	for i in n + 1:
		var k := float(i) / n
		var meia := larg * sin(PI * (0.35 + 0.65 * (1.0 - k))) * (1.0 - k * 0.85)
		var torto := (sin(fase * 1.7 + k * 3.0) * 4.0 + vento) * k * k
		pts.append(base + Vector2(meia + torto, -alt * k))
	for i in range(n - 1, 0, -1):
		var k := float(i) / n
		var meia := larg * sin(PI * (0.35 + 0.65 * (1.0 - k))) * (1.0 - k * 0.85)
		var torto := (sin(fase * 1.7 + k * 3.0) * 4.0 + vento) * k * k
		pts.append(base + Vector2(-meia + torto, -alt * k))
	return pts

## Chão: luz alaranjada, onda de choque achatada e marca queimada que esfria devagar.
func _desenhar_chao(e: Dictionary) -> void:
	var t: float = e.t
	var c: Vector2 = e.pos
	var s: float = e.esc
	# marca queimada
	var some := clampf(1.0 - (t - 1.0) / (MARCA_DURA - 1.0), 0.0, 1.0)
	_elipse(c + Vector2(0, 2), 38.0 * s, 0.3, Color(0.06, 0.04, 0.03, 0.55 * some))
	_elipse(c + Vector2(0, 2), 22.0 * s, 0.3, Color(0.03, 0.02, 0.02, 0.65 * some))
	var brasa := clampf(1.0 - t / 1.6, 0.0, 1.0)            # o chão fica em brasa e esfria
	if brasa > 0.0:
		_elipse(c + Vector2(0, 1), 22.0 * s, 0.28, Color(1.0, 0.35, 0.05, 0.45 * brasa))
	# luz da explosão no chão
	var luz := clampf(1.0 - t / 0.55, 0.0, 1.0)
	if luz > 0.0:
		_elipse(c, 110.0 * s, 0.3, Color(1.0, 0.55, 0.15, 0.22 * luz))
		_elipse(c, 60.0 * s, 0.3, Color(1.0, 0.75, 0.35, 0.3 * luz))
	# onda de choque
	var k := clampf(t / 0.38, 0.0, 1.0)
	if k < 1.0:
		var r := lerpf(12.0, 100.0, 1.0 - pow(1.0 - k, 3.0)) * s
		var anel := PackedVector2Array()
		for j in 41:
			var a := TAU * j / 40.0
			anel.append(c + Vector2(cos(a) * r, sin(a) * r * 0.32))
		draw_polyline(anel, Color(1.0, 0.85, 0.55, 0.75 * (1.0 - k)), 7.0 * (1.0 - k) + 1.0)
		draw_polyline(anel, Color(1, 1, 1, 0.6 * (1.0 - k)), 2.0)

## Ar: clarão, bola de fogo que sobe e vira fumaça, brasas e terra voando.
func _desenhar_ar(e: Dictionary) -> void:
	var t: float = e.t
	var c: Vector2 = e.pos
	var s: float = e.esc
	# clarão (rápido: um piscar de luz)
	var flash := clampf(1.0 - t / 0.11, 0.0, 1.0)
	if flash > 0.0:
		_bola_suave(c + Vector2(0, -16), 84.0 * s, Color(1.0, 0.8, 0.45), 0.5 * flash)
		_bola_suave(c + Vector2(0, -14), 32.0 * s, Color(1.0, 1.0, 0.92), 1.0 * flash)
	# núcleo da bola de fogo (os primeiros instantes: forte e cheio, depois se desfaz nas bolinhas)
	var kn := clampf(t / 0.32, 0.0, 1.0)
	if kn < 1.0:
		var cor_n := Color(1.0, 0.95, 0.7).lerp(Color(1.0, 0.5, 0.1), kn)
		_bola_suave(c + Vector2(0, -20 - 26.0 * kn) * s, (24.0 + 18.0 * kn) * s, cor_n, 1.0 - kn * kn)
	# fumaça (atrás do fogo): tufos macios que sobem e abrem
	for f in e.fumaca:
		var tf: float = t - float(f.atraso)
		if tf <= 0.0:
			continue
		var kf := clampf(tf / (DURA - float(f.atraso)), 0.0, 1.0)
		var pos: Vector2 = c + f.off * s + Vector2(float(f.deriva) * tf + sin(tf * 2.2 + float(f.r)) * 4.0, -float(f.sobe) * tf) * s
		var g: float = f.cinza
		_bola_suave(pos, (float(f.r) + 22.0 * kf) * s, Color(g, g * 0.96, g * 0.93), 0.5 * sin(PI * kf))
	# bola de fogo: bolinhas que se espalham e sobem, de branco-amarelo a laranja, vermelho e somem
	for b in e.bolas:
		var tb: float = t - float(b.atraso)
		if tb <= 0.0:
			continue
		var kb := clampf(tb / float(b.vida), 0.0, 1.0)
		if kb >= 1.0:
			continue
		var anda: Vector2 = b.vel * (1.0 - exp(-tb * 5.0)) / 5.0           # sai rápido e freia
		var pos2: Vector2 = c + (b.off + anda + Vector2(0, -float(b.sobe) * tb)) * s
		var r2: float = float(b.r) * (0.7 + 0.8 * sqrt(kb)) * s
		var cor: Color
		if kb < 0.2:
			cor = Color(1.0, 0.98, 0.8).lerp(Color(1.0, 0.82, 0.3), kb / 0.2)
		elif kb < 0.55:
			cor = Color(1.0, 0.82, 0.3).lerp(Color(1.0, 0.42, 0.06), (kb - 0.2) / 0.35)
		else:
			cor = Color(1.0, 0.42, 0.06).lerp(Color(0.4, 0.09, 0.03), (kb - 0.55) / 0.45)
		_bola_suave(pos2, r2, cor, 1.0 - pow(kb, 2.0))
		if kb < 0.3:                                              # miolo quente
			_bola_suave(pos2 + Vector2(-1, -2) * s, r2 * 0.45, Color(1.0, 1.0, 0.88), 0.9 * (1.0 - kb / 0.3))
	# brasas
	for br in e.brasas:
		var kr := clampf(t / float(br.vida), 0.0, 1.0)
		if kr >= 1.0:
			continue
		var v: Vector2 = br.v
		var traco := v.normalized() * minf(10.0, v.length() * 0.025)
		var cor2 := Color(1.0, 0.9 - kr * 0.6, 0.45 - kr * 0.45, 1.0 - kr)
		draw_line(br.p - traco, br.p, cor2, 2.2 * (1.0 - kr) + 0.6)
		draw_circle(br.p, 1.6 * (1.0 - kr) + 0.5, Color(1.0, 1.0, 0.8, 1.0 - kr))
	# terra e pedrinhas
	for p in e.pedras:
		var ap := clampf((DURA - t) / 0.6, 0.0, 1.0)
		var tam: float = p.tam
		var pts := PackedVector2Array([Vector2(-tam, -tam * 0.6), Vector2(tam * 0.5, -tam), Vector2(tam, tam * 0.4), Vector2(-tam * 0.3, tam)])
		draw_set_transform(p.p, p.ang)
		draw_colored_polygon(pts, Color(p.cor, ap))
		draw_set_transform(Vector2.ZERO)

## Bola com borda macia (degradê em 4 camadas): fogo e fumaça sem cara de "disco chapado".
func _bola_suave(centro: Vector2, r: float, cor: Color, a: float) -> void:
	if a <= 0.01 or r <= 0.5:
		return
	draw_circle(centro, r, Color(cor, a * 0.22))
	draw_circle(centro, r * 0.8, Color(cor, a * 0.3))
	draw_circle(centro, r * 0.6, Color(cor, a * 0.42))
	draw_circle(centro, r * 0.38, Color(cor, a * 0.6))

func _elipse(centro: Vector2, r: float, achata: float, cor: Color) -> void:
	if cor.a <= 0.005:
		return
	draw_set_transform(centro, 0.0, Vector2(1.0, achata))
	draw_circle(Vector2.ZERO, r, cor)
	draw_set_transform(Vector2.ZERO)
