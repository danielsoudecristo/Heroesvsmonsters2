extends Node
## CONTA: login com Google pelo Supabase (o mesmo projeto do site) e chamadas ao servidor.
## Autoload com o nome "Conta". Uso: await Conta.chamar("meu_perfil")
##
## LOGIN COM GOOGLE (funciona em qualquer celular, mesmo os que congelam o jogo quando o navegador abre):
## 1) o jogo cria um "estado" e um segredo (PKCE) e abre o Google pelo Supabase, com a lista de contas;
## 2) depois de escolher a conta, o Google volta para o site: godot-login.html?s=ESTADO&code=...
##    A página guarda o código no servidor (supabase/10_login_godot_pkce.sql) e mostra "Login feito";
## 3) o jogo pergunta ao servidor pelo código (na hora que você volta para ele) e troca pela sessão.
##    O código sozinho não serve para nada: só este aparelho tem o segredo para trocar.
## No Supabase: Redirect URLs precisa ter  https://heroes-vs-monsters.pages.dev/godot-login.html
## A sessão fica salva neste aparelho (criptografada): não precisa entrar toda vez.
## Só a chave PÚBLICA fica no jogo. NUNCA coloque a chave "secret" / "service_role" aqui.

const SUPABASE := "https://wrhrtzesfhiwydtmbezq.supabase.co"
const CHAVE := "sb_publishable_LzAJ7FOOCOBJWr8DwuyvVg_xsfKCDTP"
const PONTE := "https://heroes-vs-monsters.pages.dev/godot-login.html"   ## página do site que guarda o código do login
## LOGIN COM GOOGLE DENTRO DO APP (Android): "ID do cliente Web" do Google (o mesmo que está no Supabase >
## Authentication > Sign In / Providers > Google > Client ID). Termina em .apps.googleusercontent.com
const GOOGLE_WEB_CLIENT_ID := "398648757697-7ni57gdfhidp4f0u75ccmjcljaf8l5o1.apps.googleusercontent.com"
var ARQUIVO := "user://conta.cfg"                ## (2ª janela de teste com o argumento "conta2": conta2.cfg)
const ESPERA_LOGIN := 300.0                     ## segundos esperando o login no navegador
const PERGUNTA_CADA := 2.0                      ## de quanto em quanto tempo pergunta se o login chegou

signal mudou                                     ## entrou, saiu ou o perfil chegou do servidor
signal erro(msg: String)

var usuario := {}                                ## {id, email, nome, foto}  (vazio = convidado)
var foto: Texture2D                              ## foto do Google (quando carregar)
var esperando_login := false
var status := "convidado"                        ## convidado / entrando / carregando / conectado / erro

var _base := SUPABASE                            # (teste: dá para apontar para outro servidor com HVM_SUPABASE)
var _access := ""
var _refresh := ""
var _expira := 0.0                               ## Time.get_unix_time_from_system() em que o access vence
var _codigo := ""
var _espera_t := 0.0
var _pergunta_t := 0.0
var _renovando := false
var _verificador := ""                           # PKCE: segredo deste login (nunca sai do aparelho)
var aviso_login := ""                            ## o que está acontecendo no login (a tela de login mostra)
const PENDENTE := "user://login_pendente.cfg"    ## login começado (se o Android fechar o jogo, continua daqui)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if "conta2" in arg:
			ARQUIVO = "user://conta2.cfg"
	if OS.get_environment("HVM_SUPABASE") != "":
		_base = OS.get_environment("HVM_SUPABASE")
	_carregar()
	if _refresh != "":
		status = "carregando"
		_renovar_e_conectar()
	else:
		_retomar_pendente()
	_registrar_abertura()

# ================================================================ REGISTRO (painel do dono)
## O jogo avisa o servidor do que acontece (abriu, tempo jogado, campanha, bot) para o painel.html.
## Funciona com ou sem conta (sem conta = "Convidado", pelo id aleatório do aparelho). Tabela: 16_painel.sql
const VERSAO_JOGO := "1.3"
const NOVO_ACESSO_DEPOIS := 180.0                ## voltou ao jogo depois de 3 min fora = conta outro acesso
var _aparelho := ""
var _sessao_ini := -1.0
var _pausou_em := -1.0

