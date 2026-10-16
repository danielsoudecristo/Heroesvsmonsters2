extends SceneTree
## CORTAR PROTETOR ANDANDO: a folha nova de andar do Guerreiro Protetor (93 quadros de 1280x720, grade 10x10)
## vira a folha do jogo:
##  - tira o CONTORNO VERDE (sobra do fundo verde): borda esverdeada some, o resto perde o tom verde;
##  - mesmo tamanho na tela do "parado" e o TRONCO no mesmo ponto da âncora (não pula ao parar/andar);
##  - sem realinhar quadro a quadro (o vídeo já anda no lugar);
##  - mede o passo (abertura das pernas) e diz a velocidade que casa o pé com o chão a 18 fps.
## Loop do jogo: 1..93 uma vez, depois 24..93 (extra.laco_de = 23 na ficha).
## RODAR: godot --headless --path . --script res://ferramentas/cortar_protetor_andando.gd

const ORIGEM := "res://assets/Guerreiro Protetor/andando/andando.png"
const PARADO := "res://assets/Guerreiro Protetor/parado/parado.png"
const PARADO_CEL := Vector2i(335, 298)
const PARADO_AX := 153.23
const PARADO_AY := 295.9
const P_ESCALA := 0.51                    ## escala do personagem na ficha
const PASTA := "res://assets_otimizados/Guerreiro Protetor/andando"
const CEL := Vector2i(1280, 720)
const COLS_G := 10
const QUADROS := 93
const LACO_DE := 24                       ## quadro (contando do 1) onde o loop recomeça
const PAD := 10
const LIMITE := 4096
const ESCALA_TELA := 0.5                  ## 1 px da folha nova = 0,5 px na tela
const FPS := 18.0

