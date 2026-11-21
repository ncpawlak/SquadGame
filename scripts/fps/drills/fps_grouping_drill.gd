class_name FpsGroupingDrill
extends FpsDrill
## Grouping (GROUPING): six targets in a ring around you, you cannot move. Shoot every target (one shot each), three times
## round. The score is how tightly your three shots group on each target, however far from the bullseye the group is.

const RING_RADIUS := 6.0
const TARGETS := 6
const PASSES := 3
## Mean distance from a target's group centre (metres) that scores zero.
const REF_SPREAD := 0.25
const READY_COLOR := Color(0.85, 0.25, 0.2)
const WAIT_COLOR := Color(0.45, 0.45, 0.5)

var targets: Array = []  # FpsDrillTarget
var shot_points: Array = []  # per target: Array of Vector2 (face offsets from the bullseye)


func _init() -> void:
	super()
	stat = Stats.GROUPING
	title = "Grouping"
	instructions = "You cannot move. Shoot all six targets, three times round. Keep your shots tight on each target."
	duration = 90.0
	lock_player = true
	weapon_mode = &"semi"
	# Accuracy, grouping and sway are 99 for the standard loadout, so the spread of your shots is your own aim.
	loadout = {Stats.SHORT_ACC: 99, Stats.MEDIUM_ACC: 99, Stats.LONG_ACC: 99, Stats.GROUPING: 99, Stats.SWAY: 99}


func _build() -> void:
	for i in TARGETS:
		var ang := TAU * float(i) / float(TARGETS)
		var t := FpsDrillTarget.new()
		t.sticky = true
		t.position = Vector3(sin(ang), 0.0, -cos(ang)) * RING_RADIUS
		# Face the middle of the ring: the target's front is +Z, and turning by -ang points it back at the player.
		t.rotation.y = -ang
		add_child(t)
		t.set_up(true)
		t.hit.connect(_on_hit.bind(t))
		targets.append(t)
		shot_points.append([])


func _begin() -> void:
	for p in shot_points:
		p.clear()
	_refresh_armed()


## A target takes a shot only if it has fewer than the current pass: so every pass is all six targets.
func _pass_index() -> int:
	var low := PASSES
	for p in shot_points:
		low = mini(low, p.size())
	return low


func _refresh_armed() -> void:
	var pass_i := _pass_index()
	for i in targets.size():
		(targets[i] as FpsDrillTarget).set_tint(READY_COLOR if shot_points[i].size() <= pass_i and shot_points[i].size() < PASSES else WAIT_COLOR)


func _on_hit(_head: bool, t: FpsDrillTarget) -> void:
	if state != State.RUNNING:
		return
	var i := targets.find(t)
	if i < 0 or shot_points[i].size() > _pass_index() or shot_points[i].size() >= PASSES:
		return
	shot_points[i].append(t.face_offset(t.last_hit_pos))
	_refresh_armed()
	if _pass_index() >= PASSES:
		finish(_final_score())


func _final_score() -> float:
	return FpsDrill.group_ring_score(shot_points, REF_SPREAD)


func _hud_extra() -> String:
	return "Round %d of %d" % [mini(_pass_index() + 1, PASSES), PASSES]
