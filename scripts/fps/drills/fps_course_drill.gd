class_name FpsCourseDrill
extends FpsDrill
## Agility / obstacle course scored on time. Leg 1 is a straight sprint (SPEED), leg 2 a slalom around obstacles
## (AGILITY). Gates must be reached in order. `stat_scores()` returns both stats.

const GATE_RADIUS := 2.0
const SPRINT_PAR := 4.5
const SPRINT_LIMIT := 10.0
const SLALOM_PAR := 12.0
const SLALOM_LIMIT := 30.0

## Gate centres on the ground (XZ matters). The first SPRINT_GATES gates form the sprint leg.
const SPRINT_GATES := 2
const GATES: Array[Vector3] = [
	Vector3(0, 0, -12), Vector3(0, 0, -30),
	Vector3(-4, 0, -40), Vector3(4, 0, -50), Vector3(-4, 0, -60), Vector3(4, 0, -70), Vector3(0, 0, -80),
]

var gate_index := 0
## Time each gate was reached, in order.
var gate_times: Array = []


func _init() -> void:
	super()
	stat = Stats.AGILITY
	title = "Obstacle course"
	instructions = "Sprint to the line, then weave through the gates."
	duration = 45.0


func _build() -> void:
	for i in GATES.size():
		var g := GATES[i]
		var m := add_box(g + Vector3(0, 0.05, 0), Vector3(GATE_RADIUS * 2.0, 0.1, GATE_RADIUS * 2.0), Color(0.2, 0.7, 0.9) if i >= SPRINT_GATES else Color(0.9, 0.7, 0.2))
		m.collision_layer = 0
	# Slalom obstacles between the gates.
	for z in [-45.0, -55.0, -65.0, -75.0]:
		add_box(Vector3(0, 1.0, z), Vector3(1.2, 2.0, 1.2), Color(0.5, 0.35, 0.25))


func _begin() -> void:
	gate_index = 0
	gate_times.clear()


func _run(_delta: float) -> void:
	if player == null or gate_index >= GATES.size():
		return
	if FpsCourseDrill.gate_reached(player.global_position, GATES[gate_index], GATE_RADIUS):
		gate_times.append(elapsed)
		gate_index += 1
		if gate_index >= GATES.size():
			finish(_final_score())


static func gate_reached(pos: Vector3, gate: Vector3, radius: float) -> bool:
	return Vector2(pos.x - gate.x, pos.z - gate.z).length() <= radius


## {speed, agility} each 0..1 from the leg times (a leg not finished scores 0).
static func leg_scores(sprint_time: float, slalom_time: float) -> Dictionary:
	return {
		Stats.SPEED: 0.0 if sprint_time < 0.0 else FpsDrill.time_score(sprint_time, SPRINT_PAR, SPRINT_LIMIT),
		Stats.AGILITY: 0.0 if slalom_time < 0.0 else FpsDrill.time_score(slalom_time, SLALOM_PAR, SLALOM_LIMIT),
	}


func _leg_times() -> Array:
	var sprint := -1.0
	var slalom := -1.0
	if gate_times.size() >= SPRINT_GATES:
		sprint = float(gate_times[SPRINT_GATES - 1])
	if gate_times.size() >= GATES.size():
		slalom = float(gate_times[GATES.size() - 1]) - sprint
	return [sprint, slalom]


func stat_scores() -> Dictionary:
	var t := _leg_times()
	return FpsCourseDrill.leg_scores(t[0], t[1])


func _final_score() -> float:
	var s := stat_scores()
	return FpsDrill.clamp01((float(s[Stats.SPEED]) + float(s[Stats.AGILITY])) * 0.5)


func _hud_extra() -> String:
	return "Gate %d / %d" % [mini(gate_index + 1, GATES.size()), GATES.size()]
