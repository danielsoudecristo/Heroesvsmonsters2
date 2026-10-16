extends Control
## TELA DO CAMPEONATO: a árvore grande (16 -> 8 -> 4 -> 2 -> campeão), que dá para ARRASTAR (e dar zoom com a
## roda do mouse ou com dois dedos). Cada vaga é um escudo dourado com a foto (Google, para quem entrou com a
## conta; retrato de um personagem, para os bots) e o nome embaixo: LARANJA = Heroes, VERDE = Monsters, com o
## brasão do lado antes do nome. A luta do jogador pisca com o "VS" e o botão JOGAR leva para a batalha.
## Regras e chaveamento: scripts/sistema/campeonato.gd

const MUNDO := Vector2(2400, 1640)
const XS := [160.0, 520.0, 860.0]            ## x das colunas do lado esquerdo (oitavas, quartas, semi); a direita espelha
const Y0 := 240.0                            ## y da 1ª vaga das oitavas
const DY := 172.0                            ## espaço entre as vagas das oitavas
const FINAL_DX := 150.0                      ## distância dos finalistas até o meio
const Y_TROFEU := -395.0                    ## (em relação ao meio da árvore) troféu, campeão e finalistas
const Y_CAMPEAO := -175.0
const Y_FINALISTAS := 70.0
const COR_HEROES := Color("ffa23a")
const COR_MONSTERS := Color("7ee04a")
const OURO := Color("f6c343")
const OURO_ESCURO := Color("8a5a10")
const CONTORNO := Color("1d1206")
const ZOOM_MIN := 0.42
const ZOOM_MAX := 1.35

var cam := Vector2(1200, 700)                ## ponto do mundo no meio da tela
var zoom := 0.62
var _cam_alvo := Vector2.ZERO
var _vel := Vector2.ZERO
var _arrastando := false
var _arr_ini := Vector2.ZERO
var _arr_cam := Vector2.ZERO
var _moveu := 0.0
var _toques := {}                            ## dedo -> posição (zoom com dois dedos)
var _dist_pinca := 0.0
var _relogio := 0.0
var _entra := 0.0                            ## animação de abertura
var _ajuda := false
var _apertado := ""
var _retratos := {}                          ## id do personagem -> [Texture2D, Rect2 da cabeça]
var _imgs := {}                              ## caminho da textura -> Image (para medir o retrato)
var _faiscas: Array = []
var _aviso := ""                             ## resultado da última luta (mostra em cima)
var _aviso_t := 0.0
var f_titulo: Font
var f_texto: Font
var sem_faixa := false                        ## (modo trailer) esconde a faixa de convidado / sem conexão

# ================================================================== COMEÇO
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	f_titulo = _fonte("Fontes/lilita-one-latin-400-normal.woff2")
	f_texto = _fonte("Fontes/fredoka-latin-700-normal.woff2")
	Perfil.carregar()
	Campeonato.carregar()
	if Conta.online_pronto():                    # COM CONTA: campeonato online (pessoas reais + bots nas vagas que faltarem)
		_online = true
		if Campeonato.online and Campeonato.status in ["andando", "fim"]:
			_perguntar()                         # voltando de uma luta: só atualiza
		else:                                    # ainda não entrou: a sala de entrada escolhe o lado
			_ir_sala.call_deferred()
	elif not Campeonato.ativo or Campeonato.online:
		Campeonato.novo("monsters" if Perfil.lado == "monsters" else "heroes")
	if Campeonato.ultimo != "":
		_aviso = Campeonato.ultimo
		_aviso_t = 5.0
		Campeonato.ultimo = ""
	for i in 40:
		_faiscas.append([Vector2(randf() * MUNDO.x, randf() * MUNDO.y), randf_range(8.0, 26.0), randf() * TAU, randf_range(1.0, 2.6)])
	_cam_alvo = _foco()
	cam = _cam_alvo + Vector2(0, 160)
	Conta.estou("campeonato", Campeonato.FASES_CURTO[mini(Campeonato.fase, 3)])

func _fonte(c: String) -> Font:
	var cam_f := "res://assets/" + c
	return load(cam_f) if ResourceLoader.exists(cam_f) else ThemeDB.fallback_font

# ================================================================== ONLINE
var _online := false
var _pedindo := false
var _pergunta_t := 0.0
var _fotos_url := {}                         ## url -> Texture2D (null enquanto baixa)
var _carregou := false
var _falta_t := 0.0
var _prazo_t := 0.0

func _entrar_online() -> void:
	_pedindo = true
	var lado := "monsters" if Perfil.lado == "monsters" else "heroes"
	var r: Dictionary = await Conta.chamar("entrar_campeonato", {"p_lado": lado})
	_pedindo = false
	_receber(r)

func _perguntar() -> void:
	if _pedindo:
		return
	_pedindo = true
	var r: Dictionary = await Conta.chamar("estado_campeonato")
	_pedindo = false
	_receber(r)

func _receber(r: Dictionary) -> void:
	if r.ok and r.dados is Dictionary:
		var antes_fase := Campeonato.fase
		var antes_status := Campeonato.status
		Campeonato.de_servidor(r.dados)
		_falta_t = Campeonato.falta
		_prazo_t = Campeonato.prazo
		if not _carregou or antes_status != Campeonato.status or antes_fase != Campeonato.fase:
			_cam_alvo = _foco()
			if _carregou and antes_status == "aberto" and Campeonato.status == "andando":
				_aviso = "O campeonato começou! Boa sorte!"
				_aviso_t = 4.0
		_carregou = true
	elif not r.ok and not _carregou:                # sem internet: joga o campeonato contra bots
		_online = false
		Campeonato.novo("monsters" if Perfil.lado == "monsters" else "heroes")
		_aviso = "Sem conexão com o servidor."
		_aviso_t = 4.0
		_carregou = true

## Foto de uma pessoa (url do Google): baixa uma vez e guarda.
func _foto_url(url: String) -> Texture2D:
	if url == "" or not url.begins_with("http"):
		return null
	if _fotos_url.has(url):
		return _fotos_url[url]
	_fotos_url[url] = null
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
	_fotos_url[url] = ImageTexture.create_from_image(img)

## Onde a câmera começa: na luta do jogador (ou no campeão, se acabou).
func _foco() -> Vector2:
	var m := Campeonato.minha_luta()
	var f := Campeonato.fase
	if m < 0 or f > 3:
		return Vector2(MUNDO.x / 2.0, _yc() - 120.0)
	if f == 3:
		return Vector2(MUNDO.x / 2.0, _yc())
	var a := _pos(f, m * 2)
	var b := _pos(f, m * 2 + 1)
	return Vector2((a.x + _pos(f + 1, m).x) / 2.0, (a.y + b.y) / 2.0)

