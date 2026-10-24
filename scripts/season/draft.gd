class_name Draft
extends RefCounted
## Yearly draft class, scouting and draft-day picks (Madden-style).
##
## Scouting: the user earns POINTS_PER_WEEK scout points every week of the season (unspent points
## carry over). Each point spent on a prospect reveals a random stat group as a window of named
## tiers ("Inconsistent - Sharpshooter"); scouting the same group again narrows the window
## (4 tiers -> 3 -> 2). Numbers and potential are never shown.
##
## Draft: snake order (worst team first, champion last) for ROUNDS rounds. AI teams pick on a
## noisy read of each prospect's OVR at his listed position plus upside.

const CLASS_SIZE := 40
const ROUNDS := 2
const POINTS_PER_WEEK := 12
const MAX_POINTS_PER_PROSPECT := 5
## Window width (in tiers) after the 1st, 2nd and 3rd scout of a group.
const WINDOW_WIDTHS := [4, 3, 2]
## Group rating thresholds for tiers 1..4 (tier 0 is below the first).
const TIER_THRESHOLDS := [50, 60, 70, 80]
const TIER_COUNT := 5
const TIER_NAMES := {
	Stats.ACCURACY: ["Spray & Pray", "Inconsistent", "Steady Aim", "Marksman", "Sharpshooter"],
	Stats.HANDLING: ["Butterfingers", "Clunky", "Capable", "Smooth Operator", "Gunslinger"],
	Stats.PHYSICALITY: ["Out of Shape", "Average Build", "Athletic", "Explosive", "Freak Athlete"],
	Stats.MENTALITY: ["Lost", "Rattled", "Level-Headed", "Leader", "Field General"],
	Stats.DURABILITY: ["Glass", "Fragile", "Durable", "Sturdy", "Iron Man"],
}
const PROSPECT_QUALITY := 57.0
const PROSPECT_QUALITY_SD := 5.0
## Phenoms: every non-injury stat at least this (they play any position well).
const PHENOM_STAT_MIN := 54
const PHENOM_STAT_MAX := 64
const PHENOM_EXTRA_HEADROOM := 6
## AI draft evaluation noise (OVR points).
const AI_NOISE := 6.0

var year: int
var prospects: Array[Prospect] = []
var scout_points := 0
## One team per pick, in order. Empty until the draft order is set (after the Final).
var order: Array[Team] = []
var next_pick := 0
var _rng := RandomNumberGenerator.new()


static func generate(seed_value: int, draft_year: int, first_id: int) -> Draft:
	var d := Draft.new()
	d.year = draft_year
	d._rng.seed = seed_value
	var rng := d._rng
	var roles := [Scheme.Role.FRONTMAN, Scheme.Role.CENTER, Scheme.Role.FLEX]
	for i in CLASS_SIZE:
		var p := Prospect.new()
		p.listed_role = roles[rng.randi_range(0, roles.size() - 1)]
		var quality := PROSPECT_QUALITY + rng.randfn(0.0, PROSPECT_QUALITY_SD)
		p.soldier = PlayerGenerator.generate(rng, first_id + i, p.listed_role, quality, rng.randi_range(19, 22))
		d.prospects.append(p)
	# Usually one phenom, sometimes none or two.
	var roll := rng.randf()
	var phenoms := 0 if roll < 0.2 else (1 if roll < 0.8 else 2)
	var picked := {}
	while picked.size() < phenoms:
		picked[rng.randi_range(0, CLASS_SIZE - 1)] = true
	for i in picked:
		d._make_phenom(d.prospects[i])
	return d


func _make_phenom(p: Prospect) -> void:
	p.phenom = true
	var s := p.soldier
	for st in Stats.ALL:
		if st == Stats.INJURY or st == Stats.TOUGHNESS:
			continue
		s.stats[st] = maxi(s.stats[st], _rng.randi_range(PHENOM_STAT_MIN, PHENOM_STAT_MAX))
	for g in Stats.UPGRADABLE_GROUPS:
		var room := PlayerGenerator.roll_group_headroom(_rng, s.age, g) + PHENOM_EXTRA_HEADROOM
		s.group_caps[g] = mini(Stats.MAX_RATING, s.group_rating(g) + room)


# --- tiers -------------------------------------------------------------------------

