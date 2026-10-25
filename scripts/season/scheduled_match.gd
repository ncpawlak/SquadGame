class_name ScheduledMatch
extends RefCounted
## One fixture on the season calendar. Simulated with `home` as team_a (index 0).

var week: int
var stage: StringName = &"regular"
var home: Team
var away: Team
var match_seed: int
var result: MatchResult = null
## Set when a result was produced outside `sim_week` (e.g. a watched match) and XP is still owed.
var needs_xp := false


func is_played() -> bool:
	return result != null


func winner() -> Team:
	return result.winner() if result else null


func loser() -> Team:
	return result.loser() if result else null


func involves(team: Team) -> bool:
	return team == home or team == away


func opponent_of(team: Team) -> Team:
	if team == home:
		return away
	if team == away:
		return home
	return null


## Games won from the home side's perspective, e.g. "2-1"; "" if unplayed.
func score_text() -> String:
	if result == null:
		return ""
	return "%d-%d" % [result.score[0], result.score[1]]


## Games won by `team` in this match (0 if unplayed or not involved).
func games_for(team: Team) -> int:
	if result == null:
		return 0
	if team == home:
		return result.score[0]
	if team == away:
		return result.score[1]
	return 0


## TDM points scored by `team` in game 1 (0 if unplayed or not involved).
func points_for(team: Team) -> int:
	if result == null or not involves(team):
		return 0
	return result.tdm_points()[0 if team == home else 1]


func play() -> MatchResult:
	result = MatchEngine.simulate(home, away, match_seed)
	return result


## A steppable engine for this fixture, for the live viewer. Assign its result via `set_live_result`.
func live_engine() -> MatchEngine:
	var e := MatchEngine.new()
	e.start(home, away, match_seed)
	return e


func set_live_result(r: MatchResult) -> void:
	result = r
	needs_xp = true
