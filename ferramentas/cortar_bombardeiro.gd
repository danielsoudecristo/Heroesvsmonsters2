extends SceneTree
## CORTAR BOMBARDEIRO: a folha grande de andar do Esqueleto Bombardeiro (120 quadros de 1280x720, grade 11x11)
## vira a folha do jogo:
##  - SEM realinhar quadro a quadro (o vídeo já anda no lugar; alinhar pela "cabeça" fazia ele ir e voltar,
##    porque as bombas nas costas e o pavio ficam acima da cabeça e mexem);
##  - tira o CONTORNO VERDE (sobra do fundo verde): borda esverdeada some, o resto perde o tom verde;
##  - apaga a CHAMA VERDE do pavio e guarda onde ela estava em cada quadro (o jogo desenha um fogo de verdade ali);
##  - cria o "parado" (1 quadro, pernas mais juntas) com a mesma limpeza.
## Imprime os números para a ficha (esqueletoBombardeiro.tres).
## RODAR: godot --headless --path . --script res://ferramentas/cortar_bombardeiro.gd

const ORIGEM := "res://assets/Esqueleto Bombardeiro/Esqueleto Bombardeiro andando/Esqueleto Bombardeiro andando.png"
const PASTA := "res://assets_otimizados/Esqueleto Bombardeiro"
const CEL := Vector2i(1280, 720)
const COLS_G := 11
const QUADROS := 120
const ALTURA_TELA := 115.0            ## altura do desenho na tela (px)
const ESCALA_TELA := 0.5              ## p.escala x a.escala da ficha
const PAD := 12
const LIMITE := 4096
var manter_pecas_de := 1 << 30        ## peças soltas deste tamanho (px) para cima ficam (o ataque usa: a bomba voando)
const RAIO_CHAMA := 36.0           ## px (folha nova) em volta da chama que são apagados (o jogo desenha o fogo)

func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ORIGEM))
	img.convert(Image.FORMAT_RGBA8)
	# 1) caixa comum de todos os quadros (posição original, sem realinhar)
	var x0 := CEL.x; var y0 := CEL.y; var x1 := 0; var y1 := 0
	var alturas: Array[float] = []
	for n in QUADROS:
		var u := img.get_region(_reg(n)).get_used_rect()
		x0 = mini(x0, u.position.x); y0 = mini(y0, u.position.y)
		x1 = maxi(x1, u.end.x); y1 = maxi(y1, u.end.y)
		alturas.append(float(u.size.y))
	x0 = maxi(0, x0 - PAD); y0 = maxi(0, y0 - PAD); x1 = mini(CEL.x, x1 + PAD); y1 = mini(CEL.y, y1 + PAD)
	var fator := ALTURA_TELA / ESCALA_TELA / _mediana(alturas)
	var cw := roundi((x1 - x0) * fator)
	var ch := roundi((y1 - y0) * fator)
	var cols := mini(int(LIMITE / cw), QUADROS)
	var linhas := ceili(float(QUADROS) / cols)
	var saida := Image.create_empty(cols * cw, linhas * ch, false, Image.FORMAT_RGBA8)
	var pavio: Array = []                     # [x, y] da chama em cada quadro (px da célula nova), ou [-1,-1]
	var pes: Array[float] = []
	var chaos: Array[float] = []
	var aberturas: Array[float] = []
	var quadros_limpos: Array[Image] = []
	for n in QUADROS:
		var q := img.get_region(Rect2i(_reg(n).position + Vector2i(x0, y0), Vector2i(x1 - x0, y1 - y0)))
		q.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
		pavio.append(_limpar(q))
		quadros_limpos.append(q)
		saida.blit_rect(q, Rect2i(0, 0, cw, ch), Vector2i((n % cols) * cw, (n / cols) * ch))
		var u := q.get_used_rect()
		chaos.append(float(u.end.y))
		var faixa := maxi(3, int(u.size.y * 0.07))
		var fp := q.get_region(Rect2i(0, u.end.y - faixa, cw, faixa)).get_used_rect()
		pes.append(fp.position.x + fp.size.x / 2.0)
		aberturas.append(float(fp.size.x))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PASTA))
	var nome := "%s/andando_%dx%d.png" % [PASTA, cw, ch]
	saida.save_png(ProjectSettings.globalize_path(nome))
	# 2) parado: o quadro de pernas mais juntas
	var melhor := 0
	for n in QUADROS:
		if aberturas[n] < aberturas[melhor]:
			melhor = n
	var nome_p := "%s/parado_%dx%d.png" % [PASTA, cw, ch]
	quadros_limpos[melhor].save_png(ProjectSettings.globalize_path(nome_p))
	var ax := _mediana(pes)
	var ay := _mediana(chaos)
	print("SALVO: %s (%dx%d, %d quadros de %dx%d, %d colunas)" % [nome, saida.get_width(), saida.get_height(), QUADROS, cw, ch, cols])
	print("SALVO: %s (quadro %d)" % [nome_p, melhor + 1])
	print("cols = %d\ncw = %d\nch = %d\nax = %.1f\nay = %.1f" % [cols, cw, ch, ax, ay])
	var achou := pavio.filter(func(p): return p[0] >= 0).size()
	print("pavio achado em %d de %d quadros" % [achou, QUADROS])
	print("PAVIO_ANDAR=" + JSON.stringify(pavio))
	print("PAVIO_PARADO=" + JSON.stringify(pavio[melhor]))
	quit(0)

