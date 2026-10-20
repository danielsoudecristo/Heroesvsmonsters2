extends Control
## SALA DE ENTRADA do PvP (Batalha, Cerco e Campeonato): aparece depois de tocar em "Jogar" no modo.
## * Duas cartas grandes, uma ao lado da outra: HEROES (contorno amarelo) e MONSTERS (contorno verde).
##   Tocar numa carta = entrar daquele lado. Em cada carta, quantos estão entrando agora.
## * No meio, os dois GRUPOS separados (quem está entrando de cada lado, com a foto) e o CHAT da sala.
## * CAMPEONATO: sala de 2 minutos; 8 de cada lado no máximo (lado com 8 = LOTADO, só dá o outro).
##   Se demorar, mais gente vai completando as vagas até fechar os 2 minutos. Depois abre a árvore.
## * BATALHA e CERCO: escolheu o lado, procura alguém do outro lado — e o adversário aparece ali para o duelo.
## Ninguém é chamado de "bot" na tela: quem tem conta aparece com a foto do Google.
## Servidor: supabase/27_sala_de_entrada.sql

const FUNDO := "res://assets/Menu/escolher_lado_largo.jpg"
const IMG := {"heroes": "res://assets/pvp/Heroes.png", "monsters": "res://assets/pvp/Monsters.png"}
const PALCO := Vector2(1280, 720)
const BORDA := {"heroes": Color("ffcc33"), "monsters": Color("4fe05a")}      ## contorno das cartas
const COR_NOME := {"heroes": Color("ffa23a"), "monsters": Color("7ee04a")}   ## nomes: laranja / verde
## PESSOA REAL (a partida veio do servidor): contorno grosso no perfil — Heroes LARANJA, Monsters VERDE.
## (contra o bot fica só o brilho de sempre, sem esse contorno)
const CONTORNO_REAL := {"heroes": Color("ff8c1a"), "monsters": Color("3ddc4a")}
const OURO := Color("f6c343")
const CONTORNO := Color("120c04")
const VAGAS := 8
const TEMPO_CAMP := 120.0
const ESPERA_DUELO := 15.0
const TITULO := {"batalha": "BATALHA", "cerco": "CERCO", "campeonato": "CAMPEONATO"}
const SUB := {"batalha": "Vale troféus · vença de Heroes E de Monsters (série de 2)",
	"cerco": "2 rodadas: defenda e depois ataque",
	"campeonato": "16 jogadores · 8 Heroes × 8 Monsters · mata-mata"}

var modo := "batalha"
var online := false
var lado := ""                               ## lado escolhido ("" = ainda não escolheu)
var gente: Array = []                        ## quem está entrando: {nome, foto, lado, eu, personagem, t, local}
var reais := {"heroes": 0, "monsters": 0}    ## (campeonato) pessoas de cada lado (lotado = 8)
var falta := TEMPO_CAMP                      ## (campeonato) segundos até fechar a sala
var procura_t := 0.0                         ## (batalha/cerco) há quanto tempo está procurando
var _relogio := 0.0
var _entra := 0.0
var _escolha_t := 0.0                        ## animação de quando escolheu o lado
var _apertado := ""
var _aviso := ""
var _aviso_t := 0.0
var _pedindo := false
var _pergunta_t := 0.0
var _procura_prox := 0.0
var _entrei := false                         ## (campeonato online) já está inscrito
var _saindo := false
var _comeco_t := -1.0                        ## (campeonato) "VAI COMEÇAR!" antes de abrir a árvore
var _achou: Dictionary = {}                  ## (batalha/cerco) adversário encontrado
var _achou_t := -1.0
var _sala: Dictionary = {}
var _procura_fim := false
var _limite := ESPERA_DUELO
var _bots_t := 0.0                           ## próximos que entram na sala (sem conta / completando)
var _sala_t := 0.0                           ## há quanto tempo a sala está aberta (sem conta)
var _faiscas: Array = []
var _raio_t := 0.0
var _raio: PackedVector2Array = PackedVector2Array()
var _tex := {}
var _fotos := {}
var _retratos := {}
var _imgs := {}
var f_titulo: Font
var f_texto: Font
var fundo: TextureRect
# chat
var chat: Array = []                         ## {nome, texto, lado, eu, sis, foto}
var _chat_ultimo := 0
var _chat_t := 0.0
var campo: LineEdit
var _ja_disse := {}                          ## quem já foi anunciado no chat ("Fulano entrou")

# ================================================================== COMEÇO
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	f_titulo = _fonte("Fontes/lilita-one-latin-400-normal.woff2")
	f_texto = _fonte("Fontes/fredoka-latin-700-normal.woff2")
	Perfil.carregar()
	modo = Perfil.sala_modo if Perfil.sala_modo in ["batalha", "cerco", "campeonato"] else "batalha"
	online = Conta.online_pronto()
	for l in IMG:
		_tex[l] = load(IMG[l])
	_criar_fundo()
	_criar_chat()
	for i in 70:
		_faiscas.append(_nova_faisca(true))
	_sistema("Bem-vindo à sala %s! Escolha seu lado." % {"batalha": "de Batalha", "cerco": "do Cerco", "campeonato": "do Campeonato"}[modo])
	if online:
		_perguntar()
		_ler_chat()
	else:
		_sistema("Entre na sua conta para jogar contra pessoas do mundo todo e conversar aqui.")
	Conta.estou("sala", TITULO[modo].capitalize())

func _fonte(c: String) -> Font:
	var cam := "res://assets/" + c
	return load(cam) if ResourceLoader.exists(cam) else ThemeDB.fallback_font

## Fundo: a arte de Heroes x Monsters, desfocada e escurecida, com um zoom lento (fica atrás de tudo).
func _criar_fundo() -> void:
	fundo = TextureRect.new()
	fundo.texture = load(FUNDO)
	fundo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fundo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fundo.show_behind_parent = true
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float desfoque = 2.2;
void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * desfoque;
	vec4 c = vec4(0.0);
	float w = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float k = 1.0 / (1.0 + float(x * x + y * y));
			c += texture(TEXTURE, UV + vec2(float(x), float(y)) * px) * k;
			w += k;
		}
	}
	c /= w;
	vec2 d = UV - vec2(0.5);
	float vinheta = 1.0 - smoothstep(0.32, 0.82, length(d * vec2(1.0, 1.25)));
	float luz = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	c.rgb = mix(vec3(luz), c.rgb, 1.12);
	c.rgb *= mix(0.22, 0.62, vinheta);
	COLOR = vec4(c.rgb, 1.0);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	fundo.material = m
	add_child(fundo)

