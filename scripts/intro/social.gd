extends Control
## SOCIAL (botão redondo no canto do menu): amigos, conversa particular, chat geral, adicionar amigo e DUELO.
## - O número no botão = mensagens não lidas + pedidos de amizade + convites de duelo (grande e pulando quando tem algo).
##   Sem nada novo, mostra (em verde) quantos amigos estão online.
## - DUELO: você chama um amigo; ele recebe um aviso na tela (Aceitar / Recusar); aceitou = PvP online sem troféus.
## - ECONOMIA do servidor: nada aqui usa o Realtime. O jogo pergunta só de vez em quando (no menu a cada 10 s;
##   conversa aberta a cada 3 s; chat geral a cada 4 s). Servidor: supabase/14_social_godot.sql (+ 3_social.sql).

const JANELA := Rect2(100, 40, 1080, 650)
const LISTA := Rect2(140, 128, 1000, 470)          ## área que rola
## A 3ª é um BOTÃO (verde): abre os REPLAYS (36_replays.sql) — as batalhas suas e dos amigos das últimas 24 h.
const ABAS := [["amigos", "Amigos"], ["chat", "Chat geral"], ["replays", "▶ Replays"]]
const CADA_RESUMO := 10.0
const CADA_CONVERSA := 3.0
const CADA_CHAT := 4.0
const CADA_AMIGOS := 10.0
const DUELO_TEMPO := 90.0

var intro: Node
var aba := "amigos"
var conversa_com := {}                              # amigo aberto na conversa (vazio = lista)
var amigos: Array = []                              # meus_amigos_godot
var msgs: Array = []                                # conversa aberta
var chat: Array = []                                # chat geral
var achados: Array = []                             # busca por nome
var resumo := {"nao_lidas": 0, "pedidos": 0, "online": 0, "duelos": []}
var nota := ""
var nota_cor := Color("dfe4ff")
var carregando := false

# duelo
var convite := {}                                   # convite que CHEGOU: {id, de, nome, lado_de, t}
var esperando := {}                                 # convite que EU fiz: {id, nome, t}
var _recusados := {}                                # convites que já respondi (não mostra de novo)
var aposta_para := {}                               # amigo para quem estou montando o duelo (painel da APOSTA aberto)
var ap_moedas := 0
var ap_trofeus := 0
var ap_modo := "normal"                             ## "normal" (Batalha) ou "cerco" (2 rodadas: defende e ataca) — 19_cerco.sql
const APOSTA_MOEDAS := [0, 25, 50, 100, 200, 500]   ## os mesmos valores que o servidor aceita (14_social_godot.sql)
const APOSTA_TROFEUS := [0, 10, 20, 30, 50]