func _reg(n: int) -> Rect2i:
	return Rect2i((n % COLS_G) * CEL.x, (n / COLS_G) * CEL.y, CEL.x, CEL.y)

## Limpa um quadro (já no tamanho final): apaga a chama verde do pavio (devolve onde ela estava) e o
## contorno verde; tira o tom verde do resto (despill).
func _limpar(q: Image) -> Array:
	var w := q.get_width(); var h := q.get_height()
	var sx := 0.0; var sy := 0.0; var peso := 0.0
	var chama: Array[Vector2i] = []
	for y in h:
		for x in w:
			var c := q.get_pixel(x, y)
			if c.a < 0.02:
				continue
			var verde := c.g - maxf(c.r, c.b)
			# chama do pavio: verde-amarelado BRILHANTE (o resto do desenho não tem isso)
			if c.g > 0.5 and c.g > c.b + 0.25 and verde > 0.08:
				chama.append(Vector2i(x, y))
				var p := c.a * c.g
				sx += x * p; sy += y * p; peso += p
				continue
			if verde > 0.0:
				# borda (encosta no transparente) bem verde: é sobra do fundo -> some
				if verde > 0.06 and _na_borda(q, x, y, w, h):
					q.set_pixel(x, y, Color(0, 0, 0, 0))
					continue
				c.g = maxf(c.r, c.b) + verde * 0.15          # despill: tira o tom verde
				q.set_pixel(x, y, c)
	# apaga a chama (e um pouquinho em volta, o brilho)
	for p in chama:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var xx := p.x + dx; var yy := p.y + dy
				if xx >= 0 and yy >= 0 and xx < w and yy < h:
					var c2 := q.get_pixel(xx, yy)
					if c2.g > maxf(c2.r, c2.b):
						q.set_pixel(xx, yy, Color(0, 0, 0, 0))
	if peso < 1.0:
		return [-1, -1]
	var semente := Vector2(sx / peso, sy / peso)          # brilho verde: a chama está ali perto
	# a chama PINTADA: segue, a partir do brilho verde, os pixels de FOGO ligados a ele (vizinho com vizinho).
	# Fogo = bem saturado (r-b > 0,45) ou miolo claro amarelado. O osso é bege (pouco saturado) e os olhos
	# não encostam na chama: ficam. O pavio marrom-escuro também fica.
	var r := RAIO_CHAMA
	var mascara := {}
	var fila: Array[Vector2i] = chama.duplicate()
	for p0 in chama:
		mascara[p0] = true
	var cx := 0.0; var cy := 0.0; var np := 0.0
	while not fila.is_empty():
		var p1: Vector2i = fila.pop_back()
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var v := Vector2i(p1.x + dx, p1.y + dy)
				if v.x < 0 or v.y < 0 or v.x >= w or v.y >= h or mascara.has(v):
					continue
				if Vector2(v).distance_to(semente) > r:
					continue
				var c3 := q.get_pixel(v.x, v.y)
				var saturado := c3.r > 0.55 and c3.g > 0.25 and c3.r - c3.b > 0.45
				var miolo := c3.r + c3.g + c3.b > 2.4 and c3.r - c3.b > 0.3
				if c3.a > 0.05 and (saturado or miolo):
					mascara[v] = true
					fila.append(v)
					cx += v.x; cy += v.y; np += 1.0
	for p in mascara.keys():                                # apaga a chama (+1 px em volta: a borda dela)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var xx: int = p.x + dx; var yy: int = p.y + dy
				if xx >= 0 and yy >= 0 and xx < w and yy < h:
					var c4 := q.get_pixel(xx, yy)
					if c4.r - c4.b > 0.35 and (c4.r + c4.g) > 0.9:
						q.set_pixel(xx, yy, Color(0, 0, 0, 0))
	# o que sobrou da chama e das faíscas fica SOLTO no ar: fica só a maior peça (o personagem)
	var solto := _so_o_corpo(q, semente, r * 1.4)
	if solto[2] > 0.0:
		cx += solto[0]; cy += solto[1]; np += solto[2]
	var centro := Vector2(cx / np, cy / np) if np > 0 else semente
	return [snappedf(centro.x, 0.1), snappedf(centro.y, 0.1)]

