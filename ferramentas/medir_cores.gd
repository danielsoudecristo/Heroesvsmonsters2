extends SceneTree
## Mede as cores das partes que NÃO podem ser apagadas (óculos, botas, capa)
## e as do feixe, para calibrar a máscara da cirurgia.
##
## godot --headless --path "C:\Users\danie\Music\HvM Godot2" --script res://ferramentas/medir_cores.gd

const FOLHA := "res://assets_otimizados/Engenheiro Arcano/atacando_420x338.png"
const COLS := 6
const CW := 420
const CH := 338

func _zona(img: Image, q: int, x0: int, y0: int, x1: int, y1: int, nome: String) -> void:
	var col := q % COLS
	var lin := q / COLS
	var vivos := []
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := img.get_pixel(col * CW + x, lin * CH + y)
			if c.a > 0.5:
				vivos.append(c)
	if vivos.is_empty():
		print("%s: vazio" % nome)
		return
	vivos.sort_custom(func(a, b): return (a.r + a.g + a.b) > (b.r + b.g + b.b))
	var brilho := 0.0
	for cc in vivos:
		var cor: Color = cc
		brilho = maxf(brilho, (cor.r + cor.g + cor.b) / 3.0)
	var meio: Color = vivos[mini(vivos.size() / 2, vivos.size() - 1)]
	var top3 := PackedStringArray()
	for i in mini(3, vivos.size()):
		var c: Color = vivos[i]
		top3.append("(%.2f,%.2f,%.2f,a%.2f)" % [c.r, c.g, c.b, c.a])
	print("%s: n=%d luma_max=%.2f medio=(%.2f,%.2f,%.2f) top=%s" % [nome, vivos.size(), brilho, meio.r, meio.g, meio.b, " ".join(top3)])

func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(FOLHA))
	if img == null:
		print("ERRO: não abriu")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	_zona(img, 0, 130, 60, 195, 110, "quadro1 oculos/cabeca")
	_zona(img, 0, 240, 230, 320, 338, "quadro1 bota dianteira")
	_zona(img, 0, 60, 120, 140, 240, "quadro1 capa azul")
	_zona(img, 8, 180, 40, 240, 150, "quadro9 clarao (dentro do raio)")
	_zona(img, 8, 250, 60, 420, 130, "quadro9 feixe (fora, tem de sumir)")
	_zona(img, 4, 150, 30, 220, 160, "quadro5 clarao esquerda sobre personagem")
	_zona(img, 29, 240, 180, 340, 338, "quadro30 canhao baixado x>240")
	_zona(img, 29, 195, 60, 240, 200, "quadro30 canhao baixado x195-240")
	quit(0)
