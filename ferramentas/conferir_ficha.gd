extends SceneTree
## CONFERIR FICHA: abre dados/personagens/protetor.tres e confere as animações:
## grade coerente com a folha, corpo na tela do mesmo tamanho e pés na mesma linha
## entre parado/andar/atacar/defender (o jogo troca de uma pra outra o tempo todo).
## Também confere se os scripts dos ferramentas estão sem erro de sintaxe.
## RODAR: godot --headless --path "<pasta do projeto>" --script res://ferramentas/conferir_ficha.gd

const CAMINHO := "res://dados/personagens/protetor.tres"
const ORDEM := ["parado", "andar", "atacar", "defender", "morrer"]
const FERRAMENTAS := [
	"res://ferramentas/medir_andar.gd",
	"res://ferramentas/criar_parado.gd",
	"res://ferramentas/preparar_andando.gd",
	"res://ferramentas/preparar_morrendo.gd",
	"res://ferramentas/diag_andando.gd",
	"res://ferramentas/grade_andando.gd",
	"res://ferramentas/previa_morrendo.gd",
	"res://ferramentas/previa_troca.gd",
	"res://ferramentas/limpar_repouso.gd",
	"res://ferramentas/diag_repouso.gd",
	"res://ferramentas/conferir_repouso.gd",
	"res://ferramentas/preparar_socando.gd",
	"res://ferramentas/conferir_ficha.gd",
]

func _initialize() -> void:
	var p := load(CAMINHO) as PersonagemDados
	if p == null:
		push_error("não carregou " + CAMINHO)
		quit(1)
		return
	print("ficha: %s | escala %.3f | anims: %s" % [p.nome, p.escala, str(p.anims.keys())])
	var erros := 0
	var linhas: Array[String] = []
	for nome in ORDEM:
		if not p.anims.has(nome):
			print("  !! falta a animação " + nome)
			erros += 1
			continue
		var a: AnimDados = p.anims[nome]
		if a.textura == null:
			print("  !! %s sem textura" % nome)
			erros += 1
			continue
		var tex: Texture2D = a.textura
		var ts := tex.get_size()
		var linhas_nec := ceili(float(a.quadros) / float(a.cols))
		var ok_grade := a.cols * a.cw == int(ts.x) and linhas_nec * a.ch <= int(ts.y)
		var img := _abrir(a.textura.resource_path)
		if img == null:
			print("  !! não abriu a folha de %s (%s)" % [nome, a.textura.resource_path])
			erros += 1
			continue
		# mede o quadro 0 (é o que o medir_andar usa como referência)
		var u := img.get_region(Rect2i(a.retangulo(0))).get_used_rect()
		var e := p.escala * a.escala
		var corpo := (u.end.y - u.position.y) * e
		var pe_y := (u.end.y - a.ay) * e
		# quadro último (garante que a grade cobre todos os quadros)
		var ult := a.retangulo(a.quadros - 1)
		var uult := img.get_region(Rect2i(ult)).get_used_rect()
		var ok_ult := ult.end.x <= img.get_width() and ult.end.y <= img.get_height() and uult.size.y > 0
		if not ok_grade or not ok_ult:
			erros += 1
		# pés: mediana em vários quadros (no andar o pé sobe/descê a cada passo)
		var pe := _pes_mediana(a, p, img)
		linhas.append("%-9s folha %4dx%-4d | %2d cols x %3d quadros de %3dx%3d | grade %s | quadro0 %s | quadro %d %s | na tela: corpo %6.1f px, pés (%+.1f, %+.1f)%s" % [
			nome, int(ts.x), int(ts.y), a.cols, a.quadros, a.cw, a.ch,
			"ok" if ok_grade else "ERRADO", str(u), a.quadros - 1, "ok" if ok_ult else "ERRADO",
			corpo, pe.x, pe_y,
			"  <- folha trocada, falta adaptar" if (not ok_grade or not ok_ult) else ""])
	for l in linhas:
		print("  " + l)
	# diferenças entre as poses (é o que o jogador vê ao parar para andar/atacar)
	print("")
	print("diferença de corpo parado->andar: %+.2f px | pés: (%+.2f, %+.2f)" % [
		_corpo(p, "andar") - _corpo(p, "parado"),
		_pes(p, "andar").x - _pes(p, "parado").x, _pes(p, "andar").y - _pes(p, "parado").y])
	print("diferença de corpo parado->atacar: %+.2f px | pés: (%+.2f, %+.2f)" % [
		_corpo(p, "atacar") - _corpo(p, "parado"),
		_pes(p, "atacar").x - _pes(p, "parado").x, _pes(p, "atacar").y - _pes(p, "parado").y])
	print("parado: %d quadros (folha %s), fps %.1f" % [
		p.anims["parado"].quadros, str(p.anims["parado"].textura.get_size()), p.anims["parado"].fps])
	print("")
	for caminho in FERRAMENTAS:
		if load(caminho) == null:
			print("  !! erro de sintaxe em " + caminho)
			erros += 1
		else:
			print("  script ok: " + caminho)
	if erros > 0:
		print("ERROS: %d" % erros)
		quit(1)
		return
	print("TUDO CERTO")
	quit(0)

func _abrir(caminho: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(caminho))
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img

## Pés na tela (relativos à posição da unidade): mediana do x em vários quadros e o chão mais baixo.
func _pes_mediana(a: AnimDados, p: PersonagemDados, img: Image) -> Vector2:
	var e := p.escala * a.escala
	var xs: Array[float] = []
	var fundo := 0
	var passo := maxi(1, a.quadros / 9)
	var i := 0
	while i < a.quadros:
		var q := img.get_region(Rect2i(a.retangulo(i)))
		var u := q.get_used_rect()
		if u.size.y > 0:
			fundo = maxi(fundo, u.end.y)
			var mei := q.get_region(Rect2i(0, maxi(0, u.end.y - 7), q.get_width(), mini(7, u.end.y))).get_used_rect()
			if mei.size.x > 0:
				xs.append((mei.position.x + mei.size.x / 2.0 - a.ax) * e)
		i += passo
	if xs.is_empty():
		return Vector2(-999.0, (float(fundo) - a.ay) * e)
	xs.sort()
	return Vector2(xs[xs.size() / 2], (float(fundo) - a.ay) * e)

func _corpo(p: PersonagemDados, nome: String) -> float:
	var a: AnimDados = p.anims[nome]
	var img := _abrir(a.textura.resource_path)
	var u := img.get_region(Rect2i(a.retangulo(0))).get_used_rect()
	return (u.end.y - u.position.y) * p.escala * a.escala

func _pes(p: PersonagemDados, nome: String) -> Vector2:
	var a: AnimDados = p.anims[nome]
	return _pes_mediana(a, p, _abrir(a.textura.resource_path))
