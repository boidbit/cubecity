extends CanvasLayer
# Story lab: a colour grade over the picture (under the subtitles), set by the episode's
# mood: warm for romance, cool and pale for sad, punchy for action, bright for comedy. A
# vignette darkens the corners, and closes in for dramatic moments (set_drama).

const GRADES := {
	# tint, saturation, contrast, lift, vignette
	"romantic": [Color(1.07, 0.99, 0.92), 1.12, 1.05, 0.01, 0.38],
	"happy": [Color(1.04, 1.02, 0.95), 1.18, 1.05, 0.02, 0.22],
	"funny": [Color(1.03, 1.02, 0.97), 1.2, 1.06, 0.01, 0.2],
	"cringe": [Color(1.05, 0.99, 1.0), 1.2, 1.04, 0.02, 0.22],
	"sad": [Color(0.9, 0.96, 1.1), 0.68, 0.96, -0.02, 0.5],
	"action": [Color(1.03, 1.0, 0.95), 1.15, 1.16, -0.01, 0.42],
	"twist": [Color(0.97, 1.0, 1.04), 0.92, 1.12, -0.01, 0.5],
	"drama": [Color(0.98, 0.99, 1.03), 0.95, 1.12, -0.01, 0.48],
}
const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 tint = vec3(1.0);
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform float lift = 0.0;
uniform float vignette = 0.3;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5 + lift;
	c *= tint;
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.0, 1.3);
	c *= 1.0 - vignette * smoothstep(0.28, 0.9, length(d));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

var mat: ShaderMaterial
var base_vignette := 0.3
var drama := 0.0
var drama_want := 0.0


func setup(mood: String) -> void:
	layer = 20                 # over the game, under the story's subtitles (30)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	add_child(rect)
	var g: Array = GRADES.get(mood, [Color(1.02, 1.0, 0.98), 1.08, 1.04, 0.0, 0.28])
	var tc: Color = g[0]
	mat.set_shader_parameter("tint", Vector3(tc.r, tc.g, tc.b))
	mat.set_shader_parameter("saturation", g[1])
	mat.set_shader_parameter("contrast", g[2])
	mat.set_shader_parameter("lift", g[3])
	base_vignette = g[4]
	mat.set_shader_parameter("vignette", base_vignette)


# 0..1: how much the corners close in (a shock zoom, a reaction held on a face).
func set_drama(amount: float) -> void:
	drama_want = clampf(amount, 0.0, 1.0)


func _process(dt: float) -> void:
	if mat == null:
		return
	drama = lerpf(drama, drama_want, 1.0 - exp(-4.0 * dt))
	mat.set_shader_parameter("vignette", base_vignette + drama * 0.35)
