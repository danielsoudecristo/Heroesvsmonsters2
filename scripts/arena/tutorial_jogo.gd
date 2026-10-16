extends "res://scripts/sistema/guia.gd"
## PRIMEIRA BATALHA GUIADA (campanha, nível 1, só na primeira vez).
## Segura a campanha (arena.segurar) e ensina com a mãozinha: pegar energia, colocar a Elara,
## colocar um guerreiro, ver ele lutar e entender as barras. No fim solta o nível 1 normal.

const C := preload("res://scripts/arena/config_arena.gd")
const HUD := preload("res://scripts/arena/hud.gd")
const CASA_ELARA := Vector2i(0, 2)
const CASA_GUERREIRO := Vector2i(2, 2)
const GUERREIRO := "arqueiro"

var arena: Node
var i := 0
var _orbe: Dictionary = {}
var _monstro: Node = null
var _espera := 0.0
var _passos: Array = []

func _ready() -> void:
	super._ready()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = Vector2(C.W, C.H)                         # (no CanvasLayer não tem pai Control: o tamanho é o do palco)
	margem = 700.0
	principal.connect(_proximo)
	pulou.connect(_pular)

func comecar() -> void:
	f_titulo = arena.hud.f_titulo
	f_texto = arena.hud.f_texto
	arena.segurar = true
	arena.lbl_banner.visible = false
	arena.banner_t = 0.0
	_passos = ["inicio", "energia", "painel", "carta_elara", "casa_elara", "elara_ok", "carta_guerreiro", "casa_guerreiro",
		"luta", "castelo", "horda", "cartas", "fim"]
	total = _passos.size()
	Conta.registrar("tutorial", {"parte": "jogo", "evento": "comecou"})
	_ir(0)

func _idx(id: String) -> int:
	for k in arena.cartas_dados.size():
		if arena.cartas_dados[k].id == id:
			return k
	return 0

func _ret_casa(c: Vector2i) -> Rect2:
	return Rect2(C.G.left + c.x * C.G.cw, C.G.top + c.y * C.G.ch, C.G.cw, C.G.ch)

func _ret_carta(k: int) -> Rect2:
	return arena.hud._ret_carta(k)

func _garantir_energia(n: int) -> void:
	if arena.energia < n:
		arena.energia = n

func _ir(n: int) -> void:
	i = n
	passo = n
	_espera = 0.0
	var id: String = _passos[i]
	var hud: Node = arena.hud
	match id:
		"inicio":
			mostrar({"titulo": "Sua primeira batalha!", "bt": "Começar", "largura": 540.0,
				"texto": "Os monstros entram pela direita e querem chegar ao seu castelo, aqui na esquerda. Coloque heróis no campo para barrar o caminho deles!"})
		"energia":
			var x := C.cel_x(5)
			_orbe = {"pos": Vector2(x, -30), "x0": x, "alvo_y": C.linha_y(1) - 20, "valor": 25, "t": 0.0, "voa": false, "fixo": true}
			arena.orbes.append(_orbe)
			mostrar({"titulo": "Pegue a energia!", "bt": "", "alvo": _ret_orbe(), "redondo": true, "mao": true, "lado": "esquerda",
				"texto": "De vez em quando cai energia do céu. Toque nela para pegar. Seja rápido: se demorar, ela some!"})
		"painel":
			mostrar({"titulo": "Sua energia", "bt": "Entendi", "alvo": HUD.PAINEL, "mao": false, "lado": "direita",
				"texto": "A energia fica guardada aqui. Cada herói custa energia para entrar no campo."})
		"carta_elara":
			hud.guardado = false
			arena.carta_sel = -1
			_garantir_energia(arena.cartas_dados[_idx("elara")].custo)
			mostrar({"titulo": "Elara, a geradora", "bt": "", "alvo": _ret_carta(_idx("elara")), "mao": true, "lado": "cima",
				"texto": "A Elara não luta: ela cria energia sozinha. Toque na carta dela."})
		"casa_elara":
			mostrar({"titulo": "Coloque no campo", "bt": "", "alvo": _ret_casa(CASA_ELARA), "mao": true, "lado": "direita",
				"texto": "Agora toque nesta casa. Geradores ficam melhor lá atrás, perto do castelo, longe dos monstros."})
		"elara_ok":
			mostrar({"titulo": "Muito bem!", "bt": "Continuar", "alvo": _ret_casa(CASA_ELARA), "mao": false, "lado": "direita", "escuro": 0.45,
				"texto": "Quando a Elara soltar energia, toque para pegar também. Energia é tudo nesta guerra!"})
		"carta_guerreiro":
			hud.guardado = false
			arena.carta_sel = -1
			_garantir_energia(arena.cartas_dados[_idx(GUERREIRO)].custo)
			mostrar({"titulo": "Hora de lutar", "bt": "", "alvo": _ret_carta(_idx(GUERREIRO)), "mao": true, "lado": "cima",
				"texto": "Um monstro vai chegar pela linha do meio. Escolha o Arqueiro: ele atira flechas de longe."})
		"casa_guerreiro":
			mostrar({"titulo": "Na linha do monstro", "bt": "", "alvo": _ret_casa(CASA_GUERREIRO), "mao": true, "lado": "direita",
				"texto": "Coloque aqui. Cada herói só ataca os monstros da MESMA linha."})
		"luta":
			_monstro = arena.criar_unidade("esqueleto", "monsters", CASA_GUERREIRO.y, -1, 1)
			mostrar({"titulo": "Lá vem ele!", "bt": "", "alvo": Rect2(), "mao": false, "lado": "topo", "escuro": 0.0,
				"bloquear": false, "pular": true, "largura": 520.0,
				"texto": "Seus heróis atacam sozinhos. Olhe o Arqueiro trabalhando!"})
		"castelo":
			mostrar({"titulo": "Vida do castelo", "bt": "Próximo", "alvo": HUD.BARRA, "mao": false, "lado": "cima",
				"texto": "Se um monstro chegar ao castelo, ele perde vida. Se a vida acabar, você perde o nível."})
		"horda":
			mostrar({"titulo": "As ondas chegando", "bt": "Próximo", "alvo": Rect2(HUD.HORDA.position, Vector2(HUD.ESPIAR.end.x - HUD.HORDA.position.x, HUD.HORDA.size.y)), "mao": false, "lado": "cima",
				"texto": "A caveira anda até o seu castelo conforme o nível avança. Cada bandeira é uma onda nova; a grande é a horda final. Chegou ao fim? Você venceu!"})
		"espiar":
			mostrar({"titulo": "Espiar", "bt": "Próximo", "alvo": HUD.ESPIAR, "mao": false, "lado": "cima",
				"texto": "Por 50 de energia, você vê quais monstros vão vir e prepara a defesa certa."})
		"cartas":
			mostrar({"titulo": "Suas cartas", "bt": "Próximo", "alvo": HUD.PAINEL, "mao": true, "lado": "direita",
				"texto": "Toque no painel de energia para mostrar ou esconder as cartas. Toque num herói do campo para mandar ele parar, andar, voltar ou usar os poderes. Dois toques rápidos tiram ele da arena."})
		"fim":
			mostrar({"titulo": "Você está pronto!", "bt": "Jogar!", "largura": 540.0,
				"texto": "Vença as ondas para ganhar moedas e evoluir seus personagens. Atenção: cada nível começa com o campo limpo, então monte seu time de novo pegando as energias. Boa sorte!"})

