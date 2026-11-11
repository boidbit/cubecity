extends SceneTree
# Headless test for burning cars (burn.gd and Car.set_burn_level). Run it with tools/test_fire.sh
# <godot binary> (CI does). It exits 1 if anything fails. It checks that:
#   - the stages follow the car's health: smoke below 45 %, flames below 30 %, on fire below 20 %;
#   - a car on fire loses health and does not mend itself, so the player has about 13 s to find a repair;
#   - a damaged car that is not on fire does not mend itself either (it used to, 4 s after the last hit);
#   - a repair puts the fire out, and it stays out;
#   - in a video run (main.protect) the car keeps burning and survives;
#   - a police car on fire goes up within seconds, and its wreck burns on for 25 s and is then cleared;
#   - however many wrecks burn, only the nearest few get the full fire and a light, and the number of
#     particles stays within a budget.
# Nothing here looks at the picture: what the fire looks like is judged by eye (see the README).

var main
var world: World
var player: Car
var start := Vector3.ZERO
var passed := 0
var failed := 0
var dt := 1.0 / 60.0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)      # its _ready runs when the tree starts, so world and player are fetched in _run
	_run.call_deferred()


func _run() -> void:
	for i in 30:
		await process_frame
	world = main.world
	player = main.player
	main.traffic_cap = 0
	main.best = 1000000000    # a game over must not write a best score into the user's data
	start = Vector3(world.line(8) + 3.5, 0.9, world.line(8) + 36.0)
	await _stages()
	await _fire_hurts_and_does_not_heal()
	await _damage_stays()
	await _repair()
	await _protected()
	await _police_wreck()
	await _budget()
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


# A clean start: the player healthy, still, back on the road, nobody else about.
func _reset() -> void:
	for civ in main.civs.duplicate():
		if is_instance_valid(civ):
			civ.queue_free()
	main.civs.clear()
	for cop in main.police.duplicate():
		if is_instance_valid(cop):
			cop.queue_free()
	main.police.clear()
	main.heat = 0.0
	main.level = 0
	main.protect = false
	main.game_over = false
	main.hud.in_gas = 0.0
	main.hud.in_steer = 0.0
	player.dead = false
	player.global_transform = Transform3D(Basis.IDENTITY, start)
	player.linear_velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO
	player.hp = 100.0
	player.last_hurt = main.clock
	player._update_look()
	await _frames(30)


func _level() -> int:
	return player.burn.level if player.burn != null else 0


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
		print("PASS  ", name, ": ", detail)
	else:
		failed += 1
		print("FAIL  ", name, ": ", detail)


func _stages() -> void:
	await _reset()
	for c in [[60.0, 0], [44.0, 1], [29.0, 2], [19.0, 3], [5.0, 3]]:
		player.hp = c[0]
		player._update_look()      # (no physics step in between, so nothing burns away yet)
		var got := _level()
		_check("stage at %d%% health" % int(c[0]), got == int(c[1]), "level %d, wanted %d" % [got, int(c[1])])
	player.heal(100.0)
	_check("fully repaired: no fire", _level() == 0 and not player.burning(), "level %d" % _level())


func _fire_hurts_and_does_not_heal() -> void:
	await _reset()
	player.hp = 18.0
	player._update_look()
	_check("the player's car at 18% health is on fire", player.burning(), "level %d" % _level())
	var t := 0.0
	var top := player.hp
	var hp_at_5 := -1.0
	var burning_at_5 := false
	while t < 20.0 and not player.dead:
		await physics_frame
		t += dt
		top = maxf(top, player.hp)
		if hp_at_5 < 0.0 and t >= 5.0:
			hp_at_5 = player.hp
			burning_at_5 = player.burning()
	_check("5 s on, it is still on fire", burning_at_5, "burning %s" % str(burning_at_5))
	_check("and has lost health (1.5 a second)", hp_at_5 > 18.0 - 11.0 and hp_at_5 < 18.0 - 4.0, "%.1f hp left of 18" % hp_at_5)
	_check("nothing mended it on the way", top <= 18.01, "the highest it ever got was %.2f" % top)
	_check("the player has about 13 s to find a repair, then it goes up", player.dead and t > 10.0 and t < 14.0 and main.game_over,
		"dead %s after %.1f s, game over %s" % [str(player.dead), t, str(main.game_over)])


