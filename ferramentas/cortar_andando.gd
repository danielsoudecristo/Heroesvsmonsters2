extends SceneTree
## CORTAR ANDANDO (genérico): uma folha grande de andar (quadros de 1280x720) vira uma folha leve para o
## jogo: cada quadro alinhado pela CABEÇA (x) e pelo CHÃO (y), encolhido para a altura pedida na tela, e
## diz a velocidade que casa o pé com o chão a 18 fps (o mesmo fps de todos os que andam).
## RODAR:
##   godot --headless --path . --script res://ferramentas/cortar_andando.gd -- origem="res://assets/X/andando.png" pasta="res://assets_otimizados/X" cols=11 quadros=120 altura=115
## altura = altura do desenho na TELA (px). A folha sai com 2 px por px da tela (p.escala x a.escala = 0,5).

const CEL := Vector2i(1280, 720)
const LIMITE := 4096
const PAD := 10
const FPS_ANDAR := 18.0
const ESCALA_TELA := 0.5

func _initialize() -> void:
	var a := {}
	for x in OS.get_cmdline_user_args():
		var kv := x.split("=", true, 1)
		if kv.size() == 2:
			a[kv[0]] = kv[1].trim_prefix("\"").trim_suffix("\"")
	var origem: String = a.get("origem", "")
	var pasta: String = a.get("pasta", "")
	var cols_g := int(a.get("cols", "11"))
	var n_q := int(a.get("quadros", "0"))
	var altura_tela := float(a.get("altura", "115"))
	var img := Image.load_from_file(ProjectSettings.globalize_path(origem))
	if img == null or img.is_empty():
		push_error("não abriu " + origem)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var med: Array = []
	var alturas: Array[float] = []
	for n in n_q:
		var reg := Rect2i((n % cols_g) * CEL.x + 2, (n / cols_g) * CEL.y + 2, CEL.x - 4, CEL.y - 4)
		var q := img.get_region(reg)
		var u := q.get_used_rect()
		if u.size.y <= 0:
			push_error("quadro %d vazio" % (n + 1))
			quit(1)
			return
		med.append({"reg": reg, "u": u, "cab": _meio_x(q, u.position.y, maxi(4, int(u.size.y * 0.10))), "chao": u.end.y})
		alturas.append(float(u.size.y))
	var fator := altura_tela / ESCALA_TELA / _mediana(alturas)
	var x0 := 1 << 30; var y0 := 1 << 30; var x1 := -(1 << 30); var y1 := -(1 << 30)
	for m in med:
		var u: Rect2i = m.u
		x0 = mini(x0, u.position.x - int(m.cab)); x1 = maxi(x1, u.end.x - int(m.cab))
		y0 = mini(y0, u.position.y - int(m.chao)); y1 = maxi(y1, u.end.y - int(m.chao))
	x0 -= PAD; y0 -= PAD; x1 += PAD; y1 += PAD
	var cw := roundi((x1 - x0) * fator)
	var ch := roundi((y1 - y0) * fator)
	var cols := mini(int(LIMITE / cw), n_q)
	var linhas := ceili(float(n_q) / cols)
	if linhas * ch > LIMITE:
		push_error("folha ficaria %dx%d" % [cols * cw, linhas * ch])
		quit(1)
		return
	var saida := Image.create_empty(cols * cw, linhas * ch, false, Image.FORMAT_RGBA8)
	var pes: Array[float] = []
	var abertura: Array[float] = []
	for n in n_q:
		var m: Dictionary = med[n]
		var u: Rect2i = m.u
		var q := img.get_region(Rect2i(m.reg.position + u.position, u.size))
		q.resize(maxi(1, roundi(u.size.x * fator)), maxi(1, roundi(u.size.y * fator)), Image.INTERPOLATE_LANCZOS)
		var destino := Vector2i(roundi((u.position.x - m.cab - x0) * fator), roundi((u.position.y - m.chao - y0) * fator))
		saida.blit_rect(q, Rect2i(Vector2i.ZERO, q.get_size()), destino + Vector2i((n % cols) * cw, (n / cols) * ch))
		var cel := img.get_region(m.reg)
		var fp := _meio_x(cel, int(m.chao) - 24, 24)
		if fp >= 0.0:
			pes.append(fp - m.cab)
		abertura.append(float(cel.get_region(Rect2i(0, int(m.chao) - 40, cel.get_width(), 40)).get_used_rect().size.x))
	# passo: picos da abertura das pernas (cada pico = um passo)
	var s: Array[float] = []
	for i in abertura.size():
		s.append((abertura[maxi(0, i - 1)] + abertura[i] * 2.0 + abertura[mini(abertura.size() - 1, i + 1)]) / 4.0)
	var lo: float = s.min()
	var hi: float = s.max()
	var corte: float = lo + (hi - lo) * 0.6
	var corte_b: float = lo + (hi - lo) * 0.35
	var picos: Array[int] = []; var vp: Array[float] = []; var vv: Array[float] = []
	var i := 0
	while i < s.size():
		if s[i] >= corte:
			var j := i; var mx := i
			while j < s.size() and s[j] >= corte_b:
				if s[j] > s[mx]: mx = j
				j += 1
			picos.append(mx); vp.append(abertura[mx]); i = j
		else:
			if s[i] <= corte_b:
				vv.append(abertura[i])
			i += 1
	var por_passo := float(picos[-1] - picos[0]) / (picos.size() - 1) if picos.size() > 1 else float(n_q) / 2.0
	var passo := (_mediana(vp) - _mediana(vv)) / por_passo
	var passo_tela := passo * fator * ESCALA_TELA
	var caminho := "%s/andando_%dx%d.png" % [pasta, cw, ch]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(pasta))
	saida.save_png(ProjectSettings.globalize_path(caminho))
	print("SALVO: %s = %dx%d (%d quadros de %dx%d, %d colunas)" % [caminho, saida.get_width(), saida.get_height(), n_q, cw, ch, cols])
	print("passos no loop: %d (%.1f quadros/passo) -> pé %.2f px/quadro na tela -> velocidade casada a %.0f fps: %.0f px/s" % [
		picos.size(), por_passo, passo_tela, FPS_ANDAR, passo_tela * FPS_ANDAR])
	print("cols = %d\nquadros = %d\ncw = %d\nch = %d\nax = %.1f\nay = %.1f" % [cols, n_q, cw, ch, (_mediana(pes) - x0) * fator, float(-y0) * fator])
	quit(0)

static func _meio_x(q: Image, yy: int, h: int) -> float:
	yy = clampi(yy, 0, q.get_height() - 1)
	h = clampi(h, 1, q.get_height() - yy)
	var u := q.get_region(Rect2i(0, yy, q.get_width(), h)).get_used_rect()
	if u.size.x <= 0:
		return -1.0
	return u.position.x + u.size.x / 2.0

static func _mediana(v: Array[float]) -> float:
	if v.is_empty():
		return 0.0
	var c := v.duplicate()
	c.sort()
	return c[c.size() / 2]
