extends SceneTree
## Acha os RESTOS DO FEIXE: pixel que no quadro 15 é frio/claro mas no quadro 1 (sem
## clarão) é transparente ou bem mais escuro. Só isso é sobra da cirurgia.
##
## godot --headless --path "C:\Users\danie\Music\HvM Godot2" --script res://ferramentas/medir_resto.gd

const FOLHA := "res://assets_otimizados/Engenheiro Arcano/atacando_420x338.png"
const COLS := 6
const CW := 420
const CH := 338
const BX := 221.0
const BY := 92.0

func _px(img: Image, q: int, x: int, y: int) -> Color:
	return img.get_pixel((q % COLS) * CW + x, (q / COLS) * CH + y)

func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(FOLHA))
	if img == null:
		print("ERRO")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	for qq in [4, 8, 14, 20, 25]:
		var q: int = qq
		var n := 0
		var por_x := [0, 0, 0, 0]          # <160 / 160-195 / 195-240 / >240
		var luma_soma := 0.0
		var d_max := 0.0
		var cor := Vector3.ZERO
		for y in CH:
			for x in CW:
				var a := _px(img, q, x, y)
				if a.a <= 0.05:
					continue
				if a.g < a.r * 0.95 or a.b < a.r * 0.95:
					continue
				var luma := (a.r + a.g + a.b) / 3.0 * a.a
				if luma < 0.35:
					continue
				var b := _px(img, 0, x, y)
				var luma_b := (b.r + b.g + b.b) / 3.0 * b.a
				if b.a > 0.1 and luma <= luma_b + 0.15:
					continue                   # existe no quadro 1 e é igual: é personagem
				n += 1
				luma_soma += luma
				cor += Vector3(a.r, a.g, a.b)
				var d := Vector2(x - BX, y - BY).length()
				d_max = maxf(d_max, d)
				if x < 160: por_x[0] += 1
				elif x < 195: por_x[1] += 1
				elif x < 240: por_x[2] += 1
				else: por_x[3] += 1
		var mc := Vector3.ZERO
		if n > 0:
			mc = cor / float(n)
		print("quadro %d: restos=%d luma_med=%.2f d_max=%.0f x(<160/160-195/195-240/>240)=%d/%d/%d/%d cor=(%.2f,%.2f,%.2f)"
			% [q + 1, n, luma_soma / maxf(n, 1), d_max, por_x[0], por_x[1], por_x[2], por_x[3], mc.x, mc.y, mc.z])
	quit(0)