func _ret_orbe() -> Rect2:
	var p: Vector2 = _orbe.get("pos", Vector2(-999, -999))
	return Rect2(p - Vector2(40, 40), Vector2(80, 80))

func _process(dt: float) -> void:
	if not ativo:
		super._process(dt)
		return
	_espera += dt
	var hud: Node = arena.hud
	match _passos[i]:
		"energia":
			if _orbe.get("voa", false) or not arena.orbes.has(_orbe):
				if _espera > 0.0 and not _orbe.get("_ok", false):
					_orbe["_ok"] = true
					_espera = -0.7                         # deixa ver a energia voando para o painel
				if _espera >= 0.0:
					_ir(i + 1)
			else:
				mover_alvo(_ret_orbe())
		"carta_elara", "carta_guerreiro":
			var k := _idx("elara" if _passos[i] == "carta_elara" else GUERREIRO)
			if hud.guardado:
				hud.guardado = false
			mover_alvo(_ret_carta(k))
			if arena.carta_sel == k:
				_ir(i + 1)
		"casa_elara", "casa_guerreiro":
			var casa := CASA_ELARA if _passos[i] == "casa_elara" else CASA_GUERREIRO
			if arena.casas[casa.x][casa.y] != null:
				hud.guardado = true
				_ir(i + 1)
			elif arena.carta_sel < 0:                      # desistiu da carta: volta um passo
				_ir(i - 1)
		"luta":
			if _monstro == null or not is_instance_valid(_monstro) or _monstro.morto:
				if _espera < 900.0:
					_espera = 1000.0
				if _espera > 1001.2:
					_ir(i + 1)
	super._process(dt)

func _proximo() -> void:
	Sons.tocar("Jogo/som/clique", 0.5)
	if _passos[i] == "fim":
		_terminar(false)
		return
	_ir(i + 1)

func _pular() -> void:
	Conta.registrar("tutorial", {"parte": "jogo", "evento": "pulou", "passo": _passos[i]})
	_terminar(true)

func _terminar(pulou_: bool) -> void:
	if not pulou_:
		Conta.registrar("tutorial", {"parte": "jogo", "evento": "terminou"})
	Perfil.tutorial_jogo = true
	Perfil.salvar()
	esconder()
	arena.hud.guardado = false
	arena.tutorial_acabou()
	queue_free()
