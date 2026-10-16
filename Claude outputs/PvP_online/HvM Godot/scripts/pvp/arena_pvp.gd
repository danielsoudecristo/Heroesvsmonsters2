extends Node2D
## BATALHA PvP (igual ao site): os heróis de um lado contra os monstros do outro.
## Contra o BOT (com nome de gente quando a busca não acha ninguém) ou ONLINE contra uma pessoa.
##
## COMO FUNCIONA
## - Duas arenas no mesmo "mundo": a dos heróis (x 0..1280) e a dos monstros (espelhada, lá na direita).
##   As tropas andam até o portal da ponta, atravessam e aparecem na arena do outro, indo até o castelo dele.
## - Você vê só a SUA arena (quem é Monsters vê a dele espelhada: o castelo também fica à esquerda).
##   ESPIAR (50 de energia) mostra a arena inimiga por 6 s.
## - Cada lado tem a sua energia (do céu, da Elara / do Esqueleto Black) e as suas cartas.
## OTIMIZADO: passo fixo de 1/60 s, listas por linha, projéteis reaproveitados, tudo desenhado em poucos nós.
## ONLINE (lockstep, igual ao jogo.js): a sorte usa a MESMA semente nos dois aparelhos e eles só trocam as AÇÕES
## (colocar tropa, pegar energia, espiar). A partida anda em turnos de 10 passos; cada ação vale 3 turnos depois
## (0,5 s: dá tempo de chegar no outro). Um turno só roda quando as ações do adversário para ele já chegaram.
## No fim, os dois mandam o resultado para o servidor (finalizar_pvp): troféus e moedas são dados lá.

const C := preload("res://scripts/arena/config_arena.gd")
const P := preload("res://scripts/pvp/config_pvp.gd")
const PASSO := 1.0 / 60.0
## ONLINE: turno = passos por turno; atraso = turnos até a ação valer; desiste_em = segundos sem notícia = vitória por W.O.;
## repete = cada mensagem leva também os 2 turnos anteriores (se uma se perder, a próxima cobre).
const ONLINE := {"turno": 10, "atraso": 3, "desiste_em": 20.0, "pede_de_novo_em": 0.5, "repete": 2, "conectar_em": 25.0}
const RESULTADO_ONLINE := {"vitoria": "+30 troféus · +50 moedas", "derrota": "−20 troféus · +15 moedas", "empate": "+25 moedas"}

@export var lado_local := ""                ## "heroes" ou "monsters" ("" = o lado escolhido no menu)
@export var nivel_conta := 1                ## nível da conta (depois vem do Supabase)
@export var energia_infinita := false       ## teste
@export var mostrar_fps := false

# ---------------------------------------------------------------- o que o HUD usa (mesmos nomes da campanha)
var pvp := true
var cartas_dados: Array[PersonagemDados] = []
var carta_sel := -1
var nivel_herois := 1
var espiar_t := 0.0
var energia: int:
	get: return int(energias[lado_local])
var vida_castelo: float:
	get: return vidas[lado_local]
var vida_inimigo: float:
	get: return vidas[outro]
var recarga: Dictionary:
	get: return recargas[lado_local]

# ---------------------------------------------------------------- partida
var outro := "monsters"
var energias := {"heroes": 0.0, "monsters": 0.0}
var vidas := {"heroes": P.VIDA_CASTELO, "monsters": P.VIDA_CASTELO}
var recargas := {"heroes": {}, "monsters": {}}
var herois: Array = []                      # [linha] -> Array[Unidade]
var monstros: Array = []
var tempo := P.DURACAO
var preparo := P.PREPARO
var prorrogacao := false
var fim := false
var vencedor := ""
var abatidas := 0                           # monstros derrotados
var mortos_h := 0                           # heróis derrotados
var sol_t := 2.0
var bot_t := 4.0
var bot_nivel := 1
var adversario := ""
var rng := RandomNumberGenerator.new()
var semente := 0
var passo_n := 0                            # passos da partida desde o começo (60 por segundo)
var prox_id_orbe := 1                       # cada energia tem um número (no online o "pegar" vai pela rede)

# ---------------------------------------------------------------- ONLINE
var rede := {}                              # vazio = contra o bot. Ver _preparar_online()
var canal: RedePvp
var fila_acoes: Array = []                  # ações (minhas e do adversário) esperando o passo delas
var seq_acao := 0
var acumulado := 0.0

class Projetil:
	var ativo := false
	var tipo := ""
	var lado := ""
	var linha := 0
	var pos := Vector2.ZERO
	var vel := 0.0
	var dano := 0
	var dano_area := 0
	var raio := 0.0
	var t := 0.0

class Onda:
	var tipo := ""
	var lado := ""
	var linha := 0
	var x := 0.0
	var vel := 0.0
	var dano := 0
	var atingidos: Dictionary = {}
	var no_castelo := false

var projeteis: Array[Projetil] = []
var ondas: Array[Onda] = []
var textos: Array = []                      # {pos, txt, cor, t}
var explosoes: Array = []                   # [pos, raio, t, cor]
var orbes: Array = []                       # {pos, alvo_y, valor, t, lado, x0}
var voos: Array = []                        # energia voando na tela até o painel {de, t, valor}
var faiscas: Array = []                     # brilho do portal {pos, vel, t, cor}

# ---------------------------------------------------------------- tela
var espiando := false
var mundo: Node2D
var camada_unidades: Node2D
var desenho: Node2D
var desenho_tela: Node2D
var fundo: Sprite2D
var ui: CanvasLayer
var hud: Control
var lbl_banner: Label
var banner_t := 0.0
var lbl_fps: Label
var painel: Control                         # fim de jogo / pausa
var painel_titulo := ""
var painel_texto := ""
var painel_bons: Array[Button] = []
var troca_t := 0.0                          # clarão da troca de arena (espiar)
var f_titulo: Font
var f_texto: Font

# =================================================================== INÍCIO
func _ready() -> void:
	Perfil.carregar()
	Engine.physics_ticks_per_second = 60
	get_tree().quit_on_go_back = false
	if lado_local == "":
		lado_local = Perfil.lado if Perfil.lado != "" else "heroes"
	adversario = Perfil.pvp_adversario
	bot_nivel = Perfil.bot_nivel
	semente = randi()
	if not Perfil.pvp_sala.is_empty():
		_preparar_online(Perfil.pvp_sala)
		Perfil.pvp_sala = {}
	outro = "monsters" if lado_local == "heroes" else "heroes"
	nivel_herois = nivel_conta
	rng.seed = semente
	for i in C.G.rows:
		herois.append([])
		monstros.append([])
	for i in 64:
		projeteis.append(Projetil.new())
	f_titulo = _fonte(["Fontes/lilita-one-latin-400-normal.woff2"])
	f_texto = _fonte(["Fontes/fredoka-latin-700-normal.woff2"])
	_montar_cena()
	_montar_hud()
	comecar()

func _exit_tree() -> void:
	get_tree().quit_on_go_back = true
	get_tree().paused = false
	if canal:
		canal.fechar()

func _fonte(opcoes: Array) -> Font:
	for o in opcoes:
		var c: String = "res://assets/" + o
		if ResourceLoader.exists(c):
			return load(c)
	return ThemeDB.fallback_font

func comecar() -> void:
	for lista in [herois, monstros]:
		for l in lista:
			for u in l:
				u.queue_free()
			l.clear()
	for pr in projeteis:
		pr.ativo = false
	ondas.clear(); orbes.clear(); voos.clear(); explosoes.clear(); textos.clear()
	recargas = {"heroes": {}, "monsters": {}}
	vidas = {"heroes": P.VIDA_CASTELO, "monsters": P.VIDA_CASTELO}
	energias = {"heroes": float(P.ENERGIA_INICIAL), "monsters": float(P.ENERGIA_INICIAL)}
	if online():
		rng.seed = semente                          # a MESMA sorte nos dois aparelhos
	else:
		energias[outro] += (bot_nivel - 1) * P.BOT.energia_inicial_por_nivel     # o bot começa mais forte a cada vitória
	passo_n = 0
	prox_id_orbe = 1
	fila_acoes.clear()
	acumulado = 0.0
	tempo = P.DURACAO
	preparo = P.PREPARO
	prorrogacao = false
	fim = false
	vencedor = ""
	abatidas = 0
	mortos_h = 0
	sol_t = 2.0
	bot_t = 4.0
	carta_sel = -1
	espiando = false
	espiar_t = 0.0
	_aplicar_vista()
	_fechar_painel()
	var contra := (" · Contra %s" % adversario) if adversario != "" else " · Bot nível %d" % bot_nivel
	if online():
		contra = " · Você contra %s (online)" % adversario
	mostrar_banner("PREPARE SUA ARENA\nColoque suas tropas e pegue a energia do céu%s" % contra, 4.5)

