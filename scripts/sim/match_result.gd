class_name MatchResult
extends RefCounted
## Output of MatchEngine.simulate(): score, per-round summaries, play-by-play and box scores.

var match_seed: int
var teams: Array[Team] = []
var score: Array[int] = [0, 0]
var winner_index: int = -1
## Each: { number, mode, winner, duration_s, survivors: [int, int], clutch_soldier_id }
var rounds: Array[Dictionary] = []
var events: Array[String] = []
## soldier_id -> { team, slot, kills, deaths, assists, shots, hits, headshots, damage,
##                 rounds_played, rounds_survived, clutches, saves }
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


## Simple performance score used for MVP and XP.
static func impact(line: Dictionary) -> float:
	return line["kills"] * 100.0 + line["assists"] * 40.0 + line["damage"] * 0.5 \
		+ line["rounds_survived"] * 20.0 + line["clutches"] * 100.0 - line["deaths"] * 20.0 \
		+ line.get("saves", 0) * 50.0
