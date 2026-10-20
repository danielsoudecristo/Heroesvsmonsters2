extends Node
## LOJA DE MOEDAS (autoload "Loja"): compra pela Google Play (plugin Android LojaPlay) e quem entrega as moedas
## é o SERVIDOR, depois de conferir com o Google (supabase/functions/verificar-compra + 33_loja_moedas.sql).
##
## Caminho de uma compra:
##   comprar(id) -> janela de pagamento do Google -> evento "compra" (token) -> verificar-compra no Supabase
##   -> moedas na conta -> consumir(token) na Play Store (libera comprar o mesmo pacote de novo).
## Se o jogo fechar no meio (pagou mas não entregou), recuperar() acha a compra na próxima vez e entrega.

signal mudou                                   ## pacotes / preços / estado mudaram (a tela redesenha)
signal comprou(moedas: int, em_dobro: bool)    ## moedas entregues (a tela comemora)
signal aviso(texto: String, bom: bool)         ## mensagem para mostrar

## Pacotes de reserva (se o servidor ainda não tiver o 33_loja_moedas.sql). O servidor é quem manda.
const PACOTES_PADRAO := [
	{"id": "moedas_1000", "nome": "Punhado", "moedas": 1000, "bonus": 0, "selo": "", "preco": "R$ 4,90"},
	{"id": "moedas_2200", "nome": "Saco", "moedas": 2200, "bonus": 10, "selo": "", "preco": "R$ 9,90"},
	{"id": "moedas_5000", "nome": "Baú", "moedas": 5000, "bonus": 25, "selo": "popular", "preco": "R$ 19,90"},
	{"id": "moedas_14000", "nome": "Cofre", "moedas": 14000, "bonus": 40, "selo": "", "preco": "R$ 49,90"},
	{"id": "moedas_32000", "nome": "Tesouro", "moedas": 32000, "bonus": 60, "selo": "melhor", "preco": "R$ 99,90"},
]

var plugin: Object = null
var pacotes: Array = []                        ## [{id, nome, moedas, bonus, selo, preco, tem_preco}]
var primeira_em_dobro := false
var ocupado := ""                              ## "" / "abrindo" (janela do Google) / "conferindo" (servidor)
var _verificando := {}                         ## tokens sendo conferidos agora (nunca duas vezes ao mesmo tempo)
var _reconectar_t := 0.0
var _buscou := false
var _recuperou := false
var _recuperar_t := 0.0                        ## espera antes de tentar entregar de novo (servidor falhou)
var _ocupado_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # (continua mesmo com o jogo pausado)
	pacotes = PACOTES_PADRAO.duplicate(true)
	for p in pacotes:
		p["tem_preco"] = false
	if Engine.has_singleton("LojaPlay"):
		plugin = Engine.get_singleton("LojaPlay")
		plugin.conectar()
	var conta := get_node_or_null("/root/Conta")
	if conta:
		conta.mudou.connect(_conta_mudou)
	_carregar_pacotes()

## Dá para comprar neste aparelho? (só no app Android instalado pela Play Store)
func disponivel() -> bool:
	return plugin != null and str(plugin.estado()) == "pronto"

func logado() -> bool:
	var c := get_node_or_null("/root/Conta")
	return c != null and c.online_pronto()

func pacote(id: String) -> Dictionary:
	for p in pacotes:
		if p.id == id:
			return p
	return {}

func comprar(id: String) -> void:
	if ocupado != "":
		return
	if not logado():
		aviso.emit("Entre na sua conta para comprar moedas.", false)
		return
	if not disponivel():
		aviso.emit("A loja abre no app instalado pela Google Play." if plugin == null else "Loja da Google Play indisponível agora. Tente de novo.", false)
		if plugin:
			plugin.conectar()
		return
	ocupado = "abrindo"
	mudou.emit()
	Conta.registrar("loja", {"evento": "abriu_pagamento", "pacote": id})
	plugin.comprar(id, Conta.meu_id())

# ------------------------------------------------------------------ servidor
func _conta_mudou() -> void:
	if logado():
		_carregar_conta()
		_recuperou = false                     # (entrou agora: procura compras não entregues desta conta)

func _carregar_pacotes() -> void:
	var c := get_node_or_null("/root/Conta")
	if c == null:
		return
	var r: Dictionary = await c.ler("loja_pacotes?select=id,nome,moedas,bonus,selo,ordem&ativo=eq.true&order=ordem")
	if r.ok and r.dados is Array and not r.dados.is_empty():
		var antigos := {}
		for p in pacotes:
			antigos[p.id] = p
		var novos: Array = []
		for linha in r.dados:
			var velho: Dictionary = antigos.get(str(linha.id), {})
			novos.append({"id": str(linha.id), "nome": str(linha.nome), "moedas": int(linha.moedas), "bonus": int(linha.bonus),
				"selo": str(linha.selo), "preco": velho.get("preco", ""), "tem_preco": velho.get("tem_preco", false)})
		pacotes = novos
		_buscou = false                        # (lista nova: pergunta os preços ao Google de novo)
		mudou.emit()

