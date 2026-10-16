extends SceneTree
## Acha as chamas (tochas/velas) pintadas em cada fundo de assets/Fundo e grava as posições em
## dados/tochas_fundo.json — o jogo desenha fogo animado e luz tremulando em cima de cada uma.
## Rodar: godot --headless --path . -s ferramentas/achar_tochas.gd   (DEBUG=1 grava imagens marcadas)

const PASTA := "res://assets/Fundo/"
const SAIDA := "res://dados/tochas_fundo.json"
## Janelas acesas que o detector confunde com chama (pixels da imagem 2560x1080).
const JANELAS := {
	"guerreiro_jpg": [Vector2(407, 90), Vector2(693, 194), Vector2(46, 293), Vector2(455, 690)],
	"monsters_png": [Vector2(393, 269), Vector2(243, 369), Vector2(300, 377)],
}

func _initialize() -> void:
	var res := {}
	var debug := OS.get_environment("DEBUG") == "1"
	# 1) os fundos de NOITE mostram as tochas sem confusão: viram o molde de onde ficam as tochas
	#    de cada castelo (todos os fundos de um castelo têm a mesma geometria)
	#    (a arte antiga .jpg e a nova .png têm castelos um pouco diferentes: cada família tem o seu molde)
	var moldes := {}
	for arq in DirAccess.get_files_at(PASTA):
		if arq.ends_with(".import") or not "noite" in arq:
			continue
		var im := Image.load_from_file(ProjectSettings.globalize_path(PASTA + arq))
		im.convert(Image.FORMAT_RGBA8)
		moldes[_familia(arq)] = _achar(im)
	for k in moldes:
		moldes[k] = moldes[k].filter(func(u):          # janelas acesas que parecem chama
			for p in JANELAS.get(k, []):
				if absf(u.x - p.x) < 30.0 and absf(u.y - p.y) < 40.0:
					return false
			return true)
		print("molde %s: %d tochas  %s" % [k, moldes[k].size(), str(moldes[k].map(func(u): return Vector2i(int(u.x), int(u.y))))])
	# 2) em cada fundo, fica só a tocha do molde que está ACESA ali (de dia algumas estão apagadas)
	for arq in DirAccess.get_files_at(PASTA):
		if not (arq.ends_with(".png") or arq.ends_with(".jpg") or arq.ends_with(".webp")):
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path(PASTA + arq))
		if img == null:
			continue
		img.convert(Image.FORMAT_RGBA8)
		var tochas := _acesas(img, moldes.get(_familia(arq), []))
		res[arq.get_basename()] = tochas
		print("%s: %d chamas" % [arq, tochas.size()])
		if debug:
			for t in tochas:
				var c := Vector2i(int(t.x), int(t.y))
				for d in range(-int(t.r) - 6, int(t.r) + 7):
					for e in [-int(t.r) - 6, int(t.r) + 6]:
						for p in [Vector2i(c.x + d, c.y + e), Vector2i(c.x + e, c.y + d)]:
							if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
								img.set_pixelv(p, Color(0, 1, 0))
			img.save_png(OS.get_environment("DEBUG_DIR").path_join("tochas_" + arq.get_basename() + ".png"))
	var f := FileAccess.open(SAIDA, FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "\t"))
	f.close()
	quit()

func _familia(arq: String) -> String:
	if arq.begins_with("arena_monsters_dia_largo."):
		return "monsters_png"                      # (esse .jpg já tem o castelo da arte nova)
	if arq.begins_with("arena_guerreiro_dia_largo."):
		return "nenhuma"                           # de dia as tochas desse fundo estão apagadas
	return ("monsters" if "monsters" in arq else "guerreiro") + ("_png" if arq.ends_with(".png") else "_jpg")

func _acesas(img: Image, molde: Array) -> Array:
	var out := []
	var w := img.get_width()
	var h := img.get_height()
	for t in molde:
		var quentes := 0
		var magicas := 0
		var fundo := int(t.y) + 4
		for yy in range(int(t.y) - 34, fundo):
			for xx in range(int(t.x) - 12, int(t.x) + 13):
				if xx < 0 or yy < 0 or xx >= w or yy >= h:
					continue
				var c := img.get_pixel(xx, yy)
				if c.r >= 0.85 and c.g >= 0.42 and c.b <= 0.6 and c.g >= c.b + 0.18 and c.r >= c.g + 0.05:   # (de dia a chama é laranja)
					quentes += 1
				elif c.r >= 0.78 and c.b >= 0.9 and c.g <= 0.92 and c.b >= c.g + 0.06:
					magicas += 1
		if quentes + magicas >= 12:
			out.append({"x": t.x, "y": t.y, "r": t.r, "magica": magicas > quentes})
	return out

