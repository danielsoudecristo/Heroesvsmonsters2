extends SceneTree
## LIMPAR REPOUSO: gera as folhas de repouso (parado) dos esqueletos a partir da arte crua.
## Esqueleto normal: arte veio com chroma key (fundo verde) -> remove, despill, bleed e assa.
## Fogo / Arqueiro / Protetor: arte já chega transparente -> só despill leve (ponto verde esparsa).
## Todos: recorta o corpo, escala para casar com a ALTURA do andar (trocar sem pular) e assa
## 8 quadros de respiração (±1,2% vertical com o pé fixo no chão) em parado_repouso.png.
## Depois de rodar: --import das folhas novas e ajustar a anim "parado" em cada .tres.
## RODAR SEM ABRIR O EDITOR:
##   godot --headless --path "<pasta do projeto>" --script res://ferramentas/limpar_repouso.gd

const N_QUADROS := 8            # quadros do ciclo de respiração
const AMP := 0.012              # respiração: ±1,2% de altura
const PAD := 4                  # folga em volta do corpo na célula
const C_BAIXO := 0.25           # chroma key: abaixo disso é opaco (osso, contorno, roupa)
const C_ALTO := 0.55            # chroma key: acima disso é fundo verde

# alvo = altura do corpo na célula (= andar.ch x andar.escala da ficha); p_escala só para o print da tela
const FICHAS := [
	{
		"nome": "Esqueleto",
		"src": "res://assets/Esqueleto/parado/esqueleto repouso.png",
		"dst": "res://assets/Esqueleto/parado/parado_repouso.png",
		"chroma": true,
		"alvo": 194.6,
		"p_escala": 0.56,
		"andar": "res://assets_otimizados/Esqueleto/andando/andando_1_155x218.png",
		"andar_cw": 155, "andar_ch": 218, "andar_escala": 0.8928571428571428,
	},
	{
		"nome": "Esqueleto de Fogo",
		"src": "res://assets/Esqueleto de Fogo/parado/parado.png",
		"dst": "res://assets/Esqueleto de Fogo/parado/parado_repouso.png",
		"chroma": false,
		"alvo": 237.0,
		"p_escala": 0.47,
		"andar": "res://assets/Esqueleto de Fogo/andando/andando.png",
		"andar_cw": 175, "andar_ch": 248, "andar_escala": 1.0,
	},
	{
		"nome": "Esqueleto Arqueiro",
		"src": "res://assets/Esqueleto Arqueiro/parado/parado.png",
		"dst": "res://assets/Esqueleto Arqueiro/parado/parado_repouso.png",
		"chroma": false,
		"alvo": 190.0,
		"p_escala": 0.58,
		"andar": "res://assets/Esqueleto Arqueiro/andando/andando.png",
		"andar_cw": 161, "andar_ch": 190, "andar_escala": 1.0,
	},
	{
		"nome": "Esqueleto Protetor",
		"src": "res://assets/Esqueleto Protetor/parado/parado.png",
		"dst": "res://assets/Esqueleto Protetor/parado/parado_repouso.png",
		"chroma": false,
		"alvo": 189.0,
		"p_escala": 0.61,
		"andar": "res://assets/Esqueleto Protetor/andando/andando.png",
		"andar_cw": 135, "andar_ch": 189, "andar_escala": 1.0,
	},
]

func _initialize() -> void:
	var falhou := false
	for f in FICHAS:
		if not _processar(f):
			falhou = true
	quit(1 if falhou else 0)