# =================================================================== CENA E VISTA
func _montar_cena() -> void:
	fundo = Sprite2D.new()
	fundo.centered = true
	fundo.position = Vector2(C.W / 2, C.H / 2)
	fundo.z_index = -10
	add_child(fundo)
	mundo = Node2D.new()
	add_child(mundo)
	camada_unidades = Node2D.new()
	camada_unidades.y_sort_enabled = true
	mundo.add_child(camada_unidades)
	desenho = Node2D.new()
	desenho.z_index = 10
	desenho.draw.connect(_desenhar)
	mundo.add_child(desenho)
	desenho_tela = Node2D.new()
	desenho_tela.z_index = 11
	desenho_tela.draw.connect(_desenhar_tela)
	add_child(desenho_tela)
	RenderingServer.set_default_clear_color(Color("3d6b33"))

## Qual arena aparece e se está espelhada. Por dentro: heróis à esquerda, monstros à direita.
func _arena_vista() -> String:
	return outro if espiando else lado_local

func _aplicar_vista() -> void:
	var a := _arena_vista()
	var esp := lado_local == "monsters"               # quem é Monsters vê tudo espelhado
	if a == "heroes":
		mundo.scale = Vector2(-1, 1) if esp else Vector2.ONE
		mundo.position = Vector2(C.W, 0) if esp else Vector2.ZERO
	else:
		mundo.scale = Vector2(-1, 1) if esp else Vector2.ONE
		mundo.position = Vector2(P.MW, 0) if esp else Vector2(-(P.MW - C.W), 0)
	# fundo: o castelo da arena vista fica à esquerda quando ela é a SUA; espiando, fica à direita
	var nomes := ["arena_guerreiro_dia_largo", "arena_guerreiro_dia", "arena_guerreiro_noite_largo", "arena_guerreiro_noite", "fundo_do_jogo"]
	if a == "monsters":
		nomes = ["arena_monsters_dia_largo", "arena_monsters_dia"] + nomes
	var tex: Texture2D = null
	for n in nomes:
		for ext in ["jpg", "png", "webp"]:
			var c := "res://assets/Fundo/%s.%s" % [n, ext]
			if tex == null and ResourceLoader.exists(c):
				tex = load(c)
	fundo.texture = tex
	fundo.flip_h = espiando
	if tex:
		var k := C.H / tex.get_height()
		fundo.scale = Vector2(k, k)

func para_tela(p: Vector2) -> Vector2:
	return mundo.transform * p

func para_mundo(p: Vector2) -> Vector2:
	return mundo.transform.affine_inverse() * p

# =================================================================== HUD
func _montar_hud() -> void:
	var ids: Array = P.CARTAS_HEROES if lado_local == "heroes" else P.CARTAS_MONSTERS
	for id in ids:
		var p: PersonagemDados = Catalogo.get_p(id)
		if p:
			cartas_dados.append(p)
	ui = CanvasLayer.new()
	add_child(ui)
	hud = preload("res://scripts/arena/hud.gd").new()
	hud.arena = self
	ui.add_child(hud)
	lbl_banner = Label.new()
	lbl_banner.position = Vector2(80, 210)
	lbl_banner.size = Vector2(C.W - 160, 160)
	lbl_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_banner.add_theme_font_override("font", f_titulo)
	lbl_banner.add_theme_font_size_override("font_size", 34)
	lbl_banner.add_theme_color_override("font_color", Color("fff4d6"))
	lbl_banner.add_theme_color_override("font_outline_color", Color("24130a"))
	lbl_banner.add_theme_constant_override("outline_size", 12)
	lbl_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(lbl_banner)
	lbl_fps = Label.new()
	lbl_fps.position = Vector2(C.W - 70, 8)
	lbl_fps.visible = mostrar_fps
	ui.add_child(lbl_fps)
	# painel de fim de jogo / pausa
	painel = Control.new()
	painel.set_anchors_preset(Control.PRESET_FULL_RECT)
	painel.process_mode = Node.PROCESS_MODE_ALWAYS
	painel.mouse_filter = Control.MOUSE_FILTER_STOP
	painel.draw.connect(_desenhar_painel)
	painel.visible = false
	var camada := CanvasLayer.new()
	camada.layer = 5
	add_child(camada)
	camada.add_child(painel)

func mostrar_banner(txt: String, t := 3.2) -> void:
	lbl_banner.text = txt
	lbl_banner.visible = txt != ""
	banner_t = t

func texto_fase() -> String:
	if preparo > 0.0:
		return "Preparo %ds" % ceili(preparo)
	var t := maxi(0, ceili(tempo))
	var meus := abatidas if lado_local == "heroes" else mortos_h
	var deles := mortos_h if lado_local == "heroes" else abatidas
	return "%s%d:%02d · %d x %d" % ["+" if prorrogacao else "", t / 60, t % 60, meus, deles]

func horda_restante() -> float:
	return clampf(vidas[outro] / P.VIDA_CASTELO, 0.0, 1.0)

func espiar() -> void:
	if fim or espiar_t > 0.0:
		return
	if online():                                       # ONLINE: vira ação (gasta a energia no passo certo, nos dois aparelhos)
		if rede.espiar_pedido:
			return
		if energias[lado_local] - _energia_reservada() < C.ESPIAR_CUSTO:
			mostrar_banner("Espiar custa %d de energia" % C.ESPIAR_CUSTO, 1.6)
			return
		rede.espiar_pedido = true
		carta_sel = -1
		agendar({"tipo": "espiar"})
		return
	if not energia_infinita and energias[lado_local] < C.ESPIAR_CUSTO:
		mostrar_banner("Espiar custa %d de energia" % C.ESPIAR_CUSTO, 1.6)
		return
	if not energia_infinita:
		energias[lado_local] -= C.ESPIAR_CUSTO
	espiar_t = C.ESPIAR_DURACAO
	carta_sel = -1
	_trocar_vista(true)

func _trocar_vista(espiar_: bool) -> void:
	espiando = espiar_
	troca_t = 1.0
	_aplicar_vista()

# =================================================================== UNIDADES
func _lado_b(x: float) -> bool:
	return x > P.MW / 2.0

func criar_unidade(id: String, lado: String, linha: int, x: float, nv: int) -> Unidade:
	var p: PersonagemDados = Catalogo.get_p(id)
	if p == null:
		push_warning("PvP: não achei a ficha '%s'" % id)
		return null
	var u := Unidade.new()
	u.pvp = true
	u.fixo = preparo > 0.0
	u.iniciar(self, p, lado, linha, nv)
	u.position = Vector2(x, C.linha_y(linha))
	if lado == "heroes":
		u.anda = p.anims.has("andar") and p.comportamento != "gerador"
		var cfg: Dictionary = P.andar(id)
		cfg.merge(p.extra.get("andar", {}), true)
		u.vel_andar = float(cfg.velocidade) * rng.randf_range(0.94, 1.06)
		u.para = float(cfg.para)
		u.pausa_parar = float(cfg.get("pausa", 0.35))
		herois[linha].append(u)
	else:
		monstros[linha].append(u)
		Sons.do_personagem(p, "aparecer")
	camada_unidades.add_child(u)
	return u

## Por que não dá para colocar ("" = dá). reserva = energia já prometida em ações que ainda vão acontecer (online).
func _motivo_nao_pode(lado: String, p: PersonagemDados, linha: int, col: int, livre: bool, reserva := 0.0) -> String:
	var x := C.cel_x(col) if lado == "heroes" else P.MW - C.cel_x(col)
	var lista: Array = herois[linha] if lado == "heroes" else monstros[linha]
	for u in lista:
		if not u.morto and absf(u.position.x - x) < C.G.cw * 0.5:
			return "ocupado"
	if recargas[lado].get(p.id, 0.0) > 0.0:
		return "recarregando"
	if not livre and energias[lado] - reserva < p.custo:
		return "falta energia"
	return ""

## Nível da conta da tropa: online, cada lado usa o nível da PRÓPRIA conta (vem do servidor);
## contra o bot, você usa o seu e o bot usa nível 1.
func _nivel_tropa(lado: String, id: String, local: bool) -> int:
	if online():
		var nv: Dictionary = rede.niveis.get(lado, {})
		return clampi(int(nv.get(id, 1)), 1, Progressao.NIVEL_MAX)
	return maxi(nivel_conta, Perfil.nivel_de(id)) if local else 1

