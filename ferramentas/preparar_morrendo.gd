extends SceneTree
## PREPARAR MORRENDO (Guerreiro Protetor): adapta a folha de morte nova do jogo.
## Folha nova: grade 11x11 de células 1280x720, 120 quadros com desenho (o último da grade
## está vazio). O desenho é bem mais largo que o do andar (a espada escorrega para o lado e o
## corpo fica deitado), então no tamanho cheio só cabem 8 col x 13 lin = 104 quadros em 4096 px.
## Por isso corta a CAUDA parada (quadros 104..119 já estão em repouso, diff ~0): perde 16
## quadros parados e mantém todo o movimento, no tamanho cheio do desenho.
## Fator/âncora/escala pelo QUADRO 0 (pose de pé, igual à de referência do parado) — a mediana
## não serve aqui porque a maioria dos quadros está deitada.
## Mesma duração da folha antiga (150 quadros a 32 fps = 4,6875 s) via fps.
## RODAR SEM ABRIR O EDITOR:
##   godot --headless --path "<pasta do projeto>" --script res://ferramentas/preparar_morrendo.gd

const SRC := "res://assets/Guerreiro Protetor/morrendo/morrendo.png"
const PAR := "res://assets/Guerreiro Protetor/parado/parado.png"
const PASTA_DST := "res://assets_otimizados/Guerreiro Protetor/morrendo/"

const COLS := 11                 # grade da folha nova (células 1280x720)
const QUADROS := 121             # 120 com desenho + o último da grade vazio
const MARGEM := 10               # margem transparente ao redor do desenho (px da folha original)

const COLS_SAIDA := 8            # cabe 8 col x 13 lin = 104 quadros de 485x306 no 4096
const QUADROS_SAIDA := 104       # quadros 0..103 (corta só a cauda em repouso)

const FPS_MORRER := 104.0 / (150.0 / 32.0)  # mesma duração da folha antiga: 4,6875 s

const PAR_CW := 335              # folha parado: 8 colunas de 335x298
const PAR_CH := 298
const PAR_AX := 153.23           # âncora da folha parado (mesma do atacar)
const PAR_AY := 295.9
const P_ESCALA := 0.51           # escala do personagem na ficha

