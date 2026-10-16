extends SceneTree
## CORTAR ENGENHEIRO: a folha grande do Engenheiro Arcano (118 quadros de 1280x720) vira duas
## folhas leves para o jogo, com o PÉ no mesmo ponto das duas (ele não pula ao trocar de animação):
##   atacando = quadros 1..33 (o raio saindo do canhão) · parado = quadros 34..118 (repouso)
## Cada quadro é colado ALINHADO pelo centro dos pés e pelo chão, então some o "deslize" da
## filmagem original. A ponta do raio ganha um degradê para não terminar cortado no ar.
## RODAR: godot --headless --path "<pasta do projeto>" --script res://ferramentas/cortar_engenheiro.gd

const ORIGEM := "res://assets/Engenheiro Arcano/Engenheiro Arcano repouso+atirando.png"
const PASTA := "res://assets_otimizados/Engenheiro Arcano"
const CEL := Vector2i(1280, 720)          ## tamanho de cada quadro na folha grande
const COLS_GRANDE := 11                   ## a folha grande é 11 x 11 quadros
const Q_TIRO := [1, 33]                   ## quadros que ATIRAM (contando do 1, como no arquivo)
const Q_REP := [34, 118]                  ## quadros de REPOUSO
const ALVO_TELA := 150.0                  ## altura do corpo (repouso) em pixels na tela
const QUALIDADE := 2.0                     ## px da folha para cada px da tela (igual ao otimizar_folhas.gd)
const LIMITE := 4096                      ## tamanho máximo da folha gerada
const PAD := 8                            ## margem (em px da folha grande) em volta do corpo
const ALFA := 14                          ## alpha (0-255) mínimo para contar como desenho
const ALFA_SOLIDO := 96                   ## alpha do CORPO (ignora o brilho em volta) — define o tamanho
const FAIXA_PE := 26                      ## faixa de baixo do corpo que define o centro dos pés
const PE_X := 700                         ## até aqui (x do quadro) são as pernas; o canhão fica depois
const RAIO_ESMAZA := 130                  ## px da folha grande em que a ponta do raio some

var _quadros: Dictionary = {}             ## nº (de 1) -> {"bb": Rect2i, "pe": int}

func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ORIGEM))
	if img == null or img.is_empty():
		push_error("Não abriu " + ORIGEM)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var linhas := ceili(118.0 / COLS_GRANDE)
	if img.get_width() != COLS_GRANDE * CEL.x or img.get_height() != linhas * CEL.y:
		push_error("Folha grande veio %dx%d (esperado %dx%d)" % [img.get_width(), img.get_height(),
			COLS_GRANDE * CEL.x, linhas * CEL.y])
		quit(1)
		return
	for n in range(1, 119):
		var r := _regiao(n)
		var bb := _bbox(img, r, ALFA)
		var pe := _peso(img, r, bb)
		_quadros[n] = {"bb": bb, "pe": pe["x"], "chao": pe["y"], "solido": _bbox(img, r, ALFA_SOLIDO, r.position.x + PE_X).position.y}
		if n in [1, 2, 3, 30, 34, 70, 118]:
			print("  quadro %3d: corpo x %4d..%4d  y %3d..%4d  pe=(%d,%d)  solido_y=%d" % [
				n, bb.position.x, bb.end.x - 1, bb.position.y, bb.end.y - 1, pe["x"], pe["y"], _quadros[n]["solido"]])
	# um fator só para as duas folhas: o corpo tem de ter o MESMO tamanho nas duas
	var maior := 0
	for n in range(Q_REP[0], Q_REP[1] + 1):
		maior = maxi(maior, int(_quadros[n]["chao"]) - int(_quadros[n]["solido"]))
	var fator := ALVO_TELA * QUALIDADE / float(maior + PAD)    ## QUALIDADE=2: 2 px da folha por px da tela
	print("")
	print("FATOR x%.5f (corpo de repouso = %d px na folha grande -> %.0f px na tela)" % [fator, maior, ALVO_TELA])
	var tiro := _folha(img, Q_TIRO, "atacando", true, fator)
	var rep := _folha(img, Q_REP, "parado", false, fator)
	_muzzle(img, tiro, rep)
	print("")
	print("FOLHAS GRAVADAS em " + PASTA)
	quit(0)

