class_name Facilities
extends RefCounted
## Club facilities (issue #38): eight upgrades at levels 1-5, bought in the offseason with the club fund
## (Revenue.cash) and active at once. Level 1 is the baseline: no effect. Every level above it adds the
## same step, so level 5 is four steps:
##   Training Facility       weekly training XP +5% a step (Training.run_week)
##   Drill Rooms             offseason and camp-week XP +5% a step (Season.offseason_xp); camp drill points
##                           +1 at levels 3-4, +2 at 5 (Camp.run)
##   Scouting Office         +2 scout points a week a step (the user's draft points)
##   Medical Center          injuries 5% shorter and +1% weekly fatigue recovery a step (Conditioning)
##   Marketing Team          extra one-time XP per honor: +50 a step for a Player of the Week, +250 for a season
##                           honor (award, All-League, stat leader; on top of SeasonReview.HONOR_XP) (SeasonReview.run)
##   Gear Sponsor            the impact part of match XP x1.1 at level 2 up to x1.5 at 5 (Progression.award_match_xp)
##   Sports Science Lab      dev-star gain chances +10% and loss chances -15% a step (SeasonReview.run, Camp.run)
##   Performance Institute   a 3% chance a step, per rostered player each offseason, to raise one group cap
##                           by 1-2 (after aging; see institute)
## Pacing: one level per facility and MAX_UPGRADES upgrades per club each offseason. Upkeep: every board
## review charges UPKEEP_SHARE of what has been invested (authored starting levels count), capped at
## UPKEEP_GRANT_CAP of that year's grant. A fund that can't cover it loses a level on one facility instead
## (no debt). AI clubs buy once a season, at camp, by direction (Trades.mode), keeping a reserve.
## Levels live on Team.facility_levels (missing = 1) so the sim hooks only need the team. Saved with the Season.

const TRAINING := &"training"
const DRILL := &"drill"
const SCOUTING := &"scouting"
const MEDICAL := &"medical"
const MARKETING := &"marketing"
const GEAR := &"gear"
const LAB := &"lab"
const INSTITUTE := &"institute"
## Column order of LeagueData.FACILITY_LEVELS.
const IDS: Array[StringName] = [TRAINING, DRILL, SCOUTING, MEDICAL, MARKETING, GEAR, LAB, INSTITUTE]
const MAX_LEVEL := 5
const NAMES := {
	TRAINING: "Training Facility", DRILL: "Drill Rooms", SCOUTING: "Scouting Office", MEDICAL: "Medical Center",
	MARKETING: "Marketing Team", GEAR: "Gear Sponsor", LAB: "Sports Science Lab", INSTITUTE: "Performance Institute",
}
const TIERS := {
	TRAINING: &"standard", DRILL: &"standard", SCOUTING: &"standard", MEDICAL: &"standard",
	MARKETING: &"cheap", GEAR: &"cheap", LAB: &"premium", INSTITUTE: &"premium",
}
## Price ($K) to reach levels 2, 3, 4 and 5, by tier.
const PRICES := {
	&"cheap": [10000, 20000, 35000, 55000],
	&"standard": [20000, 40000, 70000, 110000],
	&"premium": [30000, 60000, 100000, 160000],
}
const MAX_UPGRADES := 2
const UPKEEP_SHARE := 0.05
const UPKEEP_GRANT_CAP := 0.25

## Effects per step (level - 1).
const TRAINING_XP := 0.05
const DRILL_XP := 0.05
## Extra camp drill points by level (1..5).
const DRILL_CAMP_POINTS := [0, 0, 1, 1, 2]
const SCOUT_POINTS := 2
const MEDICAL_INJURY := 0.05
const MEDICAL_RECOVERY := 0.01
const MARKETING_POTW_XP := 50.0
const MARKETING_HONOR_XP := 250.0
## Gear Sponsor: x1.1 at level 2 up to x1.5 at level 5, in even steps between.
const GEAR_IMPACT_L2 := 0.1
const GEAR_IMPACT_L5 := 0.5
const LAB_GAIN := 0.1
const LAB_LOSS := 0.15
const INSTITUTE_CHANCE := 0.03
## Players younger than this are likelier to get an Institute cap raise; older ones less.
const INSTITUTE_YOUNG_AGE := 27
const INSTITUTE_YOUNG := 1.3
const INSTITUTE_OLD := 0.7

