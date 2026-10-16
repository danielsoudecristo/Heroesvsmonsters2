extends SceneTree
## DIAG PÉS: imprime, para alguns quadros, onde tem desenho na faixa de baixo (as botas),
## no meio e no topo do quadro — para achar o centro dos pés de verdade.
## RODAR: godot --headless --path "<pasta do projeto>" --script res://ferramentas/diag_pes.gd

const ORIGEM := "res://assets/Engenheiro Arcano/Engenheiro Arcano repouso+atirando.png"
const COLS := 11
const CEL := Vector2i(1280, 720)
const ALFA := 14

func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ORIGEM))
	img.convert(Image.FORMAT_RGBA8)
	for n in [1, 2, 5, 30, 34, 50, 70, 90, 118]:
		var q: int = n - 1
		var org := Vector2i((q % COLS) * CEL.x, (q / COLS) * CEL.y)
		var faixas := [[CEL.y - 30, CEL.y], [CEL.y - 200, CEL.y - 150], [CEL.y - 400, CEL.y - 350]]
		print("")
		print("QUADRO %d (origem %s):" % [n, str(org)])
		for f in faixas:
			var linhas := PackedStringArray()
			var atual := -1
			for x in range(CEL.x):
				var tem := false
				for y in range(org.y + f[0], org.y + f[1], 3):
					if img.get_pixel(org.x + x, y).a * 255.0 >= ALFA:
						tem = true
						break
				if tem and atual < 0:
					atual = x
				elif not tem and atual >= 0:
					linhas.append("%d..%d" % [atual, x - 1])
					atual = -1
			if atual >= 0:
				linhas.append("%d..%d" % [atual, CEL.x - 1])
			print("  y %4d..%4d -> %s" % [f[0], f[1], " ".join(linhas) if not linhas.is_empty() else "(vazio)"])
	quit(0)
