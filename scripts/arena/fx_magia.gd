class_name FxMagia
extends Node2D
## MAGIA (Mago, Mago de Fogo, Esqueleto Mago) — a esfera voando e o IMPACTO no inimigo, desenhados à mão
## (sem texturas), leves no celular. Duas camadas, cada uma num nó, igual ao FxExplosao:
##   "chao" (embaixo dos personagens): luz no chão, onda de choque achatada e a marca chamuscada;
##   "ar"   (por cima): a esfera com cauda de cometa, clarão, raios de luz, anel de choque, núcleo,
##          estilhaços de energia, faíscas que sobem e fumaça arcana.
## As partes que brilham vão num nó filho com mistura ADITIVA (luz de verdade, não tinta por cima).
## Só visual: usa um rng próprio (nunca o rng da partida do PvP).

const DURA := 0.95                    ## segundos do impacto
const MARCA_DURA := 2.6               ## a marca no chão fica um pouco mais

## tema -> cores: luz (miolo quase branco), meio, borda (escura) e fumaça
const TEMAS := {
	"arcano": {"luz": Color("eefcff"), "meio": Color("62c8ff"), "borda": Color("2b4dff"), "fumaca": Color(0.30, 0.38, 0.62)},
	"fogo": {"luz": Color("fff1b8"), "meio": Color("ff8a2a"), "borda": Color("c42a08"), "fumaca": Color(0.22, 0.18, 0.16)},
	"sombra": {"luz": Color("f3e6ff"), "meio": Color("a477ff"), "borda": Color("4a17a8"), "fumaca": Color(0.18, 0.11, 0.28)},
}

var camada := "ar"                    ## "ar" ou "chao"
var par_chao: FxMagia                 ## (camada "ar") a camada do chão: o impacto acontece nas duas
var projeteis: Array = []             ## (camada "ar") a lista de projéteis da arena: as esferas são desenhadas aqui

var _imps: Array = []
var _luz: Node2D                      ## filho com mistura aditiva
var _rng := RandomNumberGenerator.new()
var _rng_desenho := RandomNumberGenerator.new()   ## (faíscas estalando: mudam de forma ~40x por segundo)

static func tema_do_tipo(tipo: String) -> String:
	match tipo:
		"magia_fogo": return "fogo"
		"magia_sombra": return "sombra"
	return "arcano"

static func eh_magia(tipo: String) -> bool:
	return tipo == "magia" or tipo == "magia_fogo" or tipo == "magia_sombra"

func _ready() -> void:
	_rng.randomize()
	_luz = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_luz.material = mat
	_luz.draw.connect(_desenhar_luz)
	add_child(_luz)

