class_name Perfil
extends RefCounted
## PERFIL DO JOGADOR: nome, lado, troféus, moedas, ligas e bônus do dia (igual ao perfil.js do site).
## CONVIDADO: tudo fica salvo neste aparelho (user://perfil.cfg).
## COM CONTA (Google): os números vêm do servidor (Supabase) e quem manda é ele. O progresso de convidado
## é levado para a conta no 1º login (uma vez só) e continua guardado no aparelho para quando sair.

static var ARQUIVO := "user://perfil%s.cfg" % sufixo_teste()

## TESTE COM 2 JANELAS NO PC: a 2ª janela recebe o argumento "conta2" e usa outra conta e outro perfil.
## (Depurar > Personalizar Instâncias de Execução > Instância 2 > Argumentos: conta2)
static func sufixo_teste() -> String:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if "conta2" in a:
			return "2"
	return ""
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
static var trofeus_bot_dia := ""         ## CONVIDADO: dia (Brasília) da contagem abaixo
static var trofeus_bot_hoje := 0         ## CONVIDADO: troféus que o bot já deu hoje (limite por dia)
static var dificuldade := "medio"         ## campanha: facil / medio / dificil / hardcore (escolhe no Novo jogo)
static var recordes := {}                ## campanha POR LADO: {"heroes"|"monsters": {dificuldade -> maior nível COMPLETADO}}
static var pvp_adversario := ""          ## nome do adversário da busca (só nesta partida)
static var pvp_modo := "normal"          ## PvP: "normal" ou "cerco" (só para a próxima partida)
static var pvp_sala := {}                ## PvP ONLINE: a sala que o servidor achou (vazio = contra o bot)
## SÉRIE CONTRA O BOT (Batalha): {jogo, meus, dele, nivel, lado_original, adversario, continua}. Vazio = sem série.
## Só na memória: vive entre uma partida e a próxima da mesma série (a cena do PvP recarrega).
static var serie_bot := {}
## REPLAY para assistir (36_replays.sql): a "receita" da partida + "lado_ver". Vazio = partida normal.
static var pvp_replay := {}
static var tutorial_menu := false        ## já viu o tutorial do menu
static var tutorial_jogo := false        ## já fez o tutorial da primeira batalha
static var convite_visto := false        ## já abriu "Convide amigos" (tira a etiqueta NOVO)
static var ja_entrou := false            ## já passou pela tela de carregamento nesta sessão
static var sala_modo := "batalha"        ## sala de entrada do PvP: "batalha", "cerco" ou "campeonato"
static var login_campeonato := false    ## convidado tocou "ENTRAR" no Campeonato: abre o login e depois volta para a árvore
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
	dificuldade = cf.get_value("campanha", "dificuldade", dificuldade)
	tutorial_menu = cf.get_value("tutorial", "menu", tutorial_menu)
	tutorial_jogo = cf.get_value("tutorial", "jogo", tutorial_jogo)
	convite_visto = cf.get_value("tutorial", "convite", convite_visto)
	var rc = cf.get_value("campanha", "recordes", {})
	recordes = _recordes_limpos(rc)
	nome = cf.get_value("convidado", "nome", cf.get_value("perfil", "nome", "Jogador"))
	moedas = cf.get_value("convidado", "moedas", cf.get_value("perfil", "moedas", MOEDAS_INICIAIS))
	trofeus = cf.get_value("convidado", "trofeus", cf.get_value("perfil", "trofeus", 0))
	vitorias = cf.get_value("convidado", "vitorias", 0)
	derrotas = cf.get_value("convidado", "derrotas", 0)
	trofeus_bot_dia = str(cf.get_value("convidado", "trofeus_bot_dia", ""))
	trofeus_bot_hoje = int(cf.get_value("convidado", "trofeus_bot_hoje", 0))
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
	cf.set_value("campanha", "dificuldade", dificuldade)
	cf.set_value("tutorial", "menu", tutorial_menu)
	cf.set_value("tutorial", "jogo", tutorial_jogo)
	cf.set_value("tutorial", "convite", convite_visto)
	cf.set_value("campanha", "recordes", recordes)
	if not _com_conta:                   # convidado: o progresso fica no aparelho
		cf.set_value("convidado", "nome", nome)
		cf.set_value("convidado", "moedas", moedas)
		cf.set_value("convidado", "trofeus", trofeus)
		cf.set_value("convidado", "vitorias", vitorias)
		cf.set_value("convidado", "derrotas", derrotas)
		cf.set_value("convidado", "trofeus_bot_dia", trofeus_bot_dia)
		cf.set_value("convidado", "trofeus_bot_hoje", trofeus_bot_hoje)
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

