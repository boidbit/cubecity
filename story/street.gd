extends RefCounted
# Story lab: the stretch of pavement next to where the car has stopped. The characters get
# out on this side and walk up and down it, staying inside the block (no crossing a road).
# Roads run along the city grid lines (World.line), ROAD_W wide; buildings start 10 m from
# a road's centre and the lamps and trees stand at 8.3 m, so people walk at 9.3 m.

const LANE := 9.3

var along_x := true          # the road runs along x (else along z)
var road := 0.0              # the road's centre line (z if along_x, else x)
var side := 1.0              # which side of the road the pavement is on
var dir := Vector3.FORWARD   # along the road, the way the car was facing
var lo := 0.0                # the block's pavement ends (along coordinate)
var hi := 0.0


static func from_car(car: Node3D) -> RefCounted:
	var s = load("res://story/street.gd").new()
	var f := -car.global_transform.basis.z
	var p := car.global_position
	s.along_x = absf(f.x) >= absf(f.z)
	var lat := p.z if s.along_x else p.x
	var k := roundi((lat + World.HALF) / World.PITCH)
	s.road = World.HALF * -1.0 + k * World.PITCH
	s.side = 1.0 if lat >= s.road else -1.0
	s.dir = Vector3(signf(f.x) if s.along_x else 0.0, 0, 0.0 if s.along_x else signf(f.z))
	var a := p.x if s.along_x else p.z
	var j := floori((a + World.HALF) / World.PITCH)
	s.lo = -World.HALF + j * World.PITCH + 12.0
	s.hi = -World.HALF + (j + 1) * World.PITCH - 12.0
	return s


func along(p: Vector3) -> float:
	return p.x if along_x else p.z


# A point on the pavement at `a` along the road, `off` metres toward the buildings from the lane.
func point(a: float, off := 0.0) -> Vector3:
	a = clampf(a, lo, hi)
	var lat := road + side * (LANE + off)
	return Vector3(a, 0, lat) if along_x else Vector3(lat, 0, a)


# How far `p` is from the walking lane, toward the buildings (the inverse of point()'s `off`).
func offset(p: Vector3) -> float:
	var lat := p.z if along_x else p.x
	return (lat - road) * side - LANE


func clamp_along(a: float) -> float:
	return clampf(a, lo, hi)


# Direction from the road toward the buildings on this side.
func outward() -> Vector3:
	return Vector3(0, 0, side) if along_x else Vector3(side, 0, 0)
