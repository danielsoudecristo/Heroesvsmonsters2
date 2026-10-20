extends Node
## SONS: toca efeitos com poucos "tocadores" reaproveitados (leve no celular).
## Autoload com o nome "Sons". Uso: Sons.tocar("Nick/som/ataque", 0.8)

const TOCADORES := 16                    ## quantos sons ao mesmo tempo, no máximo
const MESMO_SOM_INTERVALO := 0.06        ## o mesmo som não toca duas vezes em menos de 60 ms (evita barulho)
const EXTENSOES := ["mp3", "ogg", "wav"]

const MUSICA := "som game/game"         ## música de fundo (res://assets/som game/game.mp3), toca sem parar
const MUSICA_VOLUME := 0.45

var ligado := true:
	set(v):
		ligado = v
		_atualizar_musica()
var _musica: AudioStreamPlayer
var _tocadores: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}              # caminho -> AudioStream (ou null se não existe)
var _ultimo: Dictionary = {}             # caminho -> tempo da última vez
var _proximo := 0

func _ready() -> void:
	for i in TOCADORES:
		var a := AudioStreamPlayer.new()
		add_child(a)
		_tocadores.append(a)
	_musica = AudioStreamPlayer.new()
	_musica.volume_db = linear_to_db(MUSICA_VOLUME)
	add_child(_musica)
	var m := carregar(MUSICA)
	if m:
		if "loop" in m:
			m.loop = true                        # repete sem parar
		_musica.stream = m
	_atualizar_musica()

func _atualizar_musica() -> void:
	if _musica == null or _musica.stream == null:
		return
	if ligado and not _musica.playing:
		_musica.play()
	elif not ligado and _musica.playing:
		_musica.stop()

func carregar(caminho: String) -> AudioStream:
	if caminho == "":
		return null
	if _cache.has(caminho):
		return _cache[caminho]
	var s: AudioStream = null
	for nome in [caminho, caminho.replace("_", " ")]:     # (aceita "proximo_nivel" e "proximo nivel")
		for ext in EXTENSOES:
			var c := "res://assets/%s.%s" % [nome, ext]
			if ResourceLoader.exists(c):
				s = load(c)
				break
		if s:
			break
	if s == null and caminho == "Jogo/som/energia":
		s = _som_energia()                    # sem arquivo: o jogo cria o som sozinho
	if s == null and caminho == "Jogo/som/terra":
		s = carregar("Jogo/som/colocar")      # (sem terra.mp3: colocar.mp3 ou o "tum" feito pelo jogo)
	if s == null and caminho == "Jogo/som/colocar":
		s = _som_colocar()                    # sem arquivo: "tum" do personagem batendo na terra
	_cache[caminho] = s
	return s

func tocar(caminho: String, volume := 1.0) -> void:
	if not ligado or caminho == "":
		return
	var agora := Time.get_ticks_msec() / 1000.0
	if agora - _ultimo.get(caminho, -1.0) < MESMO_SOM_INTERVALO:
		return
	var s := carregar(caminho)
	if s == null:
		return
	_ultimo[caminho] = agora
	var a := _tocadores[_proximo]
	_proximo = (_proximo + 1) % TOCADORES
	a.stream = s
	a.volume_db = linear_to_db(clampf(volume, 0.01, 1.0))
	a.play()

## Toca o som de um personagem pelo nome (ex.: "morrer"), com o volume da ficha.
func do_personagem(p: PersonagemDados, nome: String) -> void:
	if p and p.sons.has(nome):
		tocar(p.sons[nome], p.volumes.get(nome, 0.8))

## Som de COLOCAR o personagem: "tum" grave dele batendo na terra + um pouco de poeira (feito pelo jogo, sem arquivo).
## Para trocar por outro, é só pôr um arquivo em assets/Jogo/som/terra.mp3 (ou .wav/.ogg).
func _som_colocar() -> AudioStreamWAV:
	const TAXA := 22050
	var dur := 0.32
	var n := int(dur * TAXA)
	var b := PackedByteArray()
	b.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var fase := 0.0
	var poeira := 0.0
	for i in n:
		var t := float(i) / TAXA
		var f := 45.0 + 110.0 * exp(-t * 22.0)          # o "tum" desce de ~155 Hz para 45 Hz
		fase += TAU * f / TAXA
		var tum := sin(fase) * minf(1.0, t * 900.0) * exp(-t * 13.0)
		poeira = poeira * 0.82 + rng.randf_range(-1.0, 1.0) * 0.18   # ruído abafado (terra)
		var v := tum * 0.95 + poeira * 1.6 * exp(-t * 26.0)
		b.encode_s16(i * 2, int(clampf(v * 0.85, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = TAXA
	w.stereo = false
	w.data = b
	return w

## Som de pegar energia: "plim-plim" brilhante subindo (feito pelo próprio jogo, sem arquivo).
## Para trocar por outro, é só pôr um arquivo em assets/Jogo/som/energia.mp3 (ou .wav/.ogg).
func _som_energia() -> AudioStreamWAV:
	const TAXA := 22050
	var notas := [[0.0, 1318.5], [0.07, 1975.5], [0.14, 2637.0]]   # Mi, Si, Mi (subindo)
	var dur := 0.55
	var n := int(dur * TAXA)
	var b := PackedByteArray()
	b.resize(n * 2)
	for i in n:
		var t := float(i) / TAXA
		var v := 0.0
		for nota in notas:
			var dt: float = t - nota[0]
			if dt < 0.0:
				continue
			var f: float = nota[1]
			var env := minf(1.0, dt * 400.0) * exp(-dt * 9.0)
			v += (sin(TAU * f * dt) + 0.35 * sin(TAU * f * 2.0 * dt) + 0.15 * sin(TAU * f * 3.0 * dt)) * env
		v += sin(TAU * 5274.0 * t) * exp(-t * 14.0) * 0.12 * (0.5 + 0.5 * sin(TAU * 38.0 * t))   # brilhinho
		b.encode_s16(i * 2, int(clampf(v * 0.32, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = TAXA
	w.stereo = false
	w.data = b
	return w
