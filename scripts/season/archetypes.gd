class_name Archetypes
extends RefCounted
## Player-mode archetypes (#100/#101): a role plus a specialty that works on single stats, not whole groups.
## data/archetypes.json lists each archetype with 'up' / 'down' stat adjustments.
##
## An archetype fixes, for every stat, the highest rating the combine can award (`ceilings`). A Center can never
## post a Frontman's Speed, however well the Combine Gauntlet goes. Role sets the base shape (the same offsets the
## league generator uses); the specialty then raises a few stats and lowers a few. Drill scores (phase 2) pick a
## value between FLOOR and the stat's ceiling, and START_OVR_CAP caps the whole soldier's starting OVR.

const DATA := "res://data/archetypes.json"

## Lowest rating a combine can award, and the highest starting OVR for any created soldier.
const FLOOR := 35
const START_OVR_CAP := 75
## Base ceiling for a stat with no role offset, and how many points each role-offset point is worth.
const BASE_CEILING := 78
const OFFSET_SCALE := 1.5
const MIN_CEILING := 45
## Not drilled and not scored: every created soldier starts with these (the Medical Center lifts them later).
const FIXED_STATS := {&"toughness": 90, &"injury": 90}

const ROLE_KEYS := {"frontman": Scheme.Role.FRONTMAN, "center": Scheme.Role.CENTER, "flex": Scheme.Role.FLEX}

static var _all: Array = []


static func all() -> Array:
	if _all.is_empty():
		var f := FileAccess.open(DATA, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_all = parsed.get("archetypes", [])
	return _all


## Archetypes for one role, in file order.
static func for_role(role: Scheme.Role) -> Array:
	return all().filter(func(a: Dictionary) -> bool: return ROLE_KEYS[a["role"]] == role)


## The archetype dictionary for an id, or {} if unknown.
static func find(id: StringName) -> Dictionary:
	for a in all():
		if StringName(a["id"]) == id:
			return a
	return {}


static func role_of(id: StringName) -> Scheme.Role:
	return ROLE_KEYS[find(id).get("role", "flex")]


## stat -> highest combine rating for this archetype. Toughness and injury are fixed (FIXED_STATS), so they have none.
static func ceilings(id: StringName) -> Dictionary:
	var a := find(id)
	var out := {}
	if a.is_empty():
		return out
	var offsets: Dictionary = PlayerGenerator.ARCHETYPES[ROLE_KEYS[a["role"]]]
	for stat in Stats.ALL:
		if FIXED_STATS.has(stat):
			continue
		var v := float(BASE_CEILING) + OFFSET_SCALE * float(offsets.get(stat, 0))
		v += float(a.get("up", {}).get(String(stat), 0)) + float(a.get("down", {}).get(String(stat), 0))
		out[stat] = clampi(roundi(v), MIN_CEILING, Stats.MAX_RATING)
	return out


## Group-level ceiling (the average of its stat ceilings), for compact displays.
static func group_ceiling(id: StringName, group: StringName) -> int:
	var c := ceilings(id)
	var total := 0.0
	var members: Array = Stats.GROUPS[group]
	var n := 0
	for s in members:
		if c.has(s):
			total += float(c[s])
			n += 1
	return roundi(total / maxf(1.0, float(n)))


## OVR at the archetype's role if every drilled stat hit its ceiling (before START_OVR_CAP).
static func max_ovr(id: StringName) -> int:
	var stats := {}
	for s in Stats.ALL:
		stats[s] = FLOOR
	stats.merge(FIXED_STATS, true)
	stats.merge(ceilings(id), true)
	return Scheme.ovr_for_role(stats, role_of(id))
