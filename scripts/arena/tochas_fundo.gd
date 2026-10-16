extends Node2D
## FOGO VIVO NAS TOCHAS DO FUNDO: cada fundo de assets/Fundo tem as tochas pintadas paradas; aqui elas
## ganham chama tremulando, luz que pulsa no muro/chão e brasas subindo. As posições vêm de
## dados/tochas_fundo.json (gerado por ferramentas/achar_tochas.gd). Filho do Sprite2D do fundo:
## herda a escala, então tudo é medido em pixels da imagem.
## LEVE: um só _draw por quadro, ~10 tochas, nada de nós por tocha.

const ARQ := "res://dados/tochas_fundo.json"
static var _todas: Dictionary = {}

var tochas: Array = []
var forca_luz := 1.0                  # de dia a luz em volta aparece menos
var t := 0.0
var _luz: Node2D                      # camada da luz (mistura aditiva: clareia o que está atrás)
static var _tex_luz: Texture2D

## Liga o fogo para a textura do fundo (nome do arquivo sem extensão). Sem tochas: some.
func usar(tex: Texture2D, noite: bool) -> void:
	tochas = []
	if tex == null:
		visible = false
		return
	if _todas.is_empty() and ResourceLoader.exists(ARQ):
		var j: Variant = load(ARQ)                  # (recurso JSON: vai junto no APK)
		if j is JSON and j.data is Dictionary:
			_todas = j.data
	var nome := tex.resource_path.get_file().get_basename()
	var meio := tex.get_size() / 2.0                # o Sprite2D é centralizado
	for e in _todas.get(nome, []):
		tochas.append({"p": Vector2(float(e.x), float(e.y) + 7.0) - meio, "r": float(e.r), "magica": bool(e.magica),
			"fase": randf() * 50.0})
	forca_luz = 1.0 if noite or "halloween" in nome or "inverno" in nome or "noite" in nome else 0.55
	visible = not tochas.is_empty()
	if _luz == null:
		_luz = Node2D.new()
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_luz.material = m
		_luz.show_behind_parent = false
		add_child(_luz)
		move_child(_luz, 0)
		_luz.draw.connect(_desenhar_luz)
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

func _process(dt: float) -> void:
	if not visible:
		return
	t += dt
	queue_redraw()
	if _luz:
		_luz.queue_redraw()

## Tamanho da chama a partir do núcleo achado na imagem (as tochas do muro de perto são maiores).
func _tam(e: Dictionary) -> float:
	return clampf(float(e.r) / 15.0, 0.7, 1.7)

func _desenhar_luz() -> void:
	for e in tochas:
		var tt: float = t + e.fase
		var tam := _tam(e)
		var piscar := 0.82 + 0.1 * sin(tt * 9.3) + 0.08 * sin(tt * 23.7 + 1.3)
		var cor := Color(0.75, 0.35, 1.0) if e.magica else Color(1.0, 0.55, 0.18)
		var r := 165.0 * tam * piscar
		_luz.draw_texture_rect(_tex_luz, Rect2(e.p + Vector2(-r, -r - 14.0 * tam), Vector2(r, r) * 2.0), false, Color(cor, 0.42 * forca_luz))
		var r2 := 62.0 * tam * piscar
		_luz.draw_texture_rect(_tex_luz, Rect2(e.p + Vector2(-r2, -r2 - 18.0 * tam), Vector2(r2, r2) * 2.0), false, Color(cor.lightened(0.3), 0.45 * forca_luz))

func _draw() -> void:
	for e in tochas:
		var tt: float = t + e.fase
		var tam := _tam(e)
		var pal: Array
		if e.magica:
			pal = [Color(0.35, 0.08, 0.6, 0.6), Color(0.62, 0.25, 1.0, 0.85), Color(0.85, 0.6, 1.0, 0.95), Color(1.0, 0.95, 1.0, 1.0)]
		else:
			pal = [Color(0.85, 0.2, 0.04, 0.45), Color(1.0, 0.42, 0.06, 0.88), Color(1.0, 0.78, 0.22, 0.96), Color(1.0, 0.97, 0.82, 1.0)]
		var vento := sin(tt * 1.7) * 3.0 + sin(tt * 0.6) * 2.0
		var trem := 0.88 + 0.12 * sin(tt * 21.0) * sin(tt * 6.7 + 1.1)
		var camadas := [[22.0, 50.0, 1.0], [16.0, 48.0, 1.7], [10.5, 34.0, 2.6], [5.5, 18.0, 3.4]]
		for i in camadas.size():
			var c: Array = camadas[i]
			var larg: float = c[0] * trem * tam
			var alt: float = c[1] * (0.86 + 0.24 * sin(tt * (10.0 + c[2]) + c[2])) * tam
			draw_colored_polygon(FxExplosao._gota(e.p, larg, alt, tt * c[2], vento * tam), pal[i])
		# línguas soltas que escapam por cima de vez em quando
		var f := fmod(tt * 1.6, 1.0)
		if f < 0.42:
			var k := f / 0.5
			var pl: Vector2 = e.p + Vector2(vento * tam * 1.5 + sin(tt * 3.0) * 3.0 * tam, -(44.0 + 30.0 * k) * tam)
			draw_colored_polygon(FxExplosao._gota(pl, 5.0 * tam * (1.0 - k), 15.0 * tam * (1.0 - k) + 0.5, tt * 2.0, vento), Color(pal[1], 0.8 * (1.0 - k)))
		# brasas subindo
		for s in 4:
			var fase := fmod(tt * 0.55 + s * 0.25, 1.0)
			var bp: Vector2 = e.p + Vector2(sin(tt * 2.3 + s * 1.9) * 9.0 * tam + vento * fase * 3.0, -(40.0 + fase * 120.0) * tam)
			draw_circle(bp, (2.6 - fase * 1.6) * tam, Color(pal[2], 0.9 * (1.0 - fase)))