func _damage_stays() -> void:
	await _reset()
	player.hp = 60.0
	player._update_look()
	await _frames(20 * 60)
	_check("a damaged car does not mend itself", player.hp <= 60.01 and not player.burning(), "%.1f hp after 20 s (it was 60)" % player.hp)
	player.hp = 38.0
	player._update_look()
	await _frames(15 * 60)
	_check("and keeps smoking", _level() >= 1 and player.hp <= 38.01, "level %d at %.1f hp after 15 s" % [_level(), player.hp])


func _repair() -> void:
	await _reset()
	player.hp = 12.0
	player._update_look()
	await _frames(60)
	var before := player.hp
	_check("on fire for a second: health goes down", player.burning() and before < 12.0, "%.1f hp" % before)
	player.heal(45.0)             # a repair pickup
	_check("a repair puts the fire out", not player.burning(), "level %d at %.0f hp" % [_level(), player.hp])
	var after := player.hp
	await _frames(120)
	_check("and it stays out, health no longer drops", not player.burning() and player.hp >= after - 0.01, "%.1f hp, was %.1f" % [player.hp, after])


func _protected() -> void:
	await _reset()
	main.protect = true           # video runs: a clip never ends on a wreck
	player.hp = 10.0
	player._update_look()
	await _frames(20 * 60)
	_check("in a video run the car burns for 20 s and survives", player.burning() and not player.dead and player.hp >= 4.0,
		"burning %s, dead %s, %.1f hp" % [str(player.burning()), str(player.dead), player.hp])


func _park_cop(distance: float, hp: float) -> Car:
	var pos := start + Vector3(0, 0, -distance)         # the player faces -Z, along the road
	var cop: Car = main.spawn_police_at(pos, 0.0, 0.0)
	cop.is_block = true           # parked: no driving
	cop.hp = hp
	cop._update_look()
	return cop


func _police_wreck() -> void:
	await _reset()
	var cop := _park_cop(70.0, 12.0)
	_check("a police car at 17% health is on fire", cop.burning(), "level %d" % (cop.burn.level if cop.burn != null else 0))
	var t := 0.0
	while t < 12.0 and not cop.dead:
		await physics_frame
		t += dt
	_check("it goes up within seconds", cop.dead and t > 1.5 and t < 8.0, "dead %s after %.1f s" % [str(cop.dead), t])
	_check("the wreck is on fire", cop.burning(), "burning %s" % str(cop.burning()))
	var t0 := t
	while t - t0 < 25.0:
		await physics_frame
		t += dt
	_check("the wreck still burns 25 s later", is_instance_valid(cop) and cop.burning(), "valid %s" % str(is_instance_valid(cop)))
	while t - t0 < 31.0:
		await physics_frame
		t += dt
	_check("and is cleared away after about 28 s", not is_instance_valid(cop), "valid %s" % str(is_instance_valid(cop)))


func _budget() -> void:
	await _reset()
	for i in 8:
		_park_cop(20.0 + i * 6.0, 8.0)
	await _frames(6 * 60)         # they go up within 3 s, chain-reacting; the wrecks burn on; the budget refreshes every 0.3 s
	var burning := 0
	var full := 0
	var lights := 0
	var emitting := 0
	var particles := 0
	for b in main.fx.burns:
		if not is_instance_valid(b) or b.level == 0:
			continue
		burning += 1
		if b.shown() >= 3:
			full += 1
		if b.light != null:
			lights += 1
		for e in b.emitters.values():
			var p := e as CPUParticles3D
			if p.emitting:
				emitting += 1
				particles += p.amount
	_check("8 police cars burn", burning >= 8, "%d burning" % burning)
	_check("only the nearest get a light", lights >= 1 and lights <= Fx.BURN_LIGHTS, "%d lights (at most %d)" % [lights, Fx.BURN_LIGHTS])
	_check("and the full fire", full >= 1 and full <= Fx.BURN_FULL, "%d full fires (at most %d)" % [full, Fx.BURN_FULL])
	_check("the particles stay within a budget", particles <= 940 and emitting <= 40, "%d emitters, %d particles (at most 40 and 940)" % [emitting, particles])