func _criar_chat() -> void:
	campo = LineEdit.new()
	campo.max_length = 120
	campo.placeholder_text = "Escreva para a sala..." if online else "Entre na sua conta para conversar"
	campo.editable = online
	campo.add_theme_font_override("font", f_texto)
	campo.add_theme_font_size_override("font_size", 17)
	campo.add_theme_color_override("font_color", Color("1c1630"))
	campo.add_theme_color_override("font_placeholder_color", Color(0.11, 0.09, 0.19, 0.5))
	campo.add_theme_color_override("font_uneditable_color", Color(0.11, 0.09, 0.19, 0.5))
	campo.add_theme_color_override("caret_color", Color("2c3874"))
	for estado in ["normal", "focus", "read_only"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("fff8e6") if estado != "read_only" else Color("bfb9ad")
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(3)
		sb.border_color = OURO if estado == "focus" else Color("141a36")
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		campo.add_theme_stylebox_override(estado, sb)
	campo.text_submitted.connect(func(_t): _enviar())
	add_child(campo)

# ================================================================== RETÂNGULOS (no palco 1280x720)
func _O() -> Vector2:
	var o := (size - PALCO) / 2.0
	if campo and campo.has_focus():                 # teclado do celular: sobe a tela para o campo aparecer
		var kb := DisplayServer.virtual_keyboard_get_height()
		if kb > 0:
			var ws := DisplayServer.window_get_size()
			var kbp := float(kb) * get_viewport_rect().size.y / maxf(1.0, float(ws.y))
			o.y -= maxf(0.0, o.y + _ret_campo().end.y + 12.0 - (size.y - kbp))
	return o

func _ret_carta(l: String) -> Rect2:
	return Rect2(24, 92, 292, 402) if l == "heroes" else Rect2(964, 92, 292, 402)

func _ret_botao(l: String) -> Rect2:
	var c := _ret_carta(l)
	return Rect2(c.position.x + 10, c.end.y + 18, c.size.x - 20, 58)

func _ret_grupo(l: String) -> Rect2:
	return Rect2(332, 238, 300, 230) if l == "heroes" else Rect2(648, 238, 300, 230)

func _ret_chat() -> Rect2:
	return Rect2(332, 480, 616, 228)

func _ret_campo() -> Rect2:
	var c := _ret_chat()
	return Rect2(c.position.x + 12, c.end.y - 52, c.size.x - 128, 42)

func _ret_enviar() -> Rect2:
	var c := _ret_chat()
	return Rect2(c.end.x - 108, c.end.y - 52, 96, 42)

func _rets() -> Dictionary:
	return {"menu": Rect2(18, 14, 128, 50), "heroes": _ret_carta("heroes"), "monsters": _ret_carta("monsters"),
		"bt_heroes": _ret_botao("heroes"), "bt_monsters": _ret_botao("monsters"), "enviar": _ret_enviar(),
		"replays": RET_REPLAYS}

## Botão REPLAYS (36_replays.sql): as batalhas suas e dos amigos das últimas 24 h.
const RET_REPLAYS := Rect2(1280 - 18 - 170, 14, 170, 50)

# ================================================================== QUEM ESTÁ ENTRANDO
func _do_lado(l: String) -> Array:
	return gente.filter(func(g): return str(g.lado) == l)

func _lotado(l: String) -> bool:
	if modo != "campeonato" or lado == l:
		return false
	if online:
		return int(reais.get(l, 0)) >= VAGAS
	return false

## Alguém novo na sala (os que não têm conta entram com o retrato de um personagem do lado).
func _novo_local(l: String) -> Dictionary:
	var lista: Array = Catalogo.do_lado(l).map(func(p): return p.id)
	var nomes := gente.map(func(g): return str(g.nome))
	var nome := ConfigPvp.nome_adversario()
	while nome in nomes:
		nome = ConfigPvp.nome_adversario()
	return {"nome": nome, "foto": "", "lado": l, "eu": false, "personagem": lista[randi() % lista.size()] if lista.size() > 0 else "",
		"t": 0.0, "local": true}

## Sem conta (e na Batalha/Cerco, para a sala nunca ficar vazia): gente entrando e saindo aos poucos.
func _mexer_sala(dt: float) -> void:
	_bots_t -= dt
	if _bots_t > 0.0 or _achou_t >= 0.0 or _comeco_t >= 0.0:
		return
	if modo == "campeonato":
		if online:
			return
		# sem conta: as vagas vão enchendo (cheia em ~25 s); começa quando lotar e você tiver escolhido
		_bots_t = randf_range(0.5, 1.3)
		var e := clampf((_sala_t - 1.5) / 22.0, 0.0, 1.0)
		for l in ["heroes", "monsters"]:
			var cabe := VAGAS - (1 if lado == l else 0)
			var tem := gente.filter(func(g): return g.lado == l and g.local and not g.get("eu", false)).size()
			if tem > cabe:
				_tirar_um(l)
			elif tem < ceili(cabe * e) and randf() < 0.8:
				_entrar_alguem(_novo_local(l))
		return
	# Batalha / Cerco: 2 a 5 de cada lado, uns entram, outros acham partida e saem
	_bots_t = randf_range(1.8, 4.2)
	var l2 := "heroes" if randf() < 0.5 else "monsters"
	var n := gente.filter(func(g): return g.lado == l2 and g.local and not g.get("eu", false)).size()
	if n < 2 or (n < 5 and randf() < 0.6):
		_entrar_alguem(_novo_local(l2))
	else:
		_tirar_um(l2)

func _entrar_alguem(g: Dictionary) -> void:
	gente.append(g)
	if not _ja_disse.has(g.nome + g.lado):
		_ja_disse[g.nome + g.lado] = true
		if _entra > 0.5:
			_sistema("%s entrou nos %s" % [g.nome, "HEROES" if g.lado == "heroes" else "MONSTERS"], g.lado)

func _tirar_um(l: String) -> void:
	for i in gente.size():
		if gente[i].lado == l and gente[i].local and not gente[i].get("eu", false):
			gente.remove_at(i)
			return

# ================================================================== ESCOLHER O LADO
func _escolher(l: String) -> void:
	if _achou_t >= 0.0 or _comeco_t >= 0.0 or _saindo:
		return
	if _lotado(l):
		_avisar("%s está lotado! Entre pelos %s." % ["HEROES" if l == "heroes" else "MONSTERS", "MONSTERS" if l == "heroes" else "HEROES"])
		Sons.tocar("Jogo/som/clique", 0.3)
		return
	if lado == l:
		return
	Sons.tocar("Jogo/som/clique", 0.6)
	var antes := lado
	lado = l
	_escolha_t = 0.0
	Perfil.lado = l                                  # o lado da próxima partida (e do menu)
	Perfil.salvar()
	if online:
		Conta.chamar("definir_lado", {"p_lado": l})
	# você aparece no grupo do lado escolhido
	gente = gente.filter(func(g): return not g.get("eu", false))
	gente.append({"nome": _meu_nome(), "foto": "", "lado": l, "eu": true, "personagem": "", "t": 0.0, "local": true})
	if modo == "campeonato":
		if online:
			_entrar_campeonato(l, antes)
		elif gente.filter(func(g): return g.lado == l and g.local and not g.get("eu", false)).size() >= VAGAS:
			_tirar_um(l)                             # alguém cede a vaga para você
	else:
		procura_t = 0.0
		_procura_prox = 0.0
		_procura_fim = false
		_limite = ESPERA_DUELO if online else randf_range(4.5, 7.0)

func _meu_nome() -> String:
	var n := Perfil.nome if Perfil.nome != "" else "Você"
	return n.get_slice(" ", 0)

func _entrar_campeonato(l: String, antes: String) -> void:
	_pedindo = true
	var r: Dictionary = await Conta.chamar("entrar_campeonato", {"p_lado": l})
	_pedindo = false
	if not r.ok:
		var e := str(r.get("erro", "")).to_lower()
		_avisar("Esse lado lotou agora! Escolha o outro." if "lotado" in e else "Não deu para entrar. Tente de novo.")
		lado = antes
		gente = gente.filter(func(g): return not g.get("eu", false))
		return
	_entrei = true
	if r.dados is Dictionary:
		_receber_camp(r.dados)

# ================================================================== SERVIDOR
func _perguntar() -> void:
	if _pedindo or _saindo:
		return
	_pedindo = true
	if modo == "campeonato":
		var r: Dictionary = await Conta.chamar("espiar_campeonato")
		_pedindo = false
		if r.ok and r.dados is Dictionary:
			_receber_camp(r.dados)
	else:
		var r2: Dictionary = await Conta.chamar("fila_lobby", {"p_modo": _modo_srv()})
		_pedindo = false
		if r2.ok and r2.dados is Array:
			_receber_fila(r2.dados)

func _modo_srv() -> String:
	return "cerco" if modo == "cerco" else "normal"

## Batalha/Cerco: as pessoas da fila (as que já estão aqui ficam; as que saíram somem).
func _receber_fila(lista: Array) -> void:
	var vistos := {}
	for x in lista:
		if not (x is Dictionary) or x.get("eu", false):
			continue
		var nome := str(x.get("nome", "Jogador"))
		var chave := nome + str(x.get("lado", ""))
		vistos[chave] = true
		if gente.filter(func(g): return not g.local and g.nome + g.lado == chave).is_empty():
			_entrar_alguem({"nome": nome, "foto": str(x.get("foto", "")) if x.get("foto") != null else "", "lado": str(x.get("lado", "heroes")),
				"eu": false, "personagem": "", "t": 0.0, "local": false})
	gente = gente.filter(func(g): return g.local or vistos.has(g.nome + g.lado))

## Campeonato: quem está na sala (pessoas e quem completa as vagas), o relógio e se começou.
func _receber_camp(d: Dictionary) -> void:
	var st := str(d.get("status", ""))
	falta = float(d.get("falta", TEMPO_CAMP))
	var re = d.get("reais", {})
	if re is Dictionary:
		reais = {"heroes": int(re.get("heroes", 0)), "monsters": int(re.get("monsters", 0))}
	var ins = d.get("inscritos", [])
	var nova: Array = []
	if ins is Array:
		for x in ins:
			var eu: bool = x.get("eu", false) == true
			var g := {"nome": _meu_nome() if eu else str(x.get("nome", "Jogador")), "foto": str(x.get("foto", "")) if x.get("foto") != null else "",
				"lado": str(x.get("lado", "heroes")), "eu": eu, "personagem": str(x.get("personagem", "")) if x.get("personagem") != null else "",
				"t": 9.0, "local": false}
			for v in gente:                              # quem já estava continua com a mesma animação
				if v.nome == g.nome and v.lado == g.lado:
					g.t = v.t
			if g.t >= 9.0:
				g.t = 0.0
				if not _ja_disse.has(g.nome + g.lado) and not eu:
					_ja_disse[g.nome + g.lado] = true
					if _entra > 0.5:
						_sistema("%s entrou nos %s" % [g.nome, "HEROES" if g.lado == "heroes" else "MONSTERS"], g.lado)
			if eu:
				lado = g.lado
				_entrei = true
			nova.append(g)
	if lado != "" and not _entrei:                       # escolheu, mas a resposta ainda não veio
		nova.append({"nome": _meu_nome(), "foto": "", "lado": lado, "eu": true, "personagem": "", "t": 1.0, "local": true})
	gente = nova
	if st == "andando" and _entrei and _comeco_t < 0.0:
		Campeonato.de_servidor(d)
		_comeco_t = 0.0
		Sons.tocar("Jogo/som/clique", 0.9)

## Batalha/Cerco: procura alguém do outro lado no servidor.
func _procurar() -> void:
	_pedindo = true
	var r: Dictionary = await Conta.chamar("procurar_partida_modo", {"p_lado": lado, "p_modo": _modo_srv()})
	_pedindo = false
	if _achou_t >= 0.0 or lado == "" or _saindo:
		return
	if r.ok and r.dados is Dictionary and r.dados.has("id"):
		await _achou_pessoa(r.dados)

func _achou_pessoa(sala: Dictionary) -> void:
	var token: String = await Conta.token_fresco()
	if _achou_t >= 0.0:
		return
	var s := sala.duplicate()
	s["token"] = token
	s["lado"] = "heroes" if str(s.get("heroes", "")) == Conta.meu_id() else "monsters"
	lado = s.lado
	var outro := "monsters" if lado == "heroes" else "heroes"
	var nome := str(s.get("nome_" + outro, "")) if s.get("nome_" + outro) != null else ""
	var foto := str(s.get("foto_" + outro, "")) if s.get("foto_" + outro) != null else ""
	_mostrar_adversario({"nome": nome if nome != "" else "Adversário", "foto": foto, "lado": outro, "personagem": "", "eu": false}, s)

## O tempo de procura acabou: sai da fila (se alguém te achou nesse meio tempo, joga com ele);
## senão, quem está esperando do outro lado aqui na sala vem duelar.
func _tempo_acabou() -> void:
	if online:
		_pedindo = true
		var r: Dictionary = await Conta.chamar("sair_da_fila_modo", {"p_modo": _modo_srv()})
		_pedindo = false
		if _achou_t >= 0.0:
			return
		if r.ok and r.dados is Dictionary and r.dados.has("id"):
			await _achou_pessoa(r.dados)
			return
	var outro := "monsters" if lado == "heroes" else "heroes"
	var quem: Dictionary = {}
	for g in gente:
		if g.lado == outro and g.local:
			quem = g
			break
	if quem.is_empty():
		quem = _novo_local(outro)
		_entrar_alguem(quem)
	_mostrar_adversario(quem, {})

func _mostrar_adversario(g: Dictionary, sala: Dictionary) -> void:
	_achou = g
	_sala = sala
	_achou_t = 0.0
	Sons.tocar("Jogo/som/clique", 1.0)

func _ir_luta() -> void:
	Perfil.pvp_modo = "cerco" if modo == "cerco" else "normal"
	Perfil.pvp_adversario = str(_achou.get("nome", ""))
	Perfil.pvp_sala = _sala
	Perfil.lado = lado
	Perfil.ja_entrou = true
	Perfil.salvar()
	get_tree().change_scene_to_file("res://cenas/pvp.tscn")

func _ir_arvore() -> void:
	if not online:                                   # sem conta: o campeonato com quem estava na sala
		var nomes := {"heroes": [], "monsters": []}
		for g in gente:
			if not g.get("eu", false):
				nomes[g.lado].append({"nome": g.nome, "personagem": g.personagem})
		Campeonato.novo(lado, nomes)
	Perfil.pvp_sala = {}
	get_tree().change_scene_to_file("res://cenas/campeonato.tscn")

func _sair(destino := "res://cenas/intro.tscn") -> void:
	if _saindo:
		return
	_saindo = true
	Sons.tocar("Jogo/som/clique", 0.5)
	if online and modo == "campeonato" and _entrei and _comeco_t < 0.0:
		Conta.chamar("sair_campeonato")
	elif online and modo != "campeonato" and lado != "":
		Conta.chamar("sair_da_fila_modo", {"p_modo": _modo_srv()})
	Conta.estou("menu")
	get_tree().change_scene_to_file(destino)

# ================================================================== CHAT
func _sistema(txt: String, l := "") -> void:
	chat.append({"nome": "", "texto": txt, "lado": l, "eu": false, "sis": true, "foto": ""})
	while chat.size() > 40:
		chat.pop_front()

func _enviar() -> void:
	if not online:
		_avisar("Entre na sua conta para conversar.")
		return
	var t := campo.text.strip_edges()
	if t == "":
		return
	campo.text = ""
	chat.append({"nome": _meu_nome(), "texto": t, "lado": lado if lado != "" else Perfil.lado, "eu": true, "sis": false, "foto": "", "meu_local": true})
	var r: Dictionary = await Conta.chamar("chat_sala_enviar", {"p_sala": modo, "p_texto": t, "p_lado": lado if lado != "" else Perfil.lado})
	if not r.ok:
		var e := str(r.get("erro", ""))
		_avisar("Calma! Espere um pouquinho para mandar de novo." if "calma" in e.to_lower() else "Não deu para mandar a mensagem.")
	elif r.dados != null:
		_chat_ultimo = maxi(_chat_ultimo, int(r.dados) - 1)
		_ler_chat()

func _ler_chat() -> void:
	var r: Dictionary = await Conta.chamar("chat_sala_ler", {"p_sala": modo, "p_depois": _chat_ultimo})
	if not r.ok or not (r.dados is Array):
		return
	for m in r.dados:
		var id := int(m.get("id", 0))
		if id <= _chat_ultimo:
			continue
		_chat_ultimo = id
		var eu: bool = m.get("eu", false) == true
		if eu:                                        # a minha já está na tela (mostrada na hora)
			var achou := false
			for c in chat:
				if c.get("meu_local", false) and c.texto == str(m.get("texto", "")):
					c.erase("meu_local")
					achou = true
					break
			if achou:
				continue
		chat.append({"nome": str(m.get("nome", "?")), "texto": str(m.get("texto", "")), "lado": str(m.get("lado", "")) if m.get("lado") != null else "",
			"eu": eu, "sis": false, "foto": str(m.get("foto", "")) if m.get("foto") != null else ""})
	while chat.size() > 40:
		chat.pop_front()

# ================================================================== A CADA QUADRO
func _process(dt: float) -> void:
	_relogio += dt
	_entra = move_toward(_entra, 1.0, dt * 2.2)
	_escolha_t += dt
	_aviso_t = maxf(0.0, _aviso_t - dt)
	_sala_t += dt
	for g in gente:
		g.t = g.t + dt
	# fundo: zoom bem lento (respira)
	fundo.size = size * 1.08
	fundo.position = -size * 0.04 + Vector2(sin(_relogio * 0.07) * 14.0, cos(_relogio * 0.05) * 8.0)
	var o := _O()
	campo.position = o + _ret_campo().position
	campo.size = _ret_campo().size
	campo.visible = _achou_t < 0.0 and _comeco_t < 0.0
	_mexer_sala(dt)
	_mexer_faiscas(dt)
	# servidor
	if online and not _saindo:
		_pergunta_t -= dt
		if _pergunta_t <= 0.0 and _achou_t < 0.0 and _comeco_t < 0.0:
			_pergunta_t = 2.0
			_perguntar()
		_chat_t -= dt
		if _chat_t <= 0.0:
			_chat_t = 2.5
			_ler_chat()
	# campeonato: relógio da sala
	if modo == "campeonato" and _comeco_t < 0.0:
		falta = maxf(0.0, falta - dt)
		if not online:
			var cheios := gente.filter(func(g): return g.local and not g.get("eu", false)).size()
			if lado != "" and (cheios >= 15 or falta <= 0.0):
				_comeco_t = 0.0
				Sons.tocar("Jogo/som/clique", 0.9)
			elif falta <= 0.0:
				falta = 0.0
	if _comeco_t >= 0.0:
		_comeco_t += dt
		if _comeco_t >= 2.2 and not _saindo:
			_saindo = true
			_ir_arvore()
	# batalha / cerco: procurando
	if modo != "campeonato" and lado != "" and _achou_t < 0.0:
		procura_t += dt
		if online and not _pedindo:
			_procura_prox -= dt
			if _procura_prox <= 0.0:
				_procura_prox = 1.5
				_procurar()
		if procura_t >= _limite and not _pedindo and not _procura_fim:
			_procura_fim = true
			_tempo_acabou()
	if _achou_t >= 0.0:
		_achou_t += dt
		if _achou_t >= 2.8 and not _saindo:
			_saindo = true
			_ir_luta()
	queue_redraw()

# ---------------------------------------------------------------- faíscas (azuis do lado Heroes, brasas do lado Monsters)
func _nova_faisca(espalhar: bool) -> Array:
	var tela := get_viewport_rect().size
	var x := randf() * tela.x
	var y := (randf() * tela.y) if espalhar else tela.y + 10.0
	return [Vector2(x, y), randf_range(18.0, 60.0), randf_range(1.2, 3.2), randf() * TAU, randf_range(0.4, 1.0)]

func _mexer_faiscas(dt: float) -> void:
	for f in _faiscas:
		f[0].y -= f[1] * dt
		f[0].x += sin(_relogio * 1.3 + f[3]) * 12.0 * dt
		if f[0].y < -10.0:
			var n := _nova_faisca(false)
			for k in n.size():
				f[k] = n[k]
	_raio_t -= dt
	if _raio_t <= 0.0:                               # o raio do meio pisca de vez em quando
		_raio_t = randf_range(0.08, 0.16) if randf() < 0.35 else randf_range(1.2, 3.5)
		_raio = PackedVector2Array()
		var x := size.x * 0.5
		for i in 15:
			_raio.append(Vector2(x + randf_range(-16.0, 16.0), size.y * i / 14.0))

# ================================================================== TOQUES
func _gui_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton) or ev.button_index != MOUSE_BUTTON_LEFT:
		return
	var p: Vector2 = ev.position - _O()
	if ev.pressed:
		_apertado = _botao_em(p)
		if campo.has_focus() and not _ret_campo().has_point(p):
			campo.release_focus()
	else:
		var b := _botao_em(p)
		if b != "" and b == _apertado:
			_tocar(b)
		_apertado = ""
	accept_event()

