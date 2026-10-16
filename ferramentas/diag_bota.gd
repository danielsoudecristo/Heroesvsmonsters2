extends SceneTree
## DIAG BOTA: mapa das pernas/botas em vários alturas (para achar o centro dos pés de verdade).
## RODAR: godot --headless --path "<pasta do projeto>" --script res://ferramentas/diag_bota.gd

const ORIGEM := "res://assets/Engenheiro Arcano/Engenheiro Arcano repouso+atirando.png"
const COLS := 11
const CEL := Vector2i(1280, 720)
const ALFA := 14

func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ORIGEM))
	img.convert(Image.FORMAT_RGBA8)
	for n in [1, 34, 70, 118]:
		var q: int = n - 1
		var org := Vector2i((q % COLS) * CEL.x, (q / COLS) * CEL.y)
		print("")
		print("QUADRO %d:" % n)
		for y in [660, 650, 640, 620, 600, 580, 560, 540, 520]:
			var linhas := PackedStringArray()
			var atual := -1
			for x in range(CEL.x):
				var tem := false
				for yy in [y - 4, y - 2, y]:
					if img.get_pixel(org.x + x, org.y + yy).a * 255.0 >= ALFA:
						tem = true
						break
				if tem and atual < 0:
					atual = x
				elif not tem and atual >= 0:
					if x - atual > 3:
						linhas.append("%d..%d" % [atual, x - 1])
					atual = -1
			if atual >= 0:
				linhas.append("%d..%d" % [atual, CEL.x - 1])
			print("  y=%d -> %s" % [y, " ".join(linhas) if not linhas.is_empty() else "(vazio)"])
	quit(0)
