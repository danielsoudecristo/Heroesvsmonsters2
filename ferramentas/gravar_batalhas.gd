extends SceneTree
## GRAVADOR DE BATALHAS (vídeos para TikTok / redes): cada vídeo é DIFERENTE do anterior.
##  - O DESTAQUE gira sozinho entre todos os personagens (Heroes e Monsters, um de cada vez, salvo em
##    user://gravacoes.cfg): o destaque entra 3 vezes no time e os inimigos são os que fazem a HABILIDADE dele
##    aparecer (Darian contra o fogo do Golem, Aura contra os invocados, Golem contra uma linha cheia...).
##  - Cenário, resto do time, posições e a ordem dos inimigos são sorteados.
##  - Batalha começa vazia, o jogador pega energia (círculo + "+50") e gasta colocando as cartas, até encher.
##  - Ao lado do vídeo sai um .txt com a legenda pronta (lado, destaque, cenário e hashtags).
## Use o Gravar_Batalhas.bat (grava N vídeos seguidos). Sozinho:
##   godot --path . --resolution 1920x1080 --fixed-fps 30 --write-movie videos/x.avi -s ferramentas/gravar_batalhas.gd -- videos/x.avi
## Perfil separado (user://perfil_gravacao.cfg) e sem servidor: não mexe na sua conta.

var CA: GDScript                            ## (carregado ao rodar: a config usa os autoloads)
var duracao := 60.0                         ## segundos de cada vídeo (2º argumento; o .bat intercala 60 e 90)
const HIST := "user://gravacoes.cfg"

## destaque -> [lado, nome no vídeo, o que mostrar, inimigos que fazem a habilidade aparecer]
const DESTAQUES := {
	"darian": ["heroes", "Guerreiro Darian", "bloqueia o fogo do Golem e arremessa os inimigos", ["golemOssos", "golemOssos", "esqueletoTita", "esqueleto", "esqueletoProtetor"]],
	"golemOssos": ["monsters", "Golem de Ossos", "raio para frente e para trás e a parede de fogo", ["nick", "protetor", "arqueiro", "sentinela", "mago", "nick"]],
	"aura": ["heroes", "Guerreira Aura", "luz divina nos invocados e cura dourada", ["esqueletoMistico", "esqueletoMago", "esqueletoMistico", "esqueleto", "esqueletoFogo"]],
	"esqueletoMistico": ["monsters", "Esqueleto Místico", "portal com esqueletos de fogo e cura", ["nick", "protetor", "arqueiro", "mago", "magoFogo"]],
	"sentinela": ["heroes", "Cavaleiro Sentinela", "onda de terra que atravessa a linha", ["esqueleto", "esqueleto", "esqueletoFogo", "esqueletoProtetor", "esqueletoArqueiro"]],
	"esqueletoTita": ["monsters", "Esqueleto Titã", "golpe em área e onda de ossos", ["nick", "nick", "protetor", "arqueiro", "magoFogo"]],
	"engenheiro": ["heroes", "Engenheiro Arcano", "raio elétrico e a sobrecarga em cadeia", ["esqueleto", "esqueletoFogo", "esqueletoArqueiro", "esqueleto", "esqueletoMago"]],
	"esqueletoMago": ["monsters", "Esqueleto Mago", "magia sombria e invocação de esqueletos", ["nick", "arqueiro", "protetor", "mago"]],
	"magoFogo": ["heroes", "Mago de Fogo", "bolas de fogo explosivas", ["esqueleto", "esqueletoProtetor", "esqueletoFogo", "esqueletoTita", "esqueleto"]],
	"esqueletoBombardeiro": ["monsters", "Esqueleto Bombardeiro", "bombas acesas explodindo", ["nick", "protetor", "sentinela", "arqueiro"]],
	"mago": ["heroes", "Mago", "magia de gelo de longe", ["esqueleto", "esqueletoArqueiro", "esqueletoFogo", "esqueletoBombardeiro"]],
	"esqueletoArqueiro": ["monsters", "Esqueleto Arqueiro", "flechas de osso", ["nick", "mago", "magoFogo", "protetor"]],
	"arqueiro": ["heroes", "Arqueiro", "chuva de flechas", ["esqueleto", "esqueletoFogo", "esqueletoMago", "esqueletoArqueiro"]],
	"esqueletoFogo": ["monsters", "Esqueleto de Fogo", "golpes em chamas", ["nick", "protetor", "arqueiro", "mago"]],
	"protetor": ["heroes", "Protetor", "escudo que segura a horda", ["esqueletoTita", "esqueleto", "esqueletoFogo", "esqueletoProtetor"]],
	"esqueletoProtetor": ["monsters", "Esqueleto Protetor", "escudo de osso", ["nick", "arqueiro", "magoFogo", "sentinela"]],
	"nick": ["heroes", "Nick", "espada rápida na linha de frente", ["esqueleto", "esqueletoFogo", "esqueletoArqueiro", "esqueletoMago"]],
}
const ORDEM := ["darian", "golemOssos", "aura", "esqueletoMistico", "sentinela", "esqueletoTita", "engenheiro", "esqueletoMago",
	"magoFogo", "esqueletoBombardeiro", "mago", "esqueletoArqueiro", "arqueiro", "esqueletoFogo", "protetor", "esqueletoProtetor", "nick"]
