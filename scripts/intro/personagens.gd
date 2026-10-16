extends Control
## PERSONAGENS (janela do menu): evoluir o nível da conta de cada personagem. IGUAL AO SITE (intro.js montarPersonagens):
## - abas Heroes / Monsters, suas moedas em cima
## - uma carta por personagem: ele parado se mexendo, nível n/15 (bolinhas; nos níveis 5, 10 e 15 são estrelas = habilidades, em breve),
##   "+x% vida e dano" e o botão Evoluir com o preço
## - quem cobra é o servidor: subir_nivel(p_personagem) do supabase/3_social.sql (preços em Progressao.PRECOS, iguais)
## Precisa estar com a conta (Google ou nome e senha). Convidado só vê.

const JANELA := Rect2(100, 40, 1080, 650)
const CARTA := Vector2(196, 232)
const ESPACO := Vector2(12, 14)
const POR_LINHA := 5
const TOPO_GRADE := 110.0
const LADOS := [["heroes", "Heroes"], ["monsters", "Monsters"]]
## Os mesmos do servidor (personagem_valido: 3_social.sql + 11_esqueleto_black.sql).
const IDS := {
	"heroes": ["elara", "nick", "arqueiro", "protetor", "mago", "magoFogo", "sentinela", "engenheiro"],
	"monsters": ["esqueletoBlack", "esqueleto", "esqueletoFogo", "esqueletoArqueiro", "esqueletoBombardeiro", "esqueletoProtetor", "esqueletoMago", "esqueletoTita"]}

var intro: Node
var lado := "heroes"
var nota := ""
var nota_cor := Color("dfe4ff")
var ocupado := ""                                   # id evoluindo agora (esperando o servidor)
var _ids: Array = []
var _abre := 0.0
var _troca := 0.0
var _relogio := 0.0
var _pulso := {}                                    # id -> 1..0 (brilho de quando sobe de nível)
var _apertado := ""                                 # botão apertado (afunda)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # (ocupa a tela toda: senão os toques não chegam)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func abrir() -> void:
	_quadro_abriu = Engine.get_process_frames()       # (o mesmo toque que abriu não pode fechar)
	lado = Perfil.lado if Perfil.lado in ["heroes", "monsters"] else "heroes"
	visible = true
	_abre = 0.0
	_tocou_aqui = false
	_montar()
	_nota_padrao()

func fechar() -> void:
	visible = false
	_apertado = ""

func _montar() -> void:
	_troca = 0.0
	_ids = []
	for p in Catalogo.do_lado(lado, false):              # TODOS do lado (os de liga aparecem com o selo da liga)
		_ids.append(p.id)
	for id in IDS[lado]:                                  # (algum que não veio do catálogo)
		if not _ids.has(id) and Catalogo.get_p(id) != null:
			_ids.append(id)

func _conta() -> Node:
	return get_node_or_null("/root/Conta")

func _logado() -> bool:
	var c := _conta()
	return c != null and c.online_pronto()

func _nota_padrao() -> void:
	nota_cor = Color("dfe4ff")
	if _logado():
		nota = "Cada nível dá +8% de vida e dano. Habilidades abrem nos níveis 5, 10 e 15 (em breve)."
	else:
		nota = "Entre com sua conta nas Opções para evoluir. Cada nível dá +8% de vida e dano."

static func _pct(nivel: int) -> int:
	return roundi((Progressao.multiplicador(nivel) - 1.0) * 100.0)