func _botao_em(p: Vector2) -> String:
	var r := _rets()
	for k in r:
		if r[k].has_point(p):
			return k
	return ""

func _tocar(b: String) -> void:
	match b:
		"menu":
			_sair()
		"heroes", "bt_heroes":
			_escolher("heroes")
		"monsters", "bt_monsters":
			_escolher("monsters")
		"enviar":
			_enviar()
		"replays":
			if _achou_t < 0.0:
				Perfil.replays_volta = "res://cenas/sala_entrada.tscn"
				_sair("res://cenas/replays.tscn")

func _unhandled_key_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel"):
		_sair()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_sair()

func _avisar(t: String) -> void:
	_aviso = t
	_aviso_t = 2.8

# ================================================================== DESENHO
func _draw() -> void:
	# camada de cor por lado + raio do meio + faíscas (em cima do fundo, atrás do resto)
	_degrade_lados()
	if _raio.size() > 1 and _raio_t < 0.2:
		draw_polyline(_raio, Color(0.7, 0.85, 1.0, 0.25), 12.0, true)
		draw_polyline(_raio, Color(1, 1, 1, 0.8), 2.5, true)
	for f in _faiscas:
		var heroi: bool = f[0].x < size.x * 0.5
		var cor := Color(0.45, 0.75, 1.0) if heroi else Color(1.0, 0.55, 0.2)
		var pis := 0.55 + 0.45 * sin(_relogio * 6.0 + f[3])
		draw_circle(f[0], f[2] * 2.6, Color(cor, 0.12 * f[4] * pis))
		draw_circle(f[0], f[2], Color(cor.lightened(0.4), 0.85 * f[4] * pis))
	var o := _O()
	draw_set_transform(o)
	var k := _ease(_entra)
	_topo(k)
	for l in ["heroes", "monsters"]:
		_carta(l, k)
		_botao_lado(l, k)
		_grupo(l, k)
	_medalhao(k)
	_painel_chat(k)
	if _aviso_t > 0.0:
		var al := clampf(_aviso_t, 0.0, 1.0)
		var w := f_titulo.get_string_size(_aviso, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 48
		var ar := Rect2(PALCO.x / 2.0 - w / 2.0, 610 - 300, w, 46)
		_caixa(ar.grow(3), Color(CONTORNO, al), 18)
		_caixa(ar, Color(0.35, 0.08, 0.08, 0.96 * al), 16)
		_texto(Vector2(PALCO.x / 2.0, ar.position.y + 31), _aviso, 19, Color(1, 0.92, 0.85, al), true, 3)
	draw_set_transform(Vector2.ZERO)
	if _achou_t >= 0.0:
		_tela_duelo()
	if _comeco_t >= 0.0:
		_tela_comeco()

func _degrade_lados() -> void:
	var w := size.x
	var h := size.y
	var az := Color(0.1, 0.25, 0.7, 0.22)
	var vm := Color(0.6, 0.2, 0.05, 0.22)
	var cl := Color(0, 0, 0, 0)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.5, 0), Vector2(w * 0.5, h), Vector2(0, h)]),
		PackedColorArray([az, cl, cl, az]))
	draw_polygon(PackedVector2Array([Vector2(w * 0.5, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * 0.5, h)]),
		PackedColorArray([cl, vm, vm, cl]))
	# escurece em cima e embaixo (dá leitura para o texto)
	var pr := Color(0, 0, 0, 0.55)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, 110), Vector2(0, 110)]), PackedColorArray([pr, pr, cl, cl]))
	draw_polygon(PackedVector2Array([Vector2(0, h - 160), Vector2(w, h - 160), Vector2(w, h), Vector2(0, h)]), PackedColorArray([cl, cl, pr, pr]))

