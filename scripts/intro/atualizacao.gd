extends Control
## ATUALIZAÇÃO OBRIGATÓRIA PELA PLAY STORE (plugin Android "AtualizarPlay" = Google Play In-App Updates).
## Tem versão nova na loja? Então a pessoa SÓ ENTRA NO MENU DEPOIS DE ATUALIZAR — todo mundo sempre na mesma versão
## (PvP online, série, campeonato e painel ao vivo dependem disso).
##  1. Já na tela de carregamento pergunta à Play Store (no máximo 6 s; sem internet / fora da loja = segue normal).
##  2. Tela cheia: versão atual → versão nova, as novidades (Supabase, 23_versao.sql) e "ATUALIZAR AGORA".
##  3. Baixa com a barra verde: MB baixados, quanto falta, velocidade e tempo restante.
##  4. Terminou: instala e o jogo reinicia sozinho. Cancelou na tela do Google: volta para o botão.
## No PC (sem o plugin) não faz nada. Para VER a tela no PC: variável HVM_TESTE_ATUALIZACAO=1 (simula a Play Store).

const CFG := "user://atualizacao.cfg"
const VERDE := [Color("d9ff9a"), Color("8be03c"), Color("3f8f1a")]
const ESPERA_MAX := 6.0                              ## segundos esperando a Play Store responder

static var ja_verificou := false                    # (uma vez por abertura do jogo)
static var liberado := false                        # já sabe que não tem atualização (pode entrar)

var intro: Node
var plugin: Object = null
## "" (nada) / perguntando / tela (esperando o toque) / imediata (tela do Google aberta) / baixando / instalando
var fase := ""
var codigo_novo := 0
var codigo_atual := 0
var nome_versao := ""
var novidades := ""
var flex_ok := true
var imediata_ok := true
var _abre := 0.0
var _relogio := 0.0
var _t := 0.0
var _botoes: Array = []
var _apertado := -1
var _quadro_abriu := -1
var _tocou_aqui := false
var _servidor_ok := false
# download
var _baixado := 0.0
var _total := 0.0
var _vel := 0.0                                     # bytes por segundo (média suave)
var _amostra := [0.0, 0.0]                          # [tempo, bytes] da última medida
var _inst_t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	if Engine.has_singleton("AtualizarPlay"):
		plugin = Engine.get_singleton("AtualizarPlay")
	elif OS.get_environment("HVM_TESTE_ATUALIZACAO") == "1":
		plugin = PlayFalsa.new()                     # (PC: simula a loja para ver a tela)

## Chamado logo que o jogo abre (tela de carregamento). Pergunta à Play Store e ao Supabase.
func verificar() -> void:
	if plugin == null or ja_verificou:
		liberado = liberado or plugin == null
		return
	ja_verificou = true
	fase = "perguntando"
	_t = 0.0
	codigo_atual = int(plugin.codigo_versao())
	plugin.verificar()
	var r: Dictionary = await Conta.chamar("app_versao")
	if r.ok and r.dados is Dictionary:
		_servidor_ok = true
		nome_versao = str(r.dados.get("versao_nome", "")) if r.dados.get("versao_nome") != null else ""
		novidades = str(r.dados.get("novidades", "")) if r.dados.get("novidades") != null else ""

## O carregamento espera esta resposta antes de deixar ir para o menu.
func segurando() -> bool:
	return plugin != null and not liberado

func bloqueando() -> bool:
	return visible and fase in ["tela", "imediata", "baixando", "instalando"]

