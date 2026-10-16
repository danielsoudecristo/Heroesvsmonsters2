extends "res://scripts/sistema/guia.gd"
## TUTORIAL DO MENU: na primeira vez que a pessoa chega no menu, mostra tudo com a mãozinha
## (perfil, campanha e dificuldades, PvP, personagens, ranking, ligas, bônus, social, opções)
## e termina levando para a primeira batalha. Dá para rever em Opções > Como jogar.

const C := preload("res://scripts/arena/config_arena.gd")

var intro: Node
var passos: Array = []
var i := 0
var _liga_tex := {}

func _ready() -> void:
	super._ready()
	principal.connect(_proximo)
	pulou.connect(_pular)
	tocou_alvo.connect(_tocou)

func comecar() -> void:
	f_titulo = intro.f_titulo
	f_texto = intro.f_texto
	_montar()
	i = 0
	Conta.registrar("tutorial", {"parte": "menu", "evento": "comecou"})
	_mostrar()

func _montar() -> void:
	var lado_txt := "Monsters" if Perfil.lado == "monsters" else "Heroes"
	passos = [
		{"titulo": "Bem-vindo, guerreiro!", "bt": "Vamos lá!", "largura": 520.0,
		 "texto": "Em Heroes vs Monsters você protege o seu castelo das ondas de inimigos. Vou te mostrar tudo em 1 minutinho.",
		 "extra": _ilu_brasoes, "extra_h": 92.0},
		{"titulo": "Este é você", "alvo": func(): return intro._ret_perfil(), "mao": true,
		 "texto": "Aqui ficam seu nome, seu lado (%s), seus troféus, suas moedas e sua liga." % lado_txt,
		 "extra": _ilu_trofeu_moeda, "extra_h": 64.0},
		{"titulo": "Novo jogo: a campanha", "alvo": func(): return intro._ret_botao(0), "mao": true, "largura": 520.0,
		 "texto": "Enfrente ondas de inimigos, nível depois de nível. A campanha não tem fim: bata o seu recorde! Escolha a dificuldade:",
		 "extra": _ilu_dificuldades, "extra_h": 64.0},
		{"titulo": "Batalha PvP", "alvo": func(): return intro._ret_botao(1), "mao": true,
		 "texto": "Dois modos: BATALHA, ao vivo contra outra pessoa (vale troféus), e CERCO, em 2 rodadas: na primeira você defende com seus personagens firmes no lugar, na segunda você ataca. Vence quem derrubar o castelo do outro mais rápido!", "largura": 540.0},
		{"titulo": "Personagens", "alvo": func(): return intro._ret_botao(2), "mao": true,
		 "texto": "Use suas moedas para evoluir cada herói e monstro até o nível 15. Cada nível dá +8% de vida e de dano.",
		 "extra": _ilu_niveis, "extra_h": 56.0},
		{"titulo": "Ranking", "alvo": func(): return intro._ret_botao(3), "mao": true,
		 "texto": "Veja os melhores do jogo em vitórias, troféus e recorde da campanha. Seu nome também aparece lá!"},
		{"titulo": "Ligas", "alvo": func(): return intro._ret_botao(3), "mao": false, "largura": 640.0, "lado": "cima",
		 "texto": "Seus troféus definem a sua liga. Todo mundo começa no Bronze. Até onde você chega?",
		 "extra": _ilu_ligas, "extra_h": 108.0},
		{"titulo": "Bônus do dia", "alvo": func(): return intro._ret_bonus(), "mao": true,
		 "texto": "Todo dia um lado fica em alta: jogando com ele, você ganha +50% de moedas. Jogou com os dois lados no mesmo dia? Mais +150!"},
		{"titulo": "Amigos e duelos", "alvo": _ret_social,
		 "redondo": true, "mao": true,
		 "texto": "Adicione amigos, converse e desafie para duelos apostando moedas e troféus. A bolinha vermelha avisa quando chega algo novo."},
		{"titulo": "Convide e ganhe!", "alvo": func(): return intro._ret_convidar(), "mao": true, "largura": 500.0,
		 "texto": "Mande seu código para os amigos. Eles ganham +200 moedas, viram seus amigos no jogo, e você ganha até +400 moedas por cada um!",
		 "extra": _ilu_convite, "extra_h": 70.0},
		{"titulo": "Opções", "alvo": func(): return intro._ret_botao(4), "mao": true,
		 "texto": "Som e música, sua conta (entre com o Google para salvar o progresso) e \"Como jogar\", para ver este tutorial de novo."},
		{"titulo": "Heroes ou Monsters?", "alvo": func(): return intro._ret_botao(5), "mao": true,
		 "texto": "Troque de lado quando quiser. Cada lado tem seus próprios personagens e seu jeito de lutar."},
		{"titulo": "Hora da primeira batalha!", "alvo": func(): return intro._ret_botao(0), "mao": true, "bt": "",
		 "texto": "Toque em Novo jogo para começar.", "acao": "novo"},
		{"titulo": "Escolha a dificuldade", "alvo": func(): return _carta_dif(0), "mao": true, "bt": "", "deixar": true,
		 "bloquear": false, "lado": "direita", "mao_ponto": func(): return _carta_dif(0).end - Vector2(_carta_dif(0).size.x / 2.0, 40),
		 "texto": "Para começar, o Fácil é o ideal. Toque em Jogar. Você pode mudar depois.", "acao": "dif"},
	]
	total = passos.size()