# ================================================================== GEOMETRIA DA ÁRVORE
## Posição (no mundo) de quem está na coluna f (0 oitavas .. 3 finalistas), índice g.
func _pos(f: int, g: int) -> Vector2:
	var n := 16 >> f
	if f >= 3:
		return Vector2(MUNDO.x / 2.0 + (-FINAL_DX if g == 0 else FINAL_DX), _yc() + Y_FINALISTAS)
	var metade := n / 2
	var esq := g < metade
	var k := g if esq else g - metade
	var x: float = XS[f] if esq else MUNDO.x - XS[f]
	return Vector2(x, _y(f, k))

func _y(f: int, k: int) -> float:
	if f == 0:
		return Y0 + k * DY
	return (_y(f - 1, k * 2) + _y(f - 1, k * 2 + 1)) / 2.0

func _yc() -> float:
	return (_y(0, 0) + _y(0, 7)) / 2.0

## Quem está na coluna f, índice g (-1 = ainda não se sabe).
func _quem(f: int, g: int) -> int:
	if f == 0:
		return g
	return int(Campeonato.vencedores[f - 1][g])

# ================================================================== QUADRO
func _process(dt: float) -> void:
	_relogio += dt
	_entra = minf(1.0, _entra + dt * 1.2)
	if _online:
		_pergunta_t -= dt
		if _pergunta_t <= 0.0:
			_pergunta_t = 2.0
			_perguntar()
		_falta_t = maxf(0.0, _falta_t - dt)                    # relógios andando entre uma pergunta e outra
		_prazo_t = maxf(0.0, _prazo_t - dt)
	if _aviso_t > 0.0:
		_aviso_t -= dt
	if not _arrastando:
		if _vel.length() > 5.0:                               # inércia depois de soltar
			cam -= _vel * dt / zoom
			_vel *= pow(0.04, dt)
			_cam_alvo = cam
		else:
			cam = cam.lerp(_cam_alvo, minf(1.0, dt * 3.0))
	_limitar()
	for fa in _faiscas:
		fa[0].y -= fa[1] * dt
		fa[2] += dt
		if fa[0].y < -20:
			fa[0] = Vector2(randf() * MUNDO.x, MUNDO.y + 20)
	queue_redraw()

func _limitar() -> void:
	var meia := size / 2.0 / zoom
	var folga := Vector2(160, 140)
	cam.x = clampf(cam.x, minf(meia.x - folga.x, MUNDO.x / 2.0), maxf(MUNDO.x - meia.x + folga.x, MUNDO.x / 2.0))
	cam.y = clampf(cam.y, minf(meia.y - folga.y - 60.0, MUNDO.y / 2.0), maxf(MUNDO.y - meia.y + folga.y, MUNDO.y / 2.0))

func _para_tela(p: Vector2) -> Vector2:
	return (p - cam) * zoom + size / 2.0

func _para_mundo(p: Vector2) -> Vector2:
	return (p - size / 2.0) / zoom + cam

# ================================================================== ENTRADA
func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_toques[ev.index] = ev.position
		else:
			_toques.erase(ev.index)
		_dist_pinca = 0.0
		return
	if ev is InputEventScreenDrag:
		_toques[ev.index] = ev.position
		if _toques.size() >= 2:                               # dois dedos: zoom
			var ps: Array = _toques.values()
			var d: float = ps[0].distance_to(ps[1])
			if _dist_pinca > 0.0:
				_zoom_em((ps[0] + ps[1]) / 2.0, d / _dist_pinca)
			_dist_pinca = d
			_arrastando = false
		return
	if ev is InputEventMagnifyGesture:
		_zoom_em(ev.position, ev.factor)
		return
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			_zoom_em(ev.position, 1.12)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			_zoom_em(ev.position, 1.0 / 1.12)
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_apertado = _botao_em(ev.position)
				_arrastando = _apertado == "" and _toques.size() < 2
				_arr_ini = ev.position
				_arr_cam = cam
				_moveu = 0.0
				_vel = Vector2.ZERO
			else:
				var b := _botao_em(ev.position)
				if _apertado != "" and b == _apertado:
					_tocar(b)
				elif _ajuda and _moveu < 8.0:
					_ajuda = false
				_apertado = ""
				_arrastando = false
		accept_event()
	elif ev is InputEventMouseMotion and _arrastando:
		cam = _arr_cam - (ev.position - _arr_ini) / zoom
		_cam_alvo = cam
		_moveu += ev.relative.length()
		_vel = _vel.lerp(ev.relative / maxf(get_process_delta_time(), 0.001), 0.35)
		accept_event()

func _zoom_em(tela: Vector2, fator: float) -> void:
	var antes := _para_mundo(tela)
	zoom = clampf(zoom * fator, ZOOM_MIN, ZOOM_MAX)
	cam += antes - _para_mundo(tela)
	_cam_alvo = cam

func _unhandled_key_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel"):
		_tocar("menu")

## Botões fixos na tela.
func _rets() -> Dictionary:
	var r := {}
	r["menu"] = Rect2(18, 16, 128, 48)
	r["ajuda"] = Rect2(size.x - 66, 16, 48, 48)
	var barra := _ret_barra()
	r["jogar"] = Rect2(barra.end.x - 236, barra.position.y + 16, 216, barra.size.y - 32)
	r["zoom_mais"] = Rect2(size.x - 66, 80, 48, 44)
	r["zoom_menos"] = Rect2(size.x - 66, 130, 48, 44)
	if not _online and not sem_faixa:            # só bots: botão para entrar na conta / tentar de novo
		var fx := _ret_faixa_offline()
		r["entrar"] = Rect2(fx.end.x - 150, fx.position.y + 8, 140, fx.size.y - 16)
	return r

## Faixa "só bots" embaixo do título (convidado ou sem conexão).
func _ret_faixa_offline() -> Rect2:
	return Rect2(size.x / 2.0 - 330, 82, 660, 58)

func _ret_barra() -> Rect2:
	var w := minf(880.0, size.x - 40.0)
	return Rect2(size.x / 2.0 - w / 2.0, size.y - 104, w, 90)

