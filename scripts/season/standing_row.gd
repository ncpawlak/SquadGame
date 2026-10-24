class_name StandingRow
extends RefCounted
## One line of the division table.

var team: Team
var rank: int
var wins: int
var losses: int
var rounds_won: int
var rounds_lost: int
var streak: String = "-"
var last5: String = ""


func games() -> int:
	return wins + losses


func win_pct() -> float:
	return float(wins) / games() if games() > 0 else 0.0


func round_diff() -> int:
	return rounds_won - rounds_lost
