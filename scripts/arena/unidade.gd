class_name Unidade
extends Sprite2D
## UM PERSONAGEM NA ARENA (herói ou monstro).
## A lógica roda em passos fixos de 1/60 s (arena chama passo()). O "cérebro" depende de p.comportamento.
## Leve: um Sprite2D só, sem nós filhos; a barra de vida é desenhada por outra camada.

var arena: Node                           # a Arena (para procurar alvos, ferir, disparar...)
var p: PersonagemDados
var lado := "heroes"
var linha := 0
var col := -1                             # casa (heróis); -1 nos monstros
## CAMPANHA: quem NÃO defende a grade é atacante (entra pelas ondas e marcha até o castelo).
## Quem defende fica firme na casa. No PvP todo mundo é atacante (cada lado tem o seu castelo).
var atacante := false
var nivel := 1
var vida_max := 1
var vida := 1.0
var vida_bonus_ativa := false         # Nick: +30% de vida enquanto houver esqueleto inimigo
var dano := 0
var chefe := false
var vel_mult := 1.0                       # (campanha) modificador "Pressa" do nível: anda mais rápido

var estado := ""
var anim: AnimDados
var t := 0.0                              # tempo dentro da animação atual
var ultimo_q := -1                        # último quadro mostrado (para disparar eventos sem pular nenhum)
var cd := 0.0                             # espera até poder atacar de novo
var cd_especial := 0.0                    # espera do poder especial (terra, ossos)
var repouso := 0.0                        # (esqueleto) espreguiçada no repouso depois de abater alguém
var tiros := 0                            # (necro) magias lançadas
var invocador: Unidade = null             # (esqueleto invocado) quem o chamou
var morto := false                        # já começou a morrer (não é mais alvo)
var livre := false                        # já pode ser tirado da arena
var ocupa_casa := true                    # (heróis) a casa só fica livre quando ele bate no chão
var dor := 0.0                            # tempo do brilho vermelho de "levou golpe"
var mostra_barra := 0.0                   # tempo que a barra de vida fica visível
var defendendo := false                   # escudo erguido (reduz o dano)
var trecho := ""                          # (protetor) parado / levantar / segurar / abaixar
var _prof := 0.0                          # deslocamento de profundidade já aplicado (y-sort da camada)
var _fade := 0.0                          # (morte sem folha) segundos que falta para sumir de vez
const FADE_MORTE := 0.45                  # quanto tempo some, quando a ficha não tem animação de morte

# ---- PvP (duas arenas, ver scripts/pvp/arena_pvp.gd) ----
var pvp := false                          # está numa batalha PvP
var anda := false                         # (herói no PvP) sai andando até o castelo inimigo
var vel_andar := 0.0
var para := 45.0                          # para a esta distância do inimigo para lutar
var pausa_parar := 0.35                   # respira um pouco entre parar e atacar
var pausa := 0.0
var fixo := false                         # PREPARO: fica parado até o "LUTEM!"
var guarda := false                       # MODO CERCO: defensor fica firme no lugar (não anda), guardando o castelo
var _escala_base := Vector2.ONE
var _fase_resp := 0.0
var no_cerco := false                     # parou no 2º quadrado antes do castelo inimigo
var atravessou := false                   # já passou pelo portal
var fenda_aberta := false                 # (PvP) o portal da ponta já abriu para ele
var x_saida := 0.0                        # (PvP) onde saiu do portal na outra arena
var t_saida := 0.0                        # (PvP) segundos desde que saiu do portal (termina de aparecer mesmo parada)

# ---- COMANDOS DO JOGADOR (menu do personagem: scripts/arena/menu_unidade.gd) ----
var uid := 0                              ## número da tropa na partida (o PvP online manda o comando por ele)
var ordem := ""                           ## "" normal / "parar" / "andar" / "voltar"
var virado := false                       ## andando de costas para o inimigo (voltando): a folha vira
var pressa := 0.0                         ## PODER AZUL: 0..1 — cada toque acelera os ataques (some devagar)
var _pressa_t := 99.0                     ## segundos desde o último toque no azul
var forcar2 := false                      ## PODER VERMELHO pedido: solta o poder 2 no próximo passo
var alvo_x := INF                         ## (campanha) casa para onde está andando
var _ordem_t := 0.0                       ## (campanha) espera para tentar a próxima casa
var _brilho2 := 0.0                       ## brilho vermelho de quando solta o poder 2
## SOBRECARGA DE ENERGIA (poder vermelho da Elara e do Esqueleto Black, pago com moedas): solta na hora uma
## rajada de energia e, por SOBRECARGA_DUR segundos, gera o DOBRO de energia duas vezes mais rápido.
const SOBRECARGA_DUR := 12.0
const SOBRECARGA_RAJADA := 3              ## orbes soltos na hora (cada um vale 2x a energia do ciclo)
var sobrecarga := 0.0
var _poder_desenhado := false
## PODER VERMELHO dos arqueiros: as próximas flechas saem DE FOGO (ponta em brasa, queimam quem acertam)
const FLECHAS_DE_FOGO := ["esqueletoArqueiro", "arqueiro"]
var flechas_fogo := 0                     ## quantas flechas de fogo ainda faltam
var queimando := 0.0                      ## segundos pegando fogo (flecha de fogo)
var _queima_dano := 0.0
var _queima_tick := 0.0
var _queima_de := "esqueletoArqueiro"
var selecionado := false                  ## o menu do personagem está aberto nele (luz dourada no chão)
var _luz: Node2D                          ## luz no chão, ATRÁS do personagem (soma luz: brilho de verdade)
static var _tex_luz: Texture2D

# ---- FLUIDEZ: mistura de quadros ----
## Folha com poucos quadros por segundo (parado a 8 fps, andar a 18...) "pula" de um desenho para o outro.
## Abaixo deste fps a Unidade mistura o quadro atual com o PRÓXIMO conforme o tempo passa (como um vídeo
## com interpolação): o movimento fica liso sem mudar a duração da animação nem os quadros de golpe.
const MISTURA_ABAIXO_DE := 30.0
static var _shader_mistura: Shader
var _mat: ShaderMaterial
var _mist_rect := Rect2()                 # quadro que o passo mostrou (outro código trocou = não mistura)
var _mist_prox := -1                      # próximo quadro (-1 = sem mistura)
var _mist_f := 0.0                        # quanto do próximo (0..1)

func iniciar(arena_: Node, p_: PersonagemDados, lado_: String, linha_: int, nivel_: int) -> void:
	arena = arena_
	p = p_
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON   # anda liso entre um passo fixo e outro
	lado = lado_
	linha = linha_
	nivel = nivel_
	atacante = pvp or lado != arena.lado_jogador    # (no PvP pvp=true: ninguém "defende a grade")
	vida_max = p.vida_no_nivel(nivel)
	vida = vida_max
	dano = p.dano_no_nivel(nivel)
	region_enabled = true
	centered = true
	cd_especial = p.extra.get("recarga_terra", p.extra.get("recarga_ossos", p.extra.get("recarga_fogo", 0.0))) * 0.5
	var inicial := "parado"
	if atacante and p.velocidade > 0 and p.anims.has("andar"):
		inicial = "andar"                            # quem vem na onda já entra andando
	elif p.comportamento == "escudo" and not p.anims.has("parado") and p.anims.has("defender"):
		inicial = "defender"                         # sem a folha "parado" (espada na mão): escudo
		trecho = "parado"
	set_anim(inicial)
	# GERADORES (Elara / Esqueleto Black): começam no ponto da animação que faz os dois soltarem
	# a 1ª energia no MESMO tempo depois de colocados (e depois a cada ciclo igual).
	var em: Dictionary = p.extra.get("energia_mao", {})
	if p.comportamento == "gerador" and anim and em.has("comeca_em"):
		t = float(em.comeca_em)
		_ultimo_total = int(t * anim.fps)
		_mostrar(_ultimo_total % anim.quadros)

# ------------------------------------------------------------------ animação
## Centro da cabeça (mira dos tiros): 18% abaixo do topo do quadro atual.
func posicao_cabeca() -> Vector2:
	if anim == null:
		return position + Vector2(0, -50)
	return Vector2(position.x, position.y - anim.ay * scale.y + 0.18 * anim.ch * scale.y)

func set_anim(nome: String, reiniciar := true) -> void:
	var a := p.anim(nome)
	if a == null or a.textura == null:
		a = p.anim_qualquer(["parado", "andar", "defender"])
		if a == null:
			return
	if estado == nome and not reiniciar:
		return
	estado = nome
	_mist_prox = -1                                 # troca de animação: começa sem mistura
	if anim != a:
		anim = a
		texture = a.textura
		scale = Vector2.ONE * p.escala * a.escala
		_escala_base = scale
		# todas as folhas são desenhadas olhando para a direita: vira para o lado do inimigo
		flip_h = _dir() < 0.0
		# os pés no ponto do personagem (quando a imagem é espelhada, o ponto dos pés também espelha)
		var ox := a.cw / 2.0 - a.ax
		offset = Vector2(-ox if flip_h else ox, a.ch / 2.0 - a.ay)
		_offset_base = offset
	t = 0.0
	ultimo_q = -1
	_ultimo_total = -1
	_mostrar(0)

func _mostrar(q: int) -> void:
	region_rect = anim.retangulo(q)

## Avança a animação e devolve os quadros que passaram neste passo (para os eventos de golpe/tiro).
## Reaproveita o mesmo array (não cria memória nova a cada passo).
var _passou := PackedInt32Array()
var _ultimo_total := -1
func _avancar(dt: float) -> PackedInt32Array:
	_passou.clear()
	if anim == null:
		return _passou
	t += dt * (vel_mult if estado == "andar" else 1.0)   # andando mais rápido (Pressa): o passo acompanha
	if anim.tem_laco():                              # entrada 1x + loop (ex.: andar do Engenheiro: 1..95, depois 22..95)
		var ql := anim.quadro_laco(t)
		if ql != ultimo_q:
			_passou.append(ql)
			_mostrar(ql)
		ultimo_q = ql
		_ultimo_total = ql
		var laco := int(anim.extra.laco_de)
		var fe := float(anim.extra.get("fps_entrada", anim.fps))
		var t_ent := laco / maxf(fe, 0.01)
		var pos_q := t * fe if t < t_ent else (t - t_ent) * anim.fps
		_preparar_mistura(ql, laco if ql == anim.quadros - 1 else ql + 1, pos_q - floorf(pos_q))
		return _passou
	var qt := int(t * anim.fps)
	if not anim.repetir:
		qt = mini(qt, anim.quadros - 1)
	for i in range(maxi(_ultimo_total + 1, qt - anim.quadros + 1), qt + 1):
		_passou.append(i % anim.quadros)
	if qt != _ultimo_total:
		_mostrar(qt % anim.quadros)
	_ultimo_total = qt
	ultimo_q = qt % anim.quadros
	if not anim.repetir and qt >= anim.quadros - 1:
		_preparar_mistura(ultimo_q, -1, 0.0)        # acabou: fica no último quadro, sem misturar
	else:
		var pos := t * anim.fps
		_preparar_mistura(ultimo_q, (ultimo_q + 1) % anim.quadros, pos - floorf(pos))
	return _passou

## Guarda a mistura deste passo; quem aplica é o _process (o desenho do quadro na tela).
func _preparar_mistura(q: int, prox: int, f: float) -> void:
	if anim.fps >= MISTURA_ABAIXO_DE or prox < 0 or prox == q:
		_mist_prox = -1
		return
	_mist_rect = region_rect
	_mist_prox = prox
	_mist_f = clampf(f, 0.0, 1.0)

func _process(_delta: float) -> void:
	if anim == null:
		return
	_passo_tranco(_delta)
	_passo_possessao_visual(_delta)                     # (acertado pelo dedo de fogo do Místico)
	_desenho_voo()
	_desenho_nascer()
	if p.extra.has("pavio_andar"):                      # fogo do pavio (Bombardeiro): anima todo quadro
		_passo_fogo(_delta)
		queue_redraw()
	elif pressa > 0.0 or _brilho2 > 0.0 or queimando > 0.0 or flechas_fogo > 0 or sobrecarga > 0.0 or _poder_desenhado:
		queue_redraw()                                   # (faíscas do poder azul / fogo / sobrecarga)
		_poder_desenhado = pressa > 0.0 or _brilho2 > 0.0 or queimando > 0.0 or flechas_fogo > 0 or sobrecarga > 0.0
	var com_luz := (selecionado or pressa > 0.0 or _brilho2 > 0.0 or sobrecarga > 0.0) and not morto
	if com_luz and _luz == null:
		_criar_luz()
	if _luz:
		_luz.visible = com_luz
		if com_luz:
			_luz.queue_redraw()
	# só mistura se o quadro na tela ainda é o que o passo mostrou (voltar/trechos/guarda trocam direto)
	var mistura := _mist_prox >= 0 and region_rect == _mist_rect and texture != null
	if not mistura:
		if _mat:
			_mat.set_shader_parameter("mistura", 0.0)
		return
	if _mat == null:
		if _shader_mistura == null:
			_shader_mistura = Shader.new()
			_shader_mistura.code = SHADER_MISTURA
		_mat = ShaderMaterial.new()
		_mat.shader = _shader_mistura
		material = _mat
	var prox_rect := anim.retangulo(_mist_prox)
	_mat.set_shader_parameter("desloc", (prox_rect.position - region_rect.position) / texture.get_size())
	_mat.set_shader_parameter("mistura", _mist_f)

