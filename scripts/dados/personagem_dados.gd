@tool
class_name PersonagemDados
extends Resource
## FICHA DE UM PERSONAGEM.
## Para criar o personagem 101: duplique uma ficha em res://dados/personagens/, troque os números
## e as imagens no Inspetor. Não precisa programar nada (a não ser que ele tenha um poder novo).

@export_group("Identidade")
@export var id: String = ""                       ## nome interno, sem espaço (ex.: "nick")
@export var nome: String = ""                     ## nome que aparece no jogo
@export var nome_curto: String = ""               ## nome no card (se vazio, usa o nome)
@export_multiline var descricao: String = ""
@export_enum("heroes", "monsters") var lado: String = "heroes"
@export var par: String = ""                      ## personagem equivalente do outro lado (ex.: nick <-> esqueleto)
@export var ativo: bool = true                    ## false = fica fora da barra (como o Cardo e a Rocha hoje)

@export_group("Comportamento")
## Qual "cérebro" o personagem usa na arena (parte 2).
@export_enum("gerador", "corpo_a_corpo", "atirador", "escudo", "mago", "sentinela", "tita", "necro", "bombardeiro", "golem", "darian", "mistico", "aura") var comportamento: String = "corpo_a_corpo"

@export_group("Custo na partida")
@export var custo: int = 100                      ## energia para colocar
@export var recarga: float = 5.0                  ## segundos até poder colocar de novo
@export var quantidade_max: int = 0               ## 0 = sem limite
@export var inicio: float = 0.0                   ## segundos até o card liberar no começo da partida
@export var desbloqueio_trofeus: int = 0          ## troféus mínimos para o card aparecer (0 = sempre libero)

@export_group("Atributos (nível 1)")
@export var vida: int = 100
@export var dano: int = 0
@export var alcance: float = 0.0                  ## pixels
@export var intervalo_ataque: float = 1.0         ## pausa entre ataques (segundos)
@export var velocidade: float = 0.0               ## pixels por segundo andando (0 = parado)
@export_range(0.0, 0.95) var defesa: float = 0.0  ## parte do dano bloqueada (0.6 = bloqueia 60%)
@export var dano_castelo: int = 10                ## (monstros) dano ao invadir o castelo
@export var gera_energia: int = 0                 ## (geradores) energia solta a cada ciclo

@export_group("Visual")
@export var escala: float = 0.5                   ## tamanho no campo
@export var cores: PackedColorArray = [Color.WHITE, Color.GRAY]  ## fundo do retrato no card
@export var cor_particulas: Color = Color.WHITE
@export var retrato_zoom: float = 0.5
@export var retrato_dy: float = 0.0
@export var barra_y: float = 0.0                  ## altura da barra de vida (0 = automática)
## Animações por nome: parado, andar, atacar, morrer, preparar, especial...
@export var anims: Dictionary[String, AnimDados] = {}

@export_group("Sons")
## Caminho sem extensão, a partir de res://assets/ (ex.: "Nick/som/ataque"). O jogo acha .mp3/.wav/.ogg.
@export var sons: Dictionary[String, String] = {}
@export var volumes: Dictionary[String, float] = {}

@export_group("Poderes")
## Números especiais de cada comportamento (flecha, magia, terra, ossos, invocação...).
@export var extra: Dictionary = {}

func nome_card() -> String:
	return nome_curto if nome_curto != "" else nome

func anim(nome_anim: String) -> AnimDados:
	return anims.get(nome_anim)

## Primeira animação que existir entre as opções (ex.: "parado", "andar").
func anim_qualquer(opcoes: Array[String]) -> AnimDados:
	for o in opcoes:
		if anims.has(o) and anims[o].textura:
			return anims[o]
	return null

## Atributos com o bônus de nível da conta (Progressao).
func vida_no_nivel(nivel: int) -> int:
	return roundi(vida * Progressao.multiplicador(nivel))

func dano_no_nivel(nivel: int) -> int:
	return roundi(dano * Progressao.multiplicador(nivel))
