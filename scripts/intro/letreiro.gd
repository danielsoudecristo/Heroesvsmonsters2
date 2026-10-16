class_name Letreiro
extends Node2D
## LETREIRO CARTOON: uma palavra grossa com contorno escuro, sombra e degradê (ouro, verde ou prata),
## igual ao logo do site. O degradê e o brilho que passa são feitos por um shader pequenininho.
## O texto fica centralizado no x = 0 e a linha de base no y = 0.

enum Cor { OURO, VERDE, PRATA }

@export var texto := "Heroes"
@export var tamanho := 86
@export var cor: Cor = Cor.OURO
@export var contorno := 15                       ## grossura do contorno (px)
@export var cor_contorno := Color("1b0f06")
@export var sombra := 6.0                        ## sombra dura embaixo (px)

## posição x (no próprio letreiro) da faixa de brilho que atravessa as letras; -9999 = sem brilho
var brilho := -9999.0:
	set(v):
		brilho = v
		if _mat:
			_mat.set_shader_parameter("brilho", v)

var fonte: Font
var _mat: ShaderMaterial
static var _shader: Shader

# cores "marca": o shader troca estas cores pelo degradê
const MARCAS := [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1)]

const CODIGO := """
shader_type canvas_item;
uniform float topo = -60.0;
uniform float base = 10.0;
uniform float brilho = -9999.0;
uniform float largura_brilho = 30.0;
varying vec2 lp;
void vertex() { lp = VERTEX; }
vec3 rampa(float t, vec3 a, vec3 b, vec3 c, vec3 d, float pb, float pc) {
	if (t < 0.08) return a;
	if (t < pb) return mix(a, b, (t - 0.08) / (pb - 0.08));
	if (t < pc) return mix(b, c, (t - pb) / (pc - pb));
	return mix(c, d, (t - pc) / (1.0 - pc));
}
void fragment() {
	vec4 c = COLOR;
	float t = clamp((lp.y - topo) / (base - topo), 0.0, 1.0);
	bool marca = true;
	vec3 g;
	if (c.r > 0.9 && c.g < 0.1 && c.b < 0.1)
		g = rampa(t, vec3(1.0, 0.953, 0.69), vec3(0.965, 0.765, 0.263), vec3(0.906, 0.604, 0.11), vec3(0.722, 0.455, 0.059), 0.48, 0.62);
	else if (c.g > 0.9 && c.r < 0.1 && c.b < 0.1)
		g = rampa(t, vec3(0.918, 1.0, 0.69), vec3(0.545, 0.878, 0.235), vec3(0.345, 0.702, 0.133), vec3(0.184, 0.49, 0.086), 0.48, 0.64);
	else if (c.b > 0.9 && c.r < 0.1 && c.g < 0.1)
		g = mix(vec3(1.0), vec3(0.79, 0.83, 0.91), t);
	else
		marca = false;
	if (marca) {
		float d = abs(lp.x + lp.y * 0.36 - brilho);
		g = mix(g, vec3(1.0), (1.0 - smoothstep(0.0, largura_brilho, d)) * 0.8);
		c.rgb = g;
	}
	COLOR = c;
}
"""

func _ready() -> void:
	if fonte == null:
		fonte = ThemeDB.fallback_font
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODIGO
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	material = _mat
	_mat.set_shader_parameter("topo", -fonte.get_ascent(tamanho) * 0.92)
	_mat.set_shader_parameter("base", fonte.get_descent(tamanho) * 0.4)
	_mat.set_shader_parameter("largura_brilho", tamanho * 0.4)
	_mat.set_shader_parameter("brilho", brilho)

func largura() -> float:
	return fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho).x

func _draw() -> void:
	var p := Vector2(-largura() / 2.0, 0)
	# sombra macia + sombra dura + contorno + letra (a cor marca vira degradê no shader)
	draw_string_outline(fonte, p + Vector2(0, sombra + 5), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, contorno + 8, Color(0, 0, 0, 0.28))
	draw_string_outline(fonte, p + Vector2(0, sombra), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, contorno, Color(cor_contorno, 0.85))
	draw_string_outline(fonte, p, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, contorno, cor_contorno)
	draw_string(fonte, p, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, MARCAS[cor])
