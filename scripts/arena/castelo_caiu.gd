extends Node2D
## CASTELO DESTRUÍDO: quando o castelo cai, o fundo troca (com tremor, clarão e nuvem de poeira) pela arte
## do castelo em ruínas de assets/Fundo/fundo caiu/<fundo>_caiu.png e as chamas e fumaças PINTADAS nela
## ganham vida: fogo tremulando com brasas subindo, tochas que sobraram acesas e colunas de fumaça subindo
## e se espalhando. Os pontos (marcados à mão em cada arte) vêm de dados/castelo_caiu.json.
## Filho do Sprite2D do fundo (igual às tochas): herda escala e espelho, tudo medido em pixels da imagem.

const ARQ := "res://dados/castelo_caiu.json"
const PASTA := "res://assets/Fundo/fundo caiu/"
const X_CASTELO := 800.0              ## (px da imagem) as tochas do fundo antes disso eram do castelo: somem
const TROCA := 0.9                    ## segundos da arte inteira virando a destruída
const TREMOR := 0.7
static var _todas: Dictionary = {}
static var _tex_luz: Texture2D

var fogos: Array = []
var tochas: Array = []
var fumacas: Array = []
var poeira: Array = []                ## nuvem de poeira do desabamento
var t := 0.0                          ## tempo desde a queda
var noite := false
var _ruinas: Sprite2D                 ## a arte destruída, por cima do fundo inteiro
var _luz: Node2D                      ## camada aditiva (brilho do fogo e clarão)
var _pos_fundo := Vector2.INF

## Existe a arte destruída para este fundo?
static func caminho(tex: Texture2D) -> String:
	if tex == null:
		return ""
	var c := PASTA + tex.resource_path.get_file().get_basename() + "_caiu.png"
	return c if ResourceLoader.exists(c) else ""

## Volta ao castelo inteiro (nível novo / revanche).
func limpar() -> void:
	visible = false
	set_process(false)
	if _ruinas:
		_ruinas.visible = false
	var fundo := get_parent() as Sprite2D
	if fundo and _pos_fundo != Vector2.INF:
		fundo.position = _pos_fundo
	_pos_fundo = Vector2.INF

## O castelo caiu. instantaneo = já mostra destruído (ex.: trocou de vista depois do fim do PvP).
## Devolve false se este fundo não tem a arte destruída.
func cair(instantaneo := false) -> bool:
	var fundo := get_parent() as Sprite2D
	if fundo == null:
		return false
	var c := caminho(fundo.texture)
	if c == "":
		limpar()
		return false
	var nome := fundo.texture.resource_path.get_file().get_basename()
	noite = "noite" in nome or "halloween" in nome or "inverno" in nome
	if _ruinas == null:
		_ruinas = Sprite2D.new()
		_ruinas.centered = true
		fundo.add_child(_ruinas)
	fundo.move_child(_ruinas, 0)                      # por cima do fundo, por baixo das tochas e deste fogo
	_ruinas.texture = load(c)
	_ruinas.flip_h = fundo.flip_h
	_ruinas.visible = true
	scale = Vector2(-1, 1) if fundo.flip_h else Vector2.ONE
	for irmao in fundo.get_children():               # as tochas pintadas do castelo inteiro somem (as da cerca ficam)
		if irmao.has_method("esconder_ate"):
			irmao.esconder_ate(X_CASTELO)
	_montar(nome, fundo.texture.get_size() / 2.0)
	t = 99.0 if instantaneo else 0.0
	if not instantaneo:
		_pos_fundo = fundo.position
	visible = true
	set_process(true)
	if _luz == null:
		_luz = Node2D.new()
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_luz.material = m
		_luz.draw.connect(_desenhar_luz)
		add_child(_luz)
	if _tex_luz == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.45))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 128
		gt.height = 128
		_tex_luz = gt
	return true

