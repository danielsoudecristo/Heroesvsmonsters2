extends SceneTree
## CLASSIFICA OS QUADROS: para cada um dos 118 quadros mede conteúdo e "raio" (pixels ciano/verde),
## para achar na prática onde termina o tiro e onde começa o repouso.
## RODAR: godot --headless --path "<pasta do projeto>" --script res://ferramentas/diag_engenheiro.gd

const FOLHA := "res://assets/Engenheiro Arcano/Engenheiro Arcano repouso+atirando.png"
const COLS := 11
const CW := 1280
const CH := 720
const QUADROS := 118
const MEIO := 4

func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(FOLHA))
	if img == null or img.is_empty():
		push_error("não abriu")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var mini := Image.new()
	mini.copy_from(img)
	mini.resize(w / MEIO, h / MEIO, Image.INTERPOLATE_BILINEAR)
	var mw: int = mini.get_width()
	var mch: int = mini.get_height()
	var cw := CW / MEIO
	var ch := CH / MEIO
	var d: PackedByteArray = mini.get_data()
	print("frame | raio  | corpo | direita | baixo")
	for q in QUADROS:
		var cx := (q % COLS) * cw
		var cy := int(q / COLS) * ch
		var raio := 0
		var corpo := 0
		var x1 := -1
		var y1 := -1
		for y in range(cy, mini(mch, cy + ch)):
			var base := y * mw * 4
			for x in range(cx, mini(mw, cx + cw)):
				var i := base + x * 4
				if d[i + 3] <= 8:
					continue
				corpo += 1
				var r := d[i]
				var g := d[i + 1]
				var b := d[i + 2]
				if g > 140 and b > 140 and r < g:
					raio += 1
				if x > x1:
					x1 = x
				if y > y1:
					y1 = y
		print("%5d | %5d | %5d | %6d | %5d" % [q + 1, raio, corpo, (x1 - cx + 1) * MEIO, (y1 - cy + 1) * MEIO])
	quit(0)
