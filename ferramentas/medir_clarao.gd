extends SceneTree
## Sai em qual quadro da folha "atacando" o clarão do canhão aparece.
## O tiro (quadros_acao) tem de sair NO clarão, não antes dele.
##
## godot --headless --path "C:\Users\danie\Music\HvM Godot2" --script res://ferramentas/medir_clarao.gd

const FOLHA := "res://assets_otimizados/Engenheiro Arcano/atacando_420x338.png"
const COLS := 6
const CW := 420
const CH := 338
## Boca do canhão na célula: saida (95, -113) tela ÷ escala total 0.5 = (190, -226) da âncora (31, 318).
const BX := 221
const BY := 92

func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(FOLHA))
	if img == null:
		print("ERRO: não abriu a folha")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var n := 33
	var clarao := -1.0
	for q in n:
		var col := q % COLS
		var lin := q / COLS
		var luz := 0.0
		var conta := 0
		# zona à frente do cano (o feixe desenhado na arte), com folga
		for y in range(BY - 56, BY + 56, 3):
			for x in range(BX - 30, CW, 3):
				var px: float = col * CW + x
				var py: float = lin * CH + y
				if px >= img.get_width() or py >= img.get_height():
					continue
				var c := img.get_pixel(int(px), int(py))
				var l := (c.r + c.g + c.b) / 3.0 * c.a
				if l > luz:
					luz = l
				if l > 0.85:
					conta += 1
		if clarao < 0.0 and luz > 0.92 and conta > 30:
			clarao = float(q + 1)
		print("quadro %2d: luz_max=%.2f pixels_brilho=%d" % [q + 1, luz, conta])
	print("")
	print("clarao forte comeca no quadro: %s" % (str(int(clarao)) if clarao > 0 else "não achei"))
	quit(0)
