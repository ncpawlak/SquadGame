class_name Wear
extends RefCounted
## Career-mode regression (#141). The player carries one Wear meter (0-100) that never resets: each season adds an age
## term plus the season's load (fatigue, games, major injuries) and loses what rest, spa, camp rehab and the Sports
## Science Lab take off. At the offseason every stat group rolls on its own: the higher the player's Wear (scaled by the
## group's weight) the likelier and larger the loss. A loss lowers the rating only, never the cap, so skill points can win it
## back. AI soldiers keep the old yearly decline in Aging.

const FRESH := 0
const WORN := 1
const BEATEN := 2
const BROKEN := 3
const TIER_NAMES := ["Fresh", "Worn", "Beaten up", "Broken"]
## Effective Wear where each tier starts (index = tier).
const TIER_START := [0.0, 35.0, 60.0, 80.0]
const TIER_CHANCE := [0.0, 0.25, 0.5, 0.8]
const TIER_LOSS_MIN := [0, 1, 1, 2]
const TIER_LOSS_MAX := [0, 2, 3, 5]
## A group's share of the player's Wear (the old peak ages as weights: physical wears first, mental last).
const GROUP_WEIGHT := {
	Stats.PHYSICALITY: 1.0, Stats.DURABILITY: 0.9, Stats.ACCURACY: 0.7,
	Stats.HANDLING: 0.6, Stats.OBJECTIVE: 0.6, Stats.MENTALITY: 0.4,
}
const WEAR_MAX := 100.0
const MAJOR_INJURY_WEEKS := 4

## Tuning knobs (career mode only; the tuning tool overrides them).
static var age_start := 24
static var age_gain := 4.0
static var fatigue_gain := 0.08
static var games_gain := 0.05
static var injury_gain := 5.0
static var passive := 1.0
static var spa_per_level := 3.0
static var rehab_per_point := 1.0
static var lab_per_step := 1.0


static func tier_of(effective: float) -> int:
	var t := FRESH
	for i in TIER_START.size():
		if effective >= float(TIER_START[i]):
			t = i
	return t


static func tier_name(wear: float) -> String:
	return TIER_NAMES[tier_of(wear)]


## Effective Wear for a group.
static func group_wear(wear: float, group: StringName) -> float:
	return wear * float(GROUP_WEIGHT.get(group, 1.0))


## Records one week of the season for the meter (fatigue and the spa level of that week's plan).
static func record_week(s: Soldier, spa_level: int) -> void:
	s.wear_fatigue_sum += s.fatigue
	s.wear_spa_sum += float(spa_level)
	s.wear_weeks += 1


## One more graded match played / one major injury picked up this season.
static func record_game(s: Soldier) -> void:
	s.wear_games += 1


static func record_injury(s: Soldier, weeks: int) -> void:
	if weeks >= MAJOR_INJURY_WEEKS:
		s.wear_injuries += 1


## The season's net change (before it is added): age and load minus reducers. `lab_steps`: Sports Science Lab level steps.
static func season_change(s: Soldier, lab_steps: int) -> float:
	var weeks := maxf(1.0, float(s.wear_weeks))
	var gain := 0.0
	if s.age >= age_start:
		gain += age_gain
	gain += fatigue_gain * s.wear_fatigue_sum / weeks
	gain += games_gain * float(s.wear_games)
	gain += injury_gain * float(s.wear_injuries)
	var relief := passive
	relief += spa_per_level * s.wear_spa_sum / weeks
	relief += rehab_per_point * float(s.wear_rehab)
	relief += lab_per_step * float(lab_steps)
	return gain - relief


## Closes the season's books: updates the meter and clears the season counters.
static func close_season(s: Soldier, lab_steps: int) -> void:
	s.wear = clampf(s.wear + season_change(s, lab_steps), 0.0, WEAR_MAX)
	s.wear_fatigue_sum = 0.0
	s.wear_spa_sum = 0.0
	s.wear_weeks = 0
	s.wear_games = 0
	s.wear_injuries = 0
	s.wear_rehab = 0


## Rolls each group's regression. Lowers ratings, leaves the caps alone. Returns {group: rating change (<= 0)}.
static func regress(s: Soldier, rng: RandomNumberGenerator, stat_changes: Dictionary = {}) -> Dictionary:
	var changes := {}
	for g in Stats.GROUP_ORDER:
		var tier := tier_of(group_wear(s.wear, g))
		if tier == FRESH or rng.randf() >= float(TIER_CHANCE[tier]):
			continue
		var before := s.group_rating(g)
		for st in Stats.group_stats(g):
			var loss := rng.randi_range(int(TIER_LOSS_MIN[tier]), int(TIER_LOSS_MAX[tier]))
			var old: int = s.stats[st]
			s.stats[st] = Stats.clamp_rating(old - loss)
			stat_changes[st] = int(s.stats[st]) - old
		var delta := s.group_rating(g) - before
		if delta != 0:
			changes[g] = delta
	return changes


## The yearly aging step for a player: age up, close the books, roll the regression.
static func age_player(s: Soldier, lab_steps: int, rng: RandomNumberGenerator) -> Dictionary:
	s.age += 1
	var ovr_before := s.best_ovr()
	close_season(s, lab_steps)
	var stat_changes := {}
	var changes := regress(s, rng, stat_changes)
	s.log_progress("Wear (%s, turned %d)" % [tier_name(s.wear), s.age], stat_changes, ovr_before)
	return {"soldier": s, "age": s.age, "changes": changes}


## Risk line for one group: "Fresh" / "Worn: 25% to lose 1-2 per stat".
static func risk_text(wear: float, group: StringName) -> String:
	var tier := tier_of(group_wear(wear, group))
	if tier == FRESH:
		return "Fresh"
	return "%s: %d%% to lose %d-%d per stat" % [TIER_NAMES[tier], roundi(float(TIER_CHANCE[tier]) * 100.0), TIER_LOSS_MIN[tier], TIER_LOSS_MAX[tier]]
