extends SceneTree
## PREPARAR SOCANDO (Esqueleto Protetor): adapta a folha de soco para o mesmo tratamento
## do lutando do Guerreiro Protetor (preparar_andando.gd): mede cada quadro, corta a união
## do desenho com margem, reduz com Lanczos para o corpo casar com o repouso/andar e calca
## a âncora dos pés na mesma linha do chão. Detecta o quadro de CONTATO do soco (punho mais
## avançado) para quadros_acao/quadros_som e gera prévia em faixa do momento do impacto.
## RODAR SEM ABRIR O EDITOR:
##   godot --headless --path "<pasta do projeto>" --script res://ferramentas/preparar_socando.gd

const SRC := "res://assets/Esqueleto Protetor/socando/socando.png"
const PASTA_DST := "res://assets_otimizados/Esqueleto Protetor/socando/"
const PREVIA := "C:/Users/danie/AppData/Local/Temp/opencode/previa_socando_contato.png"

const COLS := 8                  # grade da folha (células 229x190, 19 linhas = 152 quadros)
const CH_ORIG := 190             # altura ORIGINAL de cada célula da grade
const MARGEM := 6                # margem transparente ao redor do desenho (px da folha original)

# referência: folha parado_repouso (mesmo corpo do andar, 189 px ≈ 115 na tela)
const PAR_PATH := "res://assets/Esqueleto Protetor/parado/parado_repouso.png"
const PAR_CW := 145
const PAR_CH := 199
const PAR_AX := 72.5
const PAR_AY := 195.0
const P_ESCALA := 0.61           # escala do personagem na ficha
const FPS_SOCO := 44.0           # timing atual do atacar (preservar)

