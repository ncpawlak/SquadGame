class_name FpsCalloutsDrill
extends FpsDrill
## Squad callouts (TEAMWORK): you cannot move. Four numbered, coloured targets stand in a row. A call lights them one at a
## time; repeat it by shooting the targets in the same order. Each round adds one to the call (it starts at three), five
## rounds. A wrong target ends the round with partial credit (the share you got right), as in the 2D Sequence task.

const COUNT := 4
const ROUNDS := 5
const START_LEN := 3
const DISTANCE := 10.0
const SPACING := 2.0
## Seconds between callouts, how long each stays lit, the pause before a round and how long you get to answer.
const STEP := 0.7
const LIT_SECS := 0.45
const PAUSE := 0.8
const ANSWER_BASE := 2.0
const ANSWER_PER := 1.5
const COLORS := [Color(0.9, 0.2, 0.2), Color(0.25, 0.45, 0.95), Color(0.25, 0.8, 0.3), Color(0.95, 0.8, 0.2)]

enum Phase { PAUSE, SHOWING, ANSWERING }

var targets: Array = []  # FpsDrillTarget, left to right
var labels: Array = []
var sequence: Array = []
var phase: Phase = Phase.PAUSE
## One value per finished round (0..1).
var round_values: Array = []
var round_index := 0
var got := 0
var _clock := 0.0
var _show_i := 0
var _show_t := 0.0
var _lit := -1
var _lit_left := 0.0


func _init() -> void:
	super()
	stat = Stats.TEAMWORK
	title = "Squad callouts"
	instructions = "You cannot move. Watch the targets light up, then shoot them in the same order."
	duration = 120.0
	lock_player = true
	weapon_mode = &"semi"  # full auto sprays other targets and fails the round, so one shot per click
	allow_reload = false
	# Aim is 99 so a miss is a mistake, not the soldier's ratings; teamwork stays standard (this drill scores your attention).
	loadout = {Stats.SHORT_ACC: 99, Stats.MEDIUM_ACC: 99, Stats.LONG_ACC: 99}


# ---- scoring rules (pure) -------------------------------------------------------------------------------------------

## The call for a round: `START_LEN + round` targets, deterministic by seed.
static func make_sequence(seed_value: int, round_i: int, start_len: int = START_LEN, count: int = COUNT) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 1000 + round_i
	var out: Array = []
	for i in start_len + round_i:
		out.append(r.randi_range(0, count - 1))
	return out


## A round's value: all of it right is 1, a wrong shot (or running out of time) keeps the share already right.
static func round_value(correct: int, length: int) -> float:
	if length <= 0:
		return 0.0
	return FpsDrill.clamp01(float(correct) / float(length))


## The drill score: the mean round value over `rounds` (rounds never reached count 0).
static func callouts_score(values: Array, rounds: int = ROUNDS) -> float:
	return FpsDrill.mean_value(values, rounds)


static func answer_time(length: int) -> float:
	return ANSWER_BASE + ANSWER_PER * float(length)


# ---- run ------------------------------------------------------------------------------------------------------------

func _build() -> void:
	for i in COUNT:
		var t := FpsDrillTarget.new()
		t.sticky = true
		t.position = Vector3((i - (COUNT - 1) / 2.0) * SPACING, 0.0, -DISTANCE)
		add_child(t)
		t.set_up(true)
		t.hit.connect(_on_target_hit.bind(i))
		targets.append(t)
		var l := Label3D.new()
		l.text = str(i + 1)
		l.font_size = 96
		l.pixel_size = 0.01
		l.outline_size = 24
		l.position = Vector3(0, 1.6, 0.1)
		t.add_child(l)
		labels.append(l)
	_paint()


func _begin() -> void:
	round_values.clear()
	round_index = 0
	_new_round()


func _new_round() -> void:
	sequence = make_sequence(rng.seed, round_index)
	got = 0
	phase = Phase.PAUSE
	_clock = 0.0
	_show_i = 0
	_show_t = 0.0
	_lit = -1
	_lit_left = 0.0
	_paint()


func _run(delta: float) -> void:
	_lit_left = maxf(0.0, _lit_left - delta)
	if _lit_left <= 0.0 and _lit != -1:
		_lit = -1
		_paint()
	match phase:
		Phase.PAUSE:
			_clock += delta
			if _clock >= PAUSE:
				phase = Phase.SHOWING
				_show_t = STEP  # the first call lights straight away
		Phase.SHOWING:
			_show_t += delta
			if _show_t >= STEP:
				_show_t = 0.0
				if _show_i >= sequence.size():
					phase = Phase.ANSWERING
					_clock = 0.0
				else:
					_light(int(sequence[_show_i]), LIT_SECS)
					_show_i += 1
		Phase.ANSWERING:
			_clock += delta
			if _clock >= answer_time(sequence.size()):
				_end_round()


func _light(i: int, secs: float) -> void:
	_lit = i
	_lit_left = secs
	_paint()


func _paint() -> void:
	for i in targets.size():
		var c: Color = COLORS[i]
		(targets[i] as FpsDrillTarget).set_tint(c if i == _lit else c.darkened(0.65))


func _on_target_hit(_head: bool, i: int) -> void:
	if state != State.RUNNING or phase != Phase.ANSWERING:
		return
	_light(i, 0.2)
	if i == int(sequence[got]):
		got += 1
		if got >= sequence.size():
			_end_round()
	else:
		_end_round()


func _end_round() -> void:
	round_values.append(round_value(got, sequence.size()))
	round_index += 1
	if round_index >= ROUNDS:
		finish(_final_score())
	else:
		_new_round()


func _final_score() -> float:
	return callouts_score(round_values)


func _hud_extra() -> String:
	var what := "Watch..." if phase != Phase.ANSWERING else "Repeat it: %d / %d" % [got, sequence.size()]
	return "Round %d / %d   %s" % [mini(round_index + 1, ROUNDS), ROUNDS, what]
