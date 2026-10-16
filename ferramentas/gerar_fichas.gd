@tool
extends EditorScript
## GERAR FICHAS: cria as 14 fichas (.tres) dos personagens com os números do jogo.js.
## COMO USAR: abra este arquivo no editor de Script e aperte Ctrl+Shift+X (ou Arquivo > Executar).
## Rode só uma vez. Depois, ajuste as fichas direto no Inspetor (rodar de novo SOBRESCREVE as fichas).

const PASTA := "res://dados/personagens/"
const ASSETS := "res://assets/"

# ---------------------------------------------------------------------------------------------
# HEROES (GUERREIROS no jogo.js)
# ---------------------------------------------------------------------------------------------
const HEROES := {
	"elara": {
		"nome": "Elara", "descricao": "Medita e junta energia nas mãos: a cada ciclo solta 25 de energia",
		"comportamento": "gerador", "par": "esqueletoBlack",
		"custo": 50, "recarga": 7, "vida": 200, "gera_energia": 25, "escala": 0.57,
		"cores": ["#ffe2b8", "#b8541e"], "retrato_zoom": 0.5,
		"sons": {"gerar": ["Elara/som/energia", 0.6], "morrer": ["Elara/morrendo/som", 0.8]},
		"extra": {"energia_mao": {"quadro": 56, "x": 2, "y": -45}},
		"anims": {
			"parado": {"src": "Elara/energia/energia.png", "cols": 8, "quadros": 151, "cw": 128, "ch": 173, "ax": 60, "ay": 168, "fps": 12},
			"morrer": {"src": "Elara/morrendo/morrendo.png", "cols": 8, "quadros": 142, "cw": 338, "ch": 179, "ax": 161, "ay": 168, "fps": 24, "caido": 0.4, "repetir": false}
		}
	},
	"protetor": {
		"nome": "Protetor G", "nome_curto": "Protetor", "descricao": "Ergue o escudo e segura os monstros",
		"comportamento": "escudo", "par": "esqueletoProtetor",
		"custo": 75, "recarga": 18, "vida": 1000, "defesa": 0.6, "escala": 0.51,
		"cores": ["#dbe6fb", "#3f5fae"], "retrato_zoom": 0.5,
		"sons": {"morrer": ["Guerreiro Protetor/morrendo/som", 0.8], "escudo": ["Guerreiro Protetor/morrendo/som escudo quebrando", 0.8], "bloqueio": ["Guerreiro Protetor/som/bloqueio", 0.7]},
		"extra": {"alcance_escudo": 210, "trechos": {"parado": [1, 20], "levantar": [21, 85], "segurar": [86, 105], "abaixar": [106, 150]}},
		"anims": {
			"defender": {"src": "Guerreiro Protetor/defendendo/defendendo.png", "cols": 8, "quadros": 150, "cw": 200, "ch": 236, "ax": 109, "ay": 234, "fps": 30},
			"morrer": {"src": "Guerreiro Protetor/morrendo/morrendo.png", "cols": 8, "quadros": 150, "cw": 312, "ch": 201, "ax": 110, "ay": 194, "fps": 32, "caido": 0.8, "escala": 1.2, "repetir": false,
				"quadros_som": [100], "quadro_chao": 142, "extra": {"quadro_escudo": 10}}
		}
	},
	"nick": {
		"nome": "Nick", "descricao": "Cavaleiro: golpeia quem chega perto",
		"comportamento": "corpo_a_corpo", "par": "esqueleto",
		"custo": 100, "recarga": 8, "vida": 500, "dano": 45, "alcance": 105, "intervalo_ataque": 0.3, "escala": 0.50,
		"cores": ["#d3e0f7", "#6d8ccc"], "retrato_zoom": 0.62, "retrato_dy": 18,
		"sons": {"ataque": ["Nick/som/ataque", 0.8], "morrer": ["Nick/morrendo/som", 0.8]},
		"anims": {
			"parado": {"src": "Nick/parado/parado.png", "cols": 8, "quadros": 8, "cw": 311, "ch": 256, "ax": 78, "ay": 255, "fps": 6},
			"atacar": {"src": "Nick/atacando/atacando.png", "cols": 8, "quadros": 40, "cw": 311, "ch": 256, "ax": 78, "ay": 255, "fps": 16, "repetir": false,
				"quadros_acao": [18, 37], "quadros_som": [5, 14, 28, 37]},
			"morrer": {"src": "Nick/morrendo/morrendo.png", "cols": 8, "quadros": 19, "cw": 342, "ch": 260, "ax": 188, "ay": 255, "fps": 10, "caido": 1.2, "repetir": false}
		}
	},
	"arqueiro": {
		"nome": "Arqueiro", "descricao": "Atira flechas na linha",
		"comportamento": "atirador", "par": "esqueletoArqueiro",
		"custo": 125, "recarga": 7, "vida": 300, "dano": 30, "intervalo_ataque": 0.8, "escala": 0.41,
		"cores": ["#f3d0d0", "#b8434a"], "retrato_zoom": 0.84, "retrato_dy": 62,
		"sons": {"tiro": ["Planta/som/tiro", 0.5], "morrer": ["Arqueiro/caindo/som", 0.8], "morrer_reserva": ["Arqueiro/morrendo/som", 0.8]},
		"extra": {"flecha": {"dano": 30, "velocidade": 620, "saida_x": 53, "saida_y": -75}},
		"anims": {
			"parado": {"src": "Arqueiro/parado/parado.png", "cols": 8, "quadros": 12, "cw": 184, "ch": 294, "ax": 98, "ay": 293, "fps": 8},
			"preparar": {"src": "Arqueiro/preparando/preparando.png", "cols": 8, "quadros": 6, "cw": 201, "ch": 324, "ax": 104, "ay": 323, "fps": 12, "repetir": false, "extra": {"segura": 0.15}},
			"atacar": {"src": "Arqueiro/atacando/atacando.png", "cols": 8, "quadros": 8, "cw": 232, "ch": 300, "ax": 94, "ay": 298, "fps": 12, "repetir": false, "quadros_acao": [4]},
			"morrer": {"src": "Arqueiro/caindo/caindo.png", "cols": 8, "quadros": 151, "cw": 249, "ch": 197, "ax": 132, "ay": 195, "fps": 30, "caido": 0.8, "escala": 1.529, "repetir": false,
				"quadros_som": [84], "quadro_chao": 104}
		}
	},
	"mago": {
		"nome": "Mago", "descricao": "Lança uma esfera de energia que explode no inimigo",
		"comportamento": "mago", "par": "esqueletoMago",
		"custo": 175, "recarga": 10, "vida": 300, "dano": 70, "intervalo_ataque": 0.6, "escala": 0.62,
		"cores": ["#d4e3ff", "#2f4fa8"], "retrato_zoom": 0.5,
		"sons": {"magia": ["Mago/som/magia", 0.7], "impacto": ["Mago/som/explosao", 0.7], "morrer": ["Mago/morrendo/som", 0.8]},
		"extra": {"magia": {"dano": 70, "dano_area": 30, "raio": 75, "velocidade": 430, "saida_x": 37, "saida_y": -82},
			"brilho_cajado": {"x": -27, "y": -106, "raio": 20}},
		"anims": {
			"parado": {"src": "Mago/parado/parado.png", "cols": 8, "quadros": 12, "cw": 126, "ch": 201, "ax": 68, "ay": 199, "fps": 8},
			"atacar": {"src": "Mago/atacando/atacando.png", "cols": 8, "quadros": 151, "cw": 189, "ch": 197, "ax": 68, "ay": 195, "fps": 40, "repetir": false, "quadros_acao": [91]},
			"morrer": {"src": "Mago/morrendo/morrendo.png", "cols": 8, "quadros": 151, "cw": 380, "ch": 217, "ax": 191, "ay": 208, "fps": 32, "caido": 0.8, "repetir": false}
		}
	},
	"magoFogo": {
		"nome": "Mago de Fogo", "nome_curto": "Mago Fogo", "descricao": "Lança uma bola de fogo que explode em chamas",
		"comportamento": "mago", "par": "esqueletoFogo",
		"custo": 200, "recarga": 12, "vida": 300, "dano": 60, "intervalo_ataque": 0.6, "escala": 0.65,
		"cores": ["#ffd9b0", "#b8331c"], "retrato_zoom": 0.5,
		"sons": {"magia": ["Mago de Fogo/som/magia", 0.7], "impacto": ["Mago de Fogo/som/explosao", 0.8], "morrer": ["Mago de Fogo/morrendo/som", 0.8]},
		"extra": {"magia": {"estilo": "fogo", "dano": 60, "dano_area": 40, "raio": 90, "velocidade": 400, "saida_x": 50, "saida_y": -79},
			"brilho_cajado": {"x": -42, "y": -104, "raio": 16, "estilo": "fogo"}},
		"anims": {
			"parado": {"src": "Mago de Fogo/parado/parado.png", "cols": 8, "quadros": 24, "cw": 175, "ch": 191, "ax": 96, "ay": 188, "fps": 10},
			"atacar": {"src": "Mago de Fogo/atacando/atacando.png", "cols": 8, "quadros": 151, "cw": 339, "ch": 202, "ax": 181, "ay": 198, "fps": 40, "repetir": false, "quadros_acao": [103]},
			"morrer": {"src": "Mago de Fogo/morrendo/morrendo.png", "cols": 8, "quadros": 151, "cw": 348, "ch": 211, "ax": 168, "ay": 202, "fps": 32, "caido": 0.8, "repetir": false}
		}
	},
	"sentinela": {
		"nome": "Cavaleiro Sentinela", "nome_curto": "Sentinela", "descricao": "Gigante: golpeia, defende e crava a espada para erguer a terra na linha",
		"comportamento": "sentinela", "par": "esqueletoTita",
		"custo": 325, "recarga": 25, "vida": 1800, "dano": 60, "alcance": 150, "defesa": 0.7, "escala": 0.9,
		"cores": ["#d7e2f7", "#2b4a8f"], "retrato_zoom": 0.5,
		"sons": {"golpe": ["Cavaleiro Sentinela/som/golpe", 0.8], "terra": ["Cavaleiro Sentinela/som/terra", 0.9], "bloqueio": ["Cavaleiro Sentinela/som/escudo", 0.7], "morrer": ["Cavaleiro Sentinela/morrendo/som", 0.9]},
		"extra": {"quadros_defesa": [64, 92], "minimo_para_terra": 4, "dano_terra": 90, "quadro_impacto": 49, "velocidade_onda": 650, "recarga_terra": 6},
		"anims": {
			# Estas 3 folhas podem estar em 2 formatos; o gerador escolhe pela largura da imagem (variantes).
			"parado": {"src": "Cavaleiro Sentinela/em guarda/em_guarda.png", "grade": {"formato": [13, 12], "pes": [0.4960, 0.9769], "ref": 379, "ref_h": 216}, "quadros": 151, "fps": 24, "cols": 13, "cw": 379, "ch": 216, "ax": 188, "ay": 211,
				"variantes": [{"largura": 1872, "cols": 8, "cw": 234, "ch": 205, "ax": 131, "ay": 201}]},
			"atacar": {"src": "Cavaleiro Sentinela/atacando/atacando.png", "grade": {"formato": [13, 12], "pes": [0.4960, 0.9769], "ref": 379, "ref_h": 216}, "quadros": 151, "fps": 36, "cols": 8, "cw": 321, "ch": 216, "ax": 149, "ay": 213, "repetir": false, "quadros_acao": [43, 123],
				"variantes": [{"largura": 2568, "cols": 8, "cw": 321, "ch": 216, "ax": 149, "ay": 213}]},
			"especial": {"src": "Cavaleiro Sentinela/espada no chao/espada_no_chao.png", "grade": {"formato": [13, 12], "pes": [0.4960, 0.9769], "ref": 379, "ref_h": 216}, "quadros": 151, "fps": 34, "cols": 13, "cw": 379, "ch": 216, "ax": 188, "ay": 211, "repetir": false, "quadros_acao": [49],
				"variantes": [{"largura": 2488, "cols": 8, "cw": 311, "ch": 218, "ax": 156, "ay": 213}]},
			"morrer": {"src": "Cavaleiro Sentinela/morrendo/morrendo.png", "cols": 8, "quadros": 151, "cw": 327, "ch": 218, "ax": 170, "ay": 213, "fps": 36, "caido": 0.8, "repetir": false, "quadro_chao": 125}
		}
	},
}

