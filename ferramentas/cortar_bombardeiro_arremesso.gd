extends "res://ferramentas/cortar_bombardeiro_ataque.gd"
## CORTAR BOMBARDEIRO — ARREMESSO LONGO: a folha "arremessando bomba" (120 quadros 1280x720, por cima da
## cabeça) vira a folha "arremessando" do jogo:
##  - tira TODO o verde: contorno, faíscas verdes do pavio, fumaça e o rastro verde da bomba voando;
##  - apaga a chama pintada (o maior aglomerado de fogo amarelo/laranja do quadro) e guarda onde ela estava:
##    o jogo desenha o fogo de verdade ali (o mesmo da bomba na mão e voando);
##  - acha o quadro em que a bomba SAI DA MÃO; dali em diante só o corpo fica na folha (a bomba voando até o
##    inimigo é do jogo, por cima de todos, e explode ao tocar nele);
##  - recorta só o corpo (a folha fica pequena) e alinha pelo TRONCO com o parado (não pula ao trocar).
## RODAR: godot --headless --path . --script res://ferramentas/cortar_bombardeiro_arremesso.gd

const ORIGEM_ARR := "res://assets/Esqueleto Bombardeiro/arremessando bomba/arremessando bomba.png"

func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ORIGEM_ARR))
	img.convert(Image.FORMAT_RGBA8)
	var x0 := CEL.x; var y0 := CEL.y; var x1 := 0; var y1 := 0
	var alturas: Array[float] = []
	for n in QUADROS:
		var u := img.get_region(_reg(n)).get_used_rect()
		x0 = mini(x0, u.position.x); y0 = mini(y0, u.position.y)
		x1 = maxi(x1, u.end.x); y1 = maxi(y1, u.end.y)
		if n < 20:
			alturas.append(float(u.size.y))
	x0 = maxi(0, x0 - PAD); y0 = maxi(0, y0 - PAD); x1 = mini(CEL.x, x1 + PAD); y1 = mini(CEL.y, y1 + PAD)
	var fator := ALTURA_TELA / ESCALA_TELA / _mediana(alturas)
	var cw := roundi((x1 - x0) * fator)
	var ch := roundi((y1 - y0) * fator)
	var quadros: Array[Image] = []
	var pavio: Array = []
	var originais: Array[Image] = []
	for n in QUADROS:
		var q := img.get_region(Rect2i(_reg(n).position + Vector2i(x0, y0), Vector2i(x1 - x0, y1 - y0)))
		q.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
		var antes_fogo := q.duplicate() as Image
		pavio.append(_tirar_fogo(q))
		originais.append(antes_fogo)
		if n >= CABECA_DE and n < CABECA_ATE:
			# a fumaça do pavio passa NA FRENTE da cabeça: apagar deixaria a cabeça "transparente"
			# (não existe desenho embaixo). Fica como fumaça CINZA de verdade (só tira o verde)
			_fumaca_cinza(q)
		else:
			_tirar_verde(q)
		manter_pecas_de = 150
		_so_o_corpo(q, Vector2.ZERO, 0.0)                # faíscas e fumaça soltas somem (a bomba fica)
		_tirar_pecas_claras(q)                           # resto de chama clara solta no ar some (a bomba é escura)
		quadros.append(q)
	_reconstruir_cabeca(quadros)
	# quadro em que a bomba sai da mão: 1ª peça solta ESCURA (a bomba) depois de erguer o braço
	var solta := -1
	var solta_ponto := Vector2.ZERO
	for n in range(40, QUADROS):
		var b := _bomba_solta(quadros[n])
		if b.x >= 0.0:
			solta = n
			solta_ponto = b
			break
	if solta < 0:
		push_error("não achei a bomba saindo da mão")
		quit(1)
		return
	manter_pecas_de = 1 << 30
	for n in range(solta, QUADROS):
		_so_o_corpo(quadros[n], Vector2.ZERO, 0.0)
		pavio[n] = [-1, -1]
	# recorta só o que sobrou (o corpo): a folha fica bem menor
	var u0 := Rect2i()
	for n in QUADROS:
		var u := quadros[n].get_used_rect()
		u0 = u if n == 0 else u0.merge(u)
	u0 = u0.grow(4).intersection(Rect2i(0, 0, cw, ch))
	for n in QUADROS:
		quadros[n] = quadros[n].get_region(u0)
		if float(pavio[n][0]) >= 0.0:
			pavio[n] = [snappedf(float(pavio[n][0]) - u0.position.x, 0.1), snappedf(float(pavio[n][1]) - u0.position.y, 0.1)]
	solta_ponto -= Vector2(u0.position)
	cw = u0.size.x; ch = u0.size.y
	var cols := mini(int(LIMITE / cw), QUADROS)
	var linhas := ceili(float(QUADROS) / cols)
	var saida := Image.create_empty(cols * cw, linhas * ch, false, Image.FORMAT_RGBA8)
	for n in QUADROS:
		saida.blit_rect(quadros[n], Rect2i(0, 0, cw, ch), Vector2i((n % cols) * cw, (n / cols) * ch))
	var nome := "%s/arremessando_%dx%d.png" % [PASTA, cw, ch]
	saida.save_png(ProjectSettings.globalize_path(nome))
	# âncora pelo tronco (igual ao parado)
	var par := Image.load_from_file(ProjectSettings.globalize_path(PASTA + "/parado_233x270.png"))
	par.convert(Image.FORMAT_RGBA8)
	var ax := _tronco_x(quadros[0]) - (_tronco_x(par) - PARADO_AX)
	var ay := float(quadros[0].get_used_rect().end.y) - (float(par.get_used_rect().end.y) - PARADO_AY)
	# suaviza a trajetória do fogo (média de 3) onde há fogo
	var suave: Array = []
	for n in QUADROS:
		if float(pavio[n][0]) < 0.0:
			suave.append([-1, -1])
			continue
		var sx := 0.0; var sy := 0.0; var k := 0
		for j in [n - 1, n, n + 1]:
			if j >= 0 and j < QUADROS and float(pavio[j][0]) >= 0.0:
				sx += float(pavio[j][0]); sy += float(pavio[j][1]); k += 1
		suave.append([snappedf(sx / k, 0.1), snappedf(sy / k, 0.1)])
	print("SALVO: %s (%dx%d, %d quadros de %dx%d, %d colunas)" % [nome, saida.get_width(), saida.get_height(), QUADROS, cw, ch, cols])
	print("cols = %d\ncw = %d\nch = %d\nax = %.1f\nay = %.1f" % [cols, cw, ch, ax, ay])
	print("SOLTA_QUADRO=%d (contando do 1: %d)" % [solta, solta + 1])
	print("SOLTA_PONTO=" + JSON.stringify([snappedf(solta_ponto.x, 0.1), snappedf(solta_ponto.y, 0.1)]))
	print("fogo achado em %d quadros antes de soltar" % suave.filter(func(p): return p[0] >= 0).size())
	print("PAVIO_ARREMESSO=" + JSON.stringify(suave))
	quit(0)

