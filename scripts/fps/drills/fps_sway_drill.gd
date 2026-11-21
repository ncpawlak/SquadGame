class_name FpsSwayDrill
extends FpsDrill
## Scope-sway hold-and-shoot (SWAY): keep the crosshair inside a ring for the hold, then take the one shot on the cue.
## The sway itself comes from the player's weapon; the drill only measures where the aim is.

const TARGET_Z := -25.0
const TARGET_Y := 1.6
const RING := 0.5
const HOLD := 7.0
## The scope's idle sway is exaggerated for the drill so the drift is something you fight (the standard sway rating of 50
## on a normal rifle moves the crosshair too little to notice).
const SWAY_MULT := 14.0
const BREATH_DRAIN := 0.3
const BREATH_RECOVER := 0.2
const STEADY_HELD := 0.15
const STEADY_WINDED := 1.6

var on_target := 0.0
var shot_dist := -1.0
var cue := false
var breath := 1.0
var winded := false
## Tests drive the breath hold with this; real play reads Shift or the right mouse button.
var forced_hold := false
var _hooked: Object = null


func _init() -> void:
	super()
	stat = Stats.SWAY
	title = "Hold steady"
	instructions = "Your scope sways. Keep the crosshair in the ring. Hold Shift or the right mouse button to steady it, but your breath runs out. Shoot when FIRE shows."
	duration = HOLD + 5.0
	lock_player = true
	weapon_mode = &"semi"
	allow_reload = false
	# Aim is 99 so the shot is yours; the sway rating stays standard (the drill measures how steadily YOU hold).
	loadout = {Stats.SHORT_ACC: 99, Stats.MEDIUM_ACC: 99, Stats.LONG_ACC: 99}


func _build() -> void:
	var disc := add_box(Vector3(0, TARGET_Y, TARGET_Z), Vector3(RING * 2.0, RING * 2.0, 0.05), Color(0.95, 0.85, 0.2))
	disc.collision_layer = 0
	add_box(Vector3(0, TARGET_Y, TARGET_Z + 0.03), Vector3(RING * 0.5, RING * 0.5, 0.05), Color(0.8, 0.15, 0.15)).collision_layer = 0
	add_box(Vector3(0, 2.5, TARGET_Z - 1.0), Vector3(12, 5, 1), Color(0.5, 0.5, 0.55)).collision_layer = 1


func _begin() -> void:
	on_target = 0.0
	shot_dist = -1.0
	cue = false
	breath = 1.0
	winded = false
	var w = player.get("weapon") if player != null and "weapon" in player else null
	if w != null:
		w.sway_mult = SWAY_MULT
		_hooked = w


func _end() -> void:
	if _hooked != null and is_instance_valid(_hooked):
		_hooked.sway_mult = 1.0
		_hooked.steady = 1.0
	_hooked = null


## How steady the scope is this frame (1 = full sway): holding your breath calms it, running out makes it worse.
static func steady_for(holding: bool, p_breath: float, p_winded: bool) -> float:
	if p_winded:
		return STEADY_WINDED
	if holding and p_breath > 0.0:
		return STEADY_HELD
	return 1.0


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
	var held := forced_hold or Input.is_key_pressed(KEY_SHIFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if held and not winded and breath > 0.0:
		breath = maxf(0.0, breath - BREATH_DRAIN * delta)
		if breath <= 0.0:
			winded = true
	else:
		breath = minf(1.0, breath + BREATH_RECOVER * delta)
		if winded and breath >= 0.35:
			winded = false
	if _hooked != null and is_instance_valid(_hooked):
		_hooked.steady = FpsSwayDrill.steady_for(held, breath, winded)
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
	var bar := "#".repeat(roundi(breath * 10.0)) + "-".repeat(10 - roundi(breath * 10.0))
	var lead := "FIRE!" if cue else "Hold... %.1f" % maxf(HOLD - elapsed, 0.0)
	return "%s     breath [%s]%s" % [lead, bar, "  WINDED" if winded else ""]
