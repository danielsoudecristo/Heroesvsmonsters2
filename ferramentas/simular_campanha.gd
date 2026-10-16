extends SceneTree
## SIMULADOR DA CAMPANHA: um robô joga os níveis sozinho (sem desenhar, o mais rápido possível) e diz
## até onde chega em cada dificuldade com as cartas num certo nível. Serve para acertar o EQUILÍBRIO
## (curva de força, energia, prêmios) com números de verdade em vez de chute.
##
## O robô joga como uma pessoa razoável: pega a energia do céu/Elara, põe Elaras no começo, defende a
## linha mais ameaçada com a carta de melhor custo-benefício (preferindo quem é forte contra os inimigos
## daquela linha), atiradores atrás e tanques na frente. Uma pessoa boa vai um pouco mais longe.
##
## NÃO MEXE NO SEU JOGO: usa outro perfil (user://perfil_sim.cfg). Para não falar com o servidor, rode com
## a variável HVM_SUPABASE apontando para um endereço morto (o comando abaixo já faz isso).
## RODAR (PowerShell):
##   $env:HVM_SUPABASE="http://127.0.0.1:9"; godot --headless --fixed-fps 60 --path . --script res://ferramentas/simular_campanha.gd -- dif=medio cartas=5 de=1 ate=40
## Argumentos: dif (facil/medio/dificil/hardcore), cartas (nível das cartas 1-15), de / ate (níveis),
##   para=N (para depois de N derrotas seguidas; padrão 2), vezes=N (joga cada nível N vezes; padrão 1)

const REACAO := 0.5                   ## segundos até o robô pegar a energia que caiu
const PENSA_CADA := 0.25              ## de quanto em quanto tempo ele decide
const TEMPO_MAX := 420.0              ## segundos de jogo por nível (segurança)
## Força aproximada de cada carta (dano por segundo e "corpo" para segurar) — só para o robô escolher.
const DPS := {"nick": 25.0, "arqueiro": 19.0, "mago": 30.0, "magoFogo": 35.0, "engenheiro": 40.0, "protetor": 8.0, "sentinela": 30.0, "elara": 0.0}
const CORPO := {"nick": 340.0, "arqueiro": 0.0, "mago": 0.0, "magoFogo": 0.0, "engenheiro": 0.0, "protetor": 1400.0, "sentinela": 5000.0, "elara": 0.0}
const TANQUES := ["protetor", "nick", "sentinela"]

var arena
var args := {}
var nivel := 1
var ate := 40
var vezes := 1
var vez := 0
var derrotas_seguidas := 0
var para_em := 2
var t_nivel := 0.0
var t_pensa := 0.0
var resultados: Array = []
var vitorias_nivel := 0
var colocados := {}                     ## id -> quantas vezes o robô colocou neste nível
var fotos := ""                         ## pasta para salvar uma foto a cada 15 s (só sem --headless)
var t_foto := 0.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var dif: String = args.get("dif", "medio")
	var nv_cartas := int(args.get("cartas", "1"))
	nivel = int(args.get("de", "1"))
	ate = int(args.get("ate", "40"))
	para_em = int(args.get("para", "2"))
	vezes = int(args.get("vezes", "1"))
	fotos = args.get("fotos", "")
	Perfil.ARQUIVO = "user://perfil_sim.cfg"
	Perfil.carregar()
	Perfil.dificuldade = dif
	Perfil.recordes = {"heroes": {}, "monsters": {}}   # sem recorde: começa onde mandar (não no marco)
	Perfil.lado = "heroes"
	Perfil.tutorial_jogo = true
	Perfil.trofeus = 99999
	for p in root.get_node("Catalogo").do_lado("heroes"):
		Perfil.niveis[p.id] = nv_cartas
	arena = load("res://cenas/campanha.tscn").instantiate()
	arena.nivel_inicial = nivel
	arena.nivel_herois = nv_cartas
	arena.mostrar_fps = false
	root.add_child(arena)
	await process_frame
	if fotos == "":                                  # sem fotos: nem desenha (mais rápido)
		arena.desenho.visible = false
		arena.ui.visible = false
	arena.selecao.visible = false
	arena.selecao.inicios = []
	arena.selecao.inicio = nivel
	arena._cartas_escolhidas(_baralho())
	print("SIM dif=%s cartas=%d" % [dif, nv_cartas])

## 7 cartas: Elara + as que são fortes contra os inimigos dos próximos níveis + as de base.
func _baralho() -> Array:
	var todas := {}
	for p in arena.cartas_todas:
		todas[p.id] = p
	var ordem := ["elara", "arqueiro", "protetor", "mago", "magoFogo", "engenheiro", "nick", "sentinela"]
	var deck: Array = []
	for id in ordem:
		if todas.has(id) and deck.size() < 7:
			deck.append(todas[id])
	return deck

