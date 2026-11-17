extends SceneTree
## Ability threshold analysis (issue #124, phase 1). Reads the league's ratings and prints, for the 25
## planned ability requirement sets, how many players qualify at candidate bronze / silver / gold
## cut-offs. Changes nothing in the game.
##   SEASONS=0 SEED=7 godot --headless --path . --script res://tools/ability_distribution.gd
## SEASONS: seasons to simulate before measuring (default 0 = the league as it starts).
## FIXTURE=1: use the generated test league instead of the authored one.

## id -> [name, [required stats]]. Tier = the lowest required rating.
const ABILITIES := [
	["Frontline Warrior", [Stats.SHORT_ACC, Stats.MEDIUM_ACC, Stats.GROUPING]],
	["Marksman", [Stats.LONG_ACC, Stats.SWAY, Stats.AWARENESS]],
	["Run & Gun", [Stats.MEDIUM_ACC, Stats.SWAY, Stats.SPEED]],
	["Headhunter", [Stats.GROUPING, Stats.MEDIUM_ACC, Stats.COMPOSURE]],
	["Suppressor", [Stats.RELOAD, Stats.GROUPING, Stats.STRENGTH]],
	["Quick Hands", [Stats.RELOAD, Stats.AGILITY, Stats.COMPOSURE]],
	["Opening Strike", [Stats.AWARENESS, Stats.SPEED, Stats.SHORT_ACC]],
	["Gunslinger", [Stats.SHORT_ACC, Stats.RELOAD, Stats.AGILITY]],
	["Ghost", [Stats.SPEED, Stats.AGILITY, Stats.AWARENESS]],
	["Cover Specialist", [Stats.AGILITY, Stats.AWARENESS, Stats.COMPOSURE]],
	["Stand Fast", [Stats.STRENGTH, Stats.ENDURANCE, Stats.COMPOSURE]],
	["Marathoner", [Stats.ENDURANCE, Stats.SPEED, Stats.OBJ_IQ]],
	["Flanker", [Stats.SPEED, Stats.AWARENESS, Stats.BREACH]],
	["Clutch", [Stats.COMPOSURE, Stats.AWARENESS, Stats.ANCHOR]],
	["Field General", [Stats.TEAMWORK, Stats.AWARENESS, Stats.OBJ_IQ]],
	["Crossfire Partner", [Stats.TEAMWORK, Stats.MEDIUM_ACC, Stats.COMPOSURE]],
	["Guardian Angel", [Stats.TEAMWORK, Stats.AGILITY, Stats.SHORT_ACC]],
	["Sixth Sense", [Stats.AWARENESS, Stats.OBJ_IQ, Stats.LONG_ACC]],
	["King of the Hill", [Stats.ANCHOR, Stats.MEDIUM_ACC, Stats.COMPOSURE]],
	["Hill Breaker", [Stats.BREACH, Stats.SPEED, Stats.SHORT_ACC]],
	["Point Controller", [Stats.OBJ_IQ, Stats.TEAMWORK, Stats.ANCHOR]],
	["Retaker", [Stats.BREACH, Stats.OBJ_IQ, Stats.STRENGTH]],
	["Closer", [Stats.OBJ_IQ, Stats.COMPOSURE, Stats.ENDURANCE]],
	["Iron Man", [Stats.INJURY, Stats.TOUGHNESS, Stats.ENDURANCE]],
	["Quick Healer", [Stats.TOUGHNESS, Stats.ENDURANCE, Stats.TEAMWORK]],
]

const BRONZE_CANDIDATES := [55, 60, 65, 70, 75]
const OVR_BANDS := [[0, 69, "<70"], [70, 79, "70-79"], [80, 89, "80-89"], [90, 99, "90+"]]


