extends SceneTree
## CRIAR PARADO: monta a folha "parado" do Guerreiro Protetor a partir de UM quadro só
## (o quadro 1 da folha "lutando") e cria a respiração em cima dele: 8 quadros com o corpo
## crescendo/encolhendo ~1,2% na vertical com o pé FIXO no chão (sem balançar a espada).
## O quadro tem o MESMO tamanho (335x298) da folha lutando otimizada que o "atacar" usa,
## então a troca parado -> atacar não pula.
## Depois de rodar, ajustar na ficha: quadros = 8, fps = 10 (0,8 s por respiração).
## RODAR SEM ABRIR O EDITOR:
##   godot --headless --path "<pasta do projeto>" --script res://ferramentas/criar_parado.gd

const SRC := "res://assets/Guerreiro Protetor/lutando/lutando.png"
const DST := "res://assets/Guerreiro Protetor/parado/parado.png"
const PREVIA := "C:/Users/danie/AppData/Local/Temp/opencode/previa_parado_respirando.png"

const COLS_ORIG := 11          # colunas da folha lutando original (8789 / 11 = 799)
const CW_ORIG := 799
const CH_ORIG := 711
const QUADRO_ORIGEM := 0       # quadro 1 da folha lutando (pose de pé com a espada na mão)
const N_QUADROS := 8           # quadros do ciclo de respiração
const AMP := 0.012             # respiração: ±1,2% de altura (~3,6 px no quadro, ~1,8 px na tela)
const NCW := 335               # tamanho de cada quadro da folha nova
const NCH := 298

func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	if img == null or img.is_empty():
		push_error("Não abriu: " + SRC)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	print("folha lutando: %dx%d (grade esperada %dx%d)" % [
		img.get_width(), img.get_height(), COLS_ORIG * CW_ORIG, COLS_ORIG * CH_ORIG])

	var origem := _ret(QUADRO_ORIGEM)
	var cel0 := img.get_region(origem)
	var bb := cel0.get_used_rect()
	if bb.size.y <= 0:
		push_error("quadro de origem vazio")
		quit(1)
		return
	print("quadro %d: conteúdo em %s da célula %dx%d (pé no fundo y=%d)" % [
		QUADRO_ORIGEM + 1, str(bb), CW_ORIG, CH_ORIG, bb.end.y])

	# folha nova: N quadros de NCW x NCH em uma linha, respiração com pé fixo no chão
	var saida := Image.create_empty(N_QUADROS * NCW, NCH, false, Image.FORMAT_RGBA8)
	for i in N_QUADROS:
		var s := sin(TAU * i / N_QUADROS)
		var sy := 1.0 + AMP * s
		var cel := cel0.get_region(Rect2i(Vector2i.ZERO, cel0.get_size()))
		cel.resize(NCW, maxi(1, int(round(float(NCH) * sy))), Image.INTERPOLATE_LANCZOS)
		# alinha pelo FUNDO: o pé continua no chão, só o topo sobe/desce
		saida.blit_rect(cel, Rect2i(Vector2i.ZERO, cel.get_size()),
			Vector2i(i * NCW, NCH - cel.get_height()))

	# prévia dos quadros novos (metade do tamanho)
	var previa := Image.create_empty(int(NCW * 0.5) * N_QUADROS, int(NCH * 0.5), false, Image.FORMAT_RGBA8)
	previa.fill(Color(0.15, 0.15, 0.17, 1.0))
	for i in N_QUADROS:
		var cel := saida.get_region(Rect2i(i * NCW, 0, NCW, NCH))
		cel.resize(int(NCW * 0.5), int(NCH * 0.5), Image.INTERPOLATE_BILINEAR)
		previa.blit_rect(cel, Rect2i(Vector2i.ZERO, cel.get_size()),
			Vector2i(i * int(NCW * 0.5), 0))
	previa.save_png(PREVIA)
	print("prévia salva em " + PREVIA)

	DirAccess.make_dir_recursive_absolute(DST.get_base_dir())
	var err := saida.save_png(ProjectSettings.globalize_path(DST))
	if err != OK:
		push_error("Erro %d ao salvar %s" % [err, DST])
		quit(1)
		return
	print("SALVO: %s = %dx%d (%d quadros de %dx%d, 1 linha)" % [
		DST, saida.get_width(), saida.get_height(), N_QUADROS, NCW, NCH])
	print("--- valores para protetor.tres (anims.parado) ---")
	print("quadros = %d" % N_QUADROS)
	print("fps = 10.0   # 8 quadros a 10 fps = 0,8 s por respiração")
	quit(0)

func _ret(q: int) -> Rect2i:
	return Rect2i((q % COLS_ORIG) * CW_ORIG, (q / COLS_ORIG) * CH_ORIG, CW_ORIG, CH_ORIG)
