extends SceneTree
## Match-sim behaviour baseline. Not pass/fail: sims many matches between seeded league teams and prints
## per-role kills, deaths, damage, time in cover, distance run, hill time and game lengths, so a change to
## the role/cover AI can be compared with the numbers before it.
##   godot --headless --path . --script res://tests/sim_baseline.gd
## MATCHES=<n> sets how many matches (default 300).

const MODES := [&"tdm", &"koth", &"sudden_death"]


func _init() -> void:
	Season.fixture_teams = 0
	Season.backfill_careers = false
	Season.seed_records = false
	var n := int(OS.get_environment("MATCHES")) if OS.get_environment("MATCHES") != "" else 300
	var s := Season.new_franchise(777, 0)
	var teams: Array = s.league.teams
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# role name -> accumulators
	var role := {}
	var mode_len := {}
	var koth_split := []  # abs(hill_s share) of the winner
	var koth_zero := 0
	var t0 := Time.get_ticks_msec()
	for i in n:
		var a: Team = teams[rng.randi() % teams.size()]
		var b: Team = teams[rng.randi() % teams.size()]
		if a == b:
			continue
		var r := MatchEngine.simulate(a, b, 10000 + i)
		for g: Dictionary in r.games:
			var m: StringName = g["mode"]
			if not mode_len.has(m):
				mode_len[m] = []
			mode_len[m].append(float(g["duration_s"]))
			if m == &"koth":
				var h0 := float(g["score"][0])
				var h1 := float(g["score"][1])
				if h0 + h1 > 0.0:
					koth_split.append(maxf(h0, h1) / (h0 + h1))
				else:
					koth_zero += 1
		for id in r.box:
			var line: Dictionary = r.box[id]
			var team: Team = r.teams[int(line["team"])]
			var rname := _role_name(team, line["slot"])
			if not role.has(rname):
				role[rname] = {"n": 0}
			var acc: Dictionary = role[rname]
			acc["n"] += 1
			for k in ["kills", "deaths", "assists", "shots", "hits", "damage", "cover_s", "distance", "hill_s", "contest_s",
					"kill_dist", "rounds_played", "games"]:
				acc[k] = float(acc.get(k, 0.0)) + float(line.get(k, 0.0))
	print("matches: %d (%.1fs)" % [n, (Time.get_ticks_msec() - t0) / 1000.0])
	for rname in ["Frontman", "Center", "Flex"]:
		var a: Dictionary = role.get(rname, {})
		if a.is_empty():
			continue
		var cnt: float = a["n"]
		print("%-9s kills %.2f deaths %.2f K/D %.2f dmg %.0f acc %.1f%% cover %.1fs dist %.0fm hill %.1fs contest %.1fs killdist %.1fm" % [
			rname, a["kills"] / cnt, a["deaths"] / cnt, a["kills"] / maxf(a["deaths"], 1.0), a["damage"] / cnt,
			100.0 * a["hits"] / maxf(a["shots"], 1.0), a["cover_s"] / cnt, a["distance"] / cnt, a["hill_s"] / cnt,
			a["contest_s"] / cnt, a["kill_dist"] / maxf(a["kills"], 1.0)])
	for m in mode_len:
		var arr: Array = mode_len[m]
		var tot := 0.0
		for v in arr:
			tot += v
		print("%-12s games %d avg length %.0fs" % [m, arr.size(), tot / arr.size()])
	var sp := 0.0
	for v in koth_split:
		sp += v
	if not koth_split.is_empty():
		print("KOTH winner share of hold time: %.3f (games with no hold at all: %d)" % [sp / koth_split.size(), koth_zero])
	quit(0)


func _role_name(team: Team, slot_id: StringName) -> String:
	return Scheme.ROLE_NAMES[team.scheme.role_for_slot(slot_id)]
