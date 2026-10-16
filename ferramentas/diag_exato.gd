extends SceneTree
## DIAG EXATO: caixa exata (px a px) de alguns quadros + perfil de alpha perto do chão.
## RODAR: godot --headless --path "<pasta do projeto>" --script res://ferramentas/diag_exato.gd

const ORIGEM := "res://assets/Engenheiro Arcano/Engenheiro Arcano repouso+atirando.png"
const COLS := 11
const CEL := Vector2i(1280, 720)

func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ORIGEM))
	img.convert(Image.FORMAT_RGBA8)
	for n in [1, 34, 118]:
		var q: int = n - 1
		var org := Vector2i((q % COLS) * CEL.x, (q / COLS) * CEL.y)
		var x0 := CEL.x; var y0 := CEL.y; var x1 := 0; var y1 := 0
		for y in range(CEL.y):
			for x in range(CEL.x):
				if img.get_pixel(org.x + x, org.y + y).a * 255.0 >= 14.0:
					if x < x0: x0 = x
					if x > x1: x1 = x
					if y < y0: y0 = y
					if y > y1: y1 = y
		print("QUADRO %d exato: x %d..%d  y %d..%d" % [n, x0, x1, y0, y1])
		for x in [x0 + (x1 - x0) / 2, 500, 840]:
			var linha := ""
			for y in range(maxi(y1 - 40, 0), y1 + 1, 2):
				linha += "%d:%d " % [y, int(img.get_pixel(org.x + x, org.y + y).a * 255.0)]
			print("  coluna x=%d -> %s" % [x, linha])
	quit(0)
