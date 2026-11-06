class_name Look
extends RefCounted
# The game's picture: one place for the colour grade, sky, moon, glow and fog, so every
# mode (play, recorded videos, story) shares the same bright, saturated, shiny look.
# main.gd calls apply() every frame with the time-of-day numbers it already works out;
# the story's mood grade (story/grade.gd) goes on top of this and only nudges it.

const SKY_DAY_TOP := Color(0.13, 0.42, 0.95)
const SKY_DAY_HOR := Color(0.62, 0.84, 1.0)
const SKY_NIGHT_TOP := Color(0.015, 0.03, 0.13)
const SKY_NIGHT_HOR := Color(0.06, 0.09, 0.24)
const SKY_DUSK := Color(1.0, 0.5, 0.26)

const MOON := Color(0.55, 0.68, 1.0)
const SUN := Color(1.0, 0.96, 0.86)
const SUN_LOW := Color(1.0, 0.66, 0.38)


# Called once when the environment is made.
static func setup(env: Environment) -> void:
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	# glow makes the lit windows, lamps, headlights and sirens bloom a little
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.6
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_sky_affect = 0.0


# day 0..1 (1 = full day), dusk 0..1 (warm low sun), rain 0..1, e = sin of the time of day.
static func apply(env: Environment, sky: ProceduralSkyMaterial, sun: DirectionalLight3D, day: float, dusk: float, rain: float, e: float) -> void:
	var night := 1.0 - day
	var top := SKY_NIGHT_TOP.lerp(SKY_DAY_TOP, day)
	var hor := SKY_NIGHT_HOR.lerp(SKY_DAY_HOR, day).lerp(SKY_DUSK, dusk * 0.7)
	var grey := Color(0.6, 0.64, 0.7)
	top = top.lerp(grey * (0.3 + 0.7 * day), rain * 0.6)
	hor = hor.lerp(grey * (0.35 + 0.65 * day), rain * 0.7)
	sky.sky_top_color = top
	sky.sky_horizon_color = hor
	sky.ground_horizon_color = hor
	sky.ground_bottom_color = hor.darkened(0.3)

	# ambient: soft blue skylight at night, bright and neutral by day. Lifted for phones.
	env.ambient_light_color = Color(0.3, 0.38, 0.72).lerp(Color(0.72, 0.78, 0.9), day)
	env.ambient_light_energy = lerpf(1.0, 0.62, day)
	env.tonemap_exposure = lerpf(1.2, 1.0, day)
	# the grade: richer colour, a little more contrast, a touch brighter
	env.adjustment_brightness = 1.02 + 0.04 * night
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = lerpf(1.18, 1.35, day) - 0.25 * rain
	env.glow_intensity = lerpf(0.9, 0.3, day)
	env.fog_light_color = hor
	env.fog_density = lerpf(0.0016, 0.0032, rain)

	# sun by day, moon by night (so the road has a sheen and cars cast shadows at night)
	var low_sun := clampf(e, 0.0, 1.0)
	sun.light_energy = lerpf(0.28, 0.85, day) * (1.0 - 0.5 * rain)
	sun.light_color = MOON.lerp(SUN, day).lerp(SUN_LOW, dusk)
	if e > 0.05:
		sun.rotation_degrees = Vector3(-lerpf(8.0, 60.0, low_sun), -35.0, 0)
	else:
		sun.rotation_degrees = Vector3(-52.0, 145.0, 0)