func _topo(k: float) -> void:
	var y := -60.0 * (1.0 - k)
	_botao(Rect2(18, 14 + y, 128, 50), "← MENU", Color("4a5fae"), _apertado == "menu")
	_botao(Rect2(RET_REPLAYS.position + Vector2(0, y), RET_REPLAYS.size), "▶ REPLAYS", Color("2fa84f"), _apertado == "replays")
	var t: String = TITULO[modo]
	var w := f_titulo.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x + 150
	var r := Rect2(PALCO.x / 2.0 - w / 2.0, 10 + y, w, 62)
	_caixa(Rect2(r.position + Vector2(0, 6), r.size), Color(0, 0, 0, 0.5), 22)
	_caixa(r.grow(3), CONTORNO, 24)
	_caixa(r, Color("3a2a0a"), 22)
	_caixa(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.48)), Color("6a4a12"), 22)
	_brasao("heroes", Vector2(r.position.x + 36, r.get_center().y), 34)
	_brasao("monsters", Vector2(r.end.x - 36, r.get_center().y), 34)
	_texto(Vector2(PALCO.x / 2.0, r.position.y + 47), t, 40, OURO, true, 6)
	_texto(Vector2(PALCO.x / 2.0, r.end.y + 24), SUB[modo], 15, Color(1, 0.95, 0.85, 0.85 * k), true, 3)

