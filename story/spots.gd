extends RefCounted
# Story lab: a small film set put up on the pavement where the car has parked: a bench, an
# ice-cream cart or a chai stall (with its vendor behind it). Built from boxes like everything
# else. Street trees, lamp posts, barrels and parked cars standing there are cleared first.
#
# Positions use the Street: `a` along the road, `off` metres from the walking lane toward the
# buildings (the pavement runs from about off -2.3 at the kerb to +0.7 at the building line).

const KINDS := ["bench", "icecream", "chai"]
const AHEAD := 5.0            # the set stands this far ahead of the parked car
const BENCH_H := 0.45         # seat height

var kind := ""
var street = null
var at := 0.0                 # along the road: the middle of the set
var root: Node3D
var stand := {}               # who -> where to stand at the set (Vector3)
var seats := {}               # who -> where to sit (bench)
var face := Vector3.ZERO      # the way the people on the bench face (the road)
var vendor_at := Vector3.ZERO # stalls: where the vendor stands
var counter := Vector3.ZERO   # stalls: the middle of the counter top


static func _mat(c: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


func _box(size: Vector3, a: float, off: float, y: float, c: Color, glow := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	# the set is built with x along the road and z toward the buildings
	bm.size = Vector3(size.x, size.y, size.z) if street.along_x else Vector3(size.z, size.y, size.x)
	mi.mesh = bm
	mi.material_override = _mat(c, glow)
	root.add_child(mi)
	mi.global_position = street.point(a, off) + Vector3(0, y, 0)
	return mi


# A board above the stall, readable from the road.
func _sign(text: String, a: float, off: float, y: float, c: Color) -> void:
	_box(Vector3(1.5, 0.36, 0.05), a, off + 0.03, y, Color(0.18, 0.1, 0.12))
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.outline_size = 12
	l.pixel_size = 0.004
	l.modulate = c
	l.outline_modulate = Color(0.1, 0.05, 0.05)
	root.add_child(l)
	l.global_position = street.point(a, off) + Vector3(0, y, 0)
	var f: Vector3 = -street.outward()
	l.rotation.y = atan2(f.x, f.z)       # a label reads from its +z side


# Builds the set. who_a / who_b: the two leads (driver first). Returns null for an unknown kind.
static func build(kind_id: String, st, car_along: float, parent: Node3D, main, who_a: String, who_b: String) -> RefCounted:
	if not KINDS.has(kind_id):
		return null
	var s = load("res://story/spots.gd").new()
	s.kind = kind_id
	s.street = st
	var fwd: float = st.dir.x + st.dir.z
	s.at = st.clamp_along(car_along + AHEAD * fwd)
	s.root = Node3D.new()
	s.root.name = "spot_" + kind_id
	parent.add_child(s.root)
	s._clear(main)
	s.face = -st.outward()
	match kind_id:
		"bench":
			s._bench(who_a, who_b)
		"icecream":
			s._icecream(who_a, who_b)
		"chai":
			s._chai(who_a, who_b)
	return s


func _bench(who_a: String, who_b: String) -> void:
	var wood := Color(0.62, 0.38, 0.2)
	var iron := Color(0.15, 0.15, 0.17)
	_box(Vector3(1.9, 0.08, 0.46), at, 0.3, BENCH_H - 0.04, wood)
	_box(Vector3(1.9, 0.36, 0.07), at, 0.56, BENCH_H + 0.26, wood)
	for e in [-0.85, 0.85]:
		_box(Vector3(0.08, BENCH_H, 0.42), at + e, 0.3, BENCH_H * 0.5, iron)
		_box(Vector3(0.08, 0.5, 0.08), at + e, 0.56, BENCH_H + 0.2, iron)
	# a flower pot at each end
	for e in [-1.35, 1.35]:
		_box(Vector3(0.4, 0.4, 0.4), at + e, 0.3, 0.2, Color(0.72, 0.36, 0.22))
		_box(Vector3(0.34, 0.3, 0.34), at + e, 0.3, 0.52, Color(0.25, 0.55, 0.22))
		_box(Vector3(0.12, 0.12, 0.12), at + e, 0.2, 0.68, Color(1.0, 0.4, 0.6))
	var fwd: float = street.dir.x + street.dir.z
	# the driver sits on the left as seen from the road
	seats[who_a] = street.point(at - 0.42 * fwd, 0.38)
	seats[who_b] = street.point(at + 0.42 * fwd, 0.38)
	stand[who_a] = street.point(at - 0.5 * fwd, -0.35)
	stand[who_b] = street.point(at + 0.5 * fwd, -0.35)


func _stall_base(top: Color, side: Color) -> void:
	var fwd: float = street.dir.x + street.dir.z
	counter = street.point(at, -0.15) + Vector3(0, 1.0, 0)
	vendor_at = street.point(at, 0.5)
	# customers stand at the two ends of the counter, so the camera on the road sees them
	# side-on and the vendor face-on
	stand["_a"] = street.point(at - 1.35 * fwd, -0.55)
	stand["_b"] = street.point(at + 1.35 * fwd, -0.55)
	_box(Vector3(1.6, 0.8, 0.75), at, -0.15, 0.55, side)
	_box(Vector3(1.7, 0.08, 0.85), at, -0.15, 0.98, top)
	for e in [-0.6, 0.6]:
		_box(Vector3(0.08, 0.3, 0.3), at + e, -0.55, 0.15, Color(0.12, 0.12, 0.12))


func _icecream(who_a: String, who_b: String) -> void:
	_stall_base(Color(0.95, 0.95, 0.98), Color(0.45, 0.75, 1.0))
	# tubs of ice cream under a glass top
	var flav := [Color(1.0, 0.6, 0.75), Color(0.98, 0.93, 0.75), Color(0.45, 0.28, 0.18), Color(0.6, 0.9, 0.6)]
	for i in 4:
		_box(Vector3(0.3, 0.1, 0.3), at - 0.54 + i * 0.36, -0.15, 1.06, flav[i])
	# striped umbrella
	_box(Vector3(0.06, 1.5, 0.06), at + 0.7, 0.15, 1.75, Color(0.85, 0.85, 0.85))
	for i in 5:
		var c := Color(1.0, 0.4, 0.6) if i % 2 == 0 else Color(1, 1, 1)
		_box(Vector3(0.44, 0.08, 1.9), at + 0.7 - 0.88 + i * 0.44, 0.15, 2.5, c)
	_sign("ICE CREAM", at - 0.15, 0.5, 2.95, Color(1.0, 0.85, 0.95))
	stand[who_a] = stand["_a"]
	stand[who_b] = stand["_b"]


func _chai(who_a: String, who_b: String) -> void:
	_stall_base(Color(0.55, 0.4, 0.25), Color(0.75, 0.5, 0.25))
	# a kettle on a small stove and a row of glasses
	_box(Vector3(0.3, 0.12, 0.3), at - 0.45, -0.1, 1.08, Color(0.2, 0.2, 0.22))
	_box(Vector3(0.24, 0.26, 0.24), at - 0.45, -0.1, 1.27, Color(0.75, 0.75, 0.78))
	_box(Vector3(0.18, 0.04, 0.04), at - 0.3, -0.1, 1.32, Color(0.75, 0.75, 0.78))
	for i in 4:
		_box(Vector3(0.07, 0.11, 0.07), at + 0.05 + i * 0.13, -0.25, 1.08, Color(0.75, 0.45, 0.2))
	# a tin roof on two poles and the board
	for e in [-0.8, 0.8]:
		_box(Vector3(0.06, 1.5, 0.06), at + e, 0.25, 1.75, Color(0.3, 0.25, 0.2))
	_box(Vector3(2.0, 0.06, 1.3), at, -0.1, 2.5, Color(0.2, 0.45, 0.65))
	_sign("CHAI", at, 0.45, 2.8, Color(1.0, 0.95, 0.7))
	stand[who_a] = stand["_a"]
	stand[who_b] = stand["_b"]


# Clears street furniture from the set and the walk to it.
func _clear(main) -> void:
	var pr = main.world.props
	var c: Vector3 = street.point(at, 0.0)
	var key: Vector2i = main.world.block_of(c)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var k := key + Vector2i(dx, dz)
			for d: Dictionary in pr.block_props.get(k, []):
				if not d.get("alive", false) or not (d["t"] in ["tree", "lamp", "barrel", "parked"]):
					continue
				var p: Vector3 = d["p"]
				if absf(street.along(p) - at) > AHEAD + 6.0 or absf(street.offset(p)) > 4.5:
					continue
				d["alive"] = false
				if d.has("node") and is_instance_valid(d["node"]):
					(d["node"] as Node).queue_free()
				var mms: Dictionary = pr.block_mm.get(k, {})
				var i: int = d.get("i", -1)
				if i < 0:
					continue
				var hide := Transform3D(Basis().scaled(Vector3.ZERO), p)
				for part in (["trunk", "canopy"] if d["t"] == "tree" else ["pole", "arm", "head"]):
					if mms.has(part):
						(mms[part] as MultiMesh).set_instance_transform(i, hide)



func free_set() -> void:
	if is_instance_valid(root):
		root.queue_free()
