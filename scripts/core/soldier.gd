class_name Soldier
extends RefCounted
## A single player/soldier. Ratings live in `stats`. Each upgradable stat group has a hidden cap
## in `group_caps`: skill points can't raise a group past its cap.
## Two development ratings, both shown:
## - `dev` (1-4 stars): how fast he gains XP. Moves with awards, performance and camp drills.
## - Potential (A-F, potential_grade()): his stat ceiling, i.e. the OVR he'd reach with every
##   group at its cap. Not stored; it falls naturally as aging lowers caps.

const INTENSITY_REST := &"rest"
const INTENSITY_LIGHT := &"light"
const INTENSITY_NORMAL := &"normal"
const INTENSITY_HEAVY := &"heavy"

## Potential grades, worst to best (index = potential_grade()).
const POTENTIAL_LETTERS := ["F", "D", "C", "B", "A"]
const POTENTIAL_A := 4
## Minimum ceiling (potential_ovr) for D, C, B and A.
const POTENTIAL_CUTOFFS := [68, 76, 83, 89]
## Dev trait range (stars).
const DEV_MIN := 1
const DEV_MAX := 4
## Old saves / league data stored a single F..A grade; it maps to stars like this.
const LEGACY_GRADE_TO_DEV := [1, 1, 2, 3, 4]

var id: int
var first_name: String
var last_name: String
var age: int
var stats: Dictionary = {}
## group id -> cap (0-99) for each of Stats.UPGRADABLE_GROUPS.
var group_caps: Dictionary = {}
## Dev trait, 1-4 stars: scales XP gain. Moves at most one star a season.
var dev: int = 2
## Season year of his last dev star change (one change per season).
var dev_year: int = 0
## Year he was drafted (0 = not a draftee). Used for Rookie of the Year.
var draft_year: int = 0
## Overall pick number he went at (0 = undrafted / unknown).
var draft_pick: int = 0
## League-news story kinds already written about him: kind -> year (see LeagueNews).
var news_tags: Dictionary = {}

# Contract / free agency
## Current deal (null = free agent, retired, or a debug soldier).
var contract: Contract = null
## Season year he entered the free-agent pool (free agents only).
var fa_since: int = 0
## Free agents lower their asking price the longer they go unsigned (1.0 = full market value).
var ask_mult: float = 1.0
## Year he retired (0 = active).
var retired_year: int = 0

# Progression (levels are internal: each one just grants skill points)
var level: int = 1
var xp: int = 0
var skill_points: int = 0
## Per-stat "usage" accumulated from match actions since the last level-up.
## Nudges how the AI spends skill points.
var usage: Dictionary = {}

# Condition
## 0-100. Builds from matches and training, recovers each week. Hurts performance above ~50
## and raises injury chance.
var fatigue: float = 0.0
## Weekly training intensity (Soldier.INTENSITY_*).
var intensity: StringName = INTENSITY_NORMAL
## Weeks left on the injury list (0 = healthy).
var injury_weeks: int = 0
var injury_name: String = ""

## Nickname shown on cards, rows and the kill feed (unique within the league; "" = none yet).
var callsign: String = ""
## Procedural portrait appearance (see Look); rolled at creation.
var look: Look = null

# Off-field
## Contract personality (see Dna); rolled lazily from the id.
var dna: Dna = null
## 0-100 trust in his current club's front office (50 = neutral). Moved by negotiations and
## kept/broken promises; resets when he joins a new club.
var trust: float = TRUST_NEUTRAL
## Active starter promise: {year, team (abbrev), games, started}; {} = none.
var promise: Dictionary = {}
## Set when a broken promise makes him want out (trades act on it later).
var trade_request := false
## Abbrev of the last club that released him (free-agent loyalty).
var former_team := ""
## Two-letter home state ("" = unknown). Hometown DNA pulls him toward clubs near home.
var home_state := ""
const TRUST_NEUTRAL := 50.0
## Share of his team's matches a promised starter must start (missed weeks injured don't count).
const PROMISE_SHARE := 0.75

# Morale
## 0-100 (75 = neutral). Below 75 each 5-point step drops a random stat by 1-3; above 85 each
## 5-point step boosts one. Driven by playing time, results and contract fairness.
var morale: float = MORALE_NEUTRAL
var _mods_key := -999
var _mods: Dictionary = {}

const MORALE_NEUTRAL := 75.0
const MORALE_BOOST_START := 85.0
## Morale never touches the durability stats.
const MORALE_EXCLUDED: Array[StringName] = [&"injury", &"toughness"]

