class_name Conditioning
extends RefCounted
## Fatigue and injuries, updated once per week after the matches.
##
## Fatigue (0-100): new = old * (1 - recovery) + load
## - load = training intensity load + MATCH_LOAD if the soldier started a match, scaled down
##   by Endurance and up by age (past AGE_START).
## - recovery = RECOVERY_RATE (+ rest bonus, + bye-week bonus), lower for older soldiers.
## So fatigue settles at load / recovery: ~50s for a normal-training starter, ~70 on heavy.
## Effect in matches: almost nil below 50, mild 50-75, steep above 75 (see penalty()).
##
## Injuries: each active soldier rolls once per week.
## - chance = base from the Injury rating (99 = rare, 70 = much likelier) x fatigue multiplier
##   (1x at 40 fatigue, ~3x at 90); bench players who only trained roll at a reduced rate.
## - Toughness decides how long they're out.

const MATCH_LOAD := 14.0
const RECOVERY_RATE := 0.35
const BYE_RECOVERY_BONUS := 0.15
const AGE_START := 28
const AGE_LOAD_PER_YEAR := 0.03
const AGE_RECOVERY_PER_YEAR := 0.03

const INJURY_BASE_AT_99 := 0.004
const INJURY_BASE_AT_70 := 0.02
const TRAINING_ONLY_INJURY_MULT := 0.4

const INJURY_NAMES := {
	1: ["Sprained ankle", "Bruised ribs", "Hamstring tightness", "Jammed finger"],
	2: ["Pulled groin", "Shoulder strain", "Concussion", "Hamstring strain"],
	4: ["Torn ligament", "Fractured wrist", "Broken collarbone", "Dislocated shoulder"],
}


## Match performance loss (0-0.18) applied to accuracy, speed and reaction stats.
static func penalty(fatigue: float) -> float:
	if fatigue <= 50.0:
		return fatigue / 50.0 * 0.01
	if fatigue <= 75.0:
		return 0.01 + (fatigue - 50.0) / 25.0 * 0.04
	return 0.05 + (minf(fatigue, 100.0) - 75.0) / 25.0 * 0.13


static func status(fatigue: float) -> String:
	if fatigue < 25.0:
		return "Fresh"
	if fatigue < 50.0:
		return "Good"
	if fatigue < 75.0:
		return "Tired"
	return "Exhausted"


static func endurance_mult(soldier: Soldier) -> float:
	return 1.3 - float(soldier.stats[Stats.ENDURANCE]) / 100.0 * 0.6


static func age_years(soldier: Soldier) -> int:
	return maxi(0, soldier.age - AGE_START)


static func weekly_load(soldier: Soldier, played_match: bool) -> float:
	var load := float(Training.INTENSITY_INFO[soldier.intensity]["load"])
	if played_match:
		load += MATCH_LOAD
	return load * endurance_mult(soldier) * (1.0 + age_years(soldier) * AGE_LOAD_PER_YEAR)


static func weekly_recovery(soldier: Soldier, bye: bool) -> float:
	var r := RECOVERY_RATE + float(Training.INTENSITY_INFO[soldier.intensity]["recovery_bonus"])
	if bye:
		r += BYE_RECOVERY_BONUS
	return clampf(r * (1.0 - age_years(soldier) * AGE_RECOVERY_PER_YEAR), 0.05, 0.95)


## Weekly injury chance before the fatigue multiplier.
static func base_injury_chance(injury_rating: int) -> float:
	var t := clampf((99.0 - injury_rating) / 29.0, 0.0, 2.0)
	return INJURY_BASE_AT_99 + t * (INJURY_BASE_AT_70 - INJURY_BASE_AT_99)


static func fatigue_injury_mult(fatigue: float) -> float:
	return 1.0 + maxf(0.0, fatigue - 40.0) / 25.0


static func injury_chance(soldier: Soldier, played_match: bool) -> float:
	var c := base_injury_chance(soldier.stats[Stats.INJURY]) * fatigue_injury_mult(soldier.fatigue)
	if not played_match:
		c *= TRAINING_ONLY_INJURY_MULT
	return c


## Weeks out, from Toughness: tough soldiers shake off knocks, soft ones miss longer.
static func roll_injury_weeks(toughness: int, rng: RandomNumberGenerator) -> int:
	var max_extra := 2.0 + (100.0 - toughness) / 10.0
	var severity := rng.randf()
	return 1 + int(floor(severity * severity * max_extra))


static func injury_label(weeks: int, rng: RandomNumberGenerator) -> String:
	var key := 1 if weeks <= 1 else (2 if weeks <= 3 else 4)
	var names: Array = INJURY_NAMES[key]
	return names[rng.randi_range(0, names.size() - 1)]


## End-of-week update for one team. played_ids: soldier ids who started a match this week.
## Returns new injuries as Array of {soldier, weeks, name}.
static func end_week(team: Team, played_ids: Dictionary, bye: bool, rng: RandomNumberGenerator) -> Array:
	var injuries: Array = []
	for soldier in team.roster:
		if soldier.is_injured():
			soldier.injury_weeks -= 1
			if soldier.injury_weeks <= 0:
				soldier.injury_name = ""
			soldier.fatigue *= 0.4
			continue
		var played := played_ids.has(soldier.id)
		soldier.fatigue = clampf(soldier.fatigue * (1.0 - weekly_recovery(soldier, bye)) + weekly_load(soldier, played), 0.0, 100.0)
		var active := played or soldier.intensity != Soldier.INTENSITY_REST
		if active and rng.randf() < injury_chance(soldier, played):
			soldier.injury_weeks = roll_injury_weeks(soldier.stats[Stats.TOUGHNESS], rng)
			soldier.injury_name = injury_label(soldier.injury_weeks, rng)
			injuries.append({"soldier": soldier, "weeks": soldier.injury_weeks, "name": soldier.injury_name})
	return injuries


## Clears fatigue and injuries (between seasons).
static func reset(team: Team) -> void:
	for soldier in team.roster:
		soldier.fatigue = 0.0
		soldier.injury_weeks = 0
		soldier.injury_name = ""