static func tier_of(rating: int) -> int:
	var t := 0
	for th in TIER_THRESHOLDS:
		if rating >= th:
			t += 1
	return t


static func tier_name(group: StringName, tier: int) -> String:
	return TIER_NAMES[group][clampi(tier, 0, TIER_COUNT - 1)]


## "Inconsistent - Sharpshooter" for a revealed window, "?" if never scouted.
static func window_text(group: StringName, window: Variant) -> String:
	if window == null:
		return "?"
	var w: Vector2i = window
	return "%s - %s" % [tier_name(group, w.x), tier_name(group, w.y)]


# --- scouting ----------------------------------------------------------------------

func can_scout(p: Prospect) -> bool:
	return scout_points > 0 and p.is_available() and not p.fully_scouted()


## Spends one scout point: picks a random group that can still be narrowed and reveals a
## window of WINDOW_WIDTHS[n] tiers containing the true tier, inside any earlier window.
## Returns the group scouted, or &"" if not allowed.
func scout(p: Prospect) -> StringName:
	if not can_scout(p):
		return &""
	var options := p.scoutable_groups()
	var g: StringName = options[_rng.randi_range(0, options.size() - 1)]
	var n: int = p.scouts.get(g, 0)
	var width: int = WINDOW_WIDTHS[n]
	var prev: Vector2i = p.reveals.get(g, Vector2i(0, TIER_COUNT - 1))
	var t := p.true_tier(g)
	var lo_min := maxi(prev.x, t - width + 1)
	var lo_max := mini(t, prev.y - width + 1)
	var lo := _rng.randi_range(lo_min, lo_max)
	p.reveals[g] = Vector2i(lo, lo + width - 1)
	p.scouts[g] = n + 1
	p.points += 1
	scout_points -= 1
	return g


# --- draft day ---------------------------------------------------------------------

## `teams_in_order` is round-1 order (first pick first); later rounds snake.
func set_order(teams_in_order: Array) -> void:
	order = []
	for r in ROUNDS:
		var round_teams := teams_in_order.duplicate()
		if r % 2 == 1:
			round_teams.reverse()
		for t in round_teams:
			order.append(t)
	next_pick = 0


func is_started() -> bool:
	return not order.is_empty()


func is_complete() -> bool:
	return is_started() and next_pick >= order.size()


func on_the_clock() -> Team:
	if not is_started() or is_complete():
		return null
	return order[next_pick]


func round_of(pick_index: int) -> int:
	var per_round := order.size() / ROUNDS
	return pick_index / maxi(1, per_round) + 1


func available() -> Array[Prospect]:
	var out: Array[Prospect] = []
	for p in prospects:
		if p.is_available():
			out.append(p)
	return out


## Prospects taken so far, in pick order.
func picks() -> Array[Prospect]:
	var out: Array[Prospect] = []
	for p in prospects:
		if not p.is_available():
			out.append(p)
	out.sort_custom(func(a: Prospect, b: Prospect): return a.pick_number < b.pick_number)
	return out


func make_pick(p: Prospect) -> bool:
	var team := on_the_clock()
	if team == null or not p.is_available():
		return false
	next_pick += 1
	p.drafted_by = team
	p.pick_number = next_pick
	team.roster.append(p.soldier)
	return true


## How an AI front office values a prospect: noisy OVR at his listed position plus some upside.
func ai_value(p: Prospect) -> float:
	var s := p.soldier
	var ovr := float(s.ovr_at_role(p.listed_role))
	var upside := float(s.potential_ovr() - s.best_ovr())
	return ovr + upside * 0.4 + _rng.randfn(0.0, AI_NOISE)


func ai_pick() -> Prospect:
	var best: Prospect = null
	var best_v := -INF
	for p in available():
		var v := ai_value(p)
		if v > best_v:
			best_v = v
			best = p
	if best != null:
		make_pick(best)
	return best


## AI teams pick until the user is on the clock or the draft ends. Returns the picks made.
func sim_to_user() -> Array[Prospect]:
	var made: Array[Prospect] = []
	while not is_complete() and not on_the_clock().user_controlled:
		var p := ai_pick()
		if p == null:
			break
		made.append(p)
	return made


func sim_to_end() -> void:
	while not is_complete():
		if ai_pick() == null:
			break