# ------------------------------------------------------------------ medidas da folha grande
func _regiao(n: int) -> Rect2i:
	var q := n - 1
	return Rect2i((q % COLS_GRANDE) * CEL.x, (q / COLS_GRANDE) * CEL.y, CEL.x, CEL.y)

## Caixa do desenho (ignora brilho quase invisível). Passa de 4 em 4 px: rápido e preciso o bastante.
func _bbox(img: Image, r: Rect2i, alfa: float, x_max := 0) -> Rect2i:
	var x0 := r.end.x; var y0 := r.end.y; var x1 := r.position.x; var y1 := r.position.y
	for y in range(r.position.y, r.end.y, 4):
		for x in range(r.position.x, (r.end.x if x_max == 0 else mini(r.end.x, x_max)), 4):
			if img.get_pixel(x, y).a * 255.0 >= alfa:
				if x < x0: x0 = x
				if x > x1: x1 = x
				if y < y0: y0 = y
				if y > y1: y1 = y
	if x1 <= x0 or y1 <= y0:
		return r
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

## PÉS: onde as pernas tocam o chão (a faixa da direita — apoio do canhão / casaco — desce mais
## e fica de fora) e o centro das duas botas nessa linha.
func _peso(img: Image, r: Rect2i, bb: Rect2i) -> Dictionary:
	var xmax := mini(bb.end.x, r.position.x + PE_X)
	var y_pe := -1
	for y in range(bb.end.y - 1, r.position.y, -1):
		for x in range(bb.position.x, xmax, 2):
			if img.get_pixel(x, y).a * 255.0 >= ALFA:
				y_pe = y
				break
		if y_pe >= 0:
			break
	if y_pe < 0:
		return {"x": bb.position.x + bb.size.x / 2, "y": bb.end.y - 1}
	var x0 := xmax; var x1 := bb.position.x
	for y in range(maxi(y_pe - FAIXA_PE, r.position.y), y_pe + 1, 2):
		for x in range(bb.position.x, xmax, 2):
			if img.get_pixel(x, y).a * 255.0 >= ALFA:
				if x < x0: x0 = x
				if x > x1: x1 = x
	if x1 <= x0:
		return {"x": bb.position.x + bb.size.x / 2, "y": y_pe}
	return {"x": (x0 + x1) / 2, "y": y_pe}

# ------------------------------------------------------------------ folha nova
## Cola o intervalo de quadros numa folha nova, cada um encaixado pelo centro dos pés e pelo chão.
## O "fator" é o MESMO das duas folhas: senão o corpo mudaria de tamanho ao trocar de animação.
func _folha(img: Image, intervalo: Array, nome: String, ralo: bool, fator: float) -> Dictionary:
	var ux0 := 1 << 30; var uy0 := 1 << 30; var ux1 := -(1 << 30); var uy1 := -(1 << 30)
	var corpo := 0
	for n in range(intervalo[0], intervalo[1] + 1):
		var bb: Rect2i = _quadros[n]["bb"]
		var pe: int = _quadros[n]["pe"]
		var chao: int = _quadros[n]["chao"]
		ux0 = mini(ux0, bb.position.x - pe)
		ux1 = maxi(ux1, bb.end.x - pe)
		uy0 = mini(uy0, bb.position.y - chao)          # o topo, acima do pé
		uy1 = maxi(uy1, bb.end.y - chao)               # o casaco/apoio desce um pouco além do chão
		corpo = maxi(corpo, chao - int(_quadros[n]["solido"]))   # altura do corpo (sem o brilho)
	# âncora em (0,0) = o centro dos pés; a folha nova é a união de todos os quadros + margem
	var w := ux1 - ux0 + PAD * 2
	var h := uy1 - uy0 + PAD * 2
	var ax := roundi((-ux0 + PAD) * fator)          ## onde o pé fica dentro do quadro novo
	var ay := roundi((-uy0 + PAD) * fator)
	var cw := maxi(1, roundi(w * fator))
	var ch := maxi(1, roundi(h * fator))
	var nq: int = intervalo[1] - intervalo[0] + 1
	var ncols := clampi(int(LIMITE / cw), 1, nq)
	ncols = mini(ncols, maxi(6, ceili(sqrt(float(nq) * float(ch) / float(cw)))))
	var nrows := ceili(float(nq) / ncols)
	if nrows * ch > LIMITE or ncols * cw > LIMITE:
		push_error("%s: folha ficaria %dx%d (passa de %d)" % [nome, ncols * cw, nrows * ch, LIMITE])
		return {}
	var saida := Image.create_empty(ncols * cw, nrows * ch, false, Image.FORMAT_RGBA8)
	for n in range(intervalo[0], intervalo[1] + 1):
		var q := _quadro_escalado(img, n, fator)
		var bb: Rect2i = _quadros[n]["bb"]
		var destino := Vector2i(roundi((_quadros[n]["bb"].position.x - _quadros[n]["pe"]) * fator) + ax,
			roundi((bb.position.y - _quadros[n]["chao"]) * fator) + ay)
		var i: int = n - intervalo[0]
		saida.blit_rect(q, Rect2i(Vector2i.ZERO, q.get_size()),
			destino + Vector2i((i % ncols) * cw, (i / ncols) * ch))
	if ralo:
		_esmaza_ponta(saida, fator)
	DirAccess.make_dir_recursive_absolute(PASTA)
	var caminho := "%s/%s_%dx%d.png" % [PASTA, nome, cw, ch]
	saida.save_png(caminho)
	print("")
	print("FOLHA %-9s: %d quadros de %dx%d -> folha %dx%d (%d cols x %d linhas), corpo na tela %.0f px" % [
		nome, nq, cw, ch, saida.get_width(), saida.get_height(), ncols, nrows,
		float(corpo) * fator * 0.5])
	_conferir(caminho, intervalo, cw, ch, ax, ay, ncols, fator)
	return {"cw": cw, "ch": ch, "ax": ax, "ay": ay, "corpo": corpo, "fator": fator,
		"cols": ncols, "quadros": nq, "nome": nome}

