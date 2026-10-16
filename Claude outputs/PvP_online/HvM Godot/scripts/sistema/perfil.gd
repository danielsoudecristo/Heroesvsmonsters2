class_name Perfil
extends RefCounted
## PERFIL DO JOGADOR: nome, lado, troféus, moedas, ligas e bônus do dia (igual ao perfil.js do site).
## CONVIDADO: tudo fica salvo neste aparelho (user://perfil.cfg).
## COM CONTA (Google): os números vêm do servidor (Supabase) e quem manda é ele. O progresso de convidado
## é levado para a conta no 1º login (uma vez só) e continua guardado no aparelho para quando sair.

const ARQUIVO := "user://perfil.cfg"
const MOEDAS_INICIAIS := 100
const BONUS_DOIS_LADOS := 150            ## moedas por jogar com os dois lados no mesmo dia
const BONUS_EM_ALTA := 0.5               ## +50% de moedas para o lado em alta do dia

## LIGAS pelo total de troféus (iguais às do site; imagens em assets/liga/).
const LIGAS := [
	{"nome": "Bronze",   "min": 0,    "cor": Color("c07a45"), "img": "Bronze"},
	{"nome": "Prata",    "min": 400,  "cor": Color("c9cfd8"), "img": "Prata"},
	{"nome": "Ouro",     "min": 800,  "cor": Color("f2c14e"), "img": "Ouro"},
	{"nome": "Diamante", "min": 1500, "cor": Color("5fd0f0"), "img": "Diamante"},
	{"nome": "Mestre",   "min": 2500, "cor": Color("a57bf0"), "img": "Mestre"},
	{"nome": "Campeão",  "min": 4000, "cor": Color("ffd97a"), "img": "Campeão"},
	{"nome": "Lendas",   "min": 6000, "cor": Color("c06cf0"), "img": "Lendas"},
	{"nome": "Leões FC", "min": 8000, "cor": Color("e8b84a"), "img": "Leoncs"},
]

static var nome := "Jogador"
static var lado := ""                    ## "heroes", "monsters" ou "" (ainda não escolheu)
static var trofeus := 0
static var moedas := MOEDAS_INICIAIS
static var vitorias := 0
static var derrotas := 0
static var som := true
static var lados_hoje: Array = []        ## lados jogados hoje (para o bônus dos dois lados)
static var dia_lados := ""               ## "2026-10-04" (dia de Brasília)
static var bonus_pago := false
static var convite := ""                 ## código de convite (com conta)
static var niveis := {}                  ## nível da conta de cada personagem (com conta)
static var convidado_ok := false         ## já escolheu "Jogar como convidado" (não pergunta de novo)
static var bot_nivel := 1                ## nível do bot do PvP (sobe quando você ganha dele, desce quando perde)
static var pvp_adversario := ""          ## nome do adversário da busca (só nesta partida)
static var pvp_sala := {}                ## PvP ONLINE: a sala que o servidor achou (vazio = contra o bot)
static var ja_entrou := false            ## já passou pela tela de carregamento nesta sessão
static var _lido := false
static var _com_conta := false           ## os números atuais são da conta (não grava por cima do convidado)

static func carregar() -> void:
	if _lido:
		return
	_lido = true
	_ler_arquivo()

static func _ler_arquivo() -> void:
	var cf := ConfigFile.new()
	if cf.load(ARQUIVO) != OK:
		return
	lado = cf.get_value("perfil", "lado", lado)
	som = cf.get_value("perfil", "som", som)
	convidado_ok = cf.get_value("perfil", "convidado_ok", convidado_ok)
	bot_nivel = cf.get_value("pvp", "bot_nivel", bot_nivel)
	nome = cf.get_value("convidado", "nome", cf.get_value("perfil", "nome", "Jogador"))
	moedas = cf.get_value("convidado", "moedas", cf.get_value("perfil", "moedas", MOEDAS_INICIAIS))
	trofeus = cf.get_value("convidado", "trofeus", cf.get_value("perfil", "trofeus", 0))
	vitorias = cf.get_value("convidado", "vitorias", 0)
	derrotas = cf.get_value("convidado", "derrotas", 0)
	var d = cf.get_value("bonus", "dia", "")
	dia_lados = d if d is String else ""
	lados_hoje = cf.get_value("bonus", "lados", [])
	bonus_pago = cf.get_value("bonus", "pago", false)

static func salvar() -> void:
	var cf := ConfigFile.new()
	cf.load(ARQUIVO)                     # mantém o que já estava (ex.: o progresso de convidado)
	cf.set_value("perfil", "lado", lado)
	cf.set_value("perfil", "som", som)
	cf.set_value("perfil", "convidado_ok", convidado_ok)
	cf.set_value("pvp", "bot_nivel", bot_nivel)
	if not _com_conta:                   # convidado: o progresso fica no aparelho
		cf.set_value("convidado", "nome", nome)
		cf.set_value("convidado", "moedas", moedas)
		cf.set_value("convidado", "trofeus", trofeus)
		cf.set_value("convidado", "vitorias", vitorias)
		cf.set_value("convidado", "derrotas", derrotas)
		cf.set_value("bonus", "dia", dia_lados)
		cf.set_value("bonus", "lados", lados_hoje)
		cf.set_value("bonus", "pago", bonus_pago)
	cf.save(ARQUIVO)

