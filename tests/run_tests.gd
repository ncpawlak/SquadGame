extends SceneTree
## Headless test runner:
##   godot --headless --path . --script res://tests/run_tests.gd
## Set TEST_ONLY=<substring> to run only matching tests.
## Exits with code 0 if all tests pass, 1 otherwise.

var _failures := 0
var _passes := 0
var _current := ""


func _init() -> void:
	var tests := [
		"test_generator_ranges",
		"test_ovr_depends_on_position",
		"test_auto_lineup_fills_scheme",
		"test_assign_swaps_players",
		"test_match_structure",
		"test_arena_scoring",
		"test_looks",
		"test_match_is_deterministic",
		"test_live_engine_matches_sim",
		"test_spawn_zone_is_safe",
		"test_team_fields",
		"test_weather",
		"test_different_seeds_vary",
		"test_better_team_wins_more",
		"test_each_combat_stat_matters",
		"test_xp_levels_and_points",
		"test_potential_scales_xp",
		"test_aging_decline",
		"test_stat_groups",
		"test_group_upgrade_rules",
		"test_auto_spend_prefers_role_groups",
		"test_training_intensity",
		"test_fatigue_model",
		"test_injury_model",
		"test_match_awards_xp",
	]
	# TEST_ONLY=substring runs a subset (e.g. TEST_ONLY=live).
	var only := OS.get_environment("TEST_ONLY")
	if only != "":
		tests = tests.filter(func(n): return only in n)
	for t in tests:
		_current = t
		var before := _failures
		call(t)
		if _failures == before:
			_passes += 1
			print("  PASS  ", t)
		else:
			print("  FAIL  ", t)
	print("\n%d passed, %d failed" % [_passes, tests.size() - _passes])
	quit(0 if _passes == tests.size() else 1)


func check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("    [%s] %s" % [_current, msg])


# --- helpers ---------------------------------------------------------------

func make_soldier(id: int, value: int, overrides := {}) -> Soldier:
	var s := Soldier.new()
	s.id = id
	s.first_name = "Test"
	s.last_name = "Soldier%d" % id
	s.age = 26
	s.stats = Stats.make_uniform(value)
	for k in overrides:
		s.stats[k] = overrides[k]
	for g in Stats.UPGRADABLE_GROUPS:
		s.group_caps[g] = 99
	return s


func make_team(id: int, value: int, overrides := {}) -> Team:
	var t := Team.new()
	t.id = id
	t.name = "Team %d" % id
	t.abbrev = "T%d" % id
	for i in Team.ROSTER_SIZE:
		t.roster.append(make_soldier(id * 100 + i, value, overrides))
	t.auto_lineup()
	return t


func win_rate(a: Team, b: Team, matches: int, seed_base := 1000) -> float:
	var wins := 0
	for i in matches:
		# Alternate sides so slot order in the engine can't bias results.
		if i % 2 == 0:
			wins += 1 if MatchEngine.simulate(a, b, seed_base + i).winner_index == 0 else 0
		else:
			wins += 1 if MatchEngine.simulate(b, a, seed_base + i).winner_index == 1 else 0
	return float(wins) / matches


## True unless p sits in a sealed pocket: a 0.25 m flood fill from it covers at least 25 m².
func _open_ground(f: ArenaMap, p: Vector2) -> bool:
	var seen := {Vector2i.ZERO: true}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var head := 0
	while head < queue.size() and queue.size() < 400:
		var c: Vector2i = queue[head]
		head += 1
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if not seen.has(n) and not f.blocked(p + Vector2(n) * 0.25):
				seen[n] = true
				queue.append(n)
	return queue.size() >= 400


## Walks like MatchEngine._move (1 m strides, re-planning every few steps, on reaching the
## waypoint or after sliding along an obstacle) and reports reaching `to`.
func _walks_to(f: ArenaMap, from: Vector2, to: Vector2) -> bool:
	var p := from
	var w := p
	var repath := 0
	for i in 300:
		if p.distance_to(to) <= 1.0:
			return true
		if i >= repath or p.distance_squared_to(w) < 0.25:
			w = f.next_waypoint(p, to)
			repath = i + MatchEngine.REPATH_TICKS
		var d := p.distance_to(w)
		if d < 0.001:
			return false
		var dir := (w - p) / d
		var stride := minf(1.0, d)
		var np := p + dir * stride
		if f.blocked(np):
			np = p + Vector2(dir.x * stride, 0.0)
			if f.blocked(np):
				np = p + Vector2(0.0, dir.y * stride)
				if f.blocked(np):
					np = p
			repath = i + 1
		p = np
	return false


# --- tests -----------------------------------------------------------------

func test_generator_ranges() -> void:
	var league := League.generate(42)
	check(league.teams.size() == 2, "league should have 2 teams")
	for t in league.teams:
		check(t.roster.size() == Team.ROSTER_SIZE, "%s roster size %d" % [t.name, t.roster.size()])
		check(t.starters().size() == 5, "%s should have 5 starters" % t.name)
		for s in t.roster:
			check(s.age >= PlayerGenerator.MIN_AGE and s.age <= PlayerGenerator.MAX_AGE, "age out of range")
			for stat in Stats.ALL:
				check(s.stats[stat] >= 0 and s.stats[stat] <= 99, "%s out of range" % stat)
			for g in Stats.UPGRADABLE_GROUPS:
				check(s.group_cap(g) >= s.group_rating(g) and s.group_cap(g) <= 99, "group cap invalid for %s" % g)
			check(s.potential_ovr() >= s.best_ovr(), "potential below current OVR")