func _montar(nome: String, meio: Vector2) -> void:
	if _todas.is_empty() and ResourceLoader.exists(ARQ):
		var j: Variant = load(ARQ)                   # (recurso JSON: vai junto no APK)
		if j is JSON and j.data is Dictionary:
			_todas = j.data
	var d: Dictionary = _todas.get(nome, {})
	fogos.clear(); tochas.clear(); fumacas.clear(); poeira.clear()
	var ordem := 0
	for f in d.get("fogo", []):
		var tam := float(f[2])
		# o fogo vai pegando aos poucos depois da queda (de cima para baixo, como o que desabou)
		fogos.append({"p": Vector2(float(f[0]), float(f[1]) + 18.0 * tam) - meio, "tam": tam, "fase": randf() * 50.0,
			"acende": 0.25 + ordem * 0.12 + randf() * 0.25})
		ordem += 1
	for f in d.get("tocha", []):
		var tam := float(f[2])
		tochas.append({"p": Vector2(float(f[0]), float(f[1]) + 12.0 * tam) - meio, "tam": tam, "fase": randf() * 50.0,
			"magica": f.size() > 3 and int(f[3]) == 1, "acende": 0.2})
	for f in d.get("fumaca", []):
		fumacas.append({"p": Vector2(float(f[0]), float(f[1])) - meio, "alt": float(f[2]), "larg": float(f[3]),
			"fase": randf() * 10.0, "acende": 0.5 + randf() * 0.5})
	# poeira do desabamento: nuvens que saem da base do castelo e se espalham
	for k in 16:
		poeira.append({"p": Vector2(randf_range(40.0, 720.0), randf_range(560.0, 1000.0)) - meio,
			"r": randf_range(50.0, 110.0), "vel": Vector2(randf_range(-30.0, 60.0), randf_range(-60.0, -20.0)),
			"atraso": randf_range(0.0, 0.35)})

func _process(dt: float) -> void:
	t += dt
	var fundo := get_parent() as Sprite2D
	if _ruinas:
		_ruinas.modulate.a = clampf(t / TROCA, 0.0, 1.0)
	if fundo and _pos_fundo != Vector2.INF:          # o chão treme enquanto o castelo desaba
		if t < TREMOR:
			var k := 1.0 - t / TREMOR
			fundo.position = _pos_fundo + Vector2(sin(t * 71.0) * 9.0 * k, sin(t * 53.0 + 1.3) * 6.0 * k)
		else:
			fundo.position = _pos_fundo
			_pos_fundo = Vector2.INF
	queue_redraw()
	if _luz:
		_luz.queue_redraw()

## 0 -> 1 conforme a coisa acende (sobe suave).
func _aceso(e: Dictionary) -> float:
	return clampf((t - float(e.acende)) / 0.5, 0.0, 1.0)

# ============================================================== DESENHO (normal)
func _draw() -> void:
	_desenhar_fumacas()
	for f in fogos:
		var a := _aceso(f)
		if a > 0.0:
			_fogo(f, a)
	for e in tochas:
		var a := _aceso(e)
		if a > 0.0:
			_tocha(e, a)
	_desenhar_poeira()

## Colunas de fumaça: tufos que nascem na base, sobem, engordam, puxam para o lado com o vento e somem.
## A fumaça pintada fica embaixo: a animada passa por cima dela e dá o movimento.
func _desenhar_fumacas() -> void:
	var cor := Color(0.3, 0.29, 0.32) if noite else Color(0.2, 0.19, 0.19)
	for s in fumacas:
		var a0 := _aceso(s)
		if a0 <= 0.0:
			continue
		var alt: float = s.alt
		var larg: float = s.larg
		var vel := 34.0 / maxf(alt, 60.0)            # (~34 px/s subindo, qualquer que seja a altura)
		var n := 12
		for i in n:
			var k := fmod((t + float(s.fase)) * vel + float(i) / n, 1.0)
			var lado := sin(i * 2.7 + float(s.fase)) * 10.0 * larg
			var p: Vector2 = s.p + Vector2(lado + sin(t * 0.8 + i) * 6.0 * k - 0.3 * alt * k * k, -alt * 1.15 * k)
			var r := (22.0 + 70.0 * k) * larg * (0.85 + 0.15 * sin(i * 1.3))
			var a := 0.75 * pow(sin(PI * k), 0.75) * a0
			_tufo(p, r, Color(cor, a))
			_tufo(p + Vector2(-r * 0.25, -r * 0.28), r * 0.6, Color(cor.lightened(0.15), a * 0.5))

