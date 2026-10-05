extends Spatial
# A zipline: two poles and a cable. Press interact at either pole to hang on and ride to the other end; jump (or interact) to let go.
# The rider is a ZipRider, which looks like a vehicle to the player code (so the exit, camera and net pose all just work).

const Rider = preload("res://scripts/ZipRider.gd")
const Station = preload("res://scripts/ZipStation.gd")

const POLE_H := 5.2

var a := Vector3.ZERO           # cable top at the first pole (world)
var b := Vector3.ZERO
var net_id := ""
var stations := []
var bots_riding := 0             # bots on the cable (they ride too)


# base_a / base_b: ground points under each pole.
func setup(base_a: Vector3, base_b: Vector3) -> void:
	a = base_a + Vector3(0, POLE_H, 0)
	b = base_b + Vector3(0, POLE_H, 0)
	var pole_mat := SpatialMaterial.new()
	pole_mat.albedo_color = Color(0.32, 0.3, 0.3)
	pole_mat.metallic = 0.5
	pole_mat.roughness = 0.5
	var accent := SpatialMaterial.new()
	accent.albedo_color = Color(0.95, 0.55, 0.1)
	for i in range(2):
		var base: Vector3 = base_a if i == 0 else base_b
		var pole := MeshInstance.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.13
		cm.bottom_radius = 0.2
		cm.height = POLE_H + 0.5
		cm.radial_segments = 8
		pole.mesh = cm
		pole.material_override = pole_mat
		pole.translation = base + Vector3(0, (POLE_H + 0.5) * 0.5 - 0.2, 0)
		add_child(pole)
		var cap := MeshInstance.new()                         # a bright wheel house on top so it is easy to spot from far away
		var bm := CubeMesh.new()
		bm.size = Vector3(0.7, 0.35, 0.7)
		cap.mesh = bm
		cap.material_override = accent
		cap.translation = base + Vector3(0, POLE_H + 0.1, 0)
		add_child(cap)
		var col := StaticBody.new()                           # poles are solid
		col.collision_layer = 1
		col.collision_mask = 0
		var shape := CollisionShape.new()
		var cyl := CylinderShape.new()
		cyl.radius = 0.25
		cyl.height = POLE_H
		shape.shape = cyl
		col.add_child(shape)
		col.translation = base + Vector3(0, POLE_H * 0.5, 0)
		add_child(col)
		var st = Station.new()
		st.line = self
		st.end = i
		st.translation = base + Vector3(0, 0.6, 0)
		add_child(st)
		stations.append(st)
	var cable := MeshInstance.new()
	var cmesh := CubeMesh.new()
	cmesh.size = Vector3(0.05, 0.05, a.distance_to(b))
	cable.mesh = cmesh
	var cmat := SpatialMaterial.new()
	cmat.albedo_color = Color(0.1, 0.1, 0.1)
	cable.material_override = cmat
	add_child(cable)
	cable.transform = _cable_xf()


func _cable_xf() -> Transform:
	var mid := (a + b) * 0.5
	var t := Transform(Basis.IDENTITY, mid)
	return t.looking_at(b, Vector3.UP)


# Somebody is on the cable.
func busy() -> bool:
	if bots_riding > 0:
		return true
	for r in get_tree().get_nodes_in_group("zip_riders"):
		if r.line == self and not r.finished:
			return true
	return false


func length() -> float:
	return a.distance_to(b)


# `by` grabs the cable at pole `end` (0 = a, 1 = b) and rides to the other side. Returns the rider.
func board(by, end: int):
	var r = Rider.new()
	r.line = self
	r.from_end = end
	r.name = "ZipRider"
	get_parent().add_child(r)
	r.global_transform.origin = a if end == 0 else b
	r.occupants[0] = by
	by.enter_vehicle(r, 0)
	return r