func test_ovr_depends_on_position() -> void:
	var brawler := make_soldier(1, 50, {&"short_acc": 90, &"strength": 90, &"toughness": 90})
	var sniper := make_soldier(2, 50, {&"awareness": 90, &"medium_acc": 90, &"long_acc": 90, &"teamwork": 90})
	var runner := make_soldier(3, 50, {&"speed": 90, &"agility": 90, &"endurance": 90})
	check(brawler.ovr_at_role(Scheme.Role.FRONTMAN) > brawler.ovr_at_role(Scheme.Role.CENTER), "brawler should rate higher at frontman")
	check(sniper.ovr_at_role(Scheme.Role.CENTER) > sniper.ovr_at_role(Scheme.Role.FLEX), "sniper should rate higher at center")
	check(runner.ovr_at_role(Scheme.Role.FLEX) > runner.ovr_at_role(Scheme.Role.FRONTMAN), "runner should rate higher at flex")
	check(Scheme.ovr_for_role(Stats.make_uniform(70), Scheme.Role.CENTER) == 70, "uniform stats -> same OVR")


func test_auto_lineup_fills_scheme() -> void:
	var t := make_team(1, 50)
	t.roster[7].stats = make_soldier(0, 50, {&"short_acc": 95, &"strength": 95, &"toughness": 95}).stats
	t.roster[6].stats = make_soldier(0, 50, {&"speed": 95, &"agility": 95, &"endurance": 95}).stats
	t.auto_lineup()
	check(t.starters().size() == 5, "5 starters")
	var fm := [t.lineup[&"FM1"], t.lineup[&"FM2"]]
	check(fm.has(t.roster[7]), "best frontman should be at FM")
	check(t.lineup[&"LFX"] == t.roster[6] or t.lineup[&"RFX"] == t.roster[6], "best flex should be at a flex slot")


func test_assign_swaps_players() -> void:
	var t := make_team(1, 50)
	var a: Soldier = t.lineup[&"FM1"]
	var b: Soldier = t.lineup[&"CTR"]
	t.assign(&"FM1", b)
	check(t.lineup[&"FM1"] == b and t.lineup[&"CTR"] == a, "assigning a starter swaps slots")
	var bench_guy: Soldier = t.bench()[0]
	t.assign(&"CTR", bench_guy)
	check(t.lineup[&"CTR"] == bench_guy and t.bench().has(a), "assigning bench player benches the starter")


func test_match_structure() -> void:
	var league := League.generate(7)
	var r := MatchEngine.simulate(league.teams[0], league.teams[1], 99)
	check(r.score[r.winner_index] == MatchEngine.GAMES_TO_WIN, "winner takes 2 games")
	check(r.score[1 - r.winner_index] < MatchEngine.GAMES_TO_WIN, "loser below 2 games")
	check(r.games.size() == r.score[0] + r.score[1] and r.games.size() >= 2 and r.games.size() <= 3, "2-3 games played")
	check(r.events.size() > 10, "play-by-play has events")
	for i in r.games.size():
		var g: Dictionary = r.games[i]
		check(g["mode"] == MatchEngine.GAME_ORDER[i], "games in order TDM, KOTH, SD")
		var w: int = g["winner"]
		match g["mode"]:
			MatchEngine.MODE_TDM:
				check(g["score"][w] >= MatchEngine.TDM_POINTS_TO_WIN and g["score"][1 - w] < MatchEngine.TDM_POINTS_TO_WIN,
					"TDM winner reaches 50 (%s)" % [g["score"]])
			MatchEngine.MODE_KOTH:
				check(g["score"][w] >= int(MatchEngine.KOTH_HOLD_TO_WIN_S) and g["score"][1 - w] < int(MatchEngine.KOTH_HOLD_TO_WIN_S),
					"KOTH winner holds 2:00 (%s)" % [g["score"]])
			_:
				check(g["score"][w] == MatchEngine.ROUNDS_TO_WIN and g["rounds"].size() >= 4 and g["rounds"].size() <= 7,
					"SD first to 4 in 4-7 rounds")
	var sd := r.game_of(MatchEngine.MODE_SUDDEN_DEATH)
	check(r.mvp_id != -1, "mvp chosen")
	var kills := 0
	var deaths := 0
	for id in r.box:
		kills += r.box[id]["kills"]
		deaths += r.box[id]["deaths"]
		check(r.box[id]["hits"] <= r.box[id]["shots"], "hits <= shots")
		check(r.box[id]["rounds_played"] == r.rounds.size(), "every starter plays every sudden-death round")
		check(r.box[id]["games"] == r.games.size(), "every starter plays every game")
	check(kills == deaths, "kills == deaths (%d vs %d)" % [kills, deaths])
	check(r.box.size() == 10, "10 box score lines")
	check(sd.is_empty() or sd["rounds"].size() == r.rounds.size(), "rounds listed under the sudden-death game")