func _liberar() -> void:
	fase = ""
	liberado = true
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(dt: float) -> void:
	_relogio += dt
	if plugin == null:
		return
	match fase:
		"perguntando":
			_t += dt
			var e := str(plugin.estado())
			if e.begins_with("disponivel:"):
				var p := e.split(":")
				codigo_novo = int(p[1]) if p.size() > 1 else 0
				flex_ok = p.size() > 3 and p[3] == "1"
				imediata_ok = p.size() > 4 and p[4] == "1"
				if _t < 1.5 and not _servidor_ok:
					return                              # espera um pouquinho as novidades do servidor
				_abrir()
			elif e == "em_andamento":                   # a atualização estava no meio: continua de onde parou
				_abrir()
				_atualizar()
			elif e == "sem" or e.begins_with("erro:") or _t > ESPERA_MAX:
				if str(plugin.progresso()) == "baixado":
					_abrir()
					_instalar()
				else:
					_liberar()                          # sem versão nova (ou sem resposta): pode jogar
		"baixando", "imediata":
			var pr := str(plugin.progresso())
			if pr.begins_with("baixando:"):
				fase = "baixando"
				var q := pr.split(":")
				_baixado = float(q[1]) if q.size() > 1 else 0.0
				_total = float(q[2]) if q.size() > 2 else 0.0
				var agora := _relogio
				if agora - float(_amostra[0]) >= 0.5:
					var v := (_baixado - float(_amostra[1])) / maxf(agora - float(_amostra[0]), 0.01)
					_vel = v if _vel <= 0.0 else lerpf(_vel, v, 0.35)
					_amostra = [agora, _baixado]
			elif pr == "baixado":
				_instalar()
			elif pr == "cancelado" or pr.begins_with("falhou"):
				fase = "tela"                           # cancelou / deu erro: volta para o botão
				_baixado = 0.0
		"instalando":
			_inst_t += dt
			if _inst_t > 1.4 and _inst_t - dt <= 1.4:
				plugin.concluir()                       # instala e o jogo reinicia sozinho
	var mostra := fase in ["tela", "imediata", "baixando", "instalando"]
	if visible != mostra:
		visible = mostra
	mouse_filter = Control.MOUSE_FILTER_STOP if mostra else Control.MOUSE_FILTER_IGNORE
	if visible:
		_abre = move_toward(_abre, 1.0, dt * 3.0)
		queue_redraw()

func _abrir() -> void:
	fase = "tela"
	visible = true
	_abre = 0.0
	_quadro_abriu = Engine.get_process_frames()
	_tocou_aqui = false
	Conta.registrar("tela", {"nome": "Atualização obrigatória"})

# =================================================================== AÇÕES
func _atualizar() -> void:
	intro._clique(true)
	_baixado = 0.0
	_total = 0.0
	_vel = 0.0
	_amostra = [_relogio, 0.0]
	if flex_ok:
		fase = "baixando"
		plugin.atualizar(false)                         # baixa com a NOSSA barra (o Google só pede a confirmação)
	else:
		fase = "imediata"
		plugin.atualizar(true)                          # só tem a tela cheia do Google
	Conta.registrar("tela", {"nome": "Atualizar (aceitou)"})

func _instalar() -> void:
	if fase == "instalando":
		return
	fase = "instalando"
	_inst_t = 0.0
	_baixado = maxf(_baixado, _total)
	intro._trovao()

# =================================================================== TOQUES
func _gui_input(ev: InputEvent) -> void:
	accept_event()
	if ev is InputEventMouseButton and ev.pressed and Engine.get_process_frames() == _quadro_abriu:
		return
	if not (ev is InputEventMouseButton) or ev.button_index != MOUSE_BUTTON_LEFT:
		return
	var p: Vector2 = ev.position - intro.O
	if ev.pressed:
		_tocou_aqui = true
		_apertado = -1
		for i in _botoes.size():
			if _botoes[i].r.has_point(p):
				_apertado = i
	else:
		_apertado = -1
		if _tocou_aqui:
			_tocou_aqui = false
			for b in _botoes:
				if b.r.has_point(p):
					b.f.call()
					break

## (compatibilidade: a faixa antiga do rodapé não existe mais)
func tocar_faixa(_p: Vector2) -> bool:
	return false

