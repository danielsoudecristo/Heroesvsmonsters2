extends SceneTree
## Ícones da barra das ondas (assets/Jogo/icone_*.png) e dos castelos da barra de vida (assets/Jogo/icone castelo barra de vida/):
## tira o fundo (branco/preto que encosta na borda), recorta só o desenho e salva pequeno (128 px) em
## assets_otimizados/Jogo/. Rodar: godot --headless --path . -s ferramentas/icones_barra.gd

const ENTRA := "res://assets/Jogo/"
const SAI := "res://assets_otimizados/Jogo/"
const TAM := 128

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAI))
	for par in [["icone_monsters", "icone_monsters"], ["icone_guerreiro", "icone_guerreiro"],
			["icone castelo barra de vida/castelo guerreiro", "castelo_heroes"], ["icone castelo barra de vida/castelo monsters", "castelo_monsters"]]:
		var n: String = par[1]
		var img := Image.load_from_file(ProjectSettings.globalize_path(ENTRA + par[0] + ".png"))
		img.convert(Image.FORMAT_RGBA8)
		_tirar_fundo(img)
		var u := img.get_used_rect()
		var lado := maxi(u.size.x, u.size.y)
		var q := Image.create_empty(lado, lado, false, Image.FORMAT_RGBA8)
		q.blit_rect(img, u, Vector2i((lado - u.size.x) / 2, (lado - u.size.y) / 2))
		q.resize(TAM, TAM, Image.INTERPOLATE_LANCZOS)
		q.save_png(ProjectSettings.globalize_path(SAI + n + ".png"))
		print("%s: desenho %s -> %dx%d" % [n, str(u), TAM, TAM])
	quit()

## Fundo = pixels parecidos com a cor do canto, LIGADOS à borda (o branco dos olhos/dentes fica).
func _tirar_fundo(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var fundo := img.get_pixel(2, 2)
	if fundo.a < 0.1:
		return                                         # já é transparente
	var visto := PackedByteArray()
	visto.resize(w * h)
	var pilha := PackedInt32Array()
	for x in w:
		pilha.append(x); pilha.append((h - 1) * w + x)
	for y in h:
		pilha.append(y * w); pilha.append(y * w + w - 1)
	while pilha.size() > 0:
		var k := pilha[pilha.size() - 1]
		pilha.remove_at(pilha.size() - 1)
		if visto[k]:
			continue
		visto[k] = 1
		var px := k % w; var py := k / w
		var c := img.get_pixel(px, py)
		var d := absf(c.r - fundo.r) + absf(c.g - fundo.g) + absf(c.b - fundo.b)
		if d > 0.35:
			continue
		img.set_pixel(px, py, Color(c, clampf((d - 0.12) / 0.23, 0.0, 1.0) * c.a))   # borda suave
		if px > 0: pilha.append(k - 1)
		if px < w - 1: pilha.append(k + 1)
		if py > 0: pilha.append(k - w)
		if py < h - 1: pilha.append(k + w)
