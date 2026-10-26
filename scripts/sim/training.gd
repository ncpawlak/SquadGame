class_name Training
extends RefCounted
## Weekly training. Every soldier trains at their own intensity (Soldier.intensity):
## harder training earns more XP but builds more fatigue (see Conditioning).
## Resting and injured soldiers still earn a little XP from film study (FILM_STUDY_XP).

const BASE_XP := 150.0
## Share of BASE_XP earned by resting or injured soldiers (film study).
const FILM_STUDY_XP := 0.25

const INTENSITIES: Array[StringName] = [
	Soldier.INTENSITY_REST, Soldier.INTENSITY_LIGHT, Soldier.INTENSITY_NORMAL, Soldier.INTENSITY_HEAVY,
]

## xp: XP multiplier. load: fatigue added (before Endurance/age scaling).
## recovery_bonus: extra share of fatigue shed that week.
const INTENSITY_INFO := {
	Soldier.INTENSITY_REST: {"label": "Rest", "xp": FILM_STUDY_XP, "load": 0.0, "recovery_bonus": 0.25},
	Soldier.INTENSITY_LIGHT: {"label": "Light", "xp": 0.6, "load": 3.0, "recovery_bonus": 0.0},
	Soldier.INTENSITY_NORMAL: {"label": "Normal", "xp": 1.0, "load": 6.0, "recovery_bonus": 0.0},
	Soldier.INTENSITY_HEAVY: {"label": "Heavy", "xp": 1.6, "load": 11.0, "recovery_bonus": 0.0},
}


static func label(intensity: StringName) -> String:
	if not INTENSITY_INFO.has(intensity):
		return "Film Study"
	return INTENSITY_INFO[intensity]["label"]


static func xp_for(intensity: StringName) -> float:
	return BASE_XP * float(INTENSITY_INFO[intensity]["xp"])


## Returns soldier_id -> gain_xp report (with an added "intensity").
static func run_week(team: Team) -> Dictionary:
	var reports := {}
	for soldier in team.roster:
		if soldier.is_injured():
			var film := Progression.gain_xp(soldier, BASE_XP * FILM_STUDY_XP)
			film["intensity"] = &"film"
			reports[soldier.id] = film
			continue
		var report := Progression.gain_xp(soldier, xp_for(soldier.intensity))
		report["intensity"] = soldier.intensity
		reports[soldier.id] = report
	return reports


## AI intensity: rest the exhausted, ease veterans, push fresh young players.
static func ai_intensity(soldier: Soldier, starter: bool) -> StringName:
	var f := soldier.fatigue
	if f >= 70.0:
		return Soldier.INTENSITY_REST
	if f >= 55.0 or (soldier.age >= 31 and f >= 40.0):
		return Soldier.INTENSITY_LIGHT
	if f < 35.0 and (soldier.age <= 26 or not starter):
		return Soldier.INTENSITY_HEAVY
	return Soldier.INTENSITY_NORMAL


static func ai_set_intensities(team: Team) -> void:
	var starters := team.starters()
	for soldier in team.roster:
		soldier.intensity = ai_intensity(soldier, starters.has(soldier))