## A esfera acertou: ponto = onde bateu (frente do corpo, na altura do voo), dir = sentido do voo,
## raio = raio da explosão em área (0 = só o tiro), chao_y = y dos pés do alvo. alvo = quem levou (brilha nele).
func impacto(ponto: Vector2, dir: float, raio: float, tipo: String, chao_y: float, alvo: Node2D = null) -> void:
	var esc := clampf(maxf(raio, 34.0) / 75.0, 0.55, 1.4)
	var e := {"pos": ponto, "dir": dir if dir != 0.0 else 1.0, "t": 0.0, "esc": esc, "tema": tema_do_tipo(tipo),
		"chao": chao_y, "alvo": alvo, "semente": _rng.randi(), "dura": DURA}
	if camada == "ar" and e.tema == "fogo":
		_montar_fogo(e)
		if par_chao:
			par_chao.impacto(ponto, dir, raio, tipo, chao_y, null)
	elif camada == "ar":
		# estilhaços de energia: saem em leque, a maioria PARA FRENTE (no sentido do tiro), e caem
		var cacos: Array = []
		for k in int(11 * esc) + 4:
			var ang := _rng.randf_range(-1.25, 1.25) + (0.0 if e.dir > 0.0 else PI)
			if _rng.randf() < 0.3:
				ang = _rng.randf_range(0.0, TAU)                  # alguns espirram para todo lado
			var v := _rng.randf_range(220.0, 560.0) * esc
			cacos.append({"pos": ponto, "vel": Vector2(cos(ang), sin(ang) * 0.8 - 0.35) * v,
				"vida": _rng.randf_range(0.28, 0.55), "larg": _rng.randf_range(1.6, 3.2)})
		e["cacos"] = cacos
		# faíscas que ficam no ar e sobem devagar, piscando
		var brilhos: Array = []
		for k in int(9 * esc) + 3:
			brilhos.append({"pos": ponto + Vector2(_rng.randf_range(-26, 26), _rng.randf_range(-22, 18)) * esc,
				"vel": Vector2(_rng.randf_range(-30, 30) + e.dir * 25.0, _rng.randf_range(-90, -30)),
				"vida": _rng.randf_range(0.5, 0.9), "fase": _rng.randf() * TAU, "r": _rng.randf_range(1.4, 2.8)})
		e["brilhos"] = brilhos
		# fumaça: tufos que crescem, sobem e somem
		var fumos: Array = []
		for k in 5:
			fumos.append({"off": Vector2(_rng.randf_range(-20, 20) + e.dir * _rng.randf_range(0, 22), _rng.randf_range(-14, 10)) * esc,
				"r": _rng.randf_range(14.0, 24.0) * esc, "atraso": _rng.randf_range(0.04, 0.16), "deriva": _rng.randf_range(-16, 16)})
		e["fumos"] = fumos
		# raios de luz (estrela) do clarão
		var raios: Array = []
		for k in 7:
			raios.append({"ang": _rng.randf_range(0.0, TAU), "comp": _rng.randf_range(0.7, 1.25)})
		e["raios"] = raios
		if par_chao:
			par_chao.impacto(ponto, dir, raio, tipo, chao_y, null)
	_imps.append(e)

## FOGO (Mago de Fogo): a bola de fogo estoura numa explosão de labaredas — bolas de fogo que incham e
## esfriam (branco -> amarelo -> laranja -> vermelho), brasas voando com gravidade, o inimigo PEGA FOGO
## por um instante, chamas no chão e uma coluna de fumaça escura subindo.
func _montar_fogo(e: Dictionary) -> void:
	var esc: float = e.esc
	var ponto: Vector2 = e.pos
	e.dura = 1.45
	var bolas: Array = []                                      # labaredas da explosão
	for k in 8:
		var ang := _rng.randf_range(0.0, TAU)
		bolas.append({"off": Vector2(cos(ang), sin(ang) * 0.75 - 0.25) * _rng.randf_range(4.0, 30.0) * esc + Vector2(e.dir * _rng.randf_range(0.0, 18.0), 0) * esc,
			"r": _rng.randf_range(16.0, 30.0) * esc, "atraso": _rng.randf_range(0.0, 0.1), "vida": _rng.randf_range(0.42, 0.62)})
	e["bolas"] = bolas
	var cacos: Array = []                                      # brasas arremessadas (caem com gravidade)
	for k in int(16 * esc) + 6:
		var ang := _rng.randf_range(-1.3, 1.3) + (0.0 if e.dir > 0.0 else PI)
		if _rng.randf() < 0.35:
			ang = _rng.randf_range(PI, TAU)                    # muitas sobem (fogo vai para cima)
		var v := _rng.randf_range(160.0, 470.0) * esc
		cacos.append({"pos": ponto, "vel": Vector2(cos(ang), sin(ang) * 0.9 - 0.45) * v,
			"vida": _rng.randf_range(0.45, 1.05), "larg": _rng.randf_range(1.4, 2.8)})
	e["cacos"] = cacos
	var brilhos: Array = []                                    # fagulhas subindo no ar quente
	for k in int(12 * esc) + 4:
		brilhos.append({"pos": ponto + Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-20, 20)) * esc,
			"vel": Vector2(_rng.randf_range(-35, 35), _rng.randf_range(-150, -55)),
			"vida": _rng.randf_range(0.6, 1.25), "fase": _rng.randf() * TAU, "r": _rng.randf_range(1.2, 2.4)})
	e["brilhos"] = brilhos
	var fumos: Array = []                                      # coluna de fumaça escura
	for k in 7:
		fumos.append({"off": Vector2(_rng.randf_range(-22, 22) + e.dir * _rng.randf_range(0, 16), _rng.randf_range(-20, 6)) * esc,
			"r": _rng.randf_range(16.0, 28.0) * esc, "atraso": _rng.randf_range(0.12, 0.38), "deriva": _rng.randf_range(-22, 22)})
	e["fumos"] = fumos
	var chamas: Array = []                                     # o corpo do inimigo pegando fogo
	for k in 4:
		chamas.append({"x": _rng.randf_range(-18.0, 18.0), "y": _rng.randf_range(18.0, 75.0), "tam": _rng.randf_range(0.32, 0.5) * esc,
			"fase": _rng.randf() * 10.0, "atraso": _rng.randf_range(0.0, 0.12), "vida": _rng.randf_range(0.7, 1.05)})
	e["chamas"] = chamas
	var chao: Array = []                                       # chamas que ficam no chão um pouco
	for k in 3:
		chao.append({"x": _rng.randf_range(-34.0, 34.0) * esc, "tam": _rng.randf_range(0.26, 0.4) * esc,
			"fase": _rng.randf() * 10.0, "atraso": _rng.randf_range(0.08, 0.2), "vida": _rng.randf_range(0.9, 1.25)})
	e["chao_chamas"] = chao
	e["raios"] = []

