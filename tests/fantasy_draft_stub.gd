extends RefCounted
## Test-only stand-in for the engine's FantasyDraft (same public contract), used by
## fantasy_draft_ui.gd when Season has no start_fantasy_draft() yet. Does not touch rosters.

const ROUNDS := 15

var teams: Array = []
var user: Team
var pool: Array[Soldier] = []
var picks: Array = []


static func make(league: League, user_team: Team) -> RefCounted:
	var d: RefCounted = load("res://tests/fantasy_draft_stub.gd").new()
	d.teams = league.teams.duplicate()
	d.user = user_team
	for s in league.all_soldiers():
		d.pool.append(s)
	return d


func _order_team(i: int) -> Team:
	var r := i / teams.size()
	var k := i % teams.size()
	return teams[k] if r % 2 == 0 else teams[teams.size() - 1 - k]


func is_complete() -> bool:
	return picks.size() >= ROUNDS * teams.size()


func current_team() -> Team:
	return _order_team(picks.size())


func user_on_clock() -> bool:
	return not is_complete() and current_team() == user


func round_number() -> int:
	return picks.size() / teams.size() + 1


func pick_number() -> int:
	return picks.size() + 1


func available() -> Array[Soldier]:
	var out: Array[Soldier] = pool.duplicate()
	out.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
	return out


func make_pick(s: Soldier) -> String:
	if is_complete() or not pool.has(s):
		return "Not available."
	var t := current_team()
	var r := round_number()
	pool.erase(s)
	picks.append({"team": t, "soldier": s, "pick": picks.size() + 1, "round": r})
	return ""


func ai_choice(_team: Team) -> Soldier:
	return available()[0]


func sim_next() -> Dictionary:
	if is_complete():
		return {}
	make_pick(ai_choice(current_team()))
	return picks[-1]


func sim_to_user_pick() -> Array:
	var out: Array = []
	while not is_complete() and not user_on_clock():
		out.append(sim_next())
	return out


func sim_to_end() -> Array:
	var out: Array = []
	while not is_complete():
		out.append(sim_next())
	return out


func picks_left_for(team: Team) -> int:
	var n := 0
	for i in range(picks.size(), ROUNDS * teams.size()):
		if _order_team(i) == team:
			n += 1
	return n


func results() -> Array:
	return picks


func team_picks(team: Team) -> Array:
	return picks.filter(func(p): return p["team"] == team)