# =================================================================== DESENHO
static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

static func _mb(b: float) -> String:
	var mb := b / 1048576.0
	return ("%.1f MB" % mb).replace(".", ",") if mb < 100.0 else "%d MB" % roundi(mb)

func _botao(r: Rect2, txt: String, f: Callable, tam := 30) -> void:
	var i := _botoes.size()
	var pul := 1.0 + 0.03 * sin(_relogio * 4.0)
	var rr := Rect2(r.get_center() - r.size * pul / 2.0, r.size * pul)
	var afunda := 4.0 if _apertado == i else 0.0
	for k in 3:
		intro._caixa(rr.grow(8 + k * 7), Color(0.55, 1.0, 0.35, 0.10 - k * 0.03), 30 + k * 6)
	intro._caixa(Rect2(rr.position + Vector2(0, 7), rr.size).grow(3), intro.CONTORNO, 22)
	rr.position.y += afunda
	intro._caixa(rr.grow(3), intro.CONTORNO, 22)
	intro._botao_degrade(rr, VERDE[0], VERDE[1], VERDE[2], 20)
	intro._caixa(Rect2(rr.position + Vector2(14, 6), Vector2(rr.size.x - 28, rr.size.y * 0.3)), Color(1, 1, 1, 0.25), 12)
	intro._texto_cartoon(Vector2(rr.get_center().x, rr.position.y + rr.size.y * 0.5 + tam * 0.36), txt, tam, Color.WHITE, intro.f_titulo, 1.8, true)
	_botoes.append({"r": r, "f": f})