# ------------------------------------------------------------------ FOGO DO PAVIO (Esqueleto Bombardeiro)
## A ficha guarda onde está a ponta do pavio em cada quadro do andar (extra.pavio_andar, px da folha) e no
## parado (extra.pavio_parado). O fogo é desenhado aqui mesmo (coordenadas da folha): acompanha o passo, a
## respiração, a virada para o lado e a suavidade do movimento.
var _faiscas_fogo: Array = []              # [pos, vel, t, vida]
var _t_fogo := 0.0
var _semente_fogo := -1.0

## Ponta do pavio agora (coordenadas locais da folha, já virada para o lado certo). INF = sem pavio.
func _pavio_local() -> Vector2:
	var pt: Vector2
	var chave := "pavio_andar" if estado == "andar" else ("pavio_atacar" if estado == "atacar" else ("pavio_arremesso" if estado == "arremessar" else ""))
	if chave != "" and anim and p.extra.has(chave):
		var lista: Array = p.extra[chave]
		var q := clampi(ultimo_q, 0, lista.size() - 1)
		var a: Array = lista[q]
		if float(a[0]) < 0.0:                             # sem fogo neste quadro (a bomba já explodiu)
			return Vector2.INF
		pt = Vector2(a[0], a[1])
		if _mist_prox >= 0 and _mist_prox < lista.size() and region_rect == _mist_rect:   # entre dois quadros
			var b: Array = lista[_mist_prox]
			if float(b[0]) >= 0.0:
				pt = pt.lerp(Vector2(b[0], b[1]), _mist_f)
	elif p.extra.has("pavio_parado"):
		var c: Array = p.extra.pavio_parado
		pt = Vector2(c[0], c[1])
	else:
		return Vector2.INF
	var local := Vector2(pt.x - anim.ax, pt.y - anim.ay + 13.0)      # a chama nasce na ponta do pavio (abaixo do centro dela)
	if flip_h:
		local.x = -local.x
	return local

func _passo_fogo(dt: float) -> void:
	if _semente_fogo < 0.0:
		_semente_fogo = float(get_instance_id() % 997) * 0.37
	_t_fogo += dt
	var base := _pavio_local()
	if morto or base == Vector2.INF:
		_faiscas_fogo.clear()
		return
	# faíscas: nascem na chama, sobem espalhando e caem um pouco
	if randf() < dt * 22.0:
		_faiscas_fogo.append([base + Vector2(randf_range(-4, 4), -randf_range(4, 14)),
			Vector2(randf_range(-60, 60), randf_range(-170, -70)), 0.0, randf_range(0.25, 0.6)])
	var i := _faiscas_fogo.size() - 1
	while i >= 0:
		var f: Array = _faiscas_fogo[i]
		f[2] += dt
		f[1].y += 220.0 * dt
		f[0] += f[1] * dt
		if f[2] >= f[3]:
			_faiscas_fogo.remove_at(i)
		i -= 1

func _draw() -> void:
	if p and not morto:
		_desenho_poderes()
	if not p or not p.extra.has("pavio_andar") or morto:
		return
	var base := _pavio_local()
	if base == Vector2.INF:
		return
	var t := _t_fogo + _semente_fogo
	var vento := (-_dir() * 7.0) if estado == "andar" else 0.0          # andando: a chama deita para trás
	# fumaça fininha subindo
	for k in 3:
		var fase := fmod(t * 0.9 + k * 0.33, 1.0)
		var pos := base + Vector2(vento * 1.6 + sin(t * 2.0 + k) * 5.0 * fase, -26.0 - fase * 40.0)
		draw_circle(pos, 5.0 + fase * 9.0, Color(0.25, 0.22, 0.22, 0.18 * (1.0 - fase)))
	# brilho + chama em camadas (a mesma da bomba voando: FxExplosao.desenhar_chama)
	FxExplosao.desenhar_chama(self, base, t, 1.0, vento)
	# faíscas
	for f in _faiscas_fogo:
		var k2: float = f[2] / f[3]
		var cor := Color(1.0, 1.0 - k2 * 0.7, 0.4 - k2 * 0.4, 1.0 - k2)
		draw_circle(f[0], 2.4 * (1.0 - k2) + 0.8, cor)

## Mistura em alfa pré-multiplicado (sem borda escura onde um quadro é transparente e o outro não).
## O "cor" do vertex traz o modulate (brilho de dano, choque elétrico, sumir ao morrer).
const SHADER_MISTURA := """
shader_type canvas_item;
uniform vec2 desloc = vec2(0.0);
uniform float mistura = 0.0;
uniform float corte_v = 2.0;
varying vec4 cor;
void vertex() {
	cor = COLOR;
}
void fragment() {
	vec4 a = texture(TEXTURE, UV);
	if (mistura > 0.002) {
		vec4 b = texture(TEXTURE, UV + desloc);
		a.rgb *= a.a;
		b.rgb *= b.a;
		a = mix(a, b, mistura);
		a.rgb = a.a > 0.0001 ? a.rgb / a.a : vec3(0.0);
	}
	if (UV.y > corte_v) {
		a = vec4(0.0);                      // (invocação) a parte de baixo ainda está dentro do chão
	}
	COLOR = a * cor;
}
"""

func acabou() -> bool:
	return anim != null and not anim.repetir and t >= anim.duracao()

func _evento(passou: PackedInt32Array, quadros: PackedInt32Array) -> int:
	for q in passou:
		if q in quadros:
			return q
	return -1

# ------------------------------------------------------------------ passo da lógica (60x por segundo)
func passo(dt: float) -> void:
	_profundidade()
	if atravessou and t_saida < 1.0:
		t_saida += dt
	if dor > 0.0:
		dor -= dt
		self_modulate = Color(1, 0.55, 0.55) if dor > 0.0 else Color.WHITE
	if mostra_barra > 0.0:
		mostra_barra -= dt
	var acel := 1.0 + pressa * (0.4 if p.comportamento == "gerador" else 1.3)   # PODER AZUL: ataca mais rápido
	if sobrecarga > 0.0:                              # SOBRECARGA: o ciclo de energia corre 2x mais rápido
		sobrecarga = maxf(0.0, sobrecarga - dt)
		acel *= 2.0
	if _pressa_t < 99.0:
		_pressa_t += dt
		if _pressa_t > 1.3:
			pressa = maxf(0.0, pressa - dt * 0.32)
	_brilho2 = maxf(0.0, _brilho2 - dt)
	cd = maxf(0.0, cd - dt * acel)
	cd_especial = maxf(0.0, cd_especial - dt)
	_cd_fogo = maxf(0.0, _cd_fogo - dt * acel)
	if not _fogos_dedo.is_empty():
		_passo_fogos_dedo(dt)                             # (Místico) o fogo do dedo chegando no alvo
	repouso = maxf(0.0, repouso - dt)
	if _nasce_dur > 0.0 and not morto:                # INVOCADO: ainda saindo do chão (não age)
		_nasce_t += dt
		if _nasce_t >= _nasce_dur:
			_nasce_dur = 0.0
		return
	if _voo_dur > 0.0 and not morto:                  # ARREMESSADO (martelo do Darian): voa e cai, sem agir
		_passo_voo(dt)
		return
	var passou := _avancar(dt * acel if (estado in ["atacar", "preparar", "especial"] or p.comportamento == "gerador") else dt)
	if morto:
		_morrendo(passou, dt)
		return
	if queimando > 0.0 and not morto:                 # pegando fogo (flecha de fogo)
		queimando -= dt
		_queima_tick -= dt
		if _queima_tick <= 0.0:
			_queima_tick = 0.5
			arena.ferir(self, _queima_dano, null, _queima_de, Color("ff9a3a"))
		if queimando <= 0.0:
			_queima_dano = 0.0
	if forcar2:                                       # PODER VERMELHO: solta o poder 2 agora
		forcar2 = false
		if p.id in FLECHAS_DE_FOGO:
			flechas_fogo = 6                              # as próximas 6 flechas saem de fogo
			cd = minf(cd, 0.1)
			_brilho2 = 0.9
		elif p.anims.has("especial") and estado != "especial":
			cd_especial = 0.0
			defendendo = false
			trecho = ""
			set_anim("especial")
			_brilho2 = 0.9
		elif p.comportamento == "gerador":
			_sobrecarga_energia()
	if pvp and ordem == "voltar" and _recuar(dt):
		return
	_decidir_virada(dt)                               # inimigo atrás? vira e luta com ele
	if not pvp and not atacante and _mover_campanha(dt):
		return
	if pvp and _passo_pvp(dt):
		return
	# CAMPANHA: o herói atacando (jogador de Monsters) — os cérebros de herói nunca andaram, então
	# o passo de andar é aqui, antes do cérebro decidir o golpe.
	if not pvp and atacante and lado == "heroes" and _caminhar(dt):
		return
	match p.comportamento:
		"gerador": _gerador(passou)
		"corpo_a_corpo": _corpo_a_corpo(dt, passou)
		"atirador": _atirador(dt, passou)
		"mago": _mago(dt, passou)
		"escudo": _escudo(dt, passou)
		"sentinela": _sentinela(dt, passou)
		"tita": _tita(dt, passou)
		"necro": _necro(dt, passou)
		"bombardeiro": _bombardeiro(dt, passou)
		"golem": _golem(dt, passou)
		"darian": _darian(dt, passou)
		"mistico": _mistico(dt, passou)
		"aura": _aura(dt, passou)

## Quem está lutando fica "na frente" (desenhado por cima) para dar para ver o golpe no inimigo.
## A camada das unidades ordena pelo Y (y-sort: quem está mais embaixo fica por cima), então basta
## dar um pouquinho de Y a mais para quem bate — e no empate (os dois batendo) o herói ganha.
func _profundidade() -> void:
	var k := 0.05 if lado == "heroes" else 0.0
	if not morto and (estado in ["atacar", "preparar", "especial"] or cd > 0.0):
		k += 0.55 if lado == "heroes" else 0.35
	position.y += k - _prof                      # anda só a diferença (nunca acumula erro)
	_prof = k

## +1 = o inimigo está à direita; -1 = à esquerda. Na campanha: quem defende olha para a direita
## (os inimigos entram por lá) e quem ataca marcha para a esquerda (o castelo é o da esquerda).
func _dir() -> float:
	return arena.dir_de(lado) * (-1.0 if virado else 1.0)     # (virado = luta / anda para o outro lado)

## O lado normal (para onde o inimigo vem), sem contar o virar.
func _dir_base() -> float:
	return arena.dir_de(lado)

## Velocidade de quem anda: os monstros têm velocidade na ficha; os heróis guardam a deles no
## extra.andar (medida pelo medir_andar.gd) — mesma tabela que o PvP usa (ConfigPvp.ANDAR).
func _vel_atacante() -> float:
	return (p.velocidade if p.velocidade > 0.0 else float(ConfigPvp.andar(p.id).velocidade)) * vel_mult

## CAMPANHA: o atacante caminha até a distância de luta do seu lado e aí o cérebro assume o golpe.
## Devolve true quando este passo já foi resolvido aqui (andou).
func _caminhar(dt: float) -> bool:
	if not atacante or p.comportamento == "gerador":
		return false
	if p.comportamento == "darian" and (estado == "especial" or arena.ameaca_no_chao(self) < INF):
		return false
	var vel := _vel_atacante()
	if vel <= 0.0:
		return false
	if arena.alvo_na_frente(self, float(ConfigPvp.andar(p.id).para)) != null:
		return false                                 # deu de cara no inimigo: o cérebro luta
	if estado != "andar":
		set_anim("andar")
	position.x += _dir() * vel * dt
	return true

func _andar(dt: float) -> void:
	if not pvp and not atacante:                 # DEFENSOR da campanha: fica firme na casa dele
		_pose_guarda()
		return
	if p.velocidade <= 0:
		return
	if virado and _chegar_no_de_tras(dt):        # virou para quem chegou por trás: anda até encostar nele e luta
		return
	if guarda or ordem == "parar" or virado:    # CERCO: firme no lugar (ou mandou parar, ou está virado lutando atrás)
		_pose_guarda()
		return
	if fixo:                                      # PvP: preparo (fica no lugar até o "LUTEM!")
		if p.anims.has("parado"):
			_pose_guarda()                        # parado respirando (igual à campanha antes de começar)
		return
	var x0 := position.x
	var nx: float
	if pvp:
		nx = x0 - p.velocidade * dt * arena.marcha(self)
		nx = maxf(nx, arena.limite_x(self))       # CERCO: não passa do 2º quadrado antes do castelo
	else:
		nx = x0 + p.velocidade * vel_mult * dt * _dir()   # campanha: caminha para o lado do inimigo
	if nx >= x0 - 0.001 and pvp:                  # parado no cerco: pose parada (se tiver), respirando
		if p.anims.has("parado"):
			_pose_guarda()
		return
	if estado != "andar":
		set_anim("andar")
	position.x = nx

## Defensor parado: pose "parado" (se a folha tiver); senão o 1º quadro do andar, respirando devagar.
func _pose_guarda() -> void:
	if p.anims.has("parado"):
		if estado != "parado":
			set_anim("parado")
		if anim.quadros == 1:                         # parado de 1 quadro só (ex.: Bombardeiro): respira
			_respirar()
		return
	if estado != "andar":
		set_anim("andar")
	region_rect = anim.retangulo(0)
	_respirar()