## A carta grande do lado (a imagem com contorno amarelo/verde). Tocar = entrar daquele lado.
func _carta(l: String, k: float) -> void:
	var r := _ret_carta(l)
	var cor: Color = BORDA[l]
	var sel := lado == l
	var lot := _lotado(l)
	var ap := _apertado == l or _apertado == "bt_" + l
	var s := (1.0 if l == "heroes" else -1.0)
	r.position.x -= s * 340.0 * (1.0 - k)
	if sel:
		r.position.y -= 8.0 * _ease(_escolha_t * 3.0)
	if ap:
		r.position.y += 3.0
	var pul := 0.5 + 0.5 * sin(_relogio * 3.0 + (0.0 if l == "heroes" else 1.6))
	# brilho atrás (forte quando é o seu lado)
	var brilho := 0.55 if sel else (0.22 + 0.12 * pul)
	if lot:
		brilho = 0.06
	for i in 4:
		_caixa(r.grow(6 + i * 7), Color(cor, brilho * (0.32 - i * 0.07)), 30 + i * 6)
	_caixa(Rect2(r.position + Vector2(0, 12), r.size), Color(0, 0, 0, 0.55), 26)
	_caixa(r.grow(5), CONTORNO, 28)
	_caixa(r.grow(2), cor.darkened(0.25), 26)
	_caixa(r, cor, 24)
	# a imagem, com cantos arredondados
	var dentro := r.grow(-7)
	var tex: Texture2D = _tex[l]
	var pts := _arredondado(dentro, 18.0)
	var ts := tex.get_size()
	var asp := dentro.size.x / dentro.size.y
	var src := Rect2(0, 0, ts.x, ts.x / asp) if ts.x / ts.y < asp else Rect2((ts.x - ts.y * asp) / 2.0, 0, ts.y * asp, ts.y)
	if src.size.y > ts.y:
		src = Rect2(0, 0, ts.x, ts.y)
	var uvs := PackedVector2Array()
	for p in pts:
		var q := (p - dentro.position) / dentro.size
		uvs.append((src.position + q * src.size) / ts)
	var cores := PackedColorArray()
	cores.resize(pts.size())
	cores.fill(Color(0.42, 0.42, 0.42) if lot else Color.WHITE)
	draw_polygon(pts, cores, uvs, tex)
	# escurece embaixo (para o nome) e um reflexo passando
	var baixo := Rect2(dentro.position.x, dentro.end.y - 150, dentro.size.x, 150)
	var cl := Color(0, 0, 0, 0)
	var es := Color(0, 0, 0, 0.88)
	var pb := Geometry2D.intersect_polygons(pts, PackedVector2Array([baixo.position, Vector2(baixo.end.x, baixo.position.y), baixo.end, Vector2(baixo.position.x, baixo.end.y)]))
	for poly in pb:
		var cs := PackedColorArray()
		for p in poly:
			cs.append(cl.lerp(es, clampf((p.y - baixo.position.y) / baixo.size.y, 0.0, 1.0)))
		draw_polygon(poly, cs)
	var fx := fmod(_relogio * 0.35 + (0.0 if l == "heroes" else 0.5), 1.0) * (dentro.size.x + 400.0) - 200.0
	var faixa := PackedVector2Array([Vector2(dentro.position.x + fx, dentro.position.y), Vector2(dentro.position.x + fx + 60, dentro.position.y),
		Vector2(dentro.position.x + fx - 60, dentro.end.y), Vector2(dentro.position.x + fx - 120, dentro.end.y)])
	for poly in Geometry2D.intersect_polygons(pts, faixa):
		draw_colored_polygon(poly, Color(1, 1, 1, 0.09))
	# nome do lado
	var nome := "HEROES" if l == "heroes" else "MONSTERS"
	var tn := 42
	while tn > 24 and f_titulo.get_string_size(nome, HORIZONTAL_ALIGNMENT_LEFT, -1, tn).x > r.size.x - 96:
		tn -= 2
	var nw := f_titulo.get_string_size(nome, HORIZONTAL_ALIGNMENT_LEFT, -1, tn).x
	_brasao(l, Vector2(r.get_center().x - nw / 2.0 - 4, r.end.y - 44), 34)
	_texto(Vector2(r.get_center().x + 18, r.end.y - 28), nome, tn, cor.lightened(0.15), true, 7)
	# quantos estão entrando (no canto de cima)
	var n := _do_lado(l).size()
	var etiqueta := ("%d / %d" % [mini(n, VAGAS), VAGAS]) if modo == "campeonato" else ("%d na fila" % n)
	var ew := f_titulo.get_string_size(etiqueta, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 54
	var er := Rect2(r.end.x - ew - 12, r.position.y + 14, ew, 40)
	_caixa(er.grow(3), CONTORNO, 20)
	_caixa(er, Color(0.05, 0.05, 0.1, 0.85), 18)
	_pessoinha(Vector2(er.position.x + 20, er.get_center().y), cor)
	_texto(Vector2(er.position.x + 36, er.position.y + 28), etiqueta, 22, Color.WHITE, false, 3)
	# seu lado / lotado
	if sel:
		var fr := Rect2(r.position.x + 14, r.position.y + 14, 128, 36)
		_caixa(fr.grow(3), CONTORNO, 16)
		_caixa(fr, OURO, 14)
		_texto(Vector2(fr.get_center().x, fr.position.y + 26), "SEU LADO", 19, CONTORNO, true, 0)
	if lot:
		draw_set_transform(_O() + r.get_center(), -0.35)
		var sr := Rect2(-130, -34, 260, 68)
		_caixa(sr.grow(4), Color(0.9, 0.15, 0.1, 0.9), 14)
		_caixa(sr, Color(0.25, 0.02, 0.02, 0.92), 12)
		_texto(Vector2(0, 16), "LOTADO", 44, Color(1, 0.35, 0.3), true, 5)
		draw_set_transform(_O())

func _pessoinha(c: Vector2, cor: Color) -> void:
	draw_circle(c + Vector2(0, -6), 5.0, cor)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-8, 9), c + Vector2(8, 9), c + Vector2(6, 1), c + Vector2(0, -1), c + Vector2(-6, 1)]), cor)

