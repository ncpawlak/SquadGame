class_name MatchResult
extends RefCounted
## Output of MatchEngine.simulate(): games won, per-game and per-round summaries, play-by-play and
## box scores. A match is best of 3 games (see MatchEngine).

var match_seed: int
var teams: Array[Team] = []
## Games won by each side.
var score: Array[int] = [0, 0]
var winner_index: int = -1
## Each: { number, mode, score: [int, int], winner, duration_s, rounds: [round dicts] }. Score is
## TDM points, KOTH hold seconds or sudden-death rounds.
var games: Array[Dictionary] = []
## Sudden-death rounds only. Each: { number, mode, winner, duration_s, survivors: [int, int], clutch_soldier_id }
var rounds: Array[Dictionary] = []
var events: Array[String] = []
## soldier_id -> { team, slot, kills, deaths, assists, shots, hits, headshots, damage,
##                 rounds_played, rounds_survived, clutches, saves, games, wipes, hill_s, caps, contest_s }
var box: Dictionary = {}
var mvp_id: int = -1


func winner() -> Team:
	return teams[winner_index] if winner_index >= 0 else null


func loser() -> Team:
	return teams[1 - winner_index] if winner_index >= 0 else null


func score_line() -> String:
	return "%s %d - %d %s" % [teams[0].abbrev, score[0], score[1], teams[1].abbrev]


func box_for(soldier: Soldier) -> Dictionary:
	return box.get(soldier.id, {})


func game_of(mode: StringName) -> Dictionary:
	for g in games:
		if g["mode"] == mode:
			return g
	return {}


## TDM points scored by each side (0 if somehow absent).
func tdm_points() -> Array[int]:
	var g := game_of(MatchEngine.MODE_TDM)
	if g.is_empty():
		return [0, 0]
	return [int(g["score"][0]), int(g["score"][1])]


## "50-38", "2:00-1:12", "4-2" for one game.
static func game_score_text(game: Dictionary) -> String:
	var s: Array = game["score"]
	if game["mode"] == MatchEngine.MODE_KOTH:
		return "%s-%s" % [MatchEngine._fmt_secs(s[0]), MatchEngine._fmt_secs(s[1])]
	return "%d-%d" % [s[0], s[1]]


## Simple performance score used for MVP and XP.
static func impact(line: Dictionary) -> float:
	return line["kills"] * 100.0 + line["assists"] * 40.0 + line["damage"] * 0.5 \
		+ line["rounds_survived"] * 20.0 + line["clutches"] * 100.0 - line["deaths"] * 20.0 \
		+ line.get("saves", 0) * 50.0 + line.get("wipes", 0) * 30.0 + line.get("caps", 0) * 40.0 \
		+ line.get("hill_s", 0.0) * 1.5