## Respiração de quem está parado num quadro só: o peito sobe e desce devagar (os pés ficam no chão).
func _respirar() -> void:
	if _fase_resp == 0.0:
		_fase_resp = 0.01 + float(get_instance_id() % 628) / 100.0
	var r := sin(Time.get_ticks_msec() / 1000.0 * 2.2 + _fase_resp)
	scale = Vector2(_escala_base.x * (1.0 - 0.006 * r), _escala_base.y * (1.0 + 0.018 * r))

# ------------------------------------------------------------------ PvP
func _pose_parada() -> String:
	if p.anims.has("parado"):
		return "parado"                             # Protetor G: parado com a espada na mão
	return "defender" if p.comportamento == "escudo" and p.anims.has("defender") else "parado"

func _ocupado() -> bool:
	return estado in ["atacar", "preparar", "especial", "guarda", "voltar"] or (trecho != "" and trecho != "parado")

## Herói andando (PvP): anda até ter um inimigo logo à frente, ou até o cerco; aí o "cérebro" dele assume.
## Devolve true quando este passo já foi resolvido aqui (andou ou está respirando antes de atacar).
func _passo_pvp(dt: float) -> bool:
	no_cerco = arena.no_cerco(self)
	# Sentinela / Titã no cerco: usam o poder no castelo (a onda vai até o castelo)
	if no_cerco and p.id in ConfigPvp.PODER_NO_CASTELO and not _ocupado() and cd_especial <= 0.0 and p.anims.has("especial"):
		set_anim("especial")
		return false
	if lado != "heroes" or not anda:
		return false
	if p.comportamento == "darian" and (estado == "especial" or arena.ameaca_no_chao(self) < INF):
		return false                                   # Darian: para de andar para bloquear a onda
	if p.comportamento == "aura" and (estado in ["especial", "atacar"] or _aura_tem_o_que_fazer()):
		return false                                   # Aura: para de andar para curar / purificar
	var frente: bool = arena.alvo_na_frente(self, para) != null
	if not frente and p.comportamento in _DE_LONGE and p.comportamento != "golem":
		frente = arena.alvo_visivel(self) != null          # DE LONGE: inimigo apareceu na arena = para e ataca
	if virado and _chegar_no_de_tras(dt):                # inimigo atrás, fora do golpe: vai até ele
		return true
	if not _ocupado() and not frente and not no_cerco and not fixo and ordem != "parar" and not virado:
		if estado != "andar":
			set_anim("andar")
		position.x = minf(position.x + vel_andar * dt * arena.marcha(self), arena.limite_x(self))
		return true
	if estado == "andar":
		set_anim(_pose_parada())
		pausa = pausa_parar
	if pausa > 0.0 and not _ocupado():
		pausa -= dt
		return true
	return false

# ------------------------------------------------------------------ COMANDOS DO JOGADOR
## Toque no PODER AZUL: acelera os ataques (cada toque soma; tocar várias vezes = flechas/golpes bem mais rápidos).
func toque_azul() -> void:
	pressa = minf(1.0, pressa + 0.22)
	_pressa_t = 0.0
	cd = minf(cd, 0.12)                           # já ataca logo
	queue_redraw()

func tem_poder2() -> bool:
	return (p.anims.has("especial") or p.id in FLECHAS_DE_FOGO or p.comportamento == "gerador") and not morto

## Já está usando o poder 2 (não dá para pedir de novo agora). A sobrecarga dá para comprar de novo mesmo
## ligada (cada compra solta outra rajada e renova o tempo) — só trava um instante contra toque duplo.
func usando_poder2() -> bool:
	return estado == "especial" or flechas_fogo > 0 or (p.comportamento == "gerador" and _brilho2 > 0.0)

## SOBRECARGA DE ENERGIA: rajada de orbes de energia na hora + gera o dobro, 2x mais rápido, por um tempo.
func _sobrecarga_energia() -> void:
	sobrecarga = SOBRECARGA_DUR
	_brilho2 = 0.9
	var em: Dictionary = p.extra.get("energia_mao", {})
	var mao := position + Vector2(float(em.get("x", 0)), float(em.get("y", -50)))
	for k in SOBRECARGA_RAJADA:
		var desvio := float(k) - (SOBRECARGA_RAJADA - 1) / 2.0
		var pos := mao + Vector2(desvio * 34.0, -absf(desvio) * 10.0 - 12.0)
		_soltar_energia(pos, p.gera_energia * 2)
	Sons.do_personagem(p, "gerar")

## Solta um orbe de energia para o lado desta tropa (igual ao ciclo normal do gerador).
func _soltar_energia(pos: Vector2, valor: int) -> void:
	if pvp:                                           # PvP: Elara e Esqueleto Black geram para o lado deles
		arena.soltar_energia_lado(pos, valor, lado, self)   # (também na arena inimiga)
	elif lado == arena.lado_jogador:                  # campanha: gera para quem está defendendo
		arena.soltar_energia(pos, valor)

## FLECHA DE FOGO acertou: pega fogo (dano aos poucos, a cada meio segundo).
func queimar(dur: float, dano_tick: float, de := "esqueletoArqueiro") -> void:
	_queima_de = de
	queimando = maxf(queimando, dur)
	_queima_dano = maxf(_queima_dano, dano_tick)

## LUTA PARA TRÁS (todos os personagens): sem inimigo na frente mas com um ATRÁS no alcance = vira e luta com ele;
## quando acaba, vira de volta. Só decide fora de um golpe (não vira no meio do ataque).
var _virada_t := 0.0
func _decidir_virada(dt: float) -> void:
	if p.comportamento == "gerador" or _voo_dur > 0.0 or ordem == "voltar" or alvo_x != INF:
		return
	_virada_t -= dt
	if _virada_t > 0.0 or _ocupado():
		return
	_virada_t = 0.25
	var base := _dir_base()
	var na_frente := _tem_inimigo_para(base)
	if na_frente and pvp and arena.no_cerco(self) and _tem_inimigo_para(-base):
		_virar(true)                                      # atacando o castelo e chegou inimigo nas costas: defende-se primeiro
	elif na_frente:
		_virar(false)                                     # inimigo na frente sempre tem prioridade
	elif _tem_inimigo_para(-base):
		_virar(true)
	elif virado:
		_virar(false)

## ATAQUE DE LONGE: quem defende (campanha) e as tropas do PvP atacam assim que o inimigo APARECE na arena
## (sem esperar ele chegar perto). Os inimigos das ondas da campanha continuam parando no alcance deles.
func _alvo_de_longe(alcance: float) -> Unidade:
	if pvp or not atacante:
		var v: Unidade = arena.alvo_visivel(self)
		if v:
			return v
	return arena.alvo_na_frente(self, alcance)

## Quem atira de longe (arqueiros, magos, Engenheiro...) enxerga a LINHA INTEIRA; quem luta de perto, só o alcance.
const _DE_LONGE := ["atirador", "mago", "necro", "bombardeiro", "golem"]
func _tem_inimigo_para(s: float) -> bool:
	if p.comportamento in _DE_LONGE:
		var antes := virado
		virado = (s != _dir_base())
		var tem: bool = arena.tem_inimigo_na_linha(self)
		virado = antes
		return tem
	return _inimigo_no_sentido(s) != null

## Inimigo no alcance do personagem para o lado s (+1 direita / -1 esquerda), sem mudar para onde ele olha.
func _inimigo_no_sentido(s: float) -> Unidade:
	var antes := virado
	virado = (s != _dir_base())
	var alc := maxf(p.alcance if p.alcance > 0 else 130.0, 110.0)
	var a: Unidade = arena.alvo_na_frente(self, alc)
	virado = antes
	return a

## INIMIGO ATRÁS (ex.: tropa colocada nas costas): quem luta de PERTO já virou para ele, mas se ele não está
## colado (fora do golpe) dá uns passos até encostar — nunca fica parado de costas sem fazer nada.
## Quem atira de longe não precisa (já atira na linha inteira). Devolve true enquanto está andando até ele.
func _chegar_no_de_tras(dt: float) -> bool:
	if not virado or p.comportamento in _DE_LONGE or guarda or ordem == "parar" or _ocupado() or not p.anims.has("andar"):
		return false
	var contato: float = ConfigArena.CONTATO_MONSTRO if lado == "monsters" else (p.alcance if p.alcance > 0 else 60.0)
	if arena.alvo_na_frente(self, contato) != null:
		return false                                       # já está colado: o cérebro bate
	var e := _inimigo_no_sentido(_dir())
	if e == null:
		return false
	if estado != "andar":
		set_anim("andar")
	var v := vel_andar if vel_andar > 0.0 else float(p.velocidade)
	var passo := maxf(v, 40.0) * dt
	var falta := absf(e.position.x - position.x) - contato * 0.85
	position.x += _dir() * minf(passo, maxf(falta, 0.0))
	return true

## Vira a folha (andando de costas = voltando). Os pés continuam no mesmo ponto.
func _virar(v: bool) -> void:
	if v == virado or anim == null:
		return
	virado = v
	flip_h = _dir() < 0.0
	var ox := anim.cw / 2.0 - anim.ax
	offset = Vector2(-ox if flip_h else ox, anim.ch / 2.0 - anim.ay)
	_offset_base = offset

func _vel_comando() -> float:
	var v := vel_andar if (pvp and lado == "heroes" and vel_andar > 0.0) else _vel_atacante()
	return maxf(v, 55.0)

## CAMPANHA: anda de casa em casa (a arena reserva a casa nova antes). Devolve true enquanto está andando.
func _mover_campanha(dt: float) -> bool:
	if alvo_x == INF:
		if ordem == "voltar" or (ordem == "andar" and estado != "especial"):   # (voltar larga o ataque na hora)
			_ordem_t -= dt
			if _ordem_t <= 0.0:
				_ordem_t = 0.35
				arena.proxima_casa(self)          # tenta a próxima casa (ou para, se não der)
		return alvo_x != INF
	var dx := alvo_x - position.x
	if absf(dx) > 0.5 and (_inimigo_no_sentido(signf(dx)) != null or (_ocupado() and estado != "andar")):
		_virar(signf(dx) != _dir_base())
		return false                                  # inimigo no caminho: para e luta (depois segue)
	_virar(signf(dx) != _dir_base() and absf(dx) > 0.5)
	if estado != "andar" and p.anims.has("andar"):
		set_anim("andar")
	var passo_x := _vel_comando() * 0.9 * dt
	if absf(dx) <= passo_x:
		position.x = alvo_x
		alvo_x = INF
		_virar(false)
		_pose_guarda()
		_ordem_t = 0.0
		return true
	position.x += signf(dx) * passo_x
	return true

## PvP: VOLTAR — anda de costas para o próprio lado (sem lutar) até o começo da arena, e aí para.
func _recuar(dt: float) -> bool:
	var lim: float = arena.limite_recuo(self)
	var sentido := -_dir_base()
	if (position.x - lim) * sentido >= 0.0:            # já está no começo da arena: só para (nunca anda para a frente)
		ordem = "parar"
		_virar(false)
		set_anim(_pose_parada())
		return true
	_virar(true)
	if _inimigo_no_sentido(sentido) != null or _ocupado():
		return false                                  # inimigo no caminho de volta: luta virado para ele
	if estado != "andar" and p.anims.has("andar"):
		set_anim("andar")
	var nx := position.x + sentido * _vel_comando() * 0.85 * dt
	if (sentido < 0.0 and nx <= lim) or (sentido > 0.0 and nx >= lim):
		position.x = lim
		ordem = "parar"
		_virar(false)
		set_anim(_pose_parada())
		return true
	position.x = nx
	return true

## Brilho do PODER AZUL (anel azul nos pés + faíscas subindo) e do VERMELHO (explosão de brilho) — desenhado
## por cima do personagem, sem atrapalhar.
## Cor da energia da sobrecarga: dourada na Elara, verde-ácido no Esqueleto Black.
func _cor_sobrecarga() -> Color:
	return Color(1.0, 0.82, 0.3) if lado == "heroes" else Color(0.72, 1.0, 0.3)

func _desenho_poderes() -> void:
	if queimando > 0.0 or flechas_fogo > 0:
		_desenho_fogo()
	if sobrecarga > 0.0:
		_desenho_sobrecarga()
	if pressa <= 0.01:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0 / maxf(absf(scale.x), 0.01), 1.0 / maxf(absf(scale.y), 0.01)))
	var tt := Time.get_ticks_msec() / 1000.0
	var a := clampf(pressa * 1.4, 0.0, 1.0)
	for s in 7:                                       # faíscas azuis subindo do chão (bem pequenas)
		var f := fmod(tt * 1.2 + s * 0.143, 1.0)
		var px := sin(s * 2.3 + tt * 2.0) * 28.0
		var pos := Vector2(px, -6.0 - f * 110.0)
		draw_circle(pos, 4.0 * (1.0 - f) + 1.0, Color(0.45, 0.75, 1.0, 0.25 * (1.0 - f) * a))
		draw_circle(pos, 1.6 * (1.0 - f) + 0.6, Color(0.85, 0.95, 1.0, 0.9 * (1.0 - f) * a))
	draw_set_transform(Vector2.ZERO)

