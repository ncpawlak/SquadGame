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
	"SEA": {"age": 24, "spread": 0.9, "pot": 0.45, "pay": 0.9, "groups": {&"objective": 4, &"mentality": 3, &"accuracy": 1, &"physicality": -2}},
	"ARL": {"age": 27, "spread": 1.2, "pot": 0.1, "pay": 1.05, "groups": {&"accuracy": 4, &"handling": 2, &"objective": -3}},
	"CHI": {"age": 24, "spread": 1.0, "pot": 0.4, "pay": 0.95, "groups": {&"physicality": 4, &"handling": 1, &"mentality": -1}},
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
	["DET", 1, "Marcus", "Hale", "Anvil", 35, 95, 0, 13500, 1, 0, {"winning": 97, "loyalty": 94, "temperament": 85}],
	["BKN", 2, "Jalen", "Brooks", "Prodigy", 20, 86, 4, 4800, 3, 2025, {"playing_time": 80}],
	["ORL", 0, "Mateo", "Rivera", "Spark", 20, 80, 4, 4200, 3, 2025, {"money": 70}],
	["NYE", 0, "Andre", "Mercer", "Kingpin", 28, 98, 2, 20000, 4, 0, {"money": 92}],
	["NYE", 1, "Viktor", "Thorne", "Czar", 27, 97, 2, 19500, 3, 0, {"money": 85}],
	["LAS", 2, "Dante", "Cruz", "Hollywood", 26, 97, 3, 20000, 4, 0, {"money": 90, "temperament": 22}],
	["BOS", 1, "Silas", "Brennan", "Professor", 33, 94, 1, 12500, 2, 0, {"winning": 92}],
	["SEA", 1, "Kenji", "Ueda", "Oracle", 23, 90, 4, 8000, 4, 0, {}],
	["ORL", 5, "Bryce", "Kendall", "Payday", 31, 75, 1, 12500, 3, 0, {"money": 95}],
	["ORL", 6, "Grant", "Holloway", "Ledger", 32, 73, 0, 11000, 2, 0, {"money": 90, "security": 85}],
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
		var s := _make(roles[i % 3], rng.randi_range(64, 77), age, {})
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
	quit(0)


func _build_roster(t: Team, row: Array) -> void:
	var style: Dictionary = STYLE[t.abbrev]
	var target: int = row[7]
	var targets: Array = []
	var story_slots := {}
	for st in STORIES:
		if st[0] == t.abbrev:
			story_slots[st[1]] = st
	for i in SLOTS.size():
		var off: float = SLOTS[i][1] * float(style["spread"])
		targets.append(clampf(target + off + rng.randfn(0.0, 1.0), 55.0, 99.0))
	for i in story_slots:
		targets[i] = float(story_slots[i][6])
	# Shift the non-story targets so the roster averages the team rating.
	var free_n := SLOTS.size() - story_slots.size()
	for pass_i in 4:
		var mean := 0.0
		for v in targets:
			mean += v
		mean /= targets.size()
		var fix := (target - mean) * SLOTS.size() / free_n
		for i in targets.size():
			if not story_slots.has(i):
				targets[i] = clampf(targets[i] + fix, 55.0, 99.0)
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
			var age := clampi(roundi(float(style["age"]) + rng.randfn(0.0, 3.0) - (1.5 if i >= 8 else 0.0)), 19, 36)
			s = _make(role, roundi(targets[i]), age, style["groups"])
			if rng.randf() < float(style["pot"]):
				s.potential = mini(Soldier.POTENTIAL_A, s.potential + 1)
				PlayerGenerator.roll_caps(s, rng)
			var r := rng.randf()
			s.home_state = t.home_state if r < 0.25 else (LeagueData.random_state(rng, t.division) if r < 0.55 else LeagueData.random_state(rng))
			_contract(s, float(style["pay"]))
		t.roster.append(s)
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
	for g in groups:
		for st in Stats.group_stats(g):
			s.stats[st] = Stats.clamp_rating(s.stats[st] + groups[g] + rng.randi_range(-1, 1))
	_fit(s, ovr)
	if potential >= 0:
		s.potential = potential
	PlayerGenerator.roll_caps(s, rng)
	s.look = Look.generate(s.id, s.age, Scheme.best_role(s.stats))
	s.dna = Dna.generate(s.id, s.age)
	return s


## Moves every rating (bar the durability pair) together until best OVR hits `ovr`.
func _fit(s: Soldier, ovr: int) -> void:
	for i in 80:
		var d := ovr - s.best_ovr()
		if d == 0:
			return
		var step := clampi(d, -2, 2)
		var moved := false
		for st in Stats.ALL:
			if st == Stats.INJURY or st == Stats.TOUGHNESS:
				continue
			var v := clampi(int(s.stats[st]) + step, 30, Stats.MAX_RATING)
			moved = moved or v != s.stats[st]
			s.stats[st] = v
		if not moved:
			return


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
