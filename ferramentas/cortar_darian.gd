extends SceneTree
## CORTAR GUERREIRO DARIAN (gerado a partir do cortar_golem.gd): as 4 folhas (já com fundo transparente) viram as folhas do jogo.
##  - mesmo tamanho na tela nas 4 animações (medido pelo corpo no 1º quadro, sem os efeitos);
##  - o tamanho na tela é o do Esqueleto Titã x TAMANHO (é o maior monstro do jogo);
##  - âncora: tronco no meio e os pés no chão (do 1º quadro de cada folha);
##  - recorta junto a área que TODOS os quadros usam (efeitos inclusos) e monta a folha até 4096 px
##    (se não couber, diminui a qualidade e, em último caso, pula quadros);
##  - "parado": 1 quadro neutro (o 1º do golpe2), o jogo faz ele respirar.
## RODAR: godot --headless --path . --script res://ferramentas/cortar_golem.gd

const PASTA_IN := "res://assets/Guerreiro Darian/"
const PASTA := "res://assets_otimizados/Guerreiro Darian/"
const P_ESCALA := 0.5                      ## escala do personagem na ficha
const TAMANHO := 0.86                      ## altura na tela em relação ao Titã (herói grande, um pouco maior que o Protetor)
const LIMITE := 4096
const PAD := 8
## nome, grade (colunas, célula), quadros, quadro neutro (contando do 1) para medir o corpo
const FOLHAS := [
	{"anim": "andando", "arq": "andando", "cols": 21, "cel": Vector2i(190, 252), "n": 97},
	{"anim": "golpe1", "arq": "golpe1", "cols": 11, "cel": Vector2i(369, 331), "n": 121},
	{"anim": "golpe2", "arq": "golpe2", "cols": 12, "cel": Vector2i(330, 294), "n": 81},
	{"anim": "morrendo", "arq": "morrendo", "cols": 4, "cel": Vector2i(863, 508), "n": 117},
]

func _initialize() -> void:
	# tamanho do Titã na tela (corpo do parado)
	var tita := load("res://dados/personagens/esqueletoTita.tres") as PersonagemDados
	var ap: AnimDados = tita.anim("parado")
	var ti := ap.textura.get_image()
	if ti.is_compressed():
		ti.decompress()
	ti.convert(Image.FORMAT_RGBA8)
	var tu := ti.get_region(Rect2i(ap.retangulo(0))).get_used_rect()
	var alt_tela := float(tu.size.y) * tita.escala * ap.escala * TAMANHO
	print("Titã na tela: %.1f px  ->  Golem: %.1f px" % [float(tu.size.y) * tita.escala * ap.escala, alt_tela])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PASTA))
	for f in FOLHAS:
		_folha(f, alt_tela)
	quit(0)

func _corpo(q: Image) -> Rect2i:
	# corpo = pixels bem opacos (os efeitos do 1º quadro não existem; mesmo assim ignora semitransparente)
	var w := q.get_width(); var h := q.get_height()
	var x0 := w; var y0 := h; var x1 := -1; var y1 := -1
	for y in h:
		for x in w:
			if q.get_pixel(x, y).a > 0.5:
				x0 = mini(x0, x); y0 = mini(y0, y); x1 = maxi(x1, x); y1 = maxi(y1, y)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

func _tronco_x(q: Image, c: Rect2i) -> float:
	var ya := c.position.y + int(c.size.y * 0.35); var yb := c.position.y + int(c.size.y * 0.55)
	var x0 := q.get_width(); var x1 := -1
	for y in range(ya, yb):
		for x in range(c.position.x, c.end.x):
			if q.get_pixel(x, y).a > 0.5:
				x0 = mini(x0, x); x1 = maxi(x1, x)
	return (x0 + x1 + 1) / 2.0 if x1 >= 0 else c.get_center().x

