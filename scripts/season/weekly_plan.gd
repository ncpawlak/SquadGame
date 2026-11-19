class_name WeeklyPlan
extends RefCounted
## Player mode's weekly training plan (#138). Each week the player spends WEEK_POINTS points across five
## activities (at most WEEK_MAX in any one); camp is the same with CAMP_POINTS, CAMP_MAX and no spa. The plan
## carries over until he changes it, and starts blank.
##
## - Practice: XP on top of a film-study baseline (levels 1/2/3 total today's Light/Normal/Heavy XP).
## - Study: points toward the next dev star (cost rises per star, one star a season).
## - Outing: morale for his immediate group (Green Team or main roster), half for the rest of the club.
## - Brand: points when he plays, scaled by the week's grade. Brand decays slowly.
## - Spa: extra fatigue recovery and morale.
## Every point in the first four adds fatigue; spa is the only recovery. Unspent points are wasted.
## All the maths is here; Soldier holds the state (plan, study_progress, brand).

const PRACTICE := &"practice"
const STUDY := &"study"
const OUTING := &"outing"
const BRAND := &"brand"
const SPA := &"spa"

const WEEK_ACTIVITIES: Array[StringName] = [PRACTICE, STUDY, OUTING, BRAND, SPA]
const CAMP_ACTIVITIES: Array[StringName] = [PRACTICE, STUDY, OUTING, BRAND, SPA]
const LABELS := {PRACTICE: "Practice", STUDY: "Study Session", OUTING: "Team Outing", BRAND: "Brand Exposure", SPA: "Spa"}

const WEEK_POINTS := 4
const WEEK_MAX := 3
const CAMP_POINTS := 8
const CAMP_MAX := 4

# Per-level tables (index = level). Weekly uses levels 0-3, camp 0-4.
const FATIGUE_LOAD := [0.0, 3.0, 6.0, 11.0]
const BASELINE_XP := 37.5
const PRACTICE_XP := [0.0, 52.5, 112.5, 202.5]
const STUDY_POINTS := [0.0, 1.0, 2.2, 3.6]
const OUTING_MORALE := [0.0, 2.0, 4.0, 6.0]
const SPA_RECOVERY := [0.0, 0.12, 0.25, 0.40]
const SPA_MORALE := [0.0, 2.0, 4.0, 6.0]
const BRAND_BASE := [0.0, 2.0, 4.5, 8.0]
const CAMP_PRACTICE_XP := [0.0, 80.0, 180.0, 320.0, 520.0]
const CAMP_STUDY_POINTS := [0.0, 2.0, 4.5, 7.5, 11.0]
const CAMP_OUTING_MORALE := [0.0, 2.0, 4.0, 6.0, 8.0]
const CAMP_BRAND_BASE := [0.0, 3.0, 6.5, 11.0, 16.0]
## Share of the outing morale the rest of the club (the group he is not in) gets.
const OUTING_CLUB_SHARE := 0.5

## Dev star costs in study points: the cost to leave star `dev`. Visible to the player.
const STAR_COST := {1: 25.0, 2: 35.0, 3: 55.0}
## Career-mode tuning knobs (the league never reads them): the live star costs, and how much faster the player earns
## XP than the shared age-and-star table says. The tuning tool overrides both.
static var star_costs: Dictionary = STAR_COST.duplicate()
static var xp_boost := 2.5

## Brand earned by playing well whatever the plan: a base per played game, scaled by the grade (x0.5 .. x2).
const BRAND_PASSIVE := 1.0
## One-time brand for a season honor (also scaled down near the top, like every gain).
const HONOR_BRAND := {"Season MVP": 18.0, "Rookie of the Year": 10.0, "Best role": 10.0, "All-League": 8.0, "Champion": 6.0, "Player of the Week": 3.0}
const BRAND_MAX := 100.0
const BRAND_DECAY := 0.98
const BRAND_TIER_SIZE := 20.0
const BRAND_TIERS := ["Unknown", "Rising", "Known", "Star", "Icon"]
## Gains shrink as brand nears the top: x (1 - brand / (BRAND_MAX * BRAND_SOFT)).
const BRAND_SOFT := 1.15
## Brand's pull on market value at 100 brand (so on the re-sign price).
const BRAND_VALUE_MAX := 0.35
## Grade score range mapped to the brand multiplier 0.5 .. 2.0.
const GRADE_LOW := 60.0
const GRADE_HIGH := 97.0
const FACTOR_LOW := 0.5
const FACTOR_HIGH := 2.0


# --- plan basics --------------------------------------------------------------------------------

static func level(plan: Dictionary, activity: StringName) -> int:
	return int(plan.get(activity, 0))


static func activities(camp: bool) -> Array[StringName]:
	return CAMP_ACTIVITIES if camp else WEEK_ACTIVITIES


static func total(plan: Dictionary) -> int:
	var n := 0
	for a in WEEK_ACTIVITIES:
		n += level(plan, a)
	return n


static func points(camp: bool) -> int:
	return CAMP_POINTS if camp else WEEK_POINTS


static func max_level(camp: bool) -> int:
	return CAMP_MAX if camp else WEEK_MAX


