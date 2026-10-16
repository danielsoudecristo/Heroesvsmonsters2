extends SceneTree
## PREPARAR ANDANDO (Guerreiro Protetor): adapta a folha de andar nova do jogo.
## A folha veio em grade 11x11 de células 1280x720 (16:9, cheia de transparente em volta) e o
## último quadro está vazio. Este script mede cada quadro, corta a união do desenho com margem,
## reduz com Lanczos para o corpo ficar do mesmo tamanho na tela do herói parado (é o papel do
## medir_andar.gd + otimizar_folhas.gd, mas esses não servem direito para célula 16:9 de 121
## quadros) e calca ax/ay no parado: mesma âncora dos pés e a mesma linha do chão.
## Conferência visual (parado x andar em escala de tela): diag_andando.gd.
## RODAR SEM ABRIR O EDITOR:
##   godot --headless --path "<pasta do projeto>" --script res://ferramentas/preparar_andando.gd

const SRC := "res://assets/Guerreiro Protetor/andando/andando.png"
const PAR := "res://assets/Guerreiro Protetor/parado/parado.png"
const PASTA_DST := "res://assets_otimizados/Guerreiro Protetor/andando/"

const COLS := 11                 # grade da folha nova (células 1280x720, 121 quadros)
const QUADROS := 121
const MARGEM := 10               # margem transparente ao redor do desenho (px da folha original)

const PAR_CW := 335              # folha parado: 8 colunas de 335x298
const PAR_CH := 298
const PAR_AX := 153.23           # âncora da folha parado (mesma do atacar)
const PAR_AY := 295.9
const P_ESCALA := 0.51           # escala do personagem na ficha
const FPS_ANDAR := 12.60784351804148  # mesmo tempo de passo da folha de andar antiga