## Confere na folha SALVA que o pé de cada quadro caiu no mesmo ponto (sem pular ao trocar de animação).
func _conferir(caminho: String, intervalo: Array, cw: int, ch: int, ax: int, ay: int, ncols: int, fator: float) -> void:
	var folha := Image.load_from_file(ProjectSettings.globalize_path(caminho))
	if folha == null or folha.is_empty():
		print("  !! não consegui reler a folha para conferir")
		return
	folha.convert(Image.FORMAT_RGBA8)
	var pernas := mini(ax + roundi(150.0 * fator), cw)   # x até onde são as pernas (as botas)
	var pior_pe := 0.0; var pior_y := 0.0; var n_pior := -1
	for i in range(0, intervalo[1] - intervalo[0] + 1, 7):
		var cel := folha.get_region(Rect2i((i % ncols) * cw, (i / ncols) * ch, cw, ch))
		var y_chao := -1
		for y in range(ch - 1, 0, -1):
			for x in range(0, pernas, 2):
				if cel.get_pixel(x, y).a * 255.0 >= ALFA:
					y_chao = y
					break
			if y_chao >= 0:
				break
		if y_chao < 0:
			continue
		var bx0 := pernas; var bx1 := 0
		for y in range(maxi(y_chao - 12, 0), y_chao + 1, 2):
			for x in range(0, pernas, 2):
				if cel.get_pixel(x, y).a * 255.0 >= ALFA:
					if x < bx0: bx0 = x
					if x > bx1: bx1 = x
		if bx1 <= bx0:
			continue
		var pe := (bx0 + bx1) / 2.0
		var dp := absf(pe - ax); var dy := absf(float(y_chao) - ay)
		print("    quadro %d: pé=(%.0f,%d) esperado=(%d,%d)  botas x %d..%d" % [
			intervalo[0] + i, pe, y_chao, ax, ay, bx0, bx1])
		if dp > pior_pe:
			pior_pe = dp; n_pior = intervalo[0] + i
		pior_y = maxf(pior_y, dy)
	print("  conferido: pior pé fora do lugar = %.1f px (%d), pior chão = %.1f px -> %s" % [
		pior_pe, n_pior, pior_y, "ok" if pior_pe <= 3.0 and pior_y <= 3.0 else "REVISAR"])

## Um quadro da folha grande, já encolhido (interpolação feita uma vez só por quadro).
## Corta na CAIXA do desenho: assim o (0,0) da imagem é o topo-esquerdo do corpo e o destino
## calculado em _folha (relativo aos pés) encaixa certinho.
func _quadro_escalado(img: Image, n: int, fator: float) -> Image:
	var bb: Rect2i = _quadros[n]["bb"]
	var q := img.get_region(bb)
	if fator < 1.0:
		q.resize(maxi(1, roundi(bb.size.x * fator)), maxi(1, roundi(bb.size.y * fator)), Image.INTERPOLATE_LANCZOS)
	return q

