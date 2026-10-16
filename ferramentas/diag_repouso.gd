extends SceneTree
## Probe: confere alpha/RGB do parado_repouso.png gerado.

func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/Esqueleto/parado/parado_repouso.png"))
	if img == null or img.is_empty():
		push_error("não abriu")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	print("tamanho: %dx%d" % [img.get_width(), img.get_height()])
	var cantos := [
		Vector2i(2, 2),
		Vector2i(img.get_width() - 3, 2),
		Vector2i(2, img.get_height() - 3),
		Vector2i(img.get_width() - 3, img.get_height() - 3),
		Vector2i(46, 12),     # topo da célula 0 (acima da cabeça)
		Vector2i(12, 100),    # lateral esquerda da célula 0
	]
	for p in cantos:
		var c := img.get_pixel(p.x, p.y)
		print("pixel (%d,%d): a=%.2f r=%.0f g=%.0f b=%.0f" % [p.x, p.y, c.a, c.r * 255.0, c.g * 255.0, c.b * 255.0])
	var dados := img.get_data()
	var n := dados.size() / 4
	var z := 0
	var altos := 0
	for i in n:
		var a := dados[i * 4 + 3]
		if a == 0:
			z += 1
		elif a > 200:
			altos += 1
	print("alfa 0: %.1f%%  |  alfa >200: %.1f%%" % [100.0 * z / n, 100.0 * altos / n])
	quit(0)
