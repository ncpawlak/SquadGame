class_name Portrait
extends Control
## Profile picture: the soldier's photo face (see FaceSpec) on a disc in his team's colours, with the team logo
## faintly behind. The head is one of the baked cutouts, warped by a small anchor-driven grid, tinted by a shader and
## clipped to the circle. Soldiers without a team (free agents, prospects) get a neutral disc and jersey.

const NEUTRAL_PRIMARY := Color("#8a7d5c")
const NEUTRAL_SECONDARY := Color("#5b6470")
const SHADER := preload("res://assets/shaders/portrait_face.gdshader")

## Face placement, as fractions of the portrait diameter: face width, and where the face centre sits from the top.
const FACE_WIDTH := 0.5
const FACE_CY := 0.47
const GRID_X := 10
const GRID_Y := 12

static var _mesh_cache := {}
static var _tex_cache := {}

var soldier: Soldier
var _p: Color
var _ring: Color
var _logo: Texture2D
var _face_node: Control
var _ring_node: Control


func _init(s: Soldier, diameter := 48, ring := UiKit.LINE, team: Team = null) -> void:
	soldier = s
	_ring = ring
	_p = team.color.darkened(0.12) if team != null else NEUTRAL_PRIMARY
	# Logo of the team he actually plays for (not a team just previewing him, e.g. a free agent).
	if team != null and team.roster.has(s):
		_logo = UiKit.logo_tex(team.abbrev)
	custom_minimum_size = Vector2(diameter, diameter)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face_node = Control.new()
	_face_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_face_node.material = _make_material(s)
	_face_node.draw.connect(_draw_face)
	add_child(_face_node)
	_ring_node = Control.new()
	_ring_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring_node.draw.connect(_draw_ring)
	add_child(_ring_node)


func _draw() -> void:
	var d: float = minf(size.x, size.y)
	var c := size / 2.0
	draw_circle(c, d / 2.0, _p.darkened(0.78).lerp(Color("#111827"), 0.35))
	if _logo != null and d >= 40.0:
		var ls := d * 0.86
		draw_texture_rect(_logo, Rect2(c - Vector2(ls, ls) / 2.0, Vector2(ls, ls)), false, Color(1, 1, 1, 0.22))


func _draw_ring() -> void:
	var d: float = minf(size.x, size.y)
	_ring_node.draw_arc(size / 2.0, d / 2.0 - 1.0, 0.0, TAU, 48, _ring, 2.0, true)


func _make_material(s: Soldier) -> ShaderMaterial:
	var f := s.get_face()
	var head: Dictionary = FaceSpec.db()["heads"][f.head_id]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("mask_tex", _tex(f.head_id + "_m.png"))
	var tint: Array = FaceSpec.HAIR_TINTS[f.tint]
	var add: Array = tint[2]
	m.set_shader_parameter("hair_mul", Vector3(tint[1], tint[1], tint[1]))
	m.set_shader_parameter("hair_add", Vector3(add[0], add[1], add[2]))
	m.set_shader_parameter("gray", f.gray_at(s.age))
	var eye: Array = FaceSpec.EYE_COLORS[f.eye_color]
	m.set_shader_parameter("eye_on", 1.0)
	m.set_shader_parameter("eye_hue", eye[0])
	m.set_shader_parameter("eye_sat", eye[1])
	var tc := _p.lightened(0.05)
	m.set_shader_parameter("team_col", Vector3(tc.r, tc.g, tc.b))
	m.set_shader_parameter("jersey_v", (head["cy"] + head["fw"] * 0.72) / head["h"])
	return m


func _draw_face() -> void:
	var d: float = minf(size.x, size.y)
	var f := soldier.get_face()
	var head: Dictionary = FaceSpec.db()["heads"][f.head_id]
	var m := _face_node.material as ShaderMaterial
	var k: float = d * FACE_WIDTH / float(head["fw"])
	var w := float(head["w"])
	var cx: float = w - float(head["cx"]) if f.flip else float(head["cx"])
	var xf := Transform2D(Vector2(k, 0), Vector2(0, k), Vector2(size.x / 2.0 - cx * k, d * FACE_CY - float(head["cy"]) * k))
	# The shader sees head-image pixels, so hand it the portrait circle in those coordinates.
	m.set_shader_parameter("clip_center", (size / 2.0 - xf.origin) / k)
	m.set_shader_parameter("clip_radius", (d / 2.0 - 1.0) / k)
	_face_node.draw_mesh(_mesh(soldier.id, f, head), _tex(f.head_id + ".webp"), xf)


static func _tex(file: String) -> Texture2D:
	if not _tex_cache.has(file):
		_tex_cache[file] = load(FaceSpec.HEADS_DIR + file)
	return _tex_cache[file]


## Forget a soldier's warped mesh (his face changed, e.g. in Data Edit).
static func drop_cached_mesh(id: int) -> void:
	_mesh_cache.erase(id)


static func _mesh(id: int, f: FaceSpec, head: Dictionary) -> ArrayMesh:
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	var mesh := FaceWarp.build_mesh(head, FaceSpec.db()["indices"], f.morph, f.flip, GRID_X, GRID_Y)
	_mesh_cache[id] = mesh
	return mesh