## Botão embaixo da carta: ENTRAR / VOCÊ ESTÁ AQUI / LOTADO.
func _botao_lado(l: String, k: float) -> void:
	var r := _ret_botao(l)
	r.position.y += 80.0 * (1.0 - k)
	var cor: Color = BORDA[l].darkened(0.1)
	var txt := "ENTRAR DE " + ("HEROES" if l == "heroes" else "MONSTERS")
	if lado == l:
		txt = "VOCÊ ESTÁ AQUI ✓" if modo == "campeonato" or _achou_t >= 0.0 else "PROCURANDO..."
		cor = Color("3aa33a")
	elif _lotado(l):
		txt = "LOTADO"
		cor = Color("6a6a6a")
	elif lado != "":
		txt = "TROCAR PARA " + ("HEROES" if l == "heroes" else "MONSTERS")
		cor = cor.darkened(0.35)
	if lado == "" and not _lotado(l):                  # chama a atenção enquanto ninguém escolheu
		var pul := 0.5 + 0.5 * sin(_relogio * 4.0 + (0.0 if l == "heroes" else 1.2))
		_caixa(r.grow(4 + pul * 4), Color(cor, 0.25), 22)
	_botao(r, txt, cor, _apertado == "bt_" + l, 22)
	# embaixo: as vagas
	var n := _do_lado(l).size()
	var info := ""
	if modo == "campeonato":
		info = "LOTADO" if n >= VAGAS else ("%d vaga%s livre%s" % [VAGAS - n, "" if VAGAS - n == 1 else "s", "" if VAGAS - n == 1 else "s"])
	else:
		info = "Ninguém esperando agora" if n == 0 else ("%d esperando para duelar" % n)
	_texto(Vector2(r.get_center().x, r.end.y + 30), info, 17, Color(1, 1, 1, 0.8 * k), true, 3)

## Medalhão do meio: relógio (campeonato: 2 minutos; duelo: procurando) ou o VS.
func _medalhao(k: float) -> void:
	var c := Vector2(PALCO.x / 2.0, 150)
	var pul := 0.5 + 0.5 * sin(_relogio * 3.0)
	var rr := 46.0 * (0.6 + 0.4 * k)
	draw_circle(c, rr + 16 + pul * 4, Color(OURO, 0.1))
	draw_circle(c, rr + 6, CONTORNO)
	draw_circle(c, rr + 2, Color("3a2a0a"))
	draw_circle(c, rr - 4, Color("15122a"))
	var prog := -1.0
	var txt := "VS"
	var linha := ""
	if modo == "campeonato":
		prog = clampf(falta / TEMPO_CAMP, 0.0, 1.0)
		txt = "%d:%02d" % [int(ceil(falta)) / 60, int(ceil(falta)) % 60]
		var total := gente.size()
		if lado == "":
			linha = "Escolha seu lado para entrar no campeonato"
		elif total >= 16:
			linha = "Sala completa! Começando..."
		else:
			linha = "%d de 16 na sala · começa ao lotar ou em %s" % [total, txt]
	elif lado == "":
		linha = "Escolha seu lado para duelar"
	elif _achou_t < 0.0:
		var lim := _limite
		prog = 1.0 - clampf(procura_t / lim, 0.0, 1.0)
		txt = str(maxi(1, int(ceil(lim - maxf(0.0, procura_t)))))
		var pontos := ".".repeat(1 + int(_relogio * 2.0) % 3)
		linha = "Procurando alguém dos %s%s" % ["MONSTERS" if lado == "heroes" else "HEROES", pontos]
	if prog >= 0.0:
		draw_arc(c, rr - 1, 0, TAU, 48, Color(1, 1, 1, 0.08), 7, true)
		draw_arc(c, rr - 1, -PI / 2, -PI / 2 + TAU * prog, 48, OURO if prog > 0.2 else Color("ff5a3a"), 7, true)
	_texto(c + Vector2(0, 12 if txt.length() > 2 else 16), txt, 32 if txt.length() > 2 else 44, Color.WHITE, true, 5)
	# linhas que saem para os lados
	for s: float in [-1.0, 1.0]:
		var x0 := c.x + s * (rr + 10)
		draw_line(Vector2(x0, c.y), Vector2(x0 + s * 120 * k, c.y), Color(OURO, 0.6), 3.0, true)
		draw_circle(Vector2(x0 + s * 124 * k, c.y), 4, OURO)
	_texto(Vector2(c.x, c.y + rr + 30), linha, 17, Color(1, 0.96, 0.85, k), true, 3)

