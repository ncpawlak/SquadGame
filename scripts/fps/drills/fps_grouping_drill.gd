class_name FpsGroupingDrill
extends FpsDrill
## Recoil / burst grouping (GROUPING): empty a burst at a wall; the tighter the group, the better, wherever it lands.

const WALL_Z := -20.0
## Mean distance from the group's centre (metres at 20 m) that scores zero.
const REF_SPREAD := 0.9

var burst := 10
var points: Array = []


func _init() -> void:
	super()
	stat = Stats.GROUPING
	title = "Burst grouping"
	instructions = "Hold fire and keep the group tight."
	duration = 20.0
	player_spawn = Vector3(0, 0.1, 0)


func _build() -> void:
	add_box(Vector3(0, 2.0, WALL_Z - 0.25), Vector3(8, 4, 0.5), Color(0.6, 0.6, 0.62))
	var ring := add_box(Vector3(0, 1.6, WALL_Z + 0.01), Vector3(0.6, 0.6, 0.02), Color(0.9, 0.2, 0.2))
	ring.collision_layer = 0


func _begin() -> void:
	points.clear()


func _shot(hit: Dictionary) -> void:
	if bool(hit.get("hit", false)) and hit.has("position"):
		var p: Vector3 = hit["position"]
		points.append(Vector3(p.x, p.y, 0.0))
	if shots >= burst:
		finish(_final_score())


func _final_score() -> float:
	return FpsDrill.grouping_score(points, burst, REF_SPREAD)


func _hud_extra() -> String:
	return "Rounds %d / %d" % [shots, burst]