## Coloca uma tropa (do jogador, do bot ou, no online, do adversário). col conta a partir do castelo de quem coloca.
func colocar(lado: String, id: String, linha: int, col: int, local: bool) -> bool:
	if fim:
		return false
	var p: PersonagemDados = Catalogo.get_p(id)
	if p == null or linha < 0 or linha >= C.G.rows or col < 0 or col >= C.G.cols:
		return false
	var livre := energia_infinita and local and not online()
	var motivo := _motivo_nao_pode(lado, p, linha, col, livre)
	if motivo != "":
		if local:
			_texto_tela(Vector2(C.cel_x(col), C.linha_y(linha) - 60), motivo, Color("cccccc") if motivo == "recarregando" else Color("ff8080"))
		return false
	if not livre:
		energias[lado] -= p.custo
	recargas[lado][id] = p.recarga
	var x := C.cel_x(col) if lado == "heroes" else P.MW - C.cel_x(col)
	criar_unidade(id, lado, linha, x, _nivel_tropa(lado, id, local))
	explosoes.append([Vector2(x, C.linha_y(linha) - 10), 34.0, 0.0, Color("ffe08a") if lado == "heroes" else Color("9be05a")])
	return true

func colocar_local(casa: Vector2i) -> void:
	if carta_sel < 0 or carta_sel >= cartas_dados.size() or espiando:
		return
	var p := cartas_dados[carta_sel]
	if online():                                       # ONLINE: confere agora e manda; ela aparece daqui a 0,5 s
		for a in fila_acoes:
			if a.lado == lado_local and a.tipo == "colocar" and int(a.r) == casa.y and int(a.c) == casa.x:
				return
			if a.lado == lado_local and a.tipo == "colocar" and a.id == p.id:
				_texto_tela(Vector2(C.cel_x(casa.x), C.linha_y(casa.y) - 60), "recarregando", Color("cccccc"))
				return
		var motivo := _motivo_nao_pode(lado_local, p, casa.y, casa.x, false, _energia_reservada())
		if motivo != "":
			_texto_tela(Vector2(C.cel_x(casa.x), C.linha_y(casa.y) - 60), motivo, Color("cccccc") if motivo == "recarregando" else Color("ff8080"))
			return
		agendar({"tipo": "colocar", "id": p.id, "r": casa.y, "c": casa.x})
		carta_sel = -1
		if C.ESCONDER_CARTAS_AO_COLOCAR:
			hud.guardado = true
		return
	if colocar(lado_local, p.id, casa.y, casa.x, true):
		carta_sel = -1
		if C.ESCONDER_CARTAS_AO_COLOCAR:
			hud.guardado = true

# --- perguntas que os personagens fazem (sempre só na própria linha e na mesma arena) ---
func alvo_na_frente(u: Unidade, alcance: float) -> Unidade:
	var melhor: Unidade = null
	var melhor_d := INF
	var b := _lado_b(u.position.x)
	if u.lado == "heroes":
		for m in monstros[u.linha]:
			if m.morto or _lado_b(m.position.x) != b:
				continue
			var d: float = m.position.x - u.position.x
			if d >= -10.0 and d <= alcance and d < melhor_d:
				melhor = m; melhor_d = d
	else:
		for h in herois[u.linha]:
			if not h.ocupa_casa or _lado_b(h.position.x) != b:
				continue
			var d: float = u.position.x - h.position.x
			if d >= -10.0 and d <= alcance and d < melhor_d:
				melhor = h; melhor_d = d
	return melhor

func todos_na_frente(u: Unidade, alcance: float) -> Array:
	var r := []
	var b := _lado_b(u.position.x)
	var lista: Array = monstros[u.linha] if u.lado == "heroes" else herois[u.linha]
	for o in lista:
		if o.morto or _lado_b(o.position.x) != b:
			continue
		var d: float = (o.position.x - u.position.x) * (1.0 if u.lado == "heroes" else -1.0)
		if d >= -10.0 and d <= alcance:
			r.append(o)
	return r

func tem_inimigo_na_linha(u: Unidade) -> bool:
	if no_cerco(u):
		return true                                   # CERCO: o castelo inimigo também é alvo
	var b := _lado_b(u.position.x)
	var lista: Array = monstros[u.linha] if u.lado == "heroes" else herois[u.linha]
	for o in lista:
		if o.morto or _lado_b(o.position.x) != b:
			continue
		if (o.position.x - u.position.x) * (1.0 if u.lado == "heroes" else -1.0) > -10.0:
			return true
	return false

func contar_inimigos_na_linha(u: Unidade) -> int:
	var n := 0
	var b := _lado_b(u.position.x)
	var lista: Array = monstros[u.linha] if u.lado == "heroes" else herois[u.linha]
	for o in lista:
		if not o.morto and _lado_b(o.position.x) == b and (o.position.x - u.position.x) * (1.0 if u.lado == "heroes" else -1.0) > 0.0:
			n += 1
	return n

## CERCO: até onde a tropa pode andar (2º quadrado antes do castelo inimigo) se não tiver ninguém na frente.
func limite_x(u: Unidade) -> float:
	var heroi := u.lado == "heroes"
	var id := u.p.id
	if u.chefe or not (id in P.DE_LONGE or id in P.PODER_NO_CASTELO):
		return INF if heroi else -INF
	if heroi:
		if not _lado_b(u.position.x):
			return INF
		for m in monstros[u.linha]:
			if not m.morto and _lado_b(m.position.x) and m.position.x - u.position.x > -5.0:
				return INF                               # alguém entre ele e o castelo: vai até lá lutar
		return maxf(P.x_cerco_herois(), u.position.x)
	if _lado_b(u.position.x):
		return -INF
	for h in herois[u.linha]:
		if h.ocupa_casa and not _lado_b(h.position.x) and u.position.x - h.position.x > -5.0:
			return -INF
	return minf(P.x_cerco_monstros(), u.position.x)

func no_cerco(u: Unidade) -> bool:
	var l := limite_x(u)
	return is_finite(l) and absf(u.position.x - l) < 1.5

func ferir(alvo: Unidade, valor: float, _origem: Unidade = null) -> void:
	if alvo == null or alvo.morto:
		return
	var antes := alvo.vida
	var morreu := alvo.receber(valor)
	var tirou := antes - maxf(alvo.vida, 0.0)
	if tirou >= 1.0:
		_texto(alvo.position + Vector2(rng.randf_range(-12, 12), -alvo.anim.ay * alvo.scale.y - 6), "-%d" % roundi(tirou),
			Color("ffd36b") if alvo.lado == "monsters" else Color("ff6b6b"))
	if morreu:
		if alvo.lado == "monsters":
			abatidas += 1
			if alvo.p.comportamento == "necro":         # o Esqueleto Mago morre: os invocados somem
				for l in monstros:
					for m in l:
						if m.invocador == alvo and not m.morto:
							m.morrer()
		else:
			mortos_h += 1

func ferir_castelo(lado: String, dano: float, pos: Vector2) -> void:
	if fim:
		return
	vidas[lado] = maxf(0.0, vidas[lado] - dano)
	explosoes.append([pos, 60.0, 0.0, Color("ff6b5e") if lado == lado_local else Color("ffd34d")])
	_texto(pos + Vector2(0, -60), "-%d" % roundi(dano), Color("ff6b5e") if lado == lado_local else Color("ffd34d"))
	if lado == _arena_vista():
		Sons.tocar("Castelo/som/dano", 0.8)

## Castelo de cada lado no mundo (para os efeitos).
func _pos_castelo(lado: String, y: float) -> Vector2:
	return Vector2(C.G.left - 30.0, y - 40.0) if lado == "heroes" else Vector2(P.MW - C.G.left + 30.0, y - 40.0)

func soltar_energia(pos: Vector2, valor: int) -> void:     # (a campanha usa; aqui vem pelo soltar_energia_lado)
	soltar_energia_lado(pos, valor, "heroes")

func soltar_energia_lado(pos: Vector2, valor: int, lado: String) -> void:
	orbes.append({"id": prox_id_orbe, "pos": pos, "alvo_y": pos.y, "valor": valor, "t": 0.0, "lado": lado})
	prox_id_orbe += 1

func invocar(u: Unidade, id: String, quantos: int) -> void:
	var linhas := [u.linha - 1, u.linha, u.linha + 1]
	for i in mini(quantos, linhas.size()):
		var r: int = linhas[i]
		if r < 0 or r >= C.G.rows:
			continue
		var m := criar_unidade(id, "monsters", r, u.position.x - C.G.cw, u.nivel)
		if m:
			m.invocador = u
			m.fixo = false
			explosoes.append([m.position + Vector2(0, -20), 40.0, 0.0, Color("8a5cd6")])

func disparar(tipo: String, u: Unidade, saida: Vector2, vel: float, dano_: int, dano_area := 0, raio := 0.0) -> void:
	for pr in projeteis:
		if not pr.ativo:
			pr.ativo = true
			pr.tipo = tipo
			pr.lado = u.lado
			pr.linha = u.linha
			pr.pos = u.position + saida
			pr.vel = vel if u.lado == "heroes" else -vel
			pr.dano = dano_
			pr.dano_area = dano_area
			pr.raio = raio
			pr.t = 0.0
			return

