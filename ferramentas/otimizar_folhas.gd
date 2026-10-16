@tool
extends EditorScript
## OTIMIZAR FOLHAS: deixa as animações leves para celular, sem mudar o tamanho na tela.
## Para cada animação das fichas:
##  1) se a folha é bem maior do que aparece no jogo, diminui cada quadro (mantendo QUALIDADE x o tamanho da tela);
##  2) reorganiza os quadros para a folha não passar de 4096 px de largura nem de altura;
##  3) salva a cópia em res://assets_otimizados/ (os originais em assets/ NÃO são mexidos)
##  4) atualiza a ficha (imagem, cw, ch, ax, ay, cols, escala).
## COMO USAR: rode DEPOIS do gerar_fichas.gd. Abra este arquivo e aperte Ctrl+Shift+X.
## Para voltar às imagens originais: rode o gerar_fichas.gd de novo.

const PASTA_FICHAS := "res://dados/personagens/"
const PASTA_SAIDA := "res://assets_otimizados/"
const QUALIDADE := 2.0        ## pixels da folha para cada pixel do jogo (2 = nítido até em celular Full HD)
const MINIMO := 0.85          ## só diminui se for ficar pelo menos 15% menor
const LIMITE := 4096          ## tamanho máximo seguro de uma imagem no celular

func _run() -> void:
	var dir := DirAccess.open(PASTA_FICHAS)
	if dir == null:
		push_error("Rode o gerar_fichas.gd primeiro.")
		return
	var fichas: Array[PersonagemDados] = []
	for arq in dir.get_files():
		if arq.ends_with(".tres"):
			var p := load(PASTA_FICHAS + arq) as PersonagemDados
			if p:
				fichas.append(p)
	var antes_mb := 0.0
	var depois_mb := 0.0
	var pendentes: Array = []            # [ficha, nome_anim, caminho_novo, novos_numeros]
	var feitos: Dictionary = {}          # caminho_novo -> true (a mesma folha usada por 2 personagens só é feita uma vez)
	for p in fichas:
		for nome in p.anims:
			var a: AnimDados = p.anims[nome]
			if a.textura == null:
				continue
			var r := _otimizar(p, nome, a, feitos)
			if r.is_empty():
				continue
			antes_mb += r.antes_mb
			depois_mb += r.depois_mb
			pendentes.append([p, nome, r])
	if pendentes.is_empty():
		print("OTIMIZAR FOLHAS: nada para fazer, todas as folhas já estão leves.")
		return
	# importa as imagens novas antes de ligar nas fichas
	var fs := EditorInterface.get_resource_filesystem()
	var caminhos := PackedStringArray()
	for k in feitos:
		caminhos.append(k)
	if not caminhos.is_empty():
		fs.scan()
		fs.reimport_files(caminhos)
	var faltam := 0
	for item in pendentes:
		var r: Dictionary = item[2]
		if not ResourceLoader.exists(r.caminho):
			faltam += 1
			continue
		var p: PersonagemDados = item[0]
		var a: AnimDados = p.anims[item[1]]
		a.textura = load(r.caminho)
		a.cols = r.cols; a.cw = r.cw; a.ch = r.ch; a.ax = r.ax; a.ay = r.ay; a.escala = r.escala
	if faltam > 0:
		print("O Godot ainda está importando %d imagens novas. ESPERE a barra de importação terminar e RODE ESTE SCRIPT MAIS UMA VEZ." % faltam)
	for p in fichas:
		ResourceSaver.save(p, p.resource_path)
	print("=== OTIMIZAR FOLHAS: %d animações otimizadas ===" % pendentes.size())
	print("Memória de vídeo dessas folhas: %.0f MB  ->  %.0f MB" % [antes_mb, depois_mb])

func _otimizar(p: PersonagemDados, nome: String, a: AnimDados, feitos: Dictionary) -> Dictionary:
	var src := a.textura.resource_path
	var na_tela := p.escala * a.escala                 # quanto a folha é encolhida no jogo
	var fator := na_tela * QUALIDADE
	if fator >= MINIMO:
		fator = 1.0                                     # já está no tamanho certo: só reorganiza se passar do limite
	var ncw := maxi(1, ceili(a.cw * fator))
	var nch := maxi(1, ceili(a.ch * fator))
	var ncols := clampi(int(LIMITE / ncw), 1, a.quadros)
	ncols = mini(ncols, maxi(a.cols, ceili(sqrt(float(a.quadros) * nch / ncw))))   # folha mais "quadrada"
	var nrows := ceili(float(a.quadros) / ncols)
	var w_atual := a.textura.get_width()
	var h_atual := a.textura.get_height()
	var precisa := fator < 1.0 or w_atual > LIMITE or h_atual > LIMITE
	if not precisa:
		return {}
	if nrows * nch > LIMITE:
		push_warning("%s / %s: mesmo otimizada a folha fica com %d px de altura. Diminua os quadros." % [p.id, nome, nrows * nch])
	var caminho := PASTA_SAIDA + src.trim_prefix("res://assets/").get_basename() + "_%dx%d.png" % [ncw, nch]
	var res := {"caminho": caminho, "cols": ncols, "cw": ncw, "ch": nch,
		"ax": a.ax * fator, "ay": a.ay * fator, "escala": a.escala / fator,
		"antes_mb": w_atual * h_atual * 4 / 1048576.0, "depois_mb": ncols * ncw * nrows * nch * 4 / 1048576.0}
	if feitos.has(caminho):
		return res
	var img := Image.load_from_file(ProjectSettings.globalize_path(src))
	if img == null or img.is_empty():
		push_warning("%s / %s: não consegui abrir %s" % [p.id, nome, src])
		return {}
	img.convert(Image.FORMAT_RGBA8)
	var saida := Image.create_empty(ncols * ncw, nrows * nch, false, Image.FORMAT_RGBA8)
	for q in a.quadros:
		var ret := Rect2i((q % a.cols) * a.cw, (q / a.cols) * a.ch, a.cw, a.ch)
		ret = ret.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		if ret.size.x <= 0 or ret.size.y <= 0:
			continue
		var quadro := img.get_region(ret)
		if fator < 1.0:
			quadro.resize(maxi(1, roundi(ret.size.x * fator)), maxi(1, roundi(ret.size.y * fator)), Image.INTERPOLATE_LANCZOS)
		saida.blit_rect(quadro, Rect2i(Vector2i.ZERO, quadro.get_size()), Vector2i((q % ncols) * ncw, (q / ncols) * nch))
	DirAccess.make_dir_recursive_absolute(caminho.get_base_dir())
	saida.save_png(caminho)
	feitos[caminho] = true
	print("  %s / %s: %dx%d -> %dx%d" % [p.id, nome, w_atual, h_atual, saida.get_width(), saida.get_height()])
	return res
