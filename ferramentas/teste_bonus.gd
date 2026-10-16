extends Node
## TESTE do bônus de vida do Nick + sintaxe dos arquivos mexidos.
## RODAR: godot --headless --path "<pasta do projeto>" res://ferramentas/teste_bonus.tscn

var falhas := 0

func _ready() -> void:
	for caminho in ["res://scripts/arena/arena.gd", "res://scripts/arena/unidade.gd", "res://scripts/pvp/arena_pvp.gd"]:
		if load(caminho) == null:
			print("  !! erro de sintaxe em " + caminho)
			falhas += 1
		else:
			print("script ok: " + caminho)

	var u: Unidade = preload("res://scripts/arena/unidade.gd").new()
	u.p = load("res://dados/personagens/nick.tres")
	u.nivel = 1
	var base := u.p.vida_no_nivel(1)
	u.vida_max = base
	u.vida = float(base)
	print("")
	print("nick nível 1: vida %d/%d" % [u.vida, u.vida_max])

	u.bonus_vida_esqueleto(true)
	var esperado_max := roundi(base * 1.3)
	var esperado_vida := float(base) + base * 0.3
	_teste("com esqueleto", u.vida_max == esperado_max and absf(u.vida - esperado_vida) < 0.01,
		"vida %.1f/%d (esperado %.1f/%d)" % [u.vida, u.vida_max, esperado_vida, esperado_max])

	u.bonus_vida_esqueleto(true)   # chamou de novo: não muda nada
	_teste("chamou de novo", u.vida_max == esperado_max and absf(u.vida - esperado_vida) < 0.01,
		"vida %.1f/%d" % [u.vida, u.vida_max])

	u.vida = 200.0                 # machucou no meio (com bônus)
	u.bonus_vida_esqueleto(false)  # último esqueleto morreu
	_teste("ferido, esqueleto morreu", u.vida_max == base and absf(u.vida - 200.0) < 0.01,
		"mantém o ganho até passar do teto; vida %.1f/%d" % [u.vida, u.vida_max])

	u.vida = 400.0                 # acima do teto base
	u.bonus_vida_esqueleto(true)   # ganha de novo (corta no teto novo e soma o ganho)
	u.bonus_vida_esqueleto(false)  # perde
	_teste("tinha mais que o teto", u.vida_max == base and absf(u.vida - float(base)) < 0.01,
		"cortou o excesso; vida %.1f/%d" % [u.vida, u.vida_max])

	u.morto = true
	var antes_v := u.vida
	u.bonus_vida_esqueleto(true)
	_teste("morto não muda", absf(u.vida - antes_v) < 0.01 and not u.vida_bonus_ativa,
		"vida %.1f/%d" % [u.vida, u.vida_max])

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