## AI: what each direction (Trades.mode) buys first, the cheapest next level first.
const AI_FOCUS := {
	&"contender": [TRAINING, MEDICAL, GEAR],
	&"balanced": [TRAINING, MEDICAL, DRILL, LAB],
	&"rebuilding": [SCOUTING, LAB, DRILL, INSTITUTE],
}
## AI: club fund held back for signing bonuses, on top of next year's upkeep ($K).
const AI_BONUS_RESERVE := {&"contender": 30000, &"balanced": 15000, &"rebuilding": 5000}
## AI: an upgrade outside its focus (at most one a season) only when this many times its price is left over
## after the reserve.
const AI_SPARE_FACTOR := 2.0

var seeded := false
## Season year (the offseason after it) -> {abbrev -> [facility ids upgraded]}.
var bought := {}
## Season year -> {abbrev -> $K spent on upgrades}.
var purchases := {}
## Season year -> {abbrev -> $K upkeep paid}.
var upkeep := {}
## Season year -> {abbrev -> facility id that lost a level because the upkeep couldn't be paid}.
var drops := {}


# --- data -----------------------------------------------------------------------------

static func level(team: Team, id: StringName) -> int:
	if team == null:
		return 1
	return clampi(int(team.facility_levels.get(id, 1)), 1, MAX_LEVEL)


static func steps(team: Team, id: StringName) -> int:
	return level(team, id) - 1


static func facility_name(id: StringName) -> String:
	return NAMES.get(id, String(id))


## Price ($K) of the upgrade to `to_level` (2..5).
static func price(id: StringName, to_level: int) -> int:
	if to_level < 2 or to_level > MAX_LEVEL:
		return 0
	return int(PRICES[TIERS[id]][to_level - 2])


## Price of `team`'s next level of `id` (0 at the top level).
static func next_price(team: Team, id: StringName) -> int:
	return price(id, level(team, id) + 1)


## Total price of levels 2..`lvl` of `id`.
static func cost_to(id: StringName, lvl: int) -> int:
	var total := 0
	for l in range(2, lvl + 1):
		total += price(id, l)
	return total


## What `team` has put into its facilities ($K), starting levels included.
static func invested(team: Team) -> int:
	var total := 0
	for id in IDS:
		total += cost_to(id, level(team, id))
	return total


# --- effects --------------------------------------------------------------------------

static func training_mult(team: Team) -> float:
	return 1.0 + TRAINING_XP * steps(team, TRAINING)


static func drill_mult(team: Team) -> float:
	return 1.0 + DRILL_XP * steps(team, DRILL)


static func camp_points(team: Team) -> int:
	return int(DRILL_CAMP_POINTS[level(team, DRILL) - 1])


## The user's scout points per week.
static func scout_points(team: Team) -> int:
	return Draft.POINTS_PER_WEEK + SCOUT_POINTS * steps(team, SCOUTING)


static func injury_weeks(team: Team, weeks: int) -> int:
	var n := steps(team, MEDICAL)
	if n == 0:
		return weeks
	return maxi(1, roundi(weeks * (1.0 - MEDICAL_INJURY * n)))


static func recovery_bonus(team: Team) -> float:
	return MEDICAL_RECOVERY * steps(team, MEDICAL)


static func potw_xp(team: Team) -> float:
	return MARKETING_POTW_XP * steps(team, MARKETING)


static func honor_xp(team: Team) -> float:
	return MARKETING_HONOR_XP * steps(team, MARKETING)


static func gear_mult(team: Team) -> float:
	return 1.0 + _gear_bonus(steps(team, GEAR))


static func _gear_bonus(n: int) -> float:
	if n <= 0:
		return 0.0
	return GEAR_IMPACT_L2 + (GEAR_IMPACT_L5 - GEAR_IMPACT_L2) * (n - 1) / float(MAX_LEVEL - 2)