## TDM points = kills + wipe bonuses; KOTH hold time = what the players on the point banked.
func test_looks() -> void:
	var heads := {}
	var lowers := {}
	for id in range(1, 1500):
		var l := Look.generate(id, 19 + id % 18, id % 3 as Scheme.Role)
		var again := Look.generate(id, 19 + id % 18, id % 3 as Scheme.Role)
		check(l.describe() == again.describe() and l.skin == again.skin, "look is deterministic per id")
		if l.eyes == Look.Eyes.NIGHT_VISION:
			check(l.head == Look.Head.HELMET, "night vision only on a bare helmet mount")
		check((l.face == Look.Face.BALACLAVA) == (l.lower == Look.Lower.BALACLAVA), "balaclava covers the lower face")
		if l.head in [Look.Head.CAP_FORWARD, Look.Head.BOONIE, Look.Head.HELMET_GOGGLES]:
			check(l.eyes != Look.Eyes.GOGGLES_CLEAR and l.eyes != Look.Eyes.GOGGLES_TINTED, "no goggles under brims / doubled goggles")
		heads[l.head] = true
		lowers[l.lower] = true
	check(heads.size() == Look.Head.size(), "every headgear appears (%d)" % heads.size())
	check(lowers.size() == Look.Lower.size(), "every lower face appears (%d)" % lowers.size())
	var league := League.generate(9, 4)
	for t in league.teams:
		check(t.color2 != t.color, "team has a distinct secondary colour")
		for s in t.roster:
			check(s.look != null, "generated soldiers get a look")


func test_arena_scoring() -> void:
	var league := League.generate(7)
	var seen_koth := 0
	for seed in 6:
		var r := MatchEngine.simulate(league.teams[0], league.teams[1], 500 + seed)
		var tdm := r.game_of(MatchEngine.MODE_TDM)
		check(not tdm.is_empty(), "every match opens with TDM")
		var wipes := 0
		var caps := 0
		var hill := 0.0
		for id in r.box:
			wipes += r.box[id]["wipes"]
			caps += r.box[id]["caps"]
			hill += r.box[id]["hill_s"]
		check(wipes > 0, "arena games have team wipes")
		var koth := r.game_of(MatchEngine.MODE_KOTH)
		if not koth.is_empty():
			seen_koth += 1
			check(caps > 0, "someone captured the hill")
			check(hill >= koth["score"][0] + koth["score"][1] - 1, "hold time credited to players on the point")
			check(koth["score"][0] != koth["score"][1], "KOTH has a winner on hold time")
	check(seen_koth == 6, "KOTH is always game 2")


func test_match_is_deterministic() -> void:
	var league := League.generate(7)
	var a := MatchEngine.simulate(league.teams[0], league.teams[1], 12345)
	var b := MatchEngine.simulate(league.teams[0], league.teams[1], 12345)
	check(a.score == b.score, "same score")
	check(a.events == b.events, "same play-by-play")
	check(str(a.box) == str(b.box), "same box score")


## The live viewer steps the engine with visual events on; it must play out exactly like a sim.
func test_live_engine_matches_sim() -> void:
	var league := League.generate(7)
	var sim := MatchEngine.simulate(league.teams[0], league.teams[1], 777)
	var e := MatchEngine.new()
	e.start(league.teams[0], league.teams[1], 777)
	e.record = true
	var kinds := {}
	var shots := 0
	var moved := false
	var start_pos: Vector2 = e.squads[0][0].pos
	var more := true
	while more:
		more = e.step()
		for ev in e.visual_events:
			kinds[ev["t"]] = true
			if ev["t"] == "shot":
				shots += 1
				check(ev["result"] in ["MISS", "HIT", "HEADSHOT", "KILL"] or String(ev["result"]).begins_with("HIT x"), "shot result label")
		e.visual_events.clear()
		if e.squads[0][0].pos.distance_to(start_pos) > 5.0:
			moved = true
	var live := e.result()
	check(live.score == sim.score, "same series score")
	check(live.events == sim.events, "same play-by-play")
	check(str(live.box) == str(sim.box), "same box score")
	for k in ["game_start", "game_end", "shot", "kill", "match_end"]:
		check(kinds.has(k), "emits %s events" % k)
	check(shots > 50, "plenty of shots to draw (%d)" % shots)
	check(moved, "soldiers move around the map")
	for squad in e.squads:
		for c in squad:
			check(ArenaMap.in_bounds(c.pos), "stays inside the arena")


## Nobody may fire on a soldier standing in his own spawn zone.
func test_spawn_zone_is_safe() -> void:
	check(ArenaMap.in_spawn_zone(0, Vector2(-ArenaMap.START_X - 1.0, 0.0)), "left end is team 0's spawn")
	check(not ArenaMap.in_spawn_zone(1, Vector2(-ArenaMap.START_X - 1.0, 0.0)), "left end is not team 1's spawn")
	check(ArenaMap.in_spawn_zone(1, Vector2(ArenaMap.START_X + 1.0, 0.0)), "right end is team 1's spawn")
	check(not ArenaMap.in_spawn_zone(0, Vector2.ZERO) and not ArenaMap.in_spawn_zone(1, Vector2.ZERO), "the middle is open")
	var league := League.generate(7)
	for seed in [777, 31, 4242]:
		var e := MatchEngine.new()
		e.start(league.teams[0], league.teams[1], seed)
		e.record = true
		var where := {}
		var shots := 0
		var more := true
		while more:
			for squad in e.squads:
				for c in squad:
					where[c.soldier.id] = c
			more = e.step()
			for ev in e.visual_events:
				if ev["t"] != "shot":
					continue
				shots += 1
				var victim: MatchEngine.Combatant = where[ev["target"]]
				check(not ArenaMap.in_spawn_zone(victim.team, ev["to"]), "seed %d: shot fired into a spawn zone" % seed)
			e.visual_events.clear()
		check(shots > 50, "seed %d: shooting still happens (%d)" % [seed, shots])