## Apaga tudo que não está ligado à maior peça do desenho. Devolve [soma x, soma y, n] dos pixels apagados
## perto da chama (para achar o centro dela).
func _so_o_corpo(q: Image, perto: Vector2, raio: float) -> Array:
	var w := q.get_width(); var h := q.get_height()
	var rotulo := PackedInt32Array(); rotulo.resize(w * h)
	var tamanhos: Array[int] = [0]
	for y in h:
		for x in w:
			if rotulo[y * w + x] != 0 or q.get_pixel(x, y).a < 0.05:
				continue
			var id := tamanhos.size()
			var n := 0
			var fila: Array[Vector2i] = [Vector2i(x, y)]
			rotulo[y * w + x] = id
			while not fila.is_empty():
				var p: Vector2i = fila.pop_back()
				n += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
					var v: Vector2i = p + d
					if v.x >= 0 and v.y >= 0 and v.x < w and v.y < h and rotulo[v.y * w + v.x] == 0 and q.get_pixel(v.x, v.y).a >= 0.05:
						rotulo[v.y * w + v.x] = id
						fila.append(v)
			tamanhos.append(n)
	var maior := 1
	for i in range(1, tamanhos.size()):
		if tamanhos[i] > tamanhos[maior]:
			maior = i
	var sx := 0.0; var sy := 0.0; var n2 := 0.0
	for y in h:
		for x in w:
			var id2 := rotulo[y * w + x]
			if id2 != 0 and id2 != maior and tamanhos[id2] < manter_pecas_de:
				q.set_pixel(x, y, Color(0, 0, 0, 0))
				if Vector2(x, y).distance_to(perto) <= raio:
					sx += x; sy += y; n2 += 1.0
	return [sx, sy, n2]

func _na_borda(q: Image, x: int, y: int, w: int, h: int) -> bool:
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2)]:
		var xx: int = x + d.x; var yy: int = y + d.y
		if xx < 0 or yy < 0 or xx >= w or yy >= h or q.get_pixel(xx, yy).a < 0.1:
			return true
	return false

static func _mediana(v: Array[float]) -> float:
	if v.is_empty():
		return 0.0
	var c := v.duplicate()
	c.sort()
	return c[c.size() / 2]