func _process(dt: float) -> void:
	var i := _imps.size() - 1
	while i >= 0:
		var e: Dictionary = _imps[i]
		e.t += dt
		var dura: float = MARCA_DURA * (1.4 if e.tema == "fogo" else 1.0) if camada == "chao" else e.dura
		if e.t > dura:
			_imps.remove_at(i)
		elif camada == "ar":
			for c in e.cacos:
				c.vel.y += 1100.0 * dt
				c.vel *= 1.0 - 2.2 * dt                                # o ar freia
				c.pos += c.vel * dt
			for b in e.brilhos:
				b.vel *= 1.0 - 1.4 * dt
				b.pos += b.vel * dt
		i -= 1
	queue_redraw()
	_luz.queue_redraw()

# ===================================================================== DESENHO (mistura normal)
func _draw() -> void:
	if camada == "chao":
		for e in _imps:
			_marca_chao(e)
		return
	for pr in projeteis:                                       # fumaça que a bola de fogo deixa para trás
		if pr.ativo and pr.tipo == "magia_fogo":
			_fumaca_bola_fogo(pr.pos, signf(pr.vel), pr.t)
	for e in _imps:
		_fumaca(e)
		if e.tema == "fogo":
			_chamas_fogo(e)
		else:
			_cacos_contorno(e)

## Fumaça cinza-escura saindo da bola de fogo e ficando para trás no ar.
func _fumaca_bola_fogo(pos: Vector2, dir: float, t: float) -> void:
	var entra := minf(1.0, t * 5.0)
	for s in 7:
		var fs := fmod(t * 1.9 + s / 7.0, 1.0)
		var p := pos + Vector2(-dir * (26.0 + fs * 120.0), -fs * 30.0 + sin(s * 1.7 + t * 3.0) * 5.0)
		var r := 5.0 + 15.0 * fs
		draw_circle(p, r, Color(0.16, 0.13, 0.12, 0.2 * (1.0 - fs) * entra))

## Labaredas (mistura normal: corpo opaco do fogo) — no corpo do inimigo e no chão.
func _chamas_fogo(e: Dictionary) -> void:
	var t: float = e.t
	var alvo = e.alvo
	var base_corpo: Vector2 = alvo.position if is_instance_valid(alvo) and not alvo.get("morto") else Vector2(e.pos.x + e.dir * 16.0, e.chao)
	for c in e.chamas:
		var tl: float = t - c.atraso
		if tl <= 0.0 or tl >= c.vida:
			continue
		var env := minf(1.0, tl / 0.1) * pow(1.0 - tl / c.vida, 0.7)  # acende rápido, apaga devagar
		FxExplosao.desenhar_chama(self, base_corpo + Vector2(c.x, -c.y), tl * 1.6 + c.fase, c.tam * env, -e.dir * 8.0)
	for c in e.chao_chamas:
		var tl: float = t - c.atraso
		if tl <= 0.0 or tl >= c.vida:
			continue
		var env := minf(1.0, tl / 0.15) * pow(1.0 - tl / c.vida, 0.8)
		FxExplosao.desenhar_chama(self, Vector2(e.pos.x + c.x, e.chao - 2.0), tl * 1.4 + c.fase, c.tam * env, sin(tl * 3.0 + c.fase) * 6.0)

