class_name FpsPopupDrill
extends FpsDrill
## Shared body of drills that pop targets up on a seeded schedule (range, hold the point). Subclasses fill `slot_points`
## and call `_make_targets()`; hits and misses are tallied here.

var targets: Array = []           # FpsDrillTarget per slot
var slot_points: Array = []       # Vector3 per slot (target feet position)
var schedule: Array = []
var target_count := 10
var target_life := 1.8
var first_at := 1.0
var gap_min := 0.8
var gap_max := 1.6
var _next := 0
var hits := 0
var headshots := 0
var popped := 0


func _make_targets() -> void:
	for p in slot_points:
		var t := FpsDrillTarget.new()
		t.position = p
		t.hit.connect(_on_target_hit.bind(t))
		add_child(t)
		targets.append(t)


func _begin() -> void:
	schedule = FpsDrill.make_schedule(rng.randi(), target_count, slot_points.size(), first_at, gap_min, gap_max, target_life)
	_next = 0
	hits = 0
	headshots = 0
	popped = 0


func _run(_delta: float) -> void:
	# Pop everything that is due, in order; a slot that is still up is simply refreshed.
	while _next < schedule.size() and schedule[_next]["at"] <= elapsed:
		var e: Dictionary = schedule[_next]
		var t: FpsDrillTarget = targets[e["slot"]]
		t.pop(float(e["at"]), float(e["life"]))
		popped += 1
		_next += 1
	for t in targets:
		if t.up and t.expires <= elapsed:
			t.set_up(false)
	# Everything shown and nothing left standing: done early.
	if _next >= schedule.size() and not _any_up():
		finish(_final_score())


func _any_up() -> bool:
	for t in targets:
		if t.up:
			return true
	return false


func _on_target_hit(head: bool, t: FpsDrillTarget = null) -> void:
	if state != State.RUNNING:
		return
	hits += 1
	if head:
		headshots += 1
	_hit_made()
	_hit_by(t)


func _hit_made() -> void:
	pass


## Like _hit_made but knows which target was hit.
func _hit_by(_t: FpsDrillTarget) -> void:
	pass


func _end() -> void:
	for t in targets:
		t.set_up(false)