# ---------------------------------------------------------------------------------------------
# MONSTERS (PERSONAGENS no jogo.js). Custo e recarga vêm do par (MODO_MONSTERS.par).
# ---------------------------------------------------------------------------------------------
const QUEDA_ESQUELETO := {"src": "Esqueleto/morrendo/morrendo.png", "cols": 8, "quadros": 19, "cw": 235, "ch": 195, "ax": 132, "ay": 183, "fps": 10, "caido": 1.2, "repetir": false, "olha_direita": true}

const MONSTERS := {
	"esqueletoBlack": {
		"nome": "Esqueleto Black", "nome_curto": "Esq. Black", "descricao": "Medita sentado e solta energia das mãos para os Monsters",
		"comportamento": "gerador", "par": "elara",
		"vida": 200, "dano": 0, "velocidade": 0, "gera_energia": 25, "escala": 0.5,
		"cores": ["#2b2433", "#c9e04a"], "cor_particulas": "#e8dfc8",
		"extra": {"energia_mao": {"quadro": 110, "x": 0, "y": -58}},
		"anims": {
			"parado": {"src": "Esqueleto Black/energia/energia.png", "cols": 8, "quadros": 120, "cw": 191, "ch": 206, "ax": 98, "ay": 205, "fps": 12, "olha_direita": true}
		}
	},
	"esqueleto": {
		"nome": "Esqueleto", "descricao": "Anda até o castelo e golpeia quem estiver na frente",
		"comportamento": "corpo_a_corpo", "par": "nick",
		"vida": 180, "dano": 25, "alcance": 60, "velocidade": 34, "escala": 0.56,
		"cores": ["#dfe5f0", "#6f7c99"], "cor_particulas": "#e8dfc8",
		"sons": {"aparecer": ["Esqueleto/som/esqueleto", 0.8], "atacar": ["Esqueleto/atacando/som", 0.7], "morrer": ["Esqueleto/morrendo/som", 0.8]},
		"anims": {
			# ATENÇÃO: esta folha é ENORME (quadros de 1212x1708). Refaça com quadros de ~280x390 e troque cw/ch/ax/ay e tire a escala.
			"parado": {"src": "Esqueleto/parado/parado.png", "cols": 8, "quadros": 24, "cw": 240, "ch": 335, "ax": 120, "ay": 325, "escala": 0.5962, "fps": 12, "olha_direita": true},
			"andar": {"src": "Esqueleto/andando/andando_1.png", "cols": 8, "quadros": 50, "cw": 1212, "ch": 1708, "ax": 635, "ay": 1666, "escala": 0.1138, "fps": 23.5, "olha_direita": true},
			"atacar": {"src": "Esqueleto/atacando/atacando.png", "cols": 8, "quadros": 25, "cw": 189, "ch": 193, "ax": 52, "ay": 189, "fps": 12, "olha_direita": true},
			"morrer": QUEDA_ESQUELETO
		}
	},
	"esqueletoFogo": {
		"nome": "Esqueleto de Fogo", "descricao": "Mais forte e resistente, seus golpes queimam",
		"comportamento": "corpo_a_corpo", "par": "magoFogo",
		"vida": 240, "dano": 35, "alcance": 60, "velocidade": 30, "escala": 0.47,
		"cores": ["#ffd79a", "#b8431a"], "cor_particulas": "#ff7a1e",
		"sons": {"aparecer": ["Esqueleto de Fogo/som/Esqueleto de fogo", 0.8], "ambiente": ["Esqueleto de Fogo/som/fogo", 0.5],
			"atacar": ["Esqueleto de Fogo/socando/som", 0.7], "morrer": ["Esqueleto de Fogo/caindo/som", 0.8]},
		"anims": {
			"andar": {"src": "Esqueleto de Fogo/andando/andando.png", "cols": 8, "quadros": 40, "cw": 175, "ch": 248, "ax": 85, "ay": 241, "fps": 15.2, "olha_direita": true},
			"atacar": {"src": "Esqueleto de Fogo/socando/esqueleto_de_fogo_socando.png", "cols": 8, "quadros": 60, "cw": 160, "ch": 236, "ax": 75, "ay": 233, "fps": 40, "olha_direita": true},
			"morrer": {"src": "Esqueleto de Fogo/caindo/caindo_esqueleto_de_fogo.png", "cols": 13, "quadros": 150, "cw": 474, "ch": 270, "ax": 236, "ay": 260, "fps": 24, "caido": 0.3, "repetir": false, "olha_direita": true}
		}
	},
	"esqueletoArqueiro": {
		"nome": "Esqueleto Arqueiro", "descricao": "Para de longe e atira flechas nos guerreiros",
		"comportamento": "atirador", "par": "arqueiro",
		"vida": 150, "dano": 20, "alcance": 360, "intervalo_ataque": 0.4, "velocidade": 26, "escala": 0.58,
		"cores": ["#dcebc9", "#5d7a48"], "cor_particulas": "#e8dfc8",
		"sons": {"aparecer": ["Esqueleto/som/esqueleto", 0.8], "tiro": ["Planta/som/tiro", 0.4], "morrer": ["Esqueleto/morrendo/som", 0.8]},
		"extra": {"flecha": {"dano": 20, "velocidade": 520, "saida_x": 45, "saida_y": -72}},
		"anims": {
			"andar": {"src": "Esqueleto Arqueiro/andando/andando.png", "cols": 8, "quadros": 120, "cw": 161, "ch": 190, "ax": 71, "ay": 188, "fps": 12, "olha_direita": true},
			"atacar": {"src": "Esqueleto Arqueiro/atirando/atirando.png", "cols": 8, "quadros": 151, "cw": 176, "ch": 202, "ax": 66, "ay": 200, "fps": 34, "repetir": false, "quadros_acao": [104], "olha_direita": true},
			"morrer": {"base": "QUEDA", "escala": 0.966}
		}
	},
	"esqueletoProtetor": {
		"nome": "Esqueleto Protetor", "descricao": "Anda de escudo erguido e bloqueia metade do dano",
		"comportamento": "escudo", "par": "protetor",
		"vida": 320, "dano": 20, "alcance": 60, "defesa": 0.5, "velocidade": 24, "escala": 0.61,
		"cores": ["#d9dfea", "#4b5a78"], "cor_particulas": "#e8dfc8",
		"sons": {"aparecer": ["Esqueleto/som/esqueleto", 0.8], "escudo": ["Esqueleto Protetor/som/escudo", 0.8], "atacar": ["Esqueleto Protetor/som/golpe", 0.7], "morrer": ["Esqueleto/morrendo/som", 0.8]},
		"extra": {"escudo": {"x": 15, "y": -52, "raio": 26}},
		"anims": {
			"andar": {"src": "Esqueleto Protetor/andando/andando.png", "cols": 8, "quadros": 35, "cw": 135, "ch": 189, "ax": 76, "ay": 188, "fps": 16, "olha_direita": true},
			"atacar": {"src": "Esqueleto Protetor/socando/socando.png", "cols": 8, "quadros": 151, "cw": 229, "ch": 190, "ax": 88, "ay": 188, "fps": 44, "repetir": false, "quadros_acao": [52], "olha_direita": true},
			"morrer": {"base": "QUEDA", "escala": 0.918}
		}
	},
	"esqueletoMago": {
		"nome": "Esqueleto Mago", "descricao": "Para de longe, lança magia e invoca esqueletos do chão",
		"comportamento": "necro", "par": "mago",
		"vida": 300, "dano": 35, "alcance": 520, "intervalo_ataque": 0.8, "velocidade": 22, "escala": 0.58,
		"cores": ["#d8ccf5", "#4a2f7a"], "cor_particulas": "#e8dfc8",
		"sons": {"aparecer": ["Esqueleto/som/esqueleto", 0.8], "morrer": ["Esqueleto/morrendo/som", 0.8], "magia": ["Esqueleto Mago/som/magia", 0.7],
			"invocar": ["Esqueleto Mago/som/invocar", 0.8], "impacto": ["Esqueleto Mago/som/explosao", 0.6]},
		"extra": {"para_na_coluna": 7, "tiros_para_invocar": 5, "invoca": "esqueleto", "quantos": 3, "velocidade_magia": 380,
			"saida_x": 53, "saida_y": -59, "estilo": "sombra", "brilho_cajado": {"x": -37, "y": -93, "raio": 14}},
		"anims": {
			"parado": {"src": "Esqueleto Mago/parado/parado.png", "cols": 8, "quadros": 12, "cw": 150, "ch": 201, "ax": 57, "ay": 199, "fps": 8, "olha_direita": true},
			"andar": {"src": "Esqueleto Mago/andando/andando.png", "cols": 8, "quadros": 82, "cw": 200, "ch": 206, "ax": 91, "ay": 204, "fps": 20, "olha_direita": true},
			"atacar": {"src": "Esqueleto Mago/atirando/atirando.png", "cols": 8, "quadros": 151, "cw": 299, "ch": 204, "ax": 160, "ay": 200, "fps": 40, "repetir": false, "quadros_acao": [94], "olha_direita": true},
			"morrer": {"base": "QUEDA", "escala": 0.966}
		}
	},
	"esqueletoTita": {
		"nome": "Esqueleto Titã", "nome_curto": "Titã", "descricao": "Gigante: soca o chão e ergue ossos na linha, e luta com quem chega perto",
		"comportamento": "tita", "par": "sentinela",
		"vida": 1500, "dano": 70, "alcance": 120, "velocidade": 30, "escala": 0.89, "barra_y": 190, "dano_castelo": 40,
		"cores": ["#e6ddc8", "#5a4636"], "cor_particulas": "#e8dfc8",
		"sons": {"aparecer": ["Esqueleto/som/esqueleto", 0.9], "golpe": ["Esqueleto Tita/som/soco", 0.9], "ossos": ["Esqueleto Tita/som/ossos", 0.9],
			"passos": ["Esqueleto Tita/som/passo", 0.5], "morrer": ["Esqueleto/morrendo/som", 0.9]},
		"extra": {"minimo_ossos": 4, "dano_ossos": 80, "quadros_impacto": [42, 115], "velocidade_ossos": 600, "recarga_ossos": 7, "passos_por_ciclo": 6},
		"anims": {
			"andar": {"src": "Esqueleto Tita/andando/andando.png", "cols": 8, "quadros": 126, "cw": 167, "ch": 205, "ax": 93, "ay": 203, "fps": 11, "olha_direita": true},
			"parado": {"src": "Esqueleto Tita/parado/parado.png", "cols": 5, "quadros": 20, "cw": 190, "ch": 216, "ax": 95, "ay": 212, "fps": 10, "olha_direita": true},
			"especial": {"src": "Esqueleto Tita/socando no chao/socando_no_chao.png", "cols": 8, "quadros": 151, "cw": 160, "ch": 181, "ax": 79, "ay": 173, "fps": 36, "escala": 1.154, "repetir": false, "quadros_acao": [42, 115], "olha_direita": true},
			"atacar": {"src": "Esqueleto Tita/lutando/lutando.png", "cols": 8, "quadros": 151, "cw": 258, "ch": 184, "ax": 93, "ay": 180, "fps": 38, "escala": 1.154, "repetir": false, "quadros_acao": [39, 104], "olha_direita": true},
			"morrer": {"base": "QUEDA", "fps": 9, "caido": 1.4, "escala": 1.07}
		}
	},
}