func _processar(f: Dictionary) -> bool:
	var nome := String(f.nome)
	print("\n===== %s =====" % nome)
	var img := Image.load_from_file(ProjectSettings.globalize_path(String(f.src)))
	if img == null or img.is_empty():
		push_error("Não abriu: " + String(f.src))
		return false
	img.convert(Image.FORMAT_RGBA8)
	print("arte origem: %dx%d" % [img.get_width(), img.get_height()])

	# ---- despill leve: segura qualquer resto de verde (osso/chama nunca têm g > max(r,b))
	var dados := img.get_data()
	var n := dados.size() / 4
	var despillados := 0
	for i in n:
		var o := i * 4
		var mx := maxi(dados[o], dados[o + 2])
		if dados[o + 1] > mx:
			if f.chroma:
				pass   # o chroma key abaixo trata (com alfa e tolerância)
			else:
				dados[o + 1] = mx
				despillados += 1
	if not f.chroma:
		img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, dados)
		print("despill leve: %d pixels com halo verde" % despillados)

	if f.chroma:
		var removidos := 0
		dados = img.get_data()
		for i in n:
			var o := i * 4
			var r := float(dados[o])
			var g := float(dados[o + 1])
			var b := float(dados[o + 2])
			var luz := maxf(0.299 * r + 0.587 * g + 0.114 * b, 40.0)
			var c := (g - (r + b) * 0.5) / luz
			if c > C_ALTO:
				dados[o + 3] = 0
				removidos += 1
			elif c > C_BAIXO:
				var alfa := clampf((C_ALTO - c) / (C_ALTO - C_BAIXO), 0.0, 1.0)
				dados[o + 3] = int(alfa * 255.0 + 0.5)
				var mx2 := maxf(r, b)
				if g > mx2:
					dados[o + 1] = int(mx2 + 0.5)
			elif g > maxf(r, b):
				dados[o + 1] = int(maxf(r, b) + 0.5)
		img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, dados)
		print("chroma key: %d pixels de fundo removidos (%.1f%%)" % [removidos, 100.0 * removidos / float(n)])

	var bb := img.get_used_rect()
	if bb.size.y <= 0:
		push_error("nada sobrou depois da limpeza: " + nome)
		return false
	print("corpo em %s" % str(bb))

	var corpo := img.get_region(bb)

	if f.chroma:
		# BLEED: puxa a cor do corpo para dentro dos pixels transparentes (3 passadas).
		# Sem isso, o filtro bilinear do Godot puxa o RGB verde que ficou em a=0 e cria halo na borda.
		var largura := corpo.get_width()
		var altura := corpo.get_height()
		for _passada in 3:
			var dados_c := corpo.get_data()
			var novo := dados_c.duplicate()
			for y in altura:
				for x in largura:
					var o := (y * largura + x) * 4
					if dados_c[o + 3] != 0:
						continue
					var sr := 0
					var sg := 0
					var sb := 0
					var achou := 0
					var vizes: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
					for viz in vizes:
						var vx: int = x + viz.x
						var vy: int = y + viz.y
						if vx < 0 or vy < 0 or vx >= largura or vy >= altura:
							continue
						var vo: int = (vy * largura + vx) * 4
						if dados_c[vo + 3] == 0:
							continue
						sr += dados_c[vo]
						sg += dados_c[vo + 1]
						sb += dados_c[vo + 2]
						achou += 1
					if achou > 0:
						novo[o] = sr / achou
						novo[o + 1] = sg / achou
						novo[o + 2] = sb / achou
			corpo.set_data(largura, altura, false, Image.FORMAT_RGBA8, novo)

	# ---- paridade com o andar: mede o corpo do quadro 0 da folha andar
	var e_andar := 0.0
	var img_andar := Image.load_from_file(ProjectSettings.globalize_path(String(f.andar)))
	if img_andar != null and not img_andar.is_empty():
		img_andar.convert(Image.FORMAT_RGBA8)
		var cel := img_andar.get_region(Rect2i(0, 0, int(f.andar_cw), int(f.andar_ch)))
		var bb2 := cel.get_used_rect()
		e_andar = float(bb2.size.y) * float(f.andar_escala)
		print("andar quadro0: corpo %d px x escala %.4f = %.1f px de corpo (~%.0f na tela)" % [
			bb2.size.y, float(f.andar_escala), e_andar, e_andar * float(f.p_escala)])

	var escala := float(f.alvo) / float(bb.size.y)
	var sw := maxi(1, int(round(bb.size.x * escala)))
	var sh := maxi(1, int(round(bb.size.y * escala)))
	corpo.resize(sw, sh, Image.INTERPOLATE_LANCZOS)
	print("escala %.4f: corpo %dx%d (~%.0f px na tela com p.escala %s)" % [
		escala, sw, sh, sh * float(f.p_escala), str(f.p_escala)])
	if e_andar > 0.0:
		print("paridade repouso->andar: %+.1f px" % (float(sh) - e_andar))

	var ncw := sw + PAD * 2
	var nch := sh + PAD * 2 + 2   # +2: a respiração cresce pra cima
	var saida := Image.create_empty(N_QUADROS * ncw, nch, false, Image.FORMAT_RGBA8)
	for i in N_QUADROS:
		var s := sin(TAU * i / N_QUADROS)
		var sy := 1.0 + AMP * s
		var cel := corpo.get_region(Rect2i(Vector2i.ZERO, corpo.get_size()))
		cel.resize(sw, maxi(1, int(round(float(sh) * sy))), Image.INTERPOLATE_LANCZOS)
		# alinha pelo FUNDO: o pé continua no chão, só o topo sobe/desce
		saida.blit_rect(cel, Rect2i(Vector2i.ZERO, cel.get_size()),
			Vector2i(i * ncw + PAD, nch - PAD - cel.get_height()))

	# prévia compositando o alpha sobre cinza
	var pw := int(ncw * 0.4)
	var ph := int(nch * 0.4)
	var previa := Image.create_empty(pw * N_QUADROS, ph, false, Image.FORMAT_RGBA8)
	previa.fill(Color(0.15, 0.15, 0.17, 1.0))
	for i in N_QUADROS:
		var cel := saida.get_region(Rect2i(i * ncw, 0, ncw, nch))
		cel.resize(pw, ph, Image.INTERPOLATE_BILINEAR)
		for y in ph:
			for x in pw:
				var cor := cel.get_pixel(x, y)
				var dest := previa.get_pixel(i * pw + x, y)
				previa.set_pixel(i * pw + x, y, dest.blend(cor))
	var previa_dir := "C:/Users/danie/AppData/Local/Temp/opencode"
	var slug := String(f.nome).to_lower().replace(" ", "_").replace("ê", "e")
	var previa_path := "%s/previa_repouso_%s.png" % [previa_dir, slug]
	previa.save_png(previa_path)
	print("prévia salva em " + previa_path)

	DirAccess.make_dir_recursive_absolute(String(f.dst).get_base_dir())
	var err := saida.save_png(ProjectSettings.globalize_path(String(f.dst)))
	if err != OK:
		push_error("Erro %d ao salvar %s" % [err, String(f.dst)])
		return false
	print("SALVO: %s = %dx%d (%d quadros de %dx%d, 1 linha)" % [
		String(f.dst), saida.get_width(), saida.get_height(), N_QUADROS, ncw, nch])
	print("--- valores para a ficha (anims.parado) ---")
	print("quadros = %d" % N_QUADROS)
	print("cols = %d" % N_QUADROS)
	print("cw = %d" % ncw)
	print("ch = %d" % nch)
	print("ax = %.1f" % (ncw / 2.0))
	print("ay = %.1f" % float(nch - PAD))
	print("fps = 10.0")
	print("escala = 1.0   # altura já igual ao andar")
	return true