var _abre := 0.0
var _relogio := 0.0
var _t_resumo := 1.0
var _t_lista := 0.0
var _t_duelo := 0.0
var _pedindo := {}                                  # nome -> true (pergunta em andamento)
var _rol := 0.0
var _rol_alvo := 0.0
var _arrasto := {}
var _botoes: Array = []                             # [{r, f}] montado a cada desenho (toques)
var _altura_lista := 0.0
var _confirmar := {}                                # {id, t}: remover amigo pede 2 toques
var campo: LineEdit
var _lista: Control
var _sobe := 0.0                                    # TECLADO aberto: a janela sobe para o campo ficar à vista

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # (ocupa a tela toda: senão os toques não chegam)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_lista = Control.new()
	_lista.clip_contents = true
	_lista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lista.draw.connect(_desenhar_lista)
	add_child(_lista)
	campo = LineEdit.new()
	campo.max_length = 200
	campo.add_theme_font_override("font", intro.f_texto)
	campo.add_theme_font_size_override("font_size", 22)
	campo.add_theme_color_override("font_color", Color("1c1630"))
	campo.add_theme_color_override("font_placeholder_color", Color(0.11, 0.09, 0.19, 0.45))
	campo.add_theme_color_override("caret_color", Color("2c3874"))
	for estado in ["normal", "focus", "read_only"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("fff8e6")
		sb.set_corner_radius_all(16)
		sb.set_border_width_all(3)
		sb.border_color = Color("f6c343") if estado == "focus" else Color("141a36")
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		campo.add_theme_stylebox_override(estado, sb)
	campo.text_submitted.connect(func(_t): _enviar())
	campo.visible = false
	add_child(campo)

func _conta() -> Node:
	return get_node_or_null("/root/Conta")

func _logado() -> bool:
	var c := _conta()
	return c != null and c.online_pronto()

## O número que aparece no botão (0 = nada novo).
func avisos() -> int:
	return int(resumo.get("nao_lidas", 0)) + int(resumo.get("pedidos", 0)) + (resumo.get("duelos", []) as Array).size()

func online() -> int:
	return int(resumo.get("online", 0))

# =================================================================== ABRIR / FECHAR
func abrir() -> void:
	_quadro_abriu = Engine.get_process_frames()       # (o mesmo toque que abriu não pode fechar)
	visible = true
	_abre = 0.0
	_arrasto = {}
	conversa_com = {}
	_mudar_aba(aba)
	if not _logado():
		_aviso("Entre com sua conta nas Opções para ter amigos, conversar e duelar.", false)

func fechar() -> void:
	conversa_com = {}
	campo.visible = false
	campo.release_focus()
	_sobe = 0.0
	position.y = 0.0
	_arrasto = {}
	visible = not convite.is_empty() or not esperando.is_empty()     # (o aviso de duelo continua)

func janela_aberta() -> bool:
	return visible and _abre >= 0.0 and _modo_janela

var _modo_janela := false

func _mudar_aba(a: String) -> void:
	aba = a
	_modo_janela = true
	_rol = 0.0
	_rol_alvo = 0.0
	nota = ""
	achados = []
	_t_lista = 0.0
	campo.text = ""
	_ajustar_campo()

func _aviso(t: String, bom: bool) -> void:
	nota = t
	nota_cor = Color("b6ff6a") if bom else Color("ffb0a0")

# =================================================================== SERVIDOR (de vez em quando)
func _process(dt: float) -> void:
	_relogio += dt
	if visible:
		_abre = move_toward(_abre, 1.0, dt * 4.0)
	_rol = lerpf(_rol, _rol_alvo, minf(1.0, dt * 14.0))
	if _arrasto.is_empty():
		_rol_alvo = clampf(_rol_alvo, 0.0, _rol_max())
	_sobe = lerpf(_sobe, intro.subida_teclado(campo, _ret_campo().end.y), minf(1.0, dt * 14.0))
	if absf(position.y + _sobe) > 0.5:
		position.y = -roundf(_sobe)
	_atualizar_tela()                                   # desenha SEMPRE (mesmo sem conta), senão a aba não muda na hora
	if not _logado() or intro.tela != intro.Tela.MENU:
		return
	_t_resumo -= dt
	if _t_resumo <= 0.0:
		_t_resumo = CADA_RESUMO
		_pegar_resumo()
	if not esperando.is_empty():
		esperando.t += dt
		_t_duelo -= dt
		if _t_duelo <= 0.0:
			_t_duelo = 2.0
			_ver_meu_duelo()
	if not convite.is_empty():
		convite.t += dt
		if convite.t > DUELO_TEMPO:
			convite = {}
			_atualizar_visivel()
	if visible and _modo_janela:
		_t_lista -= dt
		if _t_lista <= 0.0:
			if not conversa_com.is_empty():
				_t_lista = CADA_CONVERSA
				_carregar_conversa()
			elif aba == "chat":
				_t_lista = CADA_CHAT
				_carregar_chat()
			elif aba == "amigos":
				_t_lista = CADA_AMIGOS
				_carregar_amigos()
			else:
				_t_lista = 999.0

func _atualizar_tela() -> void:
	var la := _area_lista()
	if _lista.position != intro.O + la.position:
		_lista.position = intro.O + la.position
	if _lista.size != la.size:
		_lista.size = la.size
	_lista.visible = visible and _modo_janela and aposta_para.is_empty()
	_ajustar_campo()
	if visible:
		queue_redraw()
		_lista.queue_redraw()

func _rpc(nome: String, args := {}) -> Dictionary:
	return await _conta().chamar(nome, args)

func _pegar_resumo() -> void:
	if _pedindo.get("resumo", false):
		return
	_pedindo.resumo = true
	var r := await _rpc("social_resumo")
	_pedindo.resumo = false
	if not (r.ok and r.dados is Dictionary):
		return
	var antes := avisos()
	resumo = r.dados
	# convite de duelo novo?
	for d in resumo.get("duelos", []):
		var id := str(d.get("id", ""))
		if convite.is_empty() and not _recusados.has(id) and esperando.is_empty():
			convite = {"id": id, "nome": str(d.get("nome", "Amigo")), "lado_de": str(d.get("lado_de", "heroes")), "t": 0.0,
				"modo": str(d.get("modo", "normal")) if d.get("modo") != null else "normal",
				"moedas": int(d.get("aposta_moedas", 0)), "trofeus": int(d.get("aposta_trofeus", 0))}
			intro._trovao()
			_atualizar_visivel()
			break
	if avisos() > antes:
		intro._clique(true)

func _carregar_amigos() -> void:
	if _pedindo.get("amigos", false):
		return
	_pedindo.amigos = true
	if amigos.is_empty():
		carregando = true
	var r := await _rpc("meus_amigos_godot")
	_pedindo.amigos = false
	carregando = false
	if r.ok and r.dados is Array:
		amigos = r.dados
	elif not r.ok:
		_aviso(_erro_bonito(str(r.erro)), false)

func _carregar_conversa() -> void:
	if conversa_com.is_empty() or _pedindo.get("conversa", false):
		return
	_pedindo.conversa = true
	var quem := str(conversa_com.id)
	var r := await _rpc("conversa", {"p_outro": quem})
	_pedindo.conversa = false
	if conversa_com.is_empty() or str(conversa_com.id) != quem:
		return
	if r.ok and r.dados is Array:
		var novo: bool = (r.dados as Array).size() != msgs.size()
		msgs = r.dados
		if novo:
			_rol_alvo = _rol_max_futuro()
		resumo.nao_lidas = maxi(0, int(resumo.get("nao_lidas", 0)) - int(conversa_com.get("nao_lidas", 0)))
		conversa_com.nao_lidas = 0

func _carregar_chat() -> void:
	if _pedindo.get("chat", false):
		return
	_pedindo.chat = true
	var r: Dictionary = await _rpc("chat_geral")                  # (17_chat_duelo.sql: com lado, troféus e online)
	var ordem_certa := true
	if not r.ok:
		r = await _conta().ler("mensagens?select=id,autor,nome,lado,texto&order=id.desc&limit=40")
		ordem_certa = false
	_pedindo.chat = false
	if r.ok and r.dados is Array:
		var l: Array = r.dados
		if not ordem_certa:
			l.reverse()
		var novo: bool = l.size() != chat.size() or (not l.is_empty() and not chat.is_empty() and l[-1].id != chat[-1].id)
		chat = l
		if novo:
			_rol_alvo = _rol_max_futuro()

func _erro_bonito(e: String) -> String:
	var m := e.to_lower()
	if "function" in m or "does not exist" in m or "could not find" in m:
		return "Falta rodar o 14_social_godot.sql no Supabase."
	if "calma" in m:
		return "Calma! Espere um pouquinho para mandar outra."
	if "amigos" in m:
		return e
	if "sem internet" in m or "conectar" in m:
		return "Sem internet. Tente de novo."
	return e.left(80)

# =================================================================== AÇÕES
func _enviar() -> void:
	var t := campo.text.strip_edges()
	if t == "" or not _logado():
		return
	if aba == "adicionar" and conversa_com.is_empty():
		_buscar(t)
		return
	campo.text = ""
	var r: Dictionary
	if not conversa_com.is_empty():
		r = await _rpc("enviar_privada", {"p_para": str(conversa_com.id), "p_texto": t})
		if r.ok:
			_t_lista = 0.0
	else:
		r = await _rpc("enviar_mensagem", {"p_texto": t, "p_lado": Perfil.lado if Perfil.lado != "" else null})
		if r.ok:
			_t_lista = 0.0
	if not r.ok:
		campo.text = t
		_aviso(_erro_bonito(str(r.erro)), false)
	else:
		intro._clique(false)

func _buscar(t: String) -> void:
	if t.length() < 2:
		_aviso("Escreva pelo menos 2 letras do nome.", false)
		return
	carregando = true
	var r := await _rpc("buscar_jogadores", {"p_texto": t})
	carregando = false
	if r.ok and r.dados is Array:
		achados = r.dados
		_aviso("Nenhum jogador com esse nome." if achados.is_empty() else "", false)
	else:
		_aviso(_erro_bonito(str(r.erro)), false)

func _pedir_amizade(j: Dictionary) -> void:
	intro._clique(true)
	var r := await _rpc("pedir_amizade", {"p_alvo": str(j.id)})
	if r.ok:
		j.situacao = str(r.dados) if r.dados is String else "pendente"
		_aviso("Vocês agora são amigos!" if j.situacao == "aceita" else "Pedido enviado para %s!" % j.nome, true)
		_t_lista = 0.0
	else:
		_aviso(_erro_bonito(str(r.erro)), false)

func _responder_amizade(a: Dictionary, aceitar: bool) -> void:
	intro._clique(true)
	var r := await _rpc("responder_amizade", {"p_de": str(a.id), "p_aceitar": aceitar})
	if r.ok:
		_aviso(("Agora você e %s são amigos!" % a.nome) if aceitar else "Pedido recusado.", aceitar)
		resumo.pedidos = maxi(0, int(resumo.get("pedidos", 0)) - 1)
		_carregar_amigos()
	else:
		_aviso(_erro_bonito(str(r.erro)), false)

func _remover(a: Dictionary) -> void:
	if _confirmar.get("id", "") != str(a.id) or _relogio - float(_confirmar.get("t", 0.0)) > 3.0:
		_confirmar = {"id": str(a.id), "t": _relogio}
		_aviso("Toque de novo no X para desfazer a amizade com %s." % a.nome, false)
		return
	_confirmar = {}
	var r := await _rpc("remover_amigo", {"p_outro": str(a.id)})
	if r.ok:
		_aviso("Amizade desfeita.", false)
		_carregar_amigos()

func _abrir_conversa(a: Dictionary) -> void:
	intro._clique(false)
	conversa_com = a
	msgs = []
	_rol = 0.0
	_rol_alvo = 0.0
	nota = ""
	campo.text = ""
	_t_lista = 0.0

# ------------------------------------------------------------------- duelo
## ⚔ Duelo: primeiro abre o painel da APOSTA (sem aposta, só moedas, só troféus ou os dois).
func _chamar_duelo(a: Dictionary) -> void:
	if not esperando.is_empty():
		return
	intro._clique(false)
	aposta_para = a
	ap_moedas = 0
	ap_trofeus = 0
	ap_modo = "normal"

func _enviar_convite() -> void:
	var a := aposta_para
	aposta_para = {}
	if a.is_empty() or not esperando.is_empty():
		return
	intro._clique(true)
	var lado := Perfil.lado if Perfil.lado in ["heroes", "monsters"] else "heroes"
	var args := {"p_para": str(a.id), "p_lado": lado, "p_moedas": ap_moedas, "p_trofeus": ap_trofeus}
	if ap_modo == "cerco":
		args["p_modo"] = "cerco"
	var r := await _rpc("convidar_duelo", args)
	if r.ok and r.dados is String:
		esperando = {"id": r.dados, "nome": str(a.nome), "t": 0.0, "moedas": ap_moedas, "trofeus": ap_trofeus}
		_t_duelo = 2.0
		_atualizar_visivel()
	else:
		_aviso(_erro_bonito(str(r.erro)), false)

func _ver_meu_duelo() -> void:
	if esperando.is_empty() or _pedindo.get("duelo", false):
		return
	_pedindo.duelo = true
	var id := str(esperando.id)
	var r := await _rpc("ver_duelo", {"p_id": id})
	_pedindo.duelo = false
	if esperando.is_empty() or str(esperando.id) != id or not (r.ok and r.dados is Dictionary):
		return
	var st := str(r.dados.get("status", ""))
	if st == "aceito" and r.dados.get("sala") is Dictionary:
		var nome := str(esperando.nome)
		esperando = {}
		await _entrar_no_duelo(r.dados.sala, nome)
	elif st in ["recusado", "cancelado"] or esperando.t > DUELO_TEMPO + 5.0:
		var nome2 := str(esperando.nome)
		esperando = {}
		_atualizar_visivel()
		_aviso("%s não aceitou o duelo agora." % nome2, false)
		intro._avisar("%s não aceitou o duelo agora." % nome2)

func _cancelar_meu_duelo() -> void:
	if esperando.is_empty():
		return
	var id := str(esperando.id)
	esperando = {}
	_atualizar_visivel()
	intro._clique(false)
	_rpc("cancelar_duelo", {"p_id": id})

func _responder_duelo(aceitar: bool) -> void:
	if convite.is_empty():
		return
	var c := convite
	convite = {}
	_recusados[str(c.id)] = true
	intro._clique(true)
	var r := await _rpc("responder_duelo", {"p_id": str(c.id), "p_aceitar": aceitar})
	_atualizar_visivel()
	if not aceitar:
		return
	if r.ok and r.dados is Dictionary and r.dados.has("id"):
		await _entrar_no_duelo(r.dados, str(c.nome))
	else:
		intro._avisar("Esse duelo já acabou." if r.ok else _erro_bonito(str(r.erro)))

## Mesmo caminho da busca do PvP: a sala + o token do canal ao vivo + o meu lado.
func _entrar_no_duelo(sala: Dictionary, nome: String) -> void:
	var token: String = await _conta().token_fresco()
	var s := sala.duplicate()
	s["token"] = token
	s["lado"] = "heroes" if str(s.get("heroes", "")) == _conta().meu_id() else "monsters"
	Perfil.pvp_adversario = nome
	Perfil.pvp_sala = s
	visible = false
	_modo_janela = false
	campo.visible = false
	intro._trovao()
	intro._ir(intro.Tela.MENU, intro._abrir_pvp)

func _atualizar_visivel() -> void:
	visible = _modo_janela or not convite.is_empty() or not esperando.is_empty()

# =================================================================== TOQUES
func _ret_aba(i: int) -> Rect2:
	return Rect2(JANELA.position.x + 300 + i * 160, JANELA.position.y + 38, 152, 48)

func _ret_fechar() -> Rect2:
	return Rect2(JANELA.end.x - 92, JANELA.position.y + 30, 64, 60)

func _ret_campo() -> Rect2:
	return Rect2(LISTA.position.x, JANELA.end.y - 84, LISTA.size.x - 190, 54)

func _ret_enviar() -> Rect2:
	return Rect2(LISTA.end.x - 176, JANELA.end.y - 84, 176, 54)

func _tem_campo() -> bool:
	return _modo_janela and visible and _logado() and (not conversa_com.is_empty() or aba in ["chat", "adicionar"]) \
		and convite.is_empty() and esperando.is_empty() and aposta_para.is_empty()

func _ajustar_campo() -> void:
	var mostra := _tem_campo()
	if campo.visible != mostra:
		campo.visible = mostra
	if not mostra:
		return
	var r := _ret_campo()
	if campo.position != intro.O + r.position:
		campo.position = intro.O + r.position
	if campo.size != r.size:
		campo.size = r.size
	var dica := "Escreva o nome do jogador..." if (aba == "adicionar" and conversa_com.is_empty()) else "Escreva uma mensagem..."
	if campo.placeholder_text != dica:
		campo.placeholder_text = dica
	var maxl := 20 if (aba == "adicionar" and conversa_com.is_empty()) else 200
	if campo.max_length != maxl:                         # (mudar todo quadro joga o cursor para o começo: "oi" virava "io")
		campo.max_length = maxl

func _area_lista() -> Rect2:
	var l := LISTA
	if not conversa_com.is_empty():
		l = Rect2(LISTA.position.x, LISTA.position.y + 50, LISTA.size.x, LISTA.size.y - 50 - 40)
	elif _tem_campo():
		l = Rect2(LISTA.position.x, LISTA.position.y + (60 if aba == "adicionar" else 0), LISTA.size.x, LISTA.size.y - 40 - (60 if aba == "adicionar" else 0))
	return l

func _rol_max() -> float:
	return maxf(0.0, _altura_lista - _area_lista().size.y)

func _rol_max_futuro() -> float:
	return 1e9                                          # (rola até o fim; o clamp acerta no próximo quadro)

var _quadro_abriu := -1

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and Engine.get_process_frames() == _quadro_abriu:
		accept_event()
		return
	var p: Vector2 = (ev.position if "position" in ev else Vector2.ZERO) - intro.O
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if ev.pressed:
				_rol_alvo += (-60.0 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 60.0)
			accept_event()
			return
		if ev.button_index != MOUSE_BUTTON_LEFT:
			return
		if ev.pressed:
			_arrasto = {"y0": p.y, "r0": _rol_alvo, "moveu": false, "lista": _area_lista().has_point(p)}
		else:
			if _arrasto.is_empty():
				return                                  # (o toque começou fora: ex. o mesmo toque que abriu a janela)
			var moveu: bool = _arrasto.get("moveu", false)
			_arrasto = {}
			if not moveu:
				_tocar(p)
		accept_event()
	elif ev is InputEventMouseMotion and not _arrasto.is_empty():
		var dy: float = p.y - _arrasto.y0
		if absf(dy) > 8.0:
			_arrasto.moveu = true
		if _arrasto.lista:
			_rol_alvo = clampf(_arrasto.r0 - dy, -40.0, _rol_max() + 40.0)
			_rol = _rol_alvo
		accept_event()

func _tocar(p: Vector2) -> void:
	# avisos de duelo por cima de tudo
	if not convite.is_empty():
		for b in _botoes:
			if b.r.has_point(p) and str(b.get("camada", "")) == "duelo":
				b.f.call()
		return
	if not esperando.is_empty():
		for b in _botoes:
			if b.r.has_point(p) and str(b.get("camada", "")) == "duelo":
				b.f.call()
		return
	if not _modo_janela:
		return
	if not aposta_para.is_empty():
		for b in _botoes:
			if b.r.has_point(p) and str(b.get("camada", "")) == "aposta":
				b.f.call()
				return
		return
	if _ret_fechar().grow(6).has_point(p) or not JANELA.grow(10).has_point(p):
		intro._clique(false)
		_modo_janela = false
		fechar()
		return
	if conversa_com.is_empty():
		for i in ABAS.size():
			if _ret_aba(i).has_point(p) and aba != ABAS[i][0]:
				intro._clique(false)
				if ABAS[i][0] == "replays":
					Perfil.replays_volta = "res://cenas/intro.tscn"
					get_tree().change_scene_to_file("res://cenas/replays.tscn")
					return
				_mudar_aba(ABAS[i][0])
				return
	if _tem_campo() and _ret_enviar().has_point(p):
		_enviar()
		return
	for b in _botoes:
		if b.r.has_point(p):
			b.f.call()
			return

# =================================================================== DESENHO
static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

func _draw() -> void:
	intro._ci = self
	_botoes = []
	var O: Vector2 = intro.O
	if _modo_janela:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.05, 0.62 * _abre))
		draw_set_transform(O, 0.0, Vector2.ONE)
		_desenhar_janela()
		if conversa_com.is_empty():
			_desenhar_abas()
		else:
			_desenhar_topo_conversa()
		if _tem_campo():
			_desenhar_envio()
		if aba == "adicionar" and conversa_com.is_empty() and _logado():
			_desenhar_topo_adicionar()
		intro._texto_cartoon(Vector2(JANELA.get_center().x, JANELA.end.y - 14 if not _tem_campo() else JANELA.end.y - 96), nota, 16, nota_cor, intro.f_texto, 1.2, true)
	draw_set_transform(O, 0.0, Vector2.ONE)
	if not convite.is_empty():
		_desenhar_convite()
	elif not esperando.is_empty():
		_desenhar_esperando()
	elif not aposta_para.is_empty() and _modo_janela:
		_desenhar_aposta()
	draw_set_transform(Vector2.ZERO)

