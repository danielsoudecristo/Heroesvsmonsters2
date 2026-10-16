extends "res://ferramentas/cortar_bombardeiro.gd"
## CORTAR BOMBARDEIRO — ATAQUE: a folha grande "jogando bomba na frente do personagem" (120 quadros 1280x720)
## vira a folha "atacando" do jogo, com a mesma limpeza do andar (sem contorno verde, sem a chama pintada:
## o jogo desenha o fogo do pavio) e:
##  - acha o quadro em que a bomba TOCA O CHÃO -> é o quadro da explosão (quadros_acao);
##  - daquele quadro em diante a bomba SOME da folha (quem aparece é a explosão do jogo);
##  - guarda o fogo do pavio quadro a quadro (com a bomba na mão e voando) e o ponto da explosão.
## Mesmo tamanho na tela do andar (altura do corpo nos quadros parados do começo).
## RODAR: godot --headless --path . --script res://ferramentas/cortar_bombardeiro_ataque.gd

const ORIGEM_ATK := "res://assets/Esqueleto Bombardeiro/jogando bomba na frente do personagem/jogando bomba na frente do personagem.png"
const PARADO_AX := 98.5               ## âncora da folha parado (a mesma do andar, ficha)
const PARADO_AY := 262.0
const PECA_MIN := 220                ## peça solta com pelo menos isso de pixels fica (a bomba); menor some (faísca, sobra)

