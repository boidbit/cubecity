class_name Shaders
extends RefCounted
# All shader code lives here as strings. No external textures needed.

static var _cache := {}


# One Shader per source, shared by every material that uses it, so a car that
# spawns mid-game does not trigger a fresh shader compile (a stutter on phones).
static func get_shader(code: String) -> Shader:
	if not _cache.has(code):
		var sh := Shader.new()
		sh.code = code
		_cache[code] = sh
	return _cache[code]

const FACADE := """
shader_type spatial;
uniform float night = 0.0;
uniform float world_hash = 1.0;
varying vec3 wpos;
varying vec3 wnor;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 cell = fract(UV);
	float side = step(abs(wnor.y), 0.5);
	vec3 key = floor((wpos - wnor * 0.2) / 2.0);
	float h = h21(key.xz + key.y * 17.0 + (wnor.x + 2.0 * wnor.z) * 3.7);
	float h2 = h21(key.xz * 1.7 + key.y * 5.0 + 9.0);
	float st = COLOR.a;
	float brick = 1.0 - step(0.33, st);
	float glassy = step(0.66, st);
	vec3 base = COLOR.rgb * (0.9 + 0.2 * h2);
	// brick courses
	vec2 bp = vec2(cell.x * 4.0 + step(0.5, fract(cell.y * 8.0)) * 0.5, cell.y * 8.0);
	float mortar = max(step(fract(bp.y), 0.1), step(fract(bp.x), 0.06));
	base = mix(base, mix(base * (0.85 + 0.25 * h21(floor(bp) + key.xz)), vec3(0.72, 0.68, 0.62), mortar * 0.8), brick * side);
	// concrete floor slabs
	base *= 1.0 - (1.0 - brick) * (1.0 - glassy) * side * step(cell.y, 0.1) * 0.25;
	base *= mix(0.75, 1.0, smoothstep(0.0, 8.0, wpos.y));
	float e = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));
	base *= 0.88 + 0.12 * smoothstep(0.0, 0.05, e);
	base = mix(base * 0.55, base, side);
	// windows per style
	vec4 wr = mix(vec4(0.16, 0.84, 0.2, 0.8), vec4(0.3, 0.7, 0.28, 0.76), brick);
	wr = mix(wr, vec4(0.04, 0.96, 0.08, 0.96), glassy);
	float win = side * step(wr.x, cell.x) * step(cell.x, wr.y) * step(wr.z, cell.y) * step(cell.y, wr.w);
	float lit = step(mix(0.6, 0.8, glassy), h) * world_hash;
	vec3 glass = mix(vec3(0.11, 0.17, 0.24), vec3(0.2, 0.32, 0.42) * (0.7 + 0.5 * h2), glassy) * (0.8 + 0.4 * h);
	// ground floor shop fronts
	float shop = side * step(wpos.y, 2.0) * step(0.5, world_hash);
	float sglass = shop * step(0.06, cell.x) * step(cell.x, 0.94) * step(0.05, cell.y) * step(cell.y, 0.68);
	float awn = shop * step(0.7, cell.y) * step(cell.y, 0.86);
	float pick = h21(floor(wpos.xz / 6.0));
	vec3 awc = pick < 0.25 ? vec3(0.75, 0.15, 0.12) : (pick < 0.5 ? vec3(0.1, 0.45, 0.25) : (pick < 0.75 ? vec3(0.12, 0.3, 0.65) : vec3(0.85, 0.6, 0.1)));
	win = win * (1.0 - shop) + sglass;
	vec3 col = mix(base, glass, win);
	col = mix(col, awc, awn);
	ALBEDO = col;
	ROUGHNESS = mix(0.9, mix(0.18, 0.06, glassy), win);
	METALLIC = win * mix(0.35, 0.6, glassy);
	vec3 em = win * (1.0 - shop) * lit * night * vec3(1.0, 0.8, 0.45) * mix(1.5, 0.9, glassy);
	em += sglass * night * vec3(1.0, 0.85, 0.6) * 1.2 + awn * night * awc * 1.5;
	EMISSION = em;
}
"""