func _ret_social() -> Rect2:
	var c: Vector2 = intro._centro_social()
	return Rect2(c - Vector2(34, 34), Vector2(68, 68))

func _carta_dif(n: int) -> Rect2:
	var d: Node = intro.dificuldade
	return d._ret_carta(n) if d else Rect2()

func _mostrar() -> void:
	var p: Dictionary = passos[i]
	var cfg := p.duplicate()
	if p.has("alvo"):
		cfg.alvo = (p.alvo as Callable).call()
	if p.has("mao_ponto"):
		cfg.mao_ponto = (p.mao_ponto as Callable).call()
	passo = i
	mostrar(cfg)
	if p.get("acao", "") == "novo":                  # daqui em diante já conta como visto
		Perfil.tutorial_menu = true
		Perfil.salvar()

var _pausado := false
func _process(dt: float) -> void:
	var atu = intro.atualizacao
	if ativo and atu and atu.bloqueando():           # janela de atualização por cima: o tutorial espera
		esconder()
		_pausado = true
	elif _pausado and not (atu and atu.bloqueando()):
		_pausado = false
		_mostrar()
	if ativo:
		palco_offset = intro.O
		var p: Dictionary = passos[i]
		if p.has("alvo"):                             # os cantos mudam com o tamanho da tela
			mover_alvo((p.alvo as Callable).call(), (p.mao_ponto as Callable).call() if p.has("mao_ponto") else Vector2.INF)
		if p.get("acao", "") == "dif" and _desde > 0.6 and not intro.dificuldade.visible:
			_fim(false)                               # fechou a janela da dificuldade
	super._process(dt)

func _proximo() -> void:
	intro._clique(false)
	if i + 1 >= passos.size():
		_fim(false)
		return
	i += 1
	_mostrar()

func _tocou(_p: Vector2) -> void:
	var p: Dictionary = passos[i]
	match p.get("acao", ""):
		"novo":
			intro._apertar(0)                         # abre a janela da dificuldade
			i += 1
			get_tree().create_timer(0.35).timeout.connect(_mostrar)
			esconder()
		"dif":
			pass                                      # a janela da dificuldade cuida (e começa a campanha)

func _pular() -> void:
	intro._clique(false)
	Conta.registrar("tutorial", {"parte": "menu", "evento": "pulou", "passo": i})
	_fim(true)

func _fim(pulou_: bool) -> void:
	if not pulou_:
		Conta.registrar("tutorial", {"parte": "menu", "evento": "terminou"})
	Perfil.tutorial_menu = true
	Perfil.salvar()
	esconder()

# =================================================================== ILUSTRAÇÕES DO BALÃO
func _ilu_brasoes(r: Rect2) -> void:
	intro._ci = self
	var c := r.get_center()
	intro._brasao("heroes", c + Vector2(-90, 0), 70.0)
	intro._brasao("monsters", c + Vector2(90, 0), 70.0)
	texto_contorno(Vector2(c.x, c.y + 12), "VS", 34, Color("ffd34d"), f_titulo, true, 6)