func _initialize() -> void:
	manter_pecas_de = PECA_MIN
	var img := Image.load_from_file(ProjectSettings.globalize_path(ORIGEM_ATK))
	img.convert(Image.FORMAT_RGBA8)
	var x0 := CEL.x; var y0 := CEL.y; var x1 := 0; var y1 := 0
	var alturas: Array[float] = []
	for n in QUADROS:
		var u := img.get_region(_reg(n)).get_used_rect()
		x0 = mini(x0, u.position.x); y0 = mini(y0, u.position.y)
		x1 = maxi(x1, u.end.x); y1 = maxi(y1, u.end.y)
		if n < 20:                                       # segurando a bomba (pose parecida com a do andar)
			alturas.append(float(u.size.y))
	x0 = maxi(0, x0 - PAD); y0 = maxi(0, y0 - PAD); x1 = mini(CEL.x, x1 + PAD); y1 = mini(CEL.y, y1 + PAD)
	var fator := ALTURA_TELA / ESCALA_TELA / _mediana(alturas)
	var cw := roundi((x1 - x0) * fator)
	var ch := roundi((y1 - y0) * fator)
	var quadros: Array[Image] = []
	var pavio: Array = []
	var bomba: Array = []                                # [centro x, fundo y] da bomba solta, ou [-1,-1]
	for n in QUADROS:
		var q := img.get_region(Rect2i(_reg(n).position + Vector2i(x0, y0), Vector2i(x1 - x0, y1 - y0)))
		q.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
		var pv: Array = _limpar(q)
		var pecas := _pecas(q)
		if pecas.size() > 1:                             # bomba voando: a chama fica no topo dela (quase sem brilho verde)
			var bb: Dictionary = pecas[1]
			var tirou := _apagar_fogo_perto(q, Vector2(float(bb.cx) + 18.0, float(bb.topo) - 14.0), 58.0)
			if tirou[2] > 3.0:
				pv = [snappedf(tirou[0] / tirou[2], 0.1), snappedf(tirou[1] / tirou[2], 0.1)]
			_so_o_corpo(q, Vector2.ZERO, 0.0)           # some com os pontinhos que sobraram soltos (a bomba fica)
			pecas = _pecas(q)
		pavio.append(pv)
		bomba.append([pecas[1].cx, pecas[1].fundo] if pecas.size() > 1 else [-1, -1])
		quadros.append(q)
	# quadro em que a bomba toca o chão: a 1ª vez que o fundo dela chega perto do mais baixo que ela vai
	var mais_baixo := -1.0
	for b in bomba:
		mais_baixo = maxf(mais_baixo, float(b[1]))
	var explode := -1
	for n in QUADROS:
		if bomba[n][1] >= 0 and float(bomba[n][1]) >= mais_baixo - 2.0:
			explode = n
			break
	if explode < 0:
		push_error("não achei a bomba caindo")
		quit(1)
		return
	var ponto: Array = bomba[explode]
	# quadro em que a bomba SAI DA MÃO (1ª vez solta, depois de preparar o arremesso)
	var solta := -1
	for n in range(20, explode + 1):
		if float(bomba[n][0]) >= 0.0:
			solta = n
			break
	# a imagem da bomba (o jogo desenha ela voando até o inimigo, por cima de todos)
	var img_bomba := _so_a_bomba(quadros[solta])
	var ret_b := img_bomba.get_used_rect()
	var centro_b := Vector2(ret_b.position) + Vector2(ret_b.size) / 2.0
	# tira o resto de chama pintada grudado na bomba (o pavio marrom fica) e recorta de novo
	for y in img_bomba.get_height():
		for x in img_bomba.get_width():
			var cb := img_bomba.get_pixel(x, y)
			if cb.a > 0.05 and cb.r > 0.45 and cb.g > 0.18 and cb.r - cb.b > 0.32:
				img_bomba.set_pixel(x, y, Color(0, 0, 0, 0))
	ret_b = img_bomba.get_used_rect()
	centro_b = Vector2(ret_b.position) + Vector2(ret_b.size) / 2.0
	var bomba_png := img_bomba.get_region(ret_b)
	var nome_b := "%s/bomba_%dx%d.png" % [PASTA, ret_b.size.x, ret_b.size.y]
	bomba_png.save_png(ProjectSettings.globalize_path(nome_b))
	# ponta do pavio = o ponto mais alto da metade direita da bomba (é dali que sai o fogo)
	var fogo_na_bomba := [ret_b.size.x * 0.75, 2.0]
	for y in bomba_png.get_height():
		var achou := false
		for x in range(bomba_png.get_width() / 2, bomba_png.get_width()):
			if bomba_png.get_pixel(x, y).a > 0.3:
				fogo_na_bomba = [x, y]
				achou = true
				break
		if achou:
			break
	# da hora que solta em diante: só o corpo na folha (a bomba e o fogo dela são do jogo)
	manter_pecas_de = 1 << 30
	for n in range(solta, QUADROS):
		_so_o_corpo(quadros[n], Vector2.ZERO, 0.0)
		pavio[n] = [-1, -1]
	var cols := mini(int(LIMITE / cw), QUADROS)
	var linhas := ceili(float(QUADROS) / cols)
	if linhas * ch > LIMITE:
		push_error("folha ficaria %dx%d" % [cols * cw, linhas * ch])
		quit(1)
		return
	var saida := Image.create_empty(cols * cw, linhas * ch, false, Image.FORMAT_RGBA8)
	var pes: Array[float] = []
	var chaos: Array[float] = []
	for n in QUADROS:
		saida.blit_rect(quadros[n], Rect2i(0, 0, cw, ch), Vector2i((n % cols) * cw, (n / cols) * ch))
		if n < 20:
			var corpo: Dictionary = _pecas(quadros[n])[0]
			chaos.append(float(corpo.fundo))
			var faixa := 8
			var fp := quadros[n].get_region(Rect2i(0, int(corpo.fundo) - faixa, cw, faixa)).get_used_rect()
			pes.append(fp.position.x + fp.size.x / 2.0)
	var nome := "%s/atacando_%dx%d.png" % [PASTA, cw, ch]
	saida.save_png(ProjectSettings.globalize_path(nome))
	var ax := _mediana(pes)
	var ay := _mediana(chaos)
	# alinha pelo TRONCO com o parado (os pés do andar e do ataque ficam em lugares diferentes da folha):
	# assim ele não pula para frente/para trás ao trocar parado <-> atacando
	var par := Image.load_from_file(ProjectSettings.globalize_path(PASTA + "/parado_233x270.png"))
	if par:
		par.convert(Image.FORMAT_RGBA8)
		var up := par.get_used_rect()
		var ua := quadros[0].get_used_rect()
		ax = _tronco_x(quadros[0]) - (_tronco_x(par) - PARADO_AX)     # tronco à mesma distância da âncora
		ay = float(ua.end.y) - (float(up.end.y) - PARADO_AY)           # chão na mesma altura
	print("SALVO: %s (%dx%d, %d quadros de %dx%d, %d colunas)" % [nome, saida.get_width(), saida.get_height(), QUADROS, cw, ch, cols])
	print("cols = %d\ncw = %d\nch = %d\nax = %.1f\nay = %.1f" % [cols, cw, ch, ax, ay])
	print("bomba solta (x,fundo) quadros 30-70: %s" % str(bomba.slice(30, 70).map(func(b): return [int(b[0]), int(b[1])])))
	print("EXPLODE_QUADRO=%d (contando do 1: %d)" % [explode, explode + 1])
	print("EXPLODE_PONTO=" + JSON.stringify(ponto))
	print("na tela: a bomba cai %.0f px à frente dos pés" % ((float(ponto[0]) - ax) * ESCALA_TELA))
	print("SOLTA_QUADRO=%d" % solta)
	print("SOLTA_PONTO=" + JSON.stringify([snappedf(centro_b.x, 0.1), snappedf(centro_b.y, 0.1)]))
	print("BOMBA_IMG=" + nome_b)
	print("FOGO_NA_BOMBA=" + JSON.stringify(fogo_na_bomba))
	print("PAVIO_ATACAR=" + JSON.stringify(pavio))
	quit(0)

