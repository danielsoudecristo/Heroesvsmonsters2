extends SceneTree
## Contact sheet dos 33 quadros do "atacar" (miniaturas com número), para OLHAR o clarão.
## godot --headless --path "C:\Users\danie\Music\HvM Godot2" --script res://ferramentas/folha_clarao.gd

const FOLHA := "res://assets_otimizados/Engenheiro Arcano/atacando_420x338.png"
const COLS := 6
const CW := 420
const CH := 338
const MINI := 168            # 420 * 0.4
const BORDA := 4

func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(FOLHA))
	if img == null:
		print("ERRO: não abriu")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var n := 33
	var ncols := COLS
	var nrows := int(ceil(float(n) / ncols))
	var saida := Image.create_empty(ncols * (MINI + BORDA) + BORDA, nrows * (MINI + BORDA) + BORDA, false, Image.FORMAT_RGBA8)
	saida.fill(Color(0.12, 0.12, 0.14, 1))
	for q in n:
		var col := q % COLS
		var lin := q / COLS
		var cel := img.get_region(Rect2(col * CW, lin * CH, CW, CH))
		cel.resize(MINI, MINI, Image.INTERPOLATE_BILINEAR)
		var fundo := Image.create_empty(MINI, MINI, false, Image.FORMAT_RGBA8)
		fundo.fill(Color(0.2, 0.22, 0.25, 1))
		fundo.blend_rect(cel, Rect2(0, 0, MINI, MINI), Vector2i.ZERO)
		saida.blit_rect(fundo, Rect2(0, 0, MINI, MINI), Vector2i(BORDA + col * (MINI + BORDA), BORDA + lin * (MINI + BORDA)))
	var caminho := "C:/Users/danie/Music/HvM Godot2/Claude outputs/engenheiro/clarao_quadros.png"
	saida.save_png(caminho)
	print("salvo: " + caminho)
	quit(0)
