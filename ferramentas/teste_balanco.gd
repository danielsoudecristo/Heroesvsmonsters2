extends Node
## TESTE de sintaxe e números do BALANÇO DA CAMPANHA (energia, preparo, horda, trio).
## RODAR: godot --headless --path "<pasta>" res://ferramentas/teste_balanco.tscn

var falhas := 0

func _ready() -> void:
	for caminho in ["res://scripts/arena/config_arena.gd", "res://scripts/arena/arena.gd",
			"res://scripts/intro/dificuldade.gd", "res://scripts/arena/unidade.gd"]:
		if load(caminho) == null:
			print("  !! erro de sintaxe em " + caminho)
			falhas += 1
		else:
			print("script ok: " + caminho)

	var C := load("res://scripts/arena/config_arena.gd")
	print("")
	# --- dificuldades: campos novos presentes e energia inicial certa
	var esperado_ini := {"facil": 100, "medio": 50, "dificil": 75, "hardcore": 120}
	for id in C.ORDEM_DIFICULDADES:
		var d: Dictionary = C.DIFICULDADES[id]
		var tem := d.has("energia_ini") and d.has("ceu_mult") and d.has("forca") and d.has("horda")
		var ini_ok := int(d.get("energia_ini", -1)) == int(esperado_ini[id])
		_teste("dificuldade %s" % id, tem and ini_ok,
			"energia inicial %d · céu ×%s · inimigos ×%s" % [C.ENERGIA_INICIAL + int(d.energia_ini), str(d.ceu_mult), str(d.forca)])

	# --- tempos da campanha
	var camp: Dictionary = C.CAMPANHA
	_teste("tempos da campanha",
		absf(float(camp.preparo) - 25.0) < 0.01 and absf(float(camp.preparo_nivel1) - 50.0) < 0.01
		and absf(float(camp.pausa_entre_ondas) - 9.0) < 0.01 and camp.has("noite_valor_mult") and camp.has("noite_intervalo_mult"),
		"preparo %ss (nível 1: %ss) · entre ondas %ss · noite ×%s a cada ×%ss" % [
			str(camp.preparo), str(camp.preparo_nivel1), str(camp.pausa_entre_ondas),
			str(camp.noite_valor_mult), str(camp.noite_intervalo_mult)])

	# --- horda crescente com o nível (teto +15%)
	_teste("horda crescente", absf(C.horda_do_nivel(1) - 1.0) < 0.001 and C.horda_do_nivel(15) > 1.08
		and absf(C.horda_do_nivel(20) - 1.15) < 0.001 and absf(C.horda_do_nivel(50) - 1.15) < 0.001,
		"nível 1 ×%s · nível 15 ×%.3f · nível 20+ ×%.2f (teto)" % [
			str(C.horda_do_nivel(1)), C.horda_do_nivel(15), C.horda_do_nivel(20)])

	# --- noite e força dos monstros seguem a conta
	_teste("noite por nível", C.eh_noite(3) and C.eh_noite(4) and not C.eh_noite(1) and not C.eh_noite(2),
		"níveis 3/4 são noite, 1/2 são dia")
	_teste("força dos monstros", C.nivel_monstros(1) == 1 and C.nivel_monstros(15) >= 4 and C.nivel_monstros(99) == 15,
		"nível 1→força 1 · nível 15→%d · nível 99→15 (teto)" % C.nivel_monstros(15))

	# --- fichas do trio (nick, esqueleto, arqueiro) e espelho
	var nick = load("res://dados/personagens/nick.tres")
	var esq = load("res://dados/personagens/esqueleto.tres")
	var arq = load("res://dados/personagens/arqueiro.tres")
	var esqA = load("res://dados/personagens/esqueletoArqueiro.tres")
	_teste("nick vs esqueleto (espelho)", nick.vida == 340 and nick.dano == 35 and esq.vida == 340 and esq.dano == 35,
		"ambos 340 de vida / 35 de dano · nick bate a cada 0,3s (%.0f dps) e ganha +30%% de vida vs esqueleto" % (35.0 / 0.3))
	_teste("arqueiro = caça-esqueleto", arq.dano == 28 and esqA.dano == 28 and arq.vida == 225,
		"28 de dano · ×1.3 vs esqueleto = %.1f por flecha (%.1f dps) · mata um esqueleto em %.1fs" % [
			28.0 * 1.3, 28.0 * 1.3 / 0.8, 340.0 / (28.0 * 1.3 / 0.8)])

	# --- elenco inteiro: 14 fichas com custo/vida/dano e par recíproco
	var ids := ["elara", "nick", "arqueiro", "protetor", "mago", "magoFogo", "sentinela",
		"esqueletoBlack", "esqueleto", "esqueletoFogo", "esqueletoArqueiro", "esqueletoProtetor", "esqueletoMago", "esqueletoTita"]
	var completos := 0
	for id in ids:
		var f = load("res://dados/personagens/%s.tres" % id)
		var ok: bool = f != null and f.custo > 0 and f.vida > 0 and f.comportamento != ""
		if ok and f.par != "":
			var p = load("res://dados/personagens/%s.tres" % f.par)
			ok = p != null and p.par == id
		if ok:
			completos += 1
	_teste("elenco completo (14 fichas)", completos == ids.size(),
		"%d/14 com custo, vida, papel e par recíproco" % completos)

	# --- papéis de destaque (os ajustes de "quero colocar todo mundo")
	var fogo = load("res://dados/personagens/magoFogo.tres")
	var terra_ok: bool = int(fogo.extra.magia.dano_area) == 55 and int(fogo.extra.magia.raio) == 110
	_teste("magoFogo = anti-horda", terra_ok,
		"explosão 55 em raio 110 (era 40/90) · nicho nítido vs o Mago generalista")
	var sents = load("res://dados/personagens/sentinela.tres")
	_teste("sentinela = terra EPICA", int(sents.extra.dano_terra) == 110,
		"onda de terra 110 (era 90) quando 4+ inimigos chegam juntos")
	var tita = load("res://dados/personagens/esqueletoTita.tres")
	_teste("titã = ossos ÉPICOS", int(tita.extra.dano_ossos) == 95,
		"onda de ossos 95 (era 80) — o contraponto monstro da sentinela")
	var fogoM = load("res://dados/personagens/esqueletoFogo.tres")
	_teste("esqueletoFogo = corredor", is_equal_approx(float(fogoM.velocidade), 38.0),
		"velocidade 38 (era 30) — pressão rápida na linha, nicho próprio")

	if falhas > 0:
		print("")
		print("FALHAS: %d" % falhas)
		get_tree().quit(1)
		return
	print("")
	print("TUDO CERTO")
	get_tree().quit(0)

func _teste(nome: String, ok: bool, det: String) -> void:
	if not ok:
		falhas += 1
	print("%-28s -> %s (%s)" % [nome, "ok" if ok else "ERRADO", det])