## O grupo de um lado: quem está entrando (foto do Google ou retrato), separados Heroes | Monsters.
func _grupo(l: String, k: float) -> void:
	var r := _ret_grupo(l)
	r.position.y += 40.0 * (1.0 - k)
	var cor: Color = BORDA[l]
	_caixa(Rect2(r.position + Vector2(0, 6), r.size), Color(0, 0, 0, 0.45), 18)
	_caixa(r.grow(3), CONTORNO, 20)
	_caixa(r, Color(0.06, 0.06, 0.12, 0.86), 18)
	var cab := Rect2(r.position, Vector2(r.size.x, 42))
	_caixa(cab, Color(cor.darkened(0.55), 0.95), 18)
	draw_rect(Rect2(cab.position.x, cab.end.y - 3, cab.size.x, 3), cor)
	_brasao(l, Vector2(cab.position.x + 24, cab.get_center().y), 28)
	_texto(Vector2(cab.position.x + 44, cab.position.y + 29), "HEROES" if l == "heroes" else "MONSTERS", 21, cor.lightened(0.2), false, 3)
	var lista := _do_lado(l)
	lista.sort_custom(func(a, b): return a.get("eu", false) and not b.get("eu", false))
	var n := lista.size()
	var cont := ("%d/%d" % [mini(n, VAGAS), VAGAS]) if modo == "campeonato" else str(n)
	_texto(Vector2(cab.end.x - 16 - f_titulo.get_string_size(cont, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x, cab.position.y + 29), cont, 20, Color.WHITE, false, 3)
	# 2 colunas x 4 linhas
	var cel := Vector2((r.size.x - 20) / 2.0, 45)
	var mostra := mini(n, VAGAS)
	if n > VAGAS:
		mostra = VAGAS - 1
	for i in VAGAS:
		var c0 := Vector2(r.position.x + 10 + (i % 2) * cel.x, cab.end.y + 6 + (i / 2) * cel.y)
		var ac := c0 + Vector2(24, cel.y / 2.0)
		if i < mostra:
			var g: Dictionary = lista[i]
			var pop := _ease(clampf(g.t * 4.0, 0.0, 1.0))
			var raio := 19.0 * (0.4 + 0.6 * pop) + (1.5 if g.t < 0.25 else 0.0)
			if g.get("eu", false):
				draw_circle(ac, raio + 6 + sin(_relogio * 5.0) * 1.5, Color(OURO, 0.35))
			_avatar(ac, raio, g, Color(OURO) if g.get("eu", false) else cor)
			var nome := str(g.nome)
			if g.get("eu", false):
				nome = "Você"
			nome = _cortar(nome, 15, cel.x - 52)
			_texto(Vector2(c0.x + 50, ac.y + 6), nome, 15, Color(OURO if g.get("eu", false) else COR_NOME[l], pop), false, 2)
		elif i == mostra and n > VAGAS:
			_texto(Vector2(c0.x + cel.x / 2.0, ac.y + 7), "+%d" % (n - mostra), 20, Color.WHITE, true, 3)
		elif modo == "campeonato":                       # vaga vazia
			draw_arc(ac, 17, 0, TAU, 28, Color(1, 1, 1, 0.16), 2.0, true)
			_texto(ac + Vector2(0, 7), "?", 18, Color(1, 1, 1, 0.22), true, 0)
	if n == 0 and modo != "campeonato":
		_texto(Vector2(r.get_center().x, r.get_center().y + 20), "Ninguém por aqui agora", 15, Color(1, 1, 1, 0.45), true, 2)

## Foto redonda: Google (pessoa com conta), retrato do personagem, ou a inicial do nome.
## Anel grosso em volta do perfil de quem é PESSOA REAL (com um brilho pulsando por fora).
func _contorno_real(c: Vector2, raio: float, cor: Color) -> void:
	var pul := 0.5 + 0.5 * sin(_relogio * 5.0)
	draw_arc(c, raio + 22, 0, TAU, 64, Color(cor, 0.25 + 0.2 * pul), 10, true)
	draw_arc(c, raio + 13, 0, TAU, 64, CONTORNO, 16, true)
	draw_arc(c, raio + 13, 0, TAU, 64, cor, 11, true)
	draw_arc(c, raio + 15, PI * 1.1, PI * 1.6, 16, cor.lightened(0.5), 4, true)

func _avatar(c: Vector2, raio: float, g: Dictionary, cor: Color) -> void:
	draw_circle(c, raio + 3, CONTORNO)
	draw_circle(c, raio + 1.5, cor)
	var tex: Texture2D = null
	var reg := Rect2()
	if g.get("eu", false) and Conta.foto:
		tex = Conta.foto
	if tex == null:
		tex = _foto_url(str(g.get("foto", "")))
	if tex:
		var ts := tex.get_size()
		var lado_q := minf(ts.x, ts.y)
		reg = Rect2((ts.x - lado_q) / 2.0, (ts.y - lado_q) / 2.0, lado_q, lado_q)
	elif str(g.get("personagem", "")) != "":
		var rt := _retrato(str(g.personagem))
		if not rt.is_empty():
			tex = rt[0]
			var q: Rect2 = rt[1]
			reg = Rect2(q.position.x, q.position.y, q.size.x, q.size.x)
	if tex == null:
		draw_circle(c, raio, cor.darkened(0.5))
		_texto(c + Vector2(0, raio * 0.38), str(g.get("nome", "?")).substr(0, 1).to_upper(), int(raio * 1.1), Color.WHITE, true, 3)
		return
	draw_circle(c, raio, cor.darkened(0.6))
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var ts2 := tex.get_size()
	for i in 28:
		var a := TAU * i / 28.0
		var d := Vector2(cos(a), sin(a))
		pts.append(c + d * raio)
		uvs.append((reg.position + (d * 0.5 + Vector2(0.5, 0.5)) * reg.size) / ts2)
	var cs := PackedColorArray()
	cs.resize(28)
	cs.fill(Color.WHITE)
	draw_polygon(pts, cs, uvs, tex)

## CHAT DA SALA: as mensagens de quem está aqui agora (e quem entrou).
func _painel_chat(k: float) -> void:
	var r := _ret_chat()
	r.position.y += 60.0 * (1.0 - k)
	_caixa(Rect2(r.position + Vector2(0, 6), r.size), Color(0, 0, 0, 0.45), 18)
	_caixa(r.grow(3), CONTORNO, 20)
	_caixa(r, Color(0.05, 0.05, 0.11, 0.88), 18)
	var cab := Rect2(r.position, Vector2(r.size.x, 34))
	_caixa(cab, Color("2a2f63"), 18)
	_balao(Vector2(cab.position.x + 22, cab.get_center().y))
	_texto(Vector2(cab.position.x + 40, cab.position.y + 24), "CHAT DA SALA", 17, OURO, false, 3)
	var on := gente.size()
	var t_on := "%d na sala" % on
	draw_circle(Vector2(cab.end.x - 22 - f_titulo.get_string_size(t_on, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x - 10, cab.get_center().y), 5, Color("4fe05a"))
	_texto(Vector2(cab.end.x - 16 - f_titulo.get_string_size(t_on, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, cab.position.y + 23), t_on, 14, Color(1, 1, 1, 0.75), false, 2)
	# mensagens (de baixo para cima)
	var area := Rect2(r.position.x + 12, cab.end.y + 6, r.size.x - 24, _ret_campo().position.y - cab.end.y - 12)
	var y := area.end.y
	var tam := 15
	for i in range(chat.size() - 1, -1, -1):
		var m: Dictionary = chat[i]
		var linhas: Array
		var cab_txt := ""
		if m.sis:
			linhas = _quebrar("• " + str(m.texto), tam, area.size.x - 8)
		else:
			cab_txt = str(m.nome) + ": "
			linhas = _quebrar(cab_txt + str(m.texto), tam, area.size.x - 34)
		var alt := linhas.size() * 20.0 + 4.0
		if y - alt < area.position.y:
			break
		y -= alt
		var cor_nome: Color = COR_NOME.get(str(m.lado), Color("c8cdf5"))
		if m.sis:
			for j in linhas.size():
				_texto_s(Vector2(area.position.x + 4, y + 16 + j * 20), linhas[j], tam, Color(cor_nome, 0.85) if str(m.lado) != "" else Color(1, 1, 1, 0.55))
		else:
			_avatar(Vector2(area.position.x + 11, y + 11), 9.0, {"nome": m.nome, "foto": m.foto, "eu": m.eu, "personagem": ""}, cor_nome)
			for j in linhas.size():
				var ln: String = linhas[j]
				var px := area.position.x + 28
				if j == 0 and ln.begins_with(cab_txt):
					_texto_s(Vector2(px, y + 16), cab_txt, tam, OURO if m.eu else cor_nome)
					px += f_texto.get_string_size(cab_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
					ln = ln.substr(cab_txt.length())
				_texto_s(Vector2(px, y + 16 + j * 20), ln, tam, Color("eef0ff"))
	_botao(_ret_enviar(), "ENVIAR", Color("3aa33a") if online else Color("6a6a6a"), _apertado == "enviar", 18)

func _balao(c: Vector2) -> void:
	_caixa(Rect2(c - Vector2(10, 8), Vector2(20, 14)), Color.WHITE, 5)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 5), c + Vector2(2, 5), c + Vector2(-6, 11)]), Color.WHITE)

## TELA DO DUELO: o adversário apareceu! (você de um lado, ele do outro, VS no meio)
func _tela_duelo() -> void:
	var t := _achou_t
	var a := clampf(t * 3.0, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.78 * a))
	var o := _O()
	draw_set_transform(o)
	var meu_l := lado
	var outro := "monsters" if lado == "heroes" else "heroes"
	var esq := meu_l if meu_l == "heroes" else outro
	var k := _ease(t * 2.2)
	for l in [esq, "monsters" if esq == "heroes" else "heroes"]:
		var s := -1.0 if l == "heroes" else 1.0
		var c := Vector2(PALCO.x / 2.0 + s * (240.0 + 500.0 * (1.0 - k)), 330)
		var cor: Color = BORDA[l]
		var g: Dictionary = {"nome": _meu_nome(), "foto": "", "eu": true, "personagem": ""} if l == meu_l else _achou
		for i in 3:
			draw_circle(c, 120 + i * 16 + sin(_relogio * 4.0) * 3.0, Color(cor, 0.12 - i * 0.03))
		if not _sala.is_empty():                       # PESSOA REAL: contorno laranja (Heroes) / verde (Monsters)
			_contorno_real(c, 104, CONTORNO_REAL[l])
		_avatar(c, 104, g, cor)
		var nome := "Você" if l == meu_l else str(g.get("nome", "?"))
		_texto(Vector2(c.x, c.y + 156), nome, 34, COR_NOME[l] if l != meu_l else OURO, true, 6)
		_brasao(l, Vector2(c.x, c.y + 196), 34)
	var vk := _ease(clampf((t - 0.35) * 3.0, 0.0, 1.0))
	if vk > 0.0:
		var vc := Vector2(PALCO.x / 2.0, 330)
		draw_circle(vc, 64 * vk, CONTORNO)
		draw_circle(vc, 58 * vk, Color("c0392b"))
		_texto(vc + Vector2(0, 22 * vk), "VS", int(64 * vk) + 1, Color.WHITE, true, 6)
	_texto(Vector2(PALCO.x / 2.0, 120), "ADVERSÁRIO ENCONTRADO!", 46, Color(OURO, a), true, 7)
	_texto(Vector2(PALCO.x / 2.0, 160), "Prepare-se para o %s..." % ("cerco" if modo == "cerco" else "duelo"), 22, Color(1, 1, 1, 0.85 * a), true, 3)
	draw_set_transform(Vector2.ZERO)