func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ORIGEM))
	img.convert(Image.FORMAT_RGBA8)
	var par := Image.load_from_file(ProjectSettings.globalize_path(PARADO))
	par.convert(Image.FORMAT_RGBA8)
	var par0 := par.get_region(Rect2i(Vector2i.ZERO, PARADO_CEL))
	var up := par0.get_used_rect()
	var alt_tela := float(up.size.y) * P_ESCALA                 # altura do parado na tela
	var x0 := CEL.x; var y0 := CEL.y; var x1 := 0; var y1 := 0
	var alturas: Array[float] = []
	for n in QUADROS:
		var u := img.get_region(_reg(n)).get_used_rect()
		x0 = mini(x0, u.position.x); y0 = mini(y0, u.position.y)
		x1 = maxi(x1, u.end.x); y1 = maxi(y1, u.end.y)
		if n + 1 >= LACO_DE:
			alturas.append(float(u.size.y))
	x0 = maxi(0, x0 - PAD); y0 = maxi(0, y0 - PAD); x1 = mini(CEL.x, x1 + PAD); y1 = mini(CEL.y, y1 + PAD)
	var fator := alt_tela / ESCALA_TELA / _mediana(alturas)
	var cw := roundi((x1 - x0) * fator)
	var ch := roundi((y1 - y0) * fator)
	var cols := mini(int(LIMITE / cw), QUADROS)
	var linhas := ceili(float(QUADROS) / cols)
	var saida := Image.create_empty(cols * cw, linhas * ch, false, Image.FORMAT_RGBA8)
	var abertura: Array[float] = []
	var verdes := 0
	var primeiro: Image
	for n in QUADROS:
		var q := img.get_region(Rect2i(_reg(n).position + Vector2i(x0, y0), Vector2i(x1 - x0, y1 - y0)))
		q.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
		verdes += _tirar_verde(q)
		saida.blit_rect(q, Rect2i(0, 0, cw, ch), Vector2i((n % cols) * cw, (n / cols) * ch))
		if n == LACO_DE - 1:
			primeiro = q
		if n + 1 >= LACO_DE:
			var u := q.get_used_rect()
			abertura.append(float(q.get_region(Rect2i(0, u.end.y - 10, cw, 10)).get_used_rect().size.x))
	var nome := "%s/andando_%dx%d.png" % [PASTA, cw, ch]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PASTA))
	saida.save_png(ProjectSettings.globalize_path(nome))
	# âncora: tronco à mesma distância da âncora que no parado; chão na mesma altura
	var ax := _tronco_x(primeiro) - (_tronco_x(par0) - PARADO_AX) * P_ESCALA / ESCALA_TELA
	var ay := float(primeiro.get_used_rect().end.y) - (float(up.end.y) - PARADO_AY) * P_ESCALA / ESCALA_TELA
	# passo: picos da abertura das pernas
	var s: Array[float] = []
	for i in abertura.size():
		s.append((abertura[maxi(0, i - 1)] + abertura[i] * 2.0 + abertura[mini(abertura.size() - 1, i + 1)]) / 4.0)
	var lo: float = s.min(); var hi: float = s.max()
	var corte: float = lo + (hi - lo) * 0.6; var corte_b: float = lo + (hi - lo) * 0.35
	var picos: Array[int] = []; var vp: Array[float] = []; var vv: Array[float] = []
	var i := 0
	while i < s.size():
		if s[i] >= corte:
			var j := i; var mx := i
			while j < s.size() and s[j] >= corte_b:
				if s[j] > s[mx]: mx = j
				j += 1
			picos.append(mx); vp.append(abertura[mx]); i = j
		else:
			if s[i] <= corte_b:
				vv.append(abertura[i])
			i += 1
	var por_passo := float(picos[-1] - picos[0]) / (picos.size() - 1) if picos.size() > 1 else float(s.size()) / 2.0
	var passo_tela := (_mediana(vp) - _mediana(vv)) / por_passo * ESCALA_TELA
	print("SALVO: %s (%dx%d, %d quadros de %dx%d, %d colunas)" % [nome, saida.get_width(), saida.get_height(), QUADROS, cw, ch, cols])
	print("verde tirado: %d px" % verdes)
	print("cols = %d\nquadros = %d\ncw = %d\nch = %d\nax = %.1f\nay = %.1f\nescala = %.6f" % [cols, QUADROS, cw, ch, ax, ay, ESCALA_TELA / P_ESCALA])
	print("passos no loop: %d (%.1f quadros/passo) -> velocidade casada a %.0f fps: %.0f px/s" % [picos.size(), por_passo, FPS, passo_tela * FPS])
	quit(0)

func _reg(n: int) -> Rect2i:
	return Rect2i((n % COLS_G) * CEL.x, (n / COLS_G) * CEL.y, CEL.x, CEL.y)

## Borda esverdeada some (2 passadas: a franja tem 1-2 px); dentro, só perde o tom verde. Devolve quantos px.
func _tirar_verde(q: Image) -> int:
	var w := q.get_width(); var h := q.get_height()
	var n := 0
	for passada in 2:
		var apagar: Array[Vector2i] = []
		for y in h:
			for x in w:
				var c := q.get_pixel(x, y)
				if c.a < 0.02:
					continue
				if c.g - maxf(c.r, c.b) > 0.03 and _na_borda(q, x, y, w, h):
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

func _na_borda(q: Image, x: int, y: int, w: int, h: int) -> bool:
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2)]:
		var xx: int = x + d.x; var yy: int = y + d.y
		if xx < 0 or yy < 0 or xx >= w or yy >= h or q.get_pixel(xx, yy).a < 0.1:
			return true
	return false

func _tronco_x(q: Image) -> float:
	var u := q.get_used_rect()
	var t := q.get_region(Rect2i(0, u.position.y + int(u.size.y * 0.35), q.get_width(), int(u.size.y * 0.2))).get_used_rect()
	return t.position.x + t.size.x / 2.0

static func _mediana(v: Array[float]) -> float:
	if v.is_empty():
		return 0.0
	var c := v.duplicate()
	c.sort()
	return c[c.size() / 2]
