extends Node
## TESTE da janela de SELEÇÃO DE CARTAS: mínimo/máximo, carta bloqueada com símbolo da liga
## (alerta ao tocar), e a integração nas duas arenas (campanha e PvP bot).
## RODAR: godot --headless --path "<pasta>" res://ferramentas/teste_selecao.tscn

const SELECAO := preload("res://scripts/arena/selecao_cartas.gd")

var falhas := 0
var trofeus_antes := 0
var tutorial_antes := false
var recebidas: Array = []

func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	Perfil.carregar()
	trofeus_antes = Perfil.trofeus
	tutorial_antes = Perfil.tutorial_jogo
	Perfil.trofeus = 0                        # ninguém tem liga: o cartão bloqueado fica bloqueado (sem gravar nada)
	Perfil.tutorial_jogo = true               # não abre a batalha guiada (só em memória)

	_teste_janela()
	await _teste_campanha()
	await _teste_pvp()

	print("")
	print("RESULTADO: %s (%d falhas)" % ["ok" if falhas == 0 else "REVISAR", falhas])
	Perfil.trofeus = trofeus_antes            # devolve só em memória (o teste não grava nada no save)
	Perfil.tutorial_jogo = tutorial_antes
	get_tree().quit(1 if falhas > 0 else 0)

# ---------------------------------------------------------------- janela (cartas falsas)
func _carta(id: String, nome: String, custo: int, trofeus := 0) -> PersonagemDados:
	var p := PersonagemDados.new()
	p.id = id
	p.nome = nome
	p.custo = custo
	p.lado = "heroes"
	p.desbloqueio_trofeus = trofeus
	return p

func _teste_janela() -> void:
	var lista: Array[PersonagemDados] = []
	for i in 8:
		lista.append(_carta("c%d" % i, "Carta %d" % i, 100 + i * 50))
	var eng := _carta("engenheiro", "Engenheiro Arcano", 450, 400)   # desbloqueia na Prata (400 troféus)
	lista.append(eng)
	var sel: Control = SELECAO.new()
	recebidas = []
	sel.escolheu = func(escolhidas: Array) -> void: recebidas = escolhidas
	add_child(sel)
	sel.abrir(lista)
	_teste("janela abre com todas as cartas", sel.visible and sel.cartas.size() == 9,
		"visível %s, %d cartas" % [str(sel.visible), sel.cartas.size()])

	# 1) tocar na carta bloqueada NÃO seleciona e mostra o alerta da liga
	sel._tocar(sel._ret_carta(8).get_center())
	_teste("carta bloqueada não seleciona", sel.selecionadas.is_empty(), "%d selecionadas" % sel.selecionadas.size())
	_teste("alerta fala da liga Prata", "Prata" in sel._alerta and "400" in sel._alerta, sel._alerta)

	# 2) menos de 3 cartas: o botão Jogar! não confirma
	sel._tocar(sel._ret_carta(0).get_center())
	sel._tocar(sel._ret_carta(1).get_center())
	sel._tocar(sel._ret_jogar().get_center())
	_teste("com 2 cartas o Jogar! não confirma", sel.visible and recebidas.is_empty(), "alerta: %s" % sel._alerta)

	# 3) 3 cartas: confirma e devolve exatamente as escolhidas
	sel._tocar(sel._ret_carta(2).get_center())
	sel._tocar(sel._ret_jogar().get_center())
	_teste("com 3 cartas confirma", not sel.visible, "visível %s" % str(sel.visible))
	_teste("devolveu as 3 cartas certas", recebidas.size() == 3
		and recebidas[0].id == "c0" and recebidas[1].id == "c1" and recebidas[2].id == "c2",
		"ids %s" % str(recebidas.map(func(p): return p.id)))

	# 4) máximo de 7: a 8ª carta livre não entra
	recebidas = []
	sel.abrir(lista)
	for i in 7:
		sel._tocar(sel._ret_carta(i).get_center())
	sel._tocar(sel._ret_carta(7).get_center())           # a última livre
	_teste("máximo de 7 cartas", sel.selecionadas.size() == 7 and "Máximo" in sel._alerta,
		"%d selecionadas · %s" % [sel.selecionadas.size(), sel._alerta])
	# tirar uma e escolher outra
	sel._tocar(sel._ret_carta(0).get_center())           # desmarca a primeira
	sel._tocar(sel._ret_carta(7).get_center())           # agora a oit entra
	_teste("trocou a carta no limite", sel.selecionadas.size() == 7 and sel.selecionadas.has(lista[7]),
		"%d selecionadas" % sel.selecionadas.size())
	sel.queue_free()

