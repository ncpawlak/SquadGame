class_name FpsSwayDrill
extends FpsDrill
## Scope-sway hold-and-shoot (SWAY): keep the crosshair inside a ring for the hold, then take the one shot on the cue.
## The sway itself comes from the player's weapon; the drill only measures where the aim is.

const TARGET_Z := -40.0
const TARGET_Y := 1.6
const RING := 0.4
const HOLD := 6.0

var on_target := 0.0
var shot_dist := -1.0
var cue := false


func _init() -> void:
	super()
	stat = Stats.SWAY
	title = "Hold steady"
	instructions = "Keep the crosshair in the ring, then shoot on FIRE."
	duration = HOLD + 4.0


func _build() -> void:
	var disc := add_box(Vector3(0, TARGET_Y, TARGET_Z), Vector3(RING * 2.0, RING * 2.0, 0.05), Color(0.95, 0.85, 0.2))
	disc.collision_layer = 0
	add_box(Vector3(0, 2.5, TARGET_Z - 1.0), Vector3(12, 5, 1), Color(0.5, 0.5, 0.55)).collision_layer = 1


func _begin() -> void:
	on_target = 0.0
	shot_dist = -1.0
	cue = false


## Distance in metres between where the aim crosses the target plane and the ring centre (large if aiming away).
func aim_error() -> float:
	var d := aim_direction()
	var o := aim_origin()
	return FpsSwayDrill.plane_error(o, d, TARGET_Z, Vector2(0, TARGET_Y))


static func plane_error(origin: Vector3, dir: Vector3, plane_z: float, centre: Vector2) -> float:
	if dir.z > -0.0001:
		return 999.0
	var t := (plane_z - origin.z) / dir.z
	var p := origin + dir * t
	return Vector2(p.x, p.y).distance_to(centre)


func _run(delta: float) -> void:
	cue = elapsed >= HOLD
	if not cue and aim_error() <= RING:
		on_target += delta


func _shot(hit: Dictionary) -> void:
	if shot_dist >= 0.0:
		return
	if not cue:
		# Jumped the gun: the shot counts as a miss.
		shot_dist = RING * 10.0
	else:
		shot_dist = aim_error()
		if hit.has("position") and bool(hit.get("hit", false)):
			var p: Vector3 = hit["position"]
			shot_dist = Vector2(p.x, p.y).distance_to(Vector2(0, TARGET_Y))
	finish(_final_score())


func _final_score() -> float:
	return FpsDrill.sway_score(on_target, HOLD, shot_dist, RING * 2.0)


func _hud_extra() -> String:
	return "FIRE!" if cue else "Hold... %.1f" % maxf(HOLD - elapsed, 0.0)