func registrar(tipo: String, dados := {}) -> void:
	_garantir_aparelho()
	chamar("registrar_evento", {"p_tipo": tipo, "p_dados": dados, "p_aparelho": _aparelho, "p_versao": VERSAO_JOGO})

## AO VIVO (20_ao_vivo.sql): o que a pessoa está fazendo agora. Manda na hora quando muda e a cada 30 s.
const AO_VIVO_CADA := 30.0
var atividade := "menu"
var atividade_detalhe := ""
var _vivo_t := 5.0

func estou(ativ: String, detalhe := "") -> void:
	if ativ == atividade and detalhe == atividade_detalhe:
		return
	atividade = ativ
	atividade_detalhe = detalhe
	_vivo_t = 0.4                                  # manda logo (junta mudanças rápidas)

## ASSISTIR AO VIVO (29_painel_assistir.sql): quando o dono abre "Assistir" no painel, o servidor responde "true"
## e o jogo passa a mandar, a cada 2,5 s, uma FOTO resumida da partida (tela_provedor: a arena que está aberta).
## Ninguém assistindo = volta para o aviso normal de 30 s (sem custo a mais).
const ASSISTIDO_CADA := 2.5
var tela_provedor: Callable                    ## a arena registra aqui: devolve {modo, castelos, unidades...}
var _assistido := false
var _sem_v2 := false                           ## servidor sem o 29_painel_assistir.sql: usa o aviso antigo
var _vivo_ocupado := false

func _ping_vivo() -> void:
	_garantir_aparelho()
	if _sem_v2:
		chamar("estou_aqui", {"p_aparelho": _aparelho, "p_atividade": atividade, "p_detalhe": atividade_detalhe, "p_versao": VERSAO_JOGO})
		return
	if _vivo_ocupado:
		return
	_vivo_ocupado = true
	var tela = null
	if _assistido and tela_provedor.is_valid():
		var obj = tela_provedor.get_object()
		if obj != null and is_instance_valid(obj) and (obj as Node).is_inside_tree():
			tela = tela_provedor.call()
	var r: Dictionary = await chamar("estou_aqui2", {"p_aparelho": _aparelho, "p_atividade": atividade, "p_detalhe": atividade_detalhe,
		"p_versao": VERSAO_JOGO, "p_tela": tela})
	_vivo_ocupado = false
	if not r.ok and ("estou_aqui2" in str(r.erro) or "function" in str(r.erro).to_lower()):
		_sem_v2 = true
		return
	var antes := _assistido
	_assistido = r.ok and r.dados == true
	if _assistido:
		_vivo_t = minf(_vivo_t, ASSISTIDO_CADA)
	elif antes:
		_vivo_t = AO_VIVO_CADA

func _garantir_aparelho() -> void:
	if _aparelho == "":
		var cf := ConfigFile.new()
		cf.load("user://aparelho.cfg")
		_aparelho = str(cf.get_value("aparelho", "id", ""))
		if _aparelho == "":
			var c := Crypto.new()
			_aparelho = c.generate_random_bytes(12).hex_encode()
			cf.set_value("aparelho", "id", _aparelho)
			cf.save("user://aparelho.cfg")

func _registrar_abertura() -> void:
	var t := 0.0
	while status == "carregando" and t < 10.0:     # espera a conta entrar (para o acesso ir com o nome certo)
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	_sessao_ini = Time.get_ticks_msec() / 1000.0
	registrar("abriu", {"plataforma": OS.get_name(), "logado": logado()})

func _fim_da_sessao() -> void:
	if _sessao_ini < 0.0:
		return
	var seg := int(Time.get_ticks_msec() / 1000.0 - _sessao_ini)
	_sessao_ini = -1.0
	if seg >= 5:
		registrar("sessao", {"segundos": seg})

