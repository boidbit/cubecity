class_name Landmarks
extends RefCounted
# A handful of hand-designed buildings that fill a whole block each, so the skyline has
# recognisable shapes and the player can tell where they are: an art-deco needle, twin towers
# on a podium, an octagonal glass tower, a round tower, a stepped ziggurat, a clock tower and
# an open arena (you can drive in). Everything else in the city is generated; these are the
# few that are designed. Each is still an ordinary destructible Building (columns of cells).
#
# build(kind) returns {w, d, heights, tint, style, roofs}; roofs are [kind, x, z] on top of a column.

# block -> landmark. Away from the safehouse corners, the railway row and the flyover roads.
const SPIRE_H := 16.0

const SITES := {
	Vector2i(8, 6): "needle",
	Vector2i(8, 9): "twin",
	Vector2i(6, 9): "octagon",
	Vector2i(9, 5): "round",
	Vector2i(6, 5): "ziggurat",
	Vector2i(9, 10): "clock",
	Vector2i(3, 8): "arena",
}


static func _grid(w: int, d: int, fill: int) -> PackedInt32Array:
	var hs := PackedInt32Array()
	hs.resize(w * d)
	hs.fill(fill)
	return hs


static func build(kind: String) -> Dictionary:
	match kind:
		"needle":
			return _needle()
		"twin":
			return _twin()
		"octagon":
			return _octagon()
		"round":
			return _round()
		"ziggurat":
			return _ziggurat()
		"clock":
			return _clock()
		_:
			return _arena()


# Distance in cells from the edge of the footprint: 0 on the outer ring.
static func _edge(x: int, z: int, w: int, d: int) -> int:
	return mini(mini(x, w - 1 - x), mini(z, d - 1 - z))


# Art-deco needle: four setbacks and a long spire.
static func _needle() -> Dictionary:
	var w := 11
	var d := 11
	var hs := _grid(w, d, 0)
	for z in d:
		for x in w:
			var e := _edge(x, z, w, d)
			hs[x + z * w] = [9, 15, 21, 26, 30, 34][mini(e, 5)]
	return {"w": w, "d": d, "heights": hs, "tint": Color(0.86, 0.74, 0.52), "style": World.encode_style(0.5, 0),
		"roofs": [["spire", 5, 5]]}


# Two slim towers on a shared podium.
static func _twin() -> Dictionary:
	var w := 17
	var d := 8
	var hs := _grid(w, d, 5)
	for z in d:
		for x in w:
			if x < 6 or x >= w - 6:
				var e := mini(_edge(x, z, w, d), 1)
				hs[x + z * w] = 28 if e >= 1 else 24
	return {"w": w, "d": d, "heights": hs, "tint": Color(0.36, 0.58, 0.74), "style": World.encode_style(0.85, 1),
		"roofs": [["spire", 2, 3], ["spire", w - 3, 3]]}


# Glass tower with cut corners and a stepped crown.
static func _octagon() -> Dictionary:
	var w := 14
	var d := 14
	var hs := _grid(w, d, 0)
	var cut := 4
	for z in d:
		for x in w:
			var cx := mini(x, w - 1 - x)
			var cz := mini(z, d - 1 - z)
			if cx + cz < cut:
				continue
			var e := _edge(x, z, w, d)
			hs[x + z * w] = 26 if e >= 3 else 24
	return {"w": w, "d": d, "heights": hs, "tint": Color(0.3, 0.62, 0.62), "style": World.encode_style(0.85, 3),
		"roofs": [["spire", 7, 7]]}


# A round tower: a disc of cells with a lower ring around the top.
static func _round() -> Dictionary:
	var w := 13
	var d := 13
	var hs := _grid(w, d, 0)
	var c := 6.0
	for z in d:
		for x in w:
			var r := Vector2(x - c, z - c).length()
			if r > 6.2:
				continue
			hs[x + z * w] = 30 if r < 4.4 else (26 if r < 5.4 else 22)
	return {"w": w, "d": d, "heights": hs, "tint": Color(0.88, 0.88, 0.9), "style": World.encode_style(0.5, 1),
		"roofs": [["spire", 6, 6]]}


# Stepped pyramid in terracotta.
static func _ziggurat() -> Dictionary:
	var w := 15
	var d := 15
	var hs := _grid(w, d, 0)
	for z in d:
		for x in w:
			var e := _edge(x, z, w, d)
			hs[x + z * w] = 4 + 4 * mini(e, 5)
	return {"w": w, "d": d, "heights": hs, "tint": Color(0.78, 0.46, 0.32), "style": World.encode_style(0.15, 0),
		"roofs": [["spire", 7, 7]]}


# Brick clock tower with a tall narrow shaft.
static func _clock() -> Dictionary:
	var w := 9
	var d := 9
	var hs := _grid(w, d, 0)
	for z in d:
		for x in w:
			var e := _edge(x, z, w, d)
			hs[x + z * w] = 8 if e == 0 else (12 if e == 1 else 32)
	return {"w": w, "d": d, "heights": hs, "tint": Color(0.7, 0.34, 0.26), "style": World.encode_style(0.15, 2),
		"roofs": [["spire", 4, 4]]}


# A ring-shaped arena, empty in the middle: drive in through the gaps.
static func _arena() -> Dictionary:
	var w := 24
	var d := 18
	var hs := _grid(w, d, 0)
	for z in d:
		for x in w:
			var nx := (x - (w - 1) * 0.5) / (w * 0.5)
			var nz := (z - (d - 1) * 0.5) / (d * 0.5)
			var r := Vector2(nx, nz).length()
			if r > 1.0 or r < 0.72:
				continue
			hs[x + z * w] = 7 if r > 0.86 else 5
	# four gates through the ring
	for x in range(w / 2 - 1, w / 2 + 1):
		for z in d:
			if hs[x + z * w] > 0 and (z < 3 or z > d - 4):
				hs[x + z * w] = 0
	for z in range(d / 2 - 1, d / 2 + 1):
		for x in w:
			if hs[x + z * w] > 0 and (x < 4 or x > w - 5):
				hs[x + z * w] = 0
	return {"w": w, "d": d, "heights": hs, "tint": Color(0.72, 0.74, 0.8), "style": World.encode_style(0.5, 3),
		"roofs": []}