func _initialize() -> void:
	var img := _abrir(SRC)
	var par := _abrir(PAR)
	if img == null or par == null:
		quit(1)
		return

	var cw := img.get_width() / COLS
	var ch := img.get_height() / COLS
	print("folha de morte: %dx%d = grade %dx%d, células %dx%d" % [
		img.get_width(), img.get_height(), COLS, img.get_height() / ch, cw, ch])

	# ---- referência: parado quadro 0 ----
	var q0 := par.get_region(Rect2i(0, 0, PAR_CW, PAR_CH))
	var u0 := q0.get_used_rect()
	if u0.size.y <= 0:
		push_error("parado quadro 0 vazio")
		quit(1)
		return
	var corpo0 := _altura_corpo(q0, u0)
	var pe0 := _meio_x(q0, maxi(0, u0.end.y - 7), mini(7, u0.end.y))
	if pe0 < 0.0:
		pe0 = u0.position.x + u0.size.x / 2.0
	print("parado quadro 0: desenho em %s, corpo %d px, pés x %.1f" % [str(u0), corpo0, pe0])

	# ---- quadro 0 da folha nova: é a pose de pé, a base do fator ----
	var n0 := img.get_region(Rect2i(0, 0, cw, ch))
	var nu0 := n0.get_used_rect()
	if nu0.size.y <= 0:
		push_error("morrendo quadro 0 vazio")
		quit(1)
		return
	var nc0 := _altura_corpo(n0, nu0)
	var f := float(corpo0) / float(nc0)
	print("morrendo quadro 0: desenho em %s, corpo de pé %d px -> fator %.4f" % [str(nu0), nc0, f])

	# ---- união do desenho (só quadros com desenho) ----
	var u_min := Vector2i(1 << 30, 1 << 30)
	var u_max := Vector2i(-1, -1)
	var fundo := 0
	var vazios: Array[int] = []
	for i in QUADROS:
		var q := img.get_region(Rect2i((i % COLS) * cw, (i / COLS) * ch, cw, ch))
		var u := q.get_used_rect()
		if u.size.x <= 0 or u.size.y <= 0:
			vazios.append(i)
			continue
		fundo = maxi(fundo, u.end.y)
		u_min = Vector2i(mini(u_min.x, u.position.x), mini(u_min.y, u.position.y))
		u_max = Vector2i(maxi(u_max.x, u.end.x), maxi(u_max.y, u.end.y))
	print("quadros vazios: %s | união %s -> %s | chão y %d" % [str(vazios), str(u_min), str(u_max), fundo])

	var x0 := maxi(0, u_min.x - MARGEM)
	var y0 := maxi(0, u_min.y - MARGEM)
	var x1 := mini(cw, u_max.x + MARGEM)
	var y1 := mini(ch, u_max.y + MARGEM)
	var ncw := int(round(float(x1 - x0) * f))
	var nch := int(round(float(y1 - y0) * f))
	print("corte %dx%d em (%d,%d) da célula %dx%d; fator %.4f -> célula nova %dx%d" % [
		x1 - x0, y1 - y0, x0, y0, cw, ch, f, ncw, nch])

	# ---- monta a folha nova: QUADROS_SAIDA quadros, COLS_SAIDA colunas ----
	var linhas := ceili(float(QUADROS_SAIDA) / COLS_SAIDA)
	var saida := Image.create_empty(COLS_SAIDA * ncw, linhas * nch, false, Image.FORMAT_RGBA8)
	for i in QUADROS_SAIDA:
		var cel := img.get_region(Rect2i((i % COLS) * cw + x0, (i / COLS) * ch + y0, x1 - x0, y1 - y0))
		cel.resize(ncw, nch, Image.INTERPOLATE_LANCZOS)
		saida.blit_rect(cel, Rect2i(Vector2i.ZERO, cel.get_size()),
			Vector2i((i % COLS_SAIDA) * ncw, (i / COLS_SAIDA) * nch))

	# ---- mede a folha pronta pelo QUADRO 0 (pose de pé) ----
	var b0 := saida.get_region(Rect2i(0, 0, ncw, nch))
	var bu0 := b0.get_used_rect()
	var corpo_final := float(_altura_corpo(b0, bu0))
	var pe_novo := _meio_x(b0, maxi(0, bu0.end.y - 7), mini(7, bu0.end.y))
	if pe_novo < 0.0:
		pe_novo = bu0.position.x + bu0.size.x / 2.0
	var c_fundo := 0
	var alturas := []
	for i in QUADROS_SAIDA:
		var q := saida.get_region(Rect2i((i % COLS_SAIDA) * ncw, (i / COLS_SAIDA) * nch, ncw, nch))
		var u := q.get_used_rect()
		if u.size.x <= 0 or u.size.y <= 0:
			alturas.append(0)
			continue
		c_fundo = maxi(c_fundo, u.end.y)
		alturas.append(u.size.y)

	var ew := (float(corpo0) * P_ESCALA) / corpo_final   # tamanho na tela de 1 px da folha nova
	var escala := ew / P_ESCALA                          # = corpo0 / corpo_final
	# âncora dos pés igual à do parado (mesmo ponto do chão nas duas folhas)
	var ax := pe_novo + (PAR_AX - pe0) * P_ESCALA / ew
	var ay := float(c_fundo) - (float(u0.end.y) - PAR_AY) * P_ESCALA / ew
	print("folha pronta: quadro 0 com desenho em %s | chão y %d" % [str(bu0), c_fundo])
	print("alturas dos quadros 40..75 (caiu quando para em ~%d):" % [
		int(round(float(nc0) * f * 0.40))])
	var faixa := []
	for i in range(40, mini(76, QUADROS_SAIDA)):
		faixa.append("%d:%d" % [i, alturas[i]])
	print("  " + " ".join(faixa))

	var nome := PASTA_DST + "morrendo_%dx%d.png" % [ncw, nch]
	DirAccess.make_dir_recursive_absolute(nome.get_base_dir())
	var err := saida.save_png(ProjectSettings.globalize_path(nome))
	if err != OK:
		push_error("erro %d ao salvar %s" % [err, nome])
		quit(1)
		return

	print("")
	print("SALVO: %s = %dx%d (%d quadros de %dx%d, %d colunas)" % [
		nome, saida.get_width(), saida.get_height(), QUADROS_SAIDA, ncw, nch, COLS_SAIDA])
	if saida.get_width() > 4096 or saida.get_height() > 4096:
		push_warning("folha %dx%d passa de 4096 px!" % [saida.get_width(), saida.get_height()])
	print("na tela: corpo parado %.1f px | corpo morrendo %.1f px | na folha %.0f px" % [
		float(corpo0) * P_ESCALA, corpo_final * escala * P_ESCALA, corpo_final])
	print("")
	print("--- valores para protetor.tres (anims.morrer) ---")
	print("textura: " + nome)
	print("cols = %d" % COLS_SAIDA)
	print("quadros = %d" % QUADROS_SAIDA)
	print("cw = %d" % ncw)
	print("ch = %d" % nch)
	print("ax = %.6f" % ax)
	print("ay = %.6f" % ay)
	print("fps = %.14f" % FPS_MORRER)
	print("escala = %.6f" % escala)
	print("quadro_chao = <a definir pela prévia>")
	quit(0)

func _abrir(caminho: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(caminho))
	if img == null or img.is_empty():
		push_error("não abriu: " + caminho)
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img

## Altura do CORPO (chão até o topo, sem a espada): só a metade direita do desenho,
## onde ficam cabeça e escudo — a espada aponta para a esquerda nas duas folhas.
static func _altura_corpo(q: Image, u: Rect2i) -> int:
	var metade := u.size.x / 2
	var ur := q.get_region(Rect2i(u.position.x + metade, u.position.y, u.size.x - metade, u.size.y)).get_used_rect()
	if ur.size.y <= 0:
		return u.size.y
	return u.end.y - (u.position.y + ur.position.y)

## Meio (x) da parte desenhada numa faixa da imagem (-1 se vazia). Igual ao medir_andar.gd.
static func _meio_x(q: Image, y0: int, h: int) -> float:
	y0 = clampi(y0, 0, q.get_height() - 1)
	h = clampi(h, 1, q.get_height() - y0)
	var u := q.get_region(Rect2i(0, y0, q.get_width(), h)).get_used_rect()
	if u.size.x <= 0:
		return -1.0
	return u.position.x + u.size.x / 2.0

static func _mediana(v: Array[float]) -> float:
	if v.is_empty():
		return 0.0
	var c := v.duplicate()
	c.sort()
	return c[c.size() / 2]