## SOBRECARGA: anéis de energia girando em volta do corpo, faíscas subindo em espiral e um contador de tempo
## (o anel no chão vai fechando conforme acaba).
func _desenho_sobrecarga() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0 / maxf(absf(scale.x), 0.01), 1.0 / maxf(absf(scale.y), 0.01)))
	var tt := Time.get_ticks_msec() / 1000.0
	var cor := _cor_sobrecarga()
	var alt := (anim.ay * absf(scale.y)) if anim else 110.0
	var fim := clampf(sobrecarga / 1.0, 0.0, 1.0)            # (some suave no último segundo)
	# dois anéis de energia (elipses) subindo e descendo pelo corpo, girando
	for k in 2:
		var y := -alt * (0.3 + 0.35 * (0.5 + 0.5 * sin(tt * 2.2 + k * PI)))
		var pts := PackedVector2Array()
		for i in 25:
			var ang := TAU * i / 24.0 + tt * (3.0 if k == 0 else -3.0)
			pts.append(Vector2(cos(ang) * 38.0, y + sin(ang) * 9.0))
		draw_polyline(pts, Color(cor, 0.35 * fim), 5.0, true)
		draw_polyline(pts, Color(cor.lightened(0.5), 0.85 * fim), 1.8, true)
	# faíscas subindo em espiral
	for s in 10:
		var f := fmod(tt * 0.9 + s * 0.1, 1.0)
		var ang := s * 2.4 + tt * 4.0
		var pos := Vector2(cos(ang) * (34.0 - f * 18.0), -f * alt * 1.15)
		draw_circle(pos, 3.6 * (1.0 - f) + 1.0, Color(cor, 0.35 * (1.0 - f) * fim))
		draw_circle(pos, 1.6 * (1.0 - f) + 0.6, Color(1, 1, 0.9, 0.95 * (1.0 - f) * fim))
	# tempo que falta: arco no chão que vai fechando
	var resta := sobrecarga / SOBRECARGA_DUR
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0 / maxf(absf(scale.x), 0.01), 0.32 / maxf(absf(scale.y), 0.01)))
	draw_arc(Vector2.ZERO, 44.0, -PI / 2.0, -PI / 2.0 + TAU * resta, 40, Color(0, 0, 0, 0.45 * fim), 9.0, true)
	draw_arc(Vector2.ZERO, 44.0, -PI / 2.0, -PI / 2.0 + TAU * resta, 40, Color(cor, 0.95 * fim), 5.0, true)
	draw_set_transform(Vector2.ZERO)

## Fogo no corpo de quem foi acertado pela flecha de fogo (e a brasa na mão do arqueiro com o poder ligado).
func _desenho_fogo() -> void:
	var sx := 1.0 / maxf(absf(scale.x), 0.01)
	var sy := 1.0 / maxf(absf(scale.y), 0.01)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(sx, sy))
	var tt := Time.get_ticks_msec() / 1000.0
	var alt := (anim.ay * absf(scale.y)) if anim else 120.0
	if queimando > 0.0:
		var a := clampf(queimando / 0.6, 0.0, 1.0)
		for k in 4:                                   # labaredas pelo corpo, cada uma no seu ritmo
			var fx := sin(k * 2.1 + 0.7) * 16.0
			var fy := -alt * (0.18 + 0.2 * k)
			FxExplosao.desenhar_chama(self, Vector2(fx, fy), tt * (1.2 + k * 0.2) + k, (0.55 - k * 0.07) * a, -_dir() * 4.0)
		for s in 6:                                   # brasas subindo
			var f := fmod(tt * 1.6 + s * 0.17, 1.0)
			draw_circle(Vector2(sin(s * 2.7 + tt) * 20.0, -alt * 0.3 - f * alt * 0.9), 2.4 * (1.0 - f) + 0.6, Color(1.0, 0.75 - f * 0.4, 0.2, 0.9 * (1.0 - f) * a))
	if flechas_fogo > 0:                              # MIRANDO com o poder ligado: o fogo fica na PONTA da flecha no arco
		var ponta := _ponta_flecha_tela()
		if ponta != Vector2.INF:
			var p2 := 0.85 + 0.15 * sin(tt * 18.0)
			draw_circle(ponta, 26.0 * p2, Color(1.0, 0.2, 0.0, 0.16))
			draw_circle(ponta, 14.0 * p2, Color(1.0, 0.45, 0.05, 0.4))
			FxExplosao.desenhar_chama(self, ponta + Vector2(0, 5), tt * 2.0, 0.5, -_dir() * 6.0)
			draw_circle(ponta, 4.5, Color(1.0, 0.95, 0.7, 0.95))
			for s in 4:                                   # faisquinhas soltando da ponta
				var f := fmod(tt * 2.5 + s * 0.25, 1.0)
				draw_circle(ponta + Vector2(-_dir() * f * 14.0 + sin(s * 2.0 + tt * 7.0) * 4.0, -f * 30.0), 1.8 * (1.0 - f) + 0.5, Color(1.0, 0.85, 0.4, 1.0 - f))
	draw_set_transform(Vector2.ZERO)

## Onde está a ponta da flecha no arco AGORA (pixels de tela a partir dos pés), pelo quadro da animação de atirar
## (medido na folha: extra.ponta_flecha — ferramentas/medir_ponta_flecha.gd). INF = sem flecha no arco.
func _ponta_flecha_tela() -> Vector2:
	if estado != "atacar" or anim == null:
		return Vector2.INF
	var lista: Array = p.extra.get("ponta_flecha", [])
	if ultimo_q < 0 or ultimo_q >= lista.size():
		return Vector2.INF
	var pt: Array = lista[ultimo_q]
	if int(pt[0]) < 0:
		return Vector2.INF
	var fs := -1.0 if flip_h else 1.0
	return Vector2((float(pt[0]) - anim.ax) * fs * absf(scale.x), (float(pt[1]) - anim.ay) * absf(scale.y))

## Luz no chão (filho com show_behind_parent: fica ATRÁS do personagem, mistura somando = brilho de verdade).
func _criar_luz() -> void:
	if _tex_luz == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.75))
		g.add_point(0.6, Color(1, 1, 1, 0.22))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 128
		gt.height = 128
		_tex_luz = gt
	_luz = Node2D.new()
	_luz.show_behind_parent = true
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_luz.material = m
	_luz.draw.connect(_desenhar_luz)
	add_child(_luz)

func _poça(centro: Vector2, larg: float, alt: float, cor: Color) -> void:
	_luz.draw_texture_rect(_tex_luz, Rect2(centro - Vector2(larg, alt) / 2.0, Vector2(larg, alt)), false, cor)

func _desenhar_luz() -> void:
	_luz.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0 / maxf(absf(scale.x), 0.01), 1.0 / maxf(absf(scale.y), 0.01)))
	var tt := Time.get_ticks_msec() / 1000.0
	if selecionado and pressa < 0.6:                  # luz dourada quente, respirando (o azul tem prioridade)
		var p := (0.85 + 0.15 * sin(tt * 3.0)) * (1.0 - pressa / 0.6)
		_poça(Vector2(0, 2), 230.0, 70.0, Color(1.0, 0.72, 0.3, 0.30 * p))
		_poça(Vector2(0, 0), 130.0, 38.0, Color(1.0, 0.85, 0.5, 0.55 * p))
	if pressa > 0.01:                                 # poder azul: luz azul elétrica tremendo
		var a := clampf(pressa * 1.3, 0.0, 1.0)
		var f := 0.9 + 0.1 * sin(tt * 17.0) * sin(tt * 5.3)
		_poça(Vector2(0, 2), 210.0 * f, 64.0 * f, Color(0.0, 0.22, 1.0, 0.55 * a))
		_poça(Vector2(0, 0), 110.0 * f, 32.0 * f, Color(0.1, 0.45, 1.0, 0.6 * a))
	if sobrecarga > 0.0:                              # SOBRECARGA: luz da energia pulsando no corpo e no chão
		var cs := _cor_sobrecarga()
		var fim := clampf(sobrecarga, 0.0, 1.0)
		var pul := 0.85 + 0.15 * sin(tt * 6.0)
		_poça(Vector2(0, 2), 240.0 * pul, 74.0 * pul, Color(cs, 0.45 * fim))
		_poça(Vector2(0, -70.0), 170.0 * pul, 200.0 * pul, Color(cs, 0.22 * fim))
	if _brilho2 > 0.0:                                # poder vermelho: clarão quente que abre e some
		var b := _brilho2 / 0.9
		var e := 1.0 + (1.0 - b) * 1.6
		var cb := _cor_sobrecarga() if p.comportamento == "gerador" else Color(1.0, 0.35, 0.1)   # (gerador: clarão de energia)
		_poça(Vector2(0, 0), 170.0 * e, 52.0 * e, Color(cb, 0.65 * b))
		_poça(Vector2(0, -60.0), 160.0 * e, 160.0 * e, Color(cb.lightened(0.1), 0.25 * b))
	_luz.draw_set_transform(Vector2.ZERO)
# ------------------------------------------------------------------ cérebros
func _gerador(passou: PackedInt32Array) -> void:
	var em: Dictionary = p.extra.get("energia_mao", {})
	if em.is_empty():
		return
	if int(em.quadro) in passou:
		var valor := p.gera_energia * (2 if sobrecarga > 0.0 else 1)   # (sobrecarga: o dobro)
		_soltar_energia(position + Vector2(em.x, em.y), valor)
		if pvp or lado == arena.lado_jogador:
			Sons.do_personagem(p, "gerar")

func _corpo_a_corpo(dt: float, passou: PackedInt32Array) -> void:
	# monstros encostam no herói antes de bater (como no site: até 50 px); heróis usam o alcance da ficha
	var alcance := (p.alcance if p.alcance > 0 else 60.0) if lado == "heroes" else ConfigArena.CONTATO_MONSTRO
	var alvo: Unidade = arena.alvo_na_frente(self, alcance)
	if lado == "heroes":
		if estado == "atacar":
			var ev := _evento(passou, anim.quadros_acao)
			if ev >= 0 and alvo:
				arena.ferir(alvo, dano, self)
			if _evento(passou, anim.quadros_som) >= 0:
				Sons.do_personagem(p, "ataque")
			if acabou():
				cd = p.intervalo_ataque
				set_anim("parado")
		elif alvo and cd <= 0.0:
			set_anim("atacar")
		elif estado != "parado":
			set_anim("parado")
		return
	# monstro: anda até encontrar um herói ou o castelo; bate a cada intervalo
	if alvo:
		if estado != "atacar":
			set_anim("atacar")
			cd = minf(cd, ConfigArena.ATK_MONSTRO)
		if cd <= 0.0:
			arena.ferir(alvo, dano, self)
			Sons.do_personagem(p, "atacar")
			cd = ConfigArena.ATK_MONSTRO
			if p.id == "esqueleto" and alvo.morto:
				repouso = 1.2            # abateu: espreguiçada no repouso antes de prosseguir
	elif repouso > 0.0:
		if estado != "parado":
			set_anim("parado")
	else:
		_andar(dt)

## ESQUELETO BOMBARDEIRO — dois ataques:
##  - DE LONGE ("arremessar"): o 1º inimigo da linha está até extra.arremesso.alcance -> para e arremessa
##    por cima da cabeça; a bomba voa num arco alto e EXPLODE AO TOCAR NO CORPO dele;
##  - DE PERTO ("atacar"): inimigo a 1 quadrado -> joga a bomba no pé dele (explode no chão).
## A bomba voando e a explosão que se vê são do jogo (por cima de todos); o dano é decidido no passo fixo.
func _bombardeiro(dt: float, passou: PackedInt32Array) -> void:
	_passo_bomba_longe(dt)
	if estado == "atacar":                               # jogando na frente: termina o movimento mesmo sem alvo
		var solta := int(p.extra.get("solta_quadro", -1))
		if solta >= 0 and solta in passou:
			_soltar_bomba()                              # sai da mão: voa até o inimigo (por cima de todos)
		if _evento(passou, anim.quadros_acao) >= 0:
			_explodir_bomba()                            # tocou o chão: dano (a explosão que se vê é a da bomba voando)
		if acabou():
			cd = p.intervalo_ataque
			_pose_guarda()
		return
	if estado == "arremessar":                           # arremesso longo
		if _evento(passou, anim.quadros_acao) >= 0:
			_arremessar_bomba()
		if acabou():
			cd = p.intervalo_ataque
			_pose_guarda()
		return
	var alcance := p.alcance if p.alcance > 0 else 100.0
	var alvo: Unidade = arena.alvo_na_frente(self, alcance)
	var arr: Dictionary = p.extra.get("arremesso", {})
	var longe: Unidade = null
	if alvo == null and p.anims.has("arremessar") and not arr.is_empty():
		longe = _alvo_de_longe(float(arr.get("alcance", 420.0)))
	if alvo == null and longe == null:
		# CERCO (PvP): parado no 2º quadrado da arena inimiga -> arremessa na parede do castelo
		if pvp and arena.has_method("no_cerco") and arena.no_cerco(self) and p.anims.has("arremessar") and not virado:
			z_index = 1
			if cd <= 0.0 and _t_impacto <= 0.0:
				_no_castelo = true
				set_anim("arremessar")
				Sons.do_personagem(p, "ataque")
			else:
				_pose_guarda()
			return
		z_index = 0                                      # andando: camada normal
		_andar(dt)
		return
	_no_castelo = false
	z_index = 1                                          # lutando: SEMPRE na frente de quem está colado nele
	if cd <= 0.0 and alvo and p.anims.has("atacar"):     # (não pula de frente para trás entre um arremesso e outro)
		set_anim("atacar")
		_ponto_bomba = Vector2.INF
		Sons.do_personagem(p, "ataque")
		return
	if cd <= 0.0 and longe and _t_impacto <= 0.0:
		set_anim("arremessar")
		Sons.do_personagem(p, "ataque")
		return
	_pose_guarda()                                       # esperando o próximo arremesso: parado, respirando

