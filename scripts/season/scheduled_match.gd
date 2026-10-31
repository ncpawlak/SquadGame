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
## League records this match broke (see StatLedger.record_match): [{stat, label, noun, fmt, phase, value, id,
## name, team, previous}]. `id` is the soldier's id, or -1 for a team streak.
var records: Array = []


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


## The home team's field: every match is played there.
func field() -> ArenaMap:
	return ArenaMap.for_team(home.abbrev)


## The weather this match is played in, rolled from the seed and the home climate. Not stored (saves keep
## only the condition on the result), so every call returns a fresh copy.
func weather() -> Weather:
	return Weather.roll(match_seed, home.abbrev)


## Weather to show for this fixture: its own while it is still ahead, what was played once it is done.
func shown_weather() -> Weather:
	if result != null:
		var w := Weather.new()
		w.kind = result.weather_kind
		w.level = result.weather_level
		return w
	return weather()


func play() -> MatchResult:
	result = MatchEngine.simulate(home, away, match_seed, field(), weather(), Market.crowd_edge(home))
	return result


## A steppable engine for this fixture, for the live viewer. Assign its result via `set_live_result`.
func live_engine() -> MatchEngine:
	var e := MatchEngine.new()
	e.start(home, away, match_seed, field(), weather(), Market.crowd_edge(home))
	return e


func set_live_result(r: MatchResult) -> void:
	result = r
	needs_xp = true