func _process(dt: float) -> bool:
	if arena == null or arena.cartas_dados.is_empty():
		return false
	t_nivel += dt
	t_pensa -= dt
	if fotos != "" and t_nivel - t_foto >= 15.0:
		t_foto = t_nivel
		root.get_texture().get_image().save_png("%s/sim_n%d_%03d.png" % [fotos, nivel, int(t_nivel)])
		var info := []
		for o in arena.orbes:
			info.append("t%.1f v%s y%.0f/%.0f" % [o.t, o.voa, o.pos.y, o.alvo_y])
		print("  t=%.0f energia=%d orbes=%s" % [t_nivel, arena.energia, str(info)])
	if t_pensa <= 0.0:
		t_pensa = PENSA_CADA
		_pegar_energia()
		if arena.estado in ["preparo", "onda", "pausa"]:
			_jogar()
	if arena.estado == "fim_nivel" or arena.estado == "derrota" or t_nivel > TEMPO_MAX:
		var venceu: bool = arena.estado == "fim_nivel"
		print("NIVEL %d %s castelo=%d tempo=%.0f mods=%s tema=%s invasores=%s cartas=%s vivos=%d" % [nivel, "VENCEU" if venceu else "PERDEU",
			int(maxf(arena.vida_castelo, 0.0)), t_nivel, str(arena.mods), arena.fase.get("tema", ""),
			str(arena.invasores), str(colocados), arena._monstros_vivos()])
		colocados = {}
		t_foto = 0.0
		if t_nivel > TEMPO_MAX:
			for r in arena.C.G.rows:
				for m in arena.monstros[r]:
					var hs: Array = arena.herois[r].map(func(h): return h.p.id)
					print("   TRAVOU: %s linha %d x=%.0f estado=%s morto=%s | heróis da linha: %s" % [m.p.id, r, m.position.x, m.estado, m.morto, str(hs)])
		vez += 1
		if venceu:
			vitorias_nivel += 1
		if vez < vezes:
			_comecar(nivel)
			return false
		var ganhou := vitorias_nivel * 2 > vezes or (vezes == 1 and venceu)
		resultados.append([nivel, vitorias_nivel, vezes])
		print("RESUMO nivel=%d vitorias=%d/%d %s" % [nivel, vitorias_nivel, vezes, "PASSOU" if ganhou else "BARROU"])
		vez = 0
		vitorias_nivel = 0
		derrotas_seguidas = 0 if ganhou else derrotas_seguidas + 1
		if derrotas_seguidas >= para_em or nivel >= ate:
			var chegou := 0
			for r in resultados:
				if r[1] * 2 > r[2] or (r[2] == 1 and r[1] == 1):
					chegou = r[0]
				else:
					break
			print("FIM dif=%s cartas=%s chegou=%d" % [Perfil.dificuldade, args.get("cartas", "1"), chegou])
			return true
		_comecar(nivel + 1)
	return false

func _comecar(n: int) -> void:
	nivel = n
	t_nivel = 0.0
	arena.segurar = false
	arena.comecar_nivel(n, true)

func _pegar_energia() -> void:
	for o in arena.orbes:
		if not o.voa and float(o.t) > REACAO:
			o.voa = true