## Authored home fields: symmetric, schemes can spawn and hold on them, the flank is walkable,
## and a match on one is deterministic.
func test_team_fields() -> void:
	var names := ArenaMap.authored()
	check(names.size() == 20, "every team has an authored field (%d)" % names.size())
	for abbrev in names:
		var f := ArenaMap.for_team(abbrev)
		f.ensure_built()
		check(ArenaMap.SURFACES.has(f.surface), "%s surface %s is known" % [abbrev, f.surface])
		check(f.venue != "" and f.props.size() >= 20, "%s has a venue and props" % abbrev)
		var mirrored := true
		for r in f.obstacles:
			var found := false
			for o in f.obstacles:
				if o.is_equal_approx(Rect2(-r.end, r.size)):
					found = true
			mirrored = mirrored and found
		check(mirrored, "%s layout is point-symmetric" % abbrev)
		# Reflected props keep their class: tall stays tall, cover stays cover (only the look may differ).
		for group in [f.walls, f.crates]:
			var same := true
			for r in group:
				var found := false
				for o in group:
					if o.is_equal_approx(Rect2(-r.end, r.size)):
						found = true
				same = same and found
			check(same, "%s sight blockers and cover mirror each other" % abbrev)
		var starts_clear := true
		for r in f.obstacles:
			starts_clear = starts_clear and r.position.x >= -ArenaMap.START_X - 0.01 and r.end.x <= ArenaMap.START_X + 0.01
		check(starts_clear, "%s starting areas are clear" % abbrev)
		for sch in Scheme.all():
			for sid in sch.slot_ids():
				check(not f.blocked(sch.spawn_of(sid)), "%s %s %s spawn is clear" % [abbrev, sch.id, sid])
				if sch.role_for_slot(sid) != Scheme.Role.FLEX:
					check(not f.blocked(sch.hold_of(sid)) and not f.blocked(sch.hold_of(sid, true)), "%s %s %s hold is clear" % [abbrev, sch.id, sid])
		for right in [false, true]:
			for i in 11:
				var p := ArenaMap.flank_point(i / 10.0, right)
				check(not f.blocked(p) and not f.blocked(-p), "%s flank route is clear" % abbrev)
		var spawn := Scheme.power_front().spawn_of(&"FM1")
		var p := spawn
		var steps := 0
		while p.distance_to(Vector2.ZERO) > 1.0 and steps < 200:
			var w := f.next_waypoint(p, Vector2.ZERO)
			check(not f.blocked(w), "%s waypoint is walkable" % abbrev)
			p = w
			steps += 1
		check(p.distance_to(Vector2.ZERO) <= 1.0, "%s: spawn can path to the hill" % abbrev)
		# Hugging any obstacle (cover spots, dead-end pockets) a soldier can still walk out. Spots
		# sealed off from the field (gaps between packed trees or tables) can't be reached anyway.
		var trapped := 0
		for s in f.cover_spots:
			if _open_ground(f, s) and not _walks_to(f, s, Vector2.ZERO):
				trapped += 1
		check(trapped == 0, "%s: %d wall-hugging spots can't walk to the hill" % [abbrev, trapped])
	var league := League.generate(7)
	var home: Team = league.teams[0]
	var field := ArenaMap.for_team(names[0])
	var a := MatchEngine.simulate(home, league.teams[1], 4242, field)
	var b := MatchEngine.simulate(home, league.teams[1], 4242, field)
	check(a.events == b.events, "a match on a field is deterministic")
	var e := MatchEngine.new()
	e.start(home, league.teams[1], 4242, field)
	for i in 400:
		e.step()
	for squad in e.squads:
		for c in squad:
			check(ArenaMap.in_bounds(c.pos) and not field.blocked(c.pos), "soldiers stay on open ground")


