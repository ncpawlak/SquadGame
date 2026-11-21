class_name FpsHillMap
extends Node3D
## Hill-capture arena built in code (floor, walls, cover, hill disc) with a navigation mesh baked at ready.
## Team 0 spawns at +Z, team 1 at -Z; the hill is at the centre.

const HALF_X := 40.0
const HALF_Z := 40.0
const HILL_RADIUS := 6.0
const SPAWN_Z := 33.0

var _cover: Array = []
var _built := false


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	var geo := Node3D.new()
	geo.name = "Geometry"
	add_child(geo)
	_box(geo, Vector3(0, -0.5, 0), Vector3(HALF_X * 2, 1, HALF_Z * 2), Color(0.35, 0.38, 0.33))
	for sx in [-1, 1]:
		_box(geo, Vector3(sx * (HALF_X + 0.5), 2, 0), Vector3(1, 4, HALF_Z * 2), Color(0.25, 0.25, 0.28))
	for sz in [-1, 1]:
		_box(geo, Vector3(0, 2, sz * (HALF_Z + 0.5)), Vector3(HALF_X * 2 + 2, 4, 1), Color(0.25, 0.25, 0.28))
	# hill marker: a flat disc, no collision so it never blocks the navmesh
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = HILL_RADIUS
	cyl.bottom_radius = HILL_RADIUS
	cyl.height = 0.05
	disc.mesh = cyl
	disc.position = Vector3(0, 0.03, 0)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.95, 0.85, 0.3, 0.6)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.material_override = dm
	disc.name = "Hill"
	add_child(disc)
	# Cover: mirrored blocks around the hill and on the lanes. Positions double as bot cover points.
	var blocks := [
		[Vector3(-12, 0, 9), Vector3(5, 2, 1.2)], [Vector3(12, 0, 9), Vector3(5, 2, 1.2)],
		[Vector3(0, 0, 14), Vector3(3, 1.4, 1.2)],
		[Vector3(-8, 0, 2), Vector3(1.2, 2, 4)], [Vector3(8, 0, 2), Vector3(1.2, 2, 4)],
		[Vector3(-22, 0, 16), Vector3(3, 2, 3)], [Vector3(22, 0, 16), Vector3(3, 2, 3)],
		[Vector3(-16, 0, 24), Vector3(4, 2, 1.2)], [Vector3(16, 0, 24), Vector3(4, 2, 1.2)],
	]
	for b in blocks:
		for mz in [1, -1]:
			var p: Vector3 = b[0]
			p.z *= mz
			var sz: Vector3 = b[1]
			_box(geo, p + Vector3(0, sz.y * 0.5, 0), sz, Color(0.5, 0.45, 0.4))
			# a cover spot just behind the block, seen from the hill
			var back := Vector3(p.x, 0, p.z + signf(p.z if p.z != 0.0 else 1.0) * (sz.z * 0.5 + 1.2))
			_cover.append(back)
	_bake_navigation(geo)


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)


func _bake_navigation(geo: Node3D) -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, geo)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nm
	region.name = "NavRegion"
	add_child(region)


func spawn_positions(team_id: int) -> Array:
	var z := SPAWN_Z * (1.0 if team_id == 0 else -1.0)
	var out: Array = []
	for i in 5:
		out.append(global_position + Vector3(-8.0 + i * 4.0, 0.1, z))
	return out


func hill_center() -> Vector3:
	return global_position


func hill_radius() -> float:
	return HILL_RADIUS


func cover_points() -> Array:
	var out: Array = []
	for c in _cover:
		out.append(global_position + c)
	return out
