extends SceneTree
## Descobre a grade de uma folha (perfil de colunas/linhas sem pixels).
## Uso: godot --headless --path "<projeto>" --script res://ferramentas/grade_andando.gd -- "res://assets/.../folha.png"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var caminho := args[0] if args.size() > 0 else "res://assets/Guerreiro Protetor/andando/andando.png"
	var img := Image.load_from_file(ProjectSettings.globalize_path(caminho))
	if img == null or img.is_empty():
		push_error("não abriu " + caminho)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	print("%s: %dx%d" % [caminho.get_file(), w, h])
	var dados := img.get_data()

	var vazio_c := PackedByteArray()
	vazio_c.resize(w)
	for x in range(w):
		var achou := false
		var y := 0
		while y < h:
			if dados[(y * w + x) * 4 + 3] > 8:
				achou = true
				break
			y += 8
		vazio_c[x] = 0 if achou else 1

	var vazio_l := PackedByteArray()
	vazio_l.resize(h)
	for y in range(h):
		var achou := false
		var x := 0
		while x < w:
			if dados[(y * w + x) * 4 + 3] > 8:
				achou = true
				break
			x += 8
		vazio_l[y] = 0 if achou else 1

	_runs("colunas vazias", vazio_c)
	_runs("linhas vazias", vazio_l)

	var cand := []
	for cols in range(4, 25):
		if w % cols != 0:
			continue
		var cw := w / cols
		for linhas in range(4, 25):
			if h % linhas != 0:
				continue
			var ch := h / linhas
			var asp := float(cw) / float(ch)
			if asp >= 0.6 and asp <= 2.0:
				cand.append("%d x %d (célula %dx%d)" % [cols, linhas, cw, ch])
	print("grades possíveis: %s" % " | ".join(cand))
	quit(0)

func _runs(titulo: String, perfil: PackedByteArray) -> void:
	var saida := []
	var i := 0
	while i < perfil.size():
		if perfil[i] == 1:
			var j := i
			while j < perfil.size() and perfil[j] == 1:
				j += 1
			if j - i >= 2:
				saida.append("%d..%d(%d)" % [i, j - 1, j - i])
			i = j
		else:
			i += 1
	print("%s: %d trechos -> %s" % [titulo, saida.size(), " ".join(saida)])
