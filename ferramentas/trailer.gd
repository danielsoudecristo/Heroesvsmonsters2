extends SceneTree
## MODO TRAILER (vídeo da Play Store, ~2 min 10 s). Abre o jogo, espera 30 s (para ajustar a gravação) e passa sozinho por:
##  1. ABERTURA: batalha épica (Heroes, noite de Halloween)
##  2. menu → 3. CAMPEONATO (sala com os 2 lados enchendo e o chat)
##  4. PERSONAGENS evoluindo (Heroes e Monsters) → 5. RANKING (pódio) e TODAS AS LIGAS
##  6. CENÁRIOS: batalhas curtas em todos os fundos (primavera, outono, inverno, dia, Halloween) dos dois lados
##  7. PvP: Heroes x Monsters e Monsters x Heroes (com a arena, o castelo inimigo e o bot jogando)
##  8. FIM: menu dos Monsters.  Tecla R = começar de novo (sem a espera) · ESC = sair.
## Usa um perfil SEPARADO (user://perfil_trailer.cfg), roda sem servidor e devolve o arquivo do campeonato
## no fim: não mexe na sua conta.  Rodar: Trailer.bat  (ou: godot --path . --maximized -s ferramentas/trailer.gd)

var C: GDScript                      # (carregados ao rodar: as configs usam os autoloads)
var P: GDScript
var CAMP_S: GDScript                 # Campeonato (scripts/sistema/campeonato.gd)

var ESPERA := float(OS.get_environment("TRAILER_ESPERA")) if OS.get_environment("TRAILER_ESPERA") != "" else 30.0
var FOTOS := OS.get_environment("TRAILER_FOTOS")      # (teste: pasta onde salvar uma foto a cada 3 s)
var _foto_t := 0.0

const CARTAS_H := ["darian", "aura", "sentinela", "engenheiro", "magoFogo", "mago", "arqueiro", "protetor"]
const CARTAS_M := ["golemOssos", "esqueletoMistico", "esqueletoTita", "esqueletoMago", "esqueletoBombardeiro", "esqueletoArqueiro", "esqueletoFogo", "esqueletoProtetor"]

## Formação de cada lado (linha, coluna, id) — um time completo usando todos os poderes.
const TIME_H := [
	[0, 0, "elara"], [0, 1, "arqueiro"], [0, 2, "engenheiro"], [0, 4, "protetor"],
	[1, 0, "aura"], [1, 2, "magoFogo"], [1, 4, "darian"],
	[2, 0, "elara"], [2, 1, "mago"], [2, 3, "sentinela"], [2, 4, "nick"],
	[3, 0, "aura"], [3, 2, "engenheiro"], [3, 4, "darian"],
	[4, 1, "arqueiro"], [4, 2, "magoFogo"], [4, 4, "protetor"]]
const TIME_M := [
	[0, 0, "esqueletoBlack"], [0, 1, "esqueletoArqueiro"], [0, 2, "esqueletoMago"], [0, 4, "esqueletoProtetor"],
	[1, 0, "esqueletoMistico"], [1, 2, "esqueletoBombardeiro"], [1, 4, "golemOssos"],
	[2, 0, "esqueletoBlack"], [2, 1, "esqueletoMago"], [2, 3, "esqueletoTita"], [2, 4, "esqueletoFogo"],
	[3, 0, "esqueletoMistico"], [3, 2, "esqueletoArqueiro"], [3, 4, "golemOssos"],
	[4, 1, "esqueletoBombardeiro"], [4, 2, "esqueletoMago"], [4, 4, "esqueletoProtetor"]]
## Quem vem atacando (repetido = vem mais vezes).
const ONDA_M := ["esqueleto", "esqueleto", "esqueletoFogo", "esqueletoArqueiro", "esqueletoProtetor", "esqueletoMago",
	"esqueletoTita", "golemOssos", "esqueletoMistico", "esqueletoBombardeiro", "esqueletoBlack", "esqueleto"]
const ONDA_H := ["nick", "nick", "protetor", "arqueiro", "darian", "sentinela", "mago", "magoFogo", "aura", "engenheiro", "nick", "protetor"]