## O celular fechou o jogo enquanto a pessoa estava no navegador? Continua o mesmo login (até 10 min).
func _retomar_pendente() -> void:
	var cf := ConfigFile.new()
	if cf.load_encrypted_pass(PENDENTE, _senha()) != OK:
		return
	var t: float = cf.get_value("login", "t", 0.0)
	if Time.get_unix_time_from_system() - t > 600.0:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDENTE))
		return
	_codigo = cf.get_value("login", "estado", "")
	_verificador = cf.get_value("login", "verificador", "")
	if _codigo == "" or _verificador == "":
		return
	esperando_login = true
	_espera_t = Time.get_unix_time_from_system() - t
	_pergunta_t = 0.3
	status = "entrando"
	aviso_login = "Terminando o login..."

func _guardar_pendente() -> void:
	var cf := ConfigFile.new()
	cf.set_value("login", "estado", _codigo)
	cf.set_value("login", "verificador", _verificador)
	cf.set_value("login", "t", Time.get_unix_time_from_system())
	cf.save_encrypted_pass(PENDENTE, _senha())

func _apagar_pendente() -> void:
	if FileAccess.file_exists(PENDENTE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDENTE))

func logado() -> bool:
	return not usuario.is_empty() and _access != ""

## Conta pronta para jogar online (logado e com o perfil carregado).
func online_pronto() -> bool:
	return logado() and status == "conectado"

func meu_id() -> String:
	return str(usuario.get("id", ""))

## Endereço do servidor (o PvP online usa para abrir o canal ao vivo).
func endereco() -> String:
	return _base

## Token de acesso que ainda vale por pelo menos 10 minutos (o canal ao vivo do PvP precisa dele).
func token_fresco() -> String:
	if _refresh != "" and Time.get_unix_time_from_system() > _expira - 540.0:
		await _renovar()
	return _access

# =================================================================== LOGIN
func entrar_google() -> void:
	if _google_nativo_disponivel():
		_entrar_google_nativo()
		return
	var c := Crypto.new()
	_codigo = c.generate_random_bytes(24).hex_encode()     # "estado": identifica ESTE login no servidor
	_verificador = _base64url(c.generate_random_bytes(32))  # PKCE: o segredo fica só neste aparelho
	esperando_login = true
	_espera_t = 0.0
	_pergunta_t = 2.0
	status = "entrando"
	var desafio := _base64url(_verificador.sha256_buffer())
	aviso_login = "Escolha a conta no navegador..."
	_guardar_pendente()
	# a página do site guarda o "estado" no navegador e abre o Google (a volta é para o endereço exato dela)
	OS.shell_open(PONTE + "?ini=" + _codigo + "&c=" + desafio)
	mudou.emit()

# =================================================================== GOOGLE DENTRO DO APP (Android)
## A janelinha de contas do próprio Android (plugin LoginGoogle, em android/build/src/main/java/com/hvm/login).
## Ela devolve um "ID token" do Google e o Supabase troca por uma sessão (grant_type=id_token). Sem navegador.
var _nativo_t := -1.0
var _nonce := ""

func _google_nativo_disponivel() -> bool:
	return OS.get_name() == "Android" and GOOGLE_WEB_CLIENT_ID != "" and Engine.has_singleton("LoginGoogle")

func _entrar_google_nativo() -> void:
	cancelar_login()
	_nonce = Crypto.new().generate_random_bytes(24).hex_encode()
	status = "entrando"
	aviso_login = "Escolha sua conta Google..."
	mudou.emit()
	Engine.get_singleton("LoginGoogle").entrar(GOOGLE_WEB_CLIENT_ID, _nonce.sha256_text())
	_nativo_t = 0.0

