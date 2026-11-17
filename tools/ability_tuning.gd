extends SceneTree
## Ability effect tuning (issue #124, phase 4): how much do abilities move a match?
## For many team pairs and seeds it plays the same match three ways and prints team A's win rate:
##   A has no abilities / both sides have theirs / B has no abilities.
## The gap between the first and last is what a full set of abilities is worth. Goal: a noticeable edge
## (a few win-rate points) that never beats a real rating gap.
##   PAIRS=12 SEEDS=40 godot --headless --path . --script res://tools/ability_tuning.gd
## It also prints each ability's own effect: the same matches with only that ability switched off.

func _init() -> void:
	var pairs_n := int(OS.get_environment("PAIRS")) if OS.get_environment("PAIRS") != "" else 12
	var seeds_n := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 40
	var s := Season.new_franchise(7, 0)
	var teams: Array = s.league.teams
	for t: Team in teams:
		t.auto_lineup()
	# Pairs of teams close in strength, so abilities (not talent) decide the result.
	var order: Array = teams.duplicate()
	order.sort_custom(func(a: Team, b: Team): return a.starters_ovr() > b.starters_ovr())
	var pairs: Array = []
	for i in mini(pairs_n, order.size() - 1):
		pairs.append([order[i], order[i + 1]])
	var wins := [0, 0, 0]
	var games := 0
	for pair in pairs:
		var a: Team = pair[0]
		var b: Team = pair[1]
		for sd in seeds_n:
			var seed_value := 1000 + sd * 31 + games
			# Swap home and away so neither side keeps the field edge.
			var home: Team = a if sd % 2 == 0 else b
			var away: Team = b if sd % 2 == 0 else a
			for cfg in 3:
				var cleared := _clear(a if cfg == 0 else (b if cfg == 2 else null))
				var r := MatchEngine.simulate(home, away, seed_value)
				_restore(cleared)
				if r.winner() == a:
					wins[cfg] += 1
			games += 1
	print("\n%d matches per setup, %d pairs of near-equal teams" % [games, pairs.size()])
	print("  A without abilities:  A wins %4.1f%%" % (100.0 * wins[0] / games))
	print("  both with abilities:  A wins %4.1f%%" % (100.0 * wins[1] / games))
	print("  B without abilities:  A wins %4.1f%%" % (100.0 * wins[2] / games))
	print("  => a full set of abilities is worth about %.1f points of win rate" % (50.0 * (wins[2] - wins[0]) / games))
	quit()


## Empties the abilities of `team`'s starters (returns what to put back).
func _clear(team: Team) -> Array:
	var saved: Array = []
	if team == null:
		return saved
	for so: Soldier in team.starters():
		saved.append([so, so.abilities])
		so.abilities = []
	return saved


func _restore(saved: Array) -> void:
	for e in saved:
		(e[0] as Soldier).abilities = e[1]