## O ROTEIRO: [tipo, duração, parâmetros]
const ROTEIRO := [
	["batalha", 17.0, {"lado": "heroes", "nivel": 15}],          # abertura: noite de Halloween, tudo explodindo
	["menu", 5.0, {"lado": "heroes"}],
	["campeonato", 10.0, {}],
	["arvore", 21.0, {}],                                        # a árvore: oitavas → quartas → semi → final → CAMPEÃO
	["personagens", 13.0, {}],
	["ranking", 13.0, {}],
	["batalha", 8.0, {"lado": "heroes", "nivel": 5}],             # primavera
	["batalha", 8.0, {"lado": "monsters", "nivel": 17}],          # inverno (castelo dos esqueletos)
	["batalha", 8.0, {"lado": "heroes", "nivel": 9}],             # outono
	["batalha", 8.0, {"lado": "monsters", "nivel": 13}],          # Halloween
	["batalha", 8.0, {"lado": "heroes", "nivel": 17}],            # inverno
	["batalha", 8.0, {"lado": "monsters", "nivel": 3}],           # noite de lua vermelha
	["pvp", 14.0, {"lado": "heroes"}],
	["pvp", 14.0, {"lado": "monsters"}],
	["menu", 6.0, {"lado": "monsters"}],
]

var t := 0.0
var passo := -1                      # -1 = esperando (gravação)
var passo_t := 0.0
var aviso: Label
var feito := {}
var time_atual: Array = []
var onda_atual: Array = []
var lado_bat := ""
var spawn_t := 0.0
var repor_t := 0.0
var defensores: Array = []           # (PvP) [unidade, linha, x, id]
var _r_antes := false
var _cena_velha: Node = null           # a cena que estava antes de trocar (ainda é a atual por um quadro)

func _initialize() -> void:
	randomize()
	C = load("res://scripts/arena/config_arena.gd")
	P = load("res://scripts/pvp/config_pvp.gd")
	CAMP_S = load("res://scripts/sistema/campeonato.gd")
	_guardar_campeonato()
	Perfil.ARQUIVO = "user://perfil_trailer.cfg"
	Perfil.carregar()
	Perfil.nome = "Daniel"
	Perfil.lado = "heroes"
	Perfil.trofeus = 1680                      # liga Diamante (Aura e Místico liberados)
	Perfil.moedas = 48500
	Perfil.dificuldade = "medio"
	Perfil.tutorial_menu = true
	Perfil.tutorial_jogo = true
	Perfil.convidado_ok = true
	Perfil.ja_entrou = true
	for id in ["elara", "nick", "arqueiro", "protetor", "mago", "magoFogo", "sentinela", "engenheiro", "darian", "aura",
			"esqueletoBlack", "esqueleto", "esqueletoFogo", "esqueletoArqueiro", "esqueletoBombardeiro", "esqueletoProtetor",
			"esqueletoMago", "esqueletoTita", "golemOssos", "esqueletoMistico"]:
		Perfil.niveis[id] = 6 + randi() % 5
	Perfil.salvar()
	change_scene_to_file("res://cenas/intro.tscn")
	var cl := CanvasLayer.new()
	cl.layer = 100
	root.add_child.call_deferred(cl)
	aviso = Label.new()
	aviso.position = Vector2(12, 8)
	aviso.add_theme_font_size_override("font_size", 18)
	aviso.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	aviso.add_theme_color_override("font_outline_color", Color.BLACK)
	aviso.add_theme_constant_override("outline_size", 6)
	cl.add_child.call_deferred(aviso)

func _finalize() -> void:
	_devolver_campeonato()

# ------------------------------------------------------------------ o campeonato da pessoa fica intacto
const CAMP := "user://campeonato.cfg"
const CAMP_COPIA := "user://campeonato_antes_do_trailer.cfg"
const CAMP_NADA := "user://campeonato_antes_do_trailer.nada"

func _guardar_campeonato() -> void:
	if FileAccess.file_exists(CAMP_COPIA) or FileAccess.file_exists(CAMP_NADA):
		_devolver_campeonato()                     # (o trailer anterior foi fechado no meio)
	if FileAccess.file_exists(CAMP):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(CAMP), ProjectSettings.globalize_path(CAMP_COPIA))
	else:
		FileAccess.open(CAMP_NADA, FileAccess.WRITE).store_string("sem campeonato")