## Marca chamuscada no chão (normal): mancha escura achatada que some devagar.
func _marca_chao(e: Dictionary) -> void:
	var k: float = e.t / MARCA_DURA
	var a := 0.32 * (1.0 - k * k) * minf(1.0, e.t * 8.0)
	if a <= 0.01:
		return
	var tm: Dictionary = TEMAS[e.tema]
	var c := Vector2(e.pos.x, e.chao - 2.0)
	draw_set_transform(c, 0.0, Vector2(1.0, 0.26))
	draw_circle(Vector2.ZERO, 46.0 * e.esc, Color(0.05, 0.04, 0.06, a * 0.55))
	draw_circle(Vector2.ZERO, 28.0 * e.esc, Color(tm.borda.darkened(0.6), a * 0.7))
	draw_set_transform(Vector2.ZERO)

## Fumaça arcana: tufos escuros e translúcidos, crescendo e subindo.
func _fumaca(e: Dictionary) -> void:
	var tm: Dictionary = TEMAS[e.tema]
	for f in e.fumos:
		var tl: float = e.t - f.atraso
		if tl <= 0.0:
			continue
		var k := clampf(tl / (e.dura - f.atraso), 0.0, 1.0)
		var a := (0.42 if e.tema == "fogo" else 0.28) * sin(PI * minf(1.0, k * 1.15)) * (1.0 - k)
		if a <= 0.01:
			continue
		var sobe: float = 95.0 if e.tema == "fogo" else 55.0      # (a fumaça do fogo sobe mais: ar quente)
		var p: Vector2 = e.pos + f.off + Vector2(f.deriva * k, -sobe * k * e.esc)
		var r: float = f.r * (0.6 + 1.1 * (1.0 - pow(1.0 - k, 2.0)))
		draw_circle(p, r, Color(tm.fumaca, a))
		draw_circle(p + Vector2(-r * 0.25, -r * 0.3), r * 0.6, Color(tm.fumaca.lightened(0.15), a * 0.6))

## Contorno escuro dos estilhaços (dá corpo: sem ele, sobre o céu claro, a luz some).
func _cacos_contorno(e: Dictionary) -> void:
	for c in e.cacos:
		var k: float = e.t / c.vida
		if k >= 1.0:
			continue
		var cauda: Vector2 = c.pos - c.vel * 0.028
		draw_line(cauda, c.pos, Color(0.03, 0.04, 0.12, 0.35 * (1.0 - k)), c.larg + 2.0, true)

# ===================================================================== DESENHO (luz aditiva)
func _desenhar_luz() -> void:
	if camada == "chao":
		for e in _imps:
			_luz_chao(_luz, e)
		return
	for pr in projeteis:
		if pr.ativo and pr.tipo == "magia_fogo":
			desenhar_bola_fogo(_luz, pr.pos, signf(pr.vel), pr.t)
		elif pr.ativo and eh_magia(pr.tipo):
			desenhar_esfera(_luz, pr.pos, signf(pr.vel), pr.t, tema_do_tipo(pr.tipo))
	for e in _imps:
		if e.tema == "fogo":
			_impacto_fogo_luz(_luz, e)
		else:
			_impacto_luz(_luz, e)

