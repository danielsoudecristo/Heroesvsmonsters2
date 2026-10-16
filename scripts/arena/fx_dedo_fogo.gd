extends Node2D
class_name FxDedoFogo
## ESQUELETO MÍSTICO — DEDO DE FOGO (só visual; o dano é a Unidade que dá, no passo fixo).
## 1) a ponta do dedo acende (estrela de fogo); 2) sai um cometa de fogo com duas fitas de chama girando em
## espiral em volta (e brasas soltando), num arco leve até o PEITO do alvo (acompanha se ele andar);
## 3) chegou: estoura em labareda (FxExplosao do jogo) e a fita some no ar.
## Desenhado somando luz (blend ADD): brilha de verdade em qualquer fundo.

var de := Vector2.ZERO
var alvo: Node2D = null
var para := Vector2.ZERO               ## onde vai acertar (atualiza enquanto o alvo existir)
var dur := 0.2                         ## tempo de voo (o mesmo que a Unidade espera para dar o dano)
var fx_ar: Node = null                 ## explosão no fim (FxExplosao do jogo), se tiver
var _t := 0.0
var _chegou := false
var _t_fim := 0.0
var _brasas: Array = []                ## [pos, vel, t, vida]
var _semente := 0.0

const CARGA := 0.12                    ## a ponta do dedo acende antes de soltar
const SOME := 0.35                     ## o rastro some depois de acertar

func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	z_index = 12
	_semente = randf() * 100.0

func _alvo_pos() -> Vector2:
	if alvo != null and is_instance_valid(alvo) and alvo.has_method("posicao_cabeca"):
		var cab: Vector2 = alvo.posicao_cabeca()
		return Vector2(cab.x, lerpf(cab.y, alvo.position.y, 0.32))          # no peito
	return para

## Ponto do caminho em k (0..1): arco para cima, mais alto no meio.
func _ponto(k: float) -> Vector2:
	var b := de.lerp(para, k)
	var arco := minf(70.0, de.distance_to(para) * 0.12)
	return b + Vector2(0, -sin(k * PI) * arco)

func _process(dt: float) -> void:
	_t += dt
	para = _alvo_pos()
	var k := clampf((_t - CARGA) / dur, 0.0, 1.0)
	if not _chegou and k >= 1.0:
		_chegou = true
		if fx_ar and is_instance_valid(fx_ar) and fx_ar.has_method("explodir"):
			fx_ar.explodir(para, 0.5)
		for i in 22:                                              # brasas espirrando do corpo
			var ang := randf() * TAU
			_brasas.append([para, Vector2(cos(ang), sin(ang) - 0.6) * randf_range(90.0, 300.0), 0.0, randf_range(0.35, 0.8)])
	if _chegou:
		_t_fim += dt
	elif _t > CARGA:                                              # brasas soltando do cometa
		for i in 2:
			_brasas.append([_ponto(k), Vector2(randf_range(-60, 60), randf_range(-120, 10)), 0.0, randf_range(0.25, 0.5)])
	var i := _brasas.size() - 1
	while i >= 0:
		var b: Array = _brasas[i]
		b[2] += dt
		b[1].y += 300.0 * dt
		b[0] += b[1] * dt
		if b[2] >= b[3]:
			_brasas.remove_at(i)
		i -= 1
	if _chegou and _t_fim > SOME and _brasas.is_empty():
		queue_free()
	queue_redraw()

