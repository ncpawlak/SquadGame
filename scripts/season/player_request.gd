class_name PlayerRequest
extends RefCounted
## Career mode (#141): the player can ask the club for a trade. He needs a real reason, picks a destination from the
## clubs that would take him, and the club answers: granted (he moves, the contract goes with him) or refused (a small
## morale hit and a few weeks before he can ask again). Only while the trade window is open, and one move a season.
##
## Reasons (any one will do):
##   playing_time  he is on the bench or the Green Team (from Week 3 on)
##   contender     his club is in the bottom half of the league and he is good enough to matter elsewhere
##   unhappy       morale is well below neutral
## The club will not let a core player go (top 3 on its roster) unless he is unhappy.

const CORE_RANK := 3
const REFUSE_MORALE := -4.0
const COOLDOWN_WEEKS := 4
const MIN_WEEK := 3
const UNHAPPY_GAP := 10.0
const REASON_TEXT := {
	&"playing_time": "You are not playing and want a team where you will.",
	&"contender": "Your club is going nowhere and you want to play for a winner.",
	&"unhappy": "You are unhappy here and want a fresh start.",
}


static func _key(season: Season) -> int:
	return season.year * 1000 + season.week


## Why he may ask right now (a list of reason keys; empty = he has no case).
static func reasons(season: Season) -> Array:
	var out: Array = []
	var p := season.player
	var team := season.user_team()
	if p == null or team == null:
		return out
	var st := PlayerCoach.status(season)
	var early := season.phase == Season.PHASE_REGULAR and not season.preseason_camp and season.week < MIN_WEEK
	if (st["where"] == PlayerCoach.WHERE_BENCH or st["where"] == PlayerCoach.WHERE_GREEN) and not early:
		out.append(&"playing_time")
	if rank_of(season, team) > season.league.teams.size() / 2 and p.best_ovr() >= _weakest_starter_ovr(team):
		out.append(&"contender")
	if p.morale <= Soldier.MORALE_NEUTRAL - UNHAPPY_GAP:
		out.append(&"unhappy")
	return out


## 1 = the strongest team in the league.
static func rank_of(season: Season, team: Team) -> int:
	var mine := team.team_ovr()
	var r := 1
	for t in season.league.teams:
		if t != team and t.team_ovr() > mine:
			r += 1
	return r


static func _weakest_starter_ovr(team: Team) -> int:
	var worst := 999
	for s in team.starters():
		worst = mini(worst, s.best_ovr())
	return worst if worst != 999 else 0


## "" if he may open the request page's list now, else why not.
static func error(season: Season) -> String:
	var p := season.player
	if p == null or not season.player_mode:
		return "Career mode only."
	if PlayerLegacy.retired(season):
		return "You have retired."
	if not season.trades.window_open(season):
		return "The trade window is closed. It reopens after the Final."
	if p.moved_year == season.year:
		return "You already changed clubs this season."
	if p.request_block > _key(season) and season.phase != Season.PHASE_OFFSEASON:
		return "The club told you no recently. Give it a few weeks."
	if p.is_injured():
		return "You are injured; no club wants to talk to you right now."
	return ""


## Clubs that would take him, best team first: [{team, starts (bool), rank}].
static func destinations(season: Season) -> Array:
	var out: Array = []
	var p := season.player
	var mine := season.user_team()
	if p == null or mine == null:
		return out
	for t in season.league.teams:
		if t == mine:
			continue
		var worst := 999
		for s in t.roster:
			worst = mini(worst, s.best_ovr())
		if t.roster.size() < Team.ROSTER_SIZE:
			worst = 0
		if p.best_ovr() < worst:
			continue
		out.append({"team": t, "starts": p.best_ovr() > _weakest_starter_ovr(t), "rank": rank_of(season, t)})
	out.sort_custom(func(a, b): return int(a["rank"]) < int(b["rank"]))
	return out


## Asks for a trade to `dest`. Returns {result: granted|refused|error, text, reasons}.
static func ask(season: Season, dest: Team) -> Dictionary:
	var err := error(season)
	if err != "":
		return {"result": "error", "text": err}
	var p := season.player
	var mine := season.user_team()
	if dest == null or dest == mine or not destinations(season).any(func(d): return d["team"] == dest):
		return {"result": "error", "text": "That club would not take you."}
	var why := reasons(season)
	if why.is_empty():
		return _refuse(season, p, "%s: \"Give us a reason. You are playing, your club is fine and you are in good spirits.\"" % mine.name, why)
	if mine.roster_count() <= season.trades.min_roster(season) and mine.roster.has(p):
		return _refuse(season, p, "%s cannot spare a body right now." % mine.name, why)
	if _core(mine, p) and not why.has(&"unhappy"):
		return _refuse(season, p, "%s: \"You are one of our top players. We are not letting you go.\"" % mine.name, why)
	p.trade_request = true  # he leaves relieved (Trades._move)
	var give: Array = [Trades.player_asset(p)]
	season.trades.execute(season, mine, give, dest, [])
	season.player_team = dest
	p.moved_year = season.year
	p.request_block = 0
	season.player_notes.append({"year": season.year, "week": season.week, "text": "You asked out and %s sent you to %s." % [mine.name, dest.name]})
	PlayerLegacy.update(season)
	return {"result": "granted", "text": "%s agreed. You are now with %s." % [mine.name, dest.name], "reasons": why}


static func _core(team: Team, p: Soldier) -> bool:
	var better := 0
	for s in team.roster:
		if s != p and s.best_ovr() > p.best_ovr():
			better += 1
	return team.roster.has(p) and better < CORE_RANK


static func _refuse(season: Season, p: Soldier, text: String, why: Array) -> Dictionary:
	p.add_morale(REFUSE_MORALE)
	p.request_block = _key(season) + COOLDOWN_WEEKS
	season.player_notes.append({"year": season.year, "week": season.week, "text": "Your trade request was refused."})
	return {"result": "refused", "text": text, "reasons": why}
