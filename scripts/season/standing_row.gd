class_name StandingRow
extends RefCounted
## One line of the division table.

var team: Team
var rank: int
var wins: int
var losses: int
## Games (of the best-of-3 matches) won / lost, and TDM points for / against.
var games_won: int
var games_lost: int
var points_for: int
var points_against: int
var streak: String = "-"
var last5: String = ""


func games() -> int:
	return wins + losses


func win_pct() -> float:
	return float(wins) / games() if games() > 0 else 0.0


func game_diff() -> int:
	return games_won - games_lost


func point_diff() -> int:
	return points_for - points_against