func _botao_em(p: Vector2) -> String:
	if _ajuda:
		return "ajuda_fora"
	var r := _rets()
	for k in r:
		if k == "jogar" and not _pode_jogar() and not _acabou_para_mim():
			continue
		if r[k].grow(4).has_point(p):
			return k
	return ""

func _pode_jogar() -> bool:
	if _online and (Campeonato.status != "andando" or Campeonato.esperando_outras() or _pedindo_sala):
		return false
	return Campeonato.ativo and Campeonato.voce >= 0 and Campeonato.minha_luta() >= 0 and Campeonato.fase <= 3

func _acabou_para_mim() -> bool:
	if _online and Campeonato.status == "aberto":
		return false
	return Campeonato.fase > 3 or Campeonato.eliminado()

func _sala_espera() -> bool:
	return _online and (not _carregou or Campeonato.status == "aberto")

func _tocar(b: String) -> void:
	Sons.tocar("Jogo/som/clique", 0.5)
	match b:
		"menu":
			if _online and Campeonato.status == "aberto":
				Conta.chamar("sair_campeonato")          # saiu da sala de espera: libera a vaga
				Campeonato.status = ""
			Conta.estou("menu")
			get_tree().change_scene_to_file("res://cenas/intro.tscn")
		"ajuda":
			_ajuda = true
		"ajuda_fora":
			_ajuda = false
		"entrar":
			if Conta.online_pronto():                # já tem conta conectada: a sala de entrada online
				Campeonato.ativo = false
				_ir_sala()
			elif Conta.logado():                     # tem conta, mas o servidor não respondeu
				_aviso = "Sem conexão com o servidor. Tente de novo em instantes."
				_aviso_t = 3.0
			else:                                    # convidado: vai para o login e volta para cá
				Perfil.login_campeonato = true
				Conta.estou("menu")
				get_tree().change_scene_to_file("res://cenas/intro.tscn")
		"zoom_mais":
			_zoom_em(size / 2.0, 1.2)
		"zoom_menos":
			_zoom_em(size / 2.0, 1.0 / 1.2)
		"jogar":
			if _pode_jogar():
				_jogar()
			elif _acabou_para_mim():
				Campeonato.ativo = false
				_ir_sala()                           # um campeonato novo: pela sala de entrada

var _pedindo_sala := false

## Sala de entrada do campeonato (escolhe o lado vendo quem está entrando, com chat).
func _ir_sala() -> void:
	Perfil.sala_modo = "campeonato"
	get_tree().change_scene_to_file("res://cenas/sala_entrada.tscn")

func _jogar() -> void:
	var adv := Campeonato.adversario()
	Perfil.pvp_modo = "normal"
	Perfil.pvp_sala = {}
	Perfil.pvp_adversario = str(Campeonato.vagas[adv].nome)
	if _online and Campeonato.adversario_pessoa():     # contra uma PESSOA: partida online de verdade
		_pedindo_sala = true
		var r: Dictionary = await Conta.chamar("campeonato_sala")
		var token: String = await Conta.token_fresco()
		_pedindo_sala = false
		if not r.ok or not (r.dados is Dictionary) or not r.dados.has("id"):
			_aviso = "Não deu para abrir a luta. Tente de novo."
			_aviso_t = 3.0
			return
		var s: Dictionary = r.dados.duplicate()
		s["token"] = token
		s["lado"] = "heroes" if str(s.get("heroes", "")) == Conta.meu_id() else "monsters"
		Perfil.pvp_sala = s
	Campeonato.em_partida = true
	Campeonato.salvar()
	get_tree().change_scene_to_file("res://cenas/pvp.tscn")

# ================================================================== DESENHO
func _draw() -> void:
	_fundo()
	draw_set_transform(size / 2.0 - cam * zoom, 0.0, Vector2(zoom, zoom))
	_desenhar_mundo()
	draw_set_transform(Vector2.ZERO)
	if _sala_espera():
		_painel_espera()
	_hud()
	if _ajuda:
		_painel_ajuda()

func _fundo() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]),
		PackedColorArray([Color("1b1640"), Color("1b1640"), Color("07091a"), Color("07091a")]))
	# luzes: laranja (Heroes) à esquerda, verde (Monsters) à direita, dourado no meio (a final)
	var c := _para_tela(Vector2(MUNDO.x / 2.0, _yc()))
	for k in 6:
		var a := 0.05 * (1.0 - k / 6.0)
		draw_circle(_para_tela(Vector2(XS[1], _yc())), (700.0 - k * 90.0) * zoom, Color(COR_HEROES, a * 0.6))
		draw_circle(_para_tela(Vector2(MUNDO.x - XS[1], _yc())), (700.0 - k * 90.0) * zoom, Color(COR_MONSTERS, a * 0.6))
		draw_circle(c, (560.0 - k * 80.0) * zoom, Color(OURO, a))

func _desenhar_mundo() -> void:
	# faíscas subindo
	for fa in _faiscas:
		var brilho := 0.35 + 0.35 * sin(fa[2] * fa[3])
		draw_circle(fa[0], 2.2, Color(1.0, 0.85, 0.45, brilho * 0.6))
	_cabecalhos()
	if Campeonato.vagas.size() < 16 or Campeonato.vencedores.size() < 4:
		return                                           # (sala de espera: a árvore ainda não foi montada)
	_linhas()
	_final_e_trofeu()
	# vagas (aparecem coluna por coluna na abertura)
	for f in 4:
		var n := 16 >> f
		var aparece := clampf(_entra * 4.0 - f * 0.6, 0.0, 1.0)
		if aparece <= 0.0:
			continue
		for g in n:
			_vaga(_pos(f, g) + Vector2(0, (1.0 - _ease(aparece)) * 30.0), _quem(f, g), f, aparece)
	_vs_da_minha_luta()

func _cabecalhos() -> void:
	for f in 3:
		for lado in [0, 1]:
			var x: float = XS[f] if lado == 0 else MUNDO.x - XS[f]
			_placa_fase(Vector2(x, 92), f)
	_placa_fase(Vector2(MUNDO.x / 2.0, 92), 3)