func _devolver_campeonato() -> void:
	if FileAccess.file_exists(CAMP_COPIA):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(CAMP_COPIA), ProjectSettings.globalize_path(CAMP))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CAMP_COPIA))
	elif FileAccess.file_exists(CAMP_NADA):
		if FileAccess.file_exists(CAMP):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CAMP))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CAMP_NADA))

# ------------------------------------------------------------------ RELÓGIO DO ROTEIRO
func _process(dt: float) -> bool:
	t += dt
	passo_t += dt
	if Input.is_key_pressed(KEY_ESCAPE):
		return true
	var r := Input.is_key_pressed(KEY_R)
	if r and not _r_antes:                          # R: começa de novo (sem a espera)
		_ir(0)
	_r_antes = r
	if FOTOS != "" and passo >= 0:
		_foto_t -= dt
		if _foto_t <= 0.0:
			_foto_t = 3.0
			root.get_texture().get_image().save_png(FOTOS.path_join("tr_%03d.png" % int(t - ESPERA)))
	if passo < 0 and t >= ESPERA - 2.5:
		_ir(int(OS.get_environment("TRAILER_INICIO")) if OS.get_environment("TRAILER_INICIO") != "" else 0, true)   # a abertura já carrega antes (sem a janela das cartas na gravação)
	if aviso:
		aviso.text = "Trailer começa em %d s  (R = começar já)" % ceili(ESPERA - t)
		if t >= ESPERA:
			aviso.queue_free()
			aviso = null
	if passo < 0:
		return false
	if passo >= ROTEIRO.size():
		return false                                # acabou: fica no menu (R = de novo)
	var p: Array = ROTEIRO[passo]
	match p[0]:
		"batalha": _passo_batalha(dt)
		"pvp": _passo_pvp(dt)
		"campeonato": _passo_campeonato(dt)
		"arvore": _passo_arvore()
		"personagens": _passo_personagens()
		"ranking": _passo_ranking()
	if passo_t >= float(p[1]):
		_ir(passo + 1)
	return false

func _ir(n: int, antes := false) -> void:
	if aviso and not antes:
		aviso.queue_free()
		aviso = null
	passo = n
	passo_t = -2.5 if antes else 0.0
	feito = {}
	defensores = []
	_cena_velha = current_scene
	if n >= ROTEIRO.size():
		return
	var p: Array = ROTEIRO[n]
	var par: Dictionary = p[2]
	match p[0]:
		"menu":
			Perfil.lado = par.lado
			Perfil.salvar()
			change_scene_to_file("res://cenas/intro.tscn")
		"personagens", "ranking":
			Perfil.lado = "heroes"
			Perfil.salvar()
			if not (current_scene and "ranking" in current_scene):
				change_scene_to_file("res://cenas/intro.tscn")
		"campeonato":
			Perfil.sala_modo = "campeonato"
			Perfil.lado = "heroes"
			Perfil.salvar()
			change_scene_to_file("res://cenas/sala_entrada.tscn")
		"arvore":
			Perfil.lado = "heroes"
			Perfil.salvar()
			CAMP_S.novo("heroes")                          # campeonato novo, offline, com você numa vaga dos Heroes
			change_scene_to_file("res://cenas/campeonato.tscn")
		"batalha":
			lado_bat = par.lado
			Perfil.lado = lado_bat
			Perfil.salvar()
			time_atual = TIME_H if lado_bat == "heroes" else TIME_M
			onda_atual = ONDA_M if lado_bat == "heroes" else ONDA_H
			change_scene_to_file("res://cenas/campanha.tscn")
		"pvp":
			lado_bat = par.lado
			Perfil.lado = lado_bat
			Perfil.pvp_modo = "normal"
			Perfil.pvp_sala = {}
			Perfil.pvp_adversario = "MaiaGamer" if lado_bat == "heroes" else "ReiDosOssos"
			Perfil.salvar()
			time_atual = TIME_H if lado_bat == "heroes" else TIME_M
			onda_atual = ONDA_M if lado_bat == "heroes" else ONDA_H
			change_scene_to_file("res://cenas/pvp.tscn")