func _desenhar_janela() -> void:
	var j := JANELA
	var NAVY: Color = intro.NAVY
	intro._caixa(Rect2(j.position + Vector2(0, 12), j.size).grow(10), Color(0, 0, 0, 0.45), 40)
	intro._caixa(j.grow(10), Color("4a2a06"), 38)
	intro._caixa(j.grow(8), Color("b8740f"), 36)
	intro._caixa(Rect2(j.position.x - 8, j.position.y - 8, j.size.x + 16, j.size.y * 0.5), Color("f6c343"), 36)
	intro._caixa(j.grow(3), NAVY, 31)
	intro._painel(j, Color("3e4f96"), Color("1f2754"), 29)
	if conversa_com.is_empty():
		intro._texto_cartoon(Vector2(j.position.x + 40, j.position.y + 78), "Social", 46, Color("ffd34d"), intro.f_titulo, 2.5, false)
	var f := _ret_fechar()
	intro._caixa(Rect2(f.position + Vector2(0, 5), f.size).grow(3), NAVY, 18)
	intro._caixa(f.grow(3), NAVY, 18)
	intro._botao_degrade(f, Color("7f95e6"), Color("4a5fae"), Color("2c3874"), 16)
	var fc := f.get_center()
	for s in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(fc - s * 11, fc + s * 11, intro.CONTORNO, 7.0, true)
		draw_line(fc - s * 11, fc + s * 11, Color.WHITE, 4.0, true)
	var a := _area_lista()
	intro._caixa(a.grow(6), Color(0.04, 0.05, 0.12, 0.45), 18)
	if not _logado():
		intro._texto_cartoon(Vector2(j.get_center().x, a.position.y + 150), "Entre com sua conta para usar o Social.", 26, intro.CREME, intro.f_titulo, 2.0, true)
		intro._texto_cartoon(Vector2(j.get_center().x, a.position.y + 190), "Entre com sua conta nas Opções para duelar", 19, Color("c9d2ff"), intro.f_texto, 1.4, true)

