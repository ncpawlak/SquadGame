class_name FpsRangeDrill
extends FpsPopupDrill
## Popup-target range at one distance. SHORT_ACC / MEDIUM_ACC / LONG_ACC use the same drill at 10, 25 and 50 m.

const RANGES := {
	Stats.SHORT_ACC: {"dist": 10.0, "life": 2.0, "title": "Short range"},
	Stats.MEDIUM_ACC: {"dist": 25.0, "life": 1.8, "title": "Medium range"},
	Stats.LONG_ACC: {"dist": 50.0, "life": 1.6, "title": "Long range"},
}
const SLOTS := 5
const SPACING := 1.8


## Build a range drill for a stat (SHORT_ACC, MEDIUM_ACC or LONG_ACC).
static func make(for_stat: StringName) -> FpsRangeDrill:
	var d := FpsRangeDrill.new()
	d.configure(for_stat)
	return d


func configure(for_stat: StringName) -> void:
	var cfg: Dictionary = RANGES.get(for_stat, RANGES[Stats.SHORT_ACC])
	stat = for_stat if RANGES.has(for_stat) else Stats.SHORT_ACC
	title = cfg["title"]
	target_life = cfg["life"]
	distance = cfg["dist"]
	instructions = "You cannot move. Shoot each target fast and as close to the bullseye as you can."
	lock_player = true
	weapon_mode = &"semi"
	# Accuracy is 99 for the standard loadout, so the score is your aim, not the soldier's rating.
	loadout = {Stats.SHORT_ACC: 99, Stats.MEDIUM_ACC: 99, Stats.LONG_ACC: 99}
	target_count = 10
	duration = first_at + target_count * gap_max + target_life + 1.0
	slot_points.clear()
	for i in SLOTS:
		slot_points.append(Vector3((i - (SLOTS - 1) / 2.0) * SPACING, 0.0, -distance))


var distance := 10.0
## Set in the scene files: which range this scene is.
@export var range_stat: StringName = Stats.SHORT_ACC:
	set(v):
		range_stat = v
		configure(v)


func _init() -> void:
	super()
	configure(Stats.SHORT_ACC)


func _build() -> void:
	_make_targets()


var values: Array = []


func _begin() -> void:
	super()
	values.clear()


## Each hit is worth how quickly it came after the target popped and how close it was to the bullseye.
func _hit_by(t: FpsDrillTarget) -> void:
	if t == null:
		return
	values.append(FpsDrill.pop_value(elapsed - t.popped_at, target_life, t.closeness(t.last_hit_pos)))


func _final_score() -> float:
	return FpsDrill.mean_value(values, target_count)


func _hud_extra() -> String:
	return "Hits %d / %d" % [hits, target_count]
