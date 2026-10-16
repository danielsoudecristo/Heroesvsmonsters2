extends SceneTree
## Onde estão os pixels frios que sobraram no quadro 15 (e no 5)? Histograma por faixa de x.
##
## godot --headless --path "C:\Users\danie\Music\HvM Godot2" --script res://ferramentas/medir_sobra.gd

const FOLHA := "res://assets_otimizados/Engenheiro Arcano/atacando_420x338.png"
const COLS := 6
const CW := 420
const CH := 338
const BX := 221.0
const BY := 92.0

func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(FOLHA))
	if img == null:
		print("ERRO")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	# sobra SOB o personagem (x<=200, d>80, luma 0.25..0.55): alfa em 5 baldes
	for qq in [8, 14, 20]:
		var q: int = qq
		var col := q % COLS
		var lin := q / COLS
		var alfas := [0, 0, 0, 0, 0]
		var n := 0
		var soma_rgb := Vector3.ZERO
		for y in CH:
			for x in CW:
				if x > 200:
					continue
				var c := img.get_pixel(col * CW + x, lin * CH + y)
				if c.a <= 0.05:
					continue
				if c.g < c.r * 0.95 or c.b < c.r * 0.95:
					continue
				var luma := (c.r + c.g + c.b) / 3.0 * c.a
				if luma < 0.25 or luma > 0.55:
					continue
				var d := Vector2(x - BX, y - BY).length()
				if d <= 80.0:
					continue
				n += 1
				soma_rgb += Vector3(c.r, c.g, c.b)
				if c.a < 0.25: alfas[0] += 1
				elif c.a < 0.5: alfas[1] += 1
				elif c.a < 0.75: alfas[2] += 1
				elif c.a < 0.95: alfas[3] += 1
				else: alfas[4] += 1
		var mr := Vector3.ZERO
		if n > 0:
			mr = soma_rgb / float(n)
		print("quadro %d sobra-personagem: n=%d alfa(<.25/.25-.5/.5-.75/.75-.95/1)=%d/%d/%d/%d/%d cor_media=(%.2f,%.2f,%.2f)"
			% [q + 1, n, alfas[0], alfas[1], alfas[2], alfas[3], alfas[4], mr.x, mr.y, mr.z])
	quit(0)
