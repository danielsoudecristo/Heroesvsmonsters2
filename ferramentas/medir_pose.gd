extends SceneTree
## Confere se a pose do quadro 1 é igual à dos quadros 9-26 (zona só de personagem:
## pernas/cape, longe do clarão). Se for ~0 de diferença, dá para usar o quadro 1
## como referência limpa para restaurar a área do clarão.
##
## godot --headless --path "C:\Users\danie\Music\HvM Godot2" --script res://ferramentas/medir_pose.gd

const FOLHA := "res://assets_otimizados/Engenheiro Arcano/atacando_420x338.png"
const COLS := 6
const CW := 420
const CH := 338

func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(FOLHA))
	if img == null:
		print("ERRO")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var ref_col := 0
	var ref_lin := 0
	for qq in [8, 14, 20, 26, 30]:
		var q: int = qq
		var col := q % COLS
		var lin := q / COLS
		var dif := 0.0
		var n := 0
		var dif_maior := 0.0
		# zona só-personagem: pernas e capa (x 40-160, y 150-330)
		for y in range(150, 330, 2):
			for x in range(40, 160, 2):
				var a := img.get_pixel(col * CW + x, lin * CH + y)
				var b := img.get_pixel(ref_col * CW + x, ref_lin * CH + y)
				var d := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)
				dif += d
				dif_maior = maxf(dif_maior, d)
				n += 1
		print("quadro %d vs 1: dif_media=%.4f dif_max=%.3f (n=%d)" % [q + 1, dif / n, dif_maior, n])
	quit(0)