func _draw() -> void:
	_botoes.clear()
	intro._ci = self
	var O: Vector2 = intro.O
	var W: float = intro.W
	var H: float = intro.H
	var a := _ease(_abre)
	# ---------- fundo: a arte do jogo escurecida + vinheta (cobre a tela toda: o menu não aparece)
	draw_rect(Rect2(Vector2.ZERO, size), Color("070912"))
	var tex: Texture2D = intro._textura(intro.FUNDOS.carga)
	if tex:
		var k := maxf(size.x / tex.get_width(), size.y / tex.get_height()) * (1.04 + 0.02 * sin(_relogio * 0.3))
		var ts := Vector2(tex.get_width(), tex.get_height()) * k
		draw_texture_rect(tex, Rect2((size - ts) / 2.0, ts), false, Color(0.42, 0.42, 0.5, a))
	var forte := Color(0.01, 0.01, 0.04, 0.85)
	var nada := Color(0.01, 0.01, 0.04, 0.0)
	var L := size.y * 0.42
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, L), Vector2(0, L)]), PackedColorArray([forte, forte, nada, nada]))
	draw_polygon(PackedVector2Array([Vector2(0, size.y), Vector2(size.x, size.y), Vector2(size.x, size.y - L), Vector2(0, size.y - L)]), PackedColorArray([forte, forte, nada, nada]))
	# brasas subindo
	for s in 40:
		var fa := fmod(_relogio * 0.06 + s * 0.025, 1.0)
		var px := fmod(s * 173.3, maxf(size.x, 1.0)) + sin(_relogio + s) * 14.0
		draw_circle(Vector2(px, size.y + 10.0 - fa * (size.y + 30.0)), 2.0 * (1.0 - fa) + 0.6, Color(0.6, 1.0, 0.4, 0.5 * (1.0 - fa) * a))
	draw_set_transform(O + Vector2(0, (1.0 - a) * 30.0))
	# ---------- título do jogo
	intro._texto_cartoon(Vector2(W / 2.0 - 112, 70), "Heroes", 46, Color("ffb347"), intro.f_titulo, 2.6, true)
	intro._texto_cartoon(Vector2(W / 2.0, 70), "vs", 26, Color.WHITE, intro.f_titulo, 1.6, true)
	intro._texto_cartoon(Vector2(W / 2.0 + 132, 70), "Monsters", 46, Color("8be03c"), intro.f_titulo, 2.6, true)
	# ---------- painel
	var j := Rect2(W / 2.0 - 380, 104, 760, 560)
	intro._caixa(Rect2(j.position + Vector2(0, 14), j.size).grow(10), Color(0, 0, 0, 0.5), 40)
	intro._caixa(j.grow(10), Color("163a10"), 38)
	intro._caixa(j.grow(7), Color("5cc22a"), 36)
	intro._caixa(j.grow(3), intro.NAVY, 32)
	intro._painel(j, Color("2c3d7e"), Color("141b40"), 30)
	# ícone (seta de download)
	var c := Vector2(j.get_center().x, j.position.y + 74)
	var pul := 0.5 + 0.5 * sin(_relogio * 3.0)
	for i in 3:
		draw_circle(c, 46 + i * 8 + pul * 4, Color(0.55, 1.0, 0.35, 0.12 - i * 0.035))
	draw_circle(c, 44, intro.CONTORNO)
	intro._bola(c, 41, Color("b6ff6a"), Color("2f9d16"))
	if fase == "instalando":
		draw_arc(c, 22, _relogio * 6.0, _relogio * 6.0 + 4.4, 24, Color.WHITE, 6.0, true)
	else:
		var dy := sin(_relogio * 4.0) * 3.0 if fase != "baixando" else fmod(_relogio * 30.0, 14.0) - 7.0
		draw_rect(Rect2(c.x - 6, c.y - 24 + dy, 12, 24), Color.WHITE)
		draw_colored_polygon(PackedVector2Array([Vector2(c.x - 19, c.y + dy), Vector2(c.x + 19, c.y + dy), Vector2(c.x, c.y + 20 + dy)]), Color.WHITE)
		draw_rect(Rect2(c.x - 21, c.y + 24, 42, 6), Color.WHITE)
	# título e versão
	var tit := "Instalando a versão nova" if fase == "instalando" else ("Baixando a versão nova" if fase == "baixando" else "Nova versão disponível!")
	intro._texto_cartoon(Vector2(j.get_center().x, j.position.y + 162), tit, 40, Color("ffd34d"), intro.f_titulo, 2.4, true)
	intro._texto_cartoon(Vector2(j.get_center().x, j.position.y + 194), "Atualize para continuar jogando com todo mundo", 18, Color("cfd6ff"), intro.f_texto, 1.1, true)
	_chips_versao(Vector2(j.get_center().x, j.position.y + 232))
	# novidades
	var caixa := Rect2(j.position.x + 46, j.position.y + 266, j.size.x - 92, 150)
	intro._caixa(caixa, Color(0.03, 0.05, 0.14, 0.6), 18, 1, Color(1, 1, 1, 0.08))
	intro._texto_cartoon(Vector2(caixa.position.x + 20, caixa.position.y + 30), "O que tem de novo", 19, Color("b6ff6a"), intro.f_titulo, 1.2, false)
	var linhas := novidades.split("\n", false) if novidades != "" else PackedStringArray(["Personagens, efeitos e correções novas.", "Melhorias para o jogo ficar ainda melhor."])
	var y := caixa.position.y + 60
	for i in mini(linhas.size(), 4):
		var ln := linhas[i].strip_edges().trim_prefix("-").trim_prefix("•").strip_edges()
		intro._caixa(Rect2(caixa.position.x + 22, y - 10, 9, 9), Color("ffd34d"), 5)
		draw_string(intro.f_texto, Vector2(caixa.position.x + 42, y), ln, HORIZONTAL_ALIGNMENT_LEFT, caixa.size.x - 60, 17, Color("eef0ff"))
		y += 23
	# parte de baixo: botão ou barra
	var base := Rect2(j.position.x + 60, j.end.y - 126, j.size.x - 120, 96)
	match fase:
		"tela":
			_botao(Rect2(base.get_center().x - 200, base.position.y + 6, 400, 74), "ATUALIZAR AGORA", _atualizar, 32)
		"imediata":
			_girando(Vector2(base.get_center().x - 160, base.position.y + 40))
			intro._texto_cartoon(Vector2(base.get_center().x + 14, base.position.y + 34), "Continue na tela da Google Play", 22, Color.WHITE, intro.f_titulo, 1.4, true)
			intro._texto_cartoon(Vector2(base.get_center().x + 14, base.position.y + 62), "O jogo abre sozinho quando terminar", 16, Color("cfd6ff"), intro.f_texto, 1.0, true)
		"baixando", "instalando":
			_barra(base)
	# rodapé de confiança
	intro._texto_cartoon(Vector2(W / 2.0, j.end.y + 40), "Seu progresso, moedas e personagens continuam salvos.", 16, Color(1, 1, 1, 0.7), intro.f_texto, 1.0, true)
	draw_set_transform(Vector2.ZERO)

