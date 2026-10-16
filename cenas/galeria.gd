extends Node2D
## GALERIA: mostra as 14 fichas animadas, para conferir se os números estão certos.
## - Clique num personagem para trocar a animação (parado, andar, atacar, morrer...).
## - Botões - e + mudam o nível da conta e mostram vida/dano naquele nível.


class Celula:
	var p: PersonagemDados
	var s: Sprite2D
	var info: Label
	var nomes: Array[String] = []
	var atual := 0
	var t := 0.0

var celulas: Array[Celula] = []
var nivel := 1
var topo: Label

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("2f5a2a"))
	_interface()
	_montar()

func _interface() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	topo = _label(Vector2(16, 8), 17)
	ui.add_child(topo)
	var x := 16.0
	for b in [["−", -1], ["+", 1], ["Nível 1", -99], ["Nível 30", 99]]:
		var bt := Button.new()
		bt.text = b[0]
		bt.position = Vector2(x, 38)
		bt.custom_minimum_size = Vector2(54 if b[0].length() <= 1 else 120, 44)
		bt.add_theme_font_size_override("font_size", 22)
		var d: int = b[1]
		bt.pressed.connect(func(): _mudar_nivel(d))
		ui.add_child(bt)
		x += bt.custom_minimum_size.x + 10

func _label(pos: Vector2, tam: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	return l

func _montar() -> void:
	if Catalogo.todos.is_empty():
		var aviso := _label(Vector2(40, 200), 26)
		aviso.text = "Nenhuma ficha encontrada.\nAbra ferramentas/gerar_fichas.gd e aperte Ctrl+Shift+X."
		add_child(aviso)
		return
	# ajusta ao tamanho da janela: 7 colunas, heróis em cima e monstros embaixo
	var tela := get_viewport_rect().size
	var heroes := Catalogo.do_lado("heroes")
	var monsters := Catalogo.do_lado("monsters")
	var col := tela.x / maxi(maxi(heroes.size(), monsters.size()), 1)
	var i := 0
	for p in heroes:
		_celula(p, Vector2(col * (i + 0.5), tela.y * 0.47), col); i += 1
	i = 0
	for p in monsters:
		_celula(p, Vector2(col * (i + 0.5), tela.y * 0.82), col); i += 1
	_atualizar_textos()

func _celula(p: PersonagemDados, pos: Vector2, largura: float) -> void:
	var c := Celula.new()
	c.p = p
	for k in ["parado", "defender", "andar", "atacar", "preparar", "especial", "morrer"]:
		if p.anims.has(k) and p.anims[k].textura:
			c.nomes.append(k)
	c.s = Sprite2D.new()
	c.s.position = pos
	c.s.region_enabled = true
	add_child(c.s)
	c.info = _label(pos + Vector2(-largura / 2 + 4, 8), 13)
	c.info.custom_minimum_size = Vector2(largura - 8, 0)
	c.info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(c.info)
	celulas.append(c)
	_aplicar_anim(c)

func _anim_de(c: Celula) -> AnimDados:
	return c.p.anims[c.nomes[c.atual]] if not c.nomes.is_empty() else null

func _aplicar_anim(c: Celula) -> void:
	var a := _anim_de(c)
	if a == null:
		return
	c.t = 0.0
	c.s.texture = a.textura
	c.s.scale = Vector2.ONE * c.p.escala * a.escala
	# as folhas de monstro olham para a direita: vira para eles ficarem de frente para os heróis
	c.s.flip_h = a.olha_direita
	var ox := a.cw / 2.0 - a.ax                                    # os pés ficam no ponto do personagem
	c.s.offset = Vector2(-ox if c.s.flip_h else ox, a.ch / 2.0 - a.ay)
	c.s.region_rect = a.retangulo(0)

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		for c in celulas:
			if c.nomes.size() > 1 and ev.position.distance_to(c.s.position + Vector2(0, -50)) < 60:
				c.atual = (c.atual + 1) % c.nomes.size()
				_aplicar_anim(c)
				_atualizar_textos()

func _mudar_nivel(d: int) -> void:
	nivel = clampi(nivel + d, 1, Progressao.NIVEL_MAX)
	_atualizar_textos()

func _atualizar_textos() -> void:
	var prox := Progressao.custo_proximo(nivel)
	topo.text = "Nível %d (×%.3f vida e dano) · próximo: %s · total até aqui: %s moedas · habilidades: %d/%d" % [
		nivel, Progressao.multiplicador(nivel),
		"máximo" if prox < 0 else "%d moedas" % prox,
		_milhar(Progressao.custo_total_ate(nivel)),
		Progressao.habilidades_abertas(nivel), Progressao.HABILIDADES_NOS.size()]
	for c in celulas:
		var nome_anim := c.nomes[c.atual] if not c.nomes.is_empty() else "sem imagem"
		var linha_dano := "  ⚔%d" % c.p.dano_no_nivel(nivel) if c.p.dano > 0 else ""
		c.info.text = "%s\n⚡%d  ❤%d%s\n[%s]" % [c.p.nome_card(), c.p.custo, c.p.vida_no_nivel(nivel), linha_dano, nome_anim]

func _milhar(n: int) -> String:
	var s := str(n)
	var r := ""
	while s.length() > 3:
		r = "." + s.right(3) + r
		s = s.left(s.length() - 3)
	return s + r

func _process(delta: float) -> void:
	for c in celulas:
		var a := _anim_de(c)
		if a == null:
			continue
		c.t += delta
		var q := a.quadro_em(c.t)
		if not a.repetir and q >= a.quadros - 1 and c.t > a.duracao() + maxf(a.caido, 0.6):
			c.t = 0.0                    # animações de uma vez só: repete depois de uma pausa, para dar para ver
			q = 0
		c.s.region_rect = a.retangulo(q)