const GROUND := """
shader_type spatial;
uniform float pitch = 72.0;
uniform float road_w = 14.0;
uniform float half_size = 576.0;
uniform float night = 0.0;
uniform float wet = 0.0;
varying vec3 wpos;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 u = mod(p + vec2(half_size), vec2(pitch));
	vec2 d = min(u, vec2(pitch) - u);
	bool inside = abs(p.x) < half_size + 1.0 && abs(p.y) < half_size + 1.0;
	float hw = road_w * 0.5;
	bool road_x = d.x < hw;
	bool road_z = d.y < hw;
	bool road = (road_x || road_z) && inside;
	bool walk = !road && (d.x < hw + 2.6 || d.y < hw + 2.6) && inside;
	float n = vnoise(p * 0.8) * 0.5 + vnoise(p * 3.1) * 0.35 + h21(floor(p * 6.0)) * 0.15;
	vec3 col;
	float rough = 0.95;
	if (road) {
		col = vec3(0.17, 0.175, 0.19) * (0.8 + 0.4 * n);
		float dash_along_z = step(0.5, fract(p.y / 8.0));
		float dash_along_x = step(0.5, fract(p.x / 8.0));
		float cx = step(d.x, 0.14) * dash_along_z * (road_z ? 0.0 : 1.0);
		float cz = step(d.y, 0.14) * dash_along_x * (road_x ? 0.0 : 1.0);
		float ex = step(abs(d.x - (hw - 0.7)), 0.12) * (road_z ? 0.0 : 1.0);
		float ez = step(abs(d.y - (hw - 0.7)), 0.12) * (road_x ? 0.0 : 1.0);
		float line = max(max(cx, cz) * 0.9, max(ex, ez) * 0.8);
		col = mix(col, vec3(0.85, 0.82, 0.7), line);
		rough = mix(0.92, 0.22, wet);
		col *= mix(1.0, 0.65, wet);
	} else if (walk) {
		vec2 t = fract(p / 2.0);
		float joint = step(t.x, 0.03) + step(t.y, 0.03);
		col = vec3(0.52, 0.51, 0.49) * (0.85 + 0.25 * n) * (1.0 - 0.18 * min(joint, 1.0));
		rough = mix(0.9, 0.5, wet);
	} else if (inside) {
		col = mix(vec3(0.33, 0.37, 0.27), vec3(0.28, 0.45, 0.24), n) * 0.85;
	} else {
		col = mix(vec3(0.42, 0.37, 0.28), vec3(0.3, 0.42, 0.25), n);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
}
"""

const CAR := """
shader_type spatial;
uniform vec4 color : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform vec3 mesh_offset = vec3(0.0);
uniform float damage = 0.0;
uniform float dent_radius = 1.1;
uniform vec4 dent0 = vec4(0.0);
uniform vec4 dent1 = vec4(0.0);
uniform vec4 dent2 = vec4(0.0);
uniform vec4 dent3 = vec4(0.0);
varying float crumple;

vec4 apply_dent(vec3 p, vec4 dent) {
	if (dent.w <= 0.0) return vec4(0.0);
	float f = smoothstep(dent_radius, 0.0, length(p - dent.xyz));
	vec3 dir = normalize(-dent.xyz + vec3(0.0, 0.5, 0.0));
	return vec4(dir * dent.w * f, f);
}

void vertex() {
	vec3 p = VERTEX + mesh_offset;
	vec4 a = apply_dent(p, dent0);
	vec4 b = apply_dent(p, dent1);
	vec4 c = apply_dent(p, dent2);
	vec4 d = apply_dent(p, dent3);
	VERTEX += a.xyz + b.xyz + c.xyz + d.xyz;
	crumple = a.w + b.w + c.w + d.w;
}

void fragment() {
	float fixedc = step(0.25, COLOR.a);
	float glass = step(0.75, COLOR.a);
	vec3 c = mix(color.rgb, COLOR.rgb, fixedc);
	float burn = clamp(damage * 0.65 + crumple * 0.35, 0.0, 0.85);
	c = mix(c, vec3(0.04), burn * (1.0 - glass * 0.5));
	ALBEDO = c;
	METALLIC = mix(0.55 * (1.0 - damage), 0.0, fixedc) + glass * 0.6;
	ROUGHNESS = mix(0.28 + damage * 0.5, mix(0.75, 0.05, glass), fixedc);
	SPECULAR = 0.5 + glass * 0.4;
}
"""

const DEBRIS := """
shader_type spatial;
uniform vec4 tint : source_color = vec4(0.7, 0.68, 0.62, 1.0);
void fragment() {
	vec2 cell = fract(UV);
	float e = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));
	ALBEDO = tint.rgb * (0.82 + 0.18 * smoothstep(0.0, 0.06, e));
	ROUGHNESS = 0.95;
}
"""

const SKID := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
void fragment() {
	ALBEDO = vec3(0.02);
	ALPHA = COLOR.a * 0.55;
}
"""
