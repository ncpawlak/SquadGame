extends SceneTree
## One-time authoring tool for the fixed league: writes data/league.json (every rostered player
## and the opening free-agent pool). The game never runs this; it only loads the JSON. Re-running
## it replaces the league, so only do that on purpose.
##   godot --headless --path . -s tools/build_league.gd
##
## Each roster is shaped to its franchise: average OVR = the team's rating, stat leanings and
## age profile from its backstory, payroll from its finances, plus the story players.

const OUT := "res://data/league.json"
const YEAR := 2026
const SEED := 20260517

## Roster template (role, OVR offset from the team rating): 5 starters, 3 backups, 4 reserves.
const SLOTS := [
	[Scheme.Role.FRONTMAN, 5], [Scheme.Role.CENTER, 5], [Scheme.Role.FLEX, 4], [Scheme.Role.FRONTMAN, 3], [Scheme.Role.FLEX, 3],
	[Scheme.Role.FRONTMAN, 0], [Scheme.Role.CENTER, -1], [Scheme.Role.FLEX, -1],
	[Scheme.Role.FRONTMAN, -4], [Scheme.Role.FLEX, -4], [Scheme.Role.CENTER, -5], [Scheme.Role.FLEX, -5],
]

## abbrev -> {age (mean), spread (offset multiplier), pot (chance of +1 potential), pay (salary
## multiplier), groups (stat leanings by group)}.
const STYLE := {
	"NYE": {"age": 28, "spread": 1.2, "pot": 0.0, "pay": 1.18, "groups": {&"accuracy": 2, &"handling": 2}},
	"DET": {"age": 29, "spread": 0.9, "pot": 0.15, "pay": 1.0, "groups": {&"mentality": 3, &"durability": 3, &"objective": 2, &"physicality": -1}},
	"LAS": {"age": 27, "spread": 1.8, "pot": 0.0, "pay": 1.2, "groups": {&"accuracy": 4, &"physicality": 1, &"mentality": -3}},
	"BOS": {"age": 31, "spread": 1.0, "pot": 0.0, "pay": 1.05, "groups": {&"mentality": 4, &"objective": 2, &"physicality": -2}},
	"SEA": {"age": 25, "spread": 0.9, "pot": 0.45, "pay": 0.9, "groups": {&"objective": 4, &"mentality": 3, &"accuracy": 1, &"physicality": -2}},
	"ARL": {"age": 27, "spread": 1.2, "pot": 0.1, "pay": 1.05, "groups": {&"accuracy": 4, &"handling": 2, &"objective": -3}},
	"CHI": {"age": 25, "spread": 1.0, "pot": 0.4, "pay": 0.95, "groups": {&"physicality": 4, &"handling": 1, &"mentality": -1}},
	"STL": {"age": 26, "spread": 0.5, "pot": 0.2, "pay": 0.95, "groups": {&"mentality": 3, &"durability": 2, &"objective": 2, &"accuracy": -2}},
	"CHA": {"age": 26, "spread": 1.0, "pot": 0.25, "pay": 1.0, "groups": {&"handling": 1, &"mentality": 1}},
	"SDV": {"age": 26, "spread": 1.2, "pot": 0.2, "pay": 1.0, "groups": {&"accuracy": 3, &"physicality": 2, &"mentality": -3}},
	"REN": {"age": 28, "spread": 0.8, "pot": 0.1, "pay": 0.75, "groups": {&"mentality": 3, &"handling": 1}},
	"ATL": {"age": 28, "spread": 0.8, "pot": 0.1, "pay": 1.0, "groups": {&"durability": 4, &"physicality": 2, &"objective": 1, &"accuracy": -2}},
	"IND": {"age": 24, "spread": 1.0, "pot": 0.35, "pay": 0.9, "groups": {&"physicality": 5, &"mentality": -2}},
	"MIA": {"age": 27, "spread": 1.4, "pot": 0.1, "pay": 1.05, "groups": {&"accuracy": 2, &"handling": 1, &"mentality": -3}},
	"DEN": {"age": 31, "spread": 0.9, "pot": 0.0, "pay": 1.35, "groups": {&"durability": 2, &"objective": 2, &"physicality": -3}},
	"BKN": {"age": 24, "spread": 1.0, "pot": 0.35, "pay": 0.9, "groups": {&"physicality": 1, &"mentality": -1}},
	"NSH": {"age": 23, "spread": 1.1, "pot": 0.45, "pay": 0.9, "groups": {&"accuracy": 3, &"handling": 2, &"mentality": -4, &"objective": -1}},
	"LOU": {"age": 24, "spread": 0.9, "pot": 0.35, "pay": 0.85, "groups": {}},
	"ORL": {"age": 28, "spread": 1.1, "pot": 0.05, "pay": 1.4, "groups": {&"mentality": -2}},
	"LRK": {"age": 23, "spread": 0.9, "pot": 0.55, "pay": 0.85, "groups": {&"objective": 1}},
}