func _desenhar_abas() -> void:
	var a := _ret_aba(0)
	var b := _ret_aba(ABAS.size() - 1)
	intro._caixa(Rect2(a.position - Vector2(8, 7), Vector2(b.end.x - a.position.x + 16, a.size.y + 14)), Color(0.05, 0.06, 0.14, 0.7), 22)
	for i in ABAS.size():
		var r := _ret_aba(i)
		var on: bool = aba == ABAS[i][0]
		if ABAS[i][0] == "replays":                    # botão VERDE (abre a tela de replays)
			intro._caixa(Rect2(r.position + Vector2(0, 4), r.size).grow(2), Color("0f3d1a"), 17)
			intro._caixa(r.grow(2), Color("0f3d1a"), 17)
			intro._botao_degrade(r, Color("8cf0a0"), Color("2fd15a"), Color("1e8a3a"), 15)
		elif on:
			intro._caixa(Rect2(r.position + Vector2(0, 4), r.size).grow(2), Color("4a2a06"), 17)
			intro._caixa(r.grow(2), Color("4a2a06"), 17)
			intro._botao_degrade(r, Color("ffe98a"), Color("ffc43a"), Color("c97a0c"), 15)
		else:
			intro._caixa(Rect2(r.position + Vector2(0, 4), r.size), Color(0.03, 0.04, 0.1, 0.6), 15)
			intro._botao_degrade(r, Color("5d6fb8"), Color("3d4c8f"), Color("2a356b"), 15)
		intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 33), ABAS[i][1], 20, Color.WHITE, intro.f_titulo, 1.5, true)
		var n := 0
		if ABAS[i][0] == "amigos":
			n = int(resumo.get("nao_lidas", 0)) + int(resumo.get("pedidos", 0))
		if n > 0:
			_bolinha(Vector2(r.end.x - 4, r.position.y + 4), n, 1.0)

