extends SceneTree
## PRÉVIA da troca na morte: parado quadro 0 x morrendo quadro 0/44/70 em escala de tela,
## cada um posicionado pela ÂNCORA (ax/ay da ficha) no mesmo ponto, com a linha da âncora
## em vermelho — dá para ver se os pés pulam e se o corpo cai na linha do chão.
## RODAR: godot --headless --path "<pasta do projeto>" --script res://ferramentas/previa_troca.gd

const PAR := "res://assets/Guerreiro Protetor/parado/parado.png"
const MOR := "res://assets_otimizados/Guerreiro Protetor/morrendo/morrendo_485x306.png"
const ESCALA := 0.51                       # escala do personagem na ficha
const PAR_CEL := Vector2i(335, 298)
const PAR_ANC := Vector2(153.23, 295.9)
const MOR_CEL := Vector2i(485, 306)
const MOR_ANC := Vector2(237.799017, 303.855128)

func _initialize() -> void:
	var par := _abrir(PAR)
	var mor := _abrir(MOR)
	if par == null or mor == null:
		quit(1)
		return
	var itens: Array = [
		[par, 0, PAR_CEL, Vector2i.ZERO, PAR_ANC],
		[mor, 0, MOR_CEL, Vector2i.ZERO, MOR_ANC],
		[mor, 44, MOR_CEL, Vector2i.ZERO, MOR_ANC],
		[mor, 70, MOR_CEL, Vector2i.ZERO, MOR_ANC],
	]
	var cel_esc := [
		Vector2i(int(PAR_CEL.x * ESCALA), int(PAR_CEL.y * ESCALA)),
		Vector2i(int(MOR_CEL.x * ESCALA), int(MOR_CEL.y * ESCALA)),
		Vector2i(int(MOR_CEL.x * ESCALA), int(MOR_CEL.y * ESCALA)),
		Vector2i(int(MOR_CEL.x * ESCALA), int(MOR_CEL.y * ESCALA)),
	]
	var larg := 0
	for c in cel_esc:
		larg = maxi(larg, c.x)
	var altura := 0
	for c in cel_esc:
		altura = maxi(altura, c.y)
	var base_y := 200                        # ponto da âncora em todas as colunas
	var saida := Image.create_empty(4 * (larg + 12) + 12, base_y + altura + 12, false, Image.FORMAT_RGBA8)
	saida.fill(Color(0.13, 0.13, 0.15, 1.0))
	for k in itens.size():
		var fonte: Image = itens[k][0]
		var quadro: int = itens[k][1]
		var cel: Vector2i = itens[k][2]
		var anc: Vector2 = itens[k][4]
		var reg := fonte.get_region(Rect2i(Vector2i((quadro % 8) * cel.x, (quadro / 8) * cel.y), cel))
		reg.resize(int(cel.x * ESCALA), int(cel.y * ESCALA), Image.INTERPOLATE_LANCZOS)
		var bx := 12 + k * (larg + 12) + (larg - reg.get_width()) / 2
		var by := base_y - int(anc.y * ESCALA)
		saida.blit_rect(reg, Rect2i(Vector2i.ZERO, reg.get_size()), Vector2i(bx, by))
		# linha da âncora (chão de referência) atravessa tudo
		for x in saida.get_width():
			saida.set_pixel(x, base_y, Color(0.9, 0.25, 0.2))
			if base_y + 1 < saida.get_height():
				saida.set_pixel(x, base_y + 1, Color(0.5, 0.12, 0.1))
	var nome := "C:/Users/danie/AppData/Local/Temp/opencode/prev_troca_morte.png"
	print("salvo: " + nome if saida.save_png(nome) == OK else "erro ao salvar")
	quit(0)

func _abrir(caminho: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(caminho))
	if img == null or img.is_empty():
		push_error("não abriu: " + caminho)
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img