## Weather: climate odds, deterministic rolls, patch coverage, the match-wide stat penalties, the
## in-patch slowdown and that clear weather leaves a match exactly as it was.
func test_weather() -> void:
	# Climate: Miami rains far more than Reno, Boston snows, San Diego never does.
	var rain := {}
	var snow := {}
	for abbrev in ["MIA", "REN", "BOS", "SDV"]:
		rain[abbrev] = 0
		snow[abbrev] = 0
		for s in 3000:
			var w := Weather.roll(s, abbrev)
			rain[abbrev] += 1 if w.kind == Weather.RAIN else 0
			snow[abbrev] += 1 if w.kind == Weather.SNOW else 0
	check(rain["MIA"] > rain["REN"] * 3, "Miami rains much more than Reno (%d vs %d)" % [rain["MIA"], rain["REN"]])
	check(snow["SDV"] == 0, "San Diego never snows")
	check(snow["BOS"] > snow["REN"] * 2 and snow["BOS"] > 300, "Boston snows often (%d)" % snow["BOS"])
	check(abs(rain["MIA"] / 3000.0 - 0.30) < 0.04, "Miami's rain rate follows its climate (%d/3000)" % rain["MIA"])

	# A roll is a pure function of the seed and the home team.
	var a := Weather.roll(1234, "BOS")
	var b := Weather.roll(1234, "BOS")
	check(a.kind == b.kind and a.level == b.level and is_equal_approx(a.coverage, b.coverage), "weather rolls are deterministic")
	var levels := {1: 0, 2: 0}
	for s in 4000:
		var w := Weather.roll(s, "SEA")
		if w.level > 0:
			levels[w.level] += 1
			var span: Vector2 = Weather.COVERAGE[w.level]
			check(w.coverage >= span.x - 0.001 and w.coverage <= span.y + 0.001, "coverage sits in the level's range")
	check(levels[1] > levels[2] and levels[2] > 0, "light weather is more common than inclement (%s)" % str(levels))

	# Patches cover about the rolled share of the open floor, never a start zone or a prop.
	var field := ArenaMap.for_team("BOS")
	field.ensure_built()
	for lvl in [1, 2]:
		var w := Weather.new()
		w.kind = Weather.RAIN
		w.level = lvl
		w.coverage = 0.3 if lvl == 2 else 0.15
		w._seed = 99 + lvl
		w.prepare(field)
		check(absf(w.covered_share() - w.coverage) < 0.02, "level %d patches cover %.0f%% (got %.1f%%)" % [lvl, w.coverage * 100.0, w.covered_share() * 100.0])
		var clean := true
		for y in Weather.ROWS:
			for x in Weather.COLS:
				if w.cell_depth(x, y) > 0.0:
					var c := Vector2(x + 0.5 - ArenaMap.HALF.x, y + 0.5 - ArenaMap.HALF.y)
					clean = clean and absf(c.x) <= ArenaMap.START_X - 0.5 and not Weather._under_prop(field, c)
		check(clean, "no patch in a start zone or under a prop")

	# Slowdown only inside a patch, by the table.
	var wet := Weather.new()
	wet.kind = Weather.SNOW
	wet.level = 2
	wet.coverage = 0.4
	wet._seed = 5
	wet.prepare(field)
	var inside := Vector2.INF
	var outside := Vector2.INF
	for y in Weather.ROWS:
		for x in Weather.COLS:
			var c := Vector2(x + 0.5 - ArenaMap.HALF.x, y + 0.5 - ArenaMap.HALF.y)
			if wet.cell_depth(x, y) > 0.0 and inside == Vector2.INF:
				inside = c
			elif wet.cell_depth(x, y) == 0.0 and outside == Vector2.INF:
				outside = c
	check(is_equal_approx(wet.slow_at(inside), 0.5), "inclement snow halves speed in a patch")
	check(wet.slow_at(outside) == 1.0, "bare floor is not slowed")
	check(Weather.clear().slow_at(inside) == 1.0, "clear weather never slows")

	# Match-wide stat penalties (rain and snow differ).
	var league := League.generate(7)
	var home: Team = league.teams[0]
	var away: Team = league.teams[1]
	var rain2 := Weather.new()
	rain2.kind = Weather.RAIN
	rain2.level = 2
	var snow1 := Weather.new()
	snow1.kind = Weather.SNOW
	snow1.level = 1
	check(rain2.penalty(&"short_acc") == 6.0 and rain2.penalty(&"sway") == 6.0 and rain2.penalty(&"composure") == 6.0, "inclement rain costs 6 points of aim, sway and composure")
	check(rain2.penalty(&"reload") == 0.0 and rain2.penalty(&"endurance") == 0.0, "rain leaves reload and endurance alone")
	check(snow1.penalty(&"reload") == 4.0 and snow1.penalty(&"grouping") == 4.0 and snow1.penalty(&"endurance") == 4.0 and snow1.penalty(&"long_acc") == 4.0, "light snow costs 4 points of reload, grouping, endurance and aim")
	check(snow1.penalty(&"sway") == 0.0 and snow1.penalty(&"composure") == 0.0, "snow leaves sway and composure alone")
	var clear_e := MatchEngine.new()
	clear_e.start(home, away, 31, field)
	var rain_e := MatchEngine.new()
	rain_e.start(home, away, 31, field, rain2)
	var snow_e := MatchEngine.new()
	snow_e.start(home, away, 31, field, snow1)
	var c0: MatchEngine.Combatant = clear_e.squads[0][0]
	var r0: MatchEngine.Combatant = rain_e.squads[0][0]
	var s0: MatchEngine.Combatant = snow_e.squads[0][0]
	check(is_equal_approx(c0.stat(&"short_acc") - r0.stat(&"short_acc"), 6.0), "rain lowers a soldier's short accuracy by 6")
	check(is_equal_approx(c0.stat(&"reload") - s0.stat(&"reload"), 4.0), "snow lowers a soldier's reload by 4")
	check(is_equal_approx(c0.stat(&"speed"), r0.stat(&"speed")), "speed is only slowed on the patches, not match-wide")

	# Clear weather changes nothing; weather is deterministic and recorded on the result.
	var plain := MatchEngine.simulate(home, away, 4242, field)
	var explicit := MatchEngine.simulate(home, away, 4242, field, Weather.clear())
	check(plain.events == explicit.events, "clear weather leaves a match untouched")
	check(plain.weather_level == 0 and plain.weather_kind == Weather.CLEAR, "a clear match is recorded as clear")
	var seed_wet := 0
	while Weather.roll(seed_wet, "BOS").level < 2 or Weather.roll(seed_wet, "BOS").kind != Weather.SNOW:
		seed_wet += 1
	var sm := ScheduledMatch.new()
	sm.home = home
	sm.away = away
	sm.match_seed = seed_wet
	sm.home.abbrev = "BOS"
	check(sm.weather().kind == Weather.SNOW and sm.weather().level == 2, "a fixture rolls its weather from its seed and home team")
	var played := sm.play()
	check(played.weather_kind == Weather.SNOW and played.weather_level == 2, "the result records the weather")
	check(sm.shown_weather().label() == "Inclement Snow", "a played match shows the weather it had")
	var live := sm.live_engine()
	while live.step():
		pass
	check(live.result().events == played.events, "a watched match plays the same weather as a simulated one")
	for squad in live.squads:
		for c in squad:
			check(ArenaMap.in_bounds(c.pos) and not field.blocked(c.pos), "soldiers stay on open ground in the snow")


