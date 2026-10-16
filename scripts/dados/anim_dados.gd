@tool
class_name AnimDados
extends Resource
## Uma animação (folha de sprite) de um personagem.
## São os mesmos números do jogo.js: cols, quadros, cw, ch, ax, ay, fps.

@export var textura: Texture2D           ## a folha de sprite (PNG)
@export var cols: int = 8                ## quantos quadros por linha
@export var quadros: int = 1             ## quantos quadros no total
@export var cw: int = 0                  ## largura de cada quadro (pixels)
@export var ch: int = 0                  ## altura de cada quadro (pixels)
@export var ax: float = 0.0              ## ponto dos pés dentro do quadro (x)
@export var ay: float = 0.0              ## ponto dos pés dentro do quadro (y)
@export var fps: float = 10.0            ## quadros por segundo
@export var escala: float = 1.0          ## escala só desta animação (multiplica a do personagem)
@export var repetir: bool = true         ## true = loop; false = toca uma vez e para no último quadro
@export var olha_direita: bool = false   ## a folha foi desenhada olhando para a direita
@export var caido: float = 0.0           ## (morte) segundos parado no chão antes de sumir
@export var quadros_acao: PackedInt32Array = []  ## quadros em que o golpe/tiro acontece (contando do 0)
@export var quadros_som: PackedInt32Array = []   ## quadros em que toca o som da ação
@export var quadro_chao: int = -1        ## (morte) quadro em que bate no chão e a casa fica livre
@export var extra: Dictionary = {}       ## números especiais desta animação (segura, cortes...)

## Linhas da folha (calculado).
func linhas() -> int:
	return ceili(float(quadros) / max(cols, 1))

## Duração de um ciclo completo, em segundos.
func duracao() -> float:
	return quadros / max(fps, 0.01)

## Retângulo do quadro n dentro da folha.
func retangulo(n: int) -> Rect2:
	n = clampi(n, 0, quadros - 1)
	return Rect2((n % cols) * cw, (n / cols) * ch, cw, ch)

## Animação com ENTRADA + LOOP (extra.laco_de = índice onde o loop recomeça):
## toca 0..fim uma vez (a entrada no ritmo extra.fps_entrada) e depois repete laco_de..fim.
func tem_laco() -> bool:
	return extra.has("laco_de")

func quadro_laco(t: float) -> int:
	var laco := clampi(int(extra.laco_de), 0, quadros - 1)
	var fe := float(extra.get("fps_entrada", fps))
	var t_entrada := laco / maxf(fe, 0.01)
	if t < t_entrada:
		return mini(int(t * fe), laco)
	return laco + int((t - t_entrada) * fps) % maxi(1, quadros - laco)

## Qual quadro mostrar depois de t segundos de animação.
func quadro_em(t: float) -> int:
	var q := int(t * fps)
	if repetir:
		return q % quadros
	return mini(q, quadros - 1)