func _passo_nativo(dt: float) -> void:
	_nativo_t += dt
	var r: String = Engine.get_singleton("LoginGoogle").resultado()
	if r == "":
		if _nativo_t > 180.0:
			_nativo_t = -1.0
			status = "convidado" if not logado() else "conectado"
			aviso_login = "O login demorou demais. Tente de novo."
			mudou.emit()
		return
	_nativo_t = -1.0
	if r.begins_with("cancelado"):
		status = "convidado" if not logado() else "conectado"
		aviso_login = ""
		mudou.emit()
		return
	if r.begins_with("erro:"):
		status = "convidado" if not logado() else "conectado"
		aviso_login = "Google: " + r.trim_prefix("erro:").left(110)
		push_warning("LoginGoogle: " + r)
		erro.emit(aviso_login)
		mudou.emit()
		return
	status = "carregando"
	aviso_login = "Entrando na sua conta..."
	mudou.emit()
	var t: Dictionary = await _http(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=id_token",
		{"provider": "google", "id_token": r.trim_prefix("ok:"), "nonce": _nonce}, false)
	if not t.ok or not (t.dados is Dictionary) or not t.dados.has("refresh_token"):
		status = "convidado" if not logado() else "conectado"
		aviso_login = "Não deu para entrar: " + str(t.erro).left(100)
		push_warning("LoginGoogle: Supabase recusou: %s" % t.erro)
		erro.emit(aviso_login)
		mudou.emit()
		return
	aviso_login = ""
	_refresh = t.dados.refresh_token
	await _renovar_e_conectar()

# =================================================================== LOGIN COM NOME E SENHA
## Funciona em qualquer aparelho, sem navegador. Por baixo, vira um "e-mail" interno nome@jogador.heroesvsmonsters.app
## (ninguém recebe e-mail nenhum). No Supabase: Authentication > Sign In / Providers > Email: ligado e "Confirm email" DESLIGADO.
const DOMINIO_NOME := "@jogador.heroesvsmonsters.app"

## Nome válido: 3 a 16 letras, números ou _ (sem espaço nem acento). Devolve "" se estiver ok, ou o problema.
static func problema_no_nome(nome: String) -> String:
	if nome.length() < 3 or nome.length() > 16:
		return "O nome precisa ter de 3 a 16 letras."
	var re := RegEx.create_from_string("^[A-Za-z0-9_]+$")
	if re.search(nome) == null:
		return "Use só letras, números e _ (sem espaço e sem acento)."
	return ""

