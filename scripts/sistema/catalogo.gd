extends Node
## CATÁLOGO: as fichas de res://dados/personagens/.
## Fica sempre disponível como "Catalogo" (Autoload). Uso: Catalogo.get_p("nick"), Catalogo.do_lado("heroes").
## OTIMIZADO: não carrega nada quando o jogo abre (o app abre mais rápido). A tela de carregamento pede as
## fichas em segundo plano (com as folhas de sprite) e a barra mostra o progresso de verdade.
## Se alguma cena usar o catálogo antes disso (ex.: abrir a arena direto pelo editor), ele carrega na hora.

const PASTA := "res://dados/personagens/"

var todos: Dictionary[String, PersonagemDados]:
	get:
		_garantir()
		return _todos

var _todos: Dictionary[String, PersonagemDados] = {}
var _carregado := false
var _pedidos: PackedStringArray = []

## FLUIDEZ: a interpolação de física fica ligada no projeto, mas desligada na árvore toda —
## só as Unidades (personagens que andam no passo fixo de 60/s) a ligam. Assim eles deslizam
## liso em qualquer tela (90/120 Hz, ou quando um quadro atrasa) e menus/HUD ficam como sempre.
func _enter_tree() -> void:
	get_tree().root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

## Caminhos de todas as fichas (.tres).
func arquivos() -> PackedStringArray:
	var lista := PackedStringArray()
	var dir := DirAccess.open(PASTA)
	if dir == null:
		push_warning("Catálogo: a pasta %s não existe. Rode ferramentas/gerar_fichas.gd primeiro." % PASTA)
		return lista
	for arq in dir.get_files():
		arq = arq.trim_suffix(".remap")          # no APK exportado os .tres viram .tres.remap
		if arq.ends_with(".tres") and not lista.has(PASTA + arq):
			lista.append(PASTA + arq)
	return lista

## Começa a carregar todas as fichas em segundo plano (usa vários núcleos do celular).
func pedir_em_segundo_plano() -> void:
	if _carregado or not _pedidos.is_empty():
		return
	for c in arquivos():
		if ResourceLoader.load_threaded_request(c, "", true) == OK:
			_pedidos.append(c)

## 0..1: quanto já carregou (1 se não pediu nada).
func progresso() -> float:
	if _carregado or _pedidos.is_empty():
		return 1.0
	var soma := 0.0
	for c in _pedidos:
		var arr := []
		var st := ResourceLoader.load_threaded_get_status(c, arr)
		soma += 1.0 if st != ResourceLoader.THREAD_LOAD_IN_PROGRESS else (float(arr[0]) if arr.size() > 0 else 0.0)
	return soma / _pedidos.size()

func _garantir() -> void:
	if not _carregado:
		recarregar()

func recarregar() -> void:
	_todos.clear()
	_carregado = true
	for c in arquivos():
		var p: PersonagemDados
		if _pedidos.has(c):
			p = ResourceLoader.load_threaded_get(c) as PersonagemDados   # já veio em segundo plano
		else:
			p = load(c) as PersonagemDados
		if p and p.id != "":
			_todos[p.id] = p
	_pedidos.clear()
	print("Catálogo: %d personagens carregados" % _todos.size())

func get_p(id: String) -> PersonagemDados:
	return todos.get(id)

## Personagens ativos de um lado, na ordem do custo (como na barra de cartas).
func do_lado(lado: String, so_ativos := true) -> Array[PersonagemDados]:
	var lista: Array[PersonagemDados] = []
	for p in todos.values():
		if p.lado == lado and (p.ativo or not so_ativos):
			lista.append(p)
	lista.sort_custom(func(a, b): return a.custo < b.custo or (a.custo == b.custo and a.nome < b.nome))
	return lista

## Par do outro lado (nick -> esqueleto).
func par_de(id: String) -> PersonagemDados:
	var p := get_p(id)
	return get_p(p.par) if p and p.par != "" else null