static func unspent(plan: Dictionary, camp := false) -> int:
	return points(camp) - total(plan)


## "" if the plan is allowed, else why not.
static func error(plan: Dictionary, camp := false) -> String:
	var allowed := activities(camp)
	for k in plan:
		if not allowed.has(k):
			return "%s is not available%s." % [LABELS.get(k, str(k)), " in camp" if camp else ""]
		if level(plan, k) < 0 or level(plan, k) > max_level(camp):
			return "%s can take 0 to %d points." % [LABELS[k], max_level(camp)]
	if total(plan) > points(camp):
		return "That is %d points; you have %d." % [total(plan), points(camp)]
	return ""


## Practice level -> the intensity the rest of the game knows (0 is Rest: no training injury exposure).
static func intensity_for(practice_level: int) -> StringName:
	match practice_level:
		0: return Soldier.INTENSITY_REST
		1: return Soldier.INTENSITY_LIGHT
		2: return Soldier.INTENSITY_NORMAL
	return Soldier.INTENSITY_HEAVY


## Fatigue the week's plan adds (before Endurance and age scaling): every point except spa.
static func fatigue_load(plan: Dictionary) -> float:
	var load := 0.0
	for a in [PRACTICE, STUDY, OUTING, BRAND]:
		load += FATIGUE_LOAD[clampi(level(plan, a), 0, WEEK_MAX)]
	return load


static func recovery_bonus(plan: Dictionary) -> float:
	return SPA_RECOVERY[clampi(level(plan, SPA), 0, WEEK_MAX)]


## Base XP (before the star and age multiplier) for a normal training week.
static func week_xp(plan: Dictionary) -> float:
	return BASELINE_XP + PRACTICE_XP[clampi(level(plan, PRACTICE), 0, WEEK_MAX)]


# --- stars --------------------------------------------------------------------------------------

## Study points needed to leave star `dev` (0 at the top).
static func star_cost(dev: int, s: Soldier = null) -> float:
	return float(star_costs.get(dev, 0.0)) * Backstory.cost_mult(s)


## Adds study points. Returns true if a star was earned. One star a season: a full bar waits for the next one.
static func add_study(s: Soldier, pts: float, year: int) -> bool:
	if pts <= 0.0 or s.dev >= Soldier.DEV_MAX:
		return false
	s.study_progress += pts
	var cost := star_cost(s.dev, s)
	if s.study_progress < cost:
		return false
	if s.dev_changed_in(year):
		s.study_progress = cost
		return false
	s.study_progress -= cost
	var from := s.dev
	s.change_dev(1, year)
	s.log_progress("Study session", {}, s.best_ovr(), from, s.dev)
	if s.dev >= Soldier.DEV_MAX:
		s.study_progress = 0.0
	return true


# --- brand --------------------------------------------------------------------------------------

static func grade_factor(score: float) -> float:
	return lerpf(FACTOR_LOW, FACTOR_HIGH, clampf((score - GRADE_LOW) / (GRADE_HIGH - GRADE_LOW), 0.0, 1.0))


static func brand_gain(lvl: int, score: float, brand: float, camp := false) -> float:
	var table: Array = CAMP_BRAND_BASE if camp else BRAND_BASE
	var base: float = table[clampi(lvl, 0, table.size() - 1)]
	return base * grade_factor(score) * maxf(0.0, 1.0 - brand / (BRAND_MAX * BRAND_SOFT))


static func tier_name(brand: float) -> String:
	return BRAND_TIERS[mini(int(brand / BRAND_TIER_SIZE), BRAND_TIERS.size() - 1)]


## Market value multiplier from brand.
static func market_mult(brand: float) -> float:
	return 1.0 + BRAND_VALUE_MAX * clampf(brand / BRAND_MAX, 0.0, 1.0)


# --- applying a week --------------------------------------------------------------------------

## The player's club group he trains with: Green Team or main roster.
static func group_of(team: Team, s: Soldier) -> Array:
	return team.green_team if team.green_team.has(s) else team.roster


static func apply_outing(team: Team, s: Soldier, amount: float) -> void:
	if amount <= 0.0:
		return
	var group := group_of(team, s)
	for x in team.org():
		x.add_morale(amount if group.has(x) else amount * OUTING_CLUB_SHARE)


## Run once as the week is prepared (before training XP): brand decay, intensity, study, spa and outing.
static func apply_week(season: Season) -> void:
	var s := season.player
	if s == null or PlayerLegacy.retired(season):
		return
	var team := season.user_team()
	if team == null or not team.org().has(s):
		return
	var plan := s.plan
	s.brand *= BRAND_DECAY
	s.intensity = intensity_for(level(plan, PRACTICE))
	if add_study(s, STUDY_POINTS[clampi(level(plan, STUDY), 0, WEEK_MAX)], season.year):
		_note(season, "Your study paid off: you are now a %s." % s.dev_text())
	s.add_morale(SPA_MORALE[clampi(level(plan, SPA), 0, WEEK_MAX)])
	Wear.record_week(s, level(plan, SPA))
	apply_outing(team, s, OUTING_MORALE[clampi(level(plan, OUTING), 0, WEEK_MAX)])