func _folha(f: Dictionary, alt_tela: float) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(PASTA_IN + f.arq + ".png"))
	img.convert(Image.FORMAT_RGBA8)
	var cel: Vector2i = f.cel
	var n: int = f.n
	var reg := func(k: int) -> Rect2i: return Rect2i((k % f.cols) * cel.x, (k / f.cols) * cel.y, cel.x, cel.y)
	var q0 := img.get_region(reg.call(0))
	var corpo := _corpo(q0)
	var tx := _tronco_x(q0, corpo)
	var pe_y := float(corpo.end.y)
	# área usada por todos os quadros (efeitos inclusos)
	var uni := Rect2i()
	for k in n:
		var u := img.get_region(reg.call(k)).get_used_rect()
		if u.size.x <= 0:
			continue
		uni = u if uni.size.x <= 0 else uni.merge(u)
	uni = uni.grow(PAD).intersection(Rect2i(Vector2i.ZERO, cel))
	# qualidade: 2 px da folha por px da tela; diminui até caber em 4096
	var passo := 1
	var qual := 2.0
	var cw := 0; var ch := 0; var cols := 0; var quadros := 0
	while true:
		var fator := alt_tela * qual / float(corpo.size.y)
		cw = ceili(uni.size.x * fator); ch = ceili(uni.size.y * fator)
		quadros = ceili(float(n) / passo)
		cols = mini(quadros, maxi(1, int(LIMITE / cw)))
		if ceili(float(quadros) / cols) * ch <= LIMITE:
			break
		if qual > 1.25:
			qual -= 0.1
		else:
			passo += 1
			qual = 2.0
	var fator2 := alt_tela * qual / float(corpo.size.y)
	var linhas := ceili(float(quadros) / cols)
	var saida := Image.create_empty(cols * cw, linhas * ch, false, Image.FORMAT_RGBA8)
	var golpe := false
	for i in quadros:
		var q := img.get_region(Rect2i(reg.call(i * passo).position + uni.position, uni.size))
		if golpe:
			_esfumar_bordas(q, SUAVE)                        # o poder some suave na borda (o jogo desenha o resto)
		q.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
		# (morrendo: o martelo já foi tirado no próprio PNG — a folha vai como está, sem apagar nada)
		saida.blit_rect(q, Rect2i(0, 0, cw, ch), Vector2i((i % cols) * cw, (i / cols) * ch))
	var pasta: String = PASTA + f.anim
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(pasta))
	var nome := "%s/%s_%dx%d.png" % [pasta, f.anim, cw, ch]
	saida.save_png(ProjectSettings.globalize_path(nome))
	var ax := (tx - uni.position.x) * fator2
	var ay := (pe_y - uni.position.y) * fator2
	var escala := 1.0 / qual / P_ESCALA
	print("[%s] %s  quadros=%d (passo %d) cols=%d cw=%d ch=%d ax=%.2f ay=%.2f escala=%.6f qualidade=%.2f" % [f.anim, nome, quadros, passo, cols, cw, ch, ax, ay, escala, qual])
	# PARADO: o 1º quadro do golpe2 (neutro), só o corpo, com a mesma escala e âncora
	if f.anim == "golpe2":
		var c2 := corpo.grow(PAD).intersection(Rect2i(Vector2i.ZERO, cel))
		var pw := ceili(c2.size.x * fator2); var ph := ceili(c2.size.y * fator2)
		var pq := q0.get_region(c2)
		pq.resize(pw, ph, Image.INTERPOLATE_LANCZOS)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PASTA + "parado"))
		var np := "%sparado/parado_%dx%d.png" % [PASTA, pw, ph]
		pq.save_png(ProjectSettings.globalize_path(np))
		print("[parado] %s  cw=%d ch=%d ax=%.2f ay=%.2f escala=%.6f" % [np, pw, ph, (tx - c2.position.x) * fator2, (pe_y - c2.position.y) * fator2, escala])
	if f.anim == "andando":
		_medir_passo(img, reg, n, corpo, fator2, alt_tela)

