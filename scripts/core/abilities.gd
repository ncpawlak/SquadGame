class_name Abilities
extends RefCounted
## Player abilities (issue #124): named combinations of ratings from different groups. A soldier holds up
## to MAX_SLOTS of them. Each has a tier (bronze, silver, gold) set by the LOWEST of its required ratings.
##
## Rules:
## - A soldier earns an ability the first time its requirements are met (every required rating at BRONZE
##   or above) and he has a free slot. Slots are never freed: an ability whose ratings later fall below
##   bronze becomes LOCKED (tier 0) but keeps its slot, so nothing replaces it. It comes back to life if
##   the ratings recover. A drop from gold to silver is just a lower tier.
## - When more abilities qualify than there are free slots, they are ranked by level minus the ability's
##   league median (MEDIAN) so easy combinations don't crowd out hard ones, then by DEFS order.
## - No random rolls: the result depends only on ratings and the order they changed in.
##
## State lives on Soldier.abilities as [{id, tier, year}] in the order earned. refresh() is called when
## ratings change (Soldier.log_progress) and by the league-wide sweep (refresh_league).
## Tier cut-offs and the MEDIAN constants come from tools/ability_distribution.gd.

const MAX_SLOTS := 4
const LOCKED := 0
const BRONZE := 1
const SILVER := 2
const GOLD := 3
## Lowest required rating for tiers 1..3.
const CUTOFFS := [75, 88, 95]
const TIER_NAMES := ["Locked", "Bronze", "Silver", "Gold"]

## id, name, required ratings, league median of the lowest required rating, one-line effect.
## The effects themselves are applied by the match engine and Conditioning (see the issue).
const DEFS := [
	{"id": &"frontline_warrior", "name": "Frontline Warrior", "stats": [Stats.SHORT_ACC, Stats.MEDIUM_ACC, Stats.GROUPING], "median": 69,
		"blurb": "Better hit chance at short and medium range."},
	{"id": &"marksman", "name": "Marksman", "stats": [Stats.LONG_ACC, Stats.SWAY, Stats.AWARENESS], "median": 65,
		"blurb": "Better hit chance at long range, with no sway penalty out there."},
	{"id": &"run_and_gun", "name": "Run & Gun", "stats": [Stats.MEDIUM_ACC, Stats.SWAY, Stats.SPEED], "median": 67,
		"blurb": "Keeps his aim while moving."},
	{"id": &"headhunter", "name": "Headhunter", "stats": [Stats.GROUPING, Stats.MEDIUM_ACC, Stats.COMPOSURE], "median": 67,
		"blurb": "More headshots."},
	{"id": &"suppressor", "name": "Suppressor", "stats": [Stats.RELOAD, Stats.GROUPING, Stats.STRENGTH], "median": 70,
		"blurb": "Follow-up bullets in a burst hit more often."},
	{"id": &"quick_hands", "name": "Quick Hands", "stats": [Stats.RELOAD, Stats.AGILITY, Stats.COMPOSURE], "median": 68,
		"blurb": "Reloads faster."},
	{"id": &"opening_strike", "name": "Opening Strike", "stats": [Stats.AWARENESS, Stats.SPEED, Stats.SHORT_ACC], "median": 65,
		"blurb": "Better hit chance in the opening seconds of a round."},
	{"id": &"gunslinger", "name": "Gunslinger", "stats": [Stats.SHORT_ACC, Stats.RELOAD, Stats.AGILITY], "median": 71,
		"blurb": "The first burst after spawning or reloading hits harder."},
	{"id": &"ghost", "name": "Ghost", "stats": [Stats.SPEED, Stats.AGILITY, Stats.AWARENESS], "median": 67,
		"blurb": "Harder to hit while moving."},
	{"id": &"cover_specialist", "name": "Cover Specialist", "stats": [Stats.AGILITY, Stats.AWARENESS, Stats.COMPOSURE], "median": 67,
		"blurb": "Extra hard to hit while ducked or peeking."},
	{"id": &"stand_fast", "name": "Stand Fast", "stats": [Stats.STRENGTH, Stats.ENDURANCE, Stats.COMPOSURE], "median": 69,
		"blurb": "Takes less damage once below half health."},
	{"id": &"marathoner", "name": "Marathoner", "stats": [Stats.ENDURANCE, Stats.SPEED, Stats.OBJ_IQ], "median": 67,
		"blurb": "Fatigue costs him less accuracy."},
	{"id": &"flanker", "name": "Flanker", "stats": [Stats.SPEED, Stats.AWARENESS, Stats.BREACH], "median": 63,
		"blurb": "Better accuracy when flanking, and being flanked hurts less."},
	{"id": &"clutch", "name": "Clutch", "stats": [Stats.COMPOSURE, Stats.AWARENESS, Stats.ANCHOR], "median": 64,
		"blurb": "Better hit chance when his squad is outnumbered."},
	{"id": &"field_general", "name": "Field General", "stats": [Stats.TEAMWORK, Stats.AWARENESS, Stats.OBJ_IQ], "median": 66,
		"blurb": "Teammates' crossfire bonus is bigger while he is alive."},
	{"id": &"crossfire_partner", "name": "Crossfire Partner", "stats": [Stats.TEAMWORK, Stats.MEDIUM_ACC, Stats.COMPOSURE], "median": 67,
		"blurb": "Shots that follow a teammate's hit land more often."},
	{"id": &"guardian_angel", "name": "Guardian Angel", "stats": [Stats.TEAMWORK, Stats.AGILITY, Stats.SHORT_ACC], "median": 67,
		"blurb": "Better against attackers who have a teammate nearly dead."},
	{"id": &"sixth_sense", "name": "Sixth Sense", "stats": [Stats.AWARENESS, Stats.OBJ_IQ, Stats.LONG_ACC], "median": 64,
		"blurb": "Rarely caught mid-reload or flanked, and finds cover sooner."},
	{"id": &"king_of_the_hill", "name": "King of the Hill", "stats": [Stats.ANCHOR, Stats.MEDIUM_ACC, Stats.COMPOSURE], "median": 64,
		"blurb": "Better hit chance while standing on the point."},
	{"id": &"hill_breaker", "name": "Hill Breaker", "stats": [Stats.BREACH, Stats.SPEED, Stats.SHORT_ACC], "median": 66,
		"blurb": "Better against targets standing on the point."},
	{"id": &"point_controller", "name": "Point Controller", "stats": [Stats.OBJ_IQ, Stats.TEAMWORK, Stats.ANCHOR], "median": 63,
		"blurb": "Adds more hold and capture pressure on the point."},
	{"id": &"retaker", "name": "Retaker", "stats": [Stats.BREACH, Stats.OBJ_IQ, Stats.STRENGTH], "median": 66,
		"blurb": "Better right after his squad loses the point."},
	{"id": &"closer", "name": "Closer", "stats": [Stats.OBJ_IQ, Stats.COMPOSURE, Stats.ENDURANCE], "median": 67,
		"blurb": "Better late in a game and in sudden death."},
	{"id": &"iron_man", "name": "Iron Man", "stats": [Stats.INJURY, Stats.TOUGHNESS, Stats.ENDURANCE], "median": 69,
		"blurb": "Lower weekly injury chance."},
	{"id": &"quick_healer", "name": "Quick Healer", "stats": [Stats.TOUGHNESS, Stats.ENDURANCE, Stats.TEAMWORK], "median": 65,
		"blurb": "Recovers from fatigue faster and misses fewer weeks to injury."},
]