static func lab_gain_mult(team: Team) -> float:
	return 1.0 + LAB_GAIN * steps(team, LAB)


static func lab_loss_mult(team: Team) -> float:
	return 1.0 - LAB_LOSS * steps(team, LAB)


static func institute_chance(team: Team) -> float:
	return INSTITUTE_CHANCE * steps(team, INSTITUTE)


## What `id` does at `lvl` ("Baseline" at level 1).
static func effect_text(id: StringName, lvl: int) -> String:
	var n := lvl - 1
	if n <= 0:
		match id:
			SCOUTING:
				return "%d scout points a week" % Draft.POINTS_PER_WEEK
		return "Baseline"
	match id:
		TRAINING:
			return "+%d%% weekly training XP" % roundi(100 * TRAINING_XP * n)
		DRILL:
			var pts := int(DRILL_CAMP_POINTS[lvl - 1])
			return "+%d%% offseason and camp XP%s" % [roundi(100 * DRILL_XP * n), (", +%d camp drill point%s" % [pts, "" if pts == 1 else "s"]) if pts > 0 else ""]
		SCOUTING:
			return "%d scout points a week" % (Draft.POINTS_PER_WEEK + SCOUT_POINTS * n)
		MEDICAL:
			return "Injuries %d%% shorter, +%d%% weekly recovery" % [roundi(100 * MEDICAL_INJURY * n), roundi(100 * MEDICAL_RECOVERY * n)]
		MARKETING:
			return "+%d XP per Player of the Week, +%d per season honor" % [roundi(MARKETING_POTW_XP * n), roundi(MARKETING_HONOR_XP * n)]
		GEAR:
			return "+%d%% match impact XP" % roundi(100 * _gear_bonus(n))
		LAB:
			return "Dev-star gains +%d%%, losses -%d%%" % [roundi(100 * LAB_GAIN * n), roundi(100 * LAB_LOSS * n)]
		INSTITUTE:
			return "%d%% a player each offseason: a group cap +1-2" % roundi(100 * INSTITUTE_CHANCE * n)
	return ""


# --- setup ----------------------------------------------------------------------------

## Authored starting levels for the fixed league's clubs (generated test leagues start at 1). Also runs
## on loading an older save that predates facilities.
func ensure(season: Season) -> void:
	if seeded:
		return
	seeded = true
	for t: Team in season.league.teams:
		if t.city == "" or not t.facility_levels.is_empty():
			continue
		var row: Array = LeagueData.FACILITY_LEVELS.get(t.abbrev, [])
		for i in mini(row.size(), IDS.size()):
			if int(row[i]) > 1:
				t.facility_levels[IDS[i]] = clampi(int(row[i]), 1, MAX_LEVEL)


# --- buying ---------------------------------------------------------------------------

func bought_ids(season: Season, team: Team) -> Array:
	return (bought.get(season.year, {}) as Dictionary).get(team.abbrev, [])


func upgrades_left(season: Season, team: Team) -> int:
	return maxi(0, MAX_UPGRADES - bought_ids(season, team).size())


## Why `team` can't upgrade `id` now ("" = it can).
func upgrade_error(season: Season, team: Team, id: StringName) -> String:
	if not IDS.has(id):
		return "Unknown facility."
	if season.phase != Season.PHASE_OFFSEASON:
		return "Facilities are upgraded in the offseason."
	if level(team, id) >= MAX_LEVEL:
		return "%s is at the top level." % facility_name(id)
	if bought_ids(season, team).has(id):
		return "%s was already upgraded this offseason." % facility_name(id)
	if upgrades_left(season, team) <= 0:
		return "The board allows %d upgrades an offseason." % MAX_UPGRADES
	if season.revenue.frozen(team):
		return "The board has frozen spending while the club fund is below $0."
	var cost := next_price(team, id)
	if float(cost) > season.revenue.cash_of(team):
		return "Not enough in the club fund: %s needed, %s available." % [Contracts.money(cost), Contracts.money(roundi(season.revenue.cash_of(team)))]
	return ""