func test_different_seeds_vary() -> void:
	var a := make_team(1, 60)
	var b := make_team(2, 60)
	var outcomes := {}
	for i in 30:
		outcomes[MatchEngine.simulate(a, b, i).score_line()] = true
	check(outcomes.size() > 3, "evenly matched teams should produce varied scorelines (%d)" % outcomes.size())
	var wr := win_rate(a, b, 200)
	check(wr > 0.38 and wr < 0.62, "identical teams ~50%% (got %.2f)" % wr)


func test_better_team_wins_more() -> void:
	var wr := win_rate(make_team(1, 75), make_team(2, 55), 100)
	# Match-day form leaves room for the odd upset even in a mismatch.
	check(wr > 0.82, "75-rated team should crush 55-rated team (%.2f)" % wr)
	wr = win_rate(make_team(1, 65), make_team(2, 60), 200)
	check(wr > 0.55, "65 should beat 60 more often (%.2f)" % wr)


## Raising any single combat stat (others equal) should improve the win rate.
## Injury is excluded because injuries aren't simulated yet (its win rate should sit near 50%).
## This is the slowest test (~2,600 matches).
func test_each_combat_stat_matters() -> void:
	var report: Array[String] = []
	for stat in Stats.ALL:
		if stat == Stats.INJURY or stat == Stats.TOUGHNESS:
			continue  # off-field stats: injury chance and injury length
		var wr := win_rate(make_team(1, 45, {stat: 95}), make_team(2, 45), 200, 5000)
		report.append("%s=%.2f" % [Stats.ABBREV[stat], wr])
		check(wr > 0.55, "%s at 95 vs 45 should help (win rate %.2f)" % [stat, wr])
	print("    stat sensitivity: ", ", ".join(report))


func test_xp_levels_and_points() -> void:
	var s := make_soldier(1, 50)
	s.potential = 2
	var m := Progression.xp_multiplier(s)
	var r := Progression.gain_xp(s, (Progression.xp_to_next(1) - 1) / m)
	check(r["levels"] == 0 and s.level == 1, "just under threshold: no level")
	r = Progression.gain_xp(s, 1.0 / m)
	check(r["levels"] == 1 and s.level == 2 and s.xp == 0, "level up exactly at threshold")
	check(s.skill_points == Progression.SKILL_POINTS_PER_LEVEL, "points granted")
	Progression.gain_xp(s, (Progression.xp_to_next(2) + Progression.xp_to_next(3)) / m)
	check(s.level == 4, "multi-level gain (level %d)" % s.level)


func test_potential_scales_xp() -> void:
	var high := make_soldier(1, 50)
	high.potential = Soldier.POTENTIAL_A
	var low := make_soldier(2, 50)
	low.potential = 0
	var rh := Progression.gain_xp(high, 1000)
	var rl := Progression.gain_xp(low, 1000)
	check(rh["xp"] > rl["xp"] * 5, "A gains far more than F (%d vs %d)" % [rh["xp"], rl["xp"]])
	# Age matters too: young soldiers gain more than veterans of the same grade.
	var young := make_soldier(3, 50)
	young.age = 20
	young.potential = Soldier.POTENTIAL_A
	var old := make_soldier(4, 50)
	old.age = 33
	old.potential = Soldier.POTENTIAL_A
	var yx: int = Progression.gain_xp(young, 1000)["xp"]
	var ox: int = Progression.gain_xp(old, 1000)["xp"]
	check(yx > ox * 4, "same grade: young gains more (%d vs %d)" % [yx, ox])
	# Grades skew high for young players, and higher grades get more cap room on average.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var young_sum := 0
	var old_sum := 0
	for i in 400:
		young_sum += PlayerGenerator.roll_potential(rng, 20)
		old_sum += PlayerGenerator.roll_potential(rng, 32)
	check(young_sum > old_sum * 1.5, "young players roll higher grades (%d vs %d)" % [young_sum, old_sum])
	var room := [0, 0]
	for i in 200:
		for k in 2:
			var so := make_soldier(10 + i, 50)
			so.age = 22
			so.potential = Soldier.POTENTIAL_A if k == 0 else 0
			PlayerGenerator.roll_caps(so, rng)
			for g in Stats.UPGRADABLE_GROUPS:
				room[k] += so.group_headroom(g)
	check(room[0] > room[1] * 2, "A caps well above F caps (%d vs %d)" % [room[0], room[1]])
	# Grade changes move caps, never below the current rating.
	var s := make_soldier(5, 70)
	s.potential = 2
	for g in Stats.UPGRADABLE_GROUPS:
		s.group_caps[g] = 72
	SeasonReview.set_potential(s, 4, rng)
	var total := 0
	for g in Stats.UPGRADABLE_GROUPS:
		total += s.group_cap(g)
	check(s.potential == 4 and total >= 72 * 4 + 4, "grade up raises caps (%d)" % total)
	SeasonReview.set_potential(s, 0, rng)
	for g in Stats.UPGRADABLE_GROUPS:
		check(s.group_cap(g) >= s.group_rating(g), "grade down never drops cap below rating")