## Apaga a chama pintada: o MAIOR aglomerado de fogo (amarelo/laranja saturado ou miolo claro amarelado),
## com 2 px em volta. Os olhos vermelhos são pequenos (e pouco amarelos): ficam. Devolve o centro dela.
func _tirar_fogo(q: Image) -> Array:
	var w := q.get_width(); var h := q.get_height()
	var marca := PackedByteArray(); marca.resize(w * h)
	for y in h:
		for x in w:
			var c := q.get_pixel(x, y)
			# só fogo SATURADO (o osso é bege: r-b ~0,2; os olhos são vermelhos: g baixo)
			if c.a > 0.1 and c.r > 0.6 and c.g > 0.35 and c.r - c.b > 0.45:
				marca[y * w + x] = 1
	var visto := PackedByteArray(); visto.resize(w * h)
	var melhor: Array[Vector2i] = []
	for y in h:
		for x in w:
			if marca[y * w + x] == 0 or visto[y * w + x] == 1:
				continue
			var comp: Array[Vector2i] = []
			var fila: Array[Vector2i] = [Vector2i(x, y)]
			visto[y * w + x] = 1
			while not fila.is_empty():
				var p: Vector2i = fila.pop_back()
				comp.append(p)
				for dy in range(-2, 3):                        # liga pedaços a até 2 px (a chama é recortada)
					for dx in range(-2, 3):
						var v := Vector2i(p.x + dx, p.y + dy)
						if v.x >= 0 and v.y >= 0 and v.x < w and v.y < h and marca[v.y * w + v.x] == 1 and visto[v.y * w + v.x] == 0:
							visto[v.y * w + v.x] = 1
							fila.append(v)
			if comp.size() > melhor.size():
				melhor = comp
	if melhor.size() < 25:                                 # sem chama de verdade neste quadro
		return [-1, -1]
	# o miolo quase branco da chama: só o que encosta nela (até 3 px)
	var junto := {}
	for p in melhor:
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var v := Vector2i(p.x + dx, p.y + dy)
				if v.x >= 0 and v.y >= 0 and v.x < w and v.y < h and not junto.has(v):
					var cm := q.get_pixel(v.x, v.y)
					if cm.a > 0.1 and cm.r + cm.g + cm.b > 2.3 and cm.r - cm.b > 0.18:
						junto[v] = true
	for v in junto:
		q.set_pixel(v.x, v.y, Color(0, 0, 0, 0))
	var sx := 0.0; var sy := 0.0
	for p in melhor:
		sx += p.x; sy += p.y
		q.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
		for dy in range(-1, 2):                                # +1 px: só a borda bem quente (o reflexo na bomba fica)
			for dx in range(-1, 2):
				var v := Vector2i(p.x + dx, p.y + dy)
				if v.x >= 0 and v.y >= 0 and v.x < w and v.y < h:
					var c2 := q.get_pixel(v.x, v.y)
					if c2.r - c2.b > 0.4 and c2.g > 0.3:
						q.set_pixel(v.x, v.y, Color(0, 0, 0, 0))
	return [snappedf(sx / melhor.size(), 0.1), snappedf(sy / melhor.size(), 0.1)]

