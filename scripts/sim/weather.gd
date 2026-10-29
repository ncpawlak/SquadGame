class_name Weather
extends RefCounted
## Weather for one match: clear, or rain / snow at level 1 (light) or 2 (inclement). Rolled from the
## match seed and the home team's climate (data/climates.json), never from the engine's RNG, so a
## match plays out the same whether it is simulated or watched and old seeds are untouched.
##
## Two effects. Match-wide: every soldier loses rating points (PENALTY). Local: patches of rain or
## snow cover part of the open floor (never a start zone) and a soldier standing in one moves slower
## and dodges worse (SLOW). The patch map is a 1 m grid shared by the engine and the viewer.

const CLIMATES_PATH := "res://data/climates.json"

const CLEAR := &"clear"
const RAIN := &"rain"
const SNOW := &"snow"

## Share of wet matches that are inclement (level 2) rather than light (level 1).
const INCLEMENT_SHARE := 0.35
## Part of the open floor covered by patches, by level (a range, rolled per match).
const COVERAGE := {1: Vector2(0.11, 0.20), 2: Vector2(0.25, 0.50)}
## Rating points taken off these stats for the whole match: [light, inclement].
const PENALTY := {
	RAIN: {"stats": [&"short_acc", &"medium_acc", &"long_acc", &"sway", &"composure"], "points": [3.0, 6.0]},
	SNOW: {"stats": [&"short_acc", &"medium_acc", &"long_acc", &"reload", &"grouping", &"endurance"], "points": [4.0, 8.0]},
}
## Speed and agility multiplier while standing in a patch: [light, inclement].
const SLOW := {RAIN: [0.8, 0.7], SNOW: [0.65, 0.5]}
const LEVEL_NAMES := ["Clear", "Light", "Inclement"]

const COLS := 96
const ROWS := 60

static var _climates: Dictionary = {}
static var _climates_loaded := false

var kind: StringName = CLEAR
## 0 = clear, 1 = light, 2 = inclement.
var level := 0
## Share of the open floor under patches.
var coverage := 0.0
var _seed := 0
var _built_for: ArenaMap = null
## Per 1 m cell (row-major from the north-west corner): 0 = bare floor, else 0.3..1 patch depth.
var _depth := PackedFloat32Array()


static func clear() -> Weather:
	return Weather.new()


## The weather for a match at `home_abbrev`'s field.
static func roll(match_seed: int, home_abbrev: String) -> Weather:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d|%s|weather" % [match_seed, home_abbrev]).hash()
	var odds := climate(home_abbrev)
	# Every roll is drawn even for a clear day so the sequence never depends on the outcome.
	var kind_roll := rng.randf()
	var level_roll := rng.randf()
	var cover_roll := rng.randf()
	var w := Weather.new()
	w._seed = rng.randi()
	if kind_roll < odds["snow"]:
		w.kind = SNOW
	elif kind_roll < odds["snow"] + odds["rain"]:
		w.kind = RAIN
	else:
		return w
	w.level = 2 if level_roll < INCLEMENT_SHARE else 1
	var span: Vector2 = COVERAGE[w.level]
	w.coverage = lerpf(span.x, span.y, cover_roll)
	return w


## {rain, snow}: the chance of each for a home game (a team with no entry never gets weather).
static func climate(abbrev: String) -> Dictionary:
	if not _climates_loaded:
		_climates_loaded = true
		if FileAccess.file_exists(CLIMATES_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CLIMATES_PATH))
			if parsed is Dictionary:
				_climates = parsed
	var c: Dictionary = _climates.get(abbrev, {})
	return {"rain": float(c.get("rain", 0.0)), "snow": float(c.get("snow", 0.0))}


func is_clear() -> bool:
	return level == 0


## "Light Rain", "Inclement Snow" or "Clear".
func label() -> String:
	if is_clear():
		return "Clear"
	return "%s %s" % [LEVEL_NAMES[level], String(kind).capitalize()]