func _draw() -> void:
	var tt := _t + _semente
	# 1) a ponta do dedo acende (e continua acesa enquanto o fogo voa)
	var acesa := clampf(_t / CARGA, 0.0, 1.0) * (1.0 - clampf(_t_fim / SOME, 0.0, 1.0))
	if acesa > 0.0:
		var pul := 0.85 + 0.15 * sin(tt * 40.0)
		draw_circle(de, 34.0 * acesa * pul, Color(1.0, 0.25, 0.02, 0.18 * acesa))
		draw_circle(de, 18.0 * acesa * pul, Color(1.0, 0.5, 0.08, 0.45 * acesa))
		draw_circle(de, 7.0 * acesa, Color(1.0, 0.95, 0.75, 0.95 * acesa))
		for r in 4:                                               # estrela de 4 pontas girando
			var ang := tt * 6.0 + r * PI / 2.0
			var v := Vector2(cos(ang), sin(ang))
			draw_line(de - v * 4.0, de + v * 26.0 * acesa * pul, Color(1.0, 0.7, 0.3, 0.7 * acesa), 2.0)
	if _t < CARGA:
		_desenhar_brasas()
		return
	var k := clampf((_t - CARGA) / dur, 0.0, 1.0)
	var some := 1.0 - clampf(_t_fim / SOME, 0.0, 1.0)
	# 2) o caminho: núcleo branco-quente + fitas de chama em espiral (do começo até a cabeça do cometa)
	var ini := maxf(0.0, k - 0.75) if not _chegou else clampf(_t_fim / SOME, 0.0, 1.0)
	var n := 26
	var nucleo := PackedVector2Array()
	var fita_a := PackedVector2Array()
	var fita_b := PackedVector2Array()
	for s in n + 1:
		var kk := lerpf(ini, k, float(s) / n)
		var pt := _ponto(kk)
		var dirv := (_ponto(minf(kk + 0.02, 1.0)) - _ponto(maxf(kk - 0.02, 0.0))).normalized()
		var nor := Vector2(-dirv.y, dirv.x)
		var largura := 10.0 * (float(s) / n)                    # mais grossa perto da cabeça
		var giro := kk * 26.0 - tt * 18.0
		nucleo.append(pt)
		fita_a.append(pt + nor * sin(giro) * largura)
		fita_b.append(pt + nor * sin(giro + PI) * largura)
	if nucleo.size() >= 2:
		draw_polyline(nucleo, Color(1.0, 0.2, 0.0, 0.25 * some), 22.0, true)
		draw_polyline(fita_a, Color(1.0, 0.45, 0.05, 0.75 * some), 4.0, true)
		draw_polyline(fita_b, Color(1.0, 0.75, 0.15, 0.65 * some), 3.0, true)
		draw_polyline(nucleo, Color(1.0, 0.9, 0.6, 0.9 * some), 3.0, true)
	# a cabeça do cometa (bola de fogo pulsando)
	if not _chegou:
		var cab := _ponto(k)
		var pul := 0.9 + 0.1 * sin(tt * 30.0)
		draw_circle(cab, 30.0 * pul, Color(1.0, 0.22, 0.0, 0.25))
		draw_circle(cab, 17.0 * pul, Color(1.0, 0.55, 0.1, 0.6))
		draw_circle(cab, 8.0, Color(1.0, 0.97, 0.8, 1.0))
	else:                                                         # 3) clarão no corpo
		var f := clampf(_t_fim / 0.25, 0.0, 1.0)
		draw_circle(para, 26.0 + 70.0 * f, Color(1.0, 0.4, 0.05, 0.5 * (1.0 - f)))
		draw_arc(para, 20.0 + 90.0 * f, 0.0, TAU, 40, Color(1.0, 0.8, 0.4, 0.8 * (1.0 - f)), 4.0 * (1.0 - f) + 1.0, true)
	_desenhar_brasas()

func _desenhar_brasas() -> void:
	for b in _brasas:
		var q: float = b[2] / b[3]
		var v: Vector2 = b[1]
		var risco := v.normalized() * minf(10.0, v.length() * 0.04) * (1.0 - q)
		draw_line(b[0] - risco, b[0], Color(1.0, 0.55, 0.12, 0.9 * (1.0 - q)), 2.0 * (1.0 - q) + 0.5)
		draw_circle(b[0], 1.8 * (1.0 - q) + 0.4, Color(1.0, 0.9 - q * 0.5, 0.5 - q * 0.4, 1.0 - q))
