@tool
extends EditorScript
## MEDIR ANDAR: liga a animação de ANDAR dos heróis (o PvP precisa: os heróis marcham até o castelo inimigo).
## Igual ao site: abre <pasta do herói>/andando/andando.png, corta pela grade, acha os pés e o meio do corpo,
## e deixa o herói andando do MESMO tamanho e no MESMO lugar do herói parado (não "pula" ao parar para atacar).
## Também acerta a velocidade da animação com a do passo, para o pé não escorregar.
## COMO USAR: abra este arquivo e aperte Ctrl+Shift+X.
## ORDEM: gerar_fichas.gd (se ainda não rodou) -> medir_andar.gd -> otimizar_folhas.gd.
## Não mexe nas outras animações. Pode rodar de novo quando trocar alguma folha de andar.

const PASTA := "res://dados/personagens/"
## grade = colunas x linhas da folha; quadros = quantos desenhos tem; passo = quanto o pé no chão anda por quadro
## (em pixels da folha original). Os mesmos números do MODO_MONSTERS.andar do jogo.js.
const HEROIS := {
	"nick": {"pasta": "Nick", "grade": [8, 12], "quadros": 89, "passo": 3.5},
	"arqueiro": {"pasta": "Arqueiro", "grade": [8, 4], "quadros": 32, "passo": 7.5},
	"sentinela": {"pasta": "Cavaleiro Sentinela", "grade": [8, 13], "quadros": 97, "passo": 4.57},
	# protetor: folha nova em grade 11x11 (célula 16:9, 120 quadros; o último está vazio).
	# Para REGERAR a folha dele rode preparar_andando.gd (corta a margem e reduz) — o caminho
	# medir_andar -> otimizar_folhas não serve pra célula 16:9 de 121 quadros (folha ficaria alta demais).
	"protetor": {"pasta": "Guerreiro Protetor", "grade": [11, 11], "quadros": 120, "passo": 8.0},
	"mago": {"pasta": "Mago", "grade": [8, 15], "quadros": 115, "passo": 3.76},
	"magoFogo": {"pasta": "Mago de Fogo", "grade": [8, 19], "quadros": 147, "passo": 5.63},
}

func _run() -> void:
	var feitos := 0
	for id in HEROIS:
		var caminho: String = PASTA + id + ".tres"
		if not ResourceLoader.exists(caminho):
			push_warning("medir_andar: não achei a ficha %s (rode o gerar_fichas.gd)" % caminho)
			continue
		var p := load(caminho) as PersonagemDados
		var msg := aplicar(p, HEROIS[id])
		print("  %s: %s" % [id, msg])
		if p.anims.has("andar"):
			ResourceSaver.save(p, caminho)
			feitos += 1
	EditorInterface.get_resource_filesystem().scan()
	print("=== MEDIR ANDAR: %d heróis andando. Agora rode o otimizar_folhas.gd. ===" % feitos)