## Tira o verde: faísca/fumaça verde some; borda esverdeada some; o resto perde o tom verde (despill).
## A parte CINZA da fumaça (colada na verde) também some: a remoção se espalha do verde apagado pelo cinza.
func _tirar_verde(q: Image) -> void:
	var original := q.duplicate() as Image
	_tirar_verde_e_fumaca(q)
	_tapar_buracos(q, original)

## Buraco FECHADO dentro do desenho (sem ligação com o fundo) é desenho que tinha sombra esverdeada
## (ex.: o crânio da bomba iluminado pela chama): volta, só sem o tom verde. Fumaça fica do lado de fora.
func _tapar_buracos(q: Image, original: Image) -> void:
	var w := q.get_width(); var h := q.get_height()
	var fora := PackedByteArray(); fora.resize(w * h)
	var fila: Array[Vector2i] = []
	for x in w:
		fila.append(Vector2i(x, 0)); fila.append(Vector2i(x, h - 1))
	for y in h:
		fila.append(Vector2i(0, y)); fila.append(Vector2i(w - 1, y))
	while not fila.is_empty():
		var p: Vector2i = fila.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h or fora[p.y * w + p.x] == 1:
			continue
		if q.get_pixel(p.x, p.y).a >= 0.02:
			continue
		fora[p.y * w + p.x] = 1
		fila.append(p + Vector2i(1, 0)); fila.append(p + Vector2i(-1, 0)); fila.append(p + Vector2i(0, 1)); fila.append(p + Vector2i(0, -1))
	for y in h:
		for x in w:
			if fora[y * w + x] == 0 and q.get_pixel(x, y).a < 0.02:
				var c := original.get_pixel(x, y)
				if c.a >= 0.02:
					var verde := c.g - maxf(c.r, c.b)
					if verde > 0.0:
						c.g = maxf(c.r, c.b) + verde * 0.15
					q.set_pixel(x, y, c)

func _tirar_verde_e_fumaca(q: Image) -> void:
	var w := q.get_width(); var h := q.get_height()
	var apagado: Array[Vector2i] = []
	for y in h:
		for x in w:
			var c0 := q.get_pixel(x, y)
			if c0.a >= 0.02 and c0.g - maxf(c0.r, c0.b) > 0.035 and not ((c0.r + c0.g + c0.b) / 3.0 > 0.66 and c0.r > 0.55):
				apagado.append(Vector2i(x, y))
	_tirar_verde_px(q)
	var visto := {}
	var fila := apagado.duplicate()
	while not fila.is_empty():
		var p: Vector2i = fila.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
			var v: Vector2i = p + d
			if v.x < 0 or v.y < 0 or v.x >= w or v.y >= h or visto.has(v):
				continue
			visto[v] = true
			var c := q.get_pixel(v.x, v.y)
			if c.a < 0.02:
				continue
			var sat := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			var lum := (c.r + c.g + c.b) / 3.0
			if sat < 0.13 and lum > 0.2 and lum < 0.76:          # fumaça cinza colada na verde (o crânio branco fica)
				q.set_pixel(v.x, v.y, Color(0, 0, 0, 0))
				fila.append(v)

