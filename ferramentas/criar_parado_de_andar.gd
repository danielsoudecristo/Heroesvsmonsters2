extends SceneTree
## CRIAR PARADO A PARTIR DO ANDAR: pega, na folha de andar já otimizada, o quadro com as pernas mais
## juntas (pose de pé) e salva como uma folha "parado" de 1 quadro só, do MESMO tamanho de célula
## (o ax/ay do andar continua valendo: ele não pula ao parar). O jogo faz a respiração.
## RODAR:
##   godot --headless --path . --script res://ferramentas/criar_parado_de_andar.gd -- folha="res://assets_otimizados/X/andando_WxH.png" cols=16 quadros=120 cw=241 ch=266

func _initialize() -> void:
	var a := {}
	for x in OS.get_cmdline_user_args():
		var kv := x.split("=", true, 1)
		if kv.size() == 2:
			a[kv[0]] = kv[1].trim_prefix("\"").trim_suffix("\"")
	var folha: String = a.get("folha", "")
	var cols := int(a.get("cols", "1"))
	var n_q := int(a.get("quadros", "1"))
	var cw := int(a.get("cw", "0"))
	var ch := int(a.get("ch", "0"))
	var img := Image.load_from_file(ProjectSettings.globalize_path(folha))
	img.convert(Image.FORMAT_RGBA8)
	var melhor := 0
	var menor := INF
	for n in n_q:
		var q := img.get_region(Rect2i((n % cols) * cw, (n / cols) * ch, cw, ch))
		var u := q.get_used_rect()
		var faixa := maxi(3, int(u.size.y * 0.07))
		var largura := float(q.get_region(Rect2i(0, u.end.y - faixa, cw, faixa)).get_used_rect().size.x)
		if largura < menor:
			menor = largura
			melhor = n
	var parado := img.get_region(Rect2i((melhor % cols) * cw, (melhor / cols) * ch, cw, ch))
	var saida := folha.get_base_dir() + "/parado_%dx%d.png" % [cw, ch]
	parado.save_png(ProjectSettings.globalize_path(saida))
	print("PARADO: quadro %d do andar (pernas mais juntas: %.0f px) -> %s" % [melhor + 1, menor, saida])
	quit(0)