## Tufo de fumaça / poeira: mancha redonda de borda macia (sem contorno de círculo).
func _tufo(c: Vector2, r: float, cor: Color) -> void:
	draw_texture_rect(_tex_luz, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, cor)

## Incêndio: três línguas de fogo lado a lado (irregular, nunca uma gota só), línguas soltas e brasas.
func _fogo(f: Dictionary, aceso: float) -> void:
	var tt: float = t + f.fase
	var tam: float = f.tam * (0.35 + 0.65 * aceso) * 1.25
	var vento := sin(tt * 1.3) * 4.0 + sin(tt * 0.5) * 3.0 - 2.0
	for q in 3:
		var dx := (q - 1) * 13.0 * tam
		var esc := tam * (1.0 if q == 1 else 0.68 + 0.1 * sin(tt * 2.0 + q))
		FxExplosao.desenhar_chama(self, f.p + Vector2(dx, 0), tt * (1.0 + q * 0.17) + q * 3.1, esc * 0.62, vento)
	# línguas que se soltam por cima
	for q in 2:
		var fl := fmod(tt * 1.4 + q * 0.5, 1.0)
		if fl < 0.5:
			var k := fl / 0.5
			var pl: Vector2 = f.p + Vector2(vento * tam + sin(tt * 3.0 + q) * 8.0 * tam, -(40.0 + 34.0 * k) * tam)
			draw_colored_polygon(FxExplosao._gota(pl, 6.0 * tam * (1.0 - k) + 0.5, 16.0 * tam * (1.0 - k) + 1.0, tt * 2.0, vento),
				Color(1.0, 0.45, 0.06, 0.85 * (1.0 - k) * aceso))
	# brasas subindo e apagando
	for s in 6:
		var fs := fmod(tt * 0.5 + s / 6.0, 1.0)
		var bp: Vector2 = f.p + Vector2(sin(tt * 2.1 + s * 1.7) * 14.0 * tam + vento * fs * 4.0, -(36.0 + fs * 150.0) * tam)
		draw_circle(bp, (2.6 - fs * 1.8) * maxf(tam, 0.6), Color(1.0, 0.75 - fs * 0.35, 0.25, 0.95 * (1.0 - fs) * aceso))

## Tocha que sobrou acesa no meio das ruínas.
func _tocha(e: Dictionary, aceso: float) -> void:
	var tt: float = t + e.fase
	var tam: float = e.tam * aceso
	var vento := sin(tt * 1.7) * 3.0 + sin(tt * 0.6) * 2.0
	var trem := 0.88 + 0.12 * sin(tt * 21.0) * sin(tt * 6.7 + 1.1)
	var pal: Array
	if e.magica:
		pal = [Color(0.35, 0.08, 0.6, 0.6), Color(0.62, 0.25, 1.0, 0.85), Color(0.85, 0.6, 1.0, 0.95), Color(1.0, 0.95, 1.0, 1.0)]
	else:
		pal = [Color(0.85, 0.2, 0.04, 0.45), Color(1.0, 0.42, 0.06, 0.88), Color(1.0, 0.78, 0.22, 0.96), Color(1.0, 0.97, 0.82, 1.0)]
	var camadas := [[22.0, 50.0, 1.0], [16.0, 48.0, 1.7], [10.5, 34.0, 2.6], [5.5, 18.0, 3.4]]
	for i in camadas.size():
		var c: Array = camadas[i]
		var larg: float = c[0] * trem * tam
		var alt: float = c[1] * (0.86 + 0.24 * sin(tt * (10.0 + c[2]) + c[2])) * tam
		if larg > 0.5:
			draw_colored_polygon(FxExplosao._gota(e.p, larg, alt, tt * c[2], vento * tam), pal[i])
	for s in 3:
		var fase := fmod(tt * 0.55 + s / 3.0, 1.0)
		var bp: Vector2 = e.p + Vector2(sin(tt * 2.3 + s * 1.9) * 9.0 * tam, -(40.0 + fase * 110.0) * tam)
		draw_circle(bp, (2.4 - fase * 1.5) * maxf(tam, 0.5), Color(pal[2], 0.9 * (1.0 - fase)))