func _tirar_verde_px(q: Image) -> void:
	var w := q.get_width(); var h := q.get_height()
	for y in h:
		for x in w:
			var c := q.get_pixel(x, y)
			if c.a < 0.02:
				continue
			# fumaça: meio transparente, sem cor e de brilho médio (a bomba é preta, o crânio é branco)
			var lum := (c.r + c.g + c.b) / 3.0
			if c.a < 0.9 and maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) < 0.12 and lum > 0.25 and lum < 0.85:
				q.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var verde := c.g - maxf(c.r, c.b)
			if verde <= 0.0:
				continue
			# fumaça e faísca verdes (mesmo as apagadinhas) somem; o corpo quase não tem verde.
			# Pixel CLARO esverdeado é o crânio da bomba com a luz verde batendo: só perde o tom verde
			var claro := (c.r + c.g + c.b) / 3.0 > 0.66 and c.r > 0.55
			if not claro and (verde > 0.035 or (verde > 0.015 and _na_borda(q, x, y, w, h))):
				q.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				c.g = maxf(c.r, c.b) + verde * 0.15
				q.set_pixel(x, y, c)

const CABECA_DE := 24                  ## quadros (contando do 0) em que a fumaça passa na frente da cabeça: 25..44
const CABECA_ATE := 44

const CABECA_MOLDES := [24, 44]        ## quadros limpos (contando do 0) que servem de molde da cabeça
const CABECA_CAIXA := Rect2i(-50, -48, 100, 82)   ## cabeça + capuz em volta dos olhos (px da folha)

## Centro dos olhos (brilho vermelho-alaranjado) na metade de cima do quadro; (-1,-1) se não achar.
func _olhos(q: Image) -> Vector2:
	var u := q.get_used_rect()
	var sx := 0.0; var sy := 0.0; var n := 0
	for y in range(u.position.y, u.position.y + int(u.size.y * 0.55)):
		for x in range(u.position.x, u.end.x):
			var c := q.get_pixel(x, y)
			if c.a > 0.5 and c.r > 0.8 and c.g < 0.5 and c.g > 0.12 and c.b < 0.3:
				sx += x; sy += y; n += 1
	return Vector2(sx / n, sy / n) if n >= 6 else Vector2(-1, -1)
const CABECA_BUSCA := 44               ## procura o encaixe até essa distância (px) para cada lado

## Cor de fumaça (cinza, sem cor) ou buraco: é o que a cabeça do molde pode cobrir.
static func _cobrivel(c: Color) -> bool:
	if c.a < 0.1:
		return true
	var sat := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
	var lum := (c.r + c.g + c.b) / 3.0
	return sat < 0.1 and lum > 0.3 and lum < 0.8

## Cabeça por baixo da fumaça: encaixa a cabeça do quadro de molde (busca o deslocamento com a menor
## diferença nos pixels que NÃO são fumaça) e põe ela onde há fumaça ou buraco, dentro do contorno dela.
func _reconstruir_cabeca(quadros: Array[Image]) -> void:
	var moldes: Array = []                                 # cada molde: Array de [x, y, cor]
	for r in CABECA_MOLDES:
		var ref: Image = quadros[r]
		var olhos := _olhos(ref)
		if olhos.x < 0.0:
			continue
		var cx := Rect2i(Vector2i(olhos) + CABECA_CAIXA.position, CABECA_CAIXA.size)
		var molde: Array = []
		for y in range(cx.position.y, cx.end.y):
			for x in range(cx.position.x, cx.end.x):
				var c := ref.get_pixel(x, y)
				if c.a > 0.6:
					molde.append([x, y, c])
		moldes.append(molde)
	var w := quadros[0].get_width(); var h := quadros[0].get_height()
	for n in range(CABECA_DE, CABECA_ATE):
		var q: Image = quadros[n]
		var melhor_m: Array = []
		var melhor_d := Vector2i.ZERO
		var melhor_nota := INF
		for molde in moldes:
			var r2 := _encaixar(q, molde, w, h)
			if r2[1] < melhor_nota:
				melhor_nota = r2[1]; melhor_d = r2[0]; melhor_m = molde
		if melhor_nota > 0.42:                                 # pose muito diferente: não arrisca
			print("cabeça quadro %d: sem encaixe bom (%.2f)" % [n + 1, melhor_nota])
			continue
		var cobriu := 0
		for m in melhor_m:
			var x: int = m[0] + melhor_d.x; var y: int = m[1] + melhor_d.y
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			if _cobrivel(q.get_pixel(x, y)):
				q.set_pixel(x, y, m[2])
				cobriu += 1
		print("cabeça quadro %d: encaixe %s nota %.2f, %d px refeitos" % [n + 1, str(melhor_d), melhor_nota, cobriu])