## Núcleo da chama = pixel quase branco-amarelado (ou lilás nas tochas mágicas). Agrupa os vizinhos;
## manchas grandes (lua, janelas acesas) ou miúdas (estrelas) ficam de fora.
func _achar(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var marca := PackedByteArray()
	marca.resize(w * h)
	var dados := img.get_data()
	for y in h:
		for x in w:
			var i := (y * w + x) * 4
			var r := dados[i]; var g := dados[i + 1]; var b := dados[i + 2]
			var quente := r >= 245 and g >= 200 and b <= 200 and g >= b + 40           # amarelo-branco
			var magica := r >= 215 and b >= 245 and g >= 150 and g <= 235 and b >= g + 15  # lilás claro
			if quente:
				marca[y * w + x] = 1
			elif magica:
				marca[y * w + x] = 2
	var out := []
	var pilha := PackedInt32Array()
	for idx in w * h:
		if marca[idx] == 0:
			continue
		var tipo := marca[idx]
		marca[idx] = 0
		pilha.clear()
		pilha.append(idx)
		var n := 0
		var x0 := w; var x1 := 0; var y0 := h; var y1 := 0
		var sx := 0.0
		var linhas := {}
		while pilha.size() > 0:
			var k := pilha[pilha.size() - 1]
			pilha.remove_at(pilha.size() - 1)
			var px := k % w; var py := k / w
			linhas[py] = int(linhas.get(py, 0)) + 1
			n += 1
			sx += px
			x0 = mini(x0, px); x1 = maxi(x1, px); y0 = mini(y0, py); y1 = maxi(y1, py)
			for d in [-1, 1, -w, w, -w - 1, -w + 1, w - 1, w + 1]:
				var q: int = k + d
				if q >= 0 and q < w * h and marca[q] != 0 and absi(q % w - px) <= 1:
					marca[q] = 0
					pilha.append(q)
		var bw := x1 - x0 + 1
		var bh := y1 - y0 + 1
		if n < 10 or n > 900 or bw > 45 or bh > 60:
			continue
		if bh < bw * 0.7:                       # chama é mais alta que larga (janela/abóbora não)
			continue
		# chama AFINA para cima (janela acesa é um retângulo/arco cheio)
		var topo := 0.0
		var base := 0.0
		for yy in linhas:
			var k2 := float(yy - y0) / maxf(1.0, float(bh - 1))
			if k2 < 0.3:
				topo = maxf(topo, linhas[yy])
			elif k2 > 0.5:
				base = maxf(base, linhas[yy])
		if bh < 4:
			continue
		# a chama BRILHA: o entorno é bem mais escuro (cerca clara, nuvem e neve de dia não passam)
		var soma := 0.0
		var cont := 0
		for yy in range(y0 - 10, y1 + 11, 2):
			for xx in range(x0 - 10, x1 + 11, 2):
				if xx < 0 or yy < 0 or xx >= w or yy >= h:
					continue
				if xx >= x0 - 4 and xx <= x1 + 4 and yy >= y0 - 4 and yy <= y1 + 4:
					continue
				var j := (yy * w + xx) * 4
				soma += 0.3 * dados[j] + 0.55 * dados[j + 1] + 0.15 * dados[j + 2]
				cont += 1
		if cont == 0 or soma / cont > 140.0:
			continue
		out.append({"x": snappedf(sx / n, 0.1), "y": float(y1), "r": snappedf(maxf(bw, bh * 0.6), 0.1), "magica": tipo == 2})
	# junta núcleos muito perto (a mesma chama partida em dois)
	var final := []
	for t in out:
		var junto := false
		for u in final:
			if absf(u.x - t.x) < 22.0 and absf(u.y - t.y) < 40.0:
				u.y = maxf(u.y, t.y)
				u.r = maxf(u.r, t.r)
				junto = true
				break
		if not junto:
			final.append(t)
	return final