func onda(tipo: String, u: Unidade, dano_: int, vel: float) -> void:
	var o := Onda.new()
	o.tipo = tipo
	o.lado = u.lado
	o.linha = u.linha
	o.x = u.position.x
	o.vel = vel if u.lado == "heroes" else -vel
	o.dano = dano_
	ondas.append(o)

func _texto(pos: Vector2, txt: String, cor: Color) -> void:
	if textos.size() < 40:
		textos.append({"pos": pos, "txt": txt, "cor": cor, "t": 0.0, "tela": false})

func _texto_tela(pos: Vector2, txt: String, cor: Color) -> void:
	textos.append({"pos": pos, "txt": txt, "cor": cor, "t": 0.0, "tela": true})

# =================================================================== PASSO FIXO (60 por segundo)
func _physics_process(dt: float) -> void:
	if fim or online():                                # (o online anda pelo _process, no ritmo dos dois aparelhos)
		return
	_passo_sim(dt)

## UM passo da partida (sempre igual em qualquer aparelho com a mesma semente e as mesmas ações).
func _passo_sim(dt: float) -> void:
	_aplicar_acoes_do_passo()
	_passo_partida(dt)
	for lado in recargas:
		var rec: Dictionary = recargas[lado]
		for k in rec.keys():
			rec[k] = maxf(0.0, rec[k] - dt)
	_passo_unidades(dt)
	_passo_projeteis(dt)
	_passo_ondas(dt)
	_passo_orbes(dt)
	passo_n += 1

func _passo_partida(dt: float) -> void:
	# energia do céu nas DUAS arenas (cada um pega a sua)
	sol_t -= dt
	if sol_t <= 0.0:
		sol_t = rng.randf_range(P.SOL.cada_min, P.SOL.cada_max)
		var xa := rng.randf_range(C.G.left + 40, C.G.left + C.G.cw * C.G.cols - 40)
		var xb := P.MW - rng.randf_range(C.G.left + 40, C.G.left + C.G.cw * C.G.cols - 40)
		for par in [[xa, "heroes"], [xb, "monsters"]]:
			orbes.append({"id": prox_id_orbe, "pos": Vector2(par[0], -30), "x0": par[0], "alvo_y": rng.randf_range(C.G.top + 40, C.G.top + C.G.ch * C.G.rows - 20),
				"valor": P.SOL.valor, "t": 0.0, "lado": par[1]})
			prox_id_orbe += 1
	# BOT (só quando não é online)
	if not online():
		var forca := _forca_bot()
		if preparo <= 0.0 and bot_nivel > 1:
			energias[outro] += dt * P.BOT.energia_por_segundo_por_nivel * (bot_nivel - 1)
		bot_t -= dt
		if bot_t <= 0.0:
			bot_t = rng.randf_range(lerpf(P.BOT.pensa_facil[0], P.BOT.pensa_dificil[0], forca), lerpf(P.BOT.pensa_facil[1], P.BOT.pensa_dificil[1], forca))
			_jogada_do_bot()
	if preparo > 0.0:                                   # PREPARO: o relógio da batalha ainda não anda
		preparo -= dt
		if preparo <= 0.0:
			for lista in [herois, monstros]:
				for l in lista:
					for u in l:
						u.fixo = false
			mostrar_banner("LUTEM!\nDerrube o castelo inimigo em 3 minutos", 2.4)
			Sons.tocar("Jogo/som/lutem", 0.9)
		return
	tempo -= dt
	if vidas.heroes <= 0.0 or vidas.monsters <= 0.0:
		_encerrar("monsters" if vidas.heroes <= 0.0 else "heroes")
		return
	if tempo <= 0.0:
		if absf(vidas.heroes - vidas.monsters) > 0.01:
			_encerrar("heroes" if vidas.heroes > vidas.monsters else "monsters")
		elif abatidas != mortos_h:
			_encerrar("heroes" if abatidas > mortos_h else "monsters")
		elif not prorrogacao:
			prorrogacao = true
			tempo = P.PRORROGACAO
			mostrar_banner("PRORROGAÇÃO!\nMais 1 minuto", 2.6)
		else:
			_encerrar("")

func _passo_unidades(dt: float) -> void:
	for r in C.G.rows:
		for lista_lado in [herois, monstros]:
			var l: Array = lista_lado[r]
			var i := l.size() - 1
			while i >= 0:
				var u: Unidade = l[i]
				u.passo(dt)
				if not u.morto:
					_portal_e_castelo(u)
				if u.livre:
					l[i] = l[l.size() - 1]; l.pop_back()     # tira sem empurrar a lista inteira
					u.queue_free()
				i -= 1

## PORTAL: chegou na ponta da arena, sai na arena do outro. CASTELO: quem luta de perto entra e dá dano.
func _portal_e_castelo(u: Unidade) -> void:
	var x := u.position.x
	if u.lado == "heroes":
		if not _lado_b(x) and x >= P.PORTAO_X:
			_atravessar(u, P.PORTAO_B + 6.0)
		elif x > P.CASTELO_MONSTERS_X:
			ferir_castelo("monsters", P.DANO_ENTRAR_HEROI, _pos_castelo("monsters", u.position.y))
			u.morto = true; u.livre = true
	else:
		if _lado_b(x) and x <= P.PORTAO_B:
			_atravessar(u, P.PORTAO_X - 6.0)
		elif x < P.CASTELO_HEROES_X:
			var d: float = float(u.p.dano_castelo if u.p.dano_castelo > 0 else 10)
			ferir_castelo("heroes", d, _pos_castelo("heroes", u.position.y))
			u.morto = true; u.livre = true

func _atravessar(u: Unidade, para_x: float) -> void:
	for x in [u.position.x, para_x]:
		for i in 8:
			faiscas.append({"pos": Vector2(x, u.position.y - rng.randf_range(20, 90)), "vel": Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 30)), "t": 0.0})
	u.position.x = para_x
	u.atravessou = true

func _passo_projeteis(dt: float) -> void:
	var fim_a := C.W + 40.0
	var comeco_b := P.MW - C.W - 40.0
	for pr in projeteis:
		if not pr.ativo:
			continue
		pr.t += dt
		var x0 := pr.pos.x
		pr.pos.x += pr.vel * dt
		var b := _lado_b(pr.pos.x)
		if pr.lado == "heroes":
			var alvo: Unidade = null
			var melhor := INF
			for m in monstros[pr.linha]:
				if m.morto or _lado_b(m.position.x) != b:
					continue
				var mx: float = m.position.x
				if mx >= x0 - 20.0 and mx <= pr.pos.x + 20.0 and mx < melhor:
					alvo = m; melhor = mx
			if alvo:
				ferir(alvo, pr.dano)
				if pr.raio > 0.0:
					_explodir(pr, alvo)
				pr.ativo = false
			elif b and pr.pos.x >= P.MW - C.G.left - 30.0:      # acertou o castelo dos monstros
				ferir_castelo("monsters", P.DANO_TIRO_CASTELO, pr.pos)
				pr.ativo = false
			elif not b and pr.pos.x > fim_a:
				pr.ativo = false
		else:
			var alvo_h: Unidade = null
			var melhor_h := -INF
			for h in herois[pr.linha]:
				if not h.ocupa_casa or _lado_b(h.position.x) != b:
					continue
				var hx: float = h.position.x
				if hx <= x0 + 20.0 and hx >= pr.pos.x - 20.0 and hx > melhor_h:
					alvo_h = h; melhor_h = hx
			if alvo_h:
				ferir(alvo_h, pr.dano)
				if pr.tipo == "magia_sombra":
					explosoes.append([alvo_h.position + Vector2(0, -50), 34.0, 0.0, Color("9b6bff")])
				pr.ativo = false
			elif not b and pr.pos.x <= C.G.left + 30.0:       # acertou o castelo dos heróis
				ferir_castelo("heroes", P.DANO_TIRO_CASTELO, pr.pos)
				pr.ativo = false
			elif b and pr.pos.x < comeco_b:
				pr.ativo = false

func _explodir(pr: Projetil, alvo: Unidade) -> void:
	var centro := alvo.position + Vector2(0, -50)
	explosoes.append([centro, pr.raio, 0.0, Color("ff8a2a") if pr.tipo == "magia_fogo" else Color("7fb6ff")])
	for r in range(maxi(0, pr.linha - 1), mini(C.G.rows, pr.linha + 2)):
		for m in monstros[r]:
			if m != alvo and not m.morto and (m.position + Vector2(0, -50)).distance_to(centro) <= pr.raio:
				ferir(m, pr.dano_area)
	Sons.tocar(alvo.p.sons.get("impacto", "Mago/som/explosao"), 0.7)