## Story players: [team, slot, first, last, callsign, age, ovr, potential, salary $K (0 = market),
## years, draft_year, dna overrides].
const STORIES := [
	["DET", 1, "Marcus", "Hale", "Anvil", 35, 87, 0, 13500, 1, 0, {"winning": 97, "loyalty": 94, "temperament": 85}],
	["BKN", 2, "Jalen", "Brooks", "Prodigy", 20, 76, 4, 4800, 3, 2025, {"playing_time": 80}],
	["ORL", 0, "Mateo", "Rivera", "Spark", 20, 71, 4, 4200, 3, 2025, {"money": 70}],
	["NYE", 0, "Andre", "Mercer", "Kingpin", 28, 92, 2, 20000, 4, 0, {"money": 92}],
	["NYE", 1, "Viktor", "Thorne", "Czar", 27, 89, 2, 19500, 3, 0, {"money": 85}],
	["LAS", 2, "Dante", "Cruz", "Hollywood", 26, 91, 3, 20000, 4, 0, {"money": 90, "temperament": 22}],
	["BOS", 1, "Silas", "Brennan", "Professor", 33, 86, 1, 12500, 2, 0, {"winning": 92}],
	["SEA", 1, "Kenji", "Ueda", "Oracle", 23, 82, 4, 8000, 4, 0, {}],
	["ORL", 5, "Bryce", "Kendall", "Payday", 31, 67, 1, 12500, 3, 0, {"money": 95}],
	["ORL", 6, "Grant", "Holloway", "Ledger", 32, 65, 0, 11000, 2, 0, {"money": 90, "security": 85}],
]

var rng := RandomNumberGenerator.new()
var next_id := 1
var used_names := {}


func _init() -> void:
	rng.seed = SEED
	var league := League.new()
	var teams_out := {}
	for i in LeagueData.TEAMS.size():
		var row: Array = LeagueData.TEAMS[i]
		var t := League.team_from_row(row, i + 1)
		_build_roster(t, row)
		league.teams.append(t)
	for i in 30:
		var roles := [Scheme.Role.FRONTMAN, Scheme.Role.CENTER, Scheme.Role.FLEX]
		var age := rng.randi_range(22, 34)
		var s := _make(roles[i % 3], rng.randi_range(56, 70), age, {})
		s.home_state = LeagueData.random_state(rng)
		league.free_agents.append(s)
	league.ensure_callsigns()
	var lines: PackedStringArray = []
	for t in league.teams:
		for s in t.roster:
			lines.append(JSON.stringify(_dict(s, t.abbrev)))
	for s in league.free_agents:
		var d := _dict(s, "")
		d["fa_since"] = YEAR - 1
		lines.append(JSON.stringify(d))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data"))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("{\"version\": 1, \"year\": %d, \"players\": [\n%s\n]}\n" % [YEAR, ",\n".join(lines)])
	f.close()
	for t in league.teams:
		var row := LeagueData.team_row(t.abbrev)
		var pay := 0
		for s in t.roster:
			pay += s.contract.salary
		var top: Array = t.roster.map(func(x: Soldier): return x.best_ovr())
		top.sort()
		print("%s  target %d  ovr %d  payroll %s  ages %.1f  top %s" % [t.abbrev, row[7], t.team_ovr(), Contracts.money(pay),
			t.roster.reduce(func(a, x): return a + x.age, 0) / 12.0, top.slice(-3)])
	_report(league)
	quit(0)


