extends SceneTree
## CORTAR ENGENHEIRO ANDANDO: a folha grande de andar do Engenheiro Arcano (95 quadros de 1280x720,
## grade 10x10) vira uma folha leve para o jogo, do MESMO tamanho do parado e com o pé no mesmo ponto.
##   quadros 1..21  = sai do repouso e vira de lado (toca uma vez quando ele começa a andar)
##   quadros 22..95 = o passo (loop: 95 -> 22 -> 95 ...) — fica gravado em extra.laco_de da animação
## Cada quadro é alinhado pela CABEÇA (x) e pelo CHÃO (y): some o "deslize" da filmagem.
## Também mede quanto o pé de apoio anda por quadro e diz a velocidade que casa com 18 fps (o pé não escorrega).
## RODAR: godot --headless --path "<pasta do projeto>" --script res://ferramentas/cortar_engenheiro_andando.gd

const ORIGEM := "res://assets/Engenheiro Arcano/andando/adando.png"
const PARADO := "res://assets_otimizados/Engenheiro Arcano/parado_225x321.png"
const PARADO_CW := 225                    ## a folha parado (a mesma da ficha)
const PARADO_CH := 321
const PASTA := "res://assets_otimizados/Engenheiro Arcano"
const CEL := Vector2i(1280, 720)
const COLS_GRANDE := 10
const QUADROS := 95
const LACO_DE := 22                       ## quadro (contando do 1) onde o loop do passo recomeça
const LIMITE := 4096
const PAD := 10                           ## margem (px da folha grande) em volta do desenho
const FPS_ANDAR := 18.0                   ## todos os que andam usam 18 fps; a velocidade é que casa com o passo
const ESCALA_TELA := 0.5                  ## p.escala x a.escala da ficha: 1 px da folha = 0,5 px na tela