## Explosão de fogo (a parte que BRILHA): clarão, labaredas que incham e esfriam, onda de calor,
## brasas riscando o ar e fagulhas subindo. O inimigo fica iluminado de laranja.
func _impacto_fogo_luz(d: CanvasItem, e: Dictionary) -> void:
	var t: float = e.t
	var s: float = e.esc
	var p: Vector2 = e.pos
	# 1) CLARÃO quente
	var kf := clampf(t / 0.11, 0.0, 1.0)
	if kf < 1.0:
		var af := 1.0 - kf
		d.draw_circle(p, 90.0 * s * (0.7 + 0.4 * kf), Color(1.0, 0.45, 0.08, 0.25 * af))
		d.draw_circle(p, 46.0 * s, Color(1.0, 0.85, 0.5, 0.6 * af))
		d.draw_circle(p, 22.0 * s, Color(1.0, 1.0, 0.92, 0.9 * af))
	# 2) LABAREDAS: cada bola nasce branca, incha, sobe e esfria até o vermelho
	for b in e.bolas:
		var tl: float = t - b.atraso
		if tl <= 0.0 or tl >= b.vida:
			continue
		var k: float = tl / b.vida
		var c: Vector2 = p + b.off * (0.5 + 0.9 * _sai(k)) + Vector2(0, -36.0 * k * s)
		var r: float = b.r * (0.45 + 0.85 * _sai(k))
		var a := pow(1.0 - k, 1.4)
		var quente := _cor_fogo(k)
		d.draw_circle(c, r * 1.45, Color(0.9, 0.18, 0.02, 0.22 * a))
		d.draw_circle(c, r, Color(quente, 0.55 * a))
		d.draw_circle(c, r * 0.55, Color(_cor_fogo(k * 0.5), 0.75 * a * (1.0 - k)))
	# 3) ONDA DE CALOR: anel fino que abre
	var ka := clampf(t / 0.3, 0.0, 1.0)
	if ka < 1.0:
		var ra := (16.0 + 85.0 * _sai(ka)) * s
		d.draw_arc(p, ra, 0.0, TAU, 48, Color(1.0, 0.5, 0.12, 0.38 * (1.0 - ka)), 6.0 * (1.0 - ka) * s + 1.0, true)
	# 4) o inimigo iluminado pelo fogo
	var alvo = e.alvo
	if is_instance_valid(alvo) and t < 0.6:
		var ab := 1.0 - t / 0.6
		d.draw_set_transform(alvo.position + Vector2(0, -50), 0.0, Vector2(0.6, 1.0))
		d.draw_circle(Vector2.ZERO, 64.0, Color(1.0, 0.42, 0.08, 0.2 * ab * ab))
		d.draw_set_transform(Vector2.ZERO)
	# 5) BRASAS voando: risco que vai do amarelo ao vermelho conforme esfria
	for c in e.cacos:
		var kc: float = t / c.vida
		if kc >= 1.0:
			continue
		var ac := 1.0 - kc
		var cor := _cor_fogo(0.2 + kc * 0.7)
		d.draw_line(c.pos - c.vel * 0.035, c.pos, Color(cor, 0.55 * ac), c.larg + 1.2, true)
		d.draw_circle(c.pos, c.larg * 0.8, Color(1.0, 0.92, 0.6, 0.95 * ac))
	# 6) FAGULHAS subindo, piscando
	for b in e.brilhos:
		var kb: float = t / b.vida
		if kb >= 1.0:
			continue
		var ab2 := (1.0 - kb) * (0.5 + 0.5 * sin(t * 26.0 + b.fase))
		d.draw_circle(b.pos, b.r * 2.6, Color(1.0, 0.4, 0.05, 0.25 * ab2))
		d.draw_circle(b.pos, b.r, Color(1.0, 0.85, 0.45, 0.95 * ab2))

## Cor do fogo pela "idade" (0 = branco quente, 0.35 = amarelo, 0.65 = laranja, 1 = vermelho escuro).
static func _cor_fogo(k: float) -> Color:
	k = clampf(k, 0.0, 1.0)
	if k < 0.35:
		return Color(1.0, 0.97, 0.82).lerp(Color(1.0, 0.8, 0.28), k / 0.35)
	if k < 0.65:
		return Color(1.0, 0.8, 0.28).lerp(Color(1.0, 0.42, 0.06), (k - 0.35) / 0.3)
	return Color(1.0, 0.42, 0.06).lerp(Color(0.7, 0.1, 0.02), (k - 0.65) / 0.35)

