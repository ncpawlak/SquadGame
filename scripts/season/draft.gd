class_name Draft
extends RefCounted
## Yearly draft class, scouting and draft-day picks (Madden-style).
##
## Scouting: the user earns POINTS_PER_WEEK scout points every week of the season (unspent points
## carry over). Each point spent on a prospect reveals a random stat group as a window of named
## tiers ("Inconsistent - Sharpshooter"); scouting the same group again narrows the window
## (3 tiers -> 2). Numbers and potential are never shown.
##
## Projections: every prospect has a league-consensus value (his real worth plus a fixed error)
## that gives his projected round and drives the mock draft. Hidden phenoms are judged at their
## listed position, so they tend to project as mid-round sleepers.
##
## Draft: snake order (worst team first, champion last) for ROUNDS rounds. AI teams pick on a
## pick-day read of the consensus value plus a bonus for their weakest position.

const CLASS_SIZE := 36
const ROUNDS := 3
const POINTS_PER_WEEK := 14
const MAX_POINTS_PER_PROSPECT := 8
## Window width (in tiers) after the 1st and 2nd scout of a group.
const WINDOW_WIDTHS := [3, 2]
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
## League-wide evaluation error baked into each prospect's consensus value (OVR points).
const CONSENSUS_NOISE := 3.0
## Extra pick-day noise per AI evaluation, so real drafts drift from the mock.
const AI_NOISE := 3.0
## Value bonus for a prospect who plays the team's weakest starting position.
const NEED_BONUS := 3.0
## The consensus underrates phenoms (scouts pigeonhole them at their listed position).
const PHENOM_UNDERRATE := 3.0

var year: int
var prospects: Array[Prospect] = []
var scout_points := 0
## One team per pick, in order. Empty until the draft order is set (after the Final).
var order: Array[Team] = []
var next_pick := 0
var _rng := RandomNumberGenerator.new()
## Set by the season so drafted rookies get a league-unique callsign.
var league: League = null


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
	for p in d.prospects:
		p.consensus = true_value(p) + rng.randfn(0.0, CONSENSUS_NOISE) - (PHENOM_UNDERRATE if p.phenom else 0.0)
	var board := d.prospects.duplicate()
	board.sort_custom(func(a: Prospect, b: Prospect): return a.consensus > b.consensus)
	for i in board.size():
		board[i].projected_rank = i + 1
	return d


func _make_phenom(p: Prospect) -> void:
	p.phenom = true
	var s := p.soldier
	for st in Stats.ALL:
		if st == Stats.INJURY or st == Stats.TOUGHNESS:
			continue
		s.stats[st] = maxi(s.stats[st], _rng.randi_range(PHENOM_STAT_MIN, PHENOM_STAT_MAX))
	s.potential = Soldier.POTENTIAL_A if _rng.randf() < 0.7 else Soldier.POTENTIAL_A - 1
	PlayerGenerator.roll_caps(s, _rng, PHENOM_EXTRA_HEADROOM)


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
	if w.x == w.y:
		return tier_name(group, w.x)
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
	for t in snake(teams_in_order):
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
	p.soldier.draft_year = year
	p.soldier.contract = Contracts.rookie_contract(p.pick_number, order.size(), year)
	team.roster.append(p.soldier)
	p.soldier.morale = 82.0
	if league != null:
		league.give_callsign(p.soldier)
	return true


## A prospect's real draft worth: OVR at his listed position plus some upside.
static func true_value(p: Prospect) -> float:
	var s := p.soldier
	var upside := float(s.potential_ovr() - s.best_ovr())
	return float(s.ovr_at_role(p.listed_role)) + upside * 0.4


# --- projections & mock draft ------------------------------------------------------

## "Early 1st", "Mid 2nd", ... or "Undrafted" for a 1-based big-board rank.
static func projection_text(rank: int, picks_per_round: int = Season.TEAM_COUNT) -> String:
	var rnd := (rank - 1) / picks_per_round + 1
	if rnd > ROUNDS:
		return "Undrafted"
	var third := ((rank - 1) % picks_per_round) * 3 / picks_per_round
	return "%s %s" % [["Early", "Mid", "Late"][third], ["1st", "2nd", "3rd", "4th"][rnd - 1]]


func projection(p: Prospect) -> String:
	return projection_text(p.projected_rank)


## The team's weakest starting position (lowest average starter OVR at that role).
static func weakest_role(team: Team) -> int:
	var sum := {}
	var n := {}
	for slot_id in team.scheme.slot_ids():
		var so: Soldier = team.lineup.get(slot_id)
		if so == null:
			continue
		var role: int = team.scheme.role_for_slot(slot_id)
		sum[role] = float(sum.get(role, 0.0)) + so.ovr_at_role(role)
		n[role] = int(n.get(role, 0)) + 1
	var worst := -1
	var worst_avg := INF
	for role in sum:
		var avg: float = sum[role] / n[role]
		if avg < worst_avg:
			worst_avg = avg
			worst = role
	return worst


static func need_bonus(team: Team, p: Prospect) -> float:
	return NEED_BONUS if int(p.listed_role) == weakest_role(team) else 0.0


## How an AI front office values a prospect on draft day: consensus, team need and some noise.
func ai_value(p: Prospect, team: Team) -> float:
	return p.consensus + need_bonus(team, p) + _rng.randfn(0.0, AI_NOISE)


func ai_pick() -> Prospect:
	var team := on_the_clock()
	if team == null:
		return null
	var best: Prospect = null
	var best_v := -INF
	for p in available():
		var v := ai_value(p, team)
		if v > best_v:
			best_v = v
			best = p
	if best != null:
		make_pick(best)
	return best


## Projected picks from `pick_order` (every pick, snake included) starting at the next pick:
## each team takes the best consensus prospect left, nudged by need. Doesn't change the draft.
## Returns [{pick (1-based), team, prospect}].
func mock(pick_order: Array) -> Array:
	var taken := {}
	var out: Array = []
	for i in range(next_pick, pick_order.size()):
		var team: Team = pick_order[i]
		var best: Prospect = null
		var best_v := -INF
		for p in prospects:
			if not p.is_available() or taken.has(p):
				continue
			var v := p.consensus + need_bonus(team, p)
			if v > best_v:
				best_v = v
				best = p
		if best == null:
			break
		taken[best] = true
		out.append({"pick": i + 1, "team": team, "prospect": best})
	return out


## Full pick order (all rounds, snake) from a round-1 order.
static func snake(teams_in_order: Array) -> Array:
	var out: Array = []
	for r in ROUNDS:
		var round_teams := teams_in_order.duplicate()
		if r % 2 == 1:
			round_teams.reverse()
		out.append_array(round_teams)
	return out


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
