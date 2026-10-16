extends Node
## TESTE do Engenheiro Arcano na ARENA DE VERDADE: para quando não tem inimigo, atira quando tem
## esqueleto na linha, o raio "energia" acerta, e toca a animação de morte ao morrer.
## RODAR: godot --headless --path "<pasta>" res://ferramentas/teste_engenheiro.tscn

var falhas := 0
var arena: Node
var h: Unidade
var m: Unidade
var viu_energia := false
var pos_na_saida := Vector2.ZERO
var t_disparo := 0.0
var tutorial_antes := false

func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	# NUNCA grava no save do jogador: lê o perfil de verdade e só liga o tutorial em MEMÓRIA
	# (Perfil.carregar() marca _lido, então a arena não relê o arquivo por cima).
	Perfil.carregar()
	tutorial_antes = Perfil.tutorial_jogo
	Perfil.tutorial_jogo = true                 # a arena não abre a batalha guiada
	var cena: PackedScene = load("res://cenas/campanha.tscn")
	var arena_no: Node = cena.instantiate()
	add_child(arena_no)
	arena = arena_no
	await get_tree().process_frame
	await get_tree().process_frame
	if arena.selecao != null and arena.selecao.visible:   # nova janela de cartas: confirma com as liberadas
		var escolhidas: Array[PersonagemDados] = []
		for p in arena.cartas_todas:
			if Perfil.personagem_liberado(p):
				escolhidas.append(p)
		arena.selecao.fechar()
		arena._cartas_escolhidas(escolhidas)
		await get_tree().process_frame
	arena.segurar = true                        # congela as ondas: o teste coloca os lutadores
	h = arena.criar_unidade("engenheiro", arena.lado_jogador, 2, 4, 1)
	_teste("colocou o engenheiro", h != null and h.estado == "parado",
		"estado inicial %s em (%.0f, %.0f)" % [h.estado if h else "?", h.position.x if h else 0, h.position.y if h else 0])

	# 1) sem inimigo na linha ele fica parado
	await _seg(0.6)
	_teste("sem inimigo fica parado", h.estado == "parado", "estado %s" % h.estado)

	# 2) entra o esqueleto na linha: tem de virar "atacar" e soltar o raio
	m = arena.criar_unidade("esqueleto", arena.lado_inimigo, 2, -1, 1)
	var vida0: float = m.vida
	var t0 := 0.0
	while t0 < 4.0 and not viu_energia:
		await get_tree().physics_frame
		t0 += 1.0 / 60.0
		for pr in arena.projeteis:
			if pr.ativo and pr.tipo == "energia":
				if not viu_energia:
					pos_na_saida = pr.pos
					t_disparo = h.t               # instante da animação em que o laser saiu
				viu_energia = true
	_teste("com inimigo na linha atira", h.estado == "atacar" or h.estado == "guarda" or viu_energia,
		"estado %s · raio visto: %s" % [h.estado, str(viu_energia)])
	_teste("o projétile é o 'energia' saindo da boca do canhão", viu_energia and absf(pos_na_saida.x - (h.position.x + 95.0)) < 24.0
		and absf(pos_na_saida.y - (h.position.y - 113.0)) < 24.0,
		"saiu em (%.0f, %.0f), esperado perto de (%.0f, %.0f)" % [pos_na_saida.x, pos_na_saida.y, h.position.x + 95.0, h.position.y - 113.0])
	_teste("sai no quadro do clarão (t≈0.07s)", t_disparo > 0.03 and t_disparo < 0.16,
		"disparou em t=%.3fs da anim" % t_disparo)

	# 3) o raio desce do cano até a cabeça, acerta e tira vida (com flash de impacto na cabeça)
	var y_voo := pos_na_saida.y
	var viu_impacto := false
	var pos_impacto := Vector2.ZERO
	t0 = 0.0
	while t0 < 3.0 and m.vida >= vida0:
		await get_tree().physics_frame
		t0 += 1.0 / 60.0
		for pr in arena.projeteis:
			if pr.ativo and pr.tipo == "energia":
				y_voo = pr.pos.y
		for im in arena.impactos:
			if not viu_impacto:
				pos_impacto = im.pos
				viu_impacto = true
	_teste("o raio acerta o esqueleto", m.vida < vida0, "vida %.0f -> %.0f" % [vida0, m.vida])
	_teste("o laser desce do cano até a cabeça", y_voo - pos_na_saida.y > 5.0,
		"desceu %.0f px (cano -113 -> cabeça -86)" % (y_voo - pos_na_saida.y))
	_teste("flash de impacto na cabeça do alvo", viu_impacto and absf(pos_impacto.y - m.posicao_cabeca().y) < 24.0,
		"impacto em (%.0f, %.0f), cabeça em (%.0f, %.0f)" % [pos_impacto.x, pos_impacto.y, m.position.x, m.posicao_cabeca().y])

	# 4) sem inimigo de pé ele volta a ficar parado
	m.morrer()
	t0 = 0.0
	while t0 < 3.0 and h.estado != "parado":
		await get_tree().physics_frame
		t0 += 1.0 / 60.0
	_teste("sem inimigo volta a ficar parado", h.estado == "parado", "estado %s depois de %.1fs" % [h.estado, t0])

	# 5) morrer COM folha de morte: toca a animação "morrer" e some depois
	h.morrer()
	await get_tree().physics_frame
	var estado_morte: String = h.estado
	var anim_morrer: bool = h.anim != null and h.anim.repetir == false  # toca uma vez
	var ficou: bool = not h.livre          # continuou ali depois de levar o golpe
	await _seg(1.5)
	var ainda: bool = is_instance_valid(h) and not h.livre
	await _seg(3.0)                         # anim ~3s + caido 0.8s = ~3.8s
	var sumiu: bool = not is_instance_valid(h) or h.livre
	_teste("morte com arte: toca animação 'morrer'", estado_morte == "morrer" and anim_morrer,
		"estado %s · anim repetir=%s" % [estado_morte, str(anim_morrer)])
	_teste("morte com arte: some depois da anim", ficou and ainda and sumiu,
		"continuou ali: %s · depois sumiu: %s" % [str(ficou), str(sumiu)])

	print("")
	print("RESULTADO: %s (%d falhas)" % ["ok" if falhas == 0 else "REVISAR", falhas])
	Perfil.tutorial_jogo = tutorial_antes       # devolve só em memória (o teste não grava nada no save)
	get_tree().quit(1 if falhas > 0 else 0)

func _seg(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _teste(nome: String, ok: bool, detalhe := "") -> void:
	if not ok:
		falhas += 1
	print("  %-46s %s  %s" % [nome, "ok " if ok else "!! ", detalhe])