## "Versão 1.2  →  Versão 1.3  NOVA"
func _chips_versao(c: Vector2) -> void:
	var atual := "Versão " + str(Conta.VERSAO_JOGO)
	var nova := "Versão " + (nome_versao if nome_versao != "" else (str(codigo_novo) if codigo_novo > 0 else "nova"))
	var f: Font = intro.f_titulo
	var w1 := f.get_string_size(atual, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 30
	var w2 := f.get_string_size(nova, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 30
	var total := w1 + 54 + w2
	var r1 := Rect2(c.x - total / 2.0, c.y - 16, w1, 32)
	var r2 := Rect2(r1.end.x + 54, c.y - 16, w2, 32)
	intro._caixa(r1, Color(1, 1, 1, 0.08), 16, 2, Color(1, 1, 1, 0.18))
	intro._texto_cartoon(Vector2(r1.get_center().x, r1.position.y + 23), atual, 18, Color("aab4e0"), f, 1.0, true)
	var ax := r1.end.x + 27 + sin(_relogio * 4.0) * 3.0
	draw_colored_polygon(PackedVector2Array([Vector2(ax - 12, c.y - 6), Vector2(ax + 2, c.y - 6), Vector2(ax + 2, c.y - 12), Vector2(ax + 14, c.y), Vector2(ax + 2, c.y + 12), Vector2(ax + 2, c.y + 6), Vector2(ax - 12, c.y + 6)]), Color("ffd34d"))
	intro._caixa(r2.grow(2), intro.CONTORNO, 18)
	intro._botao_degrade(r2, VERDE[0], VERDE[1], VERDE[2], 16)
	intro._texto_cartoon(Vector2(r2.get_center().x, r2.position.y + 23), nova, 18, Color.WHITE, f, 1.3, true)
	var tag := Rect2(r2.end.x - 20, r2.position.y - 14, 50, 20)
	intro._caixa(tag.grow(2), intro.CONTORNO, 10)
	intro._caixa(tag, Color("e8402e"), 9)
	intro._texto_cartoon(Vector2(tag.get_center().x, tag.position.y + 15), "NOVA", 12, Color.WHITE, f, 0.8, true)

## Barra verde do download: % grande, MB baixados de MB total, quanto falta, velocidade e tempo.
func _barra(r: Rect2) -> void:
	var inst := fase == "instalando"
	var k := 1.0 if inst else (clampf(_baixado / _total, 0.0, 1.0) if _total > 0.0 else 0.0)
	var b := Rect2(r.position.x, r.position.y + 38, r.size.x, 30)
	intro._caixa(b.grow(4), intro.CONTORNO, 18)
	intro._caixa(b, Color(0.02, 0.04, 0.1, 0.9), 15)
	if k > 0.0:
		var cheio := Rect2(b.position, Vector2(maxf(30.0, b.size.x * k), b.size.y))
		intro._botao_degrade(cheio, VERDE[0], VERDE[1], VERDE[2], 15)
		# listras andando (dá a sensação de movimento)
		var desl := fmod(_relogio * 40.0, 28.0)
		var x := cheio.position.x - 28.0 + desl
		while x < cheio.end.x:
			var x0 := maxf(x, cheio.position.x + 4)
			var x1 := minf(x + 12, cheio.end.x - 4)
			if x1 - x0 > 2:
				draw_colored_polygon(PackedVector2Array([Vector2(x0, cheio.end.y - 4), Vector2(x1, cheio.end.y - 4), Vector2(x1 + 8, cheio.position.y + 4), Vector2(x0 + 8, cheio.position.y + 4)]), Color(1, 1, 1, 0.13))
			x += 28
		intro._caixa(Rect2(cheio.position + Vector2(8, 4), Vector2(maxf(0.0, cheio.size.x - 16), 7)), Color(1, 1, 1, 0.3), 4)
		# brilho na ponta
		draw_circle(Vector2(cheio.end.x - 6, cheio.get_center().y), 10.0 + 3.0 * sin(_relogio * 8.0), Color(0.8, 1.0, 0.6, 0.35))
	# textos
	var pct := "%d%%" % roundi(k * 100.0)
	intro._texto_cartoon(Vector2(r.position.x, r.position.y + 28), "Instalando... o jogo vai reiniciar sozinho" if inst else pct, 28 if not inst else 20, Color("b6ff6a"), intro.f_titulo, 1.6, false)
	if not inst and _total > 0.0:
		var txt := "%s de %s" % [_mb(_baixado), _mb(_total)]
		intro._texto_cartoon(Vector2(r.end.x - intro._larg(intro.f_titulo, txt, 20), r.position.y + 28), txt, 20, Color.WHITE, intro.f_titulo, 1.3, false)
		var falta := maxf(0.0, _total - _baixado)
		var extra := "Faltam %s" % _mb(falta)
		if _vel > 1024.0:
			var seg := ceili(falta / _vel)
			extra += "  ·  %s/s  ·  %s" % [_mb(_vel), ("~%d s" % seg) if seg < 60 else ("~%d min" % ceili(seg / 60.0))]
		intro._texto_cartoon(Vector2(b.get_center().x, b.end.y + 26), extra, 17, Color("cfd6ff"), intro.f_texto, 1.0, true)
	elif not inst:
		intro._texto_cartoon(Vector2(b.get_center().x, b.end.y + 26), "Confirme na janela da Google Play para começar", 17, Color("cfd6ff"), intro.f_texto, 1.0, true)

func _girando(c: Vector2) -> void:
	draw_arc(c, 16, _relogio * 6.0, _relogio * 6.0 + 4.4, 24, Color("8be03c"), 5.0, true)

# =================================================================== PC: Play Store de mentira (só para ver a tela)
class PlayFalsa:
	var _t0 := 0
	var _baixando := false
	var _ini := 0
	func codigo_versao() -> int: return 12
	func verificar() -> void: _t0 = Time.get_ticks_msec()
	func estado() -> String:
		return "disponivel:13:0:1:1" if Time.get_ticks_msec() - _t0 > 900 else "perguntando"
	func atualizar(_imediata: bool) -> void:
		_baixando = true
		_ini = Time.get_ticks_msec()
	func progresso() -> String:
		if not _baixando:
			return ""
		var total := 87.4 * 1048576.0
		var s := (Time.get_ticks_msec() - _ini) / 1000.0
		if s < 1.2:
			return ""                                   # (a pessoa confirmando na janela do Google)
		var b := minf(total, (s - 1.2) * 6.3 * 1048576.0 * (0.85 + 0.15 * sin(s * 2.0)))
		return "baixado" if b >= total else "baixando:%d:%d" % [int(b), int(total)]
	func concluir() -> void:
		print("(simulação) instalar e reiniciar")