# ---- arremesso longo: a bomba voa até o corpo do 1º inimigo da linha e explode nele ----
var _t_impacto := 0.0                     # segundos até a bomba longe chegar (passo fixo)
var _alvo_longe: Unidade = null
var _ponto_longe := Vector2.INF           # pé do alvo na hora do arremesso (se ele sumir, explode ali)

var _no_castelo := false                  # o arremesso atual vai na parede do castelo (cerco)
var _castelo_alvo := ""                   # lado do castelo que a bomba no ar vai acertar

func _arremessar_bomba() -> void:
	var arr: Dictionary = p.extra.get("arremesso", {})
	if _no_castelo and arena.has_method("_ponto_castelo"):
		_arremessar_no_castelo(arr)
		return
	var alvo: Unidade = _alvo_de_longe(float(arr.get("alcance", 420.0)) + 80.0)
	var dir := _dir()
	var pe := Vector2(position.x + dir * 300.0, position.y) if alvo == null else alvo.position
	var altura_alvo := 90.0 if alvo == null else alvo.anim.ay * absf(alvo.scale.y)
	var corpo := pe + Vector2(0, -altura_alvo * 0.45)             # explode no peito dele
	var sp: Array = arr.get("solta_ponto", [anim.ax + 120.0, anim.ay - 190.0])
	var local := Vector2(float(sp[0]) - anim.ax, float(sp[1]) - anim.ay)
	if flip_h:
		local.x = -local.x
	var de := position + local * scale
	var dur := maxf(0.35, absf(corpo.x - de.x) / float(arr.get("velocidade", 560.0)))
	_alvo_longe = alvo
	_ponto_longe = pe
	_t_impacto = dur
	var fogo: Array = p.extra.get("fogo_na_bomba", [48, 0])
	var tex_b: Texture2D = load(str(p.extra.get("bomba_img", ""))) if p.extra.has("bomba_img") else null
	if tex_b:
		arena.lancar_bomba(tex_b, de, corpo, dur, scale.x, flip_h, Vector2(float(fogo[0]), float(fogo[1])), pe)

func _arremessar_no_castelo(arr: Dictionary) -> void:
	_castelo_alvo = "monsters" if lado == "heroes" else "heroes"
	var sp: Array = arr.get("solta_ponto", [anim.ax + 120.0, anim.ay - 190.0])
	var local := Vector2(float(sp[0]) - anim.ax, float(sp[1]) - anim.ay)
	if flip_h:
		local.x = -local.x
	var de := position + local * scale
	var parede: Vector2 = arena._ponto_castelo(_castelo_alvo, position.y - 70.0)   # na parede, na altura do peito
	var pe := Vector2(parede.x, position.y)                                       # a base da parede (chão)
	var dur := maxf(0.35, absf(parede.x - de.x) / float(arr.get("velocidade", 560.0)))
	_alvo_longe = null
	_ponto_longe = parede
	_t_impacto = dur
	var fogo: Array = p.extra.get("fogo_na_bomba", [48, 0])
	var tex_b: Texture2D = load(str(p.extra.get("bomba_img", ""))) if p.extra.has("bomba_img") else null
	if tex_b:
		arena.lancar_bomba(tex_b, de, parede, dur, scale.x, flip_h, Vector2(float(fogo[0]), float(fogo[1])), pe)

func _passo_bomba_longe(dt: float) -> void:
	if _t_impacto <= 0.0:
		return
	_t_impacto -= dt
	if _t_impacto <= 0.0:
		_impacto_longe()

func _impacto_longe() -> void:
	_t_impacto = 0.0
	if _castelo_alvo != "":                              # acertou a parede do castelo
		var lado_c := _castelo_alvo
		_castelo_alvo = ""
		arena.bomba_no_castelo(self, _ponto_longe, lado_c)
		_ponto_longe = Vector2.INF
		return
	var ponto := _ponto_longe
	if is_instance_valid(_alvo_longe) and not _alvo_longe.morto:
		ponto = _alvo_longe.position                         # encostou nele: explode onde ele está
	var bomba: Dictionary = p.extra.get("bomba", {})
	arena.explodir_bomba(self, ponto, dano, roundi(float(bomba.get("dano_area", 0)) * Progressao.multiplicador(nivel)),
		float(bomba.get("raio", 90.0)))
	_alvo_longe = null
	_ponto_longe = Vector2.INF

## Onde a bomba vai cair: no pé do inimigo da frente (o mais perto), entre 30 e 170 px à frente.
## Decidido na hora que ela sai da mão (passo fixo: igual nos dois aparelhos no PvP online).
var _ponto_bomba := Vector2.INF

func _mira_bomba() -> Vector2:
	var dir := _dir()
	var alvo: Unidade = arena.alvo_na_frente(self, (p.alcance if p.alcance > 0 else 100.0) + 70.0)
	var dx := 110.0
	if alvo:
		dx = clampf((alvo.position.x - position.x) * dir, 30.0, 170.0)
	return Vector2(position.x + dir * dx, position.y)

func _soltar_bomba() -> void:
	_ponto_bomba = _mira_bomba()
	var sp: Array = p.extra.get("solta_ponto", [anim.ax + 90.0, anim.ay - 120.0])
	var local := Vector2(float(sp[0]) - anim.ax, float(sp[1]) - anim.ay)
	if flip_h:
		local.x = -local.x
	var de := position + local * scale
	var dur := float(anim.quadros_acao[0] - int(p.extra.get("solta_quadro", 0))) / maxf(anim.fps, 1.0)
	var fogo: Array = p.extra.get("fogo_na_bomba", [48, 0])
	var tex_b: Texture2D = load(str(p.extra.get("bomba_img", ""))) if p.extra.has("bomba_img") else null
	if tex_b:
		arena.lancar_bomba(tex_b, de, _ponto_bomba, dur, scale.x, flip_h, Vector2(float(fogo[0]), float(fogo[1])))

func _explodir_bomba() -> void:
	var bomba: Dictionary = p.extra.get("bomba", {})
	if _ponto_bomba == Vector2.INF:
		_ponto_bomba = _mira_bomba()
	arena.explodir_bomba(self, _ponto_bomba, dano, roundi(float(bomba.get("dano_area", 0)) * Progressao.multiplicador(nivel)),
		float(bomba.get("raio", 90.0)))
	_ponto_bomba = Vector2.INF

# ------------------------------------------------------------------ TRANCO (levou uma explosão)
## Só visual: o desenho é empurrado para longe da explosão e treme, voltando ao lugar (a posição de verdade
## não muda: a casa e a lógica ficam iguais).
var _tranco := 0.0
var _tranco_dir := 1.0
var _offset_base := Vector2.ZERO

func levar_impacto(direcao: float, forca := 1.0) -> void:
	_tranco = maxf(_tranco, forca)
	_tranco_dir = direcao if direcao != 0.0 else 1.0

func _passo_tranco(dt: float) -> void:
	if _tranco <= 0.0:
		return
	_tranco = maxf(0.0, _tranco - dt * 2.6)
	var k := _tranco * _tranco
	var empurra := _tranco_dir * 22.0 * k                # (px da folha: na tela é a metade)
	var treme := sin(Time.get_ticks_msec() * 0.06) * 6.0 * k
	offset = _offset_base + Vector2(empurra + treme, -8.0 * k)   # (o offset é do nó: não vira com o flip_h)

# ------------------------------------------------------------------ ARREMESSO (martelo do Darian)
## A posição de verdade anda (passo fixo, igual nos dois aparelhos); a altura do voo é só o desenho.
var _voo_t := 0.0
var _voo_dur := 0.0
var _voo_de := 0.0
var _voo_para := 0.0
var _voo_dano := 0.0
var _voo_origem: Unidade = null
const VOO_ALTURA := 85.0

## Joga esta unidade "dist" px para o lado "sentido"; ao cair leva "dano_pouso". Quem defende uma casa da grade
## (campanha) não sai do lugar: leva o dano na hora com um tranco forte.
func arremessar(sentido: float, dist: float, dano_pouso: float, origem: Unidade) -> void:
	if morto:
		return
	if col >= 0 and not pvp:
		arena.ferir(self, dano_pouso, origem)
		levar_impacto(sentido, 1.6)
		return
	var lim: Vector2 = arena.limites_arremesso(self)
	_voo_de = position.x
	_voo_para = clampf(position.x + sentido * dist, lim.x, lim.y)
	_voo_dur = 0.25 + absf(_voo_para - _voo_de) / 900.0
	_voo_t = 0.0
	_voo_dano = dano_pouso
	_voo_origem = origem
	z_index = 2

func _passo_voo(dt: float) -> void:
	_voo_t += dt
	var k := clampf(_voo_t / _voo_dur, 0.0, 1.0)
	position.x = lerpf(_voo_de, _voo_para, 1.0 - pow(1.0 - k, 2.0))
	if k >= 1.0:
		_voo_dur = 0.0
		offset = _offset_base
		rotation = 0.0
		z_index = 0
		var fx_ar = arena.get("fx_ar")
		var fx_chao = arena.get("fx_chao")
		if fx_ar:
			fx_ar.pouso(position, 1.0)
		if fx_chao:
			fx_chao.pouso(position, 1.0)
		arena.ferir(self, _voo_dano, _voo_origem if is_instance_valid(_voo_origem) else null, "darian")
		levar_impacto(signf(_voo_para - _voo_de), 1.0)
		Sons.tocar("Esqueleto Tita/som/soco", 0.8)

# ------------------------------------------------------------------ INVOCADO SAINDO DO CHÃO
var _nasce_t := 0.0
var _nasce_dur := 0.0

## Começa enterrado e sobe do chão em "dur" segundos (a parte de baixo fica escondida no chão).
func nascer(dur := 1.0) -> void:
	_nasce_t = 0.0
	_nasce_dur = dur
	_desenho_nascer()

func _desenho_nascer() -> void:
	if anim == null or texture == null:
		return
	if _nasce_dur <= 0.0:
		if _mat and _corte_ativo:
			_mat.set_shader_parameter("corte_v", 2.0)
			offset = _offset_base
			_corte_ativo = false
		return
	var k := clampf(_nasce_t / _nasce_dur, 0.0, 1.0)
	k = 1.0 - pow(1.0 - k, 2.2)                         # sai rápido e assenta devagar
	_garantir_mat()
	var desce := anim.ay * (1.0 - k)
	offset = _offset_base + Vector2(0, desce)
	_mat.set_shader_parameter("corte_v", (region_rect.position.y + anim.ay * k) / float(texture.get_height()))
	_corte_ativo = true

var _corte_ativo := false

func _garantir_mat() -> void:
	if _mat:
		return
	if _shader_mistura == null:
		_shader_mistura = Shader.new()
		_shader_mistura.code = SHADER_MISTURA
	_mat = ShaderMaterial.new()
	_mat.shader = _shader_mistura
	material = _mat

## Desenho do voo (altura em arco e girando para trás). Chamado pelo _process.
func _desenho_voo() -> void:
	if _voo_dur <= 0.0:
		return
	var k := clampf(_voo_t / _voo_dur, 0.0, 1.0)
	var h := VOO_ALTURA * 4.0 * k * (1.0 - k)
	var sc := absf(scale.y) if scale.y != 0.0 else 1.0
	offset = _offset_base + Vector2(0, -h / sc)
	rotation = signf(_voo_para - _voo_de) * 0.5 * sin(PI * k)

## Depois de soltar a flecha o arqueiro SEGURA a pose do disparo (arco erguido, na altura da flecha) enquanto ela
## se afasta, e só então abaixa o arco — a flecha sai alinhada com o arco, como um arqueiro de verdade.
const SEGURA_DISPARO := 0.32
var _segura_disparo := 0.0
var _quadro_disparo := -1

func _segurar_disparo(dt: float) -> bool:
	if _segura_disparo <= 0.0 or estado != "atacar":
		_segura_disparo = 0.0
		return false
	_segura_disparo -= dt
	t -= dt                                           # (a animação não anda enquanto segura)
	_mostrar(_quadro_disparo)
	_mist_prox = -1
	return true