func _desenhar_topo_conversa() -> void:
	var j := JANELA
	var v := Rect2(j.position.x + 36, j.position.y + 34, 130, 54)
	_botao(v, "◀ Voltar", Color("7f95e6"), Color("4a5fae"), Color("2c3874"), _voltar_lista)
	var cx := j.position.x + 220
	_rosto(conversa_com, Vector2(cx, j.position.y + 61), 26)
	intro._texto_cartoon(Vector2(cx + 38, j.position.y + 58), str(conversa_com.get("nome", "")), 30, Color("ffd34d"), intro.f_titulo, 2.0, false)
	_selo_lado(cx + 38 + intro._larg(intro.f_titulo, str(conversa_com.get("nome", "")), 30) + 14, j.position.y + 56, conversa_com.get("lado_atual"))
	var on: bool = conversa_com.get("online", false) == true
	intro._texto_cartoon(Vector2(cx + 38, j.position.y + 84), "online agora" if on else "offline", 15, Color("b6ff6a") if on else Color(1, 1, 1, 0.5), intro.f_texto, 1.1, false)
	var d := Rect2(_ret_fechar().position.x - 196, j.position.y + 34, 180, 54)
	_botao(d, "⚔ Duelo", Color("ffb0a0"), Color("e0503a"), Color("8a2414"), func(): _chamar_duelo(conversa_com))

func _desenhar_envio() -> void:
	var e := _ret_enviar()
	var busca := aba == "adicionar" and conversa_com.is_empty()
	_botao(e, "Buscar" if busca else "Enviar", Color("d9ff9a"), Color("8be03c"), Color("3f8f1a"), func(): _enviar())

func _desenhar_topo_adicionar() -> void:
	var r := Rect2(LISTA.position.x, LISTA.position.y - 6, LISTA.size.x, 50)
	intro._caixa(r, Color(0.05, 0.06, 0.18, 0.6), 16)
	intro._texto_cartoon(Vector2(r.position.x + 20, r.position.y + 33), "Procure pelo nome do jogador e toque em + Amigo.", 17, Color("dfe4ff"), intro.f_texto, 1.2, false)
	var b := Rect2(r.end.x - 236, r.position.y + 4, 228, 42)
	_botao(b, "Convidar amigos", Color("ffb3d9"), Color("e0458f"), Color("7a1450"), _abrir_convidar, 19)

func _abrir_convidar() -> void:
	intro._clique(true)
	_modo_janela = false
	fechar()
	intro.convidar.abrir()

func _voltar_lista() -> void:
	intro._clique(false)
	conversa_com = {}
	msgs = []
	_t_lista = 0.0
	_rol_alvo = 0.0

## Botão desenhado + registrado para o toque.
func _botao(r: Rect2, txt: String, c1: Color, c2: Color, c3: Color, f: Callable, tam := 20, camada := "") -> void:
	var ci: CanvasItem = intro._ci
	intro._caixa(Rect2(r.position + Vector2(0, 4), r.size).grow(2), intro.CONTORNO, 15)
	intro._caixa(r.grow(2), intro.CONTORNO, 15)
	intro._botao_degrade(r, c1, c2, c3, 13)
	intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + r.size.y * 0.5 + tam * 0.36), txt, tam, Color.WHITE, intro.f_titulo, 1.4, true)
	# o toque usa coordenadas do palco; na lista, soma a posição da lista
	var rr := r
	if ci == _lista:
		rr = Rect2(r.position + _area_lista().position, r.size)
		if not _area_lista().intersects(rr):
			return
		rr = rr.intersection(_area_lista())
	_botoes.append({"r": rr, "f": f, "camada": camada})

func _bolinha(c: Vector2, n: int, k: float) -> void:
	var ci: CanvasItem = intro._ci
	var r := 13.0 * k
	ci.draw_circle(c + Vector2(0, 2), r + 2, Color(0, 0, 0, 0.35))
	ci.draw_circle(c, r + 2, intro.CONTORNO)
	ci.draw_circle(c, r, Color("ff3b3b"))
	var t := str(n) if n < 100 else "99+"
	intro._texto_cartoon(Vector2(c.x, c.y + 6 * k), t, int(16 * k), Color.WHITE, intro.f_titulo, 1.0, true)

func _rosto(d: Dictionary, c: Vector2, r: float) -> void:
	var ci: CanvasItem = intro._ci
	var nome := str(d.get("nome", "?"))
	var cores := [Color("2f7fd6"), Color("1fa6a0"), Color("8a5ad6"), Color("d65a7a"), Color("d6862f"), Color("4aa83a")]
	var cor: Color = cores[absi(nome.hash()) % cores.size()]
	ci.draw_circle(c, r + 3, intro.CONTORNO)
	intro._bola(c, r, cor.lightened(0.25), cor.darkened(0.2))
	intro._texto_cartoon(Vector2(c.x, c.y + r * 0.38), nome.left(1).to_upper(), int(r * 1.05), Color.WHITE, intro.f_titulo, 1.3, true)
	if d.get("online", false) == true:
		ci.draw_circle(c + Vector2(r * 0.72, r * 0.72), 8, intro.CONTORNO)
		ci.draw_circle(c + Vector2(r * 0.72, r * 0.72), 6, Color("6bff4a"))

## SELO do lado (Heroes / Monsters) ao lado do nome. x = começo, y = linha de base do nome. Devolve a largura.
func _selo_lado(x: float, y: float, lado, pequeno := false) -> float:
	var l := str(lado) if lado != null else ""
	if l != "heroes" and l != "monsters":
		return 0.0
	var ci: CanvasItem = intro._ci
	var her := l == "heroes"
	var txt := "HEROES" if her else "MONSTERS"
	var tam := 12 if pequeno else 13
	var h := 20.0 if pequeno else 22.0
	var w: float = intro._larg(intro.f_titulo, txt, tam) + h + 16.0
	var r := Rect2(x, y - h + 3.0, w, h)
	intro._caixa(r.grow(2), intro.CONTORNO, int(h / 2.0) + 2)
	if her:
		intro._botao_degrade(r, Color("8fb0ff"), Color("3a5fd0"), Color("22357a"), int(h / 2.0))
	else:
		intro._botao_degrade(r, Color("c9ff8a"), Color("4f9e22"), Color("23500c"), int(h / 2.0))
	intro._brasao(l, Vector2(r.position.x + h * 0.55, r.get_center().y), h * 0.95)
	intro._texto_cartoon(Vector2(r.position.x + h + 4.0, r.position.y + h * 0.5 + tam * 0.36), txt, tam,
		Color("fff3b0") if her else Color("efffd6"), intro.f_titulo, 1.0, false)
	return w

# ------------------------------------------------------------------- lista (rola)
func _desenhar_lista() -> void:
	intro._ci = _lista
	if not (visible and _modo_janela) or not _logado():
		return
	var a := _area_lista()
	var y := -_rol + 6.0
	var w := a.size.x - 14.0
	var y0 := y
	if not conversa_com.is_empty():
		y = _lista_conversa(y, w)
	elif aba == "amigos":
		y = _lista_amigos(y, w)
	elif aba == "chat":
		y = _lista_chat(y, w)
	else:
		y = _lista_achados(y, w)
	_altura_lista = y - y0 + 10.0
	if carregando:
		var c := Vector2(a.size.x / 2.0, 120)
		_lista.draw_arc(c, 26, _relogio * 5.0, _relogio * 5.0 + 4.2, 32, intro.OURO2, 7, true)