## Poeira do desabamento (só nos primeiros segundos).
func _desenhar_poeira() -> void:
	if t > 3.0:
		return
	var cor := Color(0.42, 0.4, 0.42) if noite else Color(0.62, 0.56, 0.48)
	for p in poeira:
		var tl: float = t - p.atraso
		if tl <= 0.0:
			continue
		var k := clampf(tl / 2.6, 0.0, 1.0)
		var a := 0.7 * minf(1.0, tl * 5.0) * pow(1.0 - k, 1.6)
		if a <= 0.01:
			continue
		var c: Vector2 = p.p + p.vel * tl
		var r: float = p.r * (0.9 + 1.1 * (1.0 - pow(1.0 - k, 2.0)))
		_tufo(c, r, Color(cor, minf(1.0, a * 1.6)))
		_tufo(c + Vector2(-r * 0.3, -r * 0.25), r * 0.6, Color(cor.lightened(0.15), a))

# ============================================================== DESENHO (luz aditiva)
func _desenhar_luz() -> void:
	var forca := 1.0 if noite else 0.6
	# clarão do desabamento sobre o castelo
	if t < 0.5:
		var k := t / 0.5
		var r := 700.0
		var c := Vector2(380.0, 520.0) - _meio()
		_luz.draw_texture_rect(_tex_luz, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1.0, 0.7, 0.4, 0.5 * (1.0 - k)))
	for f in fogos:
		var a := _aceso(f)
		if a <= 0.0:
			continue
		var tt: float = t + f.fase
		var piscar := 0.8 + 0.12 * sin(tt * 8.7) + 0.08 * sin(tt * 21.3 + 1.1)
		var r: float = 210.0 * f.tam * piscar
		_luz.draw_texture_rect(_tex_luz, Rect2(f.p + Vector2(-r, -r - 30.0 * f.tam), Vector2(r, r) * 2.0), false, Color(1.0, 0.5, 0.15, 0.45 * forca * a))
		var r2: float = 80.0 * f.tam * piscar
		_luz.draw_texture_rect(_tex_luz, Rect2(f.p + Vector2(-r2, -r2 - 30.0 * f.tam), Vector2(r2, r2) * 2.0), false, Color(1.0, 0.75, 0.35, 0.5 * forca * a))
	for e in tochas:
		var a := _aceso(e)
		if a <= 0.0:
			continue
		var tt: float = t + e.fase
		var piscar := 0.82 + 0.1 * sin(tt * 9.3) + 0.08 * sin(tt * 23.7 + 1.3)
		var cor := Color(0.75, 0.35, 1.0) if e.magica else Color(1.0, 0.55, 0.18)
		var r: float = 150.0 * e.tam * piscar
		_luz.draw_texture_rect(_tex_luz, Rect2(e.p + Vector2(-r, -r - 14.0 * e.tam), Vector2(r, r) * 2.0), false, Color(cor, 0.4 * forca * a))

func _meio() -> Vector2:
	var fundo := get_parent() as Sprite2D
	return fundo.texture.get_size() / 2.0 if fundo and fundo.texture else Vector2(1280, 540)