## BOLA DE FOGO voando: miolo branco-amarelo, labareda viva esticada para trás (vento do voo),
## cauda de chamas que esfria até o vermelho e brasas caindo atrás. (nó aditivo)
static func desenhar_bola_fogo(d: CanvasItem, pos: Vector2, dir: float, t: float) -> void:
	var trem := 0.9 + 0.1 * sin(t * 31.0) * sin(t * 13.0 + 0.7)
	# brilho em volta (ilumina o ar)
	d.draw_circle(pos, 48.0 * trem, Color(1.0, 0.32, 0.04, 0.10))
	d.draw_circle(pos, 30.0 * trem, Color(1.0, 0.45, 0.08, 0.20))
	# cauda: bolas que esfriam e sobem um pouco (ar quente), com turbulência
	for k in 16:
		var f := float(k) / 16.0
		var tp := pos + Vector2(-dir * (6.0 + f * 100.0), sin(t * 24.0 - f * 9.0) * 5.0 * f - f * f * 12.0)
		var r := 15.0 * (1.0 - f) * trem + 2.0
		d.draw_circle(tp, r, Color(_cor_fogo(0.25 + f * 0.75), 0.42 * (1.0 - f)))
	# labareda: a chama "de pé" girada para apontar para trás
	d.draw_set_transform(pos, -dir * PI / 2.0, Vector2.ONE)
	FxExplosao.desenhar_chama(d, Vector2(0, 10), t * 2.4, 0.5, sin(t * 9.0) * 7.0)
	d.draw_set_transform(Vector2.ZERO)
	# miolo
	d.draw_circle(pos, 13.0 * trem, Color(1.0, 0.6, 0.15, 0.7))
	d.draw_circle(pos, 8.5 * trem, Color(1.0, 0.88, 0.5, 0.95))
	d.draw_circle(pos, 4.5, Color(1.0, 1.0, 0.95, 1.0))
	# brasas que se soltam e caem atrás
	for s in 9:
		var fs := fmod(t * 2.3 + s / 9.0, 1.0)
		var ps := pos + Vector2(-dir * (10.0 + fs * 85.0), sin(s * 2.3 + t * 8.0) * 10.0 * fs + fs * fs * 22.0)
		d.draw_circle(ps, 2.2 * (1.0 - fs) + 0.5, Color(_cor_fogo(0.3 + fs * 0.6), 0.9 * (1.0 - fs)))

## Luz que o impacto joga no chão + onda de choque achatada correndo no chão.
func _luz_chao(d: CanvasItem, e: Dictionary) -> void:
	var tm: Dictionary = TEMAS[e.tema]
	var c := Vector2(e.pos.x, e.chao - 2.0)
	var kl := clampf(e.t / (0.9 if e.tema == "fogo" else 0.5), 0.0, 1.0)   # (o fogo ilumina o chão por mais tempo)
	if kl < 1.0:
		d.draw_set_transform(c, 0.0, Vector2(1.0, 0.3))
		d.draw_circle(Vector2.ZERO, 95.0 * e.esc, Color(tm.meio, 0.16 * (1.0 - kl)))
		d.draw_circle(Vector2.ZERO, 50.0 * e.esc, Color(tm.meio, 0.26 * (1.0 - kl)))
		d.draw_set_transform(Vector2.ZERO)
	var ko := clampf(e.t / 0.42, 0.0, 1.0)
	if ko < 1.0:
		var r: float = (20.0 + 110.0 * _sai(ko)) * e.esc
		d.draw_set_transform(c, 0.0, Vector2(1.0, 0.24))
		d.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(tm.meio, 0.45 * (1.0 - ko)), 7.0 * (1.0 - ko) + 1.0, true)
		d.draw_set_transform(Vector2.ZERO)