## Placa da fase: nome + quantos jogadores ainda estão na disputa.
func _placa_fase(c: Vector2, f: int) -> void:
	var larg := 230.0 if f < 3 else 290.0
	var r := Rect2(c.x - larg / 2.0, c.y - 40, larg, 74)
	var cor: Color = Campeonato.COR_FASE[f]
	var atual := Campeonato.fase == f and Campeonato.minha_luta() >= 0
	if atual:
		var pul := 0.5 + 0.5 * sin(_relogio * 4.0)
		_caixa(r.grow(6 + pul * 4), Color(cor, 0.25), 22)
	_caixa(Rect2(r.position + Vector2(0, 6), r.size), Color(0, 0, 0, 0.45), 18)
	_caixa(r.grow(3), CONTORNO, 20)
	_caixa(r, Color("2b2f6a"), 18)
	_caixa(Rect2(r.position, Vector2(r.size.x, 36)), Color("3d4596"), 18)
	_texto(Vector2(c.x, r.position.y + 28), Campeonato.FASES[f], 22 if f < 3 else 26, Color.WHITE, true, 4)
	_texto(Vector2(c.x, r.position.y + 61), "%d jogadores" % (16 >> f), 16, cor.lightened(0.35), true, 3)

## Linhas do chaveamento: de cada dupla até o vencedor (douradas quando já foi decidido).
func _linhas() -> void:
	for f in 4:
		var lutas: Array = Campeonato.vencedores[f]
		for m in lutas.size():
			var a := _pos(f, m * 2)
			var b := _pos(f, m * 2 + 1)
			var venc := int(lutas[m])
			var dest: Vector2
			if f < 3:
				dest = _pos(f + 1, m)
			else:
				dest = Vector2(MUNDO.x / 2.0, _yc() + Y_CAMPEAO)
			if f < 3:
				var esq := a.x < MUNDO.x / 2.0
				var s := 1.0 if esq else -1.0
				var xm := (a.x + dest.x) / 2.0
				for i in 2:
					var p := a if i == 0 else b
					var quem := _quem(f, m * 2 + i)
					var ganhou := venc >= 0 and venc == quem
					var perdeu := venc >= 0 and venc != quem
					var cor := OURO if ganhou else (Color(1, 1, 1, 0.12) if perdeu else Color(1, 1, 1, 0.32))
					var pts := PackedVector2Array([p + Vector2(s * 80, 0), Vector2(xm, p.y), Vector2(xm, dest.y)])
					if ganhou:
						draw_polyline(pts, Color(OURO, 0.25), 12.0, true)
					draw_polyline(pts, cor, 4.0 if ganhou else 3.0, true)
				var vai := OURO if venc >= 0 else Color(1, 1, 1, 0.32)
				draw_line(Vector2(xm, dest.y), dest - Vector2(s * 80, 0), vai, 4.0 if venc >= 0 else 3.0, true)
				if venc >= 0:                                     # brilho correndo pela linha dourada
					var k := fmod(_relogio * 0.6 + m * 0.17 + f * 0.3, 1.0)
					draw_circle(Vector2(xm, lerpf(a.y if _quem(f, m * 2) == venc else b.y, dest.y, k)), 4.0, Color(1, 0.95, 0.7, 0.8))
			else:                                                 # final -> campeão: sobe dos dois finalistas
				var ym := (a.y - 78.0 + dest.y + 100.0) / 2.0
				for i in 2:
					var p := a if i == 0 else b
					var quem := _quem(f, i)
					var ganhou := venc >= 0 and venc == quem
					var cor := OURO if ganhou else Color(1, 1, 1, 0.3)
					var pts := PackedVector2Array([p + Vector2(0, -78), Vector2(p.x, ym), Vector2(dest.x, ym)])
					if ganhou:
						draw_polyline(pts, Color(OURO, 0.25), 12.0, true)
					draw_polyline(pts, cor, 4.0, true)
				draw_line(Vector2(dest.x, ym), dest + Vector2(0, 100), OURO if venc >= 0 else Color(1, 1, 1, 0.3), 4.0, true)

## Centro: troféu, "HEROES x MONSTERS" e o campeão.
func _final_e_trofeu() -> void:
	var c := Vector2(MUNDO.x / 2.0, _yc())
	# arena da final: um círculo de luz dourada
	draw_circle(c + Vector2(0, -60), 330, Color(OURO, 0.05))
	draw_arc(c + Vector2(0, -60), 320, 0, TAU, 72, Color(OURO, 0.25), 3.0, true)
	# HEROES x MONSTERS embaixo da final
	var y := c.y + Y_FINALISTAS + 130
	_brasao("heroes", Vector2(c.x - 150, y), 44)
	_brasao("monsters", Vector2(c.x + 150, y), 44)
	_texto(Vector2(c.x - 64, y + 10), "HEROES", 22, COR_HEROES, true, 4)
	_texto(Vector2(c.x + 66, y + 10), "MONSTERS", 22, COR_MONSTERS, true, 4)
	_texto(Vector2(c.x, y + 9), "×", 26, Color.WHITE, true, 4)
	# troféu + campeão
	var t := Vector2(c.x, c.y + Y_TROFEU)
	var pul := 0.5 + 0.5 * sin(_relogio * 2.0)
	for k in 8:                                               # raios girando atrás do troféu
		var a := _relogio * 0.4 + k * TAU / 8.0
		var p1 := t + Vector2(cos(a), sin(a)) * 40
		var p2 := t + Vector2(cos(a + 0.18), sin(a + 0.18)) * 170
		var p3 := t + Vector2(cos(a - 0.18), sin(a - 0.18)) * 170
		draw_colored_polygon(PackedVector2Array([p1, p2, p3]), Color(OURO, 0.06 + 0.03 * pul))
	_trofeu(t + Vector2(0, -8), 1.6)
	var camp := Campeonato.campeao()
	_texto(Vector2(t.x, t.y + 78), "CAMPEÃO", 28 if camp >= 0 else 24, Color(OURO, 1.0 if camp >= 0 else 0.75), true, 6)
	var pc := Vector2(c.x, c.y + Y_CAMPEAO)
	if camp >= 0:
		_vaga(pc, camp, 4, 1.0)
	else:
		_vaga(pc, -1, 4, 0.9)

## O "VS" pulsando entre o jogador e o adversário da luta atual.
func _vs_da_minha_luta() -> void:
	var m := Campeonato.minha_luta()
	var f := Campeonato.fase
	if m < 0 or f > 3 or Campeonato.esperando_outras():
		return
	var a := _pos(f, m * 2)
	var b := _pos(f, m * 2 + 1)
	var c := (a + b) / 2.0
	if f < 3:
		c.x = (a.x + _pos(f + 1, m).x) / 2.0
	var pul := 0.5 + 0.5 * sin(_relogio * 5.0)
	draw_circle(c, 34 + pul * 6, Color(Campeonato.COR_FASE[f], 0.25))
	draw_circle(c, 29, CONTORNO)
	draw_circle(c, 26, Campeonato.COR_FASE[f].darkened(0.2))
	draw_circle(c + Vector2(-4, -6), 14, Color(1, 1, 1, 0.18))
	_texto(Vector2(c.x, c.y + 10), "VS", 26, Color.WHITE, true, 5)