static func _milhar(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out

func _bloqueado(p: PersonagemDados) -> bool:
	return p != null and p.desbloqueio_trofeus > 0 and Perfil.trofeus < p.desbloqueio_trofeus

# =================================================================== EVOLUIR
func _evoluir(id: String) -> void:
	if ocupado != "":
		return
	var p: PersonagemDados = Catalogo.get_p(id)
	var nome: String = p.nome if p else id
	if _bloqueado(p):
		var lg := Perfil.liga_de(p.desbloqueio_trofeus)
		_avisar("%s libera na liga %s (%d troféus). Suba de liga para evoluir!" % [nome, lg.nome, p.desbloqueio_trofeus], false)
		return
	if not _logado():
		_avisar("Entre com sua conta nas Opções para evoluir os personagens.", false)
		return
	var n := Perfil.nivel_de(id)
	var custo := Progressao.custo_proximo(n)
	if custo < 0:
		_avisar("%s já está no nível máximo!" % nome, false)
		return
	if Perfil.moedas < custo:
		_avisar("Faltam %s moedas para evoluir %s." % [_milhar(custo - Perfil.moedas), nome], false)
		return
	intro._clique(true)
	ocupado = id
	var r: Dictionary = await _conta().chamar("subir_nivel", {"p_personagem": id})
	ocupado = ""
	if not is_inside_tree():
		return
	if r.ok and r.dados is Dictionary:
		var novo := int(r.dados.get("nivel", n + 1))
		Perfil.niveis[id] = novo
		if r.dados.get("perfil") is Dictionary:
			Perfil.de_servidor(r.dados.perfil)
		Perfil.salvar()
		_pulso[id] = 1.0
		intro._trovao()
		_avisar("%s subiu para o nível %d! Agora tem +%d%% de vida e dano." % [nome, novo, _pct(novo)], true)
		_conta().mudou.emit()
		return
	var msg := str(r.erro).to_lower()
	if "moedas" in msg:
		_avisar("Moedas insuficientes.", false)
		_conta().no_servidor("meu_perfil")              # acerta as moedas com o servidor
	elif "máximo" in msg or "maximo" in msg:
		_avisar("%s já está no nível máximo!" % nome, false)
	elif r.codigo == 0:
		_avisar("Sem internet. Confira a conexão e tente de novo.", false)
	elif "subir_nivel" in msg or "function" in msg:
		_avisar("Falta rodar o 3_social.sql no Supabase.", false)
	else:
		_avisar("Não deu para evoluir: " + str(r.erro).left(70), false)

func _avisar(txt: String, bom: bool) -> void:
	nota = txt
	nota_cor = Color("b6ff6a") if bom else Color("ffb0a0")

# =================================================================== QUADRO
func _process(dt: float) -> void:
	if not visible:
		return
	_relogio += dt
	_abre = move_toward(_abre, 1.0, dt * 4.0)
	_troca = move_toward(_troca, 1.0, dt * 2.5)
	for id in _pulso.keys():
		_pulso[id] = maxf(0.0, _pulso[id] - dt * 0.8)
	queue_redraw()

# =================================================================== TOQUES
func _ret_aba(i: int) -> Rect2:
	return Rect2(JANELA.position.x + 330 + i * 150, JANELA.position.y + 36, 142, 50)

func _ret_fechar() -> Rect2:
	return Rect2(JANELA.end.x - 92, JANELA.position.y + 30, 64, 60)

func _ret_carta(i: int) -> Rect2:
	var por_linha := POR_LINHA
	var linha := i / por_linha
	var na_linha := mini(por_linha, _ids.size() - linha * por_linha)
	var larg := na_linha * CARTA.x + (na_linha - 1) * ESPACO.x
	var x0 := JANELA.get_center().x - larg / 2.0
	return Rect2(x0 + (i % por_linha) * (CARTA.x + ESPACO.x), JANELA.position.y + TOPO_GRADE + linha * (CARTA.y + ESPACO.y), CARTA.x, CARTA.y)

func _ret_botao(i: int) -> Rect2:
	var r := _ret_carta(i)
	return Rect2(r.position.x + 14, r.end.y - 44, r.size.x - 28, 36)

var _tocou_aqui := false

var _quadro_abriu := -1

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and Engine.get_process_frames() == _quadro_abriu:
		accept_event()
		return
	if not (ev is InputEventMouseButton) or ev.button_index != MOUSE_BUTTON_LEFT:
		return
	var p: Vector2 = ev.position - intro.O
	if ev.pressed:
		_tocou_aqui = true
		_apertado = ""
		for i in _ids.size():
			if _ret_botao(i).grow(6).has_point(p):
				_apertado = _ids[i]
	else:
		_apertado = ""
		if _tocou_aqui:                                 # (o toque que abriu a janela não conta)
			_tocou_aqui = false
			_tocar(p)
	accept_event()

func _tocar(p: Vector2) -> void:
	if _ret_fechar().grow(6).has_point(p) or not JANELA.grow(10).has_point(p):
		intro._clique(false)
		fechar()
		return
	for i in LADOS.size():
		if _ret_aba(i).has_point(p) and lado != LADOS[i][0]:
			intro._clique(false)
			lado = LADOS[i][0]
			_montar()
			_nota_padrao()
			return
	for i in _ids.size():
		if _ret_botao(i).grow(6).has_point(p):
			_evoluir(_ids[i])
			return

# =================================================================== DESENHO
static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

static func _ease_back(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)

func _draw() -> void:
	intro._ci = self
	var O: Vector2 = intro.O
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.05, 0.62 * _abre))
	var k := 0.92 + 0.08 * _ease(_abre)
	var c := O + JANELA.get_center()
	draw_set_transform(c - JANELA.get_center() * k, 0.0, Vector2(k, k))
	_desenhar_janela()
	for i in _ids.size():
		_desenhar_carta(i)
	_desenhar_abas()
	intro._texto_cartoon(Vector2(JANELA.get_center().x, JANELA.end.y - 20), nota, 17, nota_cor, intro.f_texto, 1.3, true)
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
	intro._degrade(Rect2(j.position.x + 20, j.position.y + 6, j.size.x - 40, 70), Color(1, 1, 1, 0.08), Color(1, 1, 1, 0))
	intro._texto_cartoon(Vector2(j.position.x + 40, j.position.y + 78), "Personagens", 46, Color("ffd34d"), intro.f_titulo, 2.5, false)
	# moedas
	var txt := _milhar(Perfil.moedas)
	var lw: float = intro._larg(intro.f_titulo, txt, 26)
	var mr := Rect2(_ret_fechar().position.x - 30 - lw - 64, j.position.y + 40, lw + 64, 46)
	intro._caixa(mr, Color(0.05, 0.06, 0.15, 0.75), 23, 2, Color(1, 0.83, 0.3, 0.5))
	intro._moeda(Vector2(mr.position.x + 24, mr.get_center().y), 30)
	intro._texto_cartoon(Vector2(mr.position.x + 46, mr.position.y + 33), txt, 26, Color("fff6d0"), intro.f_titulo, 1.6, false)
	# fechar
	var f := _ret_fechar()
	intro._caixa(Rect2(f.position + Vector2(0, 5), f.size).grow(3), NAVY, 18)
	intro._caixa(f.grow(3), NAVY, 18)
	intro._botao_degrade(f, Color("7f95e6"), Color("4a5fae"), Color("2c3874"), 16)
	var fc := f.get_center()
	for s in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(fc - s * 11, fc + s * 11, intro.CONTORNO, 7.0, true)
		draw_line(fc - s * 11, fc + s * 11, Color.WHITE, 4.0, true)