## Buys `team`'s next level of `id` out of the club fund. Returns "" or the reason it can't.
func upgrade(season: Season, team: Team, id: StringName) -> String:
	var err := upgrade_error(season, team, id)
	if err != "":
		return err
	var cost := next_price(team, id)
	var rv := season.revenue
	rv.cash[team.abbrev] = rv.cash_of(team) - cost
	team.facility_levels[id] = level(team, id) + 1
	var y := season.year
	if not bought.has(y):
		bought[y] = {}
	if not bought[y].has(team.abbrev):
		bought[y][team.abbrev] = []
	(bought[y][team.abbrev] as Array).append(id)
	if not purchases.has(y):
		purchases[y] = {}
	purchases[y][team.abbrev] = int(purchases[y].get(team.abbrev, 0)) + cost
	_prune(y)
	season.news.facility_upgrade(season, team, id, level(team, id), cost)
	return ""


func purchases_of(year: int, team: Team) -> int:
	return int((purchases.get(year, {}) as Dictionary).get(team.abbrev, 0))


func upkeep_of(year: int, team: Team) -> int:
	return int((upkeep.get(year, {}) as Dictionary).get(team.abbrev, 0))


func drop_of(year: int, team: Team) -> StringName:
	return StringName((drops.get(year, {}) as Dictionary).get(team.abbrev, &""))


func _prune(y: int) -> void:
	for d: Dictionary in [bought, purchases, upkeep, drops]:
		for k in d.keys():
			if int(k) <= y - Revenue.LEDGER_YEARS:
				d.erase(k)


# --- upkeep ---------------------------------------------------------------------------

## Upkeep `team` owes at this year's board review ($K): UPKEEP_SHARE of what it has invested, capped at
## UPKEEP_GRANT_CAP of the grant (its market term before the first review).
static func upkeep_due(season: Season, team: Team) -> int:
	var g := season.revenue.grant_of(season.year, team)
	var grant := float(g.get("grant", Revenue.market_grant(team.market_rating)))
	return roundi(minf(UPKEEP_SHARE * invested(team), UPKEEP_GRANT_CAP * maxf(0.0, grant)))


## Board review, after the grant is in: every club pays its upkeep, or loses a level on one facility if
## the fund can't cover it. Returns [{team, facility, level, due}] for the clubs that lost a level.
func charge_upkeep(season: Season) -> Array:
	ensure(season)
	var y := season.year
	var paid := {}
	var lost := {}
	var out: Array = []
	var rv := season.revenue
	for t: Team in season.league.teams:
		var due := upkeep_due(season, t)
		if due <= 0:
			continue
		if rv.cash_of(t) >= float(due):
			rv.cash[t.abbrev] = rv.cash_of(t) - due
			paid[t.abbrev] = due
			continue
		var id := _drop_pick(t)
		var to := level(t, id) - 1
		if to <= 1:
			t.facility_levels.erase(id)
		else:
			t.facility_levels[id] = to
		lost[t.abbrev] = id
		out.append({"team": t, "facility": id, "level": to, "due": due})
	upkeep[y] = paid
	drops[y] = lost
	_prune(y)
	return out


## The facility that loses a level when upkeep goes unpaid: the highest level, then the dearest to run,
## then IDS order.
static func _drop_pick(team: Team) -> StringName:
	var best: StringName = &""
	var best_key := Vector2i(-1, -1)
	for id in IDS:
		var lvl := level(team, id)
		if lvl <= 1:
			continue
		var key := Vector2i(lvl, cost_to(id, lvl))
		if key > best_key:
			best_key = key
			best = id
	return best


# --- AI -------------------------------------------------------------------------------

## AI clubs upgrade once an offseason (at camp, after free agency and the draft): their direction's
## focus first, cheapest next level first, always keeping next year's upkeep plus a bonus reserve.
func ai_spend(season: Season) -> void:
	ensure(season)
	for t: Team in season.league.teams:
		if not t.user_controlled:
			ai_spend_team(season, t)