# Career totals
const STAT_LINE_KEYS: Array[String] = ["matches", "rounds", "kills", "deaths", "assists", "damage", "saves",
	"headshots", "shots", "hits", "mvps", "clutches", "games", "wipes", "hill_s", "caps"]
var career := {"matches": 0, "rounds": 0, "kills": 0, "deaths": 0, "assists": 0, "damage": 0, "saves": 0,
	"headshots": 0, "shots": 0, "hits": 0, "mvps": 0, "clutches": 0, "games": 0, "wipes": 0, "hill_s": 0, "caps": 0}
## Season year -> totals with the same keys as `career` (plus "team" abbrev).
var season_lines: Dictionary = {}

## Progression history, oldest first. Each: {year, when, reason, changes: stat -> delta,
## ovr_from, ovr_to, dev_from, dev_to (-1 when his stars didn't move)}. Entries from older saves
## carry pot_from / pot_to (the old F..A grade) instead.
var history: Array = []
## Where new history entries are stamped; Season keeps this current ("Week 3", "Offseason", ...).
static var log_year := 0
static var log_when := ""


func _init() -> void:
	for s in Stats.ALL:
		usage[s] = 0.0


func get_look() -> Look:
	if look == null:
		look = Look.generate(id, age, Scheme.best_role(stats))
	return look


func get_dna() -> Dna:
	if dna == null:
		dna = Dna.generate(id, age)
	return dna


func add_trust(amount: float) -> void:
	trust = clampf(trust + amount, 0.0, 100.0)


static func trust_label(t: float) -> String:
	if t >= 80:
		return "Devoted"
	if t >= 62:
		return "Trusting"
	if t >= 40:
		return "Neutral"
	if t >= 20:
		return "Wary"
	return "Distrustful"


func full_name() -> String:
	return "%s %s" % [first_name, last_name]


func short_name() -> String:
	return "%s. %s" % [first_name.left(1), last_name]


## Jared "Ghost" Barrett.
func display_name() -> String:
	if callsign == "":
		return full_name()
	return "%s \"%s\" %s" % [first_name, callsign, last_name]


## GHOST (or the short name before a callsign is given).
func tag() -> String:
	return callsign.to_upper() if callsign != "" else short_name()


# --- morale -------------------------------------------------------------------

## Signed number of morale steps: -N below neutral, +N above the boost line, 0 in between.
func morale_steps() -> int:
	if morale < MORALE_NEUTRAL:
		return -int((MORALE_NEUTRAL - morale) / 5.0)
	if morale > MORALE_BOOST_START:
		return int((morale - (MORALE_BOOST_START - 5.0)) / 5.0)
	return 0


## stat -> temporary delta from morale. Deterministic per soldier and step.
func morale_mods() -> Dictionary:
	var steps := morale_steps()
	if steps == _mods_key:
		return _mods
	_mods_key = steps
	_mods = {}
	var pool: Array[StringName] = []
	for s in Stats.ALL:
		if not MORALE_EXCLUDED.has(s):
			pool.append(s)
	var dir := 1 if steps > 0 else -1
	var rng := RandomNumberGenerator.new()
	for i in absi(steps):
		rng.seed = hash([id, i, dir])
		var stat: StringName = pool[rng.randi_range(0, pool.size() - 1)]
		_mods[stat] = int(_mods.get(stat, 0)) + dir * rng.randi_range(1, 3)
	return _mods


## Chemistry bonus to each Mentality rating from linked teammates in his lineup (Relationships).
func chem_bonus() -> int:
	return Relationships.bonus_for(self)


## stat -> today's delta: morale plus lineup chemistry.
func stat_mods() -> Dictionary:
	var chem := chem_bonus()
	if chem == 0:
		return morale_mods()
	var out := morale_mods().duplicate()
	for st in Stats.group_stats(Stats.MENTALITY):
		out[st] = int(out.get(st, 0)) + chem
	return out


func eff_stat(stat: StringName) -> int:
	return clampi(int(stats[stat]) + int(stat_mods().get(stat, 0)), Stats.MIN_RATING, Stats.MAX_RATING)


## Ratings with morale and chemistry applied (what the match sim uses).
func effective_stats() -> Dictionary:
	var mods := stat_mods()
	if mods.is_empty():
		return stats
	var out := stats.duplicate()
	for s in mods:
		out[s] = clampi(int(out[s]) + int(mods[s]), Stats.MIN_RATING, Stats.MAX_RATING)
	return out


func effective_ovr_at_role(role: Scheme.Role) -> int:
	return Scheme.ovr_for_role(effective_stats(), role)


## Morale and chemistry's effect on an OVR at a role (e.g. -4 shows as "69 (-4)").
func morale_ovr_delta(role: Scheme.Role) -> int:
	return effective_ovr_at_role(role) - ovr_at_role(role)


