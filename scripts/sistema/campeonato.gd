class_name Campeonato
extends RefCounted
## CAMPEONATO PvP: 16 vagas (8 Heroes + 8 Monsters) em mata-mata: Oitavas -> Quartas -> Semifinal -> Final.
## TODA LUTA É HEROES x MONSTERS (no jogo não existe Heroes contra Heroes). Para isso valer em todas as fases,
## o chaveamento é montado assim: nas oitavas as vagas pares são Heroes e as ímpares Monsters; e em cada par
## de lutas que se encontram na fase seguinte, uma é vencida por um Heroes e a outra por um Monsters. A luta
## do jogador é de verdade (PvP contra o bot); as outras são simuladas respeitando essa regra — e assim a
## FINAL é sempre o melhor Heroes contra o melhor Monsters.
## Não existe "dificuldade" por fase: quem joga são PESSOAS (Heroes contra Monsters) — com 8 de cada lado não
## sobra vaga para bot. O bot só completa as vagas que faltam, num nível fixo de jogador comum (BOT_NIVEL).
## Hoje as outras 15 vagas são bots (cada um com o retrato de um personagem do lado dele). A estrutura já
## guarda "tipo" e "foto_url" por vaga para receber pessoas reais quando a fila online do campeonato existir.

const ARQUIVO := "user://campeonato.cfg"
const FASES := ["OITAVAS DE FINAL", "QUARTAS DE FINAL", "SEMIFINAL", "FINAL"]
const FASES_CURTO := ["Oitavas", "Quartas", "Semifinal", "Final"]
const BOT_NIVEL := 7                             ## nível do bot do PvP (1..15) quando uma vaga é de bot
const COR_FASE := [Color("4a7bd8"), Color("8a5cd6"), Color("d0453a"), Color("e0a52a")]   ## só a cor de cada fase
const PREMIO := [40, 70, 110, 300]               ## moedas por vencer cada fase (a final = campeão)

## vagas[i] = {nome, lado, tipo ("voce"/"bot"/"pessoa"), personagem (retrato do bot), foto_url}
static var vagas: Array = []
## vencedores[f][m] = índice da vaga que venceu a luta m da fase f (-1 = ainda não jogou)
static var vencedores: Array = []
static var fase := 0                             ## fase atual (0..3); 4 = acabou
static var voce := -1                            ## vaga do jogador
static var ativo := false
static var em_partida := false                   ## a cena do PvP está jogando a luta do campeonato
static var ultimo := ""                          ## texto do resultado da última luta (a árvore mostra ao voltar)

# ---- ONLINE (com conta): o servidor é quem manda (supabase/26_campeonato.sql) ----
static var online := false
static var status := ""                          ## "aberto" (sala de espera), "andando", "fim"
static var falta := 0                            ## (aberto) segundos até começar
static var prazo := 0                            ## (andando) segundos até a fase fechar
static var inscritos: Array = []                 ## (aberto) quem já entrou: {nome, foto, lado, eu}
static var lutas: Array = []                     ## lutas[f][m] = {sala?, relato?}

## Chegou o estado do servidor: vira o mesmo formato do campeonato local (a árvore desenha igual).
static func de_servidor(d: Dictionary) -> void:
	online = true
	status = str(d.get("status", ""))
	falta = int(d.get("falta", 0))
	prazo = int(d.get("prazo", 0))
	inscritos = d.get("inscritos", []) if d.get("inscritos") is Array else []
	ativo = true
	var meu := str((Engine.get_main_loop() as SceneTree).root.get_node("Conta").meu_id())
	var vs = d.get("vagas", [])
	vagas.clear()
	voce = -1
	if vs is Array:
		for i in vs.size():
			var v: Dictionary = vs[i]
			var j := str(v.get("jogador", "")) if v.get("jogador") != null else ""
			var tipo := str(v.get("tipo", "bot"))
			if j != "" and j == meu:
				tipo = "voce"
				voce = i
			vagas.append({"nome": str(v.get("nome", "?")), "lado": str(v.get("lado", "heroes")), "tipo": tipo,
				"personagem": str(v.get("personagem", "")), "foto_url": str(v.get("foto", "")) if v.get("foto") != null else ""})
	var ve = d.get("vencedores")
	vencedores = []
	if ve is Array:
		for fase_v in ve:
			vencedores.append(fase_v.map(func(x): return int(x)))
	else:
		vencedores = [[-1, -1, -1, -1, -1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1], [-1]]
	var lu = d.get("lutas")
	lutas = lu if lu is Array else []
	fase = int(d.get("fase", 0))