func _cena_com(prop: String) -> Node:
	var c := current_scene
	if c == _cena_velha and _precisa_trocar():
		return null
	return c if c and (prop in c) else null

## (personagens e ranking usam o mesmo menu que já está aberto: não trocam de cena)
func _precisa_trocar() -> bool:
	return passo >= 0 and passo < ROTEIRO.size() and not (ROTEIRO[passo][0] in ["personagens", "ranking"] and _cena_velha and "ranking" in _cena_velha)

# ------------------------------------------------------------------ CAMPEONATO (sala de entrada)
const FALAS := [["Lucas_BR", "bora Heroes, hoje a taça é nossa!", "heroes"], ["ReiDosOssos", "Monsters vai atropelar kkk", "monsters"],
	["Bia_Arqueira", "alguém de Aura aí?", "heroes"], ["NecroLord", "Golem de Ossos na linha do meio, confia", "monsters"],
	["Kaio.Pro", "quem perder paga a revanche", "heroes"], ["DarkSkull", "Místico + esqueletos de fogo = vitória", "monsters"],
	["Lari_Mage", "partiu final!!", "heroes"]]

func _passo_campeonato(_dt: float) -> void:
	var s := _cena_com("gente")
	if s == null:
		return
	if not feito.has("ini"):
		feito["ini"] = true
		s.chat = s.chat.filter(func(m): return not ("conta" in str(m.texto)))
		s._sala_t = 16.0                               # as vagas enchem rápido
		s.falta = 73.0
	if passo_t > 1.6 and not feito.has("lado"):
		feito["lado"] = true
		s._escolher("heroes")
	var k := int((passo_t - 0.8) / 1.1)
	if k >= 0 and k < FALAS.size() and not feito.has("f%d" % k):
		feito["f%d" % k] = true
		var f: Array = FALAS[k]
		s.chat.append({"nome": f[0], "texto": f[1], "lado": f[2], "eu": false, "sis": false, "foto": ""})

# ------------------------------------------------------------------ ÁRVORE DO CAMPEONATO
## Começa mostrando a árvore inteira; depois você vence fase por fase (a câmera vai junto) até a taça.
func _passo_arvore() -> void:
	var tela := _cena_com("_cam_alvo")
	if tela == null:
		return
	if not feito.has("ini"):
		feito["ini"] = true
		tela.sem_faixa = true
		tela.zoom = 0.42                                       # a árvore inteira, os 16 jogadores
		tela._cam_alvo = Vector2(tela.MUNDO.x / 2.0, tela._yc())
		tela.cam = tela._cam_alvo
	var momentos := [3.5, 7.5, 11.5, 15.5]                       # oitavas, quartas, semi, FINAL
	for i in momentos.size():
		if passo_t > momentos[i] and not feito.has("v%d" % i):
			feito["v%d" % i] = true
			CAMP_S.registrar(true)                               # você vence a luta dessa fase
			tela._aviso = CAMP_S.ultimo
			tela._aviso_t = 3.6
			CAMP_S.ultimo = ""
			tela._cam_alvo = tela._foco() if i < momentos.size() - 1 else Vector2(tela.MUNDO.x / 2.0, tela._yc() - 260.0)
	# zoom: abre na árvore toda, aproxima na sua luta e volta para ver o CAMPEÃO com a taça
	var z := 0.42
	if passo_t > 2.2:
		z = 0.7
	if passo_t > 15.5:
		z = 0.8                                                # a taça e o CAMPEÃO de perto
	tela.zoom = lerpf(tela.zoom, z, 0.03)
	if passo_t > 1.6 and not feito.has("foco"):
		feito["foco"] = true
		tela._cam_alvo = tela._foco()