## Melhor deslocamento do molde no quadro: [Vector2i, nota] (nota = diferença média de cor; menor = melhor).
func _encaixar(q: Image, molde: Array, w: int, h: int) -> Array:
	var melhor := Vector2i.ZERO
	var nota := INF
	if true:
		for passo in [4, 1]:                                 # grosso e depois fino
			var centro := melhor
			var raio := CABECA_BUSCA if passo == 4 else 4
			for dy in range(-raio, raio + 1, passo):
				for dx in range(-raio, raio + 1, passo):
					var d := centro + Vector2i(dx, dy) if passo == 1 else Vector2i(dx, dy)
					var soma := 0.0; var k := 0
					for i in range(0, molde.size(), 5):
						var m: Array = molde[i]
						var x: int = m[0] + d.x; var y: int = m[1] + d.y
						if x < 0 or y < 0 or x >= w or y >= h:
							continue
						var c := q.get_pixel(x, y)
						if _cobrivel(c):
							continue
						var cm: Color = m[2]
						soma += absf(c.r - cm.r) + absf(c.g - cm.g) + absf(c.b - cm.b)
						k += 1
					if k > molde.size() / 25 and soma / k < nota:
						nota = soma / k; melhor = d
	return [melhor, nota]

## Fumaça do pavio na frente da cabeça: vira fumaça CINZA (sem verde), um pouco transparente.
## Faíscas verdes muito vivas (pontinhos) somem; o resto do desenho só perde o tom verde.
func _fumaca_cinza(q: Image) -> void:
	var w := q.get_width(); var h := q.get_height()
	for y in h:
		for x in w:
			var c := q.get_pixel(x, y)
			if c.a < 0.02:
				continue
			var verde := c.g - maxf(c.r, c.b)
			if verde <= 0.0:
				continue
			if c.g > 0.7 and verde > 0.3:                       # faísca verde viva: some
				q.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			if verde > 0.05:                                     # fumaça esverdeada -> cinza fumaça
				var cinza := (c.r + c.g + c.b) / 3.0 * 0.92
				q.set_pixel(x, y, Color(cinza, cinza * 0.98, cinza * 0.96, c.a * 0.92))
			else:
				c.g = maxf(c.r, c.b) + verde * 0.15
				q.set_pixel(x, y, c)

## Peças soltas (fora do corpo) CLARAS são sobra da chama: somem. A bomba solta é escura e fica.
func _tirar_pecas_claras(q: Image) -> void:
	var pecas := _pecas(q)
	for i in range(pecas.size() - 1, 0, -1):
		var c := _so_a_peca(q, i)
		var u := c.get_used_rect()
		var soma := 0.0; var k := 0
		for y in range(u.position.y, u.end.y):
			for x in range(u.position.x, u.end.x):
				var p := c.get_pixel(x, y)
				if p.a > 0.3:
					soma += (p.r + p.g + p.b) / 3.0; k += 1
		if k > 0 and soma / k > 0.6:
			for y in range(u.position.y, u.end.y):
				for x in range(u.position.x, u.end.x):
					if c.get_pixel(x, y).a > 0.0:
						q.set_pixel(x, y, Color(0, 0, 0, 0))

## Centro da bomba se ela estiver SOLTA (peça separada do corpo, escura); senão (-1,-1).
func _bomba_solta(q: Image) -> Vector2:
	var pecas := _pecas(q)
	for i in range(1, pecas.size()):
		var pc: Dictionary = pecas[i]
		if int(pc.n) < 150:
			continue
		var c := _so_a_peca(q, i)
		var u := c.get_used_rect()
		var soma := 0.0; var k := 0
		for y in range(u.position.y, u.end.y, 2):
			for x in range(u.position.x, u.end.x, 2):
				var p := c.get_pixel(x, y)
				if p.a > 0.5:
					soma += (p.r + p.g + p.b) / 3.0; k += 1
		if k > 0 and soma / k < 0.35:
			return Vector2(u.position) + Vector2(u.size) / 2.0
	return Vector2(-1, -1)

## Cópia só com a i-ésima maior peça.
func _so_a_peca(q: Image, indice: int) -> Image:
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
	var alvo: int = ordem[indice] if indice < ordem.size() else -1
	for y in h:
		for x in w:
			if rotulo[y * w + x] != alvo:
				c.set_pixel(x, y, Color(0, 0, 0, 0))
	return c
