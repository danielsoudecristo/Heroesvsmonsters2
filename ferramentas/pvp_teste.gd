extends SceneTree
## PVP DE TESTE (para gravar e conferir todos os personagens): abre direto uma batalha PvP contra o bot,
## com um perfil SEPARADO (não mexe na sua conta) e TODAS as cartas liberadas.
## Uso (pelo PvP_Teste.bat):  PvP_Teste.bat [heroes|monsters] [infinita] [nivel_bot]
##   heroes / monsters = seu lado (padrão heroes)
##   infinita          = energia infinita (para testar todos rápido; sem ela é a partida normal)
##   nivel_bot         = 1 a 10 (padrão 3)

func _initialize() -> void:
	var lado := "heroes"
	var infinita := false
	var nivel := 3
	for a in OS.get_cmdline_user_args():
		if a in ["heroes", "monsters"]:
			lado = a
		elif a == "infinita":
			infinita = true
		elif a.is_valid_int():
			nivel = clampi(int(a), 1, 10)
	Perfil.ARQUIVO = "user://perfil_teste_pvp.cfg"
	Perfil.carregar()
	Perfil.lado = lado
	Perfil.trofeus = 99999                     # todas as ligas: nenhuma carta bloqueada
	Perfil.moedas = maxi(Perfil.moedas, 9999)  # dá para testar o poder vermelho (gasta moedas) à vontade
	Perfil.bot_nivel = nivel
	Perfil.pvp_adversario = ""
	Perfil.pvp_sala = {}
	Perfil.pvp_modo = "normal"
	Perfil.tutorial_jogo = true
	var cena: Node = load("res://cenas/pvp.tscn").instantiate()
	cena.set("energia_infinita", infinita)
	root.add_child(cena)
