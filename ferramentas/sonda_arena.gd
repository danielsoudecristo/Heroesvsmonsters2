extends Node
## SONDA mínima: só abre a arena de campanha e sai. Serve para achar onde trava.
## RODAR: godot --headless --path "<pasta>" res://ferramentas/sonda_arena.gd.tscn

func _ready() -> void:
	print("sonda: comecei")
	AudioServer.set_bus_mute(0, true)
	Perfil.carregar()                           # lê o save (nunca grava)
	Perfil.tutorial_jogo = true                 # só em memória
	print("sonda: perfil ok")
	var cena: PackedScene = load("res://cenas/campanha.tscn")
	print("sonda: cena carregada -> " + str(cena))
	var nó: Node = cena.instantiate()
	print("sonda: instanciada")
	add_child(nó)
	print("sonda: no ar, estado=%s cartas=%d" % [str(nó.estado), nó.cartas_dados.size()])
	await get_tree().process_frame
	await get_tree().process_frame
	print("sonda: dois quadros ok")
	get_tree().quit(0)
