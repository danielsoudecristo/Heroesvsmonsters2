extends SceneTree
## PRÉVIA da folha morrendo otimizada: monta quadros 44..67 (a queda e a batida no chão)
## para escolher o quadro_chao. RODAR:
##   godot --headless --path "<pasta do projeto>" --script res://ferramentas/previa_morrendo.gd

const SRC := "res://assets_otimizados/Guerreiro Protetor/morrendo/morrendo_485x306.png"
const COLS := 8
const INI := 44
const FIM := 67                 # inclusivo
const ESCALA := 0.55
const BORDA := 4

func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	if img == null or img.is_empty():
		push_error("não abriu: " + SRC)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var cw := img.get_width() / COLS
	var linhas_totais := 104 / COLS          # folha tem 104 quadros em 8 colunas
	var ch := img.get_height() / linhas_totais
	var linhas := int(ceil(float(FIM - INI + 1) / 6.0))
	var larg := int(cw * ESCALA)
	var alt := int(ch * ESCALA)
	# fundo quadriculado fraco para enxergar a transparência
	var saida := Image.create_empty(6 * (larg + BORDA) + BORDA,
		linhas * (alt + BORDA + 14) + BORDA, false, Image.FORMAT_RGBA8)
	saida.fill(Color(0.16, 0.16, 0.18, 1.0))
	var n := FIM - INI + 1
	for k in n:
		var i := INI + k
		var cel := img.get_region(Rect2i((i % COLS) * cw, (i / COLS) * ch, cw, ch))
		cel.resize(larg, alt, Image.INTERPOLATE_BILINEAR)
		# contorno vermelho na base (linha do chão)
		var bx := BORDA + (k % 6) * (larg + BORDA)
		var by := BORDA + int(k / 6.0) * (alt + BORDA + 14)
		saida.blit_rect(cel, Rect2i(Vector2i.ZERO, cel.get_size()), Vector2i(bx, by))
		for x in larg:
			for yy in range(alt - 3, alt):
				saida.set_pixel(bx + x, by + yy, Color(0.9, 0.2, 0.2))
		# rótulo: número do quadro em branco simples (fonte 5x7 manual)
		_rotulo(saida, bx + 3, by + alt + 2, "%d" % i)
	var saida_nome := "C:/Users/danie/AppData/Local/Temp/opencode/prev_morrer44_67.png"
	var err := saida.save_png(saida_nome)
	print("erro %d" % err if err != OK else "salvo: " + saida_nome)
	quit(0)

## rótulo mínimo 3x5 por dígito (sem fonte: só dígitos e ':')
const GLIFOS := {
	"0": [14, 17, 19, 21, 14], "1": [4, 12, 4, 4, 14], "2": [14, 17, 2, 4, 31],
	"3": [30, 1, 14, 1, 30], "4": [6, 10, 18, 31, 2], "5": [31, 16, 30, 1, 30],
	"6": [14, 16, 30, 17, 14], "7": [31, 1, 2, 4, 8], "8": [14, 17, 14, 17, 14],
	"9": [14, 17, 15, 1, 14],
}

func _rotulo(img: Image, x: int, y: int, texto: String) -> void:
	var cx := x
	for c in texto:
		var g: Array = GLIFOS.get(c, [])
		for gy in 5:
			var linha: int = g[gy] if gy < g.size() else 0
			for gx in 3:
				if linha & (16 >> gx):
					for sy in 2:
						for sx in 2:
							var px := cx + gx * 2 + sx
							var py := y + gy * 2 + sy
							if px < img.get_width() and py < img.get_height():
								img.set_pixel(px, py, Color.WHITE)
		cx += 8