const OUTROS := {"heroes": ["nick", "arqueiro", "protetor", "mago", "magoFogo", "sentinela", "engenheiro", "darian", "aura"],
	"monsters": ["esqueleto", "esqueletoFogo", "esqueletoArqueiro", "esqueletoProtetor", "esqueletoMago", "esqueletoTita", "esqueletoBombardeiro", "golemOssos", "esqueletoMistico"]}
## nível da campanha -> nome do cenário (o fundo vem do nível)
const CENARIOS := {1: "Dia", 3: "Noite", 5: "Primavera", 9: "Outono", 13: "Halloween", 15: "Halloween (noite)", 17: "Inverno", 21: "Primavera (dia)"}

var qual := 0
var b: Array                                ## [lado, nível, título, time, inimigos] (sorteado)
var destaque := ""
var saida := ""

func _initialize() -> void:
	randomize()
	CA = load("res://scripts/arena/config_arena.gd")
	var a := OS.get_cmdline_user_args()
	saida = a[0] if a.size() > 0 else ""
	if a.size() > 1 and a[1].is_valid_float():
		duracao = clampf(float(a[1]), 20.0, 180.0)
	# o destaque gira: cada vídeo é de um personagem diferente
	var cf := ConfigFile.new()
	cf.load(HIST)
	var i := int(cf.get_value("g", "proximo", 0)) % ORDEM.size()
	cf.set_value("g", "proximo", i + 1)
	cf.save(HIST)
	destaque = OS.get_environment("HVM_DESTAQUE") if OS.get_environment("HVM_DESTAQUE") in DESTAQUES else ORDEM[i]
	b = _sortear(destaque)
	print("Gravando: %s (%d s)" % [b[2], int(duracao)])
	_legenda()
	Perfil.ARQUIVO = "user://perfil_gravacao.cfg"
	Perfil.carregar()
	Perfil.lado = b[0]
	Perfil.dificuldade = "medio"
	Perfil.tutorial_jogo = true
	Perfil.tutorial_menu = true
	Perfil.trofeus = 2000                       # tudo liberado (Aura e Místico são da liga Diamante)
	for id in OUTROS.heroes + OUTROS.monsters + ["elara", "esqueletoBlack"]:
		Perfil.niveis[id] = 8
	Perfil.salvar()
	change_scene_to_file("res://cenas/campanha.tscn")