func _desenhar_abas() -> void:
	var a := _ret_aba(0)
	var b := _ret_aba(LADOS.size() - 1)
	intro._caixa(Rect2(a.position - Vector2(8, 7), Vector2(b.end.x - a.position.x + 16, a.size.y + 14)), Color(0.05, 0.06, 0.14, 0.7), 22)
	for i in LADOS.size():
		var r := _ret_aba(i)
		var on: bool = lado == LADOS[i][0]
		if on:
			intro._caixa(Rect2(r.position + Vector2(0, 4), r.size).grow(2), Color("4a2a06"), 17)
			intro._caixa(r.grow(2), Color("4a2a06"), 17)
			if i == 0:
				intro._botao_degrade(r, Color("ffe98a"), Color("ffc43a"), Color("c97a0c"), 15)
			else:
				intro._botao_degrade(r, Color("d9ff9a"), Color("8be03c"), Color("3f8f1a"), 15)
		else:
			intro._caixa(Rect2(r.position + Vector2(0, 4), r.size), Color(0.03, 0.04, 0.1, 0.6), 15)
			intro._botao_degrade(r, Color("5d6fb8"), Color("3d4c8f"), Color("2a356b"), 15)
		intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 35), LADOS[i][1], 23, Color.WHITE, intro.f_titulo, 1.6, true)

