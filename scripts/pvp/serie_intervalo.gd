extends Control
## INTERVALO DA SÉRIE (Batalha online que vale troféus — 28_serie_pvp.sql): acabou uma partida e a série continua.
## Mostra quem venceu essa partida, o PLACAR da série e o lado da próxima (trocado na 2ª, sorteado no desempate),
## conta 8 segundos e entra sozinho na próxima partida, contra a mesma pessoa.

const W := 1280.0
const CONTORNO := Color("24130a")
const COR_LADO := {"heroes": [Color("ffe98a"), Color("f6c343"), Color("b8740f")], "monsters": [Color("d9ff9a"), Color("8be03c"), Color("3f8f1a")]}
const ESPERA := 8.0

var f_titulo: Font
var f_texto: Font
var venci_partida := false
var empate_partida := false
var jogo_que_acabou := 1
var meus_pontos := 0
var pontos_dele := 0
var nome_dele := "Adversário"
var proxima: Dictionary = {}           # sala_json da próxima partida
var ao_sair: Callable                  # sair = perder a série (W.O. na próxima)
var bot := false                       # SÉRIE CONTRA O BOT: não tem sala no servidor
var proximo_lado := ""                 # (bot) o lado da próxima partida
var ao_entrar: Callable                # (bot) entra na próxima partida com o lado
var _t := 0.0
var _entrando := false
var _proximo_lado := "heroes"
var _bt_sair := Rect2()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	if bot:
		_proximo_lado = proximo_lado
		return
	var meu_id: String = get_node("/root/Conta").meu_id()
	_proximo_lado = "heroes" if str(proxima.get("heroes", "")) == meu_id else "monsters"

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()
	if _t >= ESPERA and not _entrando:
		_entrar()

func _entrar() -> void:
	_entrando = true
	if bot:
		ao_entrar.call(_proximo_lado)
		return
	var conta: Node = get_node("/root/Conta")
	var token: String = await conta.token_fresco()
	var s := proxima.duplicate()
	s["token"] = token
	s["lado"] = _proximo_lado
	Perfil.pvp_adversario = nome_dele
	Perfil.pvp_sala = s
	Perfil.pvp_modo = "normal"
	Perfil.lado = _proximo_lado
	Perfil.salvar()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://cenas/pvp.tscn")

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if _bt_sair.has_point(get_local_mouse_position()) and ao_sair.is_valid() and not _entrando:
			_entrando = true                           # sair = W.O. na próxima partida: o outro leva a série
			if bot:
				ao_sair.call()
				return
			var outro := "monsters" if _proximo_lado == "heroes" else "heroes"
			get_node("/root/Conta").chamar("finalizar_pvp", {"p_sala": str(proxima.get("id", "")), "p_vencedor": outro, "p_resumo": "wo"})
			ao_sair.call()

# ------------------------------------------------------------------ desenho
func _draw() -> void:
	var a := clampf(_t * 3.0, 0.0, 1.0)
	draw_rect(preload("res://scripts/arena/config_arena.gd").tela_toda(self), Color(0.02, 0.02, 0.07, 0.94 * a))
	var c := W / 2.0
	var k := _ease_back(_t * 2.2)
	# 1) resultado desta partida
	var tit := "EMPATE" if empate_partida else ("VOCÊ VENCEU!" if venci_partida else "VOCÊ PERDEU")
	var cor_t := Color("fff4d6") if empate_partida else (Color("ffd34d") if venci_partida else Color("ff8a7a"))
	_texto(Vector2(c, 70), "PARTIDA %d DA SÉRIE" % jogo_que_acabou, 24, Color("c9d2ff"), f_texto, 6)
	draw_set_transform(Vector2(c, 130) * (1.0 - k), 0.0, Vector2(k, k))
	_texto(Vector2(c, 130), tit, 62, cor_t, f_titulo, 14)
	draw_set_transform(Vector2.ZERO)
	# 2) placar da série
	var y := 255.0
	_placa(Rect2(c - 330, y - 70, 660, 150))
	_texto(Vector2(c - 170, y - 22), "VOCÊ", 26, Color("fff6d0"), f_titulo, 6)
	_texto(Vector2(c + 170, y - 22), nome_dele.left(14), 26, Color("fff6d0"), f_titulo, 6)
	var pulo := sin(clampf(_t * 1.6 - 0.5, 0.0, 1.0) * PI) * 10.0
	_texto(Vector2(c - 170, y + 52 - pulo * (1.0 if venci_partida else 0.0)), str(meus_pontos), 70, Color("ffd34d"), f_titulo, 12)
	_texto(Vector2(c + 170, y + 52 - pulo * (0.0 if venci_partida or empate_partida else 1.0)), str(pontos_dele), 70, Color("ffd34d"), f_titulo, 12)
	_texto(Vector2(c, y + 40), "x", 46, Color("dfe4ff"), f_titulo, 8)
	# 3) regra e o lado da próxima
	var desempate := int(proxima.get("jogo", 2)) >= 3
	var regra := "DESEMPATE! Partida 3 · lado sorteado" if desempate else "Agora os lados TROCAM"
	_texto(Vector2(c, 420), regra, 30, Color("ffd34d") if desempate else Color.WHITE, f_titulo, 8)
	var cores: Array = COR_LADO[_proximo_lado]
	var faixa := Rect2(c - 250, 448, 500, 64)
	_caixa(faixa.grow(4), CONTORNO, 22)
	_degrade(faixa, cores[0], cores[2], 20)
	_texto(Vector2(c, 491), "VOCÊ DE %s" % ("HEROES" if _proximo_lado == "heroes" else "MONSTERS"), 32, Color.WHITE, f_titulo, 8)
	_texto(Vector2(c, 548), "Troféu só para quem vencer de Heroes E de Monsters", 19, Color("c9d2ff"), f_texto, 5)
	# 4) contagem e sair
	var falta := maxi(0, ceili(ESPERA - _t))
	_texto(Vector2(c, 612), "Começando..." if _entrando else "A próxima começa em %d" % falta, 28, Color("fff4d6"), f_titulo, 7)
	_bt_sair = Rect2(W - 300, 650, 270, 48)
	_caixa(_bt_sair.grow(3), CONTORNO, 16)
	_degrade(_bt_sair, Color("9fb0f0"), Color("4a5fae"), 14)
	_texto(Vector2(_bt_sair.get_center().x, _bt_sair.position.y + 32), "Sair (perde a série)", 19, Color.WHITE, f_titulo, 5)

func _placa(r: Rect2) -> void:
	_caixa(Rect2(r.position + Vector2(0, 8), r.size).grow(5), Color(0, 0, 0, 0.4), 30)
	_caixa(r.grow(5), CONTORNO, 30)
	_caixa(r.grow(2), Color("f6c343"), 28)
	_degrade(r, Color("3e4f96"), Color("1b2350"), 26)

func _caixa(r: Rect2, cor: Color, raio: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = cor
	sb.set_corner_radius_all(raio)
	draw_style_box(sb, r)

func _degrade(r: Rect2, c1: Color, c2: Color, raio: int) -> void:
	_caixa(r, c2, raio)
	_caixa(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)), c1.lerp(c2, 0.2), raio)

func _texto(pos: Vector2, txt: String, tam: int, cor: Color, f: Font, contorno := 8) -> void:
	var x := pos.x - f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x / 2.0
	draw_string_outline(f, Vector2(x, pos.y + 3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, contorno + 4, Color(0, 0, 0, 0.3))
	draw_string_outline(f, Vector2(x, pos.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, contorno, CONTORNO)
	draw_string(f, Vector2(x, pos.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)

static func _ease_back(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