func _impacto_luz(d: CanvasItem, e: Dictionary) -> void:
	var tm: Dictionary = TEMAS[e.tema]
	var t: float = e.t
	var s: float = e.esc
	var p: Vector2 = e.pos
	# 1) CLARÃO: estoura branco e some rápido (é o que dá o "peso" do golpe)
	var kf := clampf(t / 0.12, 0.0, 1.0)
	if kf < 1.0:
		var af := 1.0 - kf
		d.draw_circle(p, 70.0 * s * (0.7 + 0.5 * kf), Color(tm.meio, 0.22 * af))
		d.draw_circle(p, 38.0 * s, Color(tm.luz, 0.55 * af))
		# raios de luz em estrela
		for r in e.raios:
			var v := Vector2.from_angle(r.ang)
			var L: float = 95.0 * s * r.comp * (0.5 + 0.5 * kf)
			d.draw_line(p + v * 10.0 * s, p + v * L, Color(tm.meio, 0.5 * af), 5.0 * af + 1.0, true)
			d.draw_line(p + v * 8.0 * s, p + v * L * 0.7, Color(tm.luz, 0.8 * af), 2.0 * af + 0.6, true)
	# 2) BRILHO NO CORPO do alvo: o inimigo é "banhado" pela magia por um instante
	var alvo = e.alvo
	if is_instance_valid(alvo) and t < 0.32:
		var ab := 1.0 - t / 0.32
		var cc: Vector2 = alvo.position + Vector2(0, -52)
		d.draw_set_transform(cc, 0.0, Vector2(0.55, 1.0))
		d.draw_circle(Vector2.ZERO, 62.0, Color(tm.meio, 0.20 * ab * ab))
		d.draw_set_transform(Vector2.ZERO)
	# 3) ANEL DE CHOQUE: abre rápido e afina
	var ka := clampf(t / 0.34, 0.0, 1.0)
	if ka < 1.0:
		var ra := (14.0 + 78.0 * _sai(ka)) * s
		d.draw_arc(p, ra, 0.0, TAU, 48, Color(tm.meio, 0.55 * (1.0 - ka)), 9.0 * (1.0 - ka) * s + 1.0, true)
		d.draw_arc(p, ra * 0.92, 0.0, TAU, 48, Color(tm.luz, 0.5 * (1.0 - ka)), 2.5 * (1.0 - ka) + 0.5, true)
	# 4) NÚCLEO: bola de energia que incha e implode
	var kn := clampf(t / 0.3, 0.0, 1.0)
	if kn < 1.0:
		var rn := 34.0 * s * sin(PI * minf(1.0, kn * 1.6 + 0.15)) * (1.0 - kn * 0.4)
		if rn > 0.5:
			d.draw_circle(p, rn * 1.5, Color(tm.borda, 0.30 * (1.0 - kn)))
			d.draw_circle(p, rn, Color(tm.meio, 0.55 * (1.0 - kn)))
			d.draw_circle(p, rn * 0.55, Color(tm.luz, 0.9 * (1.0 - kn)))
	# 5) FAÍSCAS DE ENERGIA estalando em volta do núcleo (só no começo)
	if t < 0.18:
		_rng_desenho.seed = int(e.semente) + int(t * 40.0) * 7919
		var ae := 1.0 - t / 0.18
		for q in 4:
			var a0 := _rng_desenho.randf_range(0.0, TAU)
			var pts := PackedVector2Array([p + Vector2.from_angle(a0) * 10.0 * s])
			var dirq := Vector2.from_angle(a0)
			for n in 4:
				dirq = dirq.rotated(_rng_desenho.randf_range(-0.8, 0.8))
				pts.append(pts[pts.size() - 1] + dirq * _rng_desenho.randf_range(9.0, 16.0) * s)
			d.draw_polyline(pts, Color(tm.meio, 0.5 * ae), 3.0, true)
			d.draw_polyline(pts, Color(tm.luz, 0.9 * ae), 1.2, true)
	# 6) ESTILHAÇOS: riscos de luz voando (o rastro é proporcional à velocidade)
	for c in e.cacos:
		var kc: float = t / c.vida
		if kc >= 1.0:
			continue
		var ac := 1.0 - kc
		var cauda: Vector2 = c.pos - c.vel * 0.03
		d.draw_line(cauda, c.pos, Color(tm.meio, 0.6 * ac), c.larg + 1.5, true)
		d.draw_line(c.pos - c.vel * 0.015, c.pos, Color(tm.luz, 0.95 * ac), c.larg * 0.6, true)
	# 7) BRILHOS que sobem piscando
	for b in e.brilhos:
		var kb: float = t / b.vida
		if kb >= 1.0:
			continue
		var pis := 0.55 + 0.45 * sin(t * 30.0 + b.fase)
		var ab2 := (1.0 - kb) * pis
		d.draw_circle(b.pos, b.r * 2.4, Color(tm.meio, 0.25 * ab2))
		d.draw_circle(b.pos, b.r, Color(tm.luz, 0.9 * ab2))