func _initialize() -> void:
	var img := _abrir(SRC)
	var par := _abrir(PAR)
	if img == null or par == null:
		quit(1)
		return

	var cw := img.get_width() / COLS
	var ch := img.get_height() / COLS
	print("folha de andar: %dx%d = grade %dx%d, células %dx%d" % [
		img.get_width(), img.get_height(), COLS, img.get_height() / ch, cw, ch])

	# ---- referência: parado quadro 0 (é o quadro que o medir_andar.gd usa) ----
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

	# ---- mede os 121 quadros da folha de andar ----
	var alturas: Array[float] = []
	var corpos: Array[float] = []
	var troncos: Array[float] = []
	var fundo := 0
	var u_min := Vector2i(1 << 30, 1 << 30)
	var u_max := Vector2i(-1, -1)
	var vazios: Array[int] = []
	for i in QUADROS:
		var q := img.get_region(Rect2i((i % COLS) * cw, (i / COLS) * ch, cw, ch))
		var u := q.get_used_rect()
		if u.size.x <= 0 or u.size.y <= 0:
			vazios.append(i)
			continue
		alturas.append(float(u.size.y))
		corpos.append(float(_altura_corpo(q, u)))
		var t := _meio_x(q, u.position.y + int(u.size.y * 0.22), maxi(1, int(u.size.y * 0.25)))
		if t >= 0.0:
			troncos.append(t)
		fundo = maxi(fundo, u.end.y)
		u_min = Vector2i(mini(u_min.x, u.position.x), mini(u_min.y, u.position.y))
		u_max = Vector2i(maxi(u_max.x, u.end.x), maxi(u_max.y, u.end.y))
	if corpos.is_empty():
		push_error("a folha de andar está vazia")
		quit(1)
		return
	var quadros := QUADROS
	if not vazios.is_empty():
		print("quadros vazios: %s" % str(vazios))
		if vazios == [QUADROS - 1]:
			quadros = QUADROS - 1        # só o último quadro (a última célula da grade) está sem desenho
		else:
			push_warning("quadro vazio no MEIO da folha: a animação vai dar um pulo")
	print("andar (mediana de %d quadros): desenho alto %.0f, corpo (sem espada) %.0f, tronco x %.1f, chão y %d" % [
		corpos.size(), _mediana(alturas), _mediana(corpos), _mediana(troncos), fundo])
	print("união do desenho: %s -> %s" % [str(u_min), str(u_max)])

	# ---- corte da união + margem, e fator para o corpo bater com o parado ----
	var x0 := maxi(0, u_min.x - MARGEM)
	var y0 := maxi(0, u_min.y - MARGEM)
	var x1 := mini(cw, u_max.x + MARGEM)
	var y1 := mini(ch, u_max.y + MARGEM)
	var f := float(corpo0) / _mediana(corpos)
	var ncw := int(round(float(x1 - x0) * f))
	var nch := int(round(float(y1 - y0) * f))
	print("corte %dx%d em (%d,%d) da célula %dx%d; fator %.4f -> célula nova %dx%d" % [
		x1 - x0, y1 - y0, x0, y0, cw, ch, f, ncw, nch])

	# ---- monta a folha nova: células 11x11 ----
	var linhas := ceili(float(QUADROS) / COLS)
	var saida := Image.create_empty(COLS * ncw, linhas * nch, false, Image.FORMAT_RGBA8)
	for i in QUADROS:
		var cel := img.get_region(Rect2i((i % COLS) * cw + x0, (i / COLS) * ch + y0, x1 - x0, y1 - y0))
		cel.resize(ncw, nch, Image.INTERPOLATE_LANCZOS)   # mesma interpolação do otimizar_folhas.gd
		saida.blit_rect(cel, Rect2i(Vector2i.ZERO, cel.get_size()),
			Vector2i((i % COLS) * ncw, (i / COLS) * nch))

	# ---- mede a folha pronta (já em pixels da folha nova) para gravar os números certos ----
	var c_alt: Array[float] = []
	var c_corp: Array[float] = []
	var c_pes: Array[float] = []
	var c_fundo := 0
	for i in quadros:
		var q := saida.get_region(Rect2i((i % COLS) * ncw, (i / COLS) * nch, ncw, nch))
		var u := q.get_used_rect()
		if u.size.x <= 0 or u.size.y <= 0:
			continue
		c_alt.append(float(u.size.y))
		c_corp.append(float(_altura_corpo(q, u)))
		var pe := _meio_x(q, maxi(0, u.end.y - 7), mini(7, u.end.y))
		if pe >= 0.0:
			c_pes.append(pe)
		c_fundo = maxi(c_fundo, u.end.y)

	var corpo_final := _mediana(c_corp)
	var ew := (float(corpo0) * P_ESCALA) / corpo_final      # tamanho na tela de 1 px da folha
	var escala := ew / P_ESCALA
	# âncora dos pés igual à do parado (é o mesmo ponto do chão nas duas folhas)
	var ax := _mediana(c_pes) + (PAR_AX - pe0) * P_ESCALA / ew
	var ay := float(c_fundo) - (float(u0.end.y) - PAR_AY) * P_ESCALA / ew
	print("folha pronta: pés x (mediana) %.1f, chão y %d | parado: pés x %.1f, chão y %d" % [
		_mediana(c_pes), c_fundo, pe0, u0.end.y])

	var nome := PASTA_DST + "andando_%dx%d.png" % [ncw, nch]
	DirAccess.make_dir_recursive_absolute(nome.get_base_dir())
	var err := saida.save_png(ProjectSettings.globalize_path(nome))
	if err != OK:
		push_error("erro %d ao salvar %s" % [err, nome])
		quit(1)
		return

	print("")
	print("SALVO: %s = %dx%d (%d quadros de %dx%d, %d colunas)" % [
		nome, saida.get_width(), saida.get_height(), quadros, ncw, nch, COLS])
	if saida.get_width() > 4096 or saida.get_height() > 4096:
		push_warning("folha %dx%d passa de 4096 px!" % [saida.get_width(), saida.get_height()])
	print("na tela: corpo parado %.1f px | corpo andando %.1f px | desenho parado %.1f px | desenho andando %.1f px" % [
		float(corpo0) * P_ESCALA, corpo_final * escala * P_ESCALA,
		float(u0.size.y) * P_ESCALA, _mediana(c_alt) * escala * P_ESCALA])
	print("")
	print("--- valores para protetor.tres (anims.andar) ---")
	print("textura: " + nome)
	print("cols = %d" % COLS)
	print("quadros = %d" % quadros)
	print("cw = %d" % ncw)
	print("ch = %d" % nch)
	print("ax = %.6f" % ax)
	print("ay = %.6f" % ay)
	print("fps = %.14f" % FPS_ANDAR)
	print("escala = %.6f" % escala)
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