func test_aging_decline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var young := make_soldier(1, 70)
	young.age = 24
	var r := Aging.age_soldier(young, rng)
	check(young.age == 25 and r["changes"].is_empty(), "no decline before peak")
	var vet := make_soldier(2, 70)
	vet.age = 32
	var before := {}
	for g in Stats.GROUP_ORDER:
		before[g] = vet.group_rating(g)
	r = Aging.age_soldier(vet, rng)
	check(vet.age == 33, "aged")
	check(vet.group_rating(Stats.PHYSICALITY) < before[Stats.PHYSICALITY], "physicality declines first")
	check(vet.group_rating(Stats.MENTALITY) == before[Stats.MENTALITY], "mentality holds until later")
	for g in Stats.UPGRADABLE_GROUPS:
		check(vet.group_cap(g) >= vet.group_rating(g), "cap stays at or above rating")
	check(Aging.decline_rate(6) > Aging.decline_rate(1), "decline speeds up with age")
	# Ten more years: everything falls, and steeply.
	for i in 10:
		Aging.age_soldier(vet, rng)
	check(vet.group_rating(Stats.PHYSICALITY) < 50, "old soldier's physicality collapses (%d)" % vet.group_rating(Stats.PHYSICALITY))


func test_stat_groups() -> void:
	var covered := {}
	for g in Stats.GROUP_ORDER:
		for st in Stats.group_stats(g):
			check(not covered.has(st), "%s in two groups" % st)
			covered[st] = true
	check(covered.size() == Stats.ALL.size(), "every stat belongs to a group")
	var s := make_soldier(1, 50, {&"short_acc": 60, &"medium_acc": 70, &"long_acc": 80})
	check(s.group_rating(Stats.ACCURACY) == 70, "group rating is the average")
	check(not Stats.UPGRADABLE_GROUPS.has(Stats.DURABILITY), "injury group is view-only")


func test_group_upgrade_rules() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for trial in 50:
		var s := make_soldier(1, 50)
		s.skill_points = 100
		var before := s.stats.duplicate()
		var gains := Progression.upgrade_group(s, Stats.PHYSICALITY, rng)
		var total := 0
		for st in Stats.ALL:
			var d: int = s.stats[st] - before[st]
			if Stats.group_of(st) != Stats.PHYSICALITY:
				check(d == 0, "upgrade touched %s outside the group" % st)
			else:
				check(d >= 0 and d <= Progression.MAX_STAT_GAIN_PER_UPGRADE, "%s gained %d" % [st, d])
				total += d
		check(total == 4 and gains.size() == 4, "physicality upgrade adds 4 points (got %d)" % total)
		check(s.group_rating(Stats.PHYSICALITY) == 51, "group rating rises by 1")
		check(s.skill_points == 100 - Progression.group_cost(50), "charged the group cost")
	# Caps and costs.
	var c := make_soldier(2, 50)
	c.group_caps[Stats.HANDLING] = 51
	c.skill_points = 100
	check(not Progression.upgrade_group(c, Stats.HANDLING, rng).is_empty(), "can upgrade below cap")
	check(Progression.is_capped(c, Stats.HANDLING), "capped after reaching cap")
	check(Progression.upgrade_group(c, Stats.HANDLING, rng).is_empty(), "cannot pass cap")
	check(Progression.upgrade_group(c, Stats.DURABILITY, rng).is_empty(), "durability not upgradable")
	check(Progression.group_cost(85) > Progression.group_cost(65), "cost scales with rating")
	c.skill_points = Progression.group_cost(50) - 1
	check(Progression.upgrade_group(c, Stats.MENTALITY, rng).is_empty(), "unaffordable upgrade refused")
	# Stats never pass 99.
	var top := make_soldier(3, 98)
	top.skill_points = 100
	Progression.upgrade_group(top, Stats.ACCURACY, rng)
	for st in Stats.group_stats(Stats.ACCURACY):
		check(top.stats[st] <= 99, "%s over 99" % st)


func test_auto_spend_prefers_role_groups() -> void:
	var s := make_soldier(1, 50)
	s.skill_points = 12
	var raised := Progression.auto_spend(s, Scheme.Role.FLEX)
	check(s.skill_points < Progression.group_cost(50), "spends until it can't afford more (left %d)" % s.skill_points)
	check(raised.size() > 0 and raised[0] == Stats.PHYSICALITY, "flex spends on physicality first (%s)" % [raised])
	var capped := make_soldier(2, 50)
	for g in Stats.UPGRADABLE_GROUPS:
		capped.group_caps[g] = capped.group_rating(g)
	capped.skill_points = 5
	Progression.auto_spend(capped, Scheme.Role.CENTER)
	check(capped.skill_points == 5, "fully capped player keeps points")