func _ilu_convite(r: Rect2) -> void:
	intro._ci = self
	var c := r.get_center()
	intro._presente(Vector2(r.position.x + 40, c.y + 4), 60.0, _t)
	var itens := [["+200", "para o amigo"], ["+100", "na hora"], ["+300", "quando ele jogar"]]
	var w := (r.size.x - 90) / 3.0
	for k in 3:
		var x := r.position.x + 86 + w * k + w / 2.0
		intro._moeda(Vector2(x - 30, c.y - 8), 22)
		texto_contorno(Vector2(x - 16, c.y + 0), itens[k][0], 22, Color("ffd34d"), f_titulo, false, 5)
		var tw := f_texto.get_string_size(itens[k][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(f_texto, Vector2(x - tw / 2.0, c.y + 26), itens[k][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ffd0e8"))

func _ilu_trofeu_moeda(r: Rect2) -> void:
	intro._ci = self
	var y := r.position.y + 22
	intro._trofeu(Vector2(r.position.x + 14, y), 26)
	draw_string(f_texto, Vector2(r.position.x + 36, y + 7), "Troféus: você ganha vencendo no PvP", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("ffe7a6"))
	y += 32
	intro._moeda(Vector2(r.position.x + 14, y), 26)
	draw_string(f_texto, Vector2(r.position.x + 36, y + 7), "Moedas: para evoluir seus personagens", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("ffe7a6"))

func _ilu_dificuldades(r: Rect2) -> void:
	var n := C.ORDEM_DIFICULDADES.size()
	var gap := 8.0
	var w := (r.size.x - gap * (n - 1)) / n
	for k in n:
		var d: Dictionary = C.DIFICULDADES[C.ORDEM_DIFICULDADES[k]]
		var cor: Color = d.cor
		var b := Rect2(r.position.x + k * (w + gap), r.position.y + 4, w, r.size.y - 8)
		_caixa(b.grow(2), CONTORNO, 14)
		_degrade_caixa(b, cor.lightened(0.35), cor.darkened(0.15), 12)
		texto_contorno(Vector2(b.get_center().x, b.position.y + 26), d.nome, 19, Color.WHITE, f_titulo, true, 5)
		var mv := float(d.moedas)
		var t := "moedas ×%s" % (str(int(mv)) if is_equal_approx(mv, roundf(mv)) else str(mv).replace(".", ","))
		var tw := f_texto.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(f_texto, Vector2(b.get_center().x - tw / 2.0, b.end.y - 9), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.92))

func _ilu_niveis(r: Rect2) -> void:
	var b := Rect2(r.position.x, r.position.y + 14, r.size.x, 22)
	_caixa(b.grow(2), CONTORNO, 11)
	_caixa(b, Color("1a1f40"), 10)
	var k := 0.5 + 0.5 * sin(_t * 1.6)
	var cheio := Rect2(b.position, Vector2(maxf(22.0, b.size.x * (0.08 + 0.92 * k)), b.size.y))
	_degrade_caixa(cheio, Color("eaffb0"), Color("2f9d16"), 10)
	var nv := 1 + int(round(k * 14.0))
	texto_contorno(Vector2(b.get_center().x, b.position.y + 18), "Nível %d  ·  +%d%% de força" % [nv, (nv - 1) * 5], 16, Color.WHITE, f_titulo, true, 5)
	draw_string(f_texto, Vector2(b.position.x, b.end.y + 20), "NV 1", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))
	var tw := f_texto.get_string_size("NV 15", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(f_texto, Vector2(b.end.x - tw, b.end.y + 20), "NV 15", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))

func _ilu_ligas(r: Rect2) -> void:
	var ligas: Array = Perfil.LIGAS
	var n := ligas.size()
	var w := r.size.x / n
	var minha := Perfil.liga()
	for k in n:
		var lg: Dictionary = ligas[k]
		var c := Vector2(r.position.x + w * k + w / 2.0, r.position.y + 34)
		if lg.nome == minha.nome:
			var pul := 0.5 + 0.5 * sin(_t * 4.0)
			draw_circle(c, 34.0 + pul * 3.0, Color(1, 0.85, 0.3, 0.25))
		var tex: Texture2D = _tex_liga(lg)
		if tex:
			var s := 56.0 / maxf(tex.get_width(), tex.get_height())
			var tam := Vector2(tex.get_width(), tex.get_height()) * s
			draw_texture_rect(tex, Rect2(c - tam / 2.0, tam), false)
		else:
			draw_circle(c, 22.0, lg.cor)
		var nome: String = lg.nome
		var tw := f_texto.get_string_size(nome, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(f_texto, Vector2(c.x - tw / 2.0, r.position.y + 82), nome, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ffe7a6"))
		var mt := str(int(lg.min))
		var mw := f_texto.get_string_size(mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(f_texto, Vector2(c.x - mw / 2.0, r.position.y + 100), mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.55))
		if k < n - 1:
			var ax := r.position.x + w * (k + 1)
			draw_colored_polygon(PackedVector2Array([Vector2(ax - 4, c.y - 6), Vector2(ax + 4, c.y), Vector2(ax - 4, c.y + 6)]), Color(1, 1, 1, 0.35))

func _tex_liga(lg: Dictionary) -> Texture2D:
	var k: String = lg.img
	if not _liga_tex.has(k):
		var c := "res://assets/liga/%s.png" % k
		_liga_tex[k] = load(c) if ResourceLoader.exists(c) else null
	return _liga_tex[k]