## Esmaça a ponta do raio: o alpha da faixa direita cai até zero (só o raio está lá).
func _esmaza_ponta(saida: Image, fator: float) -> void:
	var largura := saida.get_width()
	var faixa := maxi(6, roundi(RAIO_ESMAZA * fator))
	for x in range(largura - faixa, largura):
		var k := float(largura - x) / float(faixa)     # 1 na ponta, 0 na borda
		k = k * k * (3.0 - 2.0 * k)                    # suave (smoothstep)
		for y in saida.get_height():
			var c := saida.get_pixel(x, y)
			if c.a > 0.0:
				saida.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * k))

# ------------------------------------------------------------------ boca do canhão
## Mede onde o raio sai (quadro 2: raio no ar, corpo em repouso) e imprime a "saída" em px da tela.
func _muzzle(img: Image, tiro: Dictionary, rep: Dictionary) -> void:
	var n := 2
	var reg := _regiao(n)
	var bb: Rect2i = _quadros[n]["bb"]
	var pe: int = _quadros[n]["pe"]
	var ponta := -1; var ry0 := 0; var ry1 := 0
	for x in range(reg.end.x - 1, reg.position.x, -1):
		var r := _faixa(img, x, bb)
		if r.x >= 0:
			ponta = x; ry0 = int(r.x); ry1 = int(r.y)
			break
	if ponta < 0:
		print("")
		print("BOCA DO CANHÃO: não achei o raio")
		return
	var alt := ry1 - ry0 + 1
	var bx := ponta
	var vazias := 0
	var perfil := ""
	for x in range(ponta, reg.position.x, -1):
		var r := _faixa(img, x, bb)
		if r.x < 0:
			vazias += 1                             # o raio tem umas pontinhas soltas: espera
			if vazias > 6:
				break
			continue
		vazias = 0
		var alt2 := r.y - r.x + 1
		if (x % 20) == 0:
			perfil += "%d:%d " % [x - reg.position.x, alt2]
		if alt2 > float(maxi(alt, 40)) * 3.0 + 60.0:
			break                                  # engrossou: encostou no canhão
		bx = x
	print("PERFIL (x relativo:altura): " + perfil)
	var fator: float = tiro["fator"]
	var k := 0.5                                   # p.escala * a.escala = 0.5 (folha = 2x a tela)
	var saida_x := (float(bx) - pe) * fator * k    # a boca, em px da tela, a partir do pé
	var saida_y := (float(ry0 + ry1) / 2.0 - float(_quadros[n]["chao"])) * fator * k
	print("")
	print("RAIO na folha grande: ponta x=%d, boca x=%d, altura y=%d..%d" % [ponta, bx, ry0, ry1])
	print("BOCA DO CANHÃO: saida_x=%.0f saida_y=%.0f  (em px da tela, a partir dos pés)" % [saida_x, saida_y])
	print("CORPOS NA TELA: repouso %.0f px, ataque %.0f px" % [
		float(rep["corpo"]) * rep["fator"] * k, float(tiro["corpo"]) * tiro["fator"] * k])
	print("FICHAS: p.escala=%.5f  a.escala(parado)=%.5f  a.escala(atacando)=%.5f" % [
		0.5 * rep["fator"], 1.0 / rep["fator"], 1.0 / tiro["fator"]])
	print("PARADO:    cols=%d quadros=%d cw=%d ch=%d ax=%d ay=%d" % [
		rep["cols"], rep["quadros"], rep["cw"], rep["ch"], rep["ax"], rep["ay"]])
	print("ATACANDO:  cols=%d quadros=%d cw=%d ch=%d ax=%d ay=%d" % [
		tiro["cols"], tiro["quadros"], tiro["cw"], tiro["ch"], tiro["ax"], tiro["ay"]])

## Faixa vertical do desenho numa coluna (-1 se a coluna estiver vazia).
func _faixa(img: Image, x: int, bb: Rect2i) -> Vector2:
	var y0 := -1.0; var y1 := -1.0
	for y in range(bb.position.y, bb.end.y, 2):
		if img.get_pixel(x, y).a * 255.0 >= ALFA:
			if y0 < 0.0:
				y0 = y
			y1 = y
	return Vector2(y0, y1)