## Mede a folha de andar e grava na ficha (anims.andar + extra.andar). Devolve o que aconteceu (texto).
static func aplicar(p: PersonagemDados, cfg: Dictionary) -> String:
	var cam := "res://assets/%s/andando/andando.png" % cfg.pasta
	if not ResourceLoader.exists(cam):
		return "sem %s (ele fica parado na casa no PvP)" % cam
	var img := Image.load_from_file(ProjectSettings.globalize_path(cam))
	if img == null or img.is_empty():
		return "não consegui abrir %s" % cam
	img.convert(Image.FORMAT_RGBA8)
	if img.get_pixel(1, 1).a > 0.8:
		push_warning("%s: a folha de andar tem FUNDO (não é transparente). Recorte o fundo para o herói aparecer certo." % p.id)
	var cols: int = cfg.grade[0]
	var linhas: int = cfg.grade[1]
	var n := mini(int(cfg.quadros), cols * linhas)
	var cw := img.get_width() / cols
	var ch := img.get_height() / linhas
	var alturas: Array[float] = []
	var troncos: Array[float] = []
	var pes_x: Array[float] = []
	var fundo := 0
	const B := 2                                          # ignora a beiradinha do quadro (linha do vizinho)
	for i in n:
		var reg := Rect2i((i % cols) * cw + B, (i / cols) * ch + B, cw - B * 2, ch - B * 2)
		var q := img.get_region(reg)
		var u := q.get_used_rect()
		if u.size.x <= 0 or u.size.y <= 0:
			continue
		alturas.append(u.size.y)
		fundo = maxi(fundo, u.end.y + B)
		var tronco := _meio_x(q, u.position.y + int(u.size.y * 0.22), maxi(1, int(u.size.y * 0.25)))
		if tronco >= 0.0:
			troncos.append(tronco + B)
		var pe := _meio_x(q, maxi(0, u.end.y - 7), mini(7, u.end.y))
		if pe >= 0.0:
			pes_x.append(pe + B)
	if alturas.is_empty():
		return "a folha está vazia"
	var ref := medir_parado(p)
	var vel: float = float(ConfigPvp.andar(p.id).velocidade)
	var ew: float                                         # tamanho na tela de 1 pixel da folha de andar
	var ax: float
	var ay: float
	if ref.is_empty():
		ew = 150.0 / _mediana(alturas)
		ax = _mediana(pes_x)
		ay = fundo
	else:
		ew = float(ref.altura) / _mediana(alturas)
		ax = (_mediana(troncos) - float(ref.tronco_x) / ew) if not troncos.is_empty() else _mediana(pes_x)
		ay = fundo - float(ref.pes_y) / ew
	var a := AnimDados.new()
	a.textura = load(cam)
	a.cols = cols
	a.quadros = n
	a.cw = cw
	a.ch = ch
	a.ax = ax
	a.ay = ay
	a.escala = ew / p.escala
	a.repetir = true
	a.olha_direita = false
	a.fps = clampf(vel / (float(cfg.passo) * ew), 6.0, 60.0) if cfg.has("passo") else 30.0   # passo casado com a velocidade
	p.anims["andar"] = a
	var ex: Dictionary = ConfigPvp.andar(p.id)
	p.extra["andar"] = {"velocidade": ex.velocidade, "para": ex.para, "pausa": ex.get("pausa", 0.35)}
	return "andar pronto (%d quadros, %dx%d, %.0f fps)" % [n, cw, ch, a.fps]

## Altura do herói parado na tela, o meio do tronco e a linha dos pés (para o andar ficar igual).
static func medir_parado(p: PersonagemDados) -> Dictionary:
	var a := p.anim_qualquer(["parado", "defender"])
	if a == null or a.textura == null:
		return {}
	var img := Image.load_from_file(ProjectSettings.globalize_path(a.textura.resource_path))
	if img == null or img.is_empty():
		return {}
	img.convert(Image.FORMAT_RGBA8)
	var q := img.get_region(Rect2i(a.retangulo(0)))
	var u := q.get_used_rect()
	if u.size.y <= 0:
		return {}
	var e := p.escala * a.escala
	var tronco := _meio_x(q, u.position.y + int(u.size.y * 0.22), maxi(1, int(u.size.y * 0.25)))
	if tronco < 0.0:
		tronco = u.position.x + u.size.x / 2.0
	return {"altura": u.size.y * e, "tronco_x": (tronco - a.ax) * e, "pes_y": (u.end.y - a.ay) * e}

## Meio (x) da parte desenhada numa faixa da imagem (-1 se vazia). Usa o recorte nativo do Godot (rápido).
static func _meio_x(q: Image, y0: int, h: int) -> float:
	y0 = clampi(y0, 0, q.get_height() - 1)
	h = clampi(h, 1, q.get_height() - y0)
	var u := q.get_region(Rect2i(0, y0, q.get_width(), h)).get_used_rect()
	if u.size.x <= 0:
		return -1.0
	return u.position.x + u.size.x / 2.0

static func _mediana(v: Array[float]) -> float:
	var c := v.duplicate()
	c.sort()
	return c[c.size() / 2]