## Monta a batalha: 2 geradores atrás, o DESTAQUE 3 vezes (linhas espalhadas) e mais 4 personagens sorteados.
func _sortear(d: String) -> Array:
	var info: Array = DESTAQUES[d]
	var lado: String = info[0]
	var gerador := "elara" if lado == "heroes" else "esqueletoBlack"
	var outros: Array = OUTROS[lado].filter(func(x): return x != d)
	outros.shuffle()
	var nivel: int = CENARIOS.keys()[randi() % CENARIOS.size()]
	var casas: Array = []
	for l in 5:
		for col in range(1, 5):
			casas.append([l, col])
	casas.shuffle()
	var time: Array = []
	var gl := [0, 1, 2, 3, 4]
	gl.shuffle()
	time.append([gl[0], 0, gerador])
	time.append([gl[1], 0, gerador])
	var linhas_d := [0, 2, 4] if randf() < 0.5 else [1, 2, 3]
	for l in linhas_d:                                       # o destaque mais à frente, em 3 linhas
		var col := 3 if d in ["darian", "sentinela", "protetor", "nick", "golemOssos", "esqueletoTita", "esqueletoProtetor", "esqueletoFogo"] else 2
		time.append([l, col, d])
		casas = casas.filter(func(x): return not (x[0] == l and x[1] == col))
	for k in 8:                                              # o resto do time (no máximo 4 cartas diferentes)
		var c: Array = casas[k]
		time.append([c[0], c[1], outros[k % 4]])
	var ini: Array = info[3].duplicate()
	var nome_cen: String = CENARIOS[nivel]
	return [lado, nivel, "%s · %s · %s" % [info[1], "Heroes" if lado == "heroes" else "Monsters", nome_cen], time, ini]

## Legenda pronta para o TikTok, ao lado do vídeo (mesmo nome, .txt).
func _legenda() -> void:
	if saida == "":
		return
	var info: Array = DESTAQUES[destaque]
	var txt := "%s em ação! ⚔️\n%s\nCenário: %s\n\n#HeroesVsMonsters #jogomobile #towerdefense #games #%s" % [
		info[1], str(info[2]).left(1).to_upper() + str(info[2]).substr(1), CENARIOS[b[1]], str(info[1]).replace(" ", "").to_lower()]
	var f := FileAccess.open(saida.get_basename() + ".txt", FileAccess.WRITE)
	if f:
		f.store_string(txt)

var t := 0.0
var arena: Node = null
var montou := false
var spawn_t := 0.3
var repor_t := 0.0
var ceu_t := 1.0
var toque_cd := 0.0
var toques: Array = []                # [pos, tempo] dos toques na energia (círculo)
var dedo: Node2D
var fila_time: Array = []            # quem do time ainda vai entrar
var colocados: Array = []
var proxima_t := 0.0
var escolhendo := -1                 # carta selecionada (subindo) antes de colocar
var escolha_t := 0.0
var ultimo_colocado := 0.0