## Uma vaga: escudo dourado com a foto + placa do nome (brasão + nome na cor do lado).
## f: coluna (4 = o campeão, maior). quem < 0: ainda não se sabe (escudo com "?").
func _vaga(c: Vector2, quem: int, f: int, alfa: float) -> void:
	var esc := 1.25 if f == 4 else 1.0
	var w := 96.0 * esc
	var h := 110.0 * esc
	var centro := c + Vector2(0, -16 * esc)
	if quem < 0:
		_escudo(centro, w, h, Color("2b2f55"), OURO if f == 4 else Color(1, 1, 1, 0.25), alfa * 0.8)
		_texto(Vector2(centro.x, centro.y + 14), "?", 40, Color(1, 1, 1, 0.35 * alfa), true, 4)
		return
	var v: Dictionary = Campeonato.vagas[quem]
	var lado: String = v.lado
	var cor_lado := COR_HEROES if lado == "heroes" else COR_MONSTERS
	# perdeu numa fase já decidida: fica apagada
	var apagada := false
	if f <= 3 and f < 4:
		var m := g_luta(f, quem)
		if m >= 0 and int(Campeonato.vencedores[f][m]) >= 0 and int(Campeonato.vencedores[f][m]) != quem:
			apagada = true
	var e_voce := quem == Campeonato.voce
	var a := alfa * (0.42 if apagada else 1.0)
	if e_voce and not apagada:
		var pul := 0.5 + 0.5 * sin(_relogio * 3.5)
		_escudo_brilho(centro, w + 22 + pul * 8, h + 22 + pul * 8, Color(OURO, 0.35 * a))
	_escudo(centro, w, h, cor_lado.darkened(0.55), OURO if not apagada else Color(0.6, 0.6, 0.6), a)
	_foto(centro, w * 0.78, h * 0.78, v, a, apagada)
	if apagada:                                               # X vermelho de eliminado
		var s := 22.0
		draw_line(centro + Vector2(-s, -s), centro + Vector2(s, s), Color(0.85, 0.15, 0.15, 0.75 * alfa), 6.0, true)
		draw_line(centro + Vector2(s, -s), centro + Vector2(-s, s), Color(0.85, 0.15, 0.15, 0.75 * alfa), 6.0, true)
	# placa do nome
	var nome: String = v.nome
	if nome.length() > 13:
		nome = nome.substr(0, 12) + "…"
	var tam := 16 if f < 4 else 19
	var larg_txt := f_titulo.get_string_size(nome, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	var pw := larg_txt + 46
	var placa := Rect2(c.x - pw / 2.0, c.y + h * 0.5 - 12 * esc, pw, 30)
	_caixa(placa.grow(2), Color(CONTORNO, a), 10)
	_caixa(placa, Color(0.08, 0.07, 0.12, 0.92 * a), 9)
	_caixa(Rect2(placa.position.x, placa.end.y - 4, placa.size.x, 4), Color(cor_lado, 0.85 * a), 2)
	_brasao(lado, Vector2(placa.position.x + 17, placa.get_center().y - 1), 22, a)
	_texto(Vector2(placa.position.x + 32, placa.position.y + 21), nome, tam, Color(cor_lado, a), false, 3)
	if e_voce:                                                # fita "VOCÊ"
		var fr := Rect2(centro.x - 32, centro.y - h * 0.5 - 14, 64, 22)
		_caixa(fr.grow(2), Color(CONTORNO, a), 8)
		_caixa(fr, Color(OURO, a), 7)
		_texto(Vector2(fr.get_center().x, fr.position.y + 17), "VOCÊ", 15, Color(CONTORNO, a), true, 0)
	if f == 4:                                                # coroa no campeão
		var k := centro + Vector2(0, -h * 0.5 - 22)
		draw_colored_polygon(PackedVector2Array([k + Vector2(-26, 12), k + Vector2(-26, -8), k + Vector2(-13, 2), k + Vector2(0, -14),
			k + Vector2(13, 2), k + Vector2(26, -8), k + Vector2(26, 12)]), OURO)
		draw_polyline(PackedVector2Array([k + Vector2(-26, 12), k + Vector2(-26, -8), k + Vector2(-13, 2), k + Vector2(0, -14),
			k + Vector2(13, 2), k + Vector2(26, -8), k + Vector2(26, 12), k + Vector2(-26, 12)]), CONTORNO, 3.0, true)

## Em qual luta da fase f a vaga "quem" está (-1 = não está nesta fase).
func g_luta(f: int, quem: int) -> int:
	for m in Campeonato.vencedores[f].size():
		if quem in Campeonato.lutadores(f, m):
			return m
	return -1

# ---------------------------------------------------------------- escudo e foto
## Contorno do escudo (igual à imagem do perfil): topo com dois chanfros, laterais retas e ponta embaixo.
func _pts_escudo(c: Vector2, w: float, h: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var hw := w / 2.0; var hh := h / 2.0
	p.append(c + Vector2(-hw * 0.70, -hh))
	p.append(c + Vector2(-hw * 0.30, -hh * 0.90))
	p.append(c + Vector2(0, -hh * 0.98))
	p.append(c + Vector2(hw * 0.30, -hh * 0.90))
	p.append(c + Vector2(hw * 0.70, -hh))
	p.append(c + Vector2(hw, -hh * 0.80))
	p.append(c + Vector2(hw * 0.94, -hh * 0.42))
	for i in range(0, 9):                                        # lado direito descendo em curva até a ponta
		var k := float(i) / 8.0
		var x := hw * 0.94 * (1.0 - k * k)
		var y := -hh * 0.42 + (hh * 1.42) * (1.0 - pow(1.0 - k, 1.6))
		p.append(c + Vector2(x, y))
	for i in range(7, -1, -1):
		var k := float(i) / 8.0
		var x := -hw * 0.94 * (1.0 - k * k)
		var y := -hh * 0.42 + (hh * 1.42) * (1.0 - pow(1.0 - k, 1.6))
		p.append(c + Vector2(x, y))
	p.append(c + Vector2(-hw * 0.94, -hh * 0.42))
	p.append(c + Vector2(-hw, -hh * 0.80))
	return p

func _escudo(c: Vector2, w: float, h: float, cor: Color, borda: Color, a: float) -> void:
	var sombra := _pts_escudo(c + Vector2(0, 7), w, h)
	draw_colored_polygon(sombra, Color(0, 0, 0, 0.4 * a))
	var fora := _pts_escudo(c, w + 10, h + 10)
	draw_colored_polygon(fora, Color(CONTORNO, a))
	var aro := _pts_escudo(c, w + 4, h + 4)
	draw_colored_polygon(aro, Color(borda, a))
	var brilho := _pts_escudo(c + Vector2(0, -2), w - 2, h - 4)
	draw_colored_polygon(brilho, Color(borda.lightened(0.35), a * 0.6))
	draw_colored_polygon(_pts_escudo(c, w - 6, h - 6), Color(borda.darkened(0.35), a))
	draw_colored_polygon(_pts_escudo(c, w - 12, h - 12), Color(cor, a))

func _escudo_brilho(c: Vector2, w: float, h: float, cor: Color) -> void:
	for k in 3:
		draw_colored_polygon(_pts_escudo(c, w + k * 8, h + k * 8), Color(cor, cor.a * (1.0 - k * 0.3)))

## Foto dentro do escudo: Google (você), retrato do personagem (bots) ou a inicial do nome.
func _foto(c: Vector2, w: float, h: float, v: Dictionary, a: float, cinza: bool) -> void:
	var pts := _pts_escudo(c, w, h)
	var tex: Texture2D = null
	var reg := Rect2()
	var foto_real: Texture2D = Conta.foto if v.tipo == "voce" else null
	if foto_real == null and v.tipo in ["voce", "pessoa"]:
		foto_real = _foto_url(str(v.get("foto_url", "")))
	if foto_real:                                                # pessoa de verdade: a foto do Google
		tex = foto_real
		var ts := tex.get_size()
		var asp := w / h
		var rw := minf(ts.x, ts.y * asp)
		reg = Rect2((ts.x - rw) / 2.0, 0, rw, rw / asp)
	elif v.tipo == "bot":
		var rt := _retrato(str(v.personagem))
		if not rt.is_empty():
			tex = rt[0]
			reg = rt[1]
	if tex == null:                                              # sem foto: a inicial do nome
		var cor := COR_HEROES if v.lado == "heroes" else COR_MONSTERS
		draw_colored_polygon(pts, Color(cor.darkened(0.35), a))
		_texto(Vector2(c.x, c.y + 18), str(v.nome).substr(0, 1).to_upper(), 48, Color(1, 1, 1, a), true, 5)
		return
	var ts2 := tex.get_size()
	var uvs := PackedVector2Array()
	for p in pts:
		var k := (p - c) / Vector2(w, h) + Vector2(0.5, 0.5)
		uvs.append((reg.position + k * reg.size) / ts2)
	var fundo := (COR_HEROES if v.lado == "heroes" else COR_MONSTERS).darkened(0.62)
	draw_colored_polygon(pts, Color(fundo, a))
	var cor_foto := Color(0.55, 0.55, 0.55, a) if cinza else Color(1, 1, 1, a)
	var cores := PackedColorArray()
	cores.resize(pts.size())
	cores.fill(cor_foto)
	draw_polygon(pts, cores, uvs, tex)
	# brilho de vidro em cima
	draw_colored_polygon(_pts_escudo(c + Vector2(0, -h * 0.22), w * 0.8, h * 0.4), Color(1, 1, 1, 0.07 * a))

## Retrato (cabeça e ombros) de um personagem: do 1º quadro da pose parada, medido uma vez.
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
			# cabeça: centro da faixa de cima do desenho; recorte com o formato do escudo (0,87 x 1)
			var cx := u.get_center().x
			if img:
				var faixa := _area(img, Rect2i(int(u.position.x), int(u.position.y + u.size.y * 0.06), int(u.size.x), int(maxf(4.0, u.size.y * 0.2))))
				cx = faixa.get_center().x
			var hgt := u.size.y * 0.5
			var wid := hgt * 0.87
			r = [an.textura, Rect2(cx - wid / 2.0, u.position.y - hgt * 0.04, wid, hgt)]
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

# ---------------------------------------------------------------- HUD fixo
func _hud() -> void:
	var r := _rets()
	# título
	var t := "CAMPEONATO"
	_caixa(Rect2(size.x / 2.0 - 250, 10, 500, 62).grow(3), CONTORNO, 22)
	_caixa(Rect2(size.x / 2.0 - 250, 10, 500, 62), Color("3a2a0a"), 20)
	_caixa(Rect2(size.x / 2.0 - 250, 10, 500, 30), Color("6a4a12"), 20)
	_trofeu(Vector2(size.x / 2.0 - 190, 42), 0.42)
	_trofeu(Vector2(size.x / 2.0 + 190, 42), 0.42)
	_texto(Vector2(size.x / 2.0, 48), t, 32, OURO, true, 6)
	_texto(Vector2(size.x / 2.0, 66), "Heroes × Monsters · 16 jogadores", 13, Color("e8d9b0"), true, 3)
	# menu / ajuda / zoom
	_botao(r["menu"], "← MENU", Color("4a5fae"))
	_botao(r["ajuda"], "?", Color("8a5cd6"))
	_botao(r["zoom_mais"], "+", Color("3a3f6a"))
	_botao(r["zoom_menos"], "−", Color("3a3f6a"))
	_texto(Vector2(24, size.y - 120), "Arraste para ver a árvore · role para zoom", 13, Color(1, 1, 1, 0.45), false, 2)
	# faixa "só bots": convidado (ou sem conexão) não entra na fila de pessoas reais
	if not _online and not sem_faixa:
		var fx := _ret_faixa_offline()
		var convidado := not Conta.logado()
		_caixa(Rect2(fx.position + Vector2(0, 5), fx.size), Color(0, 0, 0, 0.45), 18)
		_caixa(fx.grow(3), CONTORNO, 20)
		_caixa(fx, Color("4a1f2e"), 18)
		_caixa(Rect2(fx.position, Vector2(fx.size.x, fx.size.y * 0.45)), Color("6a2a3c"), 18)
		_texto(Vector2(fx.position.x + 20, fx.position.y + 25), "MODO CONVIDADO" if convidado else "SEM CONEXÃO", 18, OURO, false, 4)
		_texto(Vector2(fx.position.x + 20, fx.position.y + 47),
			"Entre na sua conta para enfrentar gente do mundo todo!" if convidado else "Não deu para falar com o servidor.", 14, Color("ffd8e0"), false, 3)
		_botao(r["entrar"], "ENTRAR" if convidado else "TENTAR", Color("3aa33a") if convidado else Color("d68a1a"))
	# barra de baixo: sua próxima luta
	var b := _ret_barra()
	_caixa(Rect2(b.position + Vector2(0, 6), b.size), Color(0, 0, 0, 0.5), 22)
	_caixa(b.grow(3), CONTORNO, 24)
	_caixa(b, Color("20244e"), 22)
	_caixa(Rect2(b.position, Vector2(b.size.x, b.size.y * 0.45)), Color("2d3370"), 22)
	var jx := b.position.x + 26
	if _pode_jogar():
		var f := Campeonato.fase
		var adv: Dictionary = Campeonato.vagas[Campeonato.adversario()]
		var cor_adv := COR_HEROES if adv.lado == "heroes" else COR_MONSTERS
		_texto(Vector2(jx, b.position.y + 32), "SUA LUTA · " + Campeonato.FASES[f], 21, OURO, false, 4)
		_brasao(adv.lado, Vector2(jx + 12, b.position.y + 62), 24)
		_texto(Vector2(jx + 30, b.position.y + 70), "contra " + str(adv.nome), 19, cor_adv, false, 3)
		_botao_grande(r["jogar"], "JOGAR", Color("3aa33a"))
	elif _sala_espera():
		_texto(Vector2(jx, b.position.y + 38), "SALA DE ESPERA", 24, OURO, false, 4)
		_texto(Vector2(jx, b.position.y + 68), "Esperando os jogadores... as vagas vão completando até fechar o tempo.", 16, Color("d8dcff"), false, 3)
	elif _online and _pedindo_sala:
		_texto(Vector2(jx, b.position.y + 50), "Abrindo a luta...", 24, OURO, false, 4)
	elif _online and Campeonato.esperando_outras() and Campeonato.fase <= 3:
		var mm := int(_prazo_t) / 60
		var ss := int(_prazo_t) % 60
		_texto(Vector2(jx, b.position.y + 38), "ESPERANDO AS OUTRAS LUTAS", 22, OURO, false, 4)
		_texto(Vector2(jx, b.position.y + 68), "%s fecha em até %d:%02d · quem não jogar perde por W.O." % [Campeonato.FASES_CURTO[Campeonato.fase], mm, ss], 16, Color("d8dcff"), false, 3)
	else:
		var camp := Campeonato.campeao()
		var msg := ""
		if camp == Campeonato.voce:
			msg = "VOCÊ É O CAMPEÃO!"
		elif Campeonato.eliminado() or Campeonato.fase > 3:
			msg = "Campeão: " + (str(Campeonato.vagas[camp].nome) if camp >= 0 else "?")
		_texto(Vector2(jx, b.position.y + 38), msg, 24, OURO, false, 4)
		_texto(Vector2(jx, b.position.y + 68), "Jogue de novo para chegar mais longe!", 16, Color("d8dcff"), false, 3)
		_botao_grande(r["jogar"], "NOVO", Color("d68a1a"))
	# aviso do resultado da última luta
	if _aviso_t > 0.0:
		var al := clampf(_aviso_t, 0.0, 1.0)
		var ar := Rect2(size.x / 2.0 - 300, 150 if not _online else 86, 600, 46)
		_caixa(ar.grow(3), Color(CONTORNO, al), 18)
		_caixa(ar, Color(0.12, 0.1, 0.05, 0.95 * al), 16)
		_texto(Vector2(size.x / 2.0, ar.position.y + 31), _aviso, 20, Color(OURO, al), true, 3)

func _botao(r: Rect2, txt: String, cor: Color) -> void:
	var rr := r
	if _apertado != "" and _rets().get(_apertado, Rect2()) == r:
		rr.position.y += 2
	_caixa(Rect2(rr.position + Vector2(0, 4), rr.size), Color(0, 0, 0, 0.45), 14)
	_caixa(rr.grow(2), CONTORNO, 14)
	_caixa(rr, cor.darkened(0.2), 12)
	_caixa(Rect2(rr.position, Vector2(rr.size.x, rr.size.y * 0.5)), cor.lightened(0.15), 12)
	_texto(Vector2(rr.get_center().x, rr.position.y + rr.size.y * 0.5 + 8), txt, 20, Color.WHITE, true, 4)

func _botao_grande(r: Rect2, txt: String, cor: Color) -> void:
	var pul := 0.5 + 0.5 * sin(_relogio * 4.0)
	_caixa(r.grow(5 + pul * 4), Color(cor, 0.25), 20)
	_botao(r, txt, cor)
	_texto(Vector2(r.get_center().x, r.position.y + r.size.y * 0.5 + 12), txt, 30, Color.WHITE, true, 6)

## SALA DE ESPERA (online): quem já entrou de cada lado (8 vagas), o relógio e o aviso dos bots.
func _painel_espera() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	var j := Rect2(size.x / 2.0 - 450, size.y / 2.0 - 215, 900, 400)
	_caixa(Rect2(j.position + Vector2(0, 10), j.size), Color(0, 0, 0, 0.5), 28)
	_caixa(j.grow(4), CONTORNO, 28)
	_caixa(j, Color("232a5e"), 26)
	_caixa(Rect2(j.position, Vector2(j.size.x, 74)), Color("3a2a0a"), 26)
	_texto(Vector2(j.get_center().x, j.position.y + 50), "SALA DE ESPERA", 34, OURO, true, 6)
	# relógio
	var seg := int(ceil(_falta_t))
	var rel := "Conectando..." if not _carregou else ("Começa em 0:%02d" % seg if seg > 0 else "Começando...")
	var pul := 0.5 + 0.5 * sin(_relogio * 4.0)
	var rr := Rect2(j.get_center().x - 130, j.position.y + 88, 260, 42)
	_caixa(rr.grow(3 + pul * 2), Color(OURO, 0.25), 20)
	_caixa(rr, Color("15193a"), 18)
	_texto(Vector2(rr.get_center().x, rr.position.y + 30), rel, 22, Color.WHITE, true, 4)
	# as duas fileiras: 8 vagas de cada lado
	var hs: Array = Campeonato.inscritos.filter(func(x): return str(x.get("lado", "")) == "heroes")
	var ms: Array = Campeonato.inscritos.filter(func(x): return str(x.get("lado", "")) == "monsters")
	_fileira(Vector2(j.position.x + 40, j.position.y + 160), "heroes", hs)
	_fileira(Vector2(j.position.x + 40, j.position.y + 262), "monsters", ms)
	_texto(Vector2(j.get_center().x, j.end.y - 20), "Com 8 de cada lado o campeonato começa na hora · as vagas completam até fechar os 2 minutos", 14, Color(1, 1, 1, 0.6), true, 2)

func _fileira(p: Vector2, lado: String, gente: Array) -> void:
	var cor := COR_HEROES if lado == "heroes" else COR_MONSTERS
	_brasao(lado, p + Vector2(18, 30), 34)
	_texto(Vector2(p.x + 42, p.y + 22), "HEROES" if lado == "heroes" else "MONSTERS", 18, cor, false, 3)
	_texto(Vector2(p.x + 42, p.y + 46), "%d / 8" % gente.size(), 18, Color.WHITE, false, 3)
	for i in 8:
		var c := p + Vector2(190 + i * 82, 30)
		if i < gente.size():
			var g: Dictionary = gente[i]
			draw_circle(c, 31, CONTORNO)
			draw_circle(c, 29, cor)
			var tex: Texture2D = Conta.foto if g.get("eu", false) and Conta.foto else _foto_url(str(g.get("foto", "")) if g.get("foto") != null else "")
			if tex:
				var pts := PackedVector2Array(); var uvs := PackedVector2Array()
				for k in 24:
					var a := TAU * k / 24.0
					pts.append(c + Vector2(cos(a), sin(a)) * 26)
					uvs.append(Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.5)
				var cores := PackedColorArray(); cores.resize(24); cores.fill(Color.WHITE)
				draw_polygon(pts, cores, uvs, tex)
			else:
				draw_circle(c, 26, cor.darkened(0.45))
				_texto(Vector2(c.x, c.y + 11), str(g.get("nome", "?")).substr(0, 1).to_upper(), 30, Color.WHITE, true, 4)
			var nome := str(g.get("nome", "?"))
			if nome.length() > 9:
				nome = nome.substr(0, 8) + "…"
			_texto(Vector2(c.x, c.y + 50), nome, 13, OURO if g.get("eu", false) else cor, true, 3)
		else:                                                    # vaga ainda vazia
			draw_arc(c, 28, 0, TAU, 32, Color(1, 1, 1, 0.22), 2.0, true)
			_texto(Vector2(c.x, c.y + 8), "?", 22, Color(1, 1, 1, 0.25), true, 0)

## COMO FUNCIONA: explica o campeonato em 4 passos.
func _painel_ajuda() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7))
	var j := Rect2(size.x / 2.0 - 430, size.y / 2.0 - 250, 860, 500)
	_caixa(j.grow(4), CONTORNO, 28)
	_caixa(j, Color("232a5e"), 26)
	_caixa(Rect2(j.position, Vector2(j.size.x, 70)), Color("3a2a0a"), 26)
	_texto(Vector2(j.get_center().x, j.position.y + 48), "COMO FUNCIONA O CAMPEONATO", 30, OURO, true, 5)
	var passos := [
		["16 jogadores", "8 do lado HEROES (nome laranja) e 8 do lado MONSTERS (nome verde)."],
		["Toda luta é Heroes × Monsters", "Quem vence avança na árvore. Quem perde está fora."],
		["Gente do mundo todo", "Com conta: sala de entrada de até 2 minutos, com chat. As vagas completam até fechar o tempo."],
		["A grande final", "O melhor Heroes contra o melhor Monsters. Quem vencer é o CAMPEÃO!"],
	]
	var y := j.position.y + 116
	for i in passos.size():
		var c := Vector2(j.position.x + 60, y)
		draw_circle(c, 24, CONTORNO)
		draw_circle(c, 21, Campeonato.COR_FASE[i])
		_texto(Vector2(c.x, c.y + 9), str(i + 1), 24, Color.WHITE, true, 4)
		_texto(Vector2(j.position.x + 100, y - 4), passos[i][0], 22, Color.WHITE, false, 4)
		_texto(Vector2(j.position.x + 100, y + 22), passos[i][1], 16, Color("c8cdf5"), false, 2)
		y += 84
	_texto(Vector2(j.get_center().x, j.end.y - 22), "Prêmio: moedas a cada fase vencida — e muito mais para o campeão.  (toque para fechar)", 14, Color(1, 1, 1, 0.6), true, 2)