func test_training_intensity() -> void:
	var t := make_team(1, 50)
	for s in t.roster:
		s.age = 27
	t.roster[0].intensity = Soldier.INTENSITY_HEAVY
	t.roster[1].intensity = Soldier.INTENSITY_NORMAL
	t.roster[2].intensity = Soldier.INTENSITY_REST
	t.roster[3].injury_weeks = 2
	var reports := Training.run_week(t)
	check(reports[t.roster[0].id]["xp"] > reports[t.roster[1].id]["xp"], "heavy earns more xp than normal")
	var rest_xp: int = reports[t.roster[2].id]["xp"]
	check(rest_xp > 0 and rest_xp < reports[t.roster[1].id]["xp"] / 2, "rest earns a little film-study xp (%d)" % rest_xp)
	check(reports[t.roster[3].id]["intensity"] == &"film", "injured soldiers only study film")
	check(reports[t.roster[3].id]["xp"] == rest_xp, "film study xp matches rest")


func test_fatigue_model() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	check(Conditioning.penalty(30.0) < 0.01 and Conditioning.penalty(60.0) < 0.05, "little effect below 75")
	check(Conditioning.penalty(90.0) > 0.1, "steep effect above 75")
	var heavy := make_soldier(1, 60)
	heavy.intensity = Soldier.INTENSITY_HEAVY
	var rest := make_soldier(2, 60)
	rest.intensity = Soldier.INTENSITY_REST
	rest.fatigue = 60.0
	var t := Team.new()
	t.roster.append(heavy)
	t.roster.append(rest)
	heavy.stats[Stats.INJURY] = 99  # keep the test about fatigue
	rest.stats[Stats.INJURY] = 99
	Conditioning.end_week(t, {heavy.id: true}, false, rng)
	check(heavy.fatigue > 15.0, "match + heavy training builds fatigue (%.1f)" % heavy.fatigue)
	check(rest.fatigue < 40.0, "rest recovers (%.1f)" % rest.fatigue)
	# Settles below exhaustion for a normal-training starter with average endurance.
	var s := make_soldier(3, 60)
	for w in 30:
		s.fatigue = clampf(s.fatigue * (1.0 - Conditioning.weekly_recovery(s, false)) + Conditioning.weekly_load(s, true), 0.0, 100.0)
	check(s.fatigue > 40.0 and s.fatigue < 75.0, "normal starter equilibrium %.1f" % s.fatigue)
	var old := make_soldier(4, 60)
	old.age = 34
	check(Conditioning.weekly_load(old, true) > Conditioning.weekly_load(s, true), "age raises load")
	var tough := make_soldier(5, 60, {&"endurance": 90})
	check(Conditioning.weekly_load(tough, true) < Conditioning.weekly_load(s, true), "endurance lowers load")
	# Tired soldiers play worse.
	var fresh_team := make_team(6, 60)
	var tired_team := make_team(7, 60)
	for so in tired_team.roster:
		so.fatigue = 95.0
	check(win_rate(fresh_team, tired_team, 100, 7000) > 0.6, "fresh team beats an exhausted one")


func test_injury_model() -> void:
	check(Conditioning.base_injury_chance(99) < Conditioning.base_injury_chance(70), "higher Injury rating = fewer injuries")
	check(Conditioning.fatigue_injury_mult(90.0) > 2.5 and Conditioning.fatigue_injury_mult(40.0) == 1.0, "fatigue multiplies injury chance")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var tough_total := 0
	var soft_total := 0
	for i in 2000:
		tough_total += Conditioning.roll_injury_weeks(95, rng)
		soft_total += Conditioning.roll_injury_weeks(45, rng)
	check(soft_total > tough_total * 1.3, "low toughness = longer injuries (%d vs %d)" % [soft_total, tough_total])
	# Injured soldiers are skipped by auto_lineup and replaced by fill_injured.
	var t := make_team(1, 60)
	var star: Soldier = t.lineup[t.scheme.slot_ids()[0]]
	star.injury_weeks = 2
	check(t.fill_injured(), "fill_injured swaps the injured starter")
	check(not t.starters().has(star), "injured starter benched")
	t.auto_lineup()
	check(not t.starters().has(star), "auto_lineup skips injured")
	# Injury countdown.
	var weeks_before := star.injury_weeks
	Conditioning.end_week(t, {}, false, rng)
	check(star.injury_weeks == weeks_before - 1, "injury counts down weekly")


func test_match_awards_xp() -> void:
	var league := League.generate(3)
	var a := league.teams[0]
	var b := league.teams[1]
	var before := {}
	for s in a.starters() + b.starters():
		before[s.id] = s.level * 100000 + s.xp
	# Age/potential multipliers dominate xp here, so this seed must be one the high-xp side (team 1) wins.
	var r := MatchEngine.simulate(a, b, 2)
	var reports := Progression.award_match_xp(r)
	check(reports.size() == 10, "all 10 starters get xp")
	for s in a.starters() + b.starters():
		check(s.level * 100000 + s.xp > before[s.id], "%s gained xp" % s.full_name())
		check(s.career["matches"] == 1, "career match recorded")
	var w_xp := 0
	var l_xp := 0
	for s in r.winner().starters():
		w_xp += reports[s.id]["xp"]
	for s in r.loser().starters():
		l_xp += reports[s.id]["xp"]
	check(w_xp > l_xp, "winners earn more xp in total")