var avisos: Array[String] = []

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(PASTA)
	avisos.clear()
	var n := 0
	for id in HEROES:
		n += _salvar(id, HEROES[id], "heroes", {})
	for id in MONSTERS:
		var par: Dictionary = HEROES.get(MONSTERS[id].par, {})
		n += _salvar(id, MONSTERS[id], "monsters", par)
	EditorInterface.get_resource_filesystem().scan()
	print("=== GERAR FICHAS: %d fichas salvas em %s ===" % [n, PASTA])
	for a in avisos:
		push_warning(a)
	if avisos.is_empty():
		print("Tudo certo: todas as imagens foram encontradas.")

func _salvar(id: String, d: Dictionary, lado: String, par: Dictionary) -> int:
	var p := PersonagemDados.new()
	p.id = id
	p.lado = lado
	p.nome = d.nome
	p.nome_curto = d.get("nome_curto", "")
	p.descricao = d.get("descricao", "")
	p.par = d.get("par", "")
	p.comportamento = d.get("comportamento", "corpo_a_corpo")
	# monstros usam o custo/recarga do herói par (como no jogo.js)
	p.custo = d.get("custo", par.get("custo", 100))
	p.recarga = d.get("recarga", par.get("recarga", 5))
	p.vida = d.get("vida", 100)
	p.dano = d.get("dano", 0)
	p.alcance = d.get("alcance", 0.0)
	p.intervalo_ataque = d.get("intervalo_ataque", 1.0)
	p.velocidade = d.get("velocidade", 0.0)
	p.defesa = d.get("defesa", 0.0)
	p.dano_castelo = d.get("dano_castelo", 10)
	p.gera_energia = d.get("gera_energia", 0)
	p.escala = d.get("escala", 0.5)
	p.retrato_zoom = d.get("retrato_zoom", 0.5)
	p.retrato_dy = d.get("retrato_dy", 0.0)
	p.barra_y = d.get("barra_y", 0.0)
	var cores := PackedColorArray()
	for c in d.get("cores", ["#ffffff", "#888888"]):
		cores.append(Color(c))
	p.cores = cores
	p.cor_particulas = Color(d.get("cor_particulas", "#ffffff"))
	for k in d.get("sons", {}):
		p.sons[k] = d.sons[k][0]
		p.volumes[k] = float(d.sons[k][1])
	p.extra = d.get("extra", {}).duplicate(true)
	for nome_anim in d.anims:
		var a := _anim(id, nome_anim, d.anims[nome_anim])
		if a:
			p.anims[nome_anim] = a
	var caminho := PASTA + id + ".tres"
	var err := ResourceSaver.save(p, caminho)
	if err != OK:
		push_error("Não deu para salvar %s (erro %d)" % [caminho, err])
		return 0
	return 1