## (online) Minha luta desta fase já tem resultado (ou já mandei o meu): esperando as outras.
static func esperando_outras() -> bool:
	var m := minha_luta()
	if m < 0:
		return false
	if int(vencedores[fase][m]) >= 0:
		return true
	if online and fase < lutas.size() and m < lutas[fase].size():
		var l = lutas[fase][m]
		return l is Dictionary and l.has("relato")
	return false

## O adversário da minha luta é uma pessoa de verdade?
static func adversario_pessoa() -> bool:
	var a := adversario()
	return a >= 0 and str(vagas[a].tipo) == "pessoa"
static var _lido := false

# ------------------------------------------------------------------ começo
## nomes (opcional): quem estava na sala de entrada, por lado: {"heroes": [{nome, personagem}], "monsters": [...]}
static func novo(lado: String, nomes_sala := {}) -> void:
	carregar()
	online = false
	status = ""
	vagas.clear()
	var cat: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Catalogo")
	var herois: Array = cat.do_lado("heroes").map(func(p): return p.id)
	var monstros: Array = cat.do_lado("monsters").map(func(p): return p.id)
	herois.shuffle()
	monstros.shuffle()
	var nomes := {}
	for i in 16:
		var l := "heroes" if i % 2 == 0 else "monsters"
		var lista: Array = herois if l == "heroes" else monstros
		var nome := ConfigPvp.nome_adversario()
		var pers: String = lista[(i / 2) % lista.size()]
		var da_sala: Array = nomes_sala.get(l, [])
		if not da_sala.is_empty() and not nomes.has(str(da_sala[0].nome)):   # quem estava na sala ganha a vaga
			var g: Dictionary = da_sala.pop_front()
			nome = str(g.nome)
			if str(g.get("personagem", "")) != "":
				pers = str(g.personagem)
		while nomes.has(nome):
			nome = ConfigPvp.nome_adversario()
		nomes[nome] = true
		vagas.append({"nome": nome, "lado": l, "tipo": "bot", "personagem": pers, "foto_url": ""})
	# o jogador numa vaga do lado dele (sorteada)
	var minhas: Array = []
	for i in 16:
		if vagas[i].lado == lado:
			minhas.append(i)
	voce = minhas[randi() % minhas.size()]
	vagas[voce].tipo = "voce"
	vagas[voce].nome = Perfil.nome if Perfil.nome != "" else "Você"
	vencedores = [[-1, -1, -1, -1, -1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1], [-1]]
	fase = 0
	ativo = true
	salvar()

# ------------------------------------------------------------------ chaveamento
## As duas vagas da luta m da fase f (na fase 0 são vagas fixas; depois, os vencedores de baixo).
static func lutadores(f: int, m: int) -> Array:
	if f == 0:
		return [m * 2, m * 2 + 1]
	return [vencedores[f - 1][m * 2], vencedores[f - 1][m * 2 + 1]]

## Luta do jogador na fase atual (-1 = eliminado ou acabou).
static func minha_luta() -> int:
	if fase > 3 or voce < 0 or vencedores.size() < 4 or vagas.size() < 16:
		return -1
	for m in vencedores[fase].size():
		if voce in lutadores(fase, m):
			return m
	return -1

static func eliminado() -> bool:
	if online and status == "aberto":
		return false
	return ativo and voce >= 0 and fase <= 3 and minha_luta() < 0

static func campeao() -> int:
	return vencedores[3][0] if vencedores.size() == 4 else -1

## Adversário do jogador na fase atual (índice da vaga, -1 se não houver).
static func adversario() -> int:
	var m := minha_luta()
	if m < 0:
		return -1
	var l := lutadores(fase, m)
	return l[1] if l[0] == voce else l[0]