func _init() -> void:
	var seasons := int(OS.get_environment("SEASONS")) if OS.get_environment("SEASONS") != "" else 0
	var seed_value := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7
	if OS.get_environment("FIXTURE") == "1":
		Season.fixture_teams = 0
	var s := Season.new_franchise(seed_value, 1)
	for i in seasons:
		s.sim_to_end_of_season()
		while s.offseason_stage != Season.OFF_DONE:
			s.advance_offseason()
		s.start_next_season()
	var starters: Array = []
	var everyone: Array = []
	for t: Team in s.league.teams:
		starters.append_array(t.starters())
		everyone.append_array(t.roster)
	print("Year %d, %d teams, %d starters, %d rostered players" % [s.year, s.league.teams.size(), starters.size(), everyone.size()])
	_rating_table(starters)
	_per_ability(starters)
	_slot_fill(starters)
	_tier_grid(starters)
	var med := _medians(everyone)
	print("
== League median level per ability ==")
	print("  " + ", ".join(ABILITIES.map(func(a): return "%s %d" % [a[0], med[a[0]]])))
	_holders(everyone, [70, 88, 95], false, med)
	_holders(everyone, [70, 88, 95], true, med)
	print("
########## ALL ROSTERED PLAYERS (starters + bench) ##########")
	for cfg in CONFIGS:
		print("
== Best-4 mix, bronze %d / silver %d / gold %d ==" % [cfg[0], cfg[1], cfg[2]])
		_config_rows(everyone, cfg)
	quit()


## Mean and percentiles of every rating among starters.
func _rating_table(group: Array) -> void:
	print("\n== Starter ratings (min / p10 / p25 / median / p75 / p90 / max) ==")
	for st in Stats.ALL:
		var v: Array = group.map(func(so: Soldier): return int(so.stats[st]))
		v.sort()
		print("  %-18s %2d  %2d  %2d  %2d  %2d  %2d  %2d" % [Stats.LABELS[st], v[0], _pct(v, 0.1), _pct(v, 0.25), _pct(v, 0.5), _pct(v, 0.75), _pct(v, 0.9), v[-1]])


func _pct(sorted: Array, p: float) -> int:
	return int(sorted[clampi(int(p * sorted.size()), 0, sorted.size() - 1)])


## Lowest required rating of `ability` for `so` (the value tiers are cut from).
func _level(so: Soldier, ability: Array) -> int:
	var low := 99
	for st in ability[1]:
		low = mini(low, int(so.stats[st]))
	return low


## Share of starters qualifying for each ability at each bronze candidate.
func _per_ability(group: Array) -> void:
	print("\n== Share of starters who qualify, by bronze cut-off ==")
	var head := "  %-18s" % "ability"
	for b in BRONZE_CANDIDATES:
		head += " %5d" % b
	print(head)
	for a in ABILITIES:
		var line := "  %-18s" % a[0]
		for b in BRONZE_CANDIDATES:
			var n := group.filter(func(so: Soldier): return _level(so, a) >= b).size()
			line += " %4.0f%%" % (100.0 * n / group.size())
		print(line)


## How many abilities a starter qualifies for, by bronze cut-off (the 4 slots are the best four).
func _slot_fill(group: Array) -> void:
	print("\n== Qualifying abilities per starter, by bronze cut-off ==")
	print("  bronze   avg   0     1     2     3     4+   (share of starters)")
	for b in BRONZE_CANDIDATES:
		var counts := [0, 0, 0, 0, 0]
		var total := 0
		for so: Soldier in group:
			var n := 0
			for a in ABILITIES:
				if _level(so, a) >= b:
					n += 1
			total += n
			counts[mini(n, 4)] += 1
		var line := "  %5d  %4.1f" % [b, float(total) / group.size()]
		for c in counts:
			line += " %4.0f%%" % (100.0 * c / group.size())
		print(line)


## Candidate [bronze, silver, gold] sets, compared by OVR band below.
const CONFIGS := [[70, 88, 95], [75, 88, 95], [75, 85, 93], [75, 90, 95]]


## For each cut-off set: what each player's best 4 abilities look like, overall and by OVR band.
## The target: most players fill all 4 slots, a few silver, gold rare except for elite (90+) players.
func _tier_grid(group: Array) -> void:
	for cfg in CONFIGS:
		print("
== Best-4 mix, bronze %d / silver %d / gold %d ==" % [cfg[0], cfg[1], cfg[2]])
		_config_rows(group, cfg)


func _config_rows(group: Array, cfg: Array) -> void:
	print("  %-8s %5s  %5s  %6s %6s %6s   %s" % ["OVR", "n", "slots", "bronze", "silver", "gold", "players with a gold"])
	var bands: Array = [[0, 99, "all"]] + OVR_BANDS
	for band in bands:
		var members := group.filter(func(so: Soldier): return so.best_ovr() >= band[0] and so.best_ovr() <= band[1])
		if members.is_empty():
			continue
		var tiers := [0, 0, 0]
		var any_gold := 0
		for so: Soldier in members:
			var levels: Array = []
			for a in ABILITIES:
				var lv := _level(so, a)
				if lv >= cfg[0]:
					levels.append(lv)
			levels.sort()
			levels.reverse()
			var gold_here := false
			for lv in levels.slice(0, 4):
				if lv >= cfg[2]:
					tiers[2] += 1
					gold_here = true
				elif lv >= cfg[1]:
					tiers[1] += 1
				else:
					tiers[0] += 1
			if gold_here:
				any_gold += 1
		var held: int = tiers[0] + tiers[1] + tiers[2]
		print("  %-8s %5d  %4.1f   %5.0f%% %5.0f%% %5.1f%%   %4.0f%%" % [band[2], members.size(), float(held) / members.size(),
			100.0 * tiers[0] / maxf(1, held), 100.0 * tiers[1] / maxf(1, held), 100.0 * tiers[2] / maxf(1, held),
			100.0 * any_gold / members.size()])


## Each ability's typical level (league median of its lowest required rating). Ranking abilities by
## level minus this stops easy combinations from crowding out hard ones. Printed so it can become a constant.
func _medians(group: Array) -> Dictionary:
	var out := {}
	for a in ABILITIES:
		var v: Array = group.map(func(so: Soldier): return _level(so, a))
		v.sort()
		out[a[0]] = _pct(v, 0.5)
	return out


## How often each ability lands in a player's best 4 (variety check: no ability should dominate or never appear).
## `by_margin`: rank by level minus the ability's league median instead of by raw level.
func _holders(group: Array, cfg: Array, by_margin: bool, medians: Dictionary) -> void:
	print("
== Best-4 holders, bronze %d, ranked by %s (of %d rostered) ==" % [cfg[0], "margin over median" if by_margin else "raw level", group.size()])
	var held := {}
	for a in ABILITIES:
		held[a[0]] = 0
	for so: Soldier in group:
		var scored: Array = []
		for a in ABILITIES:
			var lv := _level(so, a)
			if lv >= cfg[0]:
				scored.append([lv - (int(medians[a[0]]) if by_margin else 0), a[0]])
		scored.sort_custom(func(x, y): return x[0] > y[0])
		for e in scored.slice(0, 4):
			held[e[1]] += 1
	var rows: Array = held.keys()
	rows.sort_custom(func(x, y): return held[x] > held[y])
	var line := ""
	for k in rows:
		line += "%s %d, " % [k, held[k]]
	print("  " + line)