## A BATALHA CRESCE AOS POUCOS, como uma partida de verdade:
##  - a arena começa VAZIA; o time entra UM POR VEZ (a carta sobe e o personagem aparece na casa);
##  - o 1º inimigo chega sozinho; depois vêm mais, cada vez mais rápido, até a arena ficar cheia.
func _process(dt: float) -> bool:
	t += dt
	if arena == null:
		var c := current_scene
		if c == null or not ("selecao" in c) or c.selecao == null:
			return false
		arena = c
	if not montou:
		montou = true
		arena.selecao.visible = false
		arena.selecao.inicios = []
		var ids: Array = []
		for f in b[3]:
			if not ids.has(f[2]) and ids.size() < 7:
				ids.append(f[2])
		var cartas: Array = []
		for id in ids:
			for p in arena.cartas_todas:
				if p.id == id:
					cartas.append(p)
		arena._cartas_escolhidas(cartas)
		arena.comecar_nivel(int(b[1]))
		arena.segurar = true                     # as ondas são as do gravador
		arena.energia_infinita = false              # ENERGIA DE VERDADE: gasta para colocar, ganha pegando do céu
		arena.energia = 350
		dedo = Node2D.new()                         # o "dedo" tocando na energia (círculo que abre)
		dedo.z_index = 60
		dedo.draw.connect(_desenhar_dedo)
		arena.add_child(dedo)
		arena.estado = "onda"                   # (a barra mostra "Onda 1/3", não o preparo; com segurar a campanha não anda sozinha)
		if arena.lbl_fps:
			arena.lbl_fps.visible = false
		# ordem de entrada: primeiro os geradores/suporte de trás, depois a linha de frente
		fila_time = b[3].duplicate()
		fila_time.sort_custom(func(x, y): return _ordem(x) < _ordem(y))   # geradores, o DESTAQUE, depois os baratos
		proxima_t = 1.2
		return false
	arena.lbl_banner.visible = arena.lbl_banner.visible and t < 3.0
	arena.vida_castelo = maxf(arena.vida_castelo, 55.0)   # o castelo aguenta o vídeo inteiro
	_ceu(dt)
	_pegar_energia(dt)
	_colocar_time(dt)
	_inimigos(dt)
	_repor()
	dedo.queue_redraw()
	var foto := OS.get_environment("HVM_FOTO_GRAVACAO")       # (conferir: salva quadros aos 4, 12 e 30 s)
	if foto != "":
		for k in [4.0, 12.0, 30.0]:
			if t >= k and t - dt < k:
				root.get_texture().get_image().save_png(foto.replace(".png", "_%d.png" % int(k)))
	return t >= duracao

## O time entra um por um: a carta sobe (0,55 s) e o personagem aparece na casa — igual ao jogador tocando.
func _colocar_time(dt: float) -> void:
	if fila_time.is_empty():
		if escolhendo < 0 and t > ultimo_colocado + 1.2:
			arena.hud.guardado = true            # todo mundo em campo: guarda as cartas e mostra a arena inteira
		return
	arena.hud.guardado = false
	proxima_t -= dt
	if escolhendo < 0 and fila_time[0][2] != destaque:   # (o DESTAQUE nunca é pulado: espera juntar energia)
		for k in fila_time.size():                    # a 1ª da fila que dá para pagar (a cara espera juntar)
			if arena.energia >= _custo(fila_time[k][2]):
				if fila_time[k][2] != destaque or k == 0:
					fila_time.push_front(fila_time.pop_at(k))
				break
	var f: Array = fila_time[0]
	if escolhendo < 0 and proxima_t <= 0.0 and arena.energia >= _custo(f[2]):
		escolhendo = _carta_de(f[2])
		arena.carta_sel = escolhendo             # a carta sobe (selecionada)
		escolha_t = 0.55
	elif escolhendo >= 0:
		escolha_t -= dt
		if escolha_t <= 0.0:
			arena.recarga.clear()
			arena.carta_sel = escolhendo
			arena.colocar_heroi(Vector2i(f[1], f[0]))   # entra pela mesma função do toque do jogador
			arena.hud.guardado = false
			colocados.append(f)
			fila_time.pop_front()
			escolhendo = -1
			ultimo_colocado = t
			# no começo com calma; depois mais rápido (a pessoa já pegou o ritmo)
			proxima_t = 1.5 if colocados.size() < 4 else (1.0 if colocados.size() < 9 else 0.7)

## Ordem de entrada: geradores primeiro, depois o destaque, depois o resto do mais barato ao mais caro.
func _ordem(f: Array) -> int:
	if f[2] in ["elara", "esqueletoBlack"]:
		return f[0]
	if f[2] == destaque:
		return 100 + f[0]
	return 1000 + _custo(f[2]) * 10 + f[0]

func _custo(id: String) -> int:
	for p in arena.cartas_dados:
		if p.id == id:
			return p.custo
	return 999

func _carta_de(id: String) -> int:
	for k in arena.cartas_dados.size():
		if arena.cartas_dados[k].id == id:
			return k
	return 0

