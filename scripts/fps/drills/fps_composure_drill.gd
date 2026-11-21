class_name FpsComposureDrill
extends FpsPopupDrill
## Under fire (COMPOSURE): you cannot move. Waves of popup targets come faster and faster while suppressive fire is
## called on you (the crosshair shakes and the screen goes white at the edges). The first wave is calm: that is your
## baseline. The score is how much of it you keep, in accuracy and speed, once the fire starts.

## The waves. count targets per wave; targets pop every gap_min..gap_max seconds and stay up `life`; from `lead` seconds
## before the wave's first target the player is shot at (`suppress` per burst, one burst every `every` seconds).
const PHASES := [
	{"count": 6, "gap_min": 1.5, "gap_max": 1.9, "life": 2.0, "suppress": 0.0, "every": 0.5},
	{"count": 6, "gap_min": 1.1, "gap_max": 1.4, "life": 1.8, "suppress": 0.3, "every": 0.5},
	{"count": 7, "gap_min": 0.85, "gap_max": 1.1, "life": 1.5, "suppress": 0.45, "every": 0.45},
	{"count": 8, "gap_min": 0.65, "gap_max": 0.85, "life": 1.3, "suppress": 0.6, "every": 0.4},
]
const LEAD := 0.6
## The calm baseline never counts for less than this, so a poor opening cannot make a poor finish look like a good one.
const BASELINE_FLOOR := 0.3
const RETENTION_SHARE := 0.6
const SLOTS := 5
const SPACING := 1.6
const DISTANCE := 15.0

## Per wave: the value (0..1) of each target that was hit.
var phase_values: Array = []
var suppress_log: Array = []   # every burst sent at the player: {at, amount}
var _events: Array = []
var _next_event := 0


func _init() -> void:
	super()
	stat = Stats.COMPOSURE
	title = "Under fire"
	instructions = "You cannot move. Keep hitting the targets as the fire on you gets heavier."
	lock_player = true
	# Aim is 99 so the shots are yours; composure stays at the standard 50, so the shake is the standard amount.
	loadout = {Stats.SHORT_ACC: 99, Stats.MEDIUM_ACC: 99, Stats.LONG_ACC: 99}
	target_count = total_targets()
	first_at = 1.0
	duration = last_pop_time(FpsComposureDrill.make_phase_schedule(1, SLOTS, first_at)) + 3.0
	for i in SLOTS:
		slot_points.append(Vector3((i - (SLOTS - 1) / 2.0) * SPACING, 0.0, -DISTANCE))


# ---- scoring rules (pure) -------------------------------------------------------------------------------------------

static func total_targets() -> int:
	var n := 0
	for p in PHASES:
		n += int(p["count"])
	return n


static func last_pop_time(schedule: Array) -> float:
	return float(schedule[schedule.size() - 1]["at"]) + float(schedule[schedule.size() - 1]["life"]) if not schedule.is_empty() else 0.0


## Deterministic schedule over all waves: entries {slot, at, life, phase}, never the same slot twice in a row.
static func make_phase_schedule(seed_value: int, slots: int, first: float) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var out: Array = []
	var t := first
	var last := -1
	for pi in PHASES.size():
		var p: Dictionary = PHASES[pi]
		for i in int(p["count"]):
			var slot := 0
			if slots > 1:
				slot = r.randi_range(0, slots - 1)
				if slot == last:
					slot = (slot + 1 + r.randi_range(0, slots - 2)) % slots
			out.append({"slot": slot, "at": t, "life": float(p["life"]), "phase": pi})
			last = slot
			t += r.randf_range(float(p["gap_min"]), float(p["gap_max"]))
	return out