func _atirador(dt: float, passou: PackedInt32Array) -> void:
	var fl: Dictionary = p.extra.get("flecha", {})
	if _segurar_disparo(dt):
		return
	if lado == "heroes":
		# ARQUEIRO (igual ao site): em pé -> ergue o arco (preparar) -> atira -> fica AGACHADO (guarda)
		# enquanto houver inimigo na linha, atirando de novo a cada intervalo. Sem inimigo: abaixa o arco (voltar) e fica em pé.
		var inimigo: bool = _alvo_de_longe(4000.0) != null       # atira assim que o inimigo APARECE na arena (não no escuro)
		if not inimigo and _no_cerco_pvp():
			inimigo = true                                        # PvP: chegou perto do castelo inimigo = atira no CASTELO
		match estado:
			"preparar":
				if t >= anim.duracao() + float(anim.extra.get("segura", 0.0)):
					if inimigo:
						set_anim("atacar")
					else:
						_voltar()
			"atacar":
				if _evento(passou, anim.quadros_acao) >= 0:
					var tipo_flecha: String = fl.get("tipo", "flecha")
					var alvo_flecha: Unidade = null
					if tipo_flecha == "energia":
						alvo_flecha = arena.alvo_na_frente(self, 4000.0)   # laser mira na cabeça do inimigo da frente
						if not inimigo:
							if acabou():
								cd = p.intervalo_ataque
								_guarda()
							return                                    # inimigo sumiu antes do tiro: não dispara no vazio
					arena.disparar(tipo_flecha, self, Vector2(fl.get("saida_x", 50), fl.get("saida_y", -70)), fl.get("velocidade", 600), dano, 0, 0.0, alvo_flecha)
					Sons.do_personagem(p, "tiro")
					if p.extra.has("ponta_flecha"):
						_segura_disparo = SEGURA_DISPARO
						_quadro_disparo = ultimo_q
				if acabou():
					cd = p.intervalo_ataque
					_guarda()
			"guarda":
				if not inimigo:
					_voltar()
				elif cd <= 0.0:
					set_anim("atacar")
			"voltar":                                   # o "preparar" de trás para frente (t já anda sozinho)
				var a := p.anim("preparar")
				var q := a.quadros - 1 - int(t * a.fps)
				if q < 0:
					set_anim("parado")
				else:
					region_rect = a.retangulo(q)
			_:
				if inimigo and cd <= 0.0:
					set_anim("preparar" if p.anims.has("preparar") else "atacar")
		return
	# monstro arqueiro: para quando um herói está ao alcance, ou perto do castelo, e atira
	var alcance := p.alcance if p.alcance > 0 else 360.0
	var alvo: Unidade = _alvo_de_longe(alcance)
	var no_castelo := (atacante and not pvp and position.x <= ConfigArena.G.left + ConfigArena.G.cw * 1.5) or _no_cerco_pvp()
	if estado == "atacar":
		if _evento(passou, anim.quadros_acao) >= 0:
			arena.disparar("flecha_inimiga", self, Vector2(fl.get("saida_x", 45), fl.get("saida_y", -72)), fl.get("velocidade", 520), dano)
			Sons.do_personagem(p, "tiro")
			if p.extra.has("ponta_flecha"):
				_segura_disparo = SEGURA_DISPARO
				_quadro_disparo = ultimo_q
		if acabou():
			cd = p.intervalo_ataque
			set_anim("andar" if atacante else "parado")
			_mostrar(0)
	elif (alvo or no_castelo) and cd <= 0.0:
		set_anim("atacar")
	elif not alvo and not no_castelo:
		_andar(dt)

## Agachado esperando o próximo tiro: último quadro do "atacar", parado.
func _guarda() -> void:
	estado = "guarda"
	_mostrar(anim.quadros - 1)

## Abaixa o arco: toca o "preparar" ao contrário (se não tiver, fica em pé direto).
func _voltar() -> void:
	if not p.anims.has("preparar"):
		set_anim("parado")
		return
	set_anim("preparar")
	estado = "voltar"
	t = 0.0
	region_rect = anim.retangulo(anim.quadros - 1)

func _mago(_dt: float, passou: PackedInt32Array) -> void:
	var mg: Dictionary = p.extra.get("magia", {})
	if estado == "atacar":
		if _evento(passou, anim.quadros_acao) >= 0:
			arena.disparar("magia_fogo" if mg.get("estilo", "") == "fogo" else "magia", self,
				Vector2(mg.get("saida_x", 40), mg.get("saida_y", -80)), mg.get("velocidade", 420), dano,
				roundi(mg.get("dano_area", 0) * Progressao.multiplicador(nivel)), mg.get("raio", 0))
			Sons.do_personagem(p, "magia")
		if acabou():
			cd = p.intervalo_ataque
			set_anim("parado")
	elif cd <= 0.0 and (_alvo_de_longe(4000.0) != null or _no_cerco_pvp()):   # (PvP: no cerco, a magia vai no castelo)
		set_anim("atacar")

## PvP: parado no cerco (2º quadrado antes do castelo inimigo, sem ninguém na frente) — quem atira de longe
## mira na PAREDE do castelo (a flecha / magia voa até lá e acerta).
func _no_cerco_pvp() -> bool:
	return pvp and arena.has_method("no_cerco") and arena.no_cerco(self) and not virado

func _escudo(dt: float, passou: PackedInt32Array) -> void:
	# Alvo/contato: monstro usa a distância do site (encosta antes de bater); herói usa o alcance.
	var contato := ConfigArena.CONTATO_MONSTRO if lado == "monsters" else (p.alcance if p.alcance > 0 else 60.0)
	var alvo2: Unidade = arena.alvo_na_frente(self, contato)
	if lado == "monsters":
		# Esqueleto Protetor (monstro): tanque de linha. Para na frente do inimigo MAIS À FRENTE e segura
		# a posição — não atravessa a pilha. Soca o alvo mais próximo enquanto houver, mas NUNCA anda
		# com inimigo em alcance: é o escudo que segura os vários de uma vez (defendendo reduz dano).
		defendendo = true
		if estado == "atacar":
			if _evento(passou, anim.quadros_acao) >= 0 and alvo2:
				arena.ferir(alvo2, dano, self)
			if _evento(passou, anim.quadros_som) >= 0:
				Sons.do_personagem(p, "ataque")
			if acabou():
				cd = p.intervalo_ataque
				set_anim("parado" if p.anims.has("parado") else "andar")
			return
		if alvo2:                                   # inimigo em alcance: fica firme (não anda)
			if cd <= 0.0 and p.anims.has("atacar"):
				set_anim("atacar")
				return
			scale = _escala_base
			_pose_guarda()                          # segura a linha com o escudo erguido
			return
		scale = _escala_base                       # sem inimigo: volta a marchar/segurar a guarda
		_andar(dt)
		return
	# Protetor G: inimigo na frente = saca a espada e luta (folha "lutando"), continuando com o
	# escudo no braço (segue bloqueando dano). Parado (com ou sem inimigo) = SEMPRE com a espada
	# na mão: folha "parado", feita dos quadros iniciais da folha lutando (a troca não pula).
	# A folha "defender" (só escudo, sem espada) fica só para ficha sem a folha "parado".
	var tr: Dictionary = p.extra.get("trechos", {})
	var bloqueando: bool = arena.alvo_na_frente(self, p.extra.get("alcance_escudo", 210)) != null
	var alvo: Unidade = alvo2
	defendendo = bloqueando
	if estado == "atacar":
		if _evento(passou, anim.quadros_acao) >= 0 and alvo:
			arena.ferir(alvo, dano, self)
		if _evento(passou, anim.quadros_som) >= 0:
			Sons.do_personagem(p, "ataque")
		if acabou():
			cd = p.intervalo_ataque
			trecho = ""
			set_anim("parado" if p.anims.has("parado") else "defender")
		return
	if alvo and cd <= 0.0 and p.anims.has("atacar"):
		trecho = ""
		set_anim("atacar")
		return
	if estado == "andar":                          # marchando: deixa correr
		return
	# PARADO = espada na mão SEMPRE, bloqueando ou não (folha "parado"). O dano continuou sendo
	# bloqueado pelo "defendendo" acima; sem essa folha, ele usa o escudo (folha "defender") abaixo.
	if p.anims.has("parado"):
		if estado != "parado":
			set_anim("parado")
		return
	if tr.is_empty():                              # ficha sem trechos: deixa correr
		return
	if estado != "defender":
		set_anim("defender")
		trecho = "parado"
	var q := ultimo_q + 1                          # quadro atual contando do 1 (como no jogo.js)
	if q >= int(tr.parado[1]):
		_pular_para(int(tr.parado[0]))

func _pular_para(quadro_de_1: int) -> void:
	t = (quadro_de_1 - 1 + 0.01) / anim.fps
	_ultimo_total = quadro_de_1 - 2
	ultimo_q = quadro_de_1 - 2

func _sentinela(_dt: float, passou: PackedInt32Array) -> void:
	var ex := p.extra
	var alcance := p.alcance if p.alcance > 0 else 150.0
	match estado:
		"especial":
			if int(ex.get("quadro_impacto", 49)) in passou:
				arena.onda("terra", self, roundi(ex.get("dano_terra", 90) * Progressao.multiplicador(nivel)), ex.get("velocidade_onda", 650))
				Sons.do_personagem(p, "terra")
			if acabou():
				cd_especial = ex.get("recarga_terra", 6.0)
				set_anim("parado")
		"atacar":
			var qd: Array = ex.get("quadros_defesa", [64, 92])
			defendendo = ultimo_q >= qd[0] and ultimo_q <= qd[1]
			if _evento(passou, anim.quadros_acao) >= 0:
				for alvo in arena.todos_na_frente(self, alcance):
					arena.ferir(alvo, dano, self)
				Sons.do_personagem(p, "golpe")
			if acabou():
				defendendo = false
				cd = p.intervalo_ataque * 0.3
				set_anim("parado")
		_:
			if cd_especial <= 0.0 and p.anims.has("especial") and arena.contar_inimigos_na_linha(self) >= int(ex.get("minimo_para_terra", 4)):
				set_anim("especial")
			elif cd <= 0.0 and arena.alvo_na_frente(self, alcance):
				set_anim("atacar")

func _tita(dt: float, passou: PackedInt32Array) -> void:
	var ex := p.extra
	var alcance := p.alcance if p.alcance > 0 else 120.0
	match estado:
		"especial":
			if _evento(passou, anim.quadros_acao) >= 0:
				arena.onda("ossos", self, roundi(ex.get("dano_ossos", 80) * Progressao.multiplicador(nivel)), ex.get("velocidade_ossos", 600))
				Sons.do_personagem(p, "ossos")
			if acabou():
				cd_especial = ex.get("recarga_ossos", 7.0)
				set_anim("andar")
		"atacar":
			if _evento(passou, anim.quadros_acao) >= 0:
				for alvo in arena.todos_na_frente(self, alcance):
					arena.ferir(alvo, dano, self)
				Sons.do_personagem(p, "golpe")
			if acabou():
				set_anim("andar")
		_:
			if cd_especial <= 0.0 and p.anims.has("especial") and arena.contar_inimigos_na_linha(self) >= int(ex.get("minimo_ossos", 4)):
				set_anim("especial")
			elif arena.alvo_na_frente(self, alcance):
				set_anim("atacar")
			else:
				_andar(dt)

## GOLEM DE OSSOS (liga Ouro):
##  GOLPE 1 ("especial"): crava o fogo no chão (queima quem está colado nele) e depois VARRE o fogo pela linha
##  inteira — uma onda de fogo que corre pelo chão e acerta TODOS os inimigos da linha (no PvP vai até o castelo).
##  GOLPE 2 ("atacar"): o raio de fogo sai para a FRENTE e depois explode para TRÁS — acerta os dois lados.
func _golem(dt: float, passou: PackedInt32Array) -> void:
	var ex := p.extra
	var alcance := p.alcance if p.alcance > 0 else 220.0
	var tras := float(ex.get("alcance_tras", alcance))
	match estado:
		"especial":
			var ev := _evento(passou, anim.quadros_acao)
			if ev >= 0:
				var fogo := float(ex.get("dano_fogo", 110)) * Progressao.multiplicador(nivel)
				if anim.quadros_acao.size() > 1 and ev == anim.quadros_acao[0]:
					for alvo in arena.todos_na_linha(self, alcance * 0.8, 30.0):   # o fogo bate no chão: queima quem está colado
						arena.ferir(alvo, fogo * 0.5, self)
						alvo.levar_impacto(_dir(), 0.7)
					_fogo_no_chao(position + Vector2(_dir() * 75.0, 0.0), 1.0)    # coluna de fogo saindo do chão
				else:
					arena.onda("fogo", self, roundi(fogo), float(ex.get("velocidade_fogo", 520.0)))
					_fogo_no_chao(position + Vector2(_dir() * 120.0, 0.0), 1.15)  # a varrida: o fogo explode e sai correndo
				Sons.do_personagem(p, "fogo")
			if acabou():
				cd_especial = float(ex.get("recarga_fogo", 9.0))
				set_anim("parado")
		"atacar":
			var ev2 := _evento(passou, anim.quadros_acao)
			if ev2 >= 0:
				var para_tras := anim.quadros_acao.size() > 1 and ev2 == anim.quadros_acao[anim.quadros_acao.size() - 1]
				# o raio atravessa a LINHA INTEIRA (frente, e depois para trás), do jeito que se vê na tela
				var lista: Array = arena.todos_na_linha(self, 20.0, 5000.0) if para_tras else arena.todos_na_linha(self, 5000.0, 10.0)
				_raio_visual(para_tras)
				for alvo in lista:
					arena.ferir(alvo, dano, self)
					alvo.levar_impacto(-_dir() if para_tras else _dir(), 0.9)
					arena.explosoes.append([alvo.position + Vector2(0, -50), 46.0, 0.0, Color("fff0a0")])
				Sons.do_personagem(p, "raio")
			if acabou():
				cd = p.intervalo_ataque
				set_anim("parado")
		_:
			var perto: bool = _alvo_de_longe(alcance) != null or not arena.todos_na_linha(self, 0.0, tras).is_empty()
			if cd_especial <= 0.0 and p.anims.has("especial") and arena.contar_inimigos_na_linha(self) >= int(ex.get("minimo_fogo", 2)):
				set_anim("especial")
			elif perto:
				if cd <= 0.0:
					set_anim("atacar")
				else:
					_pose_guarda()
			else:
				_andar(dt)