func _desenhar_carta(i: int) -> void:
	var id: String = _ids[i]
	var p: PersonagemDados = Catalogo.get_p(id)
	if p == null:
		return
	var entra := _ease_back(clampf(_troca * 2.4 - i * 0.09, 0.0, 1.0))
	if entra <= 0.01:
		return
	var r0 := _ret_carta(i)
	var pul: float = _pulso.get(id, 0.0)
	var k := (0.6 + 0.4 * entra) * (1.0 + 0.06 * sin(pul * PI))
	var cc := r0.get_center()
	draw_set_transform_matrix(_trans_carta(cc, k))
	var r := r0
	var n := Perfil.nivel_de(id)
	var custo := Progressao.custo_proximo(n)
	var cor1: Color = p.cores[0] if p.cores.size() > 0 else Color("6f86d6")
	var cor2: Color = p.cores[1] if p.cores.size() > 1 else cor1.darkened(0.4)
	# brilho de quando evolui
	if pul > 0.0:
		intro._caixa(r.grow(12 * pul), Color(1, 0.85, 0.3, 0.45 * pul), 26)
	# carta
	intro._caixa(Rect2(r.position + Vector2(0, 6), r.size), Color(0, 0, 0, 0.35), 20)
	intro._caixa(r.grow(3), intro.CONTORNO, 22)
	intro._painel(r, Color("34418a"), Color("1b2350"), 20)
	# janela do personagem com a cor dele
	var jan := Rect2(r.position.x + 10, r.position.y + 10, r.size.x - 20, 112)
	intro._caixa(jan, cor2.darkened(0.35), 14)
	intro._degrade(Rect2(jan.position + Vector2(3, 3), Vector2(jan.size.x - 6, jan.size.y - 6)), cor1.darkened(0.05), cor2.darkened(0.25))
	intro._elipse_degrade(Vector2(jan.get_center().x, jan.end.y - 26), 90, 46, Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.0))
	_desenhar_boneco(p, i, r, k)                      # (deixa a transformação da carta de volta)
	intro._caixa(Rect2(jan.position.x, jan.end.y - 4, jan.size.x, 4), Color(0, 0, 0, 0.25), 2)
	# selo do nível
	var sc := Vector2(r.position.x + 28, r.position.y + 28)
	draw_circle(sc + Vector2(0, 3), 22, Color(0, 0, 0, 0.35))
	draw_circle(sc, 22, intro.CONTORNO)
	if n >= Progressao.NIVEL_MAX:
		intro._bola(sc, 19, Color("fff1a8"), Color("c9850f"))
	else:
		intro._bola(sc, 19, Color("b6ff6a"), Color("3f8f1a"))
	intro._texto_cartoon(Vector2(sc.x, sc.y + 9), str(n), 24, Color.WHITE, intro.f_titulo, 1.3, true)
	if _bloqueado(p):
		_selo_liga(p, r)
	# nome
	intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 146), p.nome_card(), 22 if p.nome_card().length() <= 11 else 18, Color.WHITE, intro.f_titulo, 1.6, true)
	# bolinhas do nível (estrelas nos níveis das habilidades)
	var mx := Progressao.NIVEL_MAX
	var passo := 11.8
	var x0 := r.get_center().x - (mx - 1) * passo / 2.0
	var y := r.position.y + 162.0
	for v in range(1, mx + 1):
		var pc := Vector2(x0 + (v - 1) * passo, y)
		var tem := v <= n
		if v in Progressao.HABILIDADES_NOS:
			_estrela(pc, 8.5, Color("ffd34d") if tem else Color(1, 1, 1, 0.18), tem)
		else:
			draw_circle(pc, 5.5, intro.CONTORNO)
			draw_circle(pc, 4.0, Color("8be03c") if tem else Color(1, 1, 1, 0.16))
	intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 184), "+%d%% vida e dano" % _pct(n), 15, Color("dfe4ff"), intro.f_texto, 1.1, true)
	# botão
	var b := _ret_botao(i)
	if _apertado == id:
		b.position.y += 3
	if _bloqueado(p):
		_botao_liga(p, b)
	elif custo < 0:
		intro._caixa(b.grow(2), intro.CONTORNO, 15)
		intro._botao_degrade(b, Color("fff3b0"), Color("f6c343"), Color("b8740f"), 13)
		intro._texto_cartoon(Vector2(b.get_center().x, b.position.y + 26), "Nível máximo", 19, Color.WHITE, intro.f_titulo, 1.4, true)
	else:
		var pode := _logado() and Perfil.moedas >= custo
		intro._caixa(Rect2(b.position + Vector2(0, 4), b.size).grow(2), intro.CONTORNO, 15)
		intro._caixa(b.grow(2), intro.CONTORNO, 15)
		if pode:
			intro._botao_degrade(b, Color("d9ff9a"), Color("8be03c"), Color("3f8f1a"), 13)
		else:
			intro._botao_degrade(b, Color("8a8fa8"), Color("626780"), Color("43475c"), 13)
		if ocupado == id:
			var c := b.get_center()
			draw_arc(c, 11, _relogio * 6.0, _relogio * 6.0 + 4.2, 20, Color.WHITE, 4, true)
		else:
			var t1 := "Evoluir"
			var t2 := _milhar(custo)
			var w1: float = intro._larg(intro.f_titulo, t1, 19)
			var w2: float = intro._larg(intro.f_titulo, t2, 19)
			var x := b.get_center().x - (w1 + 10 + 24 + w2) / 2.0
			var cor := Color.WHITE if pode else Color(1, 1, 1, 0.75)
			intro._texto_cartoon(Vector2(x, b.position.y + 26), t1, 19, cor, intro.f_titulo, 1.4, false)
			intro._moeda(Vector2(x + w1 + 10 + 10, b.get_center().y + 1), 20)
			intro._texto_cartoon(Vector2(x + w1 + 10 + 24, b.position.y + 26), t2, 19, cor, intro.f_titulo, 1.4, false)
	# "Nível n!" subindo
	if pul > 0.0:
		var a := clampf(pul * 1.6, 0.0, 1.0)
		intro._texto_cartoon(Vector2(r.get_center().x, r.position.y + 64 - (1.0 - pul) * 46.0), "Nível %d!" % n, 30, Color(1, 0.9, 0.4, a), intro.f_titulo, 2.0, true)
	draw_set_transform_matrix(_t_atual())