## Brand for a played match (called when the grade is recorded). Returns the points gained.
static func apply_brand(season: Season, score: float) -> float:
	var s := season.player
	var gain := brand_gain(level(s.plan, BRAND), score, s.brand) + _soft(s.brand, BRAND_PASSIVE * grade_factor(score))
	var tier_before := Gear.tier_for_brand(s.brand)
	s.brand = minf(BRAND_MAX, s.brand + gain)
	if Gear.tier_for_brand(s.brand) > tier_before:
		Sponsors.refresh(season)  # a brand tier-up gets the sponsors talking
	return gain


static func _soft(brand: float, amount: float) -> float:
	return amount * maxf(0.0, 1.0 - brand / (BRAND_MAX * BRAND_SOFT))


## Season honors turn into brand: the season's awards, All-League, a title and each Player of the Week.
## Call once per season after the review. Returns the brand gained.
static func apply_honors(season: Season) -> float:
	var s := season.player
	var rev := season.review
	if s == null or rev == null or not season.player_mode:
		return 0.0
	var tier_before := Gear.tier_for_brand(s.brand)
	var total := 0.0
	var names: PackedStringArray = []
	for a in rev.award_for(s):
		var key: String = "Best role" if String(a).begins_with("Best ") else String(a)
		if HONOR_BRAND.has(key):
			var g := _soft(s.brand + total, float(HONOR_BRAND[key]))
			total += g
			names.append(String(a))
	var team := season.user_team()
	if team != null and season.champion == team:
		total += _soft(s.brand + total, float(HONOR_BRAND["Champion"]))
		names.append("Champion")
	var potw := SeasonReview.potw_count(season, s, season.regular_weeks)
	if potw > 0:
		total += _soft(s.brand + total, float(HONOR_BRAND["Player of the Week"]) * potw)
		names.append("Player of the Week x%d" % potw)
	if total > 0.0:
		s.brand = minf(BRAND_MAX, s.brand + total)
		_note(season, "Your honors (%s) lifted your brand by %d." % [", ".join(names), roundi(total)])
		if Gear.tier_for_brand(s.brand) > tier_before:
			Sponsors.refresh(season)
	return total


## The camp plan, applied once when camp runs. Outing morale waits for the season rollover (see apply_camp_outing).
static func apply_camp(season: Season) -> Dictionary:
	var s := season.player
	var rep := {"xp": 0, "study": 0.0, "star": false, "brand": 0.0, "outing": 0}
	if s == null or PlayerLegacy.retired(season):
		return rep
	var team := season.user_team()
	var plan := s.camp_plan
	var p := clampi(level(plan, PRACTICE), 0, CAMP_MAX)
	if p > 0:
		var report := Progression.gain_xp(s, CAMP_PRACTICE_XP[p] * Facilities.training_mult(team))
		rep["xp"] = report["xp"]
	var st := clampi(level(plan, STUDY), 0, CAMP_MAX)
	rep["study"] = CAMP_STUDY_POINTS[st]
	if add_study(s, CAMP_STUDY_POINTS[st], season.year):
		rep["star"] = true
		_note(season, "Your study paid off: you are now a %s." % s.dev_text())
	var b := clampi(level(plan, BRAND), 0, CAMP_MAX)
	if b > 0:
		var sm := PlayerGrade.summary(PlayerGrade.log_for(season, season.year))
		if int(sm["games"]) > 0:
			rep["brand"] = brand_gain(b, float(sm["avg"]), s.brand, true)
			s.brand = minf(BRAND_MAX, s.brand + float(rep["brand"]))
	s.wear_rehab = clampi(level(plan, SPA), 0, CAMP_MAX)  # camp rehab: each point takes Wear off at the next aging
	season.camp_outing_level = clampi(level(plan, OUTING), 0, CAMP_MAX)
	rep["outing"] = season.camp_outing_level
	return rep


## At the season rollover, after morale has been pulled toward neutral.
static func apply_camp_outing(season: Season) -> void:
	var lvl := season.camp_outing_level
	season.camp_outing_level = 0
	if lvl <= 0 or season.player == null:
		return
	var team := season.user_team()
	if team != null and team.org().has(season.player):
		apply_outing(team, season.player, CAMP_OUTING_MORALE[lvl])


static func _note(season: Season, text: String) -> void:
	season.player_notes.append({"year": season.year, "week": season.week, "text": text})


## What a plan would do to fatigue this week: {now, after, band, played, bye}. For the plan screen's meter.
static func projection(season: Season, plan: Dictionary) -> Dictionary:
	var s := season.player
	var team := season.user_team()
	var saved := s.plan
	s.plan = plan
	var bye := season.phase != Season.PHASE_OFFSEASON and season.is_bye(team, season.week)
	var starting: bool = PlayerCoach.status(season)["where"] == PlayerCoach.WHERE_STARTER
	var played := starting and not bye and season.phase != Season.PHASE_OFFSEASON
	var after := Conditioning.projected_fatigue(s, &"", played, bye)
	s.plan = saved
	return {"now": s.fatigue, "after": after, "band": Conditioning.status(after), "played": played, "bye": bye}