func _report(league: League) -> void:
	var n99 := 0
	var n90g := 0
	var all90 := 0
	var ovr90 := 0
	var young := []
	var by_age := {}
	var players := 0
	for t in league.teams:
		for s in t.roster:
			players += 1
			var hi := 0
			for st in Stats.ALL:
				if Stats.group_of(st) != Stats.DURABILITY and s.stats[st] >= 99:
					n99 += 1
			for g in Stats.UPGRADABLE_GROUPS:
				if s.group_rating(g) >= 90:
					hi += 1
			n90g += hi
			all90 += 1 if hi == Stats.UPGRADABLE_GROUPS.size() else 0
			ovr90 += 1 if s.best_ovr() >= 90 else 0
			var band := mini(s.age / 3 * 3, 33)
			if not by_age.has(band):
				by_age[band] = []
			by_age[band].append(s.best_ovr())
			if s.age <= 21:
				young.append(s.best_ovr())
	print("players %d  stats@99 %d  groups90+ %d  all-groups90+ %d  OVR90+ %d" % [players, n99, n90g, all90, ovr90])
	young.sort()
	print("age<=21: n %d  %s" % [young.size(), young])
	var keys := by_age.keys()
	keys.sort()
	for k in keys:
		var arr: Array = by_age[k]
		print("age %d-%d: n %d  avg %.1f  max %d" % [k, k + 2, arr.size(), arr.reduce(func(a, x): return a + x, 0) / float(arr.size()), arr.max()])