func _passo_ondas(dt: float) -> void:
	var i := ondas.size() - 1
	while i >= 0:
		var o: Onda = ondas[i]
		o.x += o.vel * dt
		var b := _lado_b(o.x)
		var lista: Array = monstros[o.linha] if o.lado == "heroes" else herois[o.linha]
		for alvo in lista:
			if alvo.morto or _lado_b(alvo.position.x) != b or o.atingidos.has(alvo.get_instance_id()):
				continue
			if absf(alvo.position.x - o.x) < 30.0:
				o.atingidos[alvo.get_instance_id()] = true
				ferir(alvo, o.dano)
		var some := false
		if o.lado == "heroes":
			if b and o.x >= P.MW - C.G.left - 30.0:
				ferir_castelo("monsters", P.DANO_PODER_CASTELO, Vector2(o.x, C.linha_y(o.linha) - 40))
				some = true
			elif not b and o.x > C.W + 40:
				some = true
		else:
			if not b and o.x <= C.G.left + 30.0:
				ferir_castelo("heroes", P.DANO_PODER_CASTELO, Vector2(o.x, C.linha_y(o.linha) - 40))
				some = true
			elif b and o.x < P.MW - C.W - 40:
				some = true
		if some:
			ondas.remove_at(i)
		i -= 1

func _passo_orbes(dt: float) -> void:
	var pega_bot := lerpf(P.BOT.pega_facil, P.BOT.pega_dificil, _forca_bot())
	var i := orbes.size() - 1
	while i >= 0:
		var o: Dictionary = orbes[i]
		o.t += dt
		var caindo: bool = o.pos.y < o.alvo_y
		if caindo:                                     # cai do céu devagar, balançando
			o.pos.y = minf(o.alvo_y, o.pos.y + 75.0 * dt)
			if o.has("x0"):
				o.pos.x = o.x0 + sin(o.t * 2.2) * 14.0
			if o.pos.y < o.alvo_y:
				o.t = 0.0
		if online():                                   # ONLINE: ninguém pegou = entra sozinha (nos dois aparelhos igual)
			if C.COLETA_AUTOMATICA > 0 and o.t > C.COLETA_AUTOMATICA:
				_coletar_sim(i)
		elif o.lado == outro:                          # o bot "clica" na energia dele
			if not caindo and o.t >= pega_bot:
				energias[outro] += o.valor
				orbes.remove_at(i)
		elif C.COLETA_AUTOMATICA > 0 and o.t > C.COLETA_AUTOMATICA:
			_coletar(i)
		i -= 1

func _coletar(i: int) -> void:
	var o: Dictionary = orbes[i]
	voos.append({"de": para_tela(o.pos), "t": 0.0, "valor": o.valor})
	orbes.remove_at(i)

## ONLINE: a energia entra no passo da partida (igual nos dois aparelhos). O voo até o painel é só enfeite.
func _coletar_sim(i: int) -> void:
	var o: Dictionary = orbes[i]
	energias[o.lado] += o.valor
	if o.lado == lado_local and not o.get("pega_local", false):
		voos.append({"de": para_tela(o.pos), "t": 0.0, "valor": 0})
	orbes.remove_at(i)

## Toque: pega a energia perto (só a sua). Também bloqueia colocar tropa se o toque foi quase em cima de uma.
func pegar_energia(pos_tela: Vector2) -> bool:
	if espiando:
		return false
	var p := para_mundo(pos_tela)
	var perto := false
	for i in orbes.size():
		var o: Dictionary = orbes[i]
		if o.lado != lado_local or o.get("pega_local", false):
			continue
		var d: float = o.pos.distance_to(p)
		if d < C.ENERGIA_TOQUE:
			if online():                               # ONLINE: já voa na sua tela; a energia entra quando a ação chegar
				o.pega_local = true
				voos.append({"de": para_tela(o.pos), "t": 0.0, "valor": 0})
				agendar({"tipo": "orbe", "id": o.id})
			else:
				_coletar(i)
			Sons.tocar("Jogo/som/energia", 0.6)
			return true
		if d < C.ENERGIA_ZONA_SEGURA:
			perto = true
	return perto

# =================================================================== BOT
func _forca_bot() -> float:
	return float(bot_nivel - 1) / float(P.BOT.maximo - 1)

func _linha_mais_cheia(lista_lado: Array) -> int:
	var n: Array[int] = []
	var maior := 0
	for r in C.G.rows:
		var c := 0
		for u in lista_lado[r]:
			if not u.morto:
				c += 1
		n.append(c)
		maior = maxi(maior, c)
	if maior == 0:
		return rng.randi() % C.G.rows
	var melhores := []
	for r in C.G.rows:
		if n[r] == maior:
			melhores.append(r)
	return melhores[rng.randi() % melhores.size()]

func _jogada_do_bot() -> void:
	if fim:
		return
	var ids: Array = P.CARTAS_MONSTERS if outro == "monsters" else P.CARTAS_HEROES
	var rec: Dictionary = recargas[outro]
	var opcoes: Array[PersonagemDados] = []
	for id in ids:
		var p: PersonagemDados = Catalogo.get_p(id)
		if p and p.custo <= energias[outro] and rec.get(id, 0.0) <= 0.0:
			opcoes.append(p)
	if opcoes.is_empty():
		return
	var esc: PersonagemDados = opcoes[rng.randi() % opcoes.size()]
	if rng.randf() < _forca_bot() * 0.7:                 # mais forte: escolhe mais vezes a tropa mais cara
		for p in opcoes:
			if p.custo > esc.custo:
				esc = p
	var colunas := roundi(lerpf(P.BOT.colunas, P.BOT.colunas_max, _forca_bot()))
	var linha := _linha_mais_cheia(herois if outro == "monsters" else monstros)
	var cols := range(colunas)
	cols.shuffle()
	for c in cols:
		if colocar(outro, esc.id, linha, c, false):
			return

# =================================================================== ONLINE (lockstep)
func online() -> bool:
	return not rede.is_empty()

## A busca do menu achou uma sala no servidor: {id, semente, heroes, monsters, niveis_*, nome_*, lado, token}.
func _preparar_online(sala: Dictionary) -> void:
	lado_local = str(sala.get("lado", lado_local))
	var o := "monsters" if lado_local == "heroes" else "heroes"
	semente = int(sala.get("semente", 0))
	adversario = str(sala.get("nome_" + o, "")) if sala.get("nome_" + o) != null else ""
	if adversario == "":
		adversario = "Adversário"
	var nh = sala.get("niveis_heroes", {})
	var nm = sala.get("niveis_monsters", {})
	rede = {"sala": str(sala.id), "lado_outro": o, "recebidos": {}, "enviados": {}, "minhas": [],
		"esperando_desde": 0, "pediu_em": 0, "saiu": false, "wo": false, "finalizando": false,
		"conectou": false, "inicio": Time.get_ticks_msec(), "espiar_pedido": false,
		"niveis": {"heroes": nh if nh is Dictionary else {}, "monsters": nm if nm is Dictionary else {}}}
	canal = RedePvp.new()
	add_child(canal)
	canal.chegou.connect(_mensagem_rede)
	canal.conectou.connect(func(): rede.conectou = true)
	canal.abrir(Conta.endereco(), Conta.CHAVE, rede.sala, str(sala.get("token", "")))
	for t in ONLINE.atraso - 1:                      # os primeiros turnos não têm ações
		_enviar_turno(t)

func _turno_de(passo: int) -> int:
	return passo / ONLINE.turno

## Tudo o que o jogador faz online vira uma AÇÃO marcada para um passo lá na frente (vai também para o adversário).
func agendar(acao: Dictionary) -> void:
	if fim:
		return
	seq_acao += 1
	acao.seq = seq_acao
	acao.lado = lado_local
	acao.passo = passo_n + ONLINE.turno * ONLINE.atraso
	rede.minhas.append(acao)
	fila_acoes.append(acao)

## Energia que já está prometida em ações minhas que ainda não aconteceram.
func _energia_reservada() -> float:
	var r := 0.0
	for a in fila_acoes:
		if a.lado != lado_local:
			continue
		if a.tipo == "colocar":
			var p: PersonagemDados = Catalogo.get_p(a.id)
			if p:
				r += p.custo
		elif a.tipo == "espiar":
			r += C.ESPIAR_CUSTO
	return r

## Segurança: cada lado só coloca as tropas dele.
func _acao_valida(a: Dictionary, lado: String) -> bool:
	match str(a.get("tipo", "")):
		"colocar":
			return str(a.get("id", "")) in (P.CARTAS_HEROES if lado == "heroes" else P.CARTAS_MONSTERS)
		"orbe", "espiar":
			return true
	return false

