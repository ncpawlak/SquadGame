class_name FpsHoldDrill
extends FpsPopupDrill
## Hold-the-point (ANCHOR): stay inside the zone while intruders pop up around it; shoot them without leaving.

const ZONE_CENTRE := Vector3(0, 0, -10)
const ZONE_RADIUS := 3.0

var in_zone := 0.0


func _init() -> void:
	super()
	stat = Stats.ANCHOR
	title = "Hold the point"
	instructions = "Stay in the circle and drop everything that pops up."
	target_count = 12
	target_life = 2.2
	gap_min = 1.0
	gap_max = 1.8
	duration = 25.0
	player_spawn = ZONE_CENTRE + Vector3(0, 0.1, 0)
	for i in 6:
		var a := TAU * float(i) / 6.0
		slot_points.append(ZONE_CENTRE + Vector3(sin(a), 0, -cos(a)) * 14.0)


func _build() -> void:
	var disc := add_box(ZONE_CENTRE + Vector3(0, 0.02, 0), Vector3(ZONE_RADIUS * 2.0, 0.04, ZONE_RADIUS * 2.0), Color(0.9, 0.9, 0.2))
	disc.collision_layer = 0
	_make_targets()
	# Intruders face the zone.
	for t in targets:
		t.look_at_from_position(t.position, Vector3(ZONE_CENTRE.x, t.position.y, ZONE_CENTRE.z), Vector3.UP, true)


func _begin() -> void:
	super()
	in_zone = 0.0


func _run(delta: float) -> void:
	if player != null:
		var p := player.global_position
		if Vector2(p.x - ZONE_CENTRE.x, p.z - ZONE_CENTRE.z).length() <= ZONE_RADIUS:
			in_zone += delta
	super(delta)


func _final_score() -> float:
	return FpsDrill.hold_score(in_zone, maxf(elapsed, 0.001), hits, target_count)


func _hud_extra() -> String:
	return "Down %d / %d" % [hits, target_count]