## Personagem que ainda é de LIGA: o boneco aparece normal (não escurece); o selo da liga fica no canto
## e o botão mostra a liga que libera (toque: avisa quantos troféus faltam).
func _botao_liga(p: PersonagemDados, b: Rect2) -> void:
	var lg := Perfil.liga_de(p.desbloqueio_trofeus)
	intro._caixa(Rect2(b.position + Vector2(0, 4), b.size).grow(2), intro.CONTORNO, 15)
	intro._caixa(b.grow(2), intro.CONTORNO, 15)
	var cor: Color = lg.cor
	intro._botao_degrade(b, cor.lightened(0.45), cor, cor.darkened(0.45), 13)
	var t1 := "Liga " + str(lg.nome)
	intro._texto_cartoon(Vector2(b.get_center().x + 10, b.position.y + 26), t1, 18, Color.WHITE, intro.f_titulo, 1.4, true)
	var tex: Texture2D = intro._textura(["liga/" + str(lg.img), "liga/" + str(lg.nome), "liga/" + str(lg.nome).to_lower()])
	var lc := Vector2(b.get_center().x - intro._larg(intro.f_titulo, t1, 18) / 2.0 - 8.0, b.get_center().y)
	if tex:
		var s := 30.0 / maxf(tex.get_width(), tex.get_height())
		var tam := Vector2(tex.get_width(), tex.get_height()) * s
		draw_texture_rect(tex, Rect2(lc - tam / 2.0, tam), false)

