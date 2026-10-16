extends "res://ferramentas/cortar_bombardeiro_ataque.gd"
## CORTAR BOMBARDEIRO — MORRENDO: a folha "morrendo" (68 quadros de 1280x720, grade 9x8): ele segura a bomba,
## o pavio acende e a bomba EXPLODE na mão dele, espalhando os ossos. A explosão pintada FICA (é a morte dele);
## sai só o verde: contorno, faíscas verdes do pavio e o tom esverdeado (despill).
## Mesmo tamanho na tela do andar/parado e o tronco na mesma âncora (não pula quando começa a morrer).
## Diz o quadro do estouro (o jogo soma a explosão dele ali) e o quadro em que a vaga fica livre.
## RODAR: godot --headless --path . --script res://ferramentas/cortar_bombardeiro_morrendo.gd

const ORIGEM_MORTE := "res://assets/Esqueleto Bombardeiro/morrendo/morrendo.png"
const COLS_MORTE := 9
const QUADROS_MORTE := 68

func _reg_m(n: int) -> Rect2i:
	return Rect2i((n % COLS_MORTE) * CEL.x, (n / COLS_MORTE) * CEL.y, CEL.x, CEL.y)

func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ORIGEM_MORTE))
	img.convert(Image.FORMAT_RGBA8)
	var x0 := CEL.x; var y0 := CEL.y; var x1 := 0; var y1 := 0
	var alturas: Array[float] = []
	var claridade: Array[float] = []
	for n in QUADROS_MORTE:
		var q0 := img.get_region(_reg_m(n))
		var u := q0.get_used_rect()
		if u.size.x <= 0:
			claridade.append(0.0)
			continue
		x0 = mini(x0, u.position.x); y0 = mini(y0, u.position.y)
		x1 = maxi(x1, u.end.x); y1 = maxi(y1, u.end.y)
		if n < 30:
			alturas.append(float(u.size.y))
		claridade.append(_quente(q0, u))
	x0 = maxi(0, x0 - PAD); y0 = maxi(0, y0 - PAD); x1 = mini(CEL.x, x1 + PAD); y1 = mini(CEL.y, y1 + PAD)
	# mesmo tamanho do andar: o andar usa ALTURA_TELA para a altura mediana do desenho em pé
	var fator := ALTURA_TELA / ESCALA_TELA / _mediana(alturas)
	var cw := roundi((x1 - x0) * fator)
	var ch := roundi((y1 - y0) * fator)
	var quadros: Array[Image] = []
	var tirados := 0
	for n in QUADROS_MORTE:
		var q := img.get_region(Rect2i(_reg_m(n).position + Vector2i(x0, y0), Vector2i(x1 - x0, y1 - y0)))
		q.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
		tirados += _sem_verde(q)
		quadros.append(q)
	var cols := mini(int(LIMITE / cw), QUADROS_MORTE)
	var linhas := ceili(float(QUADROS_MORTE) / cols)
	if linhas * ch > LIMITE:
		push_error("folha ficaria %dx%d" % [cols * cw, linhas * ch])
		quit(1)
		return
	var saida := Image.create_empty(cols * cw, linhas * ch, false, Image.FORMAT_RGBA8)
	for n in QUADROS_MORTE:
		saida.blit_rect(quadros[n], Rect2i(0, 0, cw, ch), Vector2i((n % cols) * cw, (n / cols) * ch))
	var nome := "%s/morrendo_%dx%d.png" % [PASTA, cw, ch]
	saida.save_png(ProjectSettings.globalize_path(nome))
	# âncora pelo tronco (igual ao parado)
	var par := Image.load_from_file(ProjectSettings.globalize_path(PASTA + "/parado_233x270.png"))
	par.convert(Image.FORMAT_RGBA8)
	var ax := _tronco_x(quadros[0]) - (_tronco_x(par) - PARADO_AX)
	var ay := float(quadros[0].get_used_rect().end.y) - (float(par.get_used_rect().end.y) - PARADO_AY)
	# estouro: o 1º quadro com MUITO fogo claro (o clarão da bomba)
	var maior: float = claridade.max()
	var estouro := 0
	for n in QUADROS_MORTE:
		if claridade[n] >= maior * 0.55 and n > 20:
			estouro = n
			break
	# centro do estouro (no quadro novo) — onde o jogo põe a explosão dele
	var cq := quadros[estouro].get_used_rect().get_center()
	print("SALVO: %s (%dx%d, %d quadros de %dx%d, %d colunas)" % [nome, saida.get_width(), saida.get_height(), QUADROS_MORTE, cw, ch, cols])
	print("verde tirado: %d px" % tirados)
	print("cols = %d\nquadros = %d\ncw = %d\nch = %d\nax = %.1f\nay = %.1f" % [cols, QUADROS_MORTE, cw, ch, ax, ay])
	print("ESTOURO_QUADRO=%d (contando do 1: %d)" % [estouro, estouro + 1])
	print("ESTOURO_PONTO=" + JSON.stringify([snappedf(cq.x, 0.1), snappedf(cq.y, 0.1)]))
	quit(0)

## Quanto de fogo claro (amarelo/branco quente) tem no quadro.
func _quente(q: Image, u: Rect2i) -> float:
	var n := 0
	for y in range(u.position.y, u.end.y, 4):
		for x in range(u.position.x, u.end.x, 4):
			var c := q.get_pixel(x, y)
			if c.a > 0.5 and c.r > 0.9 and c.g > 0.75 and c.b < 0.7:
				n += 1
	return float(n)

## Tira o verde e devolve quantos pixels mexeu: borda esverdeada some (2 passadas), faísca verde viva some,
## o resto perde o tom verde. A explosão (amarelo/laranja/branco) não tem verde e fica igual.
func _sem_verde(q: Image) -> int:
	var w := q.get_width(); var h := q.get_height()
	var n := 0
	for passada in 2:
		var apagar: Array[Vector2i] = []
		for y in h:
			for x in w:
				var c := q.get_pixel(x, y)
				if c.a < 0.02:
					continue
				var verde := c.g - maxf(c.r, c.b)
				if (verde > 0.03 and _na_borda(q, x, y, w, h)) or (c.g > 0.6 and verde > 0.25):
					apagar.append(Vector2i(x, y))
		for p in apagar:
			q.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
		n += apagar.size()
	for y in h:
		for x in w:
			var c := q.get_pixel(x, y)
			if c.a < 0.02:
				continue
			var verde := c.g - maxf(c.r, c.b)
			if verde > 0.0:
				c.g = maxf(c.r, c.b) + verde * 0.15
				q.set_pixel(x, y, c)
				n += 1
	return n