## ESFERA voando: cauda de cometa, halo pulsando, núcleo branco, faíscas orbitando e poeira de luz atrás.
## (desenhada num nó com mistura aditiva: as camadas somam luz)
static func desenhar_esfera(d: CanvasItem, pos: Vector2, dir: float, t: float, tema := "arcano") -> void:
	var tm: Dictionary = TEMAS[tema]
	var pul := 1.0 + 0.12 * sin(t * 22.0)
	# cauda de cometa: bolas que vão afinando para trás, com uma leve ondulação
	for k in 12:
		var f := float(k) / 12.0
		var tp := pos + Vector2(-dir * (4.0 + f * 78.0), sin(t * 18.0 - f * 7.0) * 3.5 * f)
		var r := 13.0 * (1.0 - f) + 1.5
		d.draw_circle(tp, r * 1.7, Color(tm.borda, 0.10 * (1.0 - f)))
		d.draw_circle(tp, r, Color(tm.meio, 0.22 * (1.0 - f)))
	# halo e corpo
	d.draw_circle(pos, 30.0 * pul, Color(tm.borda, 0.16))
	d.draw_circle(pos, 19.0 * pul, Color(tm.meio, 0.35))
	d.draw_circle(pos, 12.0 * pul, Color(tm.meio, 0.7))
	d.draw_circle(pos, 6.5, Color(tm.luz, 1.0))
	d.draw_circle(pos + Vector2(dir * 1.5, -1.5), 3.0, Color(1, 1, 1, 1))
	# anel de energia girando (elipse inclinada: parece uma órbita em 3D)
	var giro := t * 9.0
	var pts := PackedVector2Array()
	for k in 25:
		var a := TAU * k / 24.0
		pts.append(pos + Vector2(cos(a) * 17.0, sin(a) * 6.0).rotated(0.5 * dir + sin(t * 3.0) * 0.2))
	d.draw_polyline(pts, Color(tm.meio, 0.35), 1.6, true)
	# 3 faíscas orbitando, cada uma com um rastrinho
	for s in 3:
		var a := giro + s * TAU / 3.0
		var o := Vector2(cos(a) * 17.0, sin(a) * 6.0).rotated(0.5 * dir + sin(t * 3.0) * 0.2)
		var o2 := Vector2(cos(a - 0.5) * 17.0, sin(a - 0.5) * 6.0).rotated(0.5 * dir + sin(t * 3.0) * 0.2)
		var na_frente := sin(a) > 0.0
		d.draw_line(pos + o2, pos + o, Color(tm.meio, 0.5), 2.0, true)
		d.draw_circle(pos + o, 2.6 if na_frente else 1.8, Color(tm.luz, 0.95 if na_frente else 0.55))
	# poeira de luz ficando para trás (sobe um pouco e apaga)
	for s in 7:
		var fs := fmod(t * 2.6 + s * 0.143, 1.0)
		var ps := pos + Vector2(-dir * (10.0 + fs * 70.0), sin(s * 2.1 + t * 7.0) * 9.0 * fs - fs * 14.0)
		d.draw_circle(ps, 2.0 * (1.0 - fs) + 0.5, Color(tm.luz, 0.8 * (1.0 - fs)))

static func _sai(k: float) -> float:          ## ease-out (abre rápido e desacelera)
	return 1.0 - pow(1.0 - k, 3.0)