# ------------------------------------------------------------------ resultados
## O jogador terminou a luta: registra e simula o resto da fase (respeitando Heroes x Monsters).
## Devolve as moedas ganhas.
static func registrar(venceu: bool) -> int:
	em_partida = false
	if online:                                       # online: o servidor anota (e paga quando a fase fecha)
		var c: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Conta")
		c.chamar("campeonato_relatar_bot", {"p_venceu": venceu})
		var nas_o: String = ["nas Oitavas", "nas Quartas", "na Semifinal", "na Final"][clampi(fase, 0, 3)]
		ultimo = ("Você venceu %s! Esperando as outras lutas..." % nas_o) if venceu else ("Você foi eliminado %s." % nas_o)
		return PREMIO[clampi(fase, 0, 3)] if venceu else 0
	var m := minha_luta()
	if m < 0:
		return 0
	var adv := adversario()
	var fase_jogada := fase
	vencedores[fase][m] = voce if venceu else adv
	var ganho := 0
	if venceu:
		ganho = PREMIO[fase]
	_completar_fase()
	fase += 1
	# eliminado: o campeonato segue sozinho até o fim (para mostrar o campeão)
	while eliminado() and fase <= 3:
		_completar_fase()
		fase += 1
	var nas: String = ["nas Oitavas", "nas Quartas", "na Semifinal", "na Final"][fase_jogada]
	if venceu and fase_jogada == 3:
		ultimo = "VOCÊ É O CAMPEÃO! +%d moedas" % ganho
	elif venceu:
		ultimo = "Você venceu %s! +%d moedas · Próxima: %s" % [nas, ganho, FASES_CURTO[fase_jogada + 1]]
	else:
		ultimo = "Você foi eliminado %s. Veja quem foi o campeão!" % nas
	salvar()
	return ganho

## Simula as lutas que faltam na fase atual. Em cada par de lutas que se encontram na próxima fase,
## uma fica com um Heroes e a outra com um Monsters (assim a próxima luta também é Heroes x Monsters).
static func _completar_fase() -> void:
	var lutas: Array = vencedores[fase]
	if lutas.size() == 1:                                      # final: 50% / 50%
		if lutas[0] < 0:
			var l := lutadores(fase, 0)
			lutas[0] = l[randi() % 2]
		return
	for j in range(0, lutas.size(), 2):
		var a := j; var b := j + 1
		var lado_a := ""
		if lutas[a] >= 0:
			lado_a = vagas[lutas[a]].lado
		elif lutas[b] >= 0:
			lado_a = "monsters" if vagas[lutas[b]].lado == "heroes" else "heroes"
		else:
			lado_a = "heroes" if randf() < 0.5 else "monsters"
		var lado_b := "monsters" if lado_a == "heroes" else "heroes"
		if lutas[a] < 0:
			lutas[a] = _quem_do_lado(lutadores(fase, a), lado_a)
		if lutas[b] < 0:
			lutas[b] = _quem_do_lado(lutadores(fase, b), lado_b)

static func _quem_do_lado(par: Array, lado: String) -> int:
	return par[0] if vagas[par[0]].lado == lado else par[1]

## Saiu da luta no meio (ou fechou o jogo): conta como derrota.
static func desistiu() -> void:
	if em_partida:
		em_partida = false
		if online and adversario_pessoa():           # online contra pessoa: o W.O. já vai pela partida online
			return
		registrar(false)

# ------------------------------------------------------------------ salvar
static func carregar() -> void:
	if _lido:
		return
	_lido = true
	var cf := ConfigFile.new()
	if cf.load(ARQUIVO) != OK:
		return
	vagas = cf.get_value("c", "vagas", [])
	vencedores = cf.get_value("c", "vencedores", [])
	fase = cf.get_value("c", "fase", 0)
	voce = cf.get_value("c", "voce", -1)
	ativo = cf.get_value("c", "ativo", false) and vagas.size() == 16 and vencedores.size() == 4
	if cf.get_value("c", "em_partida", false):       # fechou o jogo no meio da luta: derrota
		em_partida = true
		desistiu()

static func salvar() -> void:
	if online:                                       # online: quem guarda é o servidor
		return
	var cf := ConfigFile.new()
	cf.set_value("c", "vagas", vagas)
	cf.set_value("c", "vencedores", vencedores)
	cf.set_value("c", "fase", fase)
	cf.set_value("c", "voce", voce)
	cf.set_value("c", "ativo", ativo)
	cf.set_value("c", "em_partida", em_partida)
	cf.save(ARQUIVO)