# ---------------------------------------------------------------- campanha
func _teste_campanha() -> void:
	var cena: PackedScene = load("res://cenas/campanha.tscn")
	var arena: Node = cena.instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	_teste("campanha abre a janela de cartas", arena.selecao != null and arena.selecao.visible, "")
	_teste("campanha segura o jogo até confirmar", arena.segurar and arena.cartas_dados.is_empty()
		and arena.estado == "preparo", "segurar %s · %d cartas · estado %s" % [str(arena.segurar), arena.cartas_dados.size(), arena.estado])
	_teste("janela mostra as cartas TODAS (inclusive a bloqueada)", arena.cartas_todas.size() > arena.cartas_dados.size(),
		"todas %d" % arena.cartas_todas.size())
	var tem_bloqueada := false
	for p in arena.cartas_todas:
		if p.desbloqueio_trofeus > 0:
			tem_bloqueada = true
	_teste("tem carta com desbloqueio de liga na lista", tem_bloqueada, "")
	# confirma com as liberadas (igual ao jogador escolhendo)
	var escolhidas: Array[PersonagemDados] = []
	for p in arena.cartas_todas:
		if Perfil.personagem_liberado(p):
			escolhidas.append(p)
	arena.selecao.fechar()
	arena._cartas_escolhidas(escolhidas)
	await get_tree().process_frame
	_teste("campanha começa o nível depois de confirmar", not arena.segurar and arena.estado == "preparo"
		and arena.cartas_dados.size() == escolhidas.size() and arena.cartas_dados.size() >= 3,
		"%d cartas · estado %s" % [arena.cartas_dados.size(), arena.estado])
	var so_liberadas := true
	for p in arena.cartas_dados:
		if not Perfil.personagem_liberado(p):
			so_liberadas = false
	_teste("só cartas liberadas entram na barra", so_liberadas, "")
	arena.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------- pvp (contra o bot)
func _teste_pvp() -> void:
	Perfil.pvp_sala = {}
	Perfil.pvp_adversario = ""
	Perfil.pvp_modo = "normal"
	var cena: PackedScene = load("res://cenas/pvp.tscn")
	var arena: Node = cena.instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	_teste("pvp abre a janela de cartas", arena.selecao != null and arena.selecao.visible, "")
	_teste("pvp trava o passo até confirmar", arena.escolhendo and arena.cartas_dados.is_empty(),
		"escolhendo %s · %d cartas" % [str(arena.escolhendo), arena.cartas_dados.size()])
	_teste("pvp mostra as cartas TODAS na janela", arena.cartas_todas.size() > arena.cartas_dados.size(),
		"todas %d" % arena.cartas_todas.size())
	var escolhidas: Array[PersonagemDados] = []
	for p in arena.cartas_todas:
		if Perfil.personagem_liberado(p):
			escolhidas.append(p)
	arena.selecao.fechar()
	arena._cartas_escolhidas(escolhidas)
	await get_tree().process_frame
	_teste("pvp começa a partida depois de confirmar", not arena.escolhendo and arena.cartas_dados.size() == escolhidas.size()
		and arena.cartas_dados.size() >= 3 and arena.preparo > 0.0,
		"%d cartas · preparo %.1fs" % [arena.cartas_dados.size(), arena.preparo])
	arena.queue_free()
	await get_tree().process_frame

func _teste(nome: String, ok: bool, detalhe := "") -> void:
	if not ok:
		falhas += 1
	print("  %-52s %s  %s" % [nome, "ok " if ok else "!! ", detalhe])