## Entra (criar = false) ou cria a conta (criar = true). Devolve "" se deu certo, ou a mensagem do problema.
func entrar_com_senha(nome: String, senha: String, criar: bool) -> String:
	nome = nome.strip_edges()
	var p := problema_no_nome(nome)
	if p != "":
		return p
	if senha.length() < 6:
		return "A senha precisa ter pelo menos 6 letras ou números."
	cancelar_login()
	status = "carregando"
	aviso_login = "Criando sua conta..." if criar else "Entrando..."
	mudou.emit()
	var email := nome.to_lower() + DOMINIO_NOME
	var r: Dictionary
	if criar:
		r = await _http(HTTPClient.METHOD_POST, "/auth/v1/signup",
			{"email": email, "password": senha, "data": {"full_name": nome, "name": nome}}, false)
	else:
		r = await _http(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=password", {"email": email, "password": senha}, false)
	aviso_login = ""
	if r.ok and r.dados is Dictionary and r.dados.has("refresh_token"):
		_refresh = r.dados.refresh_token
		await _renovar_e_conectar()
		return "" if logado() else "Não deu para carregar a conta. Tente de novo."
	status = "convidado" if not logado() else "conectado"
	mudou.emit()
	if r.ok and criar:                                       # criou, mas o Supabase quer confirmar o e-mail
		return "Conta criada, mas falta desligar \"Confirm email\" no Supabase."
	var msg := str(r.erro).to_lower()
	if r.codigo == 0:
		return "Sem internet. Confira a conexão e tente de novo."
	if "invalid login" in msg or "invalid_credentials" in msg:
		return "Nome ou senha errados."
	if "already" in msg or "registered" in msg or "exists" in msg:
		return "Esse nome já existe. Escolha outro (ou toque em Entrar)."
	if "not confirmed" in msg:
		return "Falta desligar \"Confirm email\" no Supabase."
	if "password" in msg:
		return "Senha fraca: use pelo menos 6 letras ou números."
	if "signup" in msg and "disabled" in msg:
		return "O cadastro por e-mail está desligado no Supabase."
	return "Não deu: " + str(r.erro).left(80)

func cancelar_login() -> void:
	esperando_login = false
	_codigo = ""
	_verificador = ""
	_apagar_pendente()
	status = "convidado" if not logado() else "conectado"
	mudou.emit()

static func _base64url(b: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(b).replace("+", "-").replace("/", "_").replace("=", "")

func _process(dt: float) -> void:
	if _sessao_ini >= 0.0 and status != "carregando":
		_vivo_t -= dt
		if _vivo_t <= 0.0:
			_vivo_t = ASSISTIDO_CADA if _assistido else (AO_VIVO_CADA if atividade == "menu" else 15.0)   # (em partida: o painel acha mais rápido)
			_ping_vivo()
	if _nativo_t >= 0.0:
		_passo_nativo(dt)
		return
	if not esperando_login:
		return
	_espera_t += dt
	if _espera_t > ESPERA_LOGIN:
		cancelar_login()
		erro.emit("O login demorou demais. Tente de novo.")
		return
	_pergunta_t -= dt
	if _pergunta_t <= 0.0 and not _renovando:
		_pergunta_t = PERGUNTA_CADA
		_perguntar_login()

## Voltou do navegador para o jogo (celular): pergunta na hora, sem esperar.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_pausou_em = Time.get_ticks_msec() / 1000.0
		_fim_da_sessao()
		chamar("estou_aqui", {"p_aparelho": _aparelho, "p_atividade": "fora", "p_detalhe": "", "p_versao": VERSAO_JOGO})
	elif what == NOTIFICATION_APPLICATION_RESUMED and _sessao_ini < 0.0 and _pausou_em >= 0.0:
		var fora := Time.get_ticks_msec() / 1000.0 - _pausou_em
		_sessao_ini = Time.get_ticks_msec() / 1000.0
		_vivo_t = 0.3                                  # voltou: avisa o "ao vivo" na hora
		if fora > NOVO_ACESSO_DEPOIS:
			registrar("abriu", {"plataforma": OS.get_name(), "logado": logado(), "voltou": true})
	if (what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN) and esperando_login:
		_pergunta_t = 0.0

## O navegador entregou o código no servidor (página godot-login.html do site)? Se sim, troca pela sessão.
func _perguntar_login() -> void:
	_renovando = true
	var r: Dictionary = await _http(HTTPClient.METHOD_POST, "/rest/v1/rpc/pegar_codigo_godot", {"p_estado": _codigo}, false)
	_renovando = false
	if not esperando_login:
		return
	if not r.ok:
		aviso_login = "Sem resposta do servidor (%s). Tentando de novo..." % str(r.erro).left(60)
		push_warning("Login: pegar_codigo_godot falhou: %s" % r.erro)
		return
	if not (r.dados is String) or r.dados == "":
		return                                              # ainda não escolheu a conta
	var cod: String = r.dados
	if cod.begins_with("erro:"):
		cancelar_login()
		aviso_login = "Login cancelado: " + cod.trim_prefix("erro:")
		erro.emit(aviso_login)
		return
	status = "carregando"
	aviso_login = "Entrando na sua conta..."
	mudou.emit()
	var t: Dictionary
	if cod.begins_with("rt:"):                              # (a página recebeu a sessão pronta)
		t = {"ok": true, "dados": {"refresh_token": cod.trim_prefix("rt:")}, "erro": ""}
	else:
		t = await _http(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=pkce",
			{"auth_code": cod, "code_verifier": _verificador}, false)
	esperando_login = false
	_codigo = ""
	_verificador = ""
	_apagar_pendente()
	if not t.ok or not (t.dados is Dictionary) or not t.dados.has("refresh_token"):
		status = "convidado" if not logado() else "conectado"
		aviso_login = "Não deu para entrar: " + str(t.erro).left(90)
		push_warning("Login: troca do código falhou: %s" % t.erro)
		erro.emit(aviso_login)
		mudou.emit()
		return
	_refresh = t.dados.refresh_token
	aviso_login = ""
	await _renovar_e_conectar()

func sair() -> void:
	if _access != "":
		_http(HTTPClient.METHOD_POST, "/auth/v1/logout", {}, true)       # avisa o servidor (sem esperar)
	_limpar()
	mudou.emit()

## Apaga a conta e todos os dados no servidor (exigido pela Play Store). Devolve "" se deu certo, ou o erro.
func excluir_conta() -> String:
	var r: Dictionary = await chamar("excluir_minha_conta")
	if not r.ok:
		return r.erro
	_limpar()
	mudou.emit()
	return ""

func _limpar() -> void:
	usuario = {}
	foto = null
	_access = ""
	_refresh = ""
	_expira = 0.0
	status = "convidado"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ARQUIVO))
	Perfil.voltar_convidado()