# ---------------------------------------------------------------- conta (Supabase)
static func _conta() -> Node:
	var arvore := Engine.get_main_loop() as SceneTree
	return arvore.root.get_node_or_null("Conta") if arvore else null

static func com_conta() -> bool:
	return _com_conta

## Números do convidado guardados no aparelho (para levar para a conta no 1º login).
static func dados_convidado() -> Dictionary:
	var cf := ConfigFile.new()
	cf.load(ARQUIVO)
	return {"moedas": int(cf.get_value("convidado", "moedas", moedas if not _com_conta else MOEDAS_INICIAIS)),
		"trofeus": int(cf.get_value("convidado", "trofeus", 0)),
		"vitorias": int(cf.get_value("convidado", "vitorias", 0)),
		"derrotas": int(cf.get_value("convidado", "derrotas", 0))}

## Chegou o perfil do servidor: ele é quem manda.
static func de_servidor(srv: Dictionary) -> void:
	if not _com_conta:
		salvar()                         # guarda o convidado antes de trocar
	_com_conta = true
	var c := _conta()
	nome = str(srv.get("nome", c.usuario.get("nome", "Jogador") if c else "Jogador"))
	moedas = int(srv.get("moedas", moedas))
	trofeus = int(srv.get("trofeus", trofeus))
	vitorias = int(srv.get("vitorias", vitorias))
	derrotas = int(srv.get("derrotas", derrotas))
	convite = str(srv.get("codigo_convite", "")) if srv.get("codigo_convite") != null else ""
	var d = srv.get("dia_bonus")
	dia_lados = str(d) if d != null else ""
	var l = srv.get("lados_hoje")
	lados_hoje = l if l is Array else []
	bonus_pago = bool(srv.get("bonus_duplo_pago", false))

## Saiu da conta: volta para o progresso de convidado deste aparelho.
static func voltar_convidado() -> void:
	_com_conta = false
	niveis = {}
	convite = ""
	_ler_arquivo()

# ---------------------------------------------------------------- ligas e bônus
static func liga() -> Dictionary:
	return liga_de(trofeus)

static func liga_de(t: int) -> Dictionary:
	var l: Dictionary = LIGAS[0]
	for x: Dictionary in LIGAS:
		if t >= int(x.min):
			l = x
	return l

## Dia de hoje no horário de Brasília (o servidor usa o mesmo).
static func hoje() -> String:
	var d := Time.get_date_dict_from_unix_time(int(Time.get_unix_time_from_system()) - 3 * 3600)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

## Lado em alta: dia do ano par = Heroes; ímpar = Monsters (igual ao servidor e ao site).
static func lado_em_alta() -> String:
	var d := Time.get_date_dict_from_unix_time(int(Time.get_unix_time_from_system()) - 3 * 3600)
	var inicio := Time.get_unix_time_from_datetime_dict({"year": d.year, "month": 1, "day": 1})
	var agora := Time.get_unix_time_from_datetime_dict({"year": d.year, "month": d.month, "day": d.day})
	var doy := int((agora - inicio) / 86400) + 1
	return "heroes" if doy % 2 == 0 else "monsters"

static func bonus_hoje() -> Dictionary:
	if dia_lados != hoje():
		dia_lados = hoje()
		lados_hoje = []
		bonus_pago = false
	return {"em_alta": lado_em_alta(), "lados": lados_hoje, "pago": bonus_pago, "valor": BONUS_DOIS_LADOS}

## Marca que jogou com um lado hoje. Devolve as moedas do bônus dos dois lados (0 se ainda não completou).
static func jogou_com(l: String) -> int:
	bonus_hoje()
	if not lados_hoje.has(l):
		lados_hoje.append(l)
	var ganho := 0
	if not bonus_pago and lados_hoje.has("heroes") and lados_hoje.has("monsters"):
		bonus_pago = true
		ganho = BONUS_DOIS_LADOS
		moedas += ganho
	salvar()
	return ganho

# ---------------------------------------------------------------- economia (igual ao perfil.js)
## Moedas da campanha e do PvP contra o bot: com o lado em alta vale +50%; também marca o lado jogado hoje.
## Com conta, o servidor confere e devolve os números certos.
static func ganhar_moedas(n: int, l: String) -> Dictionary:
	var alta := l != "" and l == lado_em_alta()
	var ganho := roundi(n * (1.0 + BONUS_EM_ALTA)) if alta else n
	moedas += ganho
	var duplo := jogou_com(l) if l != "" else 0
	salvar()
	var c := _conta()
	if c and _com_conta:
		var resto := n
		while resto > 0:                 # o servidor aceita até 60 por vez
			c.no_servidor("ganhar_moedas_campanha", {"qtd": mini(60, resto), "p_lado": l if l != "" else null})
			resto -= 60
	return {"ganho": ganho, "alta": alta, "duplo": duplo}

## Nível da conta de um personagem (1 se não tiver).
static func nivel_de(id: String) -> int:
	return int(niveis.get(id, 1))