# ------------------------------------------------------------------ decisão
func _jogar() -> void:
	var C = arena.C
	var cartas: Array = arena.cartas_dados
	# 1) Elaras primeiro (energia de longo prazo), na coluna de trás
	var elaras := _conta("elara")
	var quer_elaras := 2 if arena.nivel < 3 else (4 if arena.noite else 3)
	var i_elara := _indice("elara")
	var em_perigo := _linha_em_perigo()
	if i_elara >= 0 and elaras < quer_elaras and arena.energia >= 50 and _pronta("elara") and em_perigo < 0:
		for r in [2, 1, 3, 0, 4]:
			if arena.casas[0][r] == null:
				_colocar(i_elara, Vector2i(0, r))
				return
	# 2) plano por linha: 1 atirador em cada; tanque na frente onde vem corpo a corpo; depois reforço
	var atiradores_quer := clampi(1 + int(arena.nivel / 6.0), 1, 3)
	var melhor_linha := -1
	var melhor_papel := ""
	var maior := -INF
	for r in C.G.rows:
		var s := 0
		var t := 0
		for h in arena.herois[r]:
			if h.morto or h.p.id == "elara":
				continue
			if h.p.id in TANQUES:
				t += 1
			else:
				s += 1
		var ameaca := 0.0
		var corpo := false
		for m in arena.monstros[r]:
			if m.morto:
				continue
			ameaca += m.vida * (1.0 + clampf((C.W - m.position.x) / 500.0, 0.0, 2.0))
			if m.p.comportamento in ["corpo_a_corpo", "escudo", "tita"]:
				corpo = true
		var forca: float = (float(s) * 600.0 + float(t) * 300.0) * Progressao.multiplicador(arena.nivel_da_carta("arqueiro"))
		var urgencia := ameaca / 100.0 - forca / 600.0
		var papel := ""
		var nota := 0.0
		if s == 0:
			papel = "atirador"; nota = 100.0 + urgencia
		elif corpo and t == 0:
			papel = "tanque"; nota = 60.0 + urgencia
		elif s < atiradores_quer:
			papel = "atirador"; nota = 30.0 + urgencia
		elif urgencia > 2.0:
			papel = "tanque" if (corpo and t == 0) else "atirador"; nota = urgencia   # já tem quem segure: mais dano
		if papel != "" and nota > maior:
			maior = nota; melhor_linha = r; melhor_papel = papel
	if melhor_linha < 0:
		return
	# 3) a melhor carta para o papel (custo-benefício x vantagem contra quem vem nesta linha/nível)
	var alvos: Array = []
	for m in arena.monstros[melhor_linha]:
		if not m.morto:
			alvos.append(m.p.id)
	if alvos.is_empty():                                   # linha vazia: pensa nos inimigos do nível
		for o in arena.fase.ondas:
			for k in o:
				alvos.append(C.LETRA_MONSTRO[k])
	var melhor := -1
	var melhor_nota := -INF
	for i in cartas.size():
		var p: PersonagemDados = cartas[i]
		if p.id == "elara" or not _pronta(p.id):
			continue
		var e_tanque: bool = p.id in TANQUES
		if (melhor_papel == "tanque") != e_tanque:
			continue
		var vant := 0.0
		for a in alvos:
			vant += C.vantagem(p.id, a)
		vant /= maxf(1.0, alvos.size())
		var valor: float = (float(CORPO.get(p.id, 0.0)) * 0.03 + float(DPS.get(p.id, 10.0))) if e_tanque else float(DPS.get(p.id, 10.0))
		var nota := valor * vant / pow(float(p.custo), 0.8)
		if nota > melhor_nota:
			melhor_nota = nota; melhor = i
	if melhor < 0:
		return
	var p_esc: PersonagemDados = cartas[melhor]
	if arena.energia < p_esc.custo:
		# sem energia para a melhor: se a linha está apertada, vai a mais barata do mesmo papel
		if maior < 50.0:
			return
		var barata := -1
		for i in cartas.size():
			var p: PersonagemDados = cartas[i]
			if p.id != "elara" and _pronta(p.id) and (p.id in TANQUES) == (melhor_papel == "tanque") and arena.energia >= p.custo:
				if barata < 0 or p.custo < cartas[barata].custo:
					barata = i
		if barata < 0:
			return
		melhor = barata
		p_esc = cartas[melhor]
	var col := _coluna(p_esc.id, melhor_linha)
	if col >= 0:
		_colocar(melhor, Vector2i(col, melhor_linha))

## Linha com inimigo já perto do castelo (-1 = nenhuma): aí não é hora de pôr Elara.
func _linha_em_perigo() -> int:
	for r in arena.C.G.rows:
		for m in arena.monstros[r]:
			if not m.morto and m.position.x < arena.C.cel_x(4):
				return r
	return -1

## Atirador: a casa livre mais atrás (1..5). Tanque: logo na frente do último herói da linha.
func _coluna(id: String, r: int) -> int:
	var C = arena.C
	var x_inimigo: float = C.W
	for m in arena.monstros[r]:
		if not m.morto:
			x_inimigo = minf(x_inimigo, m.position.x)
	if id in TANQUES:                                     # tanque na frente (colunas 5..3), deixando lugar para atiradores
		for c in [5, 4, 6, 3, 2]:
			if arena.casas[c][r] == null and C.cel_x(c) < x_inimigo - 70.0:
				return c
		return -1
	for c in range(1, 6):
		if arena.casas[c][r] == null and C.cel_x(c) < x_inimigo - 90.0:
			return c
	for c in range(0, 9):                                 # aperto: qualquer casa livre antes do inimigo
		if arena.casas[c][r] == null and C.cel_x(c) < x_inimigo - 50.0:
			return c
	return -1

func _colocar(i: int, casa: Vector2i) -> void:
	var antes: int = arena.energia
	arena.carta_sel = i
	arena.colocar_heroi(casa)
	arena.carta_sel = -1
	if arena.energia < antes:
		var id: String = arena.cartas_dados[i].id
		colocados[id] = int(colocados.get(id, 0)) + 1

func _pronta(id: String) -> bool:
	return float(arena.recarga.get(id, 0.0)) <= 0.0

func _indice(id: String) -> int:
	for i in arena.cartas_dados.size():
		if arena.cartas_dados[i].id == id:
			return i
	return -1

func _conta(id: String) -> int:
	var n := 0
	for r in arena.C.G.rows:
		for h in arena.herois[r]:
			if not h.morto and h.p.id == id:
				n += 1
	return n