## The bursts of suppressive fire, from the schedule: {at, amount}. A wave's fire starts LEAD before its first target
## and stops where the next wave's starts (the last wave's runs until its final target is gone).
static func make_suppress_events(schedule: Array) -> Array:
	var starts: Array = []
	for pi in PHASES.size():
		var first_at_p := -1.0
		for e in schedule:
			if int(e["phase"]) == pi:
				first_at_p = float(e["at"])
				break
		starts.append(first_at_p)
	var out: Array = []
	for pi in PHASES.size():
		var p: Dictionary = PHASES[pi]
		var amount := float(p["suppress"])
		if amount <= 0.0 or float(starts[pi]) < 0.0:
			continue
		var t := maxf(float(starts[pi]) - LEAD, 0.0)
		var stop := last_pop_time(schedule) if pi + 1 >= PHASES.size() or float(starts[pi + 1]) < 0.0 else float(starts[pi + 1]) - LEAD
		while t < stop:
			out.append({"at": t, "amount": amount})
			t += float(p["every"])
	return out


## Score from the per-wave hit values: wave 0 is the calm baseline. Retention is how much of the baseline the later
## waves keep (1 = as good as calm); the rest of the score is how well they did outright.
static func composure_score(phase_vals: Array, counts: Array) -> float:
	if phase_vals.size() < 2 or counts.size() < 2:
		return 0.0
	var calm := FpsDrill.mean_value(phase_vals[0], int(counts[0]))
	var later := 0.0
	var n := 0
	for pi in range(1, mini(phase_vals.size(), counts.size())):
		later += FpsDrill.mean_value(phase_vals[pi], int(counts[pi]))
		n += 1
	if n == 0:
		return 0.0
	later /= float(n)
	var retention := FpsDrill.clamp01(later / maxf(calm, BASELINE_FLOOR))
	return FpsDrill.clamp01(RETENTION_SHARE * retention + (1.0 - RETENTION_SHARE) * later)


static func phase_counts() -> Array:
	var out: Array = []
	for p in PHASES:
		out.append(int(p["count"]))
	return out


# ---- run ------------------------------------------------------------------------------------------------------------

func _build() -> void:
	_make_targets()


func _begin() -> void:
	schedule = make_phase_schedule(rng.randi(), slot_points.size(), first_at)
	_events = make_suppress_events(schedule)
	_next = 0
	_next_event = 0
	hits = 0
	headshots = 0
	popped = 0
	suppress_log.clear()
	phase_values.clear()
	for i in PHASES.size():
		phase_values.append([])


func _run(delta: float) -> void:
	while _next_event < _events.size() and float(_events[_next_event]["at"]) <= elapsed:
		var ev: Dictionary = _events[_next_event]
		suppress_log.append(ev)
		if player != null and player.has_method(&"suppress"):
			player.call(&"suppress", float(ev["amount"]))
		_next_event += 1
	super(delta)


## The wave a target belongs to (looked up from when and where it stood up).
func _phase_of(t: FpsDrillTarget) -> int:
	var slot := targets.find(t)
	for e in schedule:
		if int(e["slot"]) == slot and is_equal_approx(float(e["at"]), t.popped_at):
			return int(e["phase"])
	return 0


func _hit_by(t: FpsDrillTarget) -> void:
	if t == null:
		return
	var pi := _phase_of(t)
	var life := t.expires - t.popped_at
	(phase_values[pi] as Array).append(FpsDrill.pop_value(elapsed - t.popped_at, life, t.closeness(t.last_hit_pos)))


## 0 for the calm wave, up to PHASES.size() - 1 for the last, from the clock (for the HUD).
func current_phase() -> int:
	var cur := 0
	for e in schedule:
		if float(e["at"]) <= elapsed:
			cur = int(e["phase"])
	return cur


func _final_score() -> float:
	return composure_score(phase_values, phase_counts())


func _hud_extra() -> String:
	var pi := current_phase()
	return "Wave %d / %d%s\nHits %d / %d" % [pi + 1, PHASES.size(), "  (calm)" if pi == 0 else "  UNDER FIRE", hits, target_count]
