class_name FpsArena
extends Node3D
## The 3D version of an ArenaMap field: floor, start zones, hill marker, perimeter walls and every prop as a
## StaticBody3D box, plus a baked navigation mesh. 2D (x, y) metres -> 3D Vector3(x, 0, y).

const WALL_H := 3.0
const COVER_H := 1.2
const FENCE_H := 1.0
const DECAL_H := 0.02
const SPAWN_Y := 0.1

const SURFACE_COLORS := {
	"asphalt": Color(0.24, 0.25, 0.27), "concrete": Color(0.45, 0.46, 0.47),
	"turf": Color(0.22, 0.42, 0.22), "sand": Color(0.72, 0.64, 0.45),
}
const KIND_COLORS := {
	&"wall": Color(0.55, 0.52, 0.48), &"pillar": Color(0.6, 0.6, 0.62), &"container": Color(0.7, 0.35, 0.2),
	&"bleachers": Color(0.5, 0.5, 0.55), &"tree": Color(0.15, 0.4, 0.15), &"hedge": Color(0.2, 0.45, 0.2),
	&"car": Color(0.3, 0.4, 0.6), &"truck": Color(0.55, 0.45, 0.3), &"bus": Color(0.8, 0.65, 0.2),
	&"dumpster": Color(0.2, 0.4, 0.3), &"barrels": Color(0.6, 0.25, 0.2), &"sandbags": Color(0.65, 0.58, 0.4),
	&"barrier": Color(0.75, 0.72, 0.7), &"stall": Color(0.7, 0.5, 0.3), &"crate": Color(0.6, 0.45, 0.25),
	&"planter": Color(0.4, 0.5, 0.3), &"dugout": Color(0.4, 0.4, 0.45), &"boat": Color(0.3, 0.5, 0.65),
	&"cabana": Color(0.8, 0.6, 0.4), &"hay": Color(0.8, 0.7, 0.35), &"table": Color(0.55, 0.4, 0.3),
	&"fence": Color(0.5, 0.5, 0.5), &"pad": Color(0.4, 0.4, 0.42), &"grass": Color(0.25, 0.5, 0.25),
	&"boards": Color(0.5, 0.38, 0.25), &"dirt": Color(0.45, 0.35, 0.25), &"water": Color(0.25, 0.5, 0.75),
}
const ZONE_COLORS := [Color(0.25, 0.5, 0.95, 0.35), Color(0.9, 0.3, 0.25, 0.35)]
const HILL_COLOR := Color(1.0, 0.85, 0.2, 0.4)

var field: ArenaMap
var nav_region: NavigationRegion3D
var _cover3: Array = []
var _mats: Dictionary = {}
var _built := false


static func make(p_field: ArenaMap) -> FpsArena:
	var a := FpsArena.new()
	a.name = "FpsArena"
	a.field = p_field
	return a


static func to3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


static func to2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _ready() -> void:
	build()


## Sky colour, ambient light and a sun, so the field is lit when it is the only 3D thing in the scene.
func _build_light() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.65, 0.78)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.0
	add_child(sun)


func build() -> void:
	if _built:
		return
	_built = true
	if field == null:
		field = ArenaMap.legacy()
	field.ensure_built()
	_build_light()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	add_child(nav_region)
	_build_floor()
	_build_zones()
	_build_walls()
	for p in field.props:
		_build_prop(p)
	for s in field.cover_spots:
		_cover3.append(to3(s))
	_bake_nav()


# --- queries ------------------------------------------------------------------------

func spawn_point(team: int, scheme: Scheme, slot: StringName) -> Vector3:
	return to3(ArenaMap.world(team, scheme.spawn_of(slot)), SPAWN_Y)


## Yaw (Node3D rotation.y) that looks along +x for team 0 and -x for team 1 (forward is -Z in Godot).
func spawn_facing_yaw(team: int) -> float:
	return -PI * 0.5 if team == 0 else PI * 0.5


func hill_rect() -> Rect2:
	return ArenaMap.HILL


func hill_center() -> Vector3:
	return to3(ArenaMap.HILL.get_center())


func cover_points() -> Array:
	return _cover3


func in_spawn_zone(team: int, v: Vector3) -> bool:
	return ArenaMap.in_spawn_zone(team, to2(v))


# --- building -----------------------------------------------------------------------

func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html(true)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.9
	_mats[key] = m
	return m


func _box(parent: Node, size: Vector3, pos: Vector3, c: Color, collide: bool) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	var holder: Node3D
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		holder = body
	else:
		holder = Node3D.new()
	holder.position = pos
	holder.add_child(mi)
	parent.add_child(holder)
	return holder


func _build_floor() -> void:
	var c: Color = SURFACE_COLORS.get(field.surface, SURFACE_COLORS["concrete"])
	var f := _box(nav_region, Vector3(ArenaMap.HALF.x * 2.0, 0.2, ArenaMap.HALF.y * 2.0), Vector3(0, -0.1, 0), c, true)
	f.name = "Floor"


func _build_zones() -> void:
	var w := ArenaMap.HALF.x - ArenaMap.START_X
	var d := ArenaMap.HALF.y * 2.0
	for team in 2:
		var sx := (-1.0 if team == 0 else 1.0) * (ArenaMap.START_X + w * 0.5)
		_box(self, Vector3(w, 0.01, d), Vector3(sx, 0.012, 0), ZONE_COLORS[team], false)
	var hr := ArenaMap.HILL
	var hc := hr.get_center()
	_box(self, Vector3(hr.size.x, 0.01, hr.size.y), Vector3(hc.x, 0.03, hc.y), HILL_COLOR, false)


func _build_walls() -> void:
	var hx := ArenaMap.HALF.x
	var hy := ArenaMap.HALF.y
	var t := 1.0
	var c := Color(0.35, 0.35, 0.38)
	_box(nav_region, Vector3(hx * 2.0 + t * 2.0, WALL_H, t), Vector3(0, WALL_H * 0.5, -hy - t * 0.5), c, true)
	_box(nav_region, Vector3(hx * 2.0 + t * 2.0, WALL_H, t), Vector3(0, WALL_H * 0.5, hy + t * 0.5), c, true)
	_box(nav_region, Vector3(t, WALL_H, hy * 2.0), Vector3(-hx - t * 0.5, WALL_H * 0.5, 0), c, true)
	_box(nav_region, Vector3(t, WALL_H, hy * 2.0), Vector3(hx + t * 0.5, WALL_H * 0.5, 0), c, true)


func _build_prop(p: Dictionary) -> void:
	var kind: StringName = p["k"]
	var r: Rect2 = p["rect"]
	var def: Dictionary = ArenaMap.KINDS[kind]
	var col: Color = KIND_COLORS.get(kind, Color(0.5, 0.5, 0.5))
	var hex: String = p.get("color", "")
	if hex != "" and Color.html_is_valid(hex):
		col = Color.html(hex)
	var c := r.get_center()
	if def.is_empty():
		_box(self, Vector3(r.size.x, DECAL_H, r.size.y), Vector3(c.x, 0.02 + DECAL_H * 0.5, c.y), col, false)
		return
	var h := WALL_H if def["tall"] else (COVER_H if def["cover"] else FENCE_H)
	var n := _box(nav_region, Vector3(r.size.x, h, r.size.y), Vector3(c.x, h * 0.5, c.y), col, true)
	n.name = String(kind)


func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)