## One line on what it does, for tooltips.
func effect_text() -> String:
	if is_clear():
		return "Clear skies."
	var pts: float = PENALTY[kind]["points"][level - 1]
	var names: Array[String] = []
	for s in PENALTY[kind]["stats"]:
		names.append(Stats.LABELS.get(s, String(s)))
	var slow := int(round((1.0 - float(SLOW[kind][level - 1])) * 100.0))
	var ground := "puddles" if kind == RAIN else "snow patches"
	return "%s on %d%% of the floor. Everyone loses %d points of %s. In %s, soldiers move and dodge %d%% worse." % [
		ground.capitalize(), int(round(coverage * 100.0)), int(pts), ", ".join(names), ground, slow]


## Rating points taken off `stat` for the whole match.
func penalty(stat: StringName) -> float:
	if is_clear() or not PENALTY[kind]["stats"].has(stat):
		return 0.0
	return PENALTY[kind]["points"][level - 1]


# --- patches ---------------------------------------------------------------------

## Lays the patches over `field`: open floor outside the start zones, the wettest cells from a noise
## field until `coverage` is reached. Built once per field.
func prepare(field: ArenaMap) -> void:
	if is_clear() or _built_for == field:
		return
	_built_for = field
	_depth = PackedFloat32Array()
	_depth.resize(COLS * ROWS)
	var noise := FastNoiseLite.new()
	noise.seed = _seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	noise.frequency = 0.09
	var cells := PackedInt32Array()
	var vals := PackedFloat32Array()
	for y in ROWS:
		for x in COLS:
			var c := Vector2(x + 0.5 - ArenaMap.HALF.x, y + 0.5 - ArenaMap.HALF.y)
			if absf(c.x) > ArenaMap.START_X - 0.5 or _under_prop(field, c):
				continue
			cells.append(y * COLS + x)
			vals.append(noise.get_noise_2d(c.x, c.y))
	var take := int(vals.size() * coverage)
	if take < 1:
		return
	var sorted := vals.duplicate()
	sorted.sort()
	var cutoff: float = sorted[vals.size() - take]
	var top: float = sorted[vals.size() - 1]
	for i in vals.size():
		if vals[i] >= cutoff:
			_depth[cells[i]] = lerpf(0.3, 1.0, inverse_lerp(cutoff, top, vals[i]) if top > cutoff else 1.0)


static func _under_prop(field: ArenaMap, p: Vector2) -> bool:
	for r in field.obstacles:
		if r.has_point(p):
			return true
	return false


## Patch depth (0 = bare floor) at a world position.
func depth_at(p: Vector2) -> float:
	if _depth.is_empty():
		return 0.0
	var x := int(floorf(p.x + ArenaMap.HALF.x))
	var y := int(floorf(p.y + ArenaMap.HALF.y))
	if x < 0 or y < 0 or x >= COLS or y >= ROWS:
		return 0.0
	return _depth[y * COLS + x]


func cell_depth(x: int, y: int) -> float:
	return _depth[y * COLS + x] if not _depth.is_empty() else 0.0


func in_patch(p: Vector2) -> bool:
	return depth_at(p) > 0.0


## Speed and agility multiplier at `p` (1.0 on bare floor or in clear weather).
func slow_at(p: Vector2) -> float:
	if is_clear() or depth_at(p) <= 0.0:
		return 1.0
	return SLOW[kind][level - 1]


## Share of the open floor actually covered (for tests and tuning).
func covered_share() -> float:
	var open := 0
	var wet := 0
	for y in ROWS:
		for x in COLS:
			var c := Vector2(x + 0.5 - ArenaMap.HALF.x, y + 0.5 - ArenaMap.HALF.y)
			if absf(c.x) > ArenaMap.START_X - 0.5 or (_built_for != null and _under_prop(_built_for, c)):
				continue
			open += 1
			if cell_depth(x, y) > 0.0:
				wet += 1
	return float(wet) / maxf(1.0, float(open))