# ---------------------------------------------------------------- ajudantes
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

static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

## Brasão (o mesmo do menu): escudo azul de Heroes ou caveira de olhos verdes de Monsters (caixa 40x40).
func _brasao(lado: String, c: Vector2, tam: float, a := 1.0) -> void:
	var k := tam / 40.0
	var o := c - Vector2(20, 20) * k
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	if lado == "monsters":
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

## Troféu dourado (escala 1 = ~70 px de altura).
func _trofeu(c: Vector2, k: float) -> void:
	var o := c
	var copo := PackedVector2Array()
	copo.append(o + Vector2(-34, -40) * k)
	copo.append(o + Vector2(34, -40) * k)
	for i in 11:
		var a := PI * i / 10.0
		copo.append(o + Vector2(cos(a) * 34, -10 + sin(a) * 30) * k)
	draw_colored_polygon(copo, OURO)
	copo.append(copo[0])
	draw_polyline(copo, CONTORNO, 3.0 * k, true)
	for s in [-1.0, 1.0]:                                      # alças
		draw_arc(o + Vector2(s * 36, -24) * k, 13 * k, -PI / 2 if s > 0 else PI / 2, PI / 2 if s > 0 else PI * 1.5, 10, OURO_ESCURO, 6 * k, true)
	draw_rect(Rect2(o + Vector2(-7, 20) * k, Vector2(14, 14) * k), Color("e0a52a"))
	var base := PackedVector2Array([o + Vector2(-26, 46) * k, o + Vector2(26, 46) * k, o + Vector2(20, 34) * k, o + Vector2(-20, 34) * k])
	draw_colored_polygon(base, Color("e0a52a"))
	base.append(base[0])
	draw_polyline(base, CONTORNO, 3.0 * k, true)
	draw_colored_polygon(PackedVector2Array([o + Vector2(-22, -34) * k, o + Vector2(-10, -34) * k, o + Vector2(-16, 8) * k]), Color(1, 1, 1, 0.3))
