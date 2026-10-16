extends SceneTree
## DIAGNÓSTICO da folha de andar nova do Guerreiro Protetor:
## 1) lista os quadros vazios;
## 2) mostra em que faixa de largura está o topo do desenho (para achar a espada x a cabeça);
## 3) monta duas imagens de comparação em escala de TELA (0.51 x escala, âncora dos pés no
##    mesmo ponto): parado x andar novo x andar antigo — sobreposto e lado a lado.
## RODAR: godot --headless --path "<pasta do projeto>" --script res://ferramentas/diag_andando.gd

const PAR := "res://assets/Guerreiro Protetor/parado/parado.png"
const NOVA := "res://assets_otimizados/Guerreiro Protetor/andando/andando_266x251.png"
const VELHA := "res://assets_otimizados/Guerreiro Protetor/andando/andando_237x244.png"
const DST := "C:/Users/danie/AppData/Local/Temp/opencode/"

const P_ESCALA := 0.51

# célula e âncoras de cada folha (ax/ay/escala como no protetor.tres)
const PAR_CELL := Vector2i(335, 298)
const PAR_ANCHOR := Vector2(153.23, 295.9)
const PAR_ESCALA := 1.0
const NOVA_CELL := Vector2i(266, 251)
const NOVA_ANCHOR := Vector2(140.799017, 247.855128)
const NOVA_ESCALA := 0.979079
const VELHA_CELL := Vector2i(237, 244)
const VELHA_ANCHOR := Vector2(126.90528239202656, 239.56784053156147)
const VELHA_ESCALA := 0.9803921568627451

const COLS_NOVA := 11
const QUADROS_NOVA := 121

func _initialize() -> void:
	var par := _abrir(PAR)
	var nova := _abrir(NOVA)
	if par == null or nova == null:
		quit(1)
		return

	# 1) quadros vazios da folha nova
	var vazios: Array[int] = []
	for i in QUADROS_NOVA:
		var cel := nova.get_region(Rect2i((i % COLS_NOVA) * NOVA_CELL.x, (i / COLS_NOVA) * NOVA_CELL.y,
			NOVA_CELL.x, NOVA_CELL.y))
		if cel.get_used_rect().size.y <= 0:
			vazios.append(i)
	print("quadros vazios na folha nova: %s" % (str(vazios) if not vazios.is_empty() else "nenhum"))

	# 2) topo por faixa de largura (espada de um lado, cabeça do outro)
	_topos("parado q0", par, Rect2i(0, 0, PAR_CELL.x, PAR_CELL.y))
	_topos("andar novo q0", nova, Rect2i(0, 0, NOVA_CELL.x, NOVA_CELL.y))
	_topos("andar novo q60", nova, Rect2i((60 % COLS_NOVA) * NOVA_CELL.x, (60 / COLS_NOVA) * NOVA_CELL.y,
		NOVA_CELL.x, NOVA_CELL.y))

	# 3) comparação em escala de tela
	var pares: Array = [
		["parado", par, Rect2i(0, 0, PAR_CELL.x, PAR_CELL.y), PAR_ANCHOR, PAR_ESCALA],
		["andar novo", nova, Rect2i(0, 0, NOVA_CELL.x, NOVA_CELL.y), NOVA_ANCHOR, NOVA_ESCALA],
	]
	var velha := _abrir(VELHA)
	if velha != null:
		pares.append(["andar antigo", velha, Rect2i(0, 0, VELHA_CELL.x, VELHA_CELL.y), VELHA_ANCHOR, VELHA_ESCALA])
	_lado_a_lado(pares, DST + "cmp_lado.png")
	_sobreposicao(pares.slice(0, 2), DST + "cmp_overlay.png")   # só parado x andar novo (q0)
	var walk60 := Rect2i((60 % COLS_NOVA) * NOVA_CELL.x, (60 / COLS_NOVA) * NOVA_CELL.y,
		NOVA_CELL.x, NOVA_CELL.y)
	_sobreposicao([pares[0], [pares[1][0], pares[1][1], walk60, pares[1][3], pares[1][4]]],
		DST + "cmp_overlay60.png")                              # mesmo teste no meio do passo
	quit(0)