func _lista_amigos(y: float, w: float) -> float:
	if amigos.is_empty() and not carregando:
		intro._texto_cartoon(Vector2(w / 2.0, y + 90), "Você ainda não tem amigos.", 26, intro.CREME, intro.f_titulo, 2.0, true)
		intro._texto_cartoon(Vector2(w / 2.0, y + 130), "Adicione amigos no fim de uma batalha online (+ Adicionar amigo)!", 19, Color("c9d2ff"), intro.f_texto, 1.4, true)
		return y + 180
	var grupos := [["Pedidos para você", func(a): return a.status == "pendente" and not a.pedido_meu],
		["Amigos", func(a): return a.status == "aceita"],
		["Pedidos que você mandou", func(a): return a.status == "pendente" and a.pedido_meu]]
	for g in grupos:
		var lista: Array = amigos.filter(g[1])
		if lista.is_empty():
			continue
		intro._texto_cartoon(Vector2(10, y + 22), "%s (%d)" % [g[0], lista.size()], 18, Color("ffd34d"), intro.f_titulo, 1.3, false)
		y += 34
		for a in lista:
			_linha_amigo(a, Rect2(0, y, w, 64))
			y += 72
		y += 6
	return y

func _linha_amigo(a: Dictionary, r: Rect2) -> void:
	var ci: CanvasItem = intro._ci
	intro._caixa(Rect2(r.position + Vector2(0, 3), r.size), Color(0, 0, 0, 0.3), 14)
	intro._caixa(r, Color(0.2, 0.25, 0.52, 0.95), 14)
	var cy := r.get_center().y
	_rosto(a, Vector2(r.position.x + 38, cy), 22)
	intro._texto_cartoon(Vector2(r.position.x + 74, cy + 1), str(a.nome), 22, Color.WHITE, intro.f_titulo, 1.4, false)
	_selo_lado(r.position.x + 74 + intro._larg(intro.f_titulo, str(a.nome), 22) + 12, cy, a.get("lado_atual"))
	var on: bool = a.get("online", false) == true
	var sub := "online" if on else "offline"
	sub += " · %d troféus" % int(a.get("trofeus", 0))
	intro._texto_cartoon(Vector2(r.position.x + 74, cy + 22), sub, 14, Color("b6ff6a") if on else Color(1, 1, 1, 0.55), intro.f_texto, 1.0, false)
	var x := r.end.x - 12
	if a.status == "aceita":
		var bx := Rect2(x - 44, cy - 20, 40, 40)
		_botao(bx, "×", Color("8a8fa8"), Color("626780"), Color("43475c"), func(): _remover(a), 26)
		x -= 56
		var bd := Rect2(x - 132, cy - 22, 132, 44)
		_botao(bd, "⚔ Duelo", Color("ffb0a0"), Color("e0503a"), Color("8a2414"), func(): _chamar_duelo(a), 19)
		x -= 144
		var bc := Rect2(x - 150, cy - 22, 150, 44)
		_botao(bc, "Conversar", Color("9fd8ff"), Color("3a8ee0"), Color("1d4f8a"), func(): _abrir_conversa(a), 19)
		var n := int(a.get("nao_lidas", 0))
		if n > 0:
			var k := 1.0 + 0.12 * sin(_relogio * 6.0)
			_bolinha(Vector2(bc.end.x - 4, bc.position.y + 2), n, k)
	elif not a.pedido_meu:
		var br := Rect2(x - 130, cy - 22, 130, 44)
		_botao(br, "Recusar", Color("8a8fa8"), Color("626780"), Color("43475c"), func(): _responder_amizade(a, false), 19)
		x -= 142
		var ba := Rect2(x - 130, cy - 22, 130, 44)
		_botao(ba, "Aceitar", Color("d9ff9a"), Color("8be03c"), Color("3f8f1a"), func(): _responder_amizade(a, true), 19)
	else:
		var bx2 := Rect2(x - 130, cy - 22, 130, 44)
		_botao(bx2, "Cancelar", Color("8a8fa8"), Color("626780"), Color("43475c"), func(): _remover(a), 19)
		intro._texto_cartoon(Vector2(bx2.position.x - 16 - intro._larg(intro.f_texto, "esperando resposta", 16), cy + 6), "esperando resposta", 16, Color(1, 1, 1, 0.6), intro.f_texto, 1.0, false)

func _altura_texto(t: String, larg: float, tam: int) -> float:
	return intro.f_texto.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, larg, tam).y

func _lista_conversa(y: float, w: float) -> float:
	if msgs.is_empty():
		intro._texto_cartoon(Vector2(w / 2.0, y + 90), "Mande a primeira mensagem para %s!" % str(conversa_com.get("nome", "")), 22, intro.CREME, intro.f_titulo, 1.8, true)
		return y + 140
	var maxl := w * 0.62
	for m in msgs:
		var minha: bool = m.get("minha", false) == true
		var t := str(m.texto)
		var tw := minf(maxl, intro._larg(intro.f_texto, t, 19) + 4)
		var th := _altura_texto(t, tw, 19)
		var bolha := Rect2((w - tw - 36) if minha else 6.0, y, tw + 30, th + 18)
		intro._caixa(Rect2(bolha.position + Vector2(0, 3), bolha.size), Color(0, 0, 0, 0.3), 16)
		intro._caixa(bolha, Color("2f7d16") if minha else Color("34418a"), 16, 2, Color("8be03c") if minha else Color("6f86d6"))
		_lista.draw_multiline_string(intro.f_texto, bolha.position + Vector2(15, 9 + 19 * 0.85), t, HORIZONTAL_ALIGNMENT_LEFT, tw, 19, -1, Color.WHITE)
		y += bolha.size.y + 10
	return y

func _lista_chat(y: float, w: float) -> float:
	if chat.is_empty():
		intro._texto_cartoon(Vector2(w / 2.0, y + 90), "Ninguém falou no chat ainda. Diga oi!", 24, intro.CREME, intro.f_titulo, 1.8, true)
		return y + 140
	var eu: String = _conta().meu_id()
	var meu_lado := Perfil.lado if Perfil.lado in ["heroes", "monsters"] else ""
	for m in chat:
		var minha := str(m.get("autor", "")) == eu
		var nome := "Você" if minha else str(m.get("nome", "?"))
		var lado = meu_lado if minha else m.get("lado")
		var t := str(m.texto)
		var tw := w - 60.0 - (0.0 if minha else 140.0)
		var th := _altura_texto(t, tw, 18)
		var r := Rect2(0, y, w, maxf(th + 44, 62.0 if not minha else 0.0))
		intro._caixa(r, Color(0.18, 0.23, 0.48, 0.85) if not minha else Color(0.16, 0.36, 0.2, 0.85), 14)
		var cor_nome := Color("b6ff6a") if minha else Color.WHITE
		intro._texto_cartoon(Vector2(18, y + 24), nome, 18, cor_nome, intro.f_titulo, 1.2, false)
		var x: float = 18.0 + intro._larg(intro.f_titulo, nome, 18) + 10.0
		x += _selo_lado(x, y + 23, lado, true) + 10.0
		if not minha and m.has("trofeus"):
			intro._trofeu(Vector2(x + 8, y + 17), 16)
			intro._texto_cartoon(Vector2(x + 19, y + 23), str(int(m.get("trofeus", 0))), 14, Color("ffe7a6"), intro.f_texto, 1.0, false)
			x += 30 + intro._larg(intro.f_texto, str(int(m.get("trofeus", 0))), 14)
		if not minha and m.get("online", false) == true:
			intro._ci.draw_circle(Vector2(x + 6, y + 18), 6, intro.CONTORNO)
			intro._ci.draw_circle(Vector2(x + 6, y + 18), 4.5, Color("6bff4a"))
		_lista.draw_multiline_string(intro.f_texto, Vector2(18, y + 34 + 18 * 0.85), t, HORIZONTAL_ALIGNMENT_LEFT, tw, 18, -1, Color.WHITE)
		if not minha and m.get("autor") != null:
			var alvo := {"id": str(m.autor), "nome": str(m.get("nome", "?")), "lado_atual": lado}
			var bd := Rect2(w - 132, y + 10, 120, 40)
			_botao(bd, "⚔ Duelo", Color("ffb0a0"), Color("e0503a"), Color("8a2414"), func(): _chamar_duelo(alvo), 18)
		y += r.size.y + 8
	return y