func _tela_comeco() -> void:
	var t := _comeco_t
	var a := clampf(t * 3.0, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7 * a))
	var c := size / 2.0
	var k := _ease(t * 2.0)
	for i in 12:
		var ang := _relogio * 0.5 + i * TAU / 12.0
		draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(ang), sin(ang)) * 600 * k, c + Vector2(cos(ang + 0.12), sin(ang + 0.12)) * 600 * k]), Color(1, 0.85, 0.3, 0.06 * a))
	_texto(c + Vector2(0, -10), "SALA COMPLETA!", int(30 + 20 * k), Color(OURO, a), true, 7)
	_texto(c + Vector2(0, 40), "O campeonato vai começar", 26, Color(1, 1, 1, a), true, 4)

# ================================================================== AJUDANTES
func _botao(r: Rect2, txt: String, cor: Color, apertado := false, tam := 20) -> void:
	var rr := r
	if apertado:
		rr.position.y += 3
	_caixa(Rect2(r.position + Vector2(0, 5), r.size), Color(0, 0, 0, 0.45), 16)
	_caixa(rr.grow(3), CONTORNO, 16)
	_caixa(rr, cor.darkened(0.25), 14)
	_caixa(Rect2(rr.position, Vector2(rr.size.x, rr.size.y * 0.52)), cor.lightened(0.12), 14)
	_texto(Vector2(rr.get_center().x, rr.position.y + rr.size.y * 0.5 + tam * 0.38), txt, tam, Color.WHITE, true, 4)

func _caixa(r: Rect2, cor: Color, raio: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = cor
	sb.set_corner_radius_all(raio)
	sb.anti_aliasing = true
	draw_style_box(sb, r)

func _texto(pos: Vector2, txt: String, tam: int, cor: Color, centro: bool, contorno: int) -> void:
	var f := f_titulo
	if centro:
		pos.x -= f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x / 2.0
	if contorno > 0:
		draw_string_outline(f, pos + Vector2(0, 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, contorno + 2, Color(0, 0, 0, 0.35 * cor.a))
		draw_string_outline(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, contorno, Color(CONTORNO, cor.a))
	draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)

## Texto do chat (fonte de leitura, contorno fino).
func _texto_s(pos: Vector2, txt: String, tam: int, cor: Color) -> void:
	draw_string_outline(f_texto, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, 3, Color(0, 0, 0, 0.6 * cor.a))
	draw_string(f_texto, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)

func _quebrar(txt: String, tam: int, larg: float) -> Array:
	var linhas: Array = []
	var atual := ""
	for p in txt.split(" "):
		var teste := p if atual == "" else atual + " " + p
		if f_texto.get_string_size(teste, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x > larg and atual != "":
			linhas.append(atual)
			atual = p
		else:
			atual = teste
	if atual != "":
		linhas.append(atual)
	return linhas

func _cortar(txt: String, tam: int, larg: float) -> String:
	if f_titulo.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x <= larg:
		return txt
	while txt.length() > 1 and f_titulo.get_string_size(txt + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x > larg:
		txt = txt.substr(0, txt.length() - 1)
	return txt + "…"

func _arredondado(r: Rect2, raio: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cantos := [[r.position + Vector2(raio, raio), PI], [Vector2(r.end.x - raio, r.position.y + raio), PI * 1.5],
		[r.end - Vector2(raio, raio), 0.0], [Vector2(r.position.x + raio, r.end.y - raio), PI * 0.5]]
	for cc in cantos:
		for i in 7:
			var a: float = cc[1] + PI * 0.5 * i / 6.0
			pts.append(cc[0] + Vector2(cos(a), sin(a)) * raio)
	return pts

static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

func _foto_url(url: String) -> Texture2D:
	if url == "" or not url.begins_with("http"):
		return null
	if _fotos.has(url):
		return _fotos[url]
	_fotos[url] = null
	_baixar(url)
	return null

func _baixar(url: String) -> void:
	var h := HTTPRequest.new()
	add_child(h)
	if h.request(url) != OK:
		h.queue_free()
		return
	var res: Array = await h.request_completed
	h.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] >= 300:
		return
	var img := Image.new()
	var dados: PackedByteArray = res[3]
	if img.load_jpg_from_buffer(dados) != OK and img.load_png_from_buffer(dados) != OK and img.load_webp_from_buffer(dados) != OK:
		return
	_fotos[url] = ImageTexture.create_from_image(img)

## Retrato (cabeça) de um personagem: do 1º quadro da pose parada, medido uma vez.
func _retrato(id: String) -> Array:
	if _retratos.has(id):
		return _retratos[id]
	var r: Array = []
	var p: PersonagemDados = Catalogo.get_p(id)
	if p:
		var an := p.anim_qualquer(["parado", "defender", "andar"])
		if an and an.textura:
			var q := an.retangulo(0)
			var img := _img(an.textura)
			var u := Rect2(q)
			if img:
				u = Rect2(_area(img, Rect2i(q)))
			var cx := u.get_center().x
			if img:
				var faixa := _area(img, Rect2i(int(u.position.x), int(u.position.y + u.size.y * 0.06), int(u.size.x), int(maxf(4.0, u.size.y * 0.2))))
				cx = faixa.get_center().x
			var hgt := u.size.y * 0.42
			r = [an.textura, Rect2(cx - hgt / 2.0, u.position.y - hgt * 0.02, hgt, hgt)]
	_retratos[id] = r
	return r

func _img(tex: Texture2D) -> Image:
	var k := tex.resource_path
	if _imgs.has(k):
		return _imgs[k]
	var img := tex.get_image()
	if img and img.is_compressed():
		img.decompress()
	_imgs[k] = img
	return img

static func _area(img: Image, q: Rect2i) -> Rect2i:
	q = q.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var x0 := q.end.x; var y0 := q.end.y; var x1 := q.position.x; var y1 := q.position.y
	for y in range(q.position.y, q.end.y, 3):
		for x in range(q.position.x, q.end.x, 3):
			if img.get_pixel(x, y).a > 0.4:
				x0 = mini(x0, x); x1 = maxi(x1, x); y0 = mini(y0, y); y1 = maxi(y1, y)
	if x1 <= x0 or y1 <= y0:
		return q
	return Rect2i(x0, y0, x1 - x0 + 3, y1 - y0 + 3)

## Brasão (o mesmo do menu): escudo azul de Heroes ou caveira de olhos verdes de Monsters (caixa 40x40).
func _brasao(l: String, c: Vector2, tam: float, a := 1.0) -> void:
	var k := tam / 40.0
	var o := c - Vector2(20, 20) * k
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	if l == "monsters":
		var cab := PackedVector2Array()
		for i in 17:
			var ang := deg_to_rad(150) + (deg_to_rad(390) - deg_to_rad(150)) * i / 16.0
			cab.append(o + (Vector2(20, 16) + Vector2(cos(ang), sin(ang)) * 13) * k)
		cab.append_array([P.call(28, 25), P.call(28, 30), P.call(12, 30), P.call(12, 25)])
		draw_colored_polygon(cab, Color(0.91, 0.87, 0.78, a))
		cab.append(cab[0])
		draw_polyline(cab, Color(0.1, 0.07, 0.03, a), 2 * k, true)
		draw_circle(P.call(14.5, 17), 3.4 * k, Color(0.55, 0.88, 0.24, a))
		draw_circle(P.call(25.5, 17), 3.4 * k, Color(0.55, 0.88, 0.24, a))
		draw_colored_polygon(PackedVector2Array([P.call(20, 21), P.call(18, 25), P.call(22, 25)]), Color(0.1, 0.07, 0.03, a))
	else:
		var esc := PackedVector2Array([P.call(20, 3), P.call(34, 8), P.call(34, 18), P.call(33.3, 23), P.call(30.5, 28), P.call(26, 33), P.call(20, 37),
			P.call(14, 33), P.call(9.5, 28), P.call(6.7, 23), P.call(6, 18), P.call(6, 8)])
		draw_colored_polygon(esc, Color(0.16, 0.29, 0.61, a))
		esc.append(esc[0])
		draw_polyline(esc, Color(OURO, a), 2.5 * k, true)
		draw_line(P.call(20, 12), P.call(20, 29), Color(OURO, a), 2 * k, true)
		draw_line(P.call(14, 19), P.call(26, 19), Color(OURO, a), 2 * k, true)