func _initialize() -> void:
	var img := _abrir(ORIGEM)
	var par := _abrir(PARADO)
	if img == null or par == null:
		quit(1)
		return
	if img.get_width() != COLS_GRANDE * CEL.x or img.get_height() < 10 * CEL.y:
		push_error("folha veio %dx%d (esperado %dx%d)" % [img.get_width(), img.get_height(), COLS_GRANDE * CEL.x, 10 * CEL.y])
		quit(1)
		return
	# ---- referência: altura do desenho no parado (px da folha parado = 2x a tela) ----
	var up := par.get_region(Rect2i(0, 0, PARADO_CW, PARADO_CH)).get_used_rect()
	var alt_parado := float(up.size.y)
	print("parado quadro 0: desenho %s (altura %d px na folha, %.0f na tela)" % [str(up), up.size.y, alt_parado * ESCALA_TELA])

	# ---- mede os 95 quadros: caixa, cabeça (x) e chão (y) ----
	var med: Array = []
	var alturas: Array[float] = []
	for n in QUADROS:
		var reg := Rect2i((n % COLS_GRANDE) * CEL.x + 2, (n / COLS_GRANDE) * CEL.y + 2, CEL.x - 4, CEL.y - 4)
		var q := img.get_region(reg)
		var u := q.get_used_rect()
		if u.size.y <= 0:
			push_error("quadro %d vazio" % (n + 1))
			quit(1)
			return
		var cabeca := _meio_x(q, u.position.y, maxi(4, int(u.size.y * 0.10)))
		med.append({"reg": reg, "u": u, "cab": cabeca, "chao": u.end.y})
		if n + 1 >= LACO_DE:
			alturas.append(float(u.size.y))
	var alt_andar := _mediana(alturas)
	var fator := alt_parado / alt_andar
	print("andar: altura mediana %.0f px na folha grande -> fator %.5f" % [alt_andar, fator])

	# ---- caixa comum com todos os quadros alinhados pela cabeça e pelo chão ----
	var x0 := 1 << 30; var y0 := 1 << 30; var x1 := -(1 << 30); var y1 := -(1 << 30)
	for m in med:
		var u: Rect2i = m.u
		x0 = mini(x0, u.position.x - int(m.cab)); x1 = maxi(x1, u.end.x - int(m.cab))
		y0 = mini(y0, u.position.y - int(m.chao)); y1 = maxi(y1, u.end.y - int(m.chao))
	x0 -= PAD; y0 -= PAD; x1 += PAD; y1 += PAD
	var cw := roundi((x1 - x0) * fator)
	var ch := roundi((y1 - y0) * fator)
	var cols := mini(int(LIMITE / cw), QUADROS)
	var linhas := ceili(float(QUADROS) / cols)
	if linhas * ch > LIMITE:
		push_error("folha ficaria %dx%d" % [cols * cw, linhas * ch])
		quit(1)
		return
	var saida := Image.create_empty(cols * cw, linhas * ch, false, Image.FORMAT_RGBA8)
	var pes: Array[float] = []                 # x do meio dos pés (relativo à cabeça) — vira o ax
	var abertura: Array[float] = []            # largura da faixa dos pés (px da folha grande), quadro a quadro do loop
	for n in QUADROS:
		var m: Dictionary = med[n]
		var u: Rect2i = m.u
		var q := img.get_region(Rect2i(m.reg.position + u.position, u.size))
		q.resize(maxi(1, roundi(u.size.x * fator)), maxi(1, roundi(u.size.y * fator)), Image.INTERPOLATE_LANCZOS)
		var destino := Vector2i(roundi((u.position.x - m.cab - x0) * fator), roundi((u.position.y - m.chao - y0) * fator))
		saida.blit_rect(q, Rect2i(Vector2i.ZERO, q.get_size()), destino + Vector2i((n % cols) * cw, (n / cols) * ch))
		var cel := img.get_region(m.reg)
		var faixa_pe := _meio_x(cel, int(m.chao) - 24, 24)
		if n + 1 >= LACO_DE:
			if faixa_pe >= 0.0:
				pes.append(faixa_pe - m.cab)
			abertura.append(float(cel.get_region(Rect2i(0, int(m.chao) - 40, cel.get_width(), 40)).get_used_rect().size.x))
	var ax := (_mediana(pes) - x0) * fator
	var ay := float(-y0) * fator
	# ---- passo: pela abertura das pernas (largura da faixa dos pés) ao longo do loop ----
	# abre (pé da frente lá na frente) -> fecha (pernas juntas) -> abre ... cada "abre" é um passo;
	# o pé de apoio volta (abertura máxima - largura de um pé) a cada passo.
	var maximos: Array[float] = []; var minimos: Array[float] = []; var idx_max: Array[int] = []
	for i in range(1, abertura.size() - 1):
		if abertura[i] >= abertura[i - 1] and abertura[i] > abertura[i + 1]:
			if abertura[i] > 280.0 and (idx_max.is_empty() or i - idx_max[-1] > 8):
				maximos.append(abertura[i]); idx_max.append(i)
		elif abertura[i] <= abertura[i - 1] and abertura[i] < abertura[i + 1] and abertura[i] < 180.0:
			minimos.append(abertura[i])
	var quadros_passo := float(idx_max[-1] - idx_max[0]) / maxf(1.0, idx_max.size() - 1) if idx_max.size() > 1 else 19.0
	var passos := idx_max.size()
	var passo := (_mediana(maximos) - _mediana(minimos)) / quadros_passo if not minimos.is_empty() else 14.0
	print("abertura das pernas: picos nos quadros %s (%.1f quadros por passo), aberta %.0f / fechada %.0f px" % [
		str(idx_max.map(func(k): return k + LACO_DE)), quadros_passo, _mediana(maximos), _mediana(minimos)])
	var passo_tela := passo * fator * ESCALA_TELA
	var fps := FPS_ANDAR
	print("velocidade que casa o pé com o chão a %.0f fps: %.0f px/s (extra.andar.velocidade e ConfigPvp.ANDAR)" % [fps, passo_tela * fps])

	var caminho := "%s/andando_%dx%d.png" % [PASTA, cw, ch]
	DirAccess.make_dir_recursive_absolute(PASTA)
	var err := saida.save_png(ProjectSettings.globalize_path(caminho))
	if err != OK:
		push_error("erro %d ao salvar %s" % [err, caminho])
		quit(1)
		return
	print("")
	print("SALVO: %s = %dx%d (%d quadros de %dx%d, %d colunas)" % [caminho, saida.get_width(), saida.get_height(), QUADROS, cw, ch, cols])
	print("passo do pé: %.2f px/quadro na folha grande = %.2f px na tela (%d passos no loop) -> fps %.2f" % [passo, passo_tela, passos, fps])
	print("--- anims.andar ---")
	print("cols = %d" % cols)
	print("quadros = %d" % QUADROS)
	print("cw = %d" % cw)
	print("ch = %d" % ch)
	print("ax = %.1f" % ax)
	print("ay = %.1f" % ay)
	print("fps = %.2f" % fps)
	print("laco_de = %d (índice do 0)" % (LACO_DE - 1))
	quit(0)

func _abrir(caminho: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(caminho))
	if img == null or img.is_empty():
		push_error("não abriu: " + caminho)
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img

## Meio (x) da parte desenhada numa faixa da imagem (-1 se vazia).
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