## Meio (x) do tronco: faixa de 35% a 55% da altura do desenho.
func _tronco_x(q: Image) -> float:
	var u := q.get_used_rect()
	var t := q.get_region(Rect2i(0, u.position.y + int(u.size.y * 0.35), q.get_width(), int(u.size.y * 0.2))).get_used_rect()
	return t.position.x + t.size.x / 2.0

## Cópia do quadro só com a 2ª maior peça (a bomba solta).
func _so_a_bomba(q: Image) -> Image:
	var c := q.duplicate() as Image
	var w := c.get_width(); var h := c.get_height()
	var rotulo := PackedInt32Array(); rotulo.resize(w * h)
	var tam: Array[int] = [0]
	for y in h:
		for x in w:
			if rotulo[y * w + x] != 0 or c.get_pixel(x, y).a < 0.05:
				continue
			var id := tam.size()
			var n := 0
			var fila: Array[Vector2i] = [Vector2i(x, y)]
			rotulo[y * w + x] = id
			while not fila.is_empty():
				var p: Vector2i = fila.pop_back()
				n += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
					var v: Vector2i = p + d
					if v.x >= 0 and v.y >= 0 and v.x < w and v.y < h and rotulo[v.y * w + v.x] == 0 and c.get_pixel(v.x, v.y).a >= 0.05:
						rotulo[v.y * w + v.x] = id
						fila.append(v)
			tam.append(n)
	var ordem: Array = range(1, tam.size())
	ordem.sort_custom(func(a, b): return tam[a] > tam[b])
	var segunda: int = ordem[1] if ordem.size() > 1 else -1
	for y in h:
		for x in w:
			if rotulo[y * w + x] != segunda:
				c.set_pixel(x, y, Color(0, 0, 0, 0))
	return c

## Peças do desenho (ligadas), da maior para a menor: {n, cx, fundo}.
func _pecas(q: Image) -> Array:
	var w := q.get_width(); var h := q.get_height()
	var rotulo := PackedInt32Array(); rotulo.resize(w * h)
	var lista: Array = []
	for y in h:
		for x in w:
			if rotulo[y * w + x] != 0 or q.get_pixel(x, y).a < 0.05:
				continue
			var id := lista.size() + 1
			var n := 0; var sx := 0.0; var fundo := 0; var topo := h
			var fila: Array[Vector2i] = [Vector2i(x, y)]
			rotulo[y * w + x] = id
			while not fila.is_empty():
				var p: Vector2i = fila.pop_back()
				n += 1; sx += p.x; fundo = maxi(fundo, p.y); topo = mini(topo, p.y)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
					var v: Vector2i = p + d
					if v.x >= 0 and v.y >= 0 and v.x < w and v.y < h and rotulo[v.y * w + v.x] == 0 and q.get_pixel(v.x, v.y).a >= 0.05:
						rotulo[v.y * w + v.x] = id
						fila.append(v)
			lista.append({"n": n, "cx": sx / n, "fundo": fundo, "topo": topo})
	lista.sort_custom(func(a, b): return a.n > b.n)
	return lista

## Apaga o fogo pintado perto de um ponto (laranja/amarelo saturado ou miolo claro amarelado; o corpo
## preto da bomba e o crânio branco dela ficam). Devolve [soma x, soma y, n] do que apagou.
func _apagar_fogo_perto(q: Image, centro: Vector2, raio: float) -> Array:
	var w := q.get_width(); var h := q.get_height()
	var sx := 0.0; var sy := 0.0; var n := 0.0
	for y in range(maxi(0, int(centro.y - raio)), mini(h, int(centro.y + raio))):
		for x in range(maxi(0, int(centro.x - raio)), mini(w, int(centro.x + raio))):
			if Vector2(x, y).distance_to(centro) > raio:
				continue
			var c := q.get_pixel(x, y)
			if c.a < 0.05:
				continue
			var saturado := c.r > 0.45 and c.g > 0.18 and c.r - c.b > 0.32        # (o pavio marrom tem r-b ~0,25: fica)
			var miolo := c.r + c.g + c.b > 2.4 and c.r - c.b > 0.3
			if saturado or miolo:
				q.set_pixel(x, y, Color(0, 0, 0, 0))
				sx += x; sy += y; n += 1.0
	return [sx, sy, n]