func _mensagem_rede(m: Dictionary) -> void:
	if rede.is_empty():
		return
	var tipo := str(m.get("tipo", ""))
	if tipo == "turno":
		var lista: Array = [[m.get("t", -1), m.get("acoes", [])]]
		var ant = m.get("ant", [])
		if ant is Array:
			lista.append_array(ant)
		for par in lista:
			if not (par is Array) or par.size() < 2 or not (par[1] is Array):
				continue
			var t := int(par[0])
			if rede.recebidos.has(t):
				continue
			rede.recebidos[t] = true
			for a in par[1]:
				if a is Dictionary and _acao_valida(a, rede.lado_outro):
					var b: Dictionary = a.duplicate()
					b.lado = rede.lado_outro
					b.passo = int(b.get("passo", 0))
					b.seq = int(b.get("seq", 0))
					if _turno_de(b.passo) == t:      # a ação tem de ser do turno que veio
						fila_acoes.append(b)
	elif tipo == "pedir":                              # o outro perdeu algum turno: mando de novo
		var desde := int(m.get("t", 0))
		for t in rede.enviados:
			if t >= desde:
				canal.enviar({"tipo": "turno", "t": t, "acoes": rede.enviados[t]})
	elif tipo == "sair":
		rede.saiu = true

func _enviar_turno(t: int) -> void:
	if rede.enviados.has(t):
		return
	var acoes: Array = []
	var resto: Array = []
	for a in rede.minhas:
		if _turno_de(a.passo) == t:
			var c: Dictionary = a.duplicate()
			c.erase("lado")
			acoes.append(c)
		else:
			resto.append(a)
	rede.minhas = resto
	rede.enviados[t] = acoes
	var ant: Array = []
	for k in range(1, ONLINE.repete + 1):
		if rede.enviados.has(t - k):
			ant.append([t - k, rede.enviados[t - k]])
	canal.enviar({"tipo": "turno", "t": t, "acoes": acoes, "ant": ant})

## Antes de cada passo: no começo do turno manda o meu turno lá da frente e confere se o do adversário já chegou.
func _pode_avancar() -> bool:
	var t := _turno_de(passo_n)
	if passo_n % ONLINE.turno == 0:
		_enviar_turno(t + ONLINE.atraso - 1)
	if rede.recebidos.has(t):
		rede.esperando_desde = 0
		return true
	var agora := Time.get_ticks_msec()
	if rede.esperando_desde == 0:
		rede.esperando_desde = agora
	var esperou: float = (agora - rede.esperando_desde) / 1000.0
	if esperou > ONLINE.pede_de_novo_em and agora - rede.pediu_em > 1000:
		rede.pediu_em = agora
		canal.enviar({"tipo": "pedir", "t": t})
	if not rede.conectou:
		if (agora - rede.inicio) / 1000.0 > ONLINE.conectar_em:
			_sem_conexao()
	elif rede.saiu or esperou > ONLINE.desiste_em:
		_encerrar_online(lado_local, true)           # o outro sumiu: vitória por W.O.
	return false

func esperando_adversario() -> bool:
	return online() and not fim and rede.esperando_desde > 0 and Time.get_ticks_msec() - rede.esperando_desde > 600

func _passo_online(dt: float) -> void:
	acumulado = minf(acumulado + dt, 0.25)
	var n := 0
	while acumulado >= PASSO and n < 8 and not fim:
		if not _pode_avancar():
			acumulado = minf(acumulado, PASSO * 2.0)
			break
		_passo_sim(PASSO)
		acumulado -= PASSO
		n += 1

func _aplicar_acoes_do_passo() -> void:
	if fila_acoes.is_empty():
		return
	var agora: Array = []
	var resto: Array = []
	for a in fila_acoes:
		if int(a.passo) <= passo_n:
			agora.append(a)
		else:
			resto.append(a)
	if agora.is_empty():
		return
	fila_acoes = resto
	agora.sort_custom(func(a, b):
		if a.passo != b.passo:
			return a.passo < b.passo
		if a.lado != b.lado:
			return a.lado == "heroes"
		return a.seq < b.seq)
	for a in agora:
		_aplicar_acao(a)

func _aplicar_acao(a: Dictionary) -> void:
	var lado: String = a.lado
	match str(a.tipo):
		"colocar":
			colocar(lado, str(a.id), int(a.r), int(a.c), false)
		"orbe":
			var id := int(a.id)
			for i in orbes.size():
				if int(orbes[i].id) == id and orbes[i].lado == lado:
					_coletar_sim(i)
					break
		"espiar":
			if lado == lado_local:
				rede.espiar_pedido = false
			if energias[lado] >= C.ESPIAR_CUSTO:
				energias[lado] -= C.ESPIAR_CUSTO
				if lado == lado_local:
					espiar_t = C.ESPIAR_DURACAO
					_trocar_vista(true)

## "Foto" do fim da partida: os dois aparelhos têm de ter a mesma (o servidor compara).
func foto_da_partida() -> String:
	var u := []
	for lista in [herois, monstros]:
		for l in lista:
			for x in l:
				if not x.morto:
					u.append([x.p.id, x.linha, roundi(x.position.x), roundi(x.vida)])
	var d := [passo_n, snappedf(vidas.heroes, 0.01), snappedf(vidas.monsters, 0.01), roundi(energias.heroes), roundi(energias.monsters),
		abatidas, mortos_h, vencedor, u]
	return JSON.stringify(d).md5_text().substr(0, 12)

func _sem_conexao() -> void:
	if fim:
		return
	fim = true
	carta_sel = -1
	painel_titulo = "SEM CONEXÃO"
	painel_texto = "Não deu para entrar na sala da partida.\nConfira a internet e tente de novo."
	if canal:
		canal.fechar()
	_abrir_painel([["Menu", Color("4a5fae"), _ir_menu]])

## Fim da partida online: mostra o resultado e grava no servidor (o primeiro aparelho que chega grava para os dois).
func _encerrar_online(v: String, wo := false) -> void:
	if rede.finalizando:
		return
	fim = true
	vencedor = v
	carta_sel = -1
	rede.wo = wo
	rede.finalizando = true
	var venceu := v == lado_local
	var empate := v == ""
	var meus := abatidas if lado_local == "heroes" else mortos_h
	var delesk := mortos_h if lado_local == "heroes" else abatidas
	painel_titulo = "VITÓRIA!" if venceu else ("EMPATE" if empate else "DERROTA")
	painel_texto = ("%s saiu da partida: vitória por W.O.!\n" % adversario) if wo and venceu else ""
	painel_texto += "Seu castelo: %d · Castelo inimigo: %d\nVocê derrotou %d e perdeu %d.\nGravando o resultado..." % [
		ceili(vidas[lado_local]), ceili(vidas[outro]), meus, delesk]
	_abrir_painel([["Menu", Color("4a5fae"), _ir_menu]])
	if venceu:
		Sons.tocar("Jogo/som/proximo_nivel", 0.9)
	elif not empate:
		Sons.tocar("Castelo/som/caiu", 1.0)
	canal.enviar({"tipo": "sair"})
	var sala = null
	for tentativa in 3:
		var r: Dictionary = await Conta.chamar("finalizar_pvp", {"p_sala": rede.sala, "p_vencedor": v if v != "" else "empate",
			"p_resumo": "wo" if wo else foto_da_partida()})
		if r.ok and r.dados is Dictionary:
			sala = r.dados
			break
		await get_tree().create_timer(1.5).timeout
	if not is_inside_tree():
		return
	canal.fechar()
	var linha := "(Sem internet para gravar o resultado.)"
	if sala != null and sala.get("finalizada", false):
		var sv := str(sala.get("vencedor", ""))
		linha = RESULTADO_ONLINE.vitoria if sv == lado_local else (RESULTADO_ONLINE.empate if sv == "empate" else RESULTADO_ONLINE.derrota)
		if sv != (v if v != "" else "empate"):
			linha += "\n(O servidor gravou o resultado do outro aparelho.)"
	painel_texto = painel_texto.replace("Gravando o resultado...", linha)
	painel.queue_redraw()
	Conta.no_servidor("meu_perfil")                     # troféus e moedas novos

## Sair no meio da partida online = derrota (o adversário ganha por W.O.).
func _desistir_online() -> void:
	if not fim:
		fim = true
		rede.finalizando = true
		canal.enviar({"tipo": "sair"})
		Conta.chamar("finalizar_pvp", {"p_sala": rede.sala, "p_vencedor": outro, "p_resumo": "wo"})
	_ir_menu()