# =================================================================== SESSÃO
func _renovar_e_conectar() -> void:
	status = "carregando"
	mudou.emit()
	if not await _renovar():
		return
	await _conectar_perfil()

## Traz o perfil do servidor (e, na 1ª vez, leva o progresso de convidado para a conta: igual ao site).
func _conectar_perfil() -> void:
	var r: Dictionary = await chamar("meu_perfil")
	if not r.ok or not (r.dados is Dictionary):
		status = "erro"
		erro.emit("Não deu para carregar a conta: " + str(r.erro))
		mudou.emit()
		return
	var srv: Dictionary = r.dados
	if not srv.get("importou_local", true):
		var loc := Perfil.dados_convidado()
		var r2: Dictionary = await chamar("importar_progresso_local", {"p_moedas": loc.moedas, "p_trofeus": loc.trofeus,
			"p_vitorias": loc.vitorias, "p_derrotas": loc.derrotas})
		if r2.ok and r2.dados is Dictionary:
			srv = r2.dados
	Perfil.de_servidor(srv)
	var ra: Dictionary = await chamar("meus_ajustes")           # (37_painel_admin.sql) ajustes do painel
	if ra.ok and ra.dados is Dictionary:
		Perfil.energia_extra = int(ra.dados.get("energia_extra", 0))
		Perfil.banido = ra.dados.get("banido", false) == true
	var rp: Dictionary = await ler("personagens_jogador?select=personagem,nivel")
	if rp.ok and rp.dados is Array:
		var nv := {}
		for linha in rp.dados:
			nv[str(linha.personagem)] = int(linha.nivel)
		Perfil.niveis = nv
	var rr: Dictionary = await ler("recordes_campanha?select=lado,dificuldade,nivel")   # (24_recorde_por_lado.sql)
	if rr.ok and rr.dados is Array:
		Perfil.recordes_do_servidor(rr.dados)
	status = "conectado"
	mudou.emit()
	if Perfil.lado in ["heroes", "monsters"]:
		chamar("definir_lado", {"p_lado": Perfil.lado})        # (17_chat_duelo.sql) mostra o lado certo para os outros
	chamar("checar_indicacao")                                 # (18_indicacao.sql) se você foi convidado e já jogou, paga quem convidou

## Grava no servidor sem esperar e acerta os números com a resposta dele (o servidor é quem manda).
func no_servidor(nome: String, args := {}) -> void:
	if not logado() or status != "conectado":
		return
	var r: Dictionary = await chamar(nome, args)
	if r.ok and r.dados is Dictionary and r.dados.has("id"):
		Perfil.de_servidor(r.dados)
		mudou.emit()
	elif not r.ok:
		push_warning("Conta: %s falhou: %s" % [nome, r.erro])