# ------------------------------------------------------------------ PERSONAGENS / RANKING
func _passo_personagens() -> void:
	var it := _cena_com("ranking")
	if it == null:
		return
	var pe: Node = it.personagens
	if not feito.has("pe"):
		feito["pe"] = true
		pe.abrir()
		pe.lado = "heroes"
		pe._montar()
	for k in 3:                                         # evolui 3 heróis, um de cada vez
		if passo_t > 1.4 + k * 1.5 and not feito.has("h%d" % k):
			feito["h%d" % k] = true
			_evoluir_falso(it, pe, ["sentinela", "engenheiro", "magoFogo"][k])
	if passo_t > 6.4 and not feito.has("pm"):
		feito["pm"] = true
		pe.lado = "monsters"
		pe._montar()
	for k in 3:                                         # e 3 monstros
		if passo_t > 7.6 + k * 1.5 and not feito.has("m%d" % k):
			feito["m%d" % k] = true
			_evoluir_falso(it, pe, ["esqueletoTita", "esqueletoMago", "esqueletoBombardeiro"][k])
	if passo_t > 12.6 and not feito.has("fecha"):
		feito["fecha"] = true
		pe.fechar()

func _evoluir_falso(it: Node, pe: Node, id: String) -> void:
	var n := Perfil.nivel_de(id)
	Perfil.niveis[id] = n + 1
	Perfil.moedas -= maxi(0, Progressao.custo_proximo(n))
	pe._pulso[id] = 1.0
	it._trovao()
	var p: Variant = root.get_node("/root/Catalogo").get_p(id)   # (autoload: só existe rodando)
	pe._avisar("%s subiu para o nível %d! Agora tem +%d%% de vida e dano." % [p.nome if p else id, n + 1, pe._pct(n + 1)], true)

func _passo_ranking() -> void:
	var it := _cena_com("ranking")
	if it == null:
		return
	var rk: Node = it.ranking
	if not feito.has("rk"):
		feito["rk"] = true
		_ranking_falso(rk)
		rk.abrir("vitorias")
	if passo_t > 4.0 and not feito.has("lg"):
		feito["lg"] = true
		rk.tipo = "ligas"
		rk._carregar()
		rk._liga_alvo = 0.0
		rk._liga_rol = 0.0
	if feito.has("lg"):                                 # o carrossel passa por TODAS as ligas, da 1ª à última
		var k := clampf((passo_t - 5.0) / 6.5, 0.0, 1.0)
		rk._liga_alvo = rk._liga_max() * (k * k * (3.0 - 2.0 * k))
	if passo_t > 12.6 and not feito.has("fecha"):
		feito["fecha"] = true
		rk.fechar()

func _ranking_falso(rk: Node) -> void:
	var nomes := ["Lucas_BR", "MaiaGamer", "ReiDosOssos", "Kaio.Pro", "Bia_Arqueira", "TitaMaster", "Daniel", "JoaoVictor",
		"NecroLord", "Ana.Clara", "Pedrinho77", "GuerreiroX", "Lari_Mage", "DarkSkull", "Theo_HvM", "Vini.Gameplay", "Duda_Fogo", "Rafa_Tank"]
	var linhas: Array = []
	var v := 412
	for i in nomes.size():
		v -= 9 + randi() % 14
		linhas.append({"posicao": i + 1, "nome": nomes[i], "avatar_url": "", "valor": v, "trofeus": 2600 - i * 70, "eu": nomes[i] == "Daniel"})
	rk._cache["vitorias|dia"] = {"linhas": linhas, "t": Time.get_ticks_msec()}

# ------------------------------------------------------------------ BATALHAS DA CAMPANHA
func _cartas(arena: Node, ids: Array) -> Array:
	var cartas: Array = []
	for id in ids:
		for p in arena.cartas_todas:
			if p.id == id:
				cartas.append(p)
	return cartas