static var _index := {}


# --- definitions ----------------------------------------------------------------------

## The definition with this id ({} if unknown).
static func def(id: StringName) -> Dictionary:
	if _index.is_empty():
		for i in DEFS.size():
			_index[DEFS[i]["id"]] = i
	return DEFS[int(_index[id])] if _index.has(id) else {}


static func ability_name(id: StringName) -> String:
	return String(def(id).get("name", id))


static func tier_name(tier: int) -> String:
	return TIER_NAMES[clampi(tier, LOCKED, GOLD)]


## Lowest of the ratings `d` requires (the value tiers are cut from).
static func level(stats: Dictionary, d: Dictionary) -> int:
	var low := Stats.MAX_RATING
	for st in d["stats"]:
		low = mini(low, int(stats.get(st, 0)))
	return low


## Tier a level earns: 0 below bronze, then bronze, silver, gold.
static func tier_for_level(lv: int) -> int:
	var t := LOCKED
	for i in CUTOFFS.size():
		if lv >= int(CUTOFFS[i]):
			t = i + 1
	return t


## Tier `stats` earns for ability `id`.
static func tier_of_stats(stats: Dictionary, id: StringName) -> int:
	var d := def(id)
	return tier_for_level(level(stats, d)) if not d.is_empty() else LOCKED


# --- a soldier's abilities -------------------------------------------------------------

## His entry for `id` ({} if he doesn't hold it, locked or not).
static func entry(s: Soldier, id: StringName) -> Dictionary:
	for e: Dictionary in s.abilities:
		if e["id"] == id:
			return e
	return {}


## His current tier in `id`: 0 if he doesn't hold it or it is locked.
static func tier(s: Soldier, id: StringName) -> int:
	return int(entry(s, id).get("tier", LOCKED))


## Abilities he holds that are active (tier above locked), as [{id, tier, year}].
static func active(s: Soldier) -> Array:
	return s.abilities.filter(func(e: Dictionary): return int(e["tier"]) > LOCKED)


static func free_slots(s: Soldier) -> int:
	return maxi(0, MAX_SLOTS - s.abilities.size())


## Re-tiers what he holds and fills free slots with newly qualified abilities. Returns the changes:
## [{id, from, to}] where from is -1 for a newly earned ability (to is its first tier).
static func refresh(s: Soldier, year := -1) -> Array:
	var changes: Array = []
	if year < 0:
		year = Soldier.log_year
	# What he holds follows his ratings, up and down. A locked ability keeps its slot.
	for e: Dictionary in s.abilities:
		var to := tier_of_stats(s.stats, e["id"])
		if to != int(e["tier"]):
			changes.append({"id": e["id"], "from": int(e["tier"]), "to": to})
			e["tier"] = to
	var free := free_slots(s)
	if free <= 0:
		return changes
	# Qualifying abilities he doesn't hold yet, best margin over the typical level first.
	var cands: Array = []
	for i in DEFS.size():
		var d: Dictionary = DEFS[i]
		if not entry(s, d["id"]).is_empty():
			continue
		var lv := level(s.stats, d)
		if tier_for_level(lv) > LOCKED:
			cands.append([lv - int(d["median"]), i])
	cands.sort_custom(func(a: Array, b: Array): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	for c in cands.slice(0, free):
		var d: Dictionary = DEFS[int(c[1])]
		var t := tier_for_level(level(s.stats, d))
		s.abilities.append({"id": d["id"], "tier": t, "year": year})
		changes.append({"id": d["id"], "from": -1, "to": t})
	return changes


## Runs refresh() on every soldier on a roster, Green Team or in the free-agent pool (a safety net for
## ratings set outside Soldier.log_progress: new leagues, drafted rookies, loaded saves).
static func refresh_league(league: League, year: int) -> void:
	for s: Soldier in league.all_soldiers():
		refresh(s, year)
	for s: Soldier in league.free_agents:
		refresh(s, year)