func _lista_achados(y: float, w: float) -> float:
	if achados.is_empty():
		intro._texto_cartoon(Vector2(w / 2.0, y + 80), "Procure um jogador pelo nome.", 24, intro.CREME, intro.f_titulo, 1.8, true)
		intro._texto_cartoon(Vector2(w / 2.0, y + 116), "Dica: no Ranking também aparecem os nomes dos melhores.", 17, Color("c9d2ff"), intro.f_texto, 1.2, true)
		return y + 150
	for j in achados:
		var r := Rect2(0, y, w, 64)
		intro._caixa(r, Color(0.2, 0.25, 0.52, 0.95), 14)
		var cy := r.get_center().y
		_rosto(j, Vector2(38, cy), 22)
		var sit := str(j.get("situacao", ""))
		intro._texto_cartoon(Vector2(74, cy + 1), str(j.nome), 22, Color.WHITE, intro.f_titulo, 1.4, false)
		_selo_lado(74 + intro._larg(intro.f_titulo, str(j.nome), 22) + 12, cy, j.get("lado_atual"))
		var on: bool = j.get("online", false) == true
		intro._texto_cartoon(Vector2(74, cy + 22), ("online · " if on else "") + "%d troféus" % int(j.get("trofeus", 0)), 14,
			Color("b6ff6a") if on else Color(1, 1, 1, 0.6), intro.f_texto, 1.0, false)
		if on:
			_botao(Rect2(w - 300, cy - 22, 120, 44), "⚔ Duelo", Color("ffb0a0"), Color("e0503a"), Color("8a2414"), func(): _chamar_duelo(j), 18)
		var b := Rect2(w - 170, cy - 22, 158, 44)
		if sit == "aceita":
			intro._texto_cartoon(Vector2(b.get_center().x, cy + 7), "Já é amigo ✓", 18, Color("b6ff6a"), intro.f_titulo, 1.2, true)
		elif sit == "pendente":
			intro._texto_cartoon(Vector2(b.get_center().x, cy + 7), "Pedido enviado", 18, Color(1, 1, 1, 0.7), intro.f_titulo, 1.2, true)
		else:
			_botao(b, "+ Amigo", Color("d9ff9a"), Color("8be03c"), Color("3f8f1a"), func(): _pedir_amizade(j), 20)
		y += 72
	return y

# ------------------------------------------------------------------- APOSTA do duelo
static func texto_aposta(m: int, t: int) -> String:
	if m <= 0 and t <= 0:
		return "Sem aposta (só diversão)"
	var partes := []
	if m > 0:
		partes.append("%d moedas" % m)
	if t > 0:
		partes.append("%d troféus" % t)
	return "Valendo " + " + ".join(partes) + " · quem vencer leva!"

func _desenhar_aposta() -> void:
	draw_rect(Rect2(-intro.O, size), Color(0, 0, 0, 0.55))
	var r := _cartao_duelo(512)
	intro._caixa(r.grow(10), Color("4a2a06"), 30)
	intro._caixa(r.grow(7), Color("e0503a"), 28)
	intro._painel(r, Color("4a3a8a"), Color("221a48"), 24)
	intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 58), "⚔ Duelo com %s" % str(aposta_para.get("nome", "")), 34, Color("ffd34d"), intro.f_titulo, 2.2, true)
	var la = aposta_para.get("lado_atual")
	if la != null and str(la) in ["heroes", "monsters"]:
		var sw: float = intro._larg(intro.f_titulo, "HEROES" if str(la) == "heroes" else "MONSTERS", 13) + 38.0
		_selo_lado(r.get_center().x - sw / 2.0, r.position.y + 6, la)
	intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 92), "O que vale? Quem vencer leva do outro.", 18, Color("c9d2ff"), intro.f_texto, 1.2, true)
	var linhas := [["Moedas", APOSTA_MOEDAS, Perfil.moedas, "m"], ["Troféus", APOSTA_TROFEUS, Perfil.trofeus, "t"]]
	var y := r.position.y + 118
	# MODO: Batalha ou Cerco
	intro._texto_cartoon(Vector2(r.position.x + 30, y + 34), "Modo", 22, Color.WHITE, intro.f_titulo, 1.4, false)
	var mx := r.position.x + 170
	var mw := (r.end.x - 24 - mx) / 2.0
	for md in [["normal", "Batalha"], ["cerco", "Cerco (2 rodadas)"]]:
		var bm := Rect2(mx + 3, y + 4, mw - 6, 44)
		var id_m: String = md[0]
		if ap_modo == id_m:
			_botao(bm, md[1], Color("fff3b0"), Color("f6c343"), Color("b8740f"), func(): pass, 19, "aposta")
		else:
			_botao(bm, md[1], Color("7f95e6"), Color("4a5fae"), Color("2c3874"), func(): _escolher_modo(id_m), 19, "aposta")
		mx += mw
	y += 66
	for ln in linhas:
		intro._texto_cartoon(Vector2(r.position.x + 30, y + 34), ln[0], 22, Color.WHITE, intro.f_titulo, 1.4, false)
		if ln[3] == "m":
			intro._moeda(Vector2(r.position.x + 30 + intro._larg(intro.f_titulo, ln[0], 22) + 18, y + 26), 22)
		var vals: Array = ln[1]
		var x := r.position.x + 170
		var lw := (r.end.x - 24 - x) / vals.size()
		for v in vals:
			var b := Rect2(x + 3, y + 4, lw - 6, 44)
			var on: bool = (ap_moedas if ln[3] == "m" else ap_trofeus) == v
			var pode: bool = int(v) <= int(ln[2])
			var txt := "Nada" if v == 0 else str(v)
			var qual: String = ln[3]
			var valor: int = v
			if on:
				_botao(b, txt, Color("fff3b0"), Color("f6c343"), Color("b8740f"), func(): pass, 19, "aposta")
			elif pode:
				_botao(b, txt, Color("7f95e6"), Color("4a5fae"), Color("2c3874"), func(): _escolher_aposta(qual, valor), 19, "aposta")
			else:
				_botao(b, txt, Color("5a5d70"), Color("44475a"), Color("2e3040"), func(): _aviso_sem_saldo(qual), 19, "aposta")
			x += lw
		y += 66
	intro._texto_cartoon(Vector2(r.get_center().x, y + 34), texto_aposta(ap_moedas, ap_trofeus), 20, Color("b6ff6a") if (ap_moedas > 0 or ap_trofeus > 0) else Color("dfe4ff"), intro.f_titulo, 1.4, true)
	intro._texto_cartoon(Vector2(r.get_center().x, y + 62), "Você tem %d moedas e %d troféus." % [Perfil.moedas, Perfil.trofeus], 16, Color(1, 1, 1, 0.6), intro.f_texto, 1.0, true)
	_botao(Rect2(r.position.x + 40, r.end.y - 84, 200, 58), "Cancelar", Color("8a8fa8"), Color("626780"), Color("43475c"), _fechar_aposta, 22, "aposta")
	_botao(Rect2(r.end.x - 300, r.end.y - 84, 260, 58), "Chamar para o duelo!", Color("ffb0a0"), Color("e0503a"), Color("8a2414"), _enviar_convite, 21, "aposta")