## O personagem está liberado para jogar? (ficha com desbloqueio_trofeus > 0 exige a liga mínima.)
static func personagem_liberado(p: PersonagemDados) -> bool:
	return p == null or p.desbloqueio_trofeus <= 0 or trofeus >= p.desbloqueio_trofeus

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

## CONVIDADO venceu o bot na Batalha: soma até o limite do dia. Devolve [ganho, quanto já ganhou hoje].
## (Com conta isso é no servidor: supabase/34_trofeus_bot.sql.)
static func ganhar_trofeus_bot(premio: int, limite: int) -> Array:
	if trofeus_bot_dia != hoje():
		trofeus_bot_dia = hoje()
		trofeus_bot_hoje = 0
	var ganho := clampi(limite - trofeus_bot_hoje, 0, premio)
	trofeus += ganho
	trofeus_bot_hoje += ganho
	salvar()
	return [ganho, trofeus_bot_hoje]

## O recorde é por lado (heróis e monstros não misturam). Vazio/fora do padrão vira os dois lados vazios.
## O arquivo antigo (só dificuldade -> nível) era UM número para os DOIS lados: ele continua valendo
## nos dois (mesma ideia do 25_recorde_para_os_dois_lados.sql) — ninguém perde o recorde que já batia.
static func _recordes_limpos(v) -> Dictionary:
	if not (v is Dictionary):
		return {"heroes": {}, "monsters": {}}
	if v.has("heroes") or v.has("monsters"):
		return v
	return {"heroes": v.duplicate(), "monsters": v.duplicate()}

## O lado que vale para quem olha o recorde (sem lado claro: os heróis, como antes).
static func _de_que_lado(lado: String) -> String:
	return lado if lado in ["heroes", "monsters"] else "heroes"

static func _recordes_do(lado: String) -> Dictionary:
	var r = recordes.get(_de_que_lado(lado))
	return r if r is Dictionary else {}

## RECORDE da campanha de um lado numa dificuldade (0 = ainda não completou nenhum nível).
static func recorde(dif: String, lado := "") -> int:
	return int(_recordes_do(lado).get(dif, 0))

## Completou o nível n: guarda se for recorde (e manda para o servidor, com conta). Devolve true se é recorde NOVO.
static func registrar_recorde(dif: String, n: int, lado := "") -> bool:
	var l := _de_que_lado(lado)
	var sub := _recordes_do(l)
	if n <= int(sub.get(dif, 0)):
		return false
	sub[dif] = n
	recordes[l] = sub
	salvar()
	var c := _conta()
	if c and c.online_pronto():
		c.chamar("registrar_recorde_campanha", {"p_dificuldade": dif, "p_nivel": n, "p_lado": l})   # (sem esperar)
	return true

## Recordes que vieram do servidor (fica o maior de cada, por lado).
static func recordes_do_servidor(linhas: Array) -> void:
	for l in linhas:
		var d := str(l.get("dificuldade", ""))
		if d == "":
			continue
		var ld := _de_que_lado(str(l.get("lado", "")))
		var sub := _recordes_do(ld)
		sub[d] = maxi(int(sub.get(d, 0)), int(l.get("nivel", 0)))
		recordes[ld] = sub
	salvar()

## Nível da conta de um personagem (1 se não tiver).
static func nivel_de(id: String) -> int:
	return int(niveis.get(id, 1))
