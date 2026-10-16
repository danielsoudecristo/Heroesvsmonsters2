extends Node
## CONTA: login com Google pelo Supabase (o mesmo projeto do site) e chamadas ao servidor.
## Autoload com o nome "Conta". Uso: await Conta.chamar("meu_perfil")
##
## LOGIN SEM PLUGIN (funciona no PC e no celular):
## 1) o jogo cria um código secreto e abre o navegador em app-login.html?godot=CODIGO
## 2) a pessoa entra com o Google; a página entrega a sessão para o código (supabase/6_login_godot.sql)
## 3) o jogo fica perguntando pelo código; quando chega, já está logado.
## A sessão fica salva neste aparelho (criptografada): não precisa entrar toda vez.
## Só a chave PÚBLICA fica no jogo. NUNCA coloque a chave "secret" / "service_role" aqui.

const SUPABASE := "https://wrhrtzesfhiwydtmbezq.supabase.co"
const CHAVE := "sb_publishable_LzAJ7FOOCOBJWr8DwuyvVg_xsfKCDTP"
const PONTE := "https://heroes-vs-monsters.pages.dev/app-login.html"
const ARQUIVO := "user://conta.cfg"
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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_environment("HVM_SUPABASE") != "":
		_base = OS.get_environment("HVM_SUPABASE")
	_carregar()
	if _refresh != "":
		status = "carregando"
		_renovar_e_conectar()

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
	var c := Crypto.new()
	_codigo = c.generate_random_bytes(24).hex_encode()
	esperando_login = true
	_espera_t = 0.0
	_pergunta_t = 1.0
	status = "entrando"
	if OS.get_environment("HVM_SUPABASE") == "":
		OS.shell_open(PONTE + "?godot=" + _codigo)
	mudou.emit()

func cancelar_login() -> void:
	esperando_login = false
	_codigo = ""
	status = "convidado" if not logado() else "conectado"
	mudou.emit()

func _process(dt: float) -> void:
	if not esperando_login:
		return
	_espera_t += dt
	_pergunta_t -= dt
	if _espera_t > ESPERA_LOGIN:
		cancelar_login()
		erro.emit("O login demorou demais. Tente de novo.")
		return
	if _pergunta_t <= 0.0 and not _renovando:
		_pergunta_t = PERGUNTA_CADA
		_perguntar_login()

func _perguntar_login() -> void:
	_renovando = true
	var r: Dictionary = await _http(HTTPClient.METHOD_POST, "/rest/v1/rpc/pegar_login_godot", {"p_codigo": _codigo}, false)
	_renovando = false
	if not esperando_login:
		return
	if r.ok and r.dados is String and r.dados != "":
		esperando_login = false
		_codigo = ""
		_refresh = r.dados
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
	var rp: Dictionary = await ler("personagens_jogador?select=personagem,nivel")
	if rp.ok and rp.dados is Array:
		var nv := {}
		for linha in rp.dados:
			nv[str(linha.personagem)] = int(linha.nivel)
		Perfil.niveis = nv
	status = "conectado"
	mudou.emit()

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