func _abrir(caminho: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(caminho))
	if img == null or img.is_empty():
		push_error("não abriu: " + caminho)
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img

func _topos(rotulo: String, img: Image, cel: Rect2i) -> void:
	var q := img.get_region(cel)
	var u := q.get_used_rect()
	var linhas: Array[String] = []
	var n := 8
	for b in n:
		var x0 := u.position.x + u.size.x * b / n
		var x1 := u.position.x + u.size.x * (b + 1) / n
		var ur := q.get_region(Rect2i(x0, u.position.y, maxi(1, x1 - x0), u.size.y)).get_used_rect()
		var topo := "-"
		if ur.size.y > 0:
			topo = str(u.position.y + ur.position.y)
		linhas.append("[%3d,%3d) topo=%s" % [x0, x1, topo])
	print("%s (desenho %s, chão %d): %s" % [rotulo, str(u), u.end.y, " | ".join(linhas)])

## Prepara as células na escala de tela (0.51 x escala da ficha).
func _tela(pares: Array) -> Array:
	var res: Array = []
	var base_y := 0
	for p in pares:
		var f: float = P_ESCALA * float(p[4])
		var cel: Image = p[1].get_region(p[2])
		cel.resize(int(round(p[2].size.x * f)), int(round(p[2].size.y * f)), Image.INTERPOLATE_LANCZOS)
		res.append([p[0], cel, f, p[3]])
		base_y = maxi(base_y, int(round(float(p[3].y) * f)))
	return [res, base_y]

## Lado a lado na escala de tela, cada âncora no centro da sua coluna, pés na mesma linha.
func _lado_a_lado(pares: Array, caminho: String) -> void:
	var zoom := 3
	var dados := _tela(pares)
	var telas: Array = dados[0]
	var base_y: int = dados[1]
	var pad := 8
	var maior_w := 0
	var maior_h := 0
	for t in telas:
		maior_w = maxi(maior_w, t[1].get_width())
		maior_h = maxi(maior_h, t[1].get_height())
	var A := Vector2i(0, base_y + pad + 4)   # linha dos pés (A.y = onde a âncora cai)
	var W := (maior_w + pad) * telas.size() + pad
	var H := A.y + pad
	var out := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	for i in telas.size():
		var cel: Image = telas[i][1]
		var an: Vector2 = telas[i][3]
		var f: float = telas[i][2]
		var px := pad + i * (maior_w + pad) + (maior_w - cel.get_width()) / 2
		var py := A.y - int(round(an.y * f))
		out.blit_rect(cel, Rect2i(Vector2i.ZERO, cel.get_size()), Vector2i(px, py))
	out.resize(W * zoom, H * zoom, Image.INTERPOLATE_NEAREST)
	out.save_png(caminho)
	print("comparação lado a lado (zoom %dx): %s" % [zoom, caminho])

## Sobreposição: 1º nítido, os outros 50% — se os corpos coincidem, o contorno aparece "dobrado".
func _sobreposicao(pares: Array, caminho: String) -> void:
	var zoom := 3
	var dados := _tela(pares)
	var telas: Array = dados[0]
	var base_y: int = dados[1]
	var pad := 10
	var maior_w := 0
	for t in telas:
		maior_w = maxi(maior_w, t[1].get_width())
	var A := Vector2i(maior_w / 2 + pad, base_y + pad + 4)
	var W := maior_w + pad * 2
	var H := A.y + pad
	var out := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	for i in telas.size():
		var cel: Image = telas[i][1]
		var an: Vector2 = telas[i][3]
		var f: float = telas[i][2]
		var destino := Vector2i(A.x - int(round(an.x * f)), A.y - int(round(an.y * f)))
		if i == 0:
			out.blit_rect(cel, Rect2i(Vector2i.ZERO, cel.get_size()), destino)
		else:
			out.blend_rect(cel, Rect2i(Vector2i.ZERO, cel.get_size()), destino)
	out.resize(W * zoom, H * zoom, Image.INTERPOLATE_NEAREST)
	out.save_png(caminho)
	print("sobreposição (zoom %dx): %s" % [zoom, caminho])