# =================================================================== FIM
func _encerrar(v: String) -> void:
	if online():
		_encerrar_online(v)
		return
	fim = true
	vencedor = v
	carta_sel = -1
	var venceu := v == lado_local
	var empate := v == ""
	var minha: float = vidas[lado_local]
	var deles: float = vidas[outro]
	var meus := abatidas if lado_local == "heroes" else mortos_h
	var delesk := mortos_h if lado_local == "heroes" else abatidas
	# moedas (contra o bot não vale troféu)
	var base: int = P.MOEDAS.vitoria if venceu else (P.MOEDAS.empate if empate else P.MOEDAS.derrota)
	var g: Dictionary = Perfil.ganhar_moedas(base, lado_local)    # +50% no lado em alta; +150 se jogou os dois lados hoje
	var ganho: int = g.ganho + g.duplo
	# BOT_DIFICULDADE: vitória = bot mais difícil na próxima; derrota = mais fácil
	var nivel_antes := bot_nivel
	if not empate:
		bot_nivel = clampi(bot_nivel + (1 if venceu else -P.BOT.derrota_diminui), 1, P.BOT.maximo)
	Perfil.bot_nivel = bot_nivel
	Perfil.salvar()
	painel_titulo = "VITÓRIA!" if venceu else ("EMPATE" if empate else "DERROTA")
	painel_texto = "Seu castelo: %d · Castelo inimigo: %d\nVocê derrotou %d e perdeu %d.\n+%d moedas" % [ceili(minha), ceili(deles), meus, delesk, ganho]
	if adversario == "" and bot_nivel != nivel_antes:
		painel_texto += "\nO bot subiu para o nível %d!" % bot_nivel if bot_nivel > nivel_antes else "\nO bot voltou para o nível %d." % bot_nivel
	_abrir_painel([["Jogar de novo", Color("ffc43a"), _jogar_de_novo], ["Menu", Color("4a5fae"), _ir_menu]])
	if venceu:
		Sons.tocar("Jogo/som/proximo_nivel", 0.9)
	elif not empate:
		Sons.tocar("Castelo/som/caiu", 1.0)

func _jogar_de_novo() -> void:
	adversario = ""                                     # na revanche é o bot de verdade (com o nível dele)
	comecar()

func _ir_menu() -> void:
	get_tree().paused = false
	Perfil.pvp_adversario = ""
	get_tree().change_scene_to_file("res://cenas/intro.tscn")

func _pausar() -> void:
	if fim or painel.visible:
		return
	if online():                                       # ONLINE: a partida não para (o outro continua jogando)
		painel_titulo = "SAIR?"
		painel_texto = "A partida continua enquanto este aviso está aberto.\nSe sair agora, você perde (vitória do adversário por W.O.)."
		_abrir_painel([["Continuar", Color("ffc43a"), _continuar], ["Desistir", Color("c0463a"), _desistir_online]])
		return
	get_tree().paused = true
	painel_titulo = "PAUSA"
	painel_texto = "A batalha está parada."
	_abrir_painel([["Continuar", Color("ffc43a"), _continuar], ["Sair da partida", Color("4a5fae"), _ir_menu]])

func _continuar() -> void:
	get_tree().paused = false
	_fechar_painel()

func _abrir_painel(botoes: Array) -> void:
	for b in painel_bons:
		b.queue_free()
	painel_bons.clear()
	var y := 420.0
	var x0 := C.W / 2.0 - (botoes.size() * 230.0 - 20.0) / 2.0
	for i in botoes.size():
		var d: Array = botoes[i]
		var b := Button.new()
		b.text = d[0]
		b.position = Vector2(x0 + i * 230.0, y)
		b.size = Vector2(210, 58)
		b.add_theme_font_override("font", f_titulo)
		b.add_theme_font_size_override("font_size", 24)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_outline_color", Color("24130a"))
		b.add_theme_constant_override("outline_size", 6)
		for estado_b in ["normal", "hover", "pressed", "focus"]:
			var sb := StyleBoxFlat.new()
			var cor: Color = d[1]
			sb.bg_color = cor.lightened(0.1 if estado_b == "hover" else 0.0).darkened(0.1 if estado_b == "pressed" else 0.0)
			sb.set_corner_radius_all(18)
			sb.set_border_width_all(3)
			sb.border_color = Color("141a36")
			sb.shadow_color = Color("141a36")
			sb.shadow_size = 0
			sb.shadow_offset = Vector2(0, 6)
			sb.border_width_bottom = 7
			b.add_theme_stylebox_override(estado_b, sb)
		b.pressed.connect(d[2])
		painel.add_child(b)
		painel_bons.append(b)
	painel.visible = true
	painel.queue_redraw()

func _fechar_painel() -> void:
	if painel:
		painel.visible = false

func _desenhar_painel() -> void:
	var tela := Rect2(Vector2.ZERO, painel.size)
	painel.draw_rect(tela, Color(0.02, 0.02, 0.06, 0.6))
	var r := Rect2(C.W / 2.0 - 300, 170, 600, 330)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2c3874")
	sb.set_corner_radius_all(26)
	sb.set_border_width_all(4)
	sb.border_color = Color("f6c343") if painel_titulo == "VITÓRIA!" else Color("141a36")
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 8)
	painel.draw_style_box(sb, r)
	var cor := Color("ffd34d") if painel_titulo == "VITÓRIA!" else (Color("ff7a6a") if painel_titulo == "DERROTA" else Color("fff4d6"))
	painel.draw_string_outline(f_titulo, Vector2(r.position.x, r.position.y + 78), painel_titulo, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 58, 14, Color("24130a"))
	painel.draw_string(f_titulo, Vector2(r.position.x, r.position.y + 78), painel_titulo, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 58, cor)
	painel.draw_multiline_string_outline(f_texto, Vector2(r.position.x + 30, r.position.y + 130), painel_texto, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 60, 20, -1, 6, Color("24130a"))
	painel.draw_multiline_string(f_texto, Vector2(r.position.x + 30, r.position.y + 130), painel_texto, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 60, 20, -1, Color("eef0ff"))

# =================================================================== QUADRO (efeitos e desenho)
func _process(dt: float) -> void:
	if online() and not fim:
		_passo_online(dt)
	for tx in textos:
		tx.t += dt
		tx.pos.y -= 40.0 * dt
	textos = textos.filter(func(tx): return tx.t < 0.9)
	var i := explosoes.size() - 1
	while i >= 0:
		explosoes[i][2] += dt
		if explosoes[i][2] > 0.4:
			explosoes.remove_at(i)
		i -= 1
	for f in faiscas:
		f.t += dt
		f.pos += f.vel * dt
	faiscas = faiscas.filter(func(f): return f.t < 0.5)
	# energia voando até o painel
	i = voos.size() - 1
	while i >= 0:
		var v: Dictionary = voos[i]
		v.t += dt
		if v.t >= 0.45:
			energias[lado_local] += v.valor          # (online o valor é 0: a energia já entrou no passo da partida)
			voos.remove_at(i)
		i -= 1
	if espiar_t > 0.0 and not get_tree().paused:
		espiar_t -= dt
		if espiar_t <= 0.0:
			_trocar_vista(false)
	troca_t = maxf(0.0, troca_t - dt * 3.0)
	if banner_t > 0.0:
		banner_t -= dt
		lbl_banner.visible = banner_t > 0.0
	if mostrar_fps:
		lbl_fps.text = "%d fps" % Engine.get_frames_per_second()
	desenho.queue_redraw()
	desenho_tela.queue_redraw()

## Coisas que não podem ficar espelhadas (texto, barra de vida): desenha "de volta" no ponto p.
func _reto(p: Vector2) -> void:
	desenho.draw_set_transform(p, 0, Vector2(mundo.scale.x, 1))

