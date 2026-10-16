extends SceneTree
## CONTATOS: monta duas folhas de miniaturas (com o número de cada quadro) para conferir
## a ordem real dos quadros da folha do Engenheiro Arcano.
## RODAR: godot --headless --path "<pasta do projeto>" --script res://ferramentas/exportar_engenheiro.gd

const FOLHA := "res://assets/Engenheiro Arcano/Engenheiro Arcano repouso+atirando.png"
const PASTA := "res://Claude outputs/engenheiro"
const COLS := 11
const CW := 1280
const CH := 720
const QUADROS := 118

func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(FOLHA))
	if img == null or img.is_empty():
		push_error("não abriu")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PASTA))
	var font := ThemeDB.fallback_font
	# ---- folha 1: quadros 1..33 (6 cols) ----
	_contato(img, font, 1, 33, 6, 320, 180, "folhaA_tiro_v2")
	# ---- folha 2: quadros 34..118 (10 cols) ----
	_contato(img, font, 34, QUADROS, 10, 192, 108, "folhaB_repouso_v2")
	# ---- folha 3: todos em ordem (11 cols, igual à folha original) ----
	_contato(img, font, 1, QUADROS, 11, 176, 99, "folhaC_tudo_v2")
	print("ok")
	quit(0)

func _contato(img: Image, font: Font, de: int, ate: int, cols: int, cw: int, ch: int, nome: String) -> void:
	var n := ate - de + 1
	var linhas := ceili(float(n) / cols)
	var saida := Image.create_empty(cols * cw, linhas * ch, false, Image.FORMAT_RGBA8)
	saida.fill(Color(0.12, 0.12, 0.15))
	for i in n:
		var q := de + i - 1
		var origem := Rect2i((q % COLS) * CW, int(q / COLS) * CH, CW, CH)
		var cel := img.get_region(origem)
		cel.resize(cw, ch, Image.INTERPOLATE_BILINEAR)
		var dx := (i % cols) * cw
		var dy := int(i / cols) * ch
		saida.blit_rect(cel, Rect2i(0, 0, cw, ch), Vector2i(dx, dy))
		_marcar(saida, font, "%d" % (de + i), Vector2i(dx + 3, dy + 2), Color.WHITE)
	saida.save_png(ProjectSettings.globalize_path(PASTA) + "/%s.png" % nome)
	print("%s.png (%dx%d, quadros %d..%d, %d cols)" % [nome, saida.get_width(), saida.get_height(), de, ate, cols])

func _marcar(destino: Image, _font: Font, txt: String, onde: Vector2i, cor: Color) -> void:
	var esc := 3
	var larg := txt.length() * 6 * esc
	var fundo := Image.create_empty(larg + 6, 7 * esc + 6, false, Image.FORMAT_RGBA8)
	fundo.fill(Color(0, 0, 0, 0.7))
	for i in txt.length():
		var dig: Array = DIGITOS[int(txt.unicode_at(i)) - 48]
		for ly in 7:
			for lx in 5:
				if dig[ly * 5 + lx] == 1:
					fundo.fill_rect(Rect2i(3 + i * 6 * esc + lx * esc, 3 + ly * esc, esc, esc), cor)
	destino.blend_rect(fundo, Rect2i(Vector2i.ZERO, fundo.get_size()), onde)

## 5x7 por dígito ('1' = pixel aceso), na ordem 0..9.
const DIGITOS := [
	[0,1,1,1,0, 1,0,0,0,1, 1,0,0,0,1, 1,0,0,0,1, 1,0,0,0,1, 1,0,0,0,1, 0,1,1,1,0],
	[0,0,1,0,0, 0,1,1,0,0, 0,0,1,0,0, 0,0,1,0,0, 0,0,1,0,0, 0,0,1,0,0, 0,1,1,1,0],
	[0,1,1,1,0, 1,0,0,0,1, 0,0,0,0,1, 0,0,0,1,0, 0,0,1,0,0, 0,1,0,0,0, 1,1,1,1,1],
	[1,1,1,1,1, 0,0,0,1,0, 0,0,1,0,0, 0,0,0,1,0, 0,0,0,0,1, 1,0,0,0,1, 0,1,1,1,0],
	[0,0,0,1,0, 0,0,1,1,0, 0,1,0,1,0, 1,0,0,1,0, 1,1,1,1,1, 0,0,0,1,0, 0,0,0,1,0],
	[1,1,1,1,1, 1,0,0,0,0, 1,1,1,1,0, 0,0,0,0,1, 0,0,0,0,1, 1,0,0,0,1, 0,1,1,1,0],
	[0,0,1,1,1, 0,1,0,0,0, 1,0,0,0,0, 1,1,1,1,0, 1,0,0,0,1, 1,0,0,0,1, 0,1,1,1,0],
	[1,1,1,1,1, 0,0,0,0,1, 0,0,0,1,0, 0,0,1,0,0, 0,1,0,0,0, 0,1,0,0,0, 0,1,0,0,0],
	[0,1,1,1,0, 1,0,0,0,1, 1,0,0,0,1, 0,1,1,1,0, 1,0,0,0,1, 1,0,0,0,1, 0,1,1,1,0],
	[0,1,1,1,0, 1,0,0,0,1, 1,0,0,0,1, 0,1,1,1,1, 0,0,0,0,1, 0,0,0,1,0, 0,1,1,0,0],
]



