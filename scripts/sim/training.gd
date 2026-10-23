class_name Training
extends RefCounted
## Weekly training (Madden-style): the whole roster gets base XP, and up to MAX_FOCUS_PLAYERS
## chosen soldiers get boosted XP plus usage in a chosen focus stat (steering their breakthroughs
## and the AI's spending).

const MAX_FOCUS_PLAYERS := 3
const BASE_XP := 120.0
const FOCUS_MULTIPLIER := 2.5
const FOCUS_USAGE := 5.0


## focus: soldier_id -> focus stat (StringName, or &"" for no specific stat).
## Returns soldier_id -> gain_xp report (with an added "focus" bool).
static func run_week(team: Team, focus: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if focus.size() > MAX_FOCUS_PLAYERS:
		push_warning("Only %d focus players allowed; extra ignored." % MAX_FOCUS_PLAYERS)
	var allowed := focus.keys().slice(0, MAX_FOCUS_PLAYERS)
	var reports := {}
	for soldier in team.roster:
		var is_focus := allowed.has(soldier.id)
		var xp := BASE_XP * (FOCUS_MULTIPLIER if is_focus else 1.0)
		if is_focus and focus[soldier.id] != &"":
			soldier.add_usage(focus[soldier.id], FOCUS_USAGE)
		var report := Progression.gain_xp(soldier, xp, rng)
		report["focus"] = is_focus
		reports[soldier.id] = report
	return reports
