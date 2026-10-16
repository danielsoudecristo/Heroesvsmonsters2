extends SceneTree
## CIRURGIA v9 (final) na folha do Engenheiro.
## O FEIXE LONGO some (x>260; 240-260 com borda suave). O clarão e a casca verde
## ENFRAQUECEM JUNTOS com o tempo e somem até o quadro 13 (0,43s) — na hora em que
## o laser do jogo já voou. O AZUL (armadura, canhão, óculos) nunca é tocado.
##
## Matiz decide quem some com o tempo:
##   VERDE (g > b*1.1)  -> casca/faísca do efeito      ex.: (0.10, 0.72, 0.61)
##   BRANCO/NEUTRO (luma>0.70, b<=g*1.15) -> núcleo do clarão
##   AZUL (b > g*1.15)  -> personagem/canhão           ex.: (0.04, 0.32, 0.76)
##   QUENTE             -> pele/madeira/couro (intocados)
##
## godot --headless --path "C:\Users\danie\Music\HvM Godot2" --script res://ferramentas/limpar_feixe.gd

const FOLHA := "res://assets_otimizados/Engenheiro Arcano/atacando_420x338.png"
const COLS := 6
const CW := 420
const CH := 338
const N := 33
const BX := 221.0
const BY := 92.0

func _init() -> void:
	var caminho := ProjectSettings.globalize_path(FOLHA)
	var img := Image.load_from_file(caminho)
	if img == null:
		print("ERRO: não abriu a folha")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var feixe := 0
	var some_tempo := 0
	for q in N:
		var col := q % COLS
		var lin := q / COLS
		var f := 1.0 if q < 7 else maxf(0.0, 1.0 - float(q - 6) * 0.165)   # some até o quadro 13
		for y in CH:
			for x in CW:
				var c := img.get_pixel(col * CW + x, lin * CH + y)
				if c.a <= 0.02:
					continue
				var luma := (c.r + c.g + c.b) / 3.0 * c.a
				var nova := c.a
				var frio: bool = c.g >= c.r * 0.95 and c.b >= c.r * 0.95
				if frio and x > 260.0:
					nova = 0.0
					feixe += 1
				elif frio and x > 240.0:
					nova = c.a * (1.0 - (x - 240.0) / 20.0)
					feixe += 1
				if f < 1.0 and nova > 0.0 and frio:
					if c.g > c.b * 1.1:
						nova *= f
						some_tempo += 1
					elif luma > 0.40 and c.b <= c.g * 1.15:
						nova *= f
						some_tempo += 1
				if nova != c.a:
					img.set_pixel(col * CW + x, lin * CH + y, Color(c.r, c.g, c.b, nova))
	print("feixe: %d · some com o tempo: %d" % [feixe, some_tempo])
	img.save_png(caminho)
	print("salvo: " + FOLHA)
	quit(0)
