extends SceneTree
## CONFERIR REPOUSO: confere a anim "parado" das fichas dos esqueletos:
## folha coerente com a grade (cols x linhas), pé dentro da célula e corpo na tela
## igual ao do andar (trocar andar<->parado não pode pular tamanho).
## RODAR: godot --headless --path "<pasta do projeto>" --script res://ferramentas/conferir_repouso.gd

const FICHAS := [
	"res://dados/personagens/esqueleto.tres",
	"res://dados/personagens/esqueletoFogo.tres",
	"res://dados/personagens/esqueletoArqueiro.tres",
	"res://dados/personagens/esqueletoProtetor.tres",
]

func _initialize() -> void:
	var falhas := 0
	for caminho in FICHAS:
		var p := load(caminho) as PersonagemDados
		if p == null:
			print("FALHOU: não carregou " + caminho)
			falhas += 1
			continue
		var a := p.anim("parado")
		var andar := p.anim("andar")
		if a == null or a.textura == null:
			print("FALHOU: %s sem anim parado" % p.id)
			falhas += 1
			continue
		var linhas := a.linhas()
		var folha_w := a.textura.get_width()
		var folha_h := a.textura.get_height()
		var grade_ok := folha_w >= a.cols * a.cw and folha_h >= linhas * a.ch
		var ultimo_ok := (a.quadros - 1) % a.cols * a.cw + a.cw <= folha_w
		# corpo do quadro 0
		var img := Image.load_from_file(ProjectSettings.globalize_path(a.textura.resource_path))
		var corpo := 0.0
		var pe_y := 0.0
		if img != null and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			var cel := img.get_region(Rect2i(0, 0, a.cw, a.ch))
			var bb := cel.get_used_rect()
			corpo = float(bb.size.y) * a.escala * p.escala
			pe_y = float(bb.end.y)
		var andar_corpo := 0.0
		if andar != null and andar.textura != null:
			var img2 := Image.load_from_file(ProjectSettings.globalize_path(andar.textura.resource_path))
			if img2 != null and not img2.is_empty():
				img2.convert(Image.FORMAT_RGBA8)
				var cel2 := img2.get_region(Rect2i(0, 0, andar.cw, andar.ch))
				andar_corpo = float(cel2.get_used_rect().size.y) * andar.escala * p.escala
		var pula := absf(corpo - andar_corpo)
		var pe_ok := a.ay <= a.ch and a.ax >= 0.0 and a.ax <= a.cw and absf(a.ay - pe_y) <= 12.0
		var ok := grade_ok and ultimo_ok and pe_ok and pula <= 8.0
		print("%s parado: folha %dx%d | %d cols x %d quadros de %dx%d | grade %s | pé %s | na tela: repouso %.1f px, andar %.1f px, pulo %+.1f px -> %s" % [
			p.id, folha_w, folha_h, a.cols, linhas, a.cw, a.ch,
			"ok" if grade_ok else "RUIM",
			"ok" if pe_ok else "RUIM",
			corpo, andar_corpo, pula,
			"ok" if ok else "FALHOU"])
		if not ok:
			falhas += 1
		# ---- atacar (se existir): só a grade da folha ----
		var at := p.anim("atacar")
		if at != null and at.textura != null:
			var aw := at.textura.get_width()
			var ah := at.textura.get_height()
			var a_linhas := at.linhas()
			var a_grade := aw >= at.cols * at.cw and ah >= a_linhas * at.ch
			var a_ultimo := (at.quadros - 1) % at.cols * at.cw + at.cw <= aw
			print("%s atacar: folha %dx%d | %d cols x %d quadros de %dx%d | grade %s -> %s" % [
				p.id, aw, ah, at.cols, a_linhas, at.cw, at.ch,
				"ok" if a_grade and a_ultimo else "RUIM",
				"ok" if a_grade and a_ultimo else "FALHOU"])
			if not a_grade or not a_ultimo:
				falhas += 1
	if falhas == 0:
		print("TUDO CERTO")
		quit(0)
	else:
		print("FALHAS: %d" % falhas)
		quit(1)
