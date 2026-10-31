class_name SeasonSnapshot
extends RefCounted
## One finished season, frozen when the champion is crowned: who won, the final table and the
## playoff bracket. `Season.champion` and `playoff_matches` reset every year; this is what is kept.

var year: int
var champion: Team = null
var runner_up: Team = null
## Final regular-season table in order: Array of {team, wins, losses, game_diff, point_diff, seed}.
## `seed` is the playoff seed (0 = missed the playoffs).
var standings: Array = []
## Every playoff match in play order: Array of {round: String, home, away, home_games, away_games, winner}.
var bracket: Array = []


static func capture(season: Season) -> SeasonSnapshot:
	var snap := SeasonSnapshot.new()
	snap.year = season.year
	snap.champion = season.champion
	for r: StandingRow in season.standings():
		snap.standings.append({
			"team": r.team, "wins": r.wins, "losses": r.losses,
			"game_diff": r.game_diff(), "point_diff": r.point_diff(),
			"seed": int(season.playoff_seeds.get(r.team, 0)),
		})
	for m: ScheduledMatch in season.playoff_matches:
		if not m.is_played():
			continue
		snap.bracket.append({
			"round": season.week_label(m.week), "home": m.home, "away": m.away,
			"home_games": m.games_for(m.home), "away_games": m.games_for(m.away), "winner": m.winner(),
		})
		if m.stage == Season.STAGE_FINAL:
			snap.runner_up = m.loser()
	return snap


## The champion's regular-season line, e.g. "7-1" ("" if the table is empty).
func champion_record() -> String:
	for row in standings:
		if row["team"] == champion:
			return "%d-%d" % [row["wins"], row["losses"]]
	return ""


## The final's score from the champion's side, e.g. "2-1" ("" if there was no final).
func final_score() -> String:
	if bracket.is_empty():
		return ""
	var f: Dictionary = bracket[-1]
	var champ_home: bool = f["home"] == champion
	return "%d-%d" % [f["home_games"] if champ_home else f["away_games"], f["away_games"] if champ_home else f["home_games"]]