func _desenhar() -> void:
	var d := desenho
	var tempo_s := Time.get_ticks_msec() / 1000.0
	# portais nas pontas das arenas
	for par in [[P.PORTAO_X, Color(1.0, 0.8, 0.3)], [P.PORTAO_B, Color(0.55, 0.95, 0.35)]]:
		var c := Vector2(par[0], C.G.top + C.G.ch * C.G.rows / 2.0)
		var cor: Color = par[1]
		d.draw_set_transform(c, 0, Vector2(0.28, 1.0))
		d.draw_circle(Vector2.ZERO, 150, Color(cor, 0.12))
		d.draw_circle(Vector2.ZERO, 118, Color(0.05, 0.03, 0.12, 0.85))
		for k in 6:
			var f := fmod(tempo_s * 0.35 + k / 6.0, 1.0)
			d.draw_arc(Vector2.ZERO, 118.0 * (1.0 - f), tempo_s * 1.5 + k, tempo_s * 1.5 + k + 4.0, 24, Color(cor, 0.15 + 0.5 * f), 6.0 + 6.0 * f)
		d.draw_set_transform(Vector2.ZERO)
	# barras de vida (só de quem levou golpe há pouco)
	for lista in [herois, monstros]:
		for l in lista:
			for u in l:
				if u.morto or u.mostra_barra <= 0.0:
					continue
				var alt: float = u.p.barra_y if u.p.barra_y > 0 else u.anim.ay * u.scale.y + 10.0
				_reto(u.position + Vector2(0, -alt))
				var w := 54.0
				var k: float = clampf(u.vida / u.vida_max, 0.0, 1.0)
				d.draw_rect(Rect2(Vector2(-w / 2, 0), Vector2(w, 7)), Color(0, 0, 0, 0.6))
				d.draw_rect(Rect2(Vector2(-w / 2 + 1, 1), Vector2((w - 2) * k, 5)), Color("5fd36b") if u.lado == lado_local else Color("ff5a4a"))
	d.draw_set_transform(Vector2.ZERO)
	# projéteis
	for pr in projeteis:
		if not pr.ativo:
			continue
		match pr.tipo:
			"flecha", "flecha_inimiga":
				var dir := signf(pr.vel)
				d.draw_line(pr.pos - Vector2(22 * dir, 0), pr.pos, Color("7a5230"), 3.0)
				d.draw_line(pr.pos, pr.pos - Vector2(7 * dir, 4), Color("dddddd"), 2.0)
				d.draw_line(pr.pos, pr.pos - Vector2(7 * dir, -4), Color("dddddd"), 2.0)
			_:
				var cor := Color("7fb6ff")
				if pr.tipo == "magia_fogo": cor = Color("ff8a2a")
				elif pr.tipo == "magia_sombra": cor = Color("9b6bff")
				var pulso := 1.0 + 0.15 * sin(pr.t * 20.0)
				d.draw_circle(pr.pos, 16.0 * pulso, Color(cor, 0.25))
				d.draw_circle(pr.pos, 9.0 * pulso, cor)
				d.draw_circle(pr.pos, 4.0, Color.WHITE)
	# ondas de terra / ossos
	for o in ondas:
		var y := C.linha_y(o.linha)
		var cor_o := Color("8a6a3a") if o.tipo == "terra" else Color("efe6d0")
		for k in 4:
			var x: float = o.x - signf(o.vel) * k * 16.0
			d.draw_rect(Rect2(x - 7, y - 26 + k * 4, 14, 26 - k * 4), Color(cor_o, 1.0 - k * 0.22))
	for e in explosoes:
		var kk: float = e[2] / 0.4
		d.draw_circle(e[0], e[1] * (0.4 + 0.6 * kk), Color(e[3], 0.45 * (1.0 - kk)))
	for f in faiscas:
		d.draw_circle(f.pos, 2.5, Color(1, 1, 1, 1.0 - f.t / 0.5))
	# energia (só a sua aparece)
	for o in orbes:
		if o.lado == lado_local and not o.get("pega_local", false):
			hud.icone_energia(d, o.pos, 21.0 * (1.0 + 0.06 * sin(tempo_s * 6.0)))
	# textos de dano (sem espelhar)
	for tx in textos:
		if tx.tela:
			continue
		var a: float = 1.0 - tx.t / 0.9
		_reto(tx.pos)
		d.draw_string_outline(f_titulo, Vector2(-40, 0), tx.txt, HORIZONTAL_ALIGNMENT_CENTER, 80, 20, 5, Color(0, 0, 0, a))
		d.draw_string(f_titulo, Vector2(-40, 0), tx.txt, HORIZONTAL_ALIGNMENT_CENTER, 80, 20, Color(tx.cor, a))
	d.draw_set_transform(Vector2.ZERO)

const BT_PAUSA := Rect2(C.W - 66, 12, 52, 52)

## Coisas na tela (não no mundo): a luz da casa com o "fantasma" da tropa, energia voando, troca de arena.
func _desenhar_tela() -> void:
	var d := desenho_tela
	# botão de pausa (no celular também dá para usar o "voltar")
	var pc := BT_PAUSA.get_center()
	d.draw_circle(pc + Vector2(0, 4), 26, Color(0, 0, 0, 0.35))
	d.draw_circle(pc, 26, Color("141a36"))
	d.draw_circle(pc, 23, Color("4a5fae"))
	d.draw_circle(pc + Vector2(-3, -5), 14, Color(1, 1, 1, 0.12))
	d.draw_rect(Rect2(pc + Vector2(-9, -10), Vector2(6, 20)), Color.WHITE)
	d.draw_rect(Rect2(pc + Vector2(3, -10), Vector2(6, 20)), Color.WHITE)
	if carta_sel >= 0 and carta_sel < cartas_dados.size() and not espiando and not fim:
		var c := C.casa_em(get_local_mouse_position())
		if c.x >= 0:
			var g := C.G
			var cor := Color(1, 1, 1) if lado_local == "heroes" else Color(0.7, 1, 0.5)
			d.draw_rect(Rect2(g.left, g.top + c.y * g.ch, g.cw * g.cols, g.ch), Color(cor, 0.12))
			d.draw_rect(Rect2(g.left + c.x * g.cw, g.top, g.cw, g.ch * g.rows), Color(cor, 0.10))
			var casa := Rect2(g.left + c.x * g.cw, g.top + c.y * g.ch, g.cw, g.ch)
			d.draw_rect(casa, Color(cor, 0.22))
			d.draw_rect(casa, Color(cor, 0.6), false, 2.0)
			var p := cartas_dados[carta_sel]
			var a := p.anim_qualquer(["parado", "defender", "andar"])
			if a and a.textura:
				var k := p.escala * a.escala
				var pes := Vector2(C.cel_x(c.x), C.linha_y(c.y))
				# a folha olha para a direita: na sua tela a tropa sempre anda para a direita
				d.draw_texture_rect_region(a.textura, Rect2(pes - Vector2(a.ax, a.ay) * k, Vector2(a.cw, a.ch) * k), a.retangulo(0), Color(1, 1, 1, 0.5))
	for tx in textos:
		if tx.tela:
			var al: float = 1.0 - tx.t / 0.9
			d.draw_string_outline(f_titulo, tx.pos - Vector2(80, 0), tx.txt, HORIZONTAL_ALIGNMENT_CENTER, 160, 20, 5, Color(0, 0, 0, al))
			d.draw_string(f_titulo, tx.pos - Vector2(80, 0), tx.txt, HORIZONTAL_ALIGNMENT_CENTER, 160, 20, Color(tx.cor, al))
	var alvo: Vector2 = hud.alvo_energia()
	for v in voos:
		var k2: float = v.t / 0.45
		var e := 1.0 - pow(1.0 - k2, 3.0)
		var pos: Vector2 = v.de.lerp(alvo, e) - Vector2(0, sin(k2 * PI) * 60.0)
		hud.icone_energia(d, pos, 18.0 * (1.0 - k2 * 0.3))
	if online() and not espiando:                      # ONLINE: tropa que você mandou e ainda vai aparecer (0,5 s)
		for ac in fila_acoes:
			if ac.lado != lado_local or ac.tipo != "colocar":
				continue
			var pa: PersonagemDados = Catalogo.get_p(ac.id)
			var an := pa.anim_qualquer(["parado", "defender", "andar"]) if pa else null
			if an and an.textura:
				var kk := pa.escala * an.escala
				var pe := Vector2(C.cel_x(int(ac.c)), C.linha_y(int(ac.r)))
				d.draw_texture_rect_region(an.textura, Rect2(pe - Vector2(an.ax, an.ay) * kk, Vector2(an.cw, an.ch) * kk), an.retangulo(0), Color(1, 1, 1, 0.35))
	if esperando_adversario():
		var tw := "Esperando %s..." % adversario
		d.draw_string_outline(f_titulo, Vector2(0, 110), tw, HORIZONTAL_ALIGNMENT_CENTER, C.W, 26, 10, Color("24130a"))
		d.draw_string(f_titulo, Vector2(0, 110), tw, HORIZONTAL_ALIGNMENT_CENTER, C.W, 26, Color("fff4d6"))
	if espiando:
		var t := "ARENA INIMIGA · %ds" % ceili(espiar_t)
		d.draw_string_outline(f_titulo, Vector2(0, 150), t, HORIZONTAL_ALIGNMENT_CENTER, C.W, 26, 10, Color("24130a"))
		d.draw_string(f_titulo, Vector2(0, 150), t, HORIZONTAL_ALIGNMENT_CENTER, C.W, 26, Color("ffb3a8"))
	if troca_t > 0.0:
		d.draw_rect(Rect2(Vector2(-200, -200), Vector2(C.W + 2000, C.H + 400)), Color(1, 1, 1, troca_t * 0.6))

# =================================================================== TOQUES
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
		if painel.visible and not fim:
			_continuar()
		else:
			_pausar()
		return
	var pos: Vector2
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		pos = get_local_mouse_position()
	elif ev is InputEventScreenTouch and ev.pressed:
		pos = get_canvas_transform().affine_inverse() * ev.position
	else:
		return
	if fim:
		return
	if BT_PAUSA.grow(6).has_point(pos):
		_pausar()
		return
	if pegar_energia(pos):
		return
	var casa := C.casa_em(pos)
	if casa.x >= 0:
		colocar_local(casa)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if painel and painel.visible and not fim:
			_continuar()
		else:
			_pausar()
