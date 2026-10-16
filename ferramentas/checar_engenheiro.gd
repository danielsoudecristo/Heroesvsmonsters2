extends SceneTree
## CHECA a ficha do Engenheiro: folhas, números e escala (sem precisar abrir a arena).
## RODAR: godot --headless --path "<pasta do projeto>" --script res://ferramentas/checar_engenheiro.gd

const CAMINHO := "res://dados/personagens/engenheiro.tres"

func _initialize() -> void:
	var p: PersonagemDados = load(CAMINHO)
	if p == null:
		push_error("não carregou " + CAMINHO)
		quit(1)
		return
	print("FICHA: id=%s nome=%s par=%s comportamento=%s custo=%d recarga=%.1f" % [
		p.id, p.nome, p.par, p.comportamento, p.custo, p.recarga])
	print("  vida=%d dano=%d intervalo=%.2f  escala=%.5f" % [p.vida, p.dano, p.intervalo_ataque, p.escala])
	var erro := false
	for nome in p.anims:
		var a: AnimDados = p.anims[nome]
		if a == null or a.textura == null:
			print("  !! anim '%s' sem folha" % nome)
			erro = true
			continue
		var img: Image = a.textura.get_image()
		var linhas := a.linhas()
		var w_esp := a.cols * a.cw
		var h_esp := linhas * a.ch
		var tam := "%dx%d" % [img.get_width(), img.get_height()]
		var ok_tam := img.get_width() == w_esp and img.get_height() == h_esp
		print("  anim %-8s: %d quadros %dx%d cols=%d ax=%.0f ay=%.0f fps=%.1f escala=%.3f TOTAL=%.3f dur=%.2fs repetir=%s" % [
			nome, a.quadros, a.cw, a.ch, a.cols, a.ax, a.ay, a.fps, a.escala, p.escala * a.escala,
			a.duracao(), str(a.repetir)])
		print("            folha %s (esperado %dx%d) %s  r0=%s  rLast=%s" % [
			tam, w_esp, h_esp, "ok" if ok_tam else "!! FOLHA NÃO COMBINA", a.retangulo(0), a.retangulo(a.quadros - 1)])
		if not ok_tam:
			erro = true
		if p.escala * a.escala < 0.425:
			print("            !! TOTAL %.3f < 0.425: o otimizar_folhas.gd vai encolher de novo" % (p.escala * a.escala))
			erro = true
		if a.ax < 0.0 or a.ax > a.cw or a.ay < 0.0 or a.ay > a.ch:
			print("    !! ponto dos pés fora do quadro")
			erro = true
		for q in a.quadros_acao:
			if q < 0 or q >= a.quadros:
				print("    !! quadro_acao %d fora do intervalo" % q)
				erro = true
	var fl: Dictionary = p.extra.get("flecha", {})
	print("  extra.flecha: %s" % [fl])
	print("  sons: %s  volumes: %s" % [p.sons, p.volumes])
	var retr := p.anim_qualquer(["parado", "defender", "andar"])
	print("  retrato sai de: %s (quadro_retrato=%s)" % [
		("%d quadros" % retr.quadros) if retr else "NADA", str(p.extra.get("quadro_retrato", 0))])
	print("")
	print("RESULTADO: %s" % ("REVISAR" if erro else "ok"))
	quit(1 if erro else 0)