## Selo da liga no canto da carta (pulsando de leve).
func _selo_liga(p: PersonagemDados, r: Rect2) -> void:
	var lg := Perfil.liga_de(p.desbloqueio_trofeus)
	var tex: Texture2D = intro._textura(["liga/" + str(lg.img), "liga/" + str(lg.nome), "liga/" + str(lg.nome).to_lower()])
	var c := Vector2(r.end.x - 30, r.position.y + 32)
	var pul := 1.0 + 0.06 * sin(_relogio * 2.8)
	if tex:
		var s := 50.0 * pul / maxf(tex.get_width(), tex.get_height())
		var tam := Vector2(tex.get_width(), tex.get_height()) * s
		draw_texture_rect(tex, Rect2(c - tam / 2.0 + Vector2(0, 3), tam), false, Color(0, 0, 0, 0.4))
		draw_texture_rect(tex, Rect2(c - tam / 2.0, tam), false)
	else:
		draw_circle(c, 18, lg.cor)

# --- transformações (a janela inteira cresce ao abrir; cada carta tem a sua escala)
func _t_k() -> float:
	return 0.92 + 0.08 * _ease(_abre)

func _t_atual() -> Transform2D:
	var O: Vector2 = intro.O
	var k := _t_k()
	return Transform2D(0.0, Vector2(k, k), 0.0, O + JANELA.get_center() - JANELA.get_center() * k)

## Carta em escala kc em volta do centro cc (coordenadas do palco).
func _trans_carta(cc: Vector2, kc: float) -> Transform2D:
	return _t_atual() * Transform2D(0.0, Vector2(kc, kc), 0.0, cc - cc * kc)

func _estrela(c: Vector2, r: float, cor: Color, cheia: bool) -> void:
	var pts := PackedVector2Array()
	for j in 10:
		var a := -PI / 2.0 + j * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if j % 2 == 0 else r * 0.45))
	var borda := pts.duplicate()
	borda.append(pts[0])
	draw_colored_polygon(pts, cor)
	draw_polyline(borda, intro.CONTORNO if cheia else Color(0, 0, 0, 0.35), 2.0, true)

## O personagem parado (ou andando no lugar), em pé na janelinha da carta.
func _desenhar_boneco(p: PersonagemDados, i: int, r: Rect2, kc: float) -> void:
	var heroi := p.lado == "heroes"
	var nomes: Array = ["parado", "defender", "andar"] if p.id == "protetor" else ["parado", "andar", "atacar"]
	var a: AnimDados = null
	var qual := ""
	for nm in nomes:
		var x := p.anim(nm)
		if x and x.textura:
			a = x
			qual = nm
			break
	if a == null:
		return
	var q := int((_relogio + i * 0.37) * a.fps) % maxi(1, a.quadros)
	if qual == "defender" and p.extra.has("trechos") and (p.extra.trechos as Dictionary).has("parado"):
		var tr: Array = p.extra.trechos.parado
		if tr.size() == 2:
			var nq: int = int(tr[1]) - int(tr[0]) + 1
			q = int(tr[0]) - 1 + int((_relogio + i * 0.37) * a.fps) % nq
	# tamanho: a escala do jogo um pouco maior, sem passar da janelinha
	var alt := 100.0
	var e := minf(p.escala * a.escala * 1.15, alt / maxf(1.0, a.ay))
	e = minf(e, (r.size.x - 30.0) / maxf(1.0, a.cw * 0.75))
	var vira := 1.0 if heroi else (-1.0 if a.olha_direita else 1.0)
	var pe := Vector2(r.get_center().x, r.position.y + 114)
	var base := _trans_carta(r.get_center(), kc)
	# sombra
	draw_set_transform_matrix(base * Transform2D(0.0, Vector2(1, 0.25), 0.0, pe))
	draw_circle(Vector2.ZERO, 38.0, Color(0, 0, 0, 0.3))
	draw_set_transform_matrix(base * Transform2D(0.0, Vector2(e * vira, e), 0.0, pe))
	var m := 2.0
	draw_texture_rect_region(a.textura, Rect2(-a.ax + m, -a.ay + m, a.cw - 2 * m, a.ch - 2 * m), a.retangulo(q).grow(-m))
	draw_set_transform_matrix(base)