func ai_spend_team(season: Season, team: Team) -> void:
	var mode: StringName = season.trades.mode(season, team)
	var focus: Array = AI_FOCUS.get(mode, AI_FOCUS[&"balanced"])
	var outside := 0
	while upgrades_left(season, team) > 0:
		var id := _ai_pick(season, team, focus, outside == 0)
		if id == &"" or upgrade(season, team, id) != "":
			return
		if not focus.has(id):
			outside += 1


## Fund `team` keeps back after buying `id`: next year's upkeep with it, plus its bonus reserve.
func ai_reserve(season: Season, team: Team, id: StringName) -> float:
	var mode: StringName = season.trades.mode(season, team)
	var g := season.revenue.grant_of(season.year, team)
	var grant := float(g.get("grant", Revenue.market_grant(team.market_rating)))
	var up := minf(UPKEEP_SHARE * (invested(team) + next_price(team, id)), UPKEEP_GRANT_CAP * maxf(0.0, grant))
	return up + float(AI_BONUS_RESERVE.get(mode, AI_BONUS_RESERVE[&"balanced"]))


func _ai_pick(season: Season, team: Team, focus: Array, allow_outside: bool) -> StringName:
	var best: StringName = &""
	var best_price := 0
	var focus_open := false
	for id in focus:
		if level(team, id) < MAX_LEVEL and not bought_ids(season, team).has(id):
			focus_open = true
		if not _ai_affords(season, team, id):
			continue
		if best == &"" or next_price(team, id) < best_price:
			best = id
			best_price = next_price(team, id)
	if best != &"" or not allow_outside:
		return best
	var cash := season.revenue.cash_of(team)
	for id in IDS:
		if focus.has(id) or not _ai_affords(season, team, id):
			continue
		var spare := cash - ai_reserve(season, team, id)
		if focus_open and spare < AI_SPARE_FACTOR * next_price(team, id):
			continue
		if best == &"" or next_price(team, id) < best_price:
			best = id
			best_price = next_price(team, id)
	return best


func _ai_affords(season: Season, team: Team, id: StringName) -> bool:
	if upgrade_error(season, team, id) != "":
		return false
	return season.revenue.cash_of(team) - next_price(team, id) >= ai_reserve(season, team, id)


# --- Performance Institute ------------------------------------------------------------

## Each offseason, after aging: every rostered player on a club with an Institute above level 1 has a
## chance (higher under INSTITUTE_YOUNG_AGE) to have one group cap raised by 1-2, likeliest the groups
## nearest their cap. Returns [{soldier, team, group, from, to}].
func institute(season: Season, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for t: Team in season.league.teams:
		var chance := institute_chance(t)
		if chance <= 0.0:
			continue
		for so: Soldier in t.roster:
			var p := chance * (INSTITUTE_YOUNG if so.age < INSTITUTE_YOUNG_AGE else INSTITUTE_OLD)
			if rng.randf() >= p:
				continue
			var groups: Array = []
			var weights: Array = []
			var total := 0.0
			for g in Stats.UPGRADABLE_GROUPS:
				if so.group_caps.has(g) and so.group_cap(g) < Stats.MAX_RATING:
					var w := 1.0 + 3.0 / (1.0 + maxf(0.0, float(so.group_headroom(g))))
					groups.append(g)
					weights.append(w)
					total += w
			if groups.is_empty():
				continue
			var roll := rng.randf() * total
			var pick: StringName = groups[-1]
			for i in groups.size():
				roll -= float(weights[i])
				if roll < 0.0:
					pick = groups[i]
					break
			var from := so.group_cap(pick)
			var to := mini(Stats.MAX_RATING, from + rng.randi_range(1, 2))
			var ovr_before := so.best_ovr()
			var pot_before := so.potential_grade()
			so.group_caps[pick] = to
			so.log_cap("Performance Institute: %s cap +%d (%d -> %d)" % [Stats.GROUP_LABELS[pick], to - from, from, to],
				pick, from, to, ovr_before, pot_before)
			out.append({"soldier": so, "team": t, "group": pick, "from": from, "to": to})
	return out