func _passo_batalha(dt: float) -> void:
	var arena := _cena_com("selecao")
	if arena == null or arena.selecao == null or "vidas" in arena:
		return
	if not feito.has("montou"):
		feito["montou"] = true
		arena.selecao.visible = false
		arena.selecao.inicios = []
		arena._cartas_escolhidas(_cartas(arena, CARTAS_H if lado_bat == "heroes" else CARTAS_M))
		arena.comecar_nivel(int(ROTEIRO[passo][2].nivel))
		arena.segurar = true                                  # as ondas são as do trailer
		arena.energia_infinita = true
		spawn_t = 0.3
		repor_t = 0.0
		for f in time_atual:
			arena.criar_unidade(f[2], lado_bat, f[0], f[1], 10)
		var lado_ini := "monsters" if lado_bat == "heroes" else "heroes"
		for i in 7:                                           # já começa com a briga no meio do campo
			var u = arena.criar_unidade(onda_atual[randi() % onda_atual.size()], lado_ini, randi() % 5, -1, 7)
			if u:
				u.position.x = randf_range(820.0, 1180.0)
		return
	arena.vida_castelo = maxf(arena.vida_castelo, 55.0)      # o castelo aguenta o trailer inteiro
	arena.hud.guardado = passo_t > 3.5                      # mostra as cartas no começo e depois a arena inteira
	if arena.estado == "derrota":
		return
	spawn_t -= dt
	var vivos := 0
	for l in arena.monstros:                                  # (monstros = sempre o lado de quem chega)
		for u in l:
			if not u.morto:
				vivos += 1
	if spawn_t <= 0.0 and vivos < 24:
		spawn_t = randf_range(0.3, 0.7)
		arena.criar_unidade(onda_atual[randi() % onda_atual.size()], "monsters" if lado_bat == "heroes" else "heroes", randi() % 5, -1, 7)
	repor_t -= dt
	if repor_t <= 0.0:                                        # quem caiu do time volta (o campo fica sempre cheio)
		repor_t = 2.0
		for f in time_atual:
			var u: Variant = arena.casas[f[1]][f[0]]
			if u == null or not is_instance_valid(u) or u.morto:
				arena.casas[f[1]][f[0]] = null
				arena.criar_unidade(f[2], lado_bat, f[0], f[1], 10)

# ------------------------------------------------------------------ PvP
func _x_pvp(col: int) -> float:
	var x: float = C.cel_x(col)
	return x if lado_bat == "heroes" else P.MW - x            # (a arena dos Monsters é a da direita, espelhada)

func _passo_pvp(dt: float) -> void:
	var arena := _cena_com("vidas")
	if arena == null or arena.selecao == null:
		return
	if not feito.has("cartas"):
		feito["cartas"] = true
		arena.selecao.visible = false
		arena._cartas_escolhidas(_cartas(arena, CARTAS_H if lado_bat == "heroes" else CARTAS_M))
		arena.preparo = 1.0                                   # (sem os 25 s de montar: o trailer já monta)
		return
	if arena.preparo > 0.0:
		return
	var inimigo := "monsters" if lado_bat == "heroes" else "heroes"
	if not feito.has("montou"):
		feito["montou"] = true
		for f in time_atual:
			_defensor_pvp(arena, f)
		spawn_t = 0.2
		for i in 6:
			arena.criar_unidade(onda_atual[randi() % onda_atual.size()], inimigo, randi() % 5, _x_pvp(7) + randf_range(-120, 120), 7)
	for k in arena.vidas:                                     # nenhum castelo cai durante o trailer
		arena.vidas[k] = maxf(arena.vidas[k], P.VIDA_CASTELO * 0.55)
	if passo_t > 3.5:
		arena.hud.guardado = true
	spawn_t -= dt
	if spawn_t <= 0.0:
		spawn_t = randf_range(0.4, 0.9)
		arena.criar_unidade(onda_atual[randi() % onda_atual.size()], inimigo, randi() % 5, _x_pvp(9) + randf_range(0, 60), 7)
	repor_t -= dt
	if repor_t <= 0.0:
		repor_t = 2.0
		for d in defensores:
			if d[0] == null or not is_instance_valid(d[0]) or d[0].morto:
				var nu = arena.criar_unidade(d[3], lado_bat, d[1], d[2], 10)
				if nu:
					nu.guarda = true
					nu.anda = false
				d[0] = nu

func _defensor_pvp(arena: Node, f: Array) -> void:
	var x: float = _x_pvp(f[1])
	var u = arena.criar_unidade(f[2], lado_bat, f[0], x, 10)
	if u:
		u.guarda = true                                       # o seu time segura a linha (fica no lugar)
		u.anda = false
	defensores.append([u, f[0], x, f[2]])
