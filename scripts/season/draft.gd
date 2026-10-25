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
## Standouts: every class has a few blue-chippers (much better all-round, high potential) and
## specialists (one elite stat group); the recap reveals them. Prospect news (weekly during the
## season) hints at them: stock rising/falling stories move the consensus, and stat stories
## ("claimed #1 for long range target practice") point at an extreme stat. Most stories are
## true, some are misleading, and none reveal a tier outright.
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
	Stats.OBJECTIVE: ["Point Shy", "Wanderer", "Contester", "Point Man", "King of the Hill"],
	Stats.DURABILITY: ["Glass", "Fragile", "Durable", "Sturdy", "Iron Man"],
}
const PROSPECT_QUALITY := 57.0
const PROSPECT_QUALITY_SD := 6.0
## Blue-chippers per class [min, max], their quality bonus [min, max] and minimum potential.
const BLUE_CHIPS := [2, 4]
const BLUE_CHIP_BONUS := [10.0, 15.0]
const BLUE_CHIP_MIN_POTENTIAL := 3
## Specialists per class [min, max] and the range of their elite group's stats.
const SPECIALISTS := [3, 5]
const SPECIALIST_STAT := [74, 86]
## Prospect news: stories per week (weights for 0, 1, 2), the share of misleading stories and
## how far a rising/falling story moves the consensus.
const NEWS_WEIGHTS := [25, 55, 20]
const NEWS_MISLEAD_CHANCE := 0.22
const NEWS_STOCK_SHIFT := 1.5
const NEWS_HINT_SHIFT := 0.6
## A stat at or above GREAT (or at or below POOR) is "newsworthy" for a stat story.
const NEWS_GREAT := 72
const NEWS_POOR := 42
const RISING_LINES := [
	"%s is turning heads in workouts; his stock is climbing.",
	"Scouts are buzzing about %s after a dominant showcase.",
	"%s keeps rising on draft boards. One GM called him \"the real deal.\"",
	"Word is several teams have %s much higher than the mocks.",
]
const FALLING_LINES := [
	"Concerns are mounting about %s; his stock is sliding.",
	"%s struggled at the regional combine and is falling on some boards.",
	"Teams are reportedly cooling on %s after private workouts.",
	"One scout on %s: \"I just don't see it translating.\"",
]
## stat -> [great story, poor story]
const STAT_LINES := {
	Stats.LONG_ACC: ["%s claimed #1 in the country for long range target practice.", "%s couldn't find the target past 300m at his workout."],
	Stats.MEDIUM_ACC: ["%s topped the mid-range qualification course.", "%s had trouble at mid range, scattering shots across the lane."],
	Stats.SHORT_ACC: ["%s went a perfect 30-for-30 in the close-quarters shoot house.", "%s was missing point-blank targets in the shoot house."],
	Stats.GROUPING: ["%s's shot groups at the range were \"the size of a coin.\"", "%s's shot groups were all over the paper."],
	Stats.RELOAD: ["%s posted the fastest reload times at the combine.", "%s fumbled magazine changes in the timed drills."],
	Stats.SPEED: ["%s ran the fastest 40 in the class.", "%s posted one of the slowest sprint times in the class."],
	Stats.AGILITY: ["%s was a blur through the cone drill.", "%s looked stiff in the agility drills."],
	Stats.STRENGTH: ["%s led the class in the sled push.", "%s was near the bottom of the class in strength testing."],
	Stats.ENDURANCE: ["%s finished the 20km ruck march first, by ten minutes.", "%s couldn't finish the 20km ruck march."],
	Stats.AWARENESS: ["Instructors rave about %s's battlefield awareness in sim exercises.", "%s was ambushed \"almost every round\" in sim exercises."],
	Stats.COMPOSURE: ["%s stayed ice-cold through the live-fire stress test.", "%s froze up during the live-fire stress test."],
	Stats.TEAMWORK: ["Squadmates voted %s the best teammate at the showcase.", "Reports say %s clashed with his squad at the showcase."],
	Stats.ANCHOR: ["%s held the hill alone for a full minute in the objective scrimmage.", "%s got pushed off the point every time in the objective scrimmage."],
	Stats.BREACH: ["%s led every successful push onto the point at the showcase.", "%s hesitated on every point push at the showcase."],
	Stats.OBJ_IQ: ["Coaches say %s \"always knows where the point is.\"", "%s kept chasing kills while the point sat empty."],
	Stats.TOUGHNESS: ["%s played through a broken hand at his final amateur event.", "%s left the combine early with a minor knock."],
	Stats.INJURY: ["Medicals came back spotless for %s.", "Teams have flagged %s's medicals."],
}
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
## Prospect news, oldest first: {year, week, prospect, kind (&"rising"/&"falling"/&"hint"),
## stat (hint stories), text, truthful}.
var news: Array = []
var _news_rng := RandomNumberGenerator.new()
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
	d._news_rng.seed = seed_value ^ 0x7E55
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
	var pool: Array = []
	for p in d.prospects:
		if not p.phenom:
			pool.append(p)
	for i in rng.randi_range(BLUE_CHIPS[0], BLUE_CHIPS[1]):
		d._make_blue_chip(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	for i in rng.randi_range(SPECIALISTS[0], SPECIALISTS[1]):
		d._make_specialist(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	for p in d.prospects:
		p.consensus = true_value(p) + rng.randfn(0.0, CONSENSUS_NOISE) - (PHENOM_UNDERRATE if p.phenom else 0.0)
	d.rerank()
	return d


## Recomputes every prospect's big-board rank from the consensus.
func rerank() -> void:
	var board := prospects.duplicate()
	board.sort_custom(func(a: Prospect, b: Prospect): return a.consensus > b.consensus)
	for i in board.size():
		board[i].projected_rank = i + 1


func _make_blue_chip(p: Prospect) -> void:
	p.standout = &"blue_chip"
	var s := p.soldier
	var bonus := _rng.randf_range(BLUE_CHIP_BONUS[0], BLUE_CHIP_BONUS[1])
	for st in Stats.ALL:
		if st == Stats.INJURY:
			continue
		s.stats[st] = Stats.clamp_rating(s.stats[st] + bonus)
	s.potential = maxi(s.potential, _rng.randi_range(BLUE_CHIP_MIN_POTENTIAL, Soldier.POTENTIAL_A))
	PlayerGenerator.roll_caps(s, _rng)


func _make_specialist(p: Prospect) -> void:
	p.standout = &"specialist"
	var groups: Array = Stats.UPGRADABLE_GROUPS
	var g: StringName = groups[_rng.randi_range(0, groups.size() - 1)]
	p.specialty = g
	var s := p.soldier
	for st in Stats.group_stats(g):
		s.stats[st] = maxi(s.stats[st], _rng.randi_range(SPECIALIST_STAT[0], SPECIALIST_STAT[1]))
	PlayerGenerator.roll_caps(s, _rng)


static func standout_label(p: Prospect) -> String:
	if p.phenom:
		return "PHENOM"
	if p.standout == &"blue_chip":
		return "BLUE CHIP"
	if p.standout == &"specialist":
		return "%s SPECIALIST" % Stats.GROUP_LABELS[p.specialty].to_upper()
	return ""


# --- prospect news -----------------------------------------------------------------

## Generates this week's prospect stories (0-2) and applies their effect on the consensus.
## Returns the new stories.
func weekly_news(week: int) -> Array:
	var rng := _news_rng
	var roll := rng.randi_range(1, NEWS_WEIGHTS[0] + NEWS_WEIGHTS[1] + NEWS_WEIGHTS[2])
	var count := 0 if roll <= NEWS_WEIGHTS[0] else (1 if roll <= NEWS_WEIGHTS[0] + NEWS_WEIGHTS[1] else 2)
	var made: Array = []
	var used := {}
	for i in count:
		var story := _make_story(week, used)
		if story.is_empty():
			continue
		used[story["prospect"]] = true
		made.append(story)
		news.append(story)
	if not made.is_empty():
		rerank()
	return made


func _make_story(week: int, used: Dictionary) -> Dictionary:
	var rng := _news_rng
	var avail: Array = available().filter(func(p): return not used.has(p))
	if avail.is_empty():
		return {}
	var truthful := rng.randf() >= NEWS_MISLEAD_CHANCE
	var story := {"year": year, "week": week, "truthful": truthful, "stat": &""}
	if rng.randf() < 0.5:
		# Stock story: truthful ones go to prospects the consensus has wrong, in the right direction.
		var gap := func(p: Prospect) -> float: return true_value(p) - p.consensus
		var p: Prospect = avail[rng.randi_range(0, avail.size() - 1)]
		var under: Array = avail.filter(func(x): return gap.call(x) > 1.0)
		var over: Array = avail.filter(func(x): return gap.call(x) < -1.0)
		var rising := rng.randf() < 0.5
		if truthful and not under.is_empty() and (rising or over.is_empty()):
			p = under[rng.randi_range(0, under.size() - 1)]
			rising = true
		elif truthful and not over.is_empty():
			p = over[rng.randi_range(0, over.size() - 1)]
			rising = false
		else:
			# Misleading: push him further from where he belongs.
			rising = gap.call(p) < 0.0
			story["truthful"] = false
		var lines: Array = RISING_LINES if rising else FALLING_LINES
		story["prospect"] = p
		story["kind"] = &"rising" if rising else &"falling"
		story["text"] = lines[rng.randi_range(0, lines.size() - 1)] % p.soldier.full_name()
		p.consensus += NEWS_STOCK_SHIFT if rising else -NEWS_STOCK_SHIFT
		return story
	# Stat story about an extreme stat (or, if misleading, an ordinary one dressed up).
	var cands: Array = []
	for p in avail:
		for st in STAT_LINES:
			var v: int = p.soldier.stats[st]
			var extreme := v >= NEWS_GREAT or v <= NEWS_POOR
			if extreme == truthful:
				cands.append([p, st, v >= NEWS_GREAT if truthful else rng.randf() < 0.5])
	if cands.is_empty():
		return {}
	var pick: Array = cands[rng.randi_range(0, cands.size() - 1)]
	var pr: Prospect = pick[0]
	var great: bool = pick[2]
	story["prospect"] = pr
	story["stat"] = pick[1]
	story["kind"] = &"hint"
	story["great"] = great
	story["text"] = STAT_LINES[pick[1]][0 if great else 1] % pr.soldier.full_name()
	pr.consensus += NEWS_HINT_SHIFT if great else -NEWS_HINT_SHIFT
	return story


func news_for(p: Prospect) -> Array:
	return news.filter(func(n): return n["prospect"] == p)


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