## Inimigos: o 1º chega sozinho; depois o ritmo e o máximo em campo vão subindo até a arena encher.
func _inimigos(dt: float) -> void:
	if t < 3.0 or t > duracao - 2.0:
		return
	var k := clampf((t - 3.0) / 26.0, 0.0, 1.0)              # 0 no começo -> 1 com a arena cheia
	var intervalo := lerpf(4.5, 0.4, k * k)
	var maximo := int(lerpf(1.0, 24.0, k))
	spawn_t -= dt
	var vivos := 0
	for l in arena.monstros:
		for u in l:
			if not u.morto:
				vivos += 1
	if spawn_t <= 0.0 and vivos < maximo:
		spawn_t = intervalo * randf_range(0.8, 1.2)
		var linha := randi() % 5
		if colocados.size() > 0 and k < 0.3:                  # no começo vem na linha de quem já está em campo
			linha = int(colocados[randi() % colocados.size()][0])
		var pesados := ["esqueletoTita", "golemOssos", "darian", "sentinela"]
		var id := _inimigo()
		while k < 0.35 and id in pesados:                      # os grandões só aparecem depois
			id = _inimigo()
		arena.criar_unidade(id, _lado_ini(), linha, -1, 7)

## Quem do time caiu volta para a FILA: é colocado de novo quando der energia (paga de novo, igual ao jogador).
func _repor() -> void:
	if t < repor_t:
		return
	repor_t = t + 1.0
	for f in colocados.duplicate():
		var u: Variant = arena.casas[f[1]][f[0]]
		if u == null or not is_instance_valid(u) or u.morto:
			arena.casas[f[1]][f[0]] = null
			colocados.erase(f)
			fila_time.append(f)

## Energia do céu (o gravador segura a campanha, então ele mesmo solta): cai balançando, como no jogo.
func _ceu(dt: float) -> void:
	ceu_t -= dt
	if ceu_t > 0.0 or t > duracao - 3.0:
		return
	ceu_t = randf_range(1.1, 1.6) if t < 32.0 else randf_range(2.2, 3.0)
	var x := randf_range(CA.G.left + 40, CA.G.left + CA.G.cw * CA.G.cols - 40)
	arena.orbes.append({"pos": Vector2(x, -30), "x0": x, "alvo_y": randf_range(CA.G.top + 40, CA.G.top + CA.G.ch * CA.G.rows - 20),
		"valor": 50 if t < 12.0 else 75, "t": 0.0, "voa": false})   # (depois vale mais: a arena enche)

## O "jogador" toca nas energias que já caíram (do céu e as que a Elara solta): elas voam para o painel.
func _pegar_energia(dt: float) -> void:
	toque_cd -= dt
	for k in toques.size():
		toques[k][1] += dt
	toques = toques.filter(func(x): return x[1] < 0.5)
	if toque_cd > 0.0:
		return
	for o in arena.orbes:
		if o.voa or o.pos.y < CA.G.top + 10.0:          # (toca quando ela já desceu um pouco na arena)
			continue
		if arena.pegar_energia(o.pos):
			toques.append([o.pos, 0.0])
			arena._texto(o.pos + Vector2(0, -36), "+%d" % int(o.valor), Color("ffe14a"))
			toque_cd = 0.3
			return

func _desenhar_dedo() -> void:
	for x in toques:
		var k: float = x[1] / 0.5
		dedo.draw_arc(x[0], 14.0 + 30.0 * k, 0, TAU, 32, Color(1, 1, 1, 0.9 * (1.0 - k)), 4.0, true)
		dedo.draw_circle(x[0], 12.0 * (1.0 - k), Color(1, 1, 1, 0.5 * (1.0 - k)))
func _inimigo() -> String:
	var l: Array = b[4]
	return l[randi() % l.size()]

func _lado_ini() -> String:
	return "monsters" if b[0] == "heroes" else "heroes"
