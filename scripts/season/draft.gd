class_name Draft
extends RefCounted
## Yearly draft class, scouting and draft-day picks (Madden-style).
##
## Scouting: the user earns POINTS_PER_WEEK scout points every week of the season (unspent points
## carry over). Each point spent on a prospect scouts two random stat groups, revealing each as a
## window of named tiers ("Inconsistent - Sharpshooter"); scouting a group again narrows it (3 tiers
## -> 2). Once every group is down to 2 tiers, each further point pins one group to its exact tier.
## Numbers and potential are never shown.
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
## Free scouting: every prospect carries a rough "area scout" grade (a noisy class-relative
## letter), and once per season (Week 1) the user may send scouts to one region: every prospect
## from that region's states is scouted to REGION_SCOUT_POINTS for free. Auto-scout spends points
## for him (favorites first, then the big board). Prospects can be starred as favorites.
##
## Draft: same order every round (worst team first, champion last) for ROUNDS rounds. AI teams pick on a
## pick-day read of the consensus value plus a bonus for their weakest position.

const CLASS_SIZE := 110
const ROUNDS := 3
const POINTS_PER_WEEK := 20
const REGION_SCOUT_POINTS := 4
## Auto-scout levels: "up to 3" gives every group a first look, "up to 6" narrows every group.
const AUTO_SCOUT_LEVELS := [3, 6]
## Area-scout grades by class percentile (best first) and the noise on their read (OVR points).
const AREA_GRADES := [["A", 0.05], ["B+", 0.15], ["B", 0.30], ["C+", 0.50], ["C", 0.70], ["D", 0.88], ["F", 1.0]]
const AREA_NOISE := 4.0
const MAX_POINTS_PER_PROSPECT := 10
## Window width (in tiers) after the 1st, 2nd and 3rd scout of a group.
const WINDOW_WIDTHS := [3, 2, 1]
## Groups scouted per point while any group is still wider than 2 tiers (then 1 per point).
const GROUPS_PER_POINT := 2
## Scouts a group needs before the one-group, exact-tier phase starts.
const BROAD_SCOUTS := 2
## Group rating thresholds for tiers 1..4 (tier 0 is below the first).
const TIER_THRESHOLDS := [58, 68, 77, 86]
const TIER_COUNT := 5
const TIER_NAMES := {
	Stats.ACCURACY: ["Spray & Pray", "Inconsistent", "Steady Aim", "Marksman", "Sharpshooter"],
	Stats.HANDLING: ["Butterfingers", "Clunky", "Capable", "Smooth Operator", "Gunslinger"],
	Stats.PHYSICALITY: ["Out of Shape", "Average Build", "Athletic", "Explosive", "Freak Athlete"],
	Stats.MENTALITY: ["Lost", "Rattled", "Level-Headed", "Leader", "Field General"],
	Stats.OBJECTIVE: ["Point Shy", "Wanderer", "Contester", "Point Man", "King of the Hill"],
	Stats.DURABILITY: ["Glass", "Fragile", "Durable", "Sturdy", "Iron Man"],
}
const PROSPECT_QUALITY := 58.0
const PROSPECT_QUALITY_SD := 6.0
## Blue-chippers per class [min, max], their OVR at the listed position [min, max] and minimum
## potential. They are day-one starters.
const BLUE_CHIPS := [3, 6]
const BLUE_CHIP_OVR := [68, 72]
const BLUE_CHIP_MIN_POTENTIAL := 3
## Chance a class has a generational talent (one per class at most), and his OVR [min, max].
const GENERATIONAL_CHANCE := 0.18
const GENERATIONAL_OVR := [74, 77]
## Specialists per class [min, max] and the range of their elite group's stats.
const SPECIALISTS := [8, 12]
const SPECIALIST_STAT := [78, 90]
## Prospect news: stories per week (weights for 0, 1, 2) and how far a rising/falling story moves
## the consensus. Facts (drill results, class rankings, measured strengths/weaknesses) are always
## true; rumors ("reportedly", "one scout claims", "word is") and stock buzz are true
## NEWS_RUMOR_TRUE of the time, so they can't be trusted or ignored.
const NEWS_WEIGHTS := [25, 55, 20]
const NEWS_RUMOR_TRUE := 0.5
## Share of stat stories that are rumors (the rest are facts).
const NEWS_RUMOR_SHARE := 0.4
const NEWS_STOCK_SHIFT := 1.5
const NEWS_HINT_SHIFT := 0.6
## A stat at or above GREAT (or at or below POOR) is "newsworthy" for a stat story. A false rumor
## is about a stat inside the ordinary band [POOR + 8, GREAT - 8].
const NEWS_GREAT := 82
const NEWS_POOR := 52
const NEWS_ORDINARY_MARGIN := 8
const RISING_LINES := [
	"%s is turning heads in workouts; his stock is climbing.",
	"Scouts are buzzing about %s; his stock is climbing.",
	"%s keeps rising on draft boards. One GM called him \"the real deal.\"",
	"Word is several teams have %s much higher than the mocks.",
]
const FALLING_LINES := [
	"Concerns are mounting about %s; his stock is sliding.",
	"Word is %s struggled in a private workout and is falling on some boards.",
	"Teams are reportedly cooling on %s after private workouts.",
	"One scout on %s: \"I just don't see it translating.\"",
]
## Class rankings: stat -> [best in the class, worst in the class]. Only told about the prospect
## who really is first (or last) in the whole class in that stat, by a clear point.
const STAT_LINES := {
	Stats.LONG_ACC: ["%s posted the best long-range score in the class at the combine.", "%s posted the worst long-range score in the class at the combine."],
	Stats.MEDIUM_ACC: ["%s topped the whole class on the mid-range qualification course.", "%s finished dead last in the class on the mid-range course."],
	Stats.SHORT_ACC: ["%s posted the best shoot-house score in the class.", "%s posted the worst shoot-house score in the class."],
	Stats.GROUPING: ["%s shot the tightest groups of anyone in the class.", "%s shot the widest groups of anyone in the class."],
	Stats.SWAY: ["Nobody in the class shot steadier on the move than %s.", "%s had the shakiest moving-fire score in the class."],
	Stats.RELOAD: ["%s posted the fastest reload times in the class.", "%s posted the slowest reload times in the class."],
	Stats.SPEED: ["%s ran the fastest 40 in the class.", "%s ran the slowest 40 in the class."],
	Stats.AGILITY: ["%s posted the best cone-drill time in the class.", "%s posted the worst cone-drill time in the class."],
	Stats.STRENGTH: ["%s led the class in the sled push.", "%s finished last in the class in the sled push."],
	Stats.ENDURANCE: ["%s finished the 20km ruck march first in the class.", "%s finished the 20km ruck march last in the class."],
	Stats.AWARENESS: ["%s graded out as the most aware prospect in the class in sim exercises.", "%s graded out as the least aware prospect in the class in sim exercises."],
	Stats.COMPOSURE: ["%s posted the best live-fire stress test score in the class.", "%s posted the worst live-fire stress test score in the class."],
	Stats.TEAMWORK: ["The class voted %s its best teammate.", "%s got the lowest teammate grades in the class."],
	Stats.ANCHOR: ["%s held the hill longer than anyone in the class in the objective scrimmage.", "%s was pushed off the point faster than anyone in the class."],
	Stats.BREACH: ["%s led the class in successful point pushes at the showcase.", "%s had the fewest successful point pushes in the class."],
	Stats.OBJ_IQ: ["%s posted the highest objective-IQ grade in the class.", "%s posted the lowest objective-IQ grade in the class."],
	Stats.TOUGHNESS: ["Trainers rate %s the quickest healer in the class.", "Trainers rate %s the slowest healer in the class."],
	Stats.INJURY: ["%s has the cleanest medicals in the class.", "%s has the most red flags on his medicals in the class."],
}
## Measured strengths/weaknesses (no ranking): stat -> [great (>= GREAT), poor (<= POOR)].
const REPORT_LINES := {
	Stats.LONG_ACC: ["%s was ringing steel past 400m at his workout.", "%s couldn't find the target past 300m at his workout."],
	Stats.MEDIUM_ACC: ["%s shot a near-perfect mid-range qualification course.", "%s had trouble at mid range, scattering shots across the lane."],
	Stats.SHORT_ACC: ["%s cleared the close-quarters shoot house without a miss.", "%s was missing point-blank targets in the shoot house."],
	Stats.GROUPING: ["%s's shot groups at the range were \"the size of a coin.\"", "%s's shot groups were all over the paper."],
	Stats.SWAY: ["%s hit every plate on the run-and-gun course without slowing down.", "%s's muzzle was wandering all over on the moving-fire course."],
	Stats.RELOAD: ["%s's magazine changes were lightning-quick in the timed drills.", "%s fumbled magazine changes in the timed drills."],
	Stats.SPEED: ["%s posted a blazing 40 time.", "%s looked slow in sprint testing."],
	Stats.AGILITY: ["%s was a blur through the cone drill.", "%s looked stiff in the agility drills."],
	Stats.STRENGTH: ["%s put up big numbers in the sled push.", "%s struggled in strength testing."],
	Stats.ENDURANCE: ["%s finished the 20km ruck march well ahead of the pace.", "%s couldn't finish the 20km ruck march."],
	Stats.AWARENESS: ["Instructors rave about %s's battlefield awareness in sim exercises.", "%s was ambushed \"almost every round\" in sim exercises."],
	Stats.COMPOSURE: ["%s stayed ice-cold through the live-fire stress test.", "%s froze up during the live-fire stress test."],
	Stats.TEAMWORK: ["Squadmates at the showcase rave about %s as a teammate.", "Reports say %s clashed with his squad at the showcase."],
	Stats.ANCHOR: ["%s held the hill alone for a full minute in the objective scrimmage.", "%s got pushed off the point every time in the objective scrimmage."],
	Stats.BREACH: ["%s led successful pushes onto the point at the showcase.", "%s hesitated on every point push at the showcase."],
	Stats.OBJ_IQ: ["Coaches say %s \"always knows where the point is.\"", "%s kept chasing kills while the point sat empty."],
	Stats.TOUGHNESS: ["%s played through a broken hand at his final amateur event.", "%s left the combine early with a minor knock."],
	Stats.INJURY: ["Medicals came back spotless for %s.", "Teams have flagged %s's medicals."],
}
## Rumors: [great lines, poor lines], formatted with [name, STAT_NOUNS[stat]].
const RUMOR_LINES := [
	["One scout claims %s's %s is \"elite.\"", "Word is %s tested off the charts in %s at a private workout.", "%s reportedly wowed one team's staff with his %s."],
	["One scout claims %s's %s \"won't hold up\" at the pro level.", "Word is teams have concerns about %s's %s.", "%s reportedly struggled with his %s at a private workout."],
]
const STAT_NOUNS := {
	Stats.LONG_ACC: "long-range shooting", Stats.MEDIUM_ACC: "mid-range shooting", Stats.SHORT_ACC: "close-quarters shooting",
	Stats.GROUPING: "shot grouping", Stats.SWAY: "aim on the move", Stats.RELOAD: "reload speed", Stats.SPEED: "speed",
	Stats.AGILITY: "agility", Stats.STRENGTH: "strength", Stats.ENDURANCE: "endurance", Stats.AWARENESS: "awareness",
	Stats.COMPOSURE: "composure", Stats.TEAMWORK: "teamwork", Stats.ANCHOR: "ability to hold a point",
	Stats.BREACH: "point pushing", Stats.OBJ_IQ: "objective IQ", Stats.TOUGHNESS: "recovery from knocks", Stats.INJURY: "medicals",
}
## Phenoms: every non-injury stat at least this (they play any position well).
const PHENOM_STAT_MIN := 64
const PHENOM_STAT_MAX := 74
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
## stat, great and claim (&"rank"/&"report"/&"rumor") for hint stories, text, truthful, rumor}.
## Facts are always true; rumors (stock buzz and rumor-worded stat stories) are coin flips.
var news: Array = []
var _news_rng := RandomNumberGenerator.new()
var scout_points := 0
## Region the user's scouts covered this season ("" = not used yet).
var region_scouted := ""
## One team per pick, in order. Empty until the draft order is set (after the Final).
var order: Array[Team] = []
## Who each pick originally belonged to (order before trades), same indexing as `order`.
var original: Array[Team] = []
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
		p.soldier.home_state = LeagueData.random_state(rng)
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
	if rng.randf() < GENERATIONAL_CHANCE:
		d._make_blue_chip(pool.pop_at(rng.randi_range(0, pool.size() - 1)), true)
	for i in rng.randi_range(SPECIALISTS[0], SPECIALISTS[1]):
		d._make_specialist(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	for p in d.prospects:
		p.consensus = true_value(p) + rng.randfn(0.0, CONSENSUS_NOISE) - (PHENOM_UNDERRATE if p.phenom else 0.0)
	d.rerank()
	d._grade_area(rng)
	return d


## Rough area-scout letter for every prospect: his class percentile on a noisy read.
func _grade_area(rng: RandomNumberGenerator) -> void:
	var reads := {}
	for p in prospects:
		reads[p] = true_value(p) + rng.randfn(0.0, AREA_NOISE)
	var board := prospects.duplicate()
	board.sort_custom(func(a: Prospect, b: Prospect): return reads[a] > reads[b])
	for i in board.size():
		board[i].area_grade = _grade_for_pct(float(i + 1) / board.size())
	var truth := prospects.duplicate()
	truth.sort_custom(func(a: Prospect, b: Prospect): return true_value(a) > true_value(b))
	for i in truth.size():
		truth[i].true_grade = _grade_for_pct(float(i + 1) / truth.size())


static func _grade_for_pct(pct: float) -> String:
	for g in AREA_GRADES:
		if pct <= g[1]:
			return g[0]
	return AREA_GRADES[-1][0]


## Recomputes every prospect's big-board rank from the consensus.
func rerank() -> void:
	var board := prospects.duplicate()
	board.sort_custom(func(a: Prospect, b: Prospect): return a.consensus > b.consensus)
	for i in board.size():
		board[i].projected_rank = i + 1


func _make_blue_chip(p: Prospect, generational := false) -> void:
	p.standout = &"generational" if generational else &"blue_chip"
	var s := p.soldier
	var band: Array = GENERATIONAL_OVR if generational else BLUE_CHIP_OVR
	var target := _rng.randi_range(band[0], band[1])
	# Lift every rating together until he's a starter-grade OVR at his listed position.
	for i in 60:
		if s.ovr_at_role(p.listed_role) >= target:
			break
		for st in Stats.ALL:
			if st != Stats.INJURY and st != Stats.TOUGHNESS:
				s.stats[st] = Stats.clamp_rating(s.stats[st] + 1)
	s.potential = Soldier.POTENTIAL_A if generational else maxi(s.potential, _rng.randi_range(BLUE_CHIP_MIN_POTENTIAL, Soldier.POTENTIAL_A))
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
	if p.standout == &"generational":
		return "GENERATIONAL"
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
	var story := {"year": year, "week": week, "truthful": true, "rumor": false, "stat": &""}
	if rng.randf() < 0.5:
		# Stock buzz is rumor: true ones go to prospects the consensus has wrong, in the right direction.
		var truthful := rng.randf() < NEWS_RUMOR_TRUE
		story["rumor"] = true
		story["truthful"] = truthful
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
	var pick: Array = _rumor_pick(avail, rng) if rng.randf() < NEWS_RUMOR_SHARE else _fact_pick(avail, rng)
	if pick.is_empty():
		return {}
	var pr: Prospect = pick[0]
	var st: StringName = pick[1]
	var great: bool = pick[2]
	var kind: String = pick[3]
	story["prospect"] = pr
	story["stat"] = st
	story["kind"] = &"hint"
	story["great"] = great
	story["claim"] = kind
	match kind:
		"rank":
			story["text"] = STAT_LINES[st][0 if great else 1] % pr.soldier.full_name()
		"report":
			story["text"] = REPORT_LINES[st][0 if great else 1] % pr.soldier.full_name()
		_:
			var lines: Array = RUMOR_LINES[0 if great else 1]
			story["text"] = lines[rng.randi_range(0, lines.size() - 1)] % [pr.soldier.full_name(), STAT_NOUNS[st]]
			story["rumor"] = true
			story["truthful"] = pick[4]
	pr.consensus += NEWS_HINT_SHIFT if great else -NEWS_HINT_SHIFT
	return story


## The class leader (or last place) in `st`, by at least one point; null if tied.
func class_extreme(st: StringName, best: bool) -> Prospect:
	var top: Prospect = null
	var runner := -1000
	for p in prospects:
		var v: int = p.soldier.stats[st] if best else -p.soldier.stats[st]
		if top == null:
			top = p
			continue
		var tv: int = top.soldier.stats[st] if best else -top.soldier.stats[st]
		if v > tv:
			runner = tv
			top = p
		elif v > runner:
			runner = v
	if top == null:
		return null
	var topv: int = top.soldier.stats[st] if best else -top.soldier.stats[st]
	return top if topv > runner else null


## A fact: [prospect, stat, great, "rank"|"report"]. Rankings go only to the real class
## leader/last place (and only when that's newsworthy); reports to any extreme stat.
func _fact_pick(avail: Array, rng: RandomNumberGenerator) -> Array:
	var ranks: Array = []
	for st in STAT_LINES:
		for best in [true, false]:
			var p := class_extreme(st, best)
			if p == null or not avail.has(p):
				continue
			var v: int = p.soldier.stats[st]
			if (best and v >= NEWS_GREAT) or (not best and v <= NEWS_POOR):
				ranks.append([p, st, best, "rank"])
	var reports: Array = []
	for p in avail:
		for st in REPORT_LINES:
			var v: int = p.soldier.stats[st]
			if v >= NEWS_GREAT or v <= NEWS_POOR:
				reports.append([p, st, v >= NEWS_GREAT, "report"])
	if not ranks.is_empty() and (reports.is_empty() or rng.randf() < 0.4):
		return ranks[rng.randi_range(0, ranks.size() - 1)]
	if reports.is_empty():
		return []
	return reports[rng.randi_range(0, reports.size() - 1)]


## A rumor: [prospect, stat, great, "rumor", truthful]. True ones are about a real extreme stat;
## false ones dress up an ordinary stat as a strength or a weakness.
func _rumor_pick(avail: Array, rng: RandomNumberGenerator) -> Array:
	var truthful := rng.randf() < NEWS_RUMOR_TRUE
	var cands: Array = []
	for p in avail:
		for st in STAT_NOUNS:
			var v: int = p.soldier.stats[st]
			if truthful and (v >= NEWS_GREAT or v <= NEWS_POOR):
				cands.append([p, st, v >= NEWS_GREAT, "rumor", true])
			elif not truthful and v >= NEWS_POOR + NEWS_ORDINARY_MARGIN and v <= NEWS_GREAT - NEWS_ORDINARY_MARGIN:
				cands.append([p, st, rng.randf() < 0.5, "rumor", false])
	if cands.is_empty():
		return []
	return cands[rng.randi_range(0, cands.size() - 1)]


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


## Spends one scout point. While any group is wider than 2 tiers, two random such groups are
## narrowed; after that, one group is pinned to its exact tier. Each reveal is a window of
## WINDOW_WIDTHS[n] tiers containing the true tier, inside any earlier window.
## Returns the groups scouted (empty if not allowed).
func scout(p: Prospect) -> Array[StringName]:
	var out: Array[StringName] = []
	if not can_scout(p):
		return out
	var broad: Array[StringName] = []
	for g in Stats.GROUP_ORDER:
		if int(p.scouts.get(g, 0)) < BROAD_SCOUTS:
			broad.append(g)
	var options: Array[StringName] = broad if not broad.is_empty() else p.scoutable_groups()
	var count := GROUPS_PER_POINT if not broad.is_empty() else 1
	for i in mini(count, options.size()):
		# Least-scouted groups first, so every group gets a first look before any gets a second.
		var fewest := 99
		for g in options:
			fewest = mini(fewest, int(p.scouts.get(g, 0)))
		var pool: Array[StringName] = options.filter(func(g): return int(p.scouts.get(g, 0)) == fewest)
		var g: StringName = pool[_rng.randi_range(0, pool.size() - 1)]
		options.erase(g)
		_narrow(p, g)
		out.append(g)
	p.points += 1
	scout_points -= 1
	return out


## Scouts `p` up to `level` points without spending the user's points (region scouting).
func scout_free(p: Prospect, level: int) -> void:
	while p.points < mini(level, MAX_POINTS_PER_PROSPECT) and not p.fully_scouted():
		scout_points += 1
		scout(p)


func region_of(p: Prospect) -> String:
	return LeagueData.region_of(p.soldier.home_state)


## Prospects from `region`.
func in_region(region: String) -> Array[Prospect]:
	var out: Array[Prospect] = []
	for p in prospects:
		if region_of(p) == region:
			out.append(p)
	return out


## The once-a-season region scout: every prospect from `region` scouted to REGION_SCOUT_POINTS.
## Returns how many prospects it covered (-1 if already used this season).
func scout_region(region: String) -> int:
	if region_scouted != "":
		return -1
	region_scouted = region
	var n := 0
	for p in in_region(region):
		if p.is_available():
			scout_free(p, REGION_SCOUT_POINTS)
			n += 1
	return n


## Auto-scout: spends scout points bringing prospects up to `level` points (level 3 covers
## everyone below 3; level 6 only those already at 3+). Favorites go first, then the big board.
## Returns how many prospects were scouted.
func auto_scout(level: int) -> int:
	var lo := 0 if level <= AUTO_SCOUT_LEVELS[0] else AUTO_SCOUT_LEVELS[0]
	var board: Array = available().filter(func(p: Prospect): return p.points >= lo and p.points < level)
	board.sort_custom(func(a: Prospect, b: Prospect):
		if a.favorite != b.favorite:
			return a.favorite
		return a.projected_rank < b.projected_rank)
	var n := 0
	for p in board:
		if scout_points <= 0:
			break
		while p.points < level and can_scout(p):
			scout(p)
		n += 1
	return n


func favorites() -> Array[Prospect]:
	var out: Array[Prospect] = []
	for p in prospects:
		if p.favorite:
			out.append(p)
	out.sort_custom(func(a: Prospect, b: Prospect): return a.projected_rank < b.projected_rank)
	return out


func _narrow(p: Prospect, g: StringName) -> void:
	var n: int = p.scouts.get(g, 0)
	var width: int = WINDOW_WIDTHS[n]
	var prev: Vector2i = p.reveals.get(g, Vector2i(0, TIER_COUNT - 1))
	var t := p.true_tier(g)
	var lo_min := maxi(prev.x, t - width + 1)
	var lo_max := mini(t, prev.y - width + 1)
	var lo := _rng.randi_range(lo_min, lo_max)
	p.reveals[g] = Vector2i(lo, lo + width - 1)
	p.scouts[g] = n + 1


# --- draft day ---------------------------------------------------------------------

## `teams_in_order` is round-1 order (first pick first); every round repeats it.
func set_order(teams_in_order: Array) -> void:
	order = []
	for t in full_order(teams_in_order):
		order.append(t)
	original = order.duplicate()
	next_pick = 0


func is_started() -> bool:
	return not order.is_empty()


func is_complete() -> bool:
	return is_started() and next_pick >= order.size()


## Picks `team` still has to make.
func picks_left_for(team: Team) -> int:
	var n := 0
	for i in range(next_pick, order.size()):
		if order[i] == team:
			n += 1
	return n


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
	p.soldier.draft_pick = p.pick_number
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
	picks_per_round = maxi(1, picks_per_round)
	var rnd := (rank - 1) / picks_per_round + 1
	if rnd > ROUNDS:
		return "Undrafted"
	var third := ((rank - 1) % picks_per_round) * 3 / picks_per_round
	return "%s %s" % [["Early", "Mid", "Late"][third], ["1st", "2nd", "3rd", "4th"][rnd - 1]]


func projection(p: Prospect) -> String:
	return projection_text(p.projected_rank, league.teams.size() if league != null else Season.TEAM_COUNT)


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


## Projected picks from `pick_order` (every pick, all rounds) starting at the next pick:
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


## Full pick order (all rounds) from a round-1 order: like football, the worst team picks
## first in every round.
static func full_order(teams_in_order: Array) -> Array:
	var out: Array = []
	for r in ROUNDS:
		out.append_array(teams_in_order)
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