## Fica só o corpo: o maior pedaço e o que encosta nele. Pedaços soltos LONGE do corpo (o martelo jogado
## para fora da imagem, que ficaria cortado na borda) são apagados.
func _so_o_corpo(q: Image) -> void:
	var w := q.get_width(); var h := q.get_height()
	var lab := PackedInt32Array(); lab.resize(w * h)
	var areas: Array[int] = [0]
	var caixas: Array[Rect2i] = [Rect2i()]
	var pilha := PackedInt32Array()
	var id := 0
	for i0 in w * h:
		if lab[i0] != 0 or q.get_pixel(i0 % w, i0 / w).a < 0.08:
			continue
		id += 1
		lab[i0] = id
		pilha.append(i0)
		var n := 0
		var x0 := w; var y0 := h; var x1 := 0; var y1 := 0
		while pilha.size() > 0:
			var i := pilha[pilha.size() - 1]
			pilha.remove_at(pilha.size() - 1)
			n += 1
			var x := i % w; var y := i / w
			x0 = mini(x0, x); y0 = mini(y0, y); x1 = maxi(x1, x); y1 = maxi(y1, y)
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var xx: int = x + dx; var yy: int = y + dy
					if xx < 0 or yy < 0 or xx >= w or yy >= h:
						continue
					var j := yy * w + xx
					if lab[j] == 0 and q.get_pixel(xx, yy).a >= 0.08:
						lab[j] = id
						pilha.append(j)
		areas.append(n)
		caixas.append(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))
	if id <= 1:
		return
	var maior := 1
	for k in range(2, id + 1):
		if areas[k] > areas[maior]:
			maior = k
	var corpo: Rect2i = caixas[maior].grow(4)
	var apagar := {}
	for k in range(1, id + 1):
		if k != maior and not corpo.intersects(caixas[k]):
			apagar[k] = true
	if apagar.is_empty():
		return
	for i in w * h:
		if apagar.has(lab[i]):
			q.set_pixel(i % w, i / w, Color(0, 0, 0, 0))

## Alfa em rampa na faixa da esquerda (onde só passa o martelo): nunca aparece cortado na borda.
func _sumir_na_esquerda(q: Image, larg: int) -> void:
	for y in q.get_height():
		for x in mini(larg, q.get_width()):
			var c := q.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var k := float(x) / larg
			c.a *= k * k * (3.0 - 2.0 * k)
			q.set_pixel(x, y, c)

const SUAVE := 70                         ## px (folha original) em que o poder vai sumindo na borda do quadro

## Apaga devagar (alfa em rampa) perto das bordas da esquerda, direita e de cima: nada de corte reto.
func _esfumar_bordas(q: Image, larg: int) -> void:
	var w := q.get_width(); var h := q.get_height()
	for y in h:
		var ky := clampf(float(y) / larg, 0.0, 1.0)
		for x in w:
			var k := minf(ky, minf(clampf(float(x) / larg, 0.0, 1.0), clampf(float(w - 1 - x) / larg, 0.0, 1.0)))
			if k >= 1.0:
				continue
			var c := q.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			c.a *= k * k * (3.0 - 2.0 * k)
			q.set_pixel(x, y, c)

## Pixels muito claros (o raio / o fogo branco) numa faixa de x: começo (x0), centro (cx) e altura média (y).
func _brilho(q: Image, xa: float, xb: float) -> Dictionary:
	var soma_y := 0.0; var soma_x := 0.0; var n := 0; var x0 := INF
	for y in q.get_height():
		for x in q.get_width():
			if x < xa or x > xb:
				continue
			var c := q.get_pixel(x, y)
			if c.a > 0.6 and c.get_luminance() > 0.82:
				soma_y += y; soma_x += x; n += 1
				x0 = minf(x0, float(x))
	if n == 0:
		return {"x0": xa, "cx": xa, "y": 0.0}
	return {"x0": x0, "cx": soma_x / n, "y": soma_y / n}

## passo (abertura das pernas) -> velocidade que casa o pé com o chão a 18 fps
func _medir_passo(img: Image, reg: Callable, n: int, corpo: Rect2i, fator: float, _alt: float) -> void:
	var ab: Array[float] = []
	for k in n:
		var q: Image = img.get_region(reg.call(k))
		var u := q.get_used_rect()
		ab.append(float(q.get_region(Rect2i(0, u.end.y - 8, q.get_width(), 8)).get_used_rect().size.x))
	var lo: float = ab.min(); var hi: float = ab.max()
	var picos := 0
	var acima := false
	for v in ab:
		if v > lo + (hi - lo) * 0.6 and not acima:
			picos += 1; acima = true
		elif v < lo + (hi - lo) * 0.35:
			acima = false
	var px_tela := (hi - lo) * fator * 0.5          # 0,5 = tela por px da folha (qualidade 2)
	print("[andar] abertura %.0f..%.0f px, %d passos em %d quadros -> ~%.0f px/s a 18 fps" % [lo, hi, picos, n, px_tela * picos * 18.0 / n * 2.0 / 2.0])
