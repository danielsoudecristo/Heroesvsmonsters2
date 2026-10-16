extends SceneTree
## Acha a PONTA DA FLECHA (a ponta roxa) em cada quadro do "atacar" de um arqueiro e imprime a lista
## [x, y] (pixels do quadro; -1 = sem flecha no arco) para pôr no extra "ponta_flecha" da ficha.
## O fogo das Flechas de Fogo fica grudado nessa ponta enquanto ele mira.
## Rodar: godot --headless --path . -s ferramentas/medir_ponta_flecha.gd -- esqueletoArqueiro

func _initialize() -> void:
	var id: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "esqueletoArqueiro"
	var p: PersonagemDados = load("res://dados/personagens/%s.tres" % id)
	var a: AnimDados = p.anim("atacar")
	var img := Image.load_from_file(ProjectSettings.globalize_path(a.textura.resource_path))
	img.convert(Image.FORMAT_RGBA8)
	var lista := []
	for q in a.quadros:
		var r := Rect2i(a.retangulo(q))
		var mx := -1
		var ys := []
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var c := img.get_pixel(x, y)
				if c.a > 0.5 and c.b > 0.45 and c.b > c.r + 0.12 and c.b > c.g + 0.2:
					var lx := x - r.position.x
					if lx > mx + 2:
						ys = [y - r.position.y]
						mx = lx
					elif lx >= mx - 2:
						ys.append(y - r.position.y)
						mx = maxi(mx, lx)
		if mx < 0 or ys.size() < 2:
			lista.append([-1, -1])
		else:
			var soma := 0
			for v in ys:
				soma += int(v)
			lista.append([mx, roundi(float(soma) / ys.size())])
	print("ESC=", p.escala * a.escala, " AX=", a.ax, " AY=", a.ay, " ACAO=", a.quadros_acao)
	print("PONTA=", JSON.stringify(lista))
	quit()