func _anim(id: String, nome_anim: String, spec: Dictionary) -> AnimDados:
	if spec.get("base", "") == "QUEDA":                  # reaproveita a queda do Esqueleto comum
		var s := QUEDA_ESQUELETO.duplicate(true)
		for k in spec:
			if k != "base":
				s[k] = spec[k]
		spec = s
	var a := AnimDados.new()
	var caminho: String = ASSETS + spec.src
	if ResourceLoader.exists(caminho):
		a.textura = load(caminho)
	else:
		avisos.append("%s / %s: não achei a imagem %s" % [id, nome_anim, caminho])
	a.cols = spec.get("cols", 8)
	a.quadros = spec.get("quadros", 1)
	a.cw = spec.get("cw", 0)
	a.ch = spec.get("ch", 0)
	a.ax = spec.get("ax", 0)
	a.ay = spec.get("ay", 0)
	# folhas com dois formatos possíveis: escolhe pela largura real da imagem
	if a.textura and spec.has("variantes"):
		for v in spec.variantes:
			if a.textura.get_width() == int(v.largura):
				a.cols = v.cols; a.cw = v.cw; a.ch = v.ch; a.ax = v.ax; a.ay = v.ay
	# GRADE 13x12 (folhas originais do Cavaleiro Sentinela): calcula o quadro pelo tamanho real da imagem
	if a.textura and spec.has("grade"):
		var gr: Dictionary = spec.grade
		var w := a.textura.get_width()
		var h := a.textura.get_height()
		var fc: int = gr.formato[0]
		var fl: int = gr.formato[1]
		if abs(w - fc * int(w / fc)) <= 1 and abs(float(w) / fc / (float(h) / fl) - float(gr.ref) / float(gr.ref_h)) < 0.08:
			a.cols = fc
			a.cw = int(w / fc)
			a.ch = int(h / fl)
			a.ax = gr.pes[0] * a.cw
			a.ay = gr.pes[1] * a.ch
	a.fps = spec.get("fps", 10.0)
	a.escala = spec.get("escala", 1.0)
	a.repetir = spec.get("repetir", true)
	a.olha_direita = spec.get("olha_direita", false)
	a.caido = spec.get("caido", 0.0)
	a.quadros_acao = PackedInt32Array(spec.get("quadros_acao", []))
	a.quadros_som = PackedInt32Array(spec.get("quadros_som", []))
	a.quadro_chao = spec.get("quadro_chao", -1)
	a.extra = spec.get("extra", {}).duplicate(true)
	# confere se a folha tem o tamanho esperado
	if a.textura:
		var esperado_w := a.cols * a.cw
		var esperado_h := a.linhas() * a.ch
		var w := a.textura.get_width()
		var h := a.textura.get_height()
		if w < esperado_w - 2 or h < esperado_h - 2:
			avisos.append("%s / %s: a imagem tem %dx%d, mas os números pedem pelo menos %dx%d. Confira cols/cw/ch." % [id, nome_anim, w, h, esperado_w, esperado_h])
		if w > 8192 or h > 8192:
			avisos.append("%s / %s: imagem de %dx%d é GRANDE DEMAIS: muitos celulares não abrem. Diminua essa folha." % [id, nome_anim, w, h])
		elif w > 4096 or h > 4096:
			avisos.append("%s / %s: imagem de %dx%d passa de 4096: celulares mais fracos podem não abrir. Vale diminuir." % [id, nome_anim, w, h])
	return a