## Troca o refresh_token por uma sessão nova (o Supabase devolve outro refresh_token: guardamos).
func _renovar() -> bool:
	if _refresh == "":
		return false
	_renovando = true
	var r: Dictionary = await _http(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token", {"refresh_token": _refresh}, false)
	_renovando = false
	if not r.ok or not (r.dados is Dictionary) or not r.dados.has("access_token"):
		if r.codigo >= 400 and r.codigo < 500:     # sessão vencida/cancelada: volta a ser convidado
			_limpar()
			erro.emit("Sua sessão acabou. Entre de novo com o Google.")
		else:
			status = "erro"
			erro.emit("Sem internet para entrar na conta.")
		mudou.emit()
		return false
	var d: Dictionary = r.dados
	_access = d.access_token
	_refresh = d.get("refresh_token", _refresh)
	_expira = Time.get_unix_time_from_system() + float(d.get("expires_in", 3600)) - 60.0
	var u: Dictionary = d.get("user", {})
	var m: Dictionary = u.get("user_metadata", {})
	var email: String = u.get("email", "")
	usuario = {"id": u.get("id", ""), "email": email,
		"nome": m.get("full_name", m.get("name", email.get_slice("@", 0) if email != "" else "Jogador")),
		"foto": m.get("avatar_url", m.get("picture", ""))}
	_salvar()
	_baixar_foto(usuario.foto)
	return true

func _salvar() -> void:
	var cf := ConfigFile.new()
	cf.set_value("conta", "refresh", _refresh)
	cf.save_encrypted_pass(ARQUIVO, _senha())

func _carregar() -> void:
	var cf := ConfigFile.new()
	if cf.load_encrypted_pass(ARQUIVO, _senha()) == OK:
		_refresh = cf.get_value("conta", "refresh", "")

func _senha() -> String:
	return "hvm-" + OS.get_unique_id()

func _baixar_foto(url: String) -> void:
	if not url.begins_with("https://"):
		return
	var h := HTTPRequest.new()
	add_child(h)
	h.request(url)
	var res: Array = await h.request_completed
	h.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return
	var img := Image.new()
	var corpo: PackedByteArray = res[3]
	if img.load_jpg_from_buffer(corpo) != OK and img.load_png_from_buffer(corpo) != OK and img.load_webp_from_buffer(corpo) != OK:
		return
	foto = ImageTexture.create_from_image(img)
	mudou.emit()

# =================================================================== SERVIDOR
## Chama uma função do banco (as dos arquivos supabase/*.sql). Devolve {ok, dados, erro, codigo}.
func chamar(nome: String, args := {}) -> Dictionary:
	return await _com_sessao(HTTPClient.METHOD_POST, "/rest/v1/rpc/" + nome, args)

## Lê uma tabela (só as linhas do próprio jogador, por causa das regras do banco). Ex.: "personagens_jogador?select=personagem,nivel"
func ler(tabela_e_filtro: String) -> Dictionary:
	return await _com_sessao(HTTPClient.METHOD_GET, "/rest/v1/" + tabela_e_filtro, null)

func _com_sessao(metodo: int, caminho: String, corpo) -> Dictionary:
	var com_login := _access != ""
	if com_login and Time.get_unix_time_from_system() > _expira:
		await _renovar()
		com_login = _access != ""
	var r: Dictionary = await _http(metodo, caminho, corpo, com_login)
	if com_login and r.codigo == 401 and await _renovar():   # venceu no meio: renova e tenta de novo
		r = await _http(metodo, caminho, corpo, true)
	return r

func _http(metodo: int, caminho: String, corpo, com_login: bool) -> Dictionary:
	var h := HTTPRequest.new()
	h.timeout = 20.0
	add_child(h)
	var cab := PackedStringArray(["apikey: " + CHAVE, "Content-Type: application/json"])
	if com_login:
		cab.append("Authorization: Bearer " + _access)
	var texto := "" if corpo == null else JSON.stringify(corpo)
	var e := h.request(_base + caminho, cab, metodo, texto)
	if e != OK:
		h.queue_free()
		return {"ok": false, "dados": null, "erro": "não deu para conectar", "codigo": 0}
	var res: Array = await h.request_completed
	h.queue_free()
	var codigo: int = res[1]
	var txt: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var dados = JSON.parse_string(txt) if txt != "" else null
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "dados": null, "erro": "sem internet", "codigo": 0}
	if codigo >= 300:
		var msg := txt
		if dados is Dictionary:
			msg = str(dados.get("message", dados.get("msg", dados.get("error_description", txt))))
		return {"ok": false, "dados": dados, "erro": msg, "codigo": codigo}
	return {"ok": true, "dados": dados, "erro": "", "codigo": codigo}