func add_morale(amount: float) -> void:
	morale = clampf(morale + amount, 0.0, 100.0)


static func morale_label(m: float) -> String:
	if m >= 90.0:
		return "Ecstatic"
	if m >= 80.0:
		return "Happy"
	if m >= 70.0:
		return "Content"
	if m >= 55.0:
		return "Unhappy"
	return "Furious"


func get_stat(stat: StringName) -> int:
	return stats[stat]


func ovr_at_role(role: Scheme.Role) -> int:
	return Scheme.ovr_for_role(stats, role)


func best_ovr() -> int:
	return ovr_at_role(Scheme.best_role(stats))


func group_rating(group: StringName) -> int:
	return Stats.group_rating(stats, group)


func group_cap(group: StringName) -> int:
	return int(group_caps.get(group, group_rating(group)))


## Group upgrades left before the cap (0 = capped).
func group_headroom(group: StringName) -> int:
	return maxi(0, group_cap(group) - group_rating(group))


func is_injured() -> bool:
	return injury_weeks > 0


## Potential grade 0 (F) .. 4 (A) from his stat ceiling (potential_ovr).
func potential_grade() -> int:
	return grade_for_ceiling(potential_ovr())


static func grade_for_ceiling(ceiling: int) -> int:
	var g := 0
	for c in POTENTIAL_CUTOFFS:
		if ceiling >= c:
			g += 1
	return g


func potential_letter() -> String:
	return POTENTIAL_LETTERS[potential_grade()]


## "★★★" for dev 3 (text fallback where the insignia graphic doesn't fit).
static func dev_stars(stars: int) -> String:
	return "★".repeat(clampi(stars, DEV_MIN, DEV_MAX))


func dev_text() -> String:
	return dev_stars(dev)


## Moves his dev trait by `delta` stars (clamped 1-4) and stamps the season. Returns the change.
func change_dev(delta: int, year: int) -> int:
	var to := clampi(dev + delta, DEV_MIN, DEV_MAX)
	var moved := to - dev
	if moved != 0:
		dev = to
		dev_year = year
	return moved


## True if his dev trait already moved this season.
func dev_changed_in(year: int) -> bool:
	return dev_year == year and year > 0


## Save migration: old saves stored the F..A grade in `potential`.
func _migrate_prop(prop: String, val: Variant) -> void:
	if prop == "potential" and typeof(val) == TYPE_INT:
		dev = LEGACY_GRADE_TO_DEV[clampi(int(val), 0, LEGACY_GRADE_TO_DEV.size() - 1)]


## Ratings if every upgradable group reached its cap (each stat raised by the group's headroom).
func potential_stats() -> Dictionary:
	var out := stats.duplicate()
	for g in Stats.UPGRADABLE_GROUPS:
		var room := group_headroom(g)
		for s in Stats.group_stats(g):
			out[s] = mini(Stats.MAX_RATING, int(stats[s]) + room)
	return out


## Best-role OVR at full potential.
func potential_ovr() -> int:
	var p := potential_stats()
	return Scheme.ovr_for_role(p, Scheme.best_role(p))


func add_usage(stat: StringName, amount: float) -> void:
	usage[stat] += amount


## Records a progression event (stat deltas and/or a dev star change) in `history`, stamped with
## the current log_year / log_when. Repeats of the same reason at the same stamp are merged.
## `ovr_before` is best_ovr() before the change was applied.
func log_progress(reason: String, changes: Dictionary, ovr_before: int, dev_from := -1, dev_to := -1) -> void:
	var deltas := {}
	for st in changes:
		if int(changes[st]) != 0:
			deltas[st] = int(changes[st])
	if deltas.is_empty() and dev_from == dev_to:
		return
	if not history.is_empty() and dev_from == dev_to:
		var last: Dictionary = history[-1]
		if last["year"] == log_year and last["when"] == log_when and last["reason"] == reason and not history_has_grade_change(last):
			for st in deltas:
				last["changes"][st] = int(last["changes"].get(st, 0)) + deltas[st]
			last["ovr_to"] = best_ovr()
			return
	history.append({"year": log_year, "when": log_when, "reason": reason, "changes": deltas,
		"ovr_from": ovr_before, "ovr_to": best_ovr(), "dev_from": dev_from, "dev_to": dev_to})


## True if a history entry moved his dev stars (or, in old saves, his potential grade).
static func history_has_grade_change(e: Dictionary) -> bool:
	return int(e.get("dev_from", -1)) != int(e.get("dev_to", -1)) or int(e.get("pot_from", -1)) != int(e.get("pot_to", -1))
