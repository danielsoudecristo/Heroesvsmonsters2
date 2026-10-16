class_name RedePvp
extends Node
## CANAL AO VIVO DA PARTIDA ONLINE (Supabase Realtime, "broadcast"), sem plugin.
## É o mesmo canal "pvp:<sala>" que o site usa: WebSocket + protocolo Phoenix.
## Os dois aparelhos só trocam as AÇÕES (lockstep). Quem simula a partida é a arena_pvp.gd.
##
## Uso:
##   var c := RedePvp.new(); add_child(c)
##   c.chegou.connect(func(m): ...)
##   c.abrir(Conta.SUPABASE, Conta.CHAVE, id_da_sala, token)
##   c.enviar({"tipo": "turno", ...})
##   c.fechar()
## Se a internet piscar, ele reconecta sozinho e entra de novo na sala.

signal conectou                         ## entrou na sala (também depois de reconectar)
signal chegou(m: Dictionary)            ## mensagem do adversário
signal caiu                             ## perdeu a conexão (vai tentar de novo)

const BATIDA := 20.0                    ## "heartbeat" do Phoenix (o servidor derruba sem ele em ~60 s)
const ESPERA_VOLTAR := [0.5, 1.0, 2.0, 3.0, 5.0]   ## espera entre as tentativas de reconectar
const MAX_FILA := 60                    ## mensagens guardadas enquanto está sem conexão

var pronto := false                     ## true = dentro da sala, pode mandar
var topico := ""
var _url := ""
var _token := ""
var _ws: WebSocketPeer
var _ref := 0
var _join_ref := ""
var _batida_t := 0.0
var _estado_ant := -1
var _tentativa := 0
var _voltar_t := -1.0
var _fila: Array = []
var _fechado := false

func abrir(base: String, chave: String, sala: String, token: String) -> void:
	topico = "realtime:pvp:" + sala
	_token = token
	_url = base.replace("https://", "wss://").replace("http://", "ws://") + "/realtime/v1/websocket?apikey=" + chave + "&vsn=1.0.0"
	_fechado = false
	_conectar()

func trocar_token(token: String) -> void:
	_token = token
	if pronto:
		_mandar(topico, "access_token", {"access_token": token})

func enviar(m: Dictionary) -> void:
	if pronto:
		_mandar(topico, "broadcast", {"type": "broadcast", "event": "m", "payload": m})
	elif _fila.size() < MAX_FILA:
		_fila.append(m)

func fechar() -> void:
	if _fechado:
		return
	_fechado = true
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if pronto:
			_mandar(topico, "phx_leave", {})
		_ws.close(1000, "fim")
	pronto = false

# ------------------------------------------------------------------ conexão
func _conectar() -> void:
	pronto = false
	_estado_ant = -1
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 18
	_ws.outbound_buffer_size = 1 << 18
	_ws.heartbeat_interval = 0.0
	if _ws.connect_to_url(_url) != OK:
		_agendar_volta()

func _agendar_volta() -> void:
	if _fechado:
		return
	pronto = false
	_voltar_t = ESPERA_VOLTAR[mini(_tentativa, ESPERA_VOLTAR.size() - 1)]
	_tentativa += 1

func _process(dt: float) -> void:
	if _voltar_t >= 0.0:
		_voltar_t -= dt
		if _voltar_t < 0.0:
			_conectar()
		return
	if _ws == null:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if _estado_ant != WebSocketPeer.STATE_OPEN:
			_entrar_na_sala()
		while _ws.get_available_packet_count() > 0:
			_receber(_ws.get_packet().get_string_from_utf8())
		_batida_t -= dt
		if _batida_t <= 0.0:
			_batida_t = BATIDA
			_mandar("phoenix", "heartbeat", {})
	elif st == WebSocketPeer.STATE_CLOSED and _estado_ant != WebSocketPeer.STATE_CLOSED:
		var estava := pronto
		pronto = false
		if not _fechado:
			if estava:
				caiu.emit()
			_agendar_volta()
	_estado_ant = st

func _entrar_na_sala() -> void:
	_batida_t = BATIDA
	_ref += 1
	_join_ref = str(_ref)
	var cfg := {"config": {"broadcast": {"self": false, "ack": false}, "presence": {"key": "", "enabled": false},
		"postgres_changes": [], "private": false}}
	if _token != "":
		cfg["access_token"] = _token
	_ws.send_text(JSON.stringify({"topic": topico, "event": "phx_join", "payload": cfg, "ref": _join_ref, "join_ref": _join_ref}))

func _mandar(top: String, evento: String, payload: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_ref += 1
	var msg := {"topic": top, "event": evento, "payload": payload, "ref": str(_ref)}
	if top == topico:
		msg["join_ref"] = _join_ref
	_ws.send_text(JSON.stringify(msg))

func _receber(txt: String) -> void:
	var m = JSON.parse_string(txt)
	if not (m is Dictionary):
		return
	var evento: String = str(m.get("event", ""))
	if str(m.get("topic", "")) != topico:
		return                                          # (respostas do heartbeat)
	var pl = m.get("payload", {})
	match evento:
		"broadcast":
			if pl is Dictionary and pl.get("payload") is Dictionary:
				chegou.emit(pl.payload)
		"phx_reply":
			if str(m.get("ref", "")) == _join_ref and pl is Dictionary:
				if str(pl.get("status", "")) == "ok":
					pronto = true
					_tentativa = 0
					var guardadas := _fila
					_fila = []
					for g in guardadas:
						enviar(g)
					conectou.emit()
				else:
					push_warning("RedePvp: não entrou na sala: %s" % JSON.stringify(pl))
					_ws.close()
		"phx_error", "phx_close":
			if not _fechado:
				pronto = false
				_ws.close()