func _escolher_modo(m: String) -> void:
	intro._clique(false)
	ap_modo = m

func _fechar_aposta() -> void:
	intro._clique(false)
	aposta_para = {}

func _aviso_convite_sem_saldo() -> void:
	intro._avisar("Você não tem moedas ou troféus suficientes para essa aposta.")

func _escolher_aposta(qual: String, v: int) -> void:
	intro._clique(false)
	if qual == "m":
		ap_moedas = v
	else:
		ap_trofeus = v

func _aviso_sem_saldo(qual: String) -> void:
	intro._avisar("Você não tem %s suficientes para isso." % ("moedas" if qual == "m" else "troféus"))

# ------------------------------------------------------------------- avisos de duelo (por cima de tudo)
func _cartao_duelo(h: float) -> Rect2:
	return Rect2(intro.W / 2.0 - 300, intro.H / 2.0 - h / 2.0, 600, h)

func _desenhar_convite() -> void:
	draw_rect(Rect2(-intro.O, size), Color(0, 0, 0, 0.55))
	var r := _cartao_duelo(330)
	var pul := 1.0 + 0.03 * sin(_relogio * 5.0)
	draw_set_transform(intro.O + r.get_center() * (1.0 - pul), 0.0, Vector2(pul, pul))
	intro._caixa(r.grow(10), Color("4a2a06"), 30)
	intro._caixa(r.grow(7), Color("e0503a"), 28)
	intro._painel(r, Color("4a3a8a"), Color("221a48"), 24)
	var cerco: bool = str(convite.get("modo", "normal")) == "cerco"
	intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 70), "⚔ DUELO DE CERCO! ⚔" if cerco else "⚔ DUELO! ⚔", 44 if cerco else 48, Color("ffd34d"), intro.f_titulo, 2.5, true)
	var meu := "Monsters" if str(convite.lado_de) == "heroes" else "Heroes"
	intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 118), "%s te chamou para um duelo!" % str(convite.nome), 24, Color.WHITE, intro.f_titulo, 1.6, true)
	var sw2: float = intro._larg(intro.f_titulo, "HEROES" if str(convite.lado_de) == "heroes" else "MONSTERS", 13) + 38.0
	_selo_lado(r.get_center().x - sw2 / 2.0, r.position.y + 18, convite.lado_de)
	var am := int(convite.get("moedas", 0))
	var at := int(convite.get("trofeus", 0))
	intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 148), ("Você joga de %s · 2 rodadas: defende e ataca" if cerco else "Você joga de %s") % meu, 18, Color("c9d2ff"), intro.f_texto, 1.2, true)
	intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 176), texto_aposta(am, at), 19,
		Color("ffd34d") if (am > 0 or at > 0) else Color("c9d2ff"), intro.f_titulo, 1.3, true)
	var falta_saldo := Perfil.moedas < am or Perfil.trofeus < at
	var k := clampf(1.0 - float(convite.t) / DUELO_TEMPO, 0.0, 1.0)
	var barra := Rect2(r.position.x + 60, r.position.y + 196, r.size.x - 120, 10)
	intro._caixa(barra, Color(0, 0, 0, 0.4), 5)
	intro._caixa(Rect2(barra.position, Vector2(barra.size.x * k, barra.size.y)), Color("ffd34d"), 5)
	draw_set_transform(intro.O, 0.0, Vector2.ONE)
	_botao(Rect2(r.position.x + 60, r.end.y - 92, 220, 62), "Recusar", Color("8a8fa8"), Color("626780"), Color("43475c"), func(): _responder_duelo(false), 24, "duelo")
	if falta_saldo:
		intro._texto_cartoon(Vector2(r.get_center().x, r.end.y - 100), "Você não tem o suficiente para essa aposta.", 16, Color("ffb0a0"), intro.f_texto, 1.1, true)
		_botao(Rect2(r.end.x - 280, r.end.y - 92, 220, 62), "Aceitar!", Color("5a5d70"), Color("44475a"), Color("2e3040"), _aviso_convite_sem_saldo, 26, "duelo")
	else:
		_botao(Rect2(r.end.x - 280, r.end.y - 92, 220, 62), "Aceitar!", Color("d9ff9a"), Color("8be03c"), Color("3f8f1a"), func(): _responder_duelo(true), 26, "duelo")

func _desenhar_esperando() -> void:
	draw_rect(Rect2(-intro.O, size), Color(0, 0, 0, 0.55))
	var r := _cartao_duelo(270)
	intro._caixa(r.grow(10), Color("4a2a06"), 30)
	intro._caixa(r.grow(7), Color("f6c343"), 28)
	intro._painel(r, Color("3e4f96"), Color("1f2754"), 24)
	intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 62), "⚔ Duelo", 40, Color("ffd34d"), intro.f_titulo, 2.2, true)
	intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 100), "Esperando %s aceitar..." % str(esperando.nome), 24, Color.WHITE, intro.f_titulo, 1.6, true)
	intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 126), texto_aposta(int(esperando.get("moedas", 0)), int(esperando.get("trofeus", 0))), 16, Color("ffd34d"), intro.f_texto, 1.1, true)
	var falta := maxi(0, ceili(DUELO_TEMPO - float(esperando.t)))
	var c := Vector2(r.get_center().x, r.position.y + 158)
	draw_arc(c, 18, _relogio * 5.0, _relogio * 5.0 + 4.2, 24, intro.OURO2, 5, true)
	intro._texto_cartoon(Vector2(r.get_center().x + 40, c.y + 7), "%ds" % falta, 18, Color("c9d2ff"), intro.f_texto, 1.2, false)
	_botao(Rect2(r.get_center().x - 110, r.end.y - 84, 220, 58), "Cancelar", Color("8a8fa8"), Color("626780"), Color("43475c"), func(): _cancelar_meu_duelo(), 24, "duelo")