## GUERREIRO DARIAN (herói, liga Ouro):
##  GOLPE 1 ("especial" = bloqueio): quando vem fogo/ossos/terra pelo chão na linha dele (ou o Golem prepara o fogo),
##  ergue o martelo na frente (do quadro 73 até o último) e SEGURA: a onda para no martelo e não passa.
##  GOLPE 2 ("atacar"): martelada (quadro 28) e o grande golpe (quadro 54) que ARREMESSA os inimigos da frente
##  5 casas para trás; caem e levam o dano forte.
const DARIAN_BLOQUEIO_Q := 72                 # (0..) quadro a partir do qual o martelo está na frente
var _ameaca_t := 0.0

func bloqueando() -> bool:
	return p.comportamento == "darian" and estado == "especial" and ultimo_q >= DARIAN_BLOQUEIO_Q and not morto

## A onda bateu no martelo: efeito do bloqueio (só visual) e um tranquinho para trás.
func bloqueou_onda(tipo: String) -> void:
	var fx_ar = arena.get("fx_ar")
	var fx_chao = arena.get("fx_chao")
	var cor := Color(1.0, 0.55, 0.12) if tipo == "fogo" else (Color(0.95, 0.92, 0.82) if tipo == "ossos" else Color(0.65, 0.5, 0.3))
	if fx_ar:
		fx_ar.bloqueio(position, _dir(), cor)
	if fx_chao:
		fx_chao.bloqueio(position, _dir(), cor)
	levar_impacto(-_dir(), 0.6)
	Sons.do_personagem(p, "bloqueio")
	_ameaca_t = 0.8

func _darian(dt: float, passou: PackedInt32Array) -> void:
	var ex := p.extra
	var alcance := p.alcance if p.alcance > 0 else 120.0
	var ameaca: float = arena.ameaca_no_chao(self)      # distância da onda inimiga que vem (INF = nada)
	if ameaca < INF:
		_ameaca_t = 0.8
	else:
		_ameaca_t = maxf(0.0, _ameaca_t - dt)
	defendendo = bloqueando()
	match estado:
		"especial":
			if _ameaca_t <= 0.0 and acabou():
				set_anim("parado")
			return
		"atacar":
			if ameaca < 600.0 and p.anims.has("especial"):    # fogo vindo: larga o golpe e bloqueia
				set_anim("especial")
				t = float(DARIAN_BLOQUEIO_Q - 14) / anim.fps
				_ultimo_total = DARIAN_BLOQUEIO_Q - 15
				return
			var ev := _evento(passou, anim.quadros_acao)
			if ev >= 0:
				var forte :=anim.quadros_acao.size() > 1 and ev == anim.quadros_acao[anim.quadros_acao.size() - 1]
				var lista: Array = arena.todos_na_frente(self, alcance + 20.0)
				var ponto := position + Vector2(_dir() * 85.0, 0.0)
				var fx_ar = arena.get("fx_ar")
				var fx_chao = arena.get("fx_chao")
				if fx_ar:
					fx_ar.martelada(ponto, _dir(), forte)
				if fx_chao:
					fx_chao.martelada(ponto, _dir(), forte)
				for alvo in lista:
					if forte:
						var pesado: bool = alvo.chefe or alvo.p.vida >= 1400
						var casas := float(ex.get("casas_arremesso", 5)) * (0.4 if pesado else 1.0)
						arena.ferir(alvo, dano * 0.4, self)
						alvo.arremessar(_dir(), casas * ConfigArena.G.cw, dano * float(ex.get("dano_pouso", 2.2)), self)
					else:
						arena.ferir(alvo, dano, self)
						alvo.levar_impacto(_dir(), 0.9)
				Sons.do_personagem(p, "golpe")
			if acabou():
				cd = p.intervalo_ataque
				set_anim("parado")
			return
	# parado / andando
	if _ameaca_t > 0.0 and p.anims.has("especial"):
		set_anim("especial")
		if ameaca < 600.0:                             # a onda já está perto: ergue o martelo rápido
			t = float(DARIAN_BLOQUEIO_Q - 14) / anim.fps
			_ultimo_total = DARIAN_BLOQUEIO_Q - 15
		return
	if arena.alvo_na_frente(self, alcance) != null:
		if cd <= 0.0:
			set_anim("atacar")
		else:
			_pose_guarda()
	else:
		_pose_guarda()                                 # (quem anda é o _passo_pvp / _caminhar)

## GUERREIRA AURA (heroína de suporte, liga Diamante):
##  GOLPE 1 ("especial" = purificação): abre o livro sagrado e, no quadro 60, a LUZ DIVINA cai do céu em cima de
##  TODOS os esqueletos INVOCADOS da arena (os do Esqueleto Mago e do Místico): dano sagrado forte.
##  GOLPE 2 ("atacar" = cura): ergue o cajado e, no quadro 49, CURA os aliados na frente dela. Ela não bate em ninguém.
func _aura_tem_o_que_fazer() -> bool:
	if cd_especial <= 0.0 and not arena.invocados_inimigos(self).is_empty():
		return true
	if cd <= 0.0:
		for a in arena.aliados_na_frente(self, float(p.extra.get("alcance_cura", 560.0))):
			if a.vida < a.vida_max * 0.85:
				return true
	return false

func _aura(_dt: float, passou: PackedInt32Array) -> void:
	var ex := p.extra
	var fx_ar = arena.get("fx_ar")
	var fx_chao = arena.get("fx_chao")
	match estado:
		"especial":
			if _evento(passou, anim.quadros_acao) >= 0:
				var sagrado := float(ex.get("dano_sagrado", 220)) * Progressao.multiplicador(nivel)
				for alvo in arena.invocados_inimigos(self):
					if fx_ar:
						fx_ar.luz_divina(alvo.position)
					if fx_chao:
						fx_chao.luz_divina(alvo.position)
					arena.ferir(alvo, sagrado, self, "", Color("fff2a0"))
				Sons.do_personagem(p, "luz")
			if acabou():
				cd_especial = float(ex.get("recarga_luz", 10.0))
				set_anim("parado")
			return
		"atacar":
			if _evento(passou, anim.quadros_acao) >= 0:
				var cura := float(ex.get("cura", 110)) * Progressao.multiplicador(nivel)
				var sc := absf(scale.y)
				var cajado := position + Vector2(_dir() * 45.0 * sc, -330.0 * sc)
				for a in arena.aliados_na_frente(self, float(ex.get("alcance_cura", 560.0))):
					if a.vida >= a.vida_max:
						continue
					var antes: float = a.vida
					a.vida = minf(float(a.vida_max), a.vida + cura)
					a.mostra_barra = 2.2
					arena._texto(a.position + Vector2(0, -a.anim.ay * a.scale.y - 6), "+%d" % roundi(a.vida - antes), Color("ffe58a"))
					if fx_ar:
						fx_ar.cura(cajado, a.position, true)
					if fx_chao:
						fx_chao.cura(cajado, a.position, true)
				Sons.do_personagem(p, "cura")
			if acabou():
				cd = float(ex.get("recarga_cura", 6.0))
				set_anim("parado")
			return
	if cd_especial <= 0.0 and p.anims.has("especial") and not arena.invocados_inimigos(self).is_empty():
		set_anim("especial")
		return
	if cd <= 0.0:
		for a in arena.aliados_na_frente(self, float(ex.get("alcance_cura", 560.0))):
			if a.vida < a.vida_max * 0.85:
				set_anim("atacar")
				return
	_pose_guarda()

## ESQUELETO MÍSTICO (suporte dos Monsters):
##  GOLPE 1 ("especial" = cura): aponta para a frente (quadro 105) e CURA todos os aliados na frente dele.
##  GOLPE 2 ("atacar" = invocação): abre o portal de fogo e, no quadro 105, chama 3 ESQUELETOS DE FOGO que
##  saem de dentro do chão (na linha dele e nas vizinhas). Ele mesmo não bate em ninguém.
var _meus_invocados: Array = []

func _mistico(dt: float, passou: PackedInt32Array) -> void:
	var ex := p.extra
	var alcance := p.alcance if p.alcance > 0 else 450.0
	var alcance_cura := float(ex.get("alcance_cura", 520.0))
	match estado:
		"especial":
			if _evento(passou, anim.quadros_acao) >= 0:
				var cura := float(ex.get("cura", 120)) * Progressao.multiplicador(nivel)
				var sc := absf(scale.y)
				var mao := position + Vector2(_dir() * 60.0 * sc, -150.0 * sc)
				var fx_ar = arena.get("fx_ar")
				var fx_chao = arena.get("fx_chao")
				for a in arena.aliados_na_frente(self, alcance_cura):
					if a.vida >= a.vida_max:
						continue
					var antes: float = a.vida
					a.vida = minf(float(a.vida_max), a.vida + cura)
					a.mostra_barra = 2.2
					arena._texto(a.position + Vector2(0, -a.anim.ay * a.scale.y - 6), "+%d" % roundi(a.vida - antes), Color("6dffb0"))
					if fx_ar:
						fx_ar.cura(mao, a.position)
					if fx_chao:
						fx_chao.cura(mao, a.position)
				Sons.do_personagem(p, "cura")
			_dedo_de_fogo(passou)                                  # (apontou o dedo curando: também queima o inimigo)
			if acabou():
				cd_especial = float(ex.get("recarga_cura", 7.0))
				set_anim("parado")
			return
		"atacar":
			if _vai_invocar and _evento(passou, anim.quadros_acao) >= 0:
				var novos: Array = arena.invocar(self, str(ex.get("invoca", "esqueletoFogo")), int(ex.get("quantos", 3)), float(ex.get("vida_invocados", 0.6)))
				_meus_invocados.append_array(novos)
				Sons.do_personagem(p, "invocar")
			_dedo_de_fogo(passou)                                  # cada vez que aponta o dedo: raio de fogo
			if acabou():
				if _vai_invocar:
					cd = float(ex.get("recarga_invocar", 16.0))
				_cd_fogo = float(ex.get("recarga_fogo", 1.5))
				_vai_invocar = false
				set_anim("parado")
			return
	_meus_invocados = _meus_invocados.filter(func(m): return is_instance_valid(m) and not m.morto)
	# 1) cura: algum aliado ferido na frente
	if cd_especial <= 0.0 and p.anims.has("especial"):
		for a in arena.aliados_na_frente(self, alcance_cura):
			if a.vida < a.vida_max * 0.8:
				set_anim("especial")
				return
	# 2) invoca: inimigo na linha e os invocados de antes já caíram
	if cd <= 0.0 and _meus_invocados.is_empty() and arena.tem_inimigo_na_linha(self):
		_vai_invocar = true
		set_anim("atacar")
		return
	# 2b) DEDO DE FOGO: inimigo à vista = aponta o dedo e queima (sem invocar)
	if _cd_fogo <= 0.0 and p.extra.has("dano_fogo") and _alvo_de_longe(alcance) != null:
		_vai_invocar = false
		set_anim("atacar")
		return
	# 3) anda até a distância de suporte (fica atrás da linha de frente)
	var para_x := ConfigArena.cel_x(int(ex.get("para_na_coluna", 7)))
	var chegou: bool = not atacante or position.x <= para_x or arena.alvo_na_frente(self, alcance) != null \
		or not arena.aliados_na_frente(self, 160.0).is_empty() and arena.tem_inimigo_na_linha(self)
	if not chegou:
		_andar(dt)
	elif estado != "parado":
		set_anim("parado")
	elif anim.quadros == 1:
		_respirar()

## ESQUELETO MÍSTICO — DEDO DE FOGO: nos quadros em que ele está com o dedo apontado (extra.dedo_quadros)
## sai um raio de fogo da PONTA DO DEDO até o inimigo da frente. O dano chega junto com o fogo (contado aqui,
## no passo fixo: igual nos dois aparelhos); o desenho é o FxDedoFogo.
const FX_DEDO := preload("res://scripts/arena/fx_dedo_fogo.gd")
var _cd_fogo := 0.0
var _vai_invocar := false
var _fogos_dedo: Array = []                # [segundos até chegar, alvo]

func _dedo_de_fogo(passou: PackedInt32Array) -> void:
	var dq: Dictionary = p.extra.get("dedo_quadros", {})
	if not p.extra.has("dano_fogo") or not dq.has(estado):
		return
	if _evento(passou, PackedInt32Array(dq[estado])) < 0:
		return
	var alvo: Unidade = _alvo_de_longe(p.alcance if p.alcance > 0 else 450.0)
	if alvo == null:
		return
	var ponta := _ponta_dedo()
	var fx = FX_DEDO.new()
	fx.de = ponta
	fx.alvo = alvo
	fx.para = alvo.posicao_cabeca()
	fx.dur = clampf(ponta.distance_to(fx.para) / 1500.0, 0.1, 0.35)
	var fx_ar = arena.get("fx_ar")
	fx.fx_ar = fx_ar
	var pai: Node = fx_ar.get_parent() if fx_ar else get_parent()
	pai.add_child(fx)
	_fogos_dedo.append([FX_DEDO.CARGA + fx.dur, alvo])
	Sons.do_personagem(p, "dedo")