func _build_roster(t: Team, row: Array) -> void:
	var style: Dictionary = STYLE[t.abbrev]
	var target: int = row[7]
	var targets: Array = []
	var top_cap := 88.0 if target >= 80 else 86.0
	var story_slots := {}
	for st in STORIES:
		if st[0] == t.abbrev:
			story_slots[st[1]] = st
	for i in SLOTS.size():
		var off: float = SLOTS[i][1] * float(style["spread"])
		targets.append(clampf(target + off + rng.randfn(0.0, 1.0), 50.0, top_cap))
	for i in story_slots:
		targets[i] = float(story_slots[i][6])
	# Ages first: young players land in the lowest slots and are held to the age curve, so a
	# great 20-year-old is a rare story rather than the norm. Prime-age players carry the rest.
	var ages := {}
	var free: Array = []
	for i in SLOTS.size():
		if not story_slots.has(i):
			ages[i] = clampi(roundi(float(style["age"]) + rng.randfn(0.0, 3.0) - (1.5 if i >= 8 else 0.0)), 23 if target >= 82 else 19, 36)
			free.append(i)
	var by_age: Array = free.map(func(i): return ages[i])
	by_age.sort()
	var by_target := free.duplicate()
	by_target.sort_custom(func(a, b): return targets[a] < targets[b])
	var young_n := by_age.filter(func(a): return a <= 22).size()
	for k in young_n:
		ages[by_target[k]] = by_age[k]
	var rest: Array = by_age.slice(young_n)
	for k in range(rest.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp = rest[k]
		rest[k] = rest[j]
		rest[j] = tmp
	for k in range(young_n, by_target.size()):
		ages[by_target[k]] = rest[k - young_n]
	var fixed := story_slots.duplicate()
	for i in free:
		var cap := _age_cap(ages[i])
		if targets[i] > cap:
			targets[i] = cap
			fixed[i] = true
	# Shift the other targets so the roster averages the team rating.
	for pass_i in 6:
		var mean := 0.0
		for v in targets:
			mean += v
		mean /= targets.size()
		var adj: Array = free.filter(func(i): return not fixed.has(i) and (targets[i] < top_cap or mean > target))
		if adj.is_empty():
			break
		var fix := (target - mean) * SLOTS.size() / adj.size()
		for i in adj:
			targets[i] = clampf(targets[i] + fix, 50.0, top_cap)
	for i in SLOTS.size():
		var role: Scheme.Role = SLOTS[i][0]
		var s: Soldier
		if story_slots.has(i):
			var st: Array = story_slots[i]
			s = _make(role, st[6], st[5], style["groups"], st[7])
			s.first_name = st[2]
			s.last_name = st[3]
			s.callsign = st[4]
			used_names["%s %s" % [st[2], st[3]]] = true
			s.draft_year = st[10]
			var salary: int = st[8] if st[8] > 0 else Contracts.market_value(s)
			s.contract = Contract.make(salary, st[9], YEAR - (YEAR - st[10] if st[10] > 0 else 1), st[10] > 0)
			var dna := s.get_dna()
			for k in st[11]:
				dna.set(k, st[11][k])
			s.home_state = t.home_state if rng.randf() < 0.5 else LeagueData.random_state(rng, t.division)
		else:
			s = _make(role, roundi(targets[i]), ages[i], style["groups"])
			if rng.randf() < float(style["pot"]):
				s.potential = mini(Soldier.POTENTIAL_A, s.potential + 1)
				PlayerGenerator.roll_caps(s, rng)
			var r := rng.randf()
			s.home_state = t.home_state if r < 0.25 else (LeagueData.random_state(rng, t.division) if r < 0.55 else LeagueData.random_state(rng))
			_contract(s, float(style["pay"]))
		t.roster.append(s)
	_set_potentials(t, target, story_slots)
	# Keep everyone under the cap (the big spenders sit just below it).
	var total := 0
	for s in t.roster:
		total += s.contract.salary
	var limit := int(Contracts.SALARY_CAP * 0.97)
	if total > limit:
		var scale := float(limit) / total
		for s in t.roster:
			s.contract.salary = maxi(Contracts.MIN_SALARY, roundi(s.contract.salary * scale / 10.0) * 10)
	t.auto_lineup()


## Most players grade C or lower: each team carries 2-4 A/B talents (better teams more),
## favouring the youngest and best. Story players keep their authored grades.
func _set_potentials(t: Team, target: int, story_slots: Dictionary) -> void:
	var want := clampi(2 + roundi((target - 65) / 10.0), 2, 4)
	var stories: Array = story_slots.keys().map(func(i): return t.roster[i])
	var have := t.roster.filter(func(s: Soldier): return s.potential >= 3).size()
	var pool: Array = t.roster.filter(func(s: Soldier): return not stories.has(s))
	var value := func(s: Soldier) -> float: return s.best_ovr() * 0.3 - s.age * 1.5 + s.potential
	pool.sort_custom(func(a: Soldier, b: Soldier): return value.call(a) > value.call(b))
	# Too many: demote the least promising A/B players.
	for k in range(pool.size() - 1, -1, -1):
		if have <= want:
			break
		var s: Soldier = pool[k]
		if s.potential >= 3:
			s.potential = 3 - 1 - (1 if rng.randf() < 0.3 else 0)
			PlayerGenerator.roll_caps(s, rng)
			have -= 1
	# Too few: promote the most promising.
	for s: Soldier in pool:
		if have >= want:
			break
		if s.potential < 3:
			s.potential = 3 if rng.randf() < 0.75 else Soldier.POTENTIAL_A
			PlayerGenerator.roll_caps(s, rng)
			have += 1


## Highest OVR a non-story player of this age starts at: around 60-66 through 21, then
## climbing into the prime (26-30), with a little noise.
func _age_cap(age: int) -> float:
	var base := 99.0
	if age <= 25:
		base = [60.0, 60.0, 63.0, 66.0, 71.0, 76.0, 81.0, 85.0][clampi(age - 18, 0, 7)]
	return base + rng.randfn(0.0, 2.5)


func _contract(s: Soldier, pay: float) -> void:
	if s.age <= 22 and rng.randf() < 0.75:
		s.draft_year = YEAR - 1 - rng.randi_range(0, maxi(0, s.age - 20))
		var pick := rng.randi_range(1, 60)
		var c := Contracts.rookie_contract(pick, 60, s.draft_year)
		c.years = maxi(1, c.years - (YEAR - 1 - s.draft_year))
		s.contract = c
		return
	var yrs := 1 if s.age >= 33 else (rng.randi_range(1, 2) if s.age >= 30 else rng.randi_range(1, 4))
	var salary := clampi(roundi(Contracts.market_value(s) * pay * rng.randf_range(0.85, 1.15) / 10.0) * 10, Contracts.MIN_SALARY, Contracts.MAX_SALARY)
	s.contract = Contract.make(salary, yrs, YEAR - rng.randi_range(0, 2))


func _make(role: Scheme.Role, ovr: int, age: int, groups: Dictionary, potential := -1) -> Soldier:
	var s := PlayerGenerator.generate(rng, next_id, role, float(ovr) - 4.0, age)
	next_id += 1
	while used_names.has(s.full_name()):
		s.first_name = PlayerGenerator.FIRST_NAMES[rng.randi_range(0, PlayerGenerator.FIRST_NAMES.size() - 1)]
		s.last_name = PlayerGenerator.LAST_NAMES[rng.randi_range(0, PlayerGenerator.LAST_NAMES.size() - 1)]
	used_names[s.full_name()] = true
	_shape(s, role, ovr, groups)
	if potential >= 0:
		s.potential = potential
	PlayerGenerator.roll_caps(s, rng)
	s.look = Look.generate(s.id, s.age, Scheme.best_role(s.stats))
	s.dna = Dna.generate(s.id, s.age)
	return s


## Tiered profile: one signature group above the rest, the role's core groups at the target and
## the two least useful groups well below it, so even stars have holes. Stats keep the generated
## archetype shape inside each group; durability is rolled on its own.
func _shape(s: Soldier, role: Scheme.Role, ovr: int, groups: Dictionary) -> void:
	var order: Array = Stats.UPGRADABLE_GROUPS.duplicate()
	var val := {}
	for g in order:
		val[g] = Progression.group_value(role, g) + float(groups.get(g, 0)) * 0.8 + rng.randf_range(0.0, 3.0)
	order.sort_custom(func(a, b): return val[a] > val[b])
	var off := {order[0]: rng.randf_range(2.0, 6.0), order[1]: 0.0, order[2]: rng.randf_range(-3.0, 0.0),
		order[3]: -rng.randf_range(5.0, 10.0), order[4]: -rng.randf_range(9.0, 16.0)}
	for g in order:
		var avg := Stats.group_average(s.stats, g)
		for st in Stats.group_stats(g):
			var shape := clampf(float(s.stats[st]) - avg, -7.0, 7.0)
			s.stats[st] = clampi(roundi(ovr + off[g] + shape + float(groups.get(g, 0)) * 0.5), 30, 97)
	s.stats[Stats.TOUGHNESS] = clampi(roundi(ovr - 6.0 + rng.randfn(0.0, 7.0) + float(groups.get(Stats.DURABILITY, 0))), 40, 97)
	s.stats[Stats.INJURY] = clampi(roundi(rng.randf_range(70.0, 94.0) + float(groups.get(Stats.DURABILITY, 0))), 55, 97)
	# Hit the target by moving the top three groups under a soft ceiling, then the holes (kept
	# under 90), then lift the ceiling: 99s and 90+ everywhere are only for the very top.
	var weak := [order[3], order[4]]
	for pass_i in 4:
		var ceiling := 96 if pass_i < 2 else Stats.MAX_RATING
		for i in 80:
			var d := ovr - s.best_ovr()
			if d == 0:
				break
			var step := clampi(d, -1, 1)
			var moved := false
			for st in Stats.ALL:
				var g := Stats.group_of(st)
				if g == Stats.DURABILITY or ((pass_i == 0 or pass_i == 2) and g in weak) or (pass_i == 1 and not g in weak):
					continue
				var top := 89 if pass_i == 1 else ceiling + (2 if g == order[0] else 0)
				var v := clampi(int(s.stats[st]) + step, 30, maxi(top, int(s.stats[st]) if step < 0 else top))
				moved = moved or v != s.stats[st]
				s.stats[st] = v
			if not moved:
				break
	if s.best_ovr() != ovr:
		push_warning("fit miss: %s wanted %d got %d" % [s.full_name(), ovr, s.best_ovr()])


func _dict(s: Soldier, team: String) -> Dictionary:
	var stats := {}
	for k in Stats.ALL:
		stats[Stats.ABBREV[k]] = int(s.stats[k])
	var caps := {}
	for g in Stats.UPGRADABLE_GROUPS:
		caps[String(g)] = s.group_cap(g)
	var dna := {}
	for k in Dna.MOTIVATIONS + [&"temperament", &"savvy"]:
		dna[String(k)] = s.get_dna().value(k)
	var d := {"id": s.id, "team": team, "first": s.first_name, "last": s.last_name, "callsign": s.callsign,
		"age": s.age, "state": s.home_state, "potential": s.potential, "draft_year": s.draft_year,
		"stats": stats, "caps": caps, "dna": dna}
	if s.contract != null:
		d["salary"] = s.contract.salary
		d["years"] = s.contract.years
		d["signed"] = s.contract.signed_year
		d["rookie"] = s.contract.rookie
	return d