func _carregar_conta() -> void:
	var r: Dictionary = await Conta.chamar("minha_loja")
	if r.ok and r.dados is Dictionary:
		primeira_em_dobro = r.dados.get("primeira_em_dobro", false) == true
		mudou.emit()

## A tela da loja chama ao abrir: atualiza pacotes, preços e o "1ª compra em dobro".
func atualizar() -> void:
	_carregar_pacotes()
	if logado():
		_carregar_conta()
	_buscou = false

# ------------------------------------------------------------------ Play Store
func _process(dt: float) -> void:
	if plugin == null:
		return
	var est := str(plugin.estado())
	if est.begins_with("erro"):
		_reconectar_t -= dt
		if _reconectar_t <= 0.0:
			_reconectar_t = 15.0
			plugin.conectar()
		return
	if est != "pronto":
		return
	if not _buscou:
		_buscou = true
		plugin.buscar_produtos(",".join(pacotes.map(func(p): return p.id)))
	_ler_precos()
	if not _recuperou and logado():
		_recuperar_t -= dt
		if _recuperar_t <= 0.0:
			_recuperou = true
			plugin.recuperar()                 # pagou e o jogo fechou antes de entregar? entrega agora
	if ocupado == "abrindo":                   # (a janela do Google fechou sem resposta: destrava o botão)
		_ocupado_t += dt
		if _ocupado_t > 120.0:
			ocupado = ""
			mudou.emit()
	else:
		_ocupado_t = 0.0
	var txt := str(plugin.eventos())
	if txt == "[]":
		return
	var lista = JSON.parse_string(txt)
	if not (lista is Array):
		return
	for ev in lista:
		match str(ev.get("tipo", "")):
			"compra":
				_chegou_compra(ev)
			"cancelou":
				ocupado = ""
				mudou.emit()
			"erro":
				ocupado = ""
				mudou.emit()
				push_warning("LojaPlay: %s" % str(ev))
				aviso.emit("Não deu para concluir a compra (%s)." % str(ev.get("codigo", "?")), false)

var _precos_vistos := ""
func _ler_precos() -> void:
	var txt := str(plugin.produtos())
	if txt == _precos_vistos:
		return
	_precos_vistos = txt
	var lista = JSON.parse_string(txt)
	if not (lista is Array):
		return
	for d in lista:
		var p := pacote(str(d.get("id", "")))
		if not p.is_empty() and str(d.get("preco", "")) != "":
			p.preco = str(d.preco)             # preço do Google, já na moeda da pessoa ("R$ 4,90")
			p.tem_preco = true
	mudou.emit()

func _chegou_compra(ev: Dictionary) -> void:
	var token := str(ev.get("token", ""))
	if token == "" or _verificando.has(token):
		return
	if str(ev.get("estado", "")) == "pendente":
		ocupado = ""
		mudou.emit()
		aviso.emit("Pagamento pendente: as moedas chegam assim que o Google confirmar.", true)
		return
	if not logado():
		ocupado = ""
		mudou.emit()
		return                                 # (entra na conta e recuperar() entrega)
	var conta_compra := str(ev.get("conta", ""))
	if conta_compra != "" and conta_compra != Conta.meu_id():
		ocupado = ""
		mudou.emit()
		return                                 # compra feita com OUTRA conta do jogo: entrega quando ela entrar
	_verificando[token] = true
	ocupado = "conferindo"
	mudou.emit()
	var r: Dictionary = await Conta.funcao("verificar-compra", {"token": token, "produto": str(ev.get("produto", ""))})
	_verificando.erase(token)
	ocupado = ""
	var d = r.get("dados")
	if r.ok and d is Dictionary and d.get("ok", false) == true:
		Perfil.moedas = int(d.get("saldo", Perfil.moedas))
		Perfil.salvar()
		plugin.consumir(token)                 # entregue: libera comprar o mesmo pacote de novo
		Conta.mudou.emit()
		if d.get("novo", false) == true:
			primeira_em_dobro = false
			Conta.registrar("loja", {"evento": "comprou", "pacote": str(ev.get("produto", "")), "moedas": int(d.get("moedas_ganhas", 0))})
			comprou.emit(int(d.get("moedas_ganhas", 0)), d.get("em_dobro", false) == true)
	elif d is Dictionary and d.get("pendente", false) == true:
		aviso.emit("Pagamento pendente: as moedas chegam assim que o Google confirmar.", true)
	else:
		# NÃO consome: a compra fica guardada na Play Store e o jogo tenta entregar de novo depois
		var e := str(d.get("erro", r.get("erro", ""))) if d is Dictionary else str(r.get("erro", ""))
		push_warning("verificar-compra: %s" % e)
		aviso.emit("Pagamento recebido! Estamos confirmando suas moedas, elas chegam em instantes.", true)
		_recuperou = false
		_recuperar_t = 20.0                    # tenta de novo daqui a pouco (sem ficar martelando o servidor)
	mudou.emit()