## Ponta do dedo agora (no mundo), medida na folha (extra.dedo: px da folha por animação).
func _ponta_dedo() -> Vector2:
	var d: Dictionary = p.extra.get("dedo", {})
	if not d.has(estado) or anim == null:
		return posicao_cabeca()
	var pt: Array = d[estado]
	var local := Vector2(float(pt[0]) - anim.ax, float(pt[1]) - anim.ay) * absf(scale.x)
	if flip_h:
		local.x = -local.x
	return position + local

## (passo fixo) o fogo do dedo chegou: dano + queima + POSSESSÃO no corpo.
func _passo_fogos_dedo(dt: float) -> void:
	var i := _fogos_dedo.size() - 1
	while i >= 0:
		var f: Array = _fogos_dedo[i]
		f[0] -= dt
		if f[0] <= 0.0:
			_fogos_dedo.remove_at(i)
			var alvo = f[1]
			if alvo != null and is_instance_valid(alvo) and not alvo.morto:
				var mult := Progressao.multiplicador(nivel)
				arena.ferir(alvo, float(p.extra.get("dano_fogo", 45)) * mult, self, "", Color("ff9a3a"))
				var qm: Array = p.extra.get("queima", [2.4, 8])
				alvo.queimar(float(qm[0]), float(qm[1]) * mult, p.id)
				alvo.possuir(1.8)
				Sons.do_personagem(p, "fogo")
		i -= 1

# ------------------------------------------------------------------ POSSESSÃO DE FOGO (no corpo de quem é acertado)
## O corpo vira brasa (brilha laranja por dentro, pulsando), "almas" de fogo do próprio corpo sobem e se
## desfazem, e um círculo de runas em chamas gira no chão. Só visual (o dano é a queima).
var possuido := 0.0
var _fx_possessao: Node2D = null
const POSSESSAO := 1.8

func possuir(dur: float) -> void:
	possuido = maxf(possuido, dur)

func _passo_possessao_visual(dt: float) -> void:
	if possuido <= 0.0 and _fx_possessao == null:
		return
	possuido = maxf(0.0, possuido - dt)
	if _fx_possessao == null:
		_fx_possessao = Node2D.new()
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_fx_possessao.material = m
		_fx_possessao.draw.connect(_desenhar_possessao)
		add_child(_fx_possessao)
	var ativo := possuido > 0.0 and not morto
	_fx_possessao.visible = ativo
	if ativo:
		var k := clampf(possuido / 0.5, 0.0, 1.0)            # some devagar no fim
		var tt := Time.get_ticks_msec() / 1000.0
		var pul := 0.5 + 0.5 * sin(tt * 14.0) * sin(tt * 4.3 + 1.0)
		if dor <= 0.0:
			self_modulate = Color.WHITE.lerp(Color(1.0, 0.62 + 0.15 * pul, 0.4), 0.75 * k)
		_fx_possessao.queue_redraw()
	elif dor <= 0.0 and not morto:
		self_modulate = Color.WHITE

func _desenhar_possessao() -> void:
	var n := _fx_possessao
	var tt := Time.get_ticks_msec() / 1000.0
	var k := clampf(possuido / 0.5, 0.0, 1.0)
	var vida_fx := 1.0 - possuido / POSSESSAO                 # 0 = acabou de pegar, 1 = acabando
	# 1) ALMAS DE FOGO: cópias do próprio corpo (o quadro atual) subindo, esticando e se desfazendo
	if texture and region_rect.size.x > 0.0:
		var tam := region_rect.size
		for g in 3:
			var f := fmod(tt * 0.9 + g / 3.0, 1.0)
			var sobe := f * tam.y * 0.45
			var estica := 1.0 + f * 0.25
			var r := Rect2(offset.x - tam.x * 0.5 * estica, offset.y - tam.y * 0.5 * estica - sobe, tam.x * estica, tam.y * estica)
			if flip_h:
				r = Rect2(r.position.x + r.size.x, r.position.y, -r.size.x, r.size.y)
			var a := 0.42 * (1.0 - f) * k
			n.draw_texture_rect_region(texture, r, region_rect, Color(1.0, 0.38 + 0.3 * (1.0 - f), 0.08, a))
		# brilho por dentro do corpo (o próprio quadro somando luz laranja)
		var r0 := Rect2(offset - tam * 0.5, tam)
		if flip_h:
			r0 = Rect2(r0.position.x + tam.x, r0.position.y, -tam.x, tam.y)
		n.draw_texture_rect_region(texture, r0, region_rect, Color(1.0, 0.45, 0.1, (0.35 + 0.2 * sin(tt * 16.0)) * k))
	# 2) CÍRCULO DE RUNAS EM CHAMAS no chão (sem a escala do personagem)
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0 / maxf(absf(scale.x), 0.01), 1.0 / maxf(absf(scale.y), 0.01)))
	var abre := minf(1.0, vida_fx * 6.0)
	var R := 62.0 * abre
	var ach := 0.3
	var giro := tt * 1.6
	var pts := PackedVector2Array()
	for s in 49:
		var ang := s * TAU / 48.0
		pts.append(Vector2(cos(ang) * R, sin(ang) * R * ach))
	n.draw_polyline(pts, Color(1.0, 0.45, 0.08, 0.7 * k), 3.0, true)
	var pts2 := PackedVector2Array()
	for s in 49:
		var ang := s * TAU / 48.0
		pts2.append(Vector2(cos(ang) * R * 0.72, sin(ang) * R * 0.72 * ach))
	n.draw_polyline(pts2, Color(1.0, 0.75, 0.3, 0.5 * k), 1.6, true)
	for s in 8:                                               # runas (traços em brasa girando)
		var ang := giro + s * TAU / 8.0
		var c := Vector2(cos(ang) * R * 0.86, sin(ang) * R * 0.86 * ach)
		var tg := Vector2(-sin(ang), cos(ang) * ach).normalized()
		n.draw_line(c - tg * 6.0, c + tg * 6.0, Color(1.0, 0.85, 0.45, 0.9 * k), 2.0)
		n.draw_line(c + Vector2(0, -5), c + Vector2(0, 3), Color(1.0, 0.6, 0.2, 0.8 * k), 1.6)
	for s in 6:                                               # labaredinhas subindo do círculo
		var ang := -giro * 0.7 + s * TAU / 6.0
		var c2 := Vector2(cos(ang) * R, sin(ang) * R * ach)
		FxExplosao.desenhar_chama(n, c2, tt * 1.4 + s, 0.22 * k * abre, 0.0)
	n.draw_set_transform(Vector2.ZERO)

## Coluna de fogo saindo do chão (só visual): chamas altas + chão rachado em brasa + estouro de terra.
func _fogo_no_chao(ponto: Vector2, esc: float) -> void:
	var fx_ar = arena.get("fx_ar")
	var fx_chao = arena.get("fx_chao")
	if fx_chao:
		fx_chao.erupcao(ponto, esc)
		fx_chao.explodir(ponto, esc * 0.8)
	if fx_ar:
		fx_ar.erupcao(ponto, esc)
		fx_ar.explodir(ponto + Vector2(0, -24), esc * 0.6, ponto.y)

## O raio do Golem desenhado pelo jogo (a folha só mostra o começo dele): sai das mãos e vai até a ponta
## da linha — para a frente e, no 2º estouro, para trás. Só visual.
func _raio_visual(para_tras: bool) -> void:
	var fx_ar = arena.get("fx_ar")
	if fx_ar == null:
		return
	var sc := absf(scale.x)
	var s := -_dir() if para_tras else _dir()
	var ponto: Array = p.extra.get("raio_tras" if para_tras else "raio_frente", [50.0, 180.0])
	var dx := float(ponto[0]) * (0.35 if para_tras else 1.0)       # para trás: sai das costas (o estouro da folha fica atrás)
	var de := position + Vector2(s * dx * sc, -float(ponto[1]) * sc)
	fx_ar.raio(de, arena.ponta_da_linha(self, s), 0.8 if para_tras else 0.6, 1.0)

func _necro(dt: float, passou: PackedInt32Array) -> void:
	var ex := p.extra
	var alcance := p.alcance if p.alcance > 0 else 520.0
	var para_x := ConfigArena.cel_x(int(ex.get("para_na_coluna", 7)))
	var chegou := not atacante or position.x <= para_x or _alvo_de_longe(alcance) != null
	if not chegou:
		_andar(dt)
		return
	if estado == "atacar":
		if _evento(passou, anim.quadros_acao) >= 0:
			arena.disparar("magia_sombra", self, Vector2(ex.get("saida_x", 53), ex.get("saida_y", -59)), ex.get("velocidade_magia", 380), dano)
			Sons.do_personagem(p, "magia")
			tiros += 1
			if tiros % int(ex.get("tiros_para_invocar", 5)) == 0:
				arena.invocar(self, ex.get("invoca", "esqueleto"), int(ex.get("quantos", 3)))
				Sons.do_personagem(p, "invocar")
		if acabou():
			cd = p.intervalo_ataque
			set_anim("parado")
	elif cd <= 0.0 and (_alvo_de_longe(alcance) or (atacante and position.x <= ConfigArena.G.left + ConfigArena.G.cw * 2) or (pvp and position.x <= para_x) or _no_cerco_pvp()):
		set_anim("atacar")
	elif estado != "parado":
		set_anim("parado")

# ------------------------------------------------------------------ dano e morte
## Aplica o dano (já descontando o escudo). Devolve true se morreu agora.
func receber(valor: float) -> bool:
	if morto:
		return false
	if defendendo:
		valor *= 1.0 - p.defesa
		if lado == "heroes" or p.comportamento == "escudo":
			Sons.do_personagem(p, "bloqueio" if p.sons.has("bloqueio") else "escudo")
	vida -= valor
	dor = 0.12
	mostra_barra = 2.2
	if vida <= 0.0:
		morrer()
		return true
	return false

## Nick: +30% de vida enquanto houver esqueleto normal inimigo de pé.
## Ganhou o bônus: o excesso entra na vida atual. Perdeu: corta o excesso (não cura nem machuca).
func bonus_vida_esqueleto(tem: bool) -> void:
	if morto or vida_bonus_ativa == tem:
		return
	var base := float(p.vida_no_nivel(nivel))
	if tem:
		vida_max = roundi(base * 1.3)
		vida = minf(vida + base * 0.3, float(vida_max))
	else:
		vida_max = roundi(base)
		vida = minf(vida, float(vida_max))
	vida_bonus_ativa = tem

func morrer() -> void:
	if _t_impacto > 0.0 and not morto:                 # morreu com a bomba LONGE no ar: ela chega e explode igual
		morto = true
		_impacto_longe()
	if _ponto_bomba != Vector2.INF and not morto:      # Bombardeiro morreu com a bomba no ar: ela explode igual
		var ex_ponto := _ponto_bomba
		morto = true
		var bomba: Dictionary = p.extra.get("bomba", {})
		arena.explodir_bomba(self, ex_ponto, dano, roundi(float(bomba.get("dano_area", 0)) * Progressao.multiplicador(nivel)),
			float(bomba.get("raio", 90.0)))
		_ponto_bomba = Vector2.INF
	z_index = 0
	morto = true
	defendendo = false
	vida = 0.0
	self_modulate = Color.WHITE
	Sons.do_personagem(p, "morrer")
	if p.anims.has("morrer"):
		set_anim("morrer")
	else:
		_fade = FADE_MORTE                  # sem folha de morte: some devagar na última pose
		ocupa_casa = false                  # a casa já fica livre (igual a ele sumir na hora)

## (Bombardeiro) A bomba explode na mão dele quando morre: a explosão do jogo por cima da pintada na folha
## (clarão, bola de fogo, brasas, ossos/terra voando, onda e marca queimada no chão). Só visual.
func _estouro_da_morte() -> void:
	var fx_ar = arena.get("fx_ar")
	var fx_chao = arena.get("fx_chao")
	if fx_ar == null:
		return
	var pt: Array = p.extra.get("morte_ponto", [anim.ax, anim.ay - 120.0])
	var local := Vector2(float(pt[0]) - anim.ax, float(pt[1]) - anim.ay)
	if flip_h:
		local.x = -local.x
	var ponto := position + local * scale
	fx_ar.explodir(ponto, 1.55, position.y)
	if fx_chao:
		fx_chao.explodir(Vector2(ponto.x, position.y), 1.4)
	Sons.tocar("Mago/som/explosao", 0.8)

func _morrendo(passou: PackedInt32Array, dt: float) -> void:
	if anim == null or estado != "morrer":
		if _fade > 0.0:                     # sumidinha suave (Engenheiro: não tem animação de morte)
			_fade = maxf(0.0, _fade - dt)
			self_modulate = Color(1, 1, 1, _fade / FADE_MORTE)
			ocupa_casa = false
			if _fade <= 0.0:
				livre = true
			return
		livre = true
		ocupa_casa = false
		return
	if anim.quadro_chao >= 0 and anim.quadro_chao in passou:
		ocupa_casa = false
	if p.extra.has("morte_estouro") and int(p.extra.morte_estouro) in passou:
		_estouro_da_morte()
	if t >= anim.duracao() + anim.caido:
		ocupa_casa = false
		livre = true