func _initialize() -> void:
	var img := _abrir(SRC)
	var par := _abrir(PAR_PATH)
	if img == null or par == null:
		quit(1)
		return

	var cw := img.get_width() / COLS
	var ch := CH_ORIG
	if img.get_width() % COLS != 0 or img.get_height() % ch != 0:
		push_error("folha %dx%d não fecha com grade %d cols x células %d px" % [
			img.get_width(), img.get_height(), COLS, ch])
		quit(1)
		return
	var linhas := img.get_height() / ch
	var quadros_total := COLS * linhas
	print("folha de soco: %dx%d = grade %dx%d, células %dx%d (%d quadros)" % [
		img.get_width(), img.get_height(), COLS, linhas, cw, ch, quadros_total])

	# ---- referência: parado_repouso quadro 0 (mesmo corpo do andar) ----
	var q0 := par.get_region(Rect2i(0, 0, PAR_CW, PAR_CH))
	var u0 := q0.get_used_rect()
	if u0.size.y <= 0:
		push_error("parado quadro 0 vazio")
		quit(1)
		return
	var corpo0 := u0.size.y
	var pe0 := _meio_x(q0, maxi(0, u0.end.y - 7), mini(7, u0.end.y))
	if pe0 < 0.0:
		pe0 = u0.position.x + u0.size.x / 2.0
	print("parado quadro 0: desenho em %s, corpo %d px, pés x %.1f" % [str(u0), corpo0, pe0])

	# ---- mede os quadros da folha de soco ----
	var u_min := Vector2i(1 << 30, 1 << 30)
	var u_max := Vector2i(-1, -1)
	var vazios: Array[int] = []
	var reaches: Array[float] = []
	var fundo := 0
	for i in quadros_total:
		var q := img.get_region(Rect2i((i % COLS) * cw, (i / COLS) * ch, cw, ch))
		var u := q.get_used_rect()
		if u.size.x <= 0 or u.size.y <= 0:
			vazios.append(i)
			reaches.append(-1.0)
			continue
		# o esqueleto soca para a ESQUERDA (mesma orientação das folhas): punho = x pequeno
		reaches.append(float(cw - u.position.x))
		fundo = maxi(fundo, u.end.y)
		u_min = Vector2i(mini(u_min.x, u.position.x), mini(u_min.y, u.position.y))
		u_max = Vector2i(maxi(u_max.x, u.end.x), maxi(u_max.y, u.end.y))
	if u_min.y > u_max.y:
		push_error("a folha de soco está vazia")
		quit(1)
		return
	var quadros := quadros_total
	while quadros > 0 and vazios.has(quadros - 1):
		quadros -= 1                  # descarta quadros vazios no FINAL da grade
		print("quadro vazio no final: %d" % quadros)
	var meios: Array[int] = []
	for v in vazios:
		if v < quadros:
			meios.append(v)
	if not meios.is_empty():
		push_warning("quadro vazio no MEIO da folha: %s" % str(meios))
	print("união do desenho: %s -> %s | chão y %d | %d quadros usados" % [str(u_min), str(u_max), fundo, quadros])

	# ---- contato do soco: punho mais avançado (reach máximo) ----
	var contato := 0
	var melhor := -1.0
	for i in quadros:
		if reaches[i] > melhor:
			melhor = reaches[i]
			contato = i
	var ordem: Array[int] = []
	for i in quadros:
		ordem.append(i)
	ordem.sort_custom(func(a, b): return reaches[a] > reaches[b])
	print("contato do soco: quadro %d (reach %.0f) | piores: %s" % [
		contato, melhor, str(ordem.slice(0, 6))])

	# ---- corte da união + margem, fator para o corpo bater com o repouso ----
	var x0 := maxi(0, u_min.x - MARGEM)
	var y0 := maxi(0, u_min.y - MARGEM)
	var x1 := mini(cw, u_max.x + MARGEM)
	var y1 := mini(ch, u_max.y + MARGEM)
	# corpo mediano dos quadros (sem arma acima da cabeça: altura cheia é o corpo)
	var alturas: Array[float] = []
	for i in quadros:
		var q := img.get_region(Rect2i((i % COLS) * cw, (i / COLS) * ch, cw, ch))
		var u := q.get_used_rect()
		if u.size.y > 0:
			alturas.append(float(u.size.y))
	var f := float(corpo0) / _mediana(alturas)
	var ncw := int(round(float(x1 - x0) * f))
	var nch := int(round(float(y1 - y0) * f))
	print("corte %dx%d em (%d,%d) da célula %dx%d; fator %.4f -> célula nova %dx%d" % [
		x1 - x0, y1 - y0, x0, y0, cw, ch, f, ncw, nch])

	# ---- monta a folha nova ----
	var linhas_novas := ceili(float(quadros) / COLS)
	var saida := Image.create_empty(COLS * ncw, linhas_novas * nch, false, Image.FORMAT_RGBA8)
	for i in quadros:
		var cel := img.get_region(Rect2i((i % COLS) * cw + x0, (i / COLS) * ch + y0, x1 - x0, y1 - y0))
		cel.resize(ncw, nch, Image.INTERPOLATE_LANCZOS)
		saida.blit_rect(cel, Rect2i(Vector2i.ZERO, cel.get_size()),
			Vector2i((i % COLS) * ncw, (i / COLS) * nch))

	# ---- mede a folha pronta para gravar os números certos ----
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
		c_corp.append(float(u.size.y))
		var pe := _meio_x(q, maxi(0, u.end.y - 7), mini(7, u.end.y))
		if pe >= 0.0:
			c_pes.append(pe)
		c_fundo = maxi(c_fundo, u.end.y)

	var corpo_final := _mediana(c_corp)
	var ew := (float(corpo0) * P_ESCALA) / corpo_final      # tamanho na tela de 1 px da folha nova
	var escala := ew / P_ESCALA
	var ax := _mediana(c_pes) + (PAR_AX - pe0) * P_ESCALA / ew
	var ay := float(c_fundo) - (float(u0.end.y) - PAR_AY) * P_ESCALA / ew
	print("folha pronta: pés x (mediana) %.1f, chão y %d | repouso: pés x %.1f, chão y %d" % [
		_mediana(c_pes), c_fundo, pe0, u0.end.y])

	# ---- prévia em faixa ao redor do contato (compositando alpha sobre cinza) ----
	var faixa0 := maxi(0, contato - 6)
	var faixa1 := mini(quadros - 1, contato + 6)
	var n_faixa := faixa1 - faixa0 + 1
	var pw := int(ncw * 0.5)
	var ph := int(nch * 0.5)
	var previa := Image.create_empty(pw * n_faixa, ph, false, Image.FORMAT_RGBA8)
	previa.fill(Color(0.15, 0.15, 0.17, 1.0))
	for k in n_faixa:
		var i := faixa0 + k
		var cel := saida.get_region(Rect2i((i % COLS) * ncw, (i / COLS) * nch, ncw, nch))
		cel.resize(pw, ph, Image.INTERPOLATE_BILINEAR)
		var cor_marc := Color(1.0, 0.25, 0.2)
		for y in ph:
			for x in pw:
				var cor := cel.get_pixel(x, y)
				if i == contato and (x < 3 or x >= pw - 3 or y < 3 or y >= ph - 3):
					cor = cor_marc
				var dest := previa.get_pixel(k * pw + x, y)
				previa.set_pixel(k * pw + x, y, dest.blend(cor))
	previa.save_png(PREVIA)
	print("prévia do contato (quadro %d em vermelho, %d..%d): %s" % [contato, faixa0, faixa1, PREVIA])

	var nome := PASTA_DST + "socando_%dx%d.png" % [ncw, nch]
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
	print("na tela: corpo repouso %.1f px | corpo socando %.1f px" % [
		float(corpo0) * P_ESCALA, corpo_final * escala * P_ESCALA])
	print("")
	print("--- valores para esqueletoProtetor.tres (anims.atacar) ---")
	print("textura: " + nome)
	print("cols = %d" % COLS)
	print("quadros = %d" % quadros)
	print("cw = %d" % ncw)
	print("ch = %d" % nch)
	print("ax = %.6f" % ax)
	print("ay = %.6f" % ay)
	print("fps = %.1f   # timing atual preservado" % FPS_SOCO)
	print("escala = %.6f" % escala)
	print("quadros_acao = PackedInt32Array(%d)   # contato do soco" % contato)
	print("quadros_som = PackedInt32Array(%d)   # golpe.mp3 no impacto" % contato)
	quit(0)

func _abrir(caminho: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(caminho))
	if img == null or img.is_empty():
		push_error("não abriu: " + caminho)
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img

## Meio (x) da parte desenhada numa faixa da imagem (-1 se vazia). Igual ao preparar_andando.gd.
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
