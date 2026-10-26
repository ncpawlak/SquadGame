class_name League
extends RefCounted
## Container for teams and free agents. The franchise league is the fixed 20-team league loaded
## from data/league.json (see LeagueData); `generate` builds a small random league (exhibitions
## of old, and the compact test fixture).

const CITIES := [
	"Boston", "Denver", "Austin", "Seattle", "Chicago", "Atlanta", "Phoenix", "Detroit",
	"Portland", "Miami", "Toronto", "Nashville",
]
const NICKNAMES := [
	"Vipers", "Wardens", "Outlaws", "Sentinels", "Raptors", "Ironclads", "Phantoms", "Hammers",
	"Reapers", "Titans", "Spectres", "Marauders",
]
const COLORS := [
	Color("#3b82f6"), Color("#ef4444"), Color("#22c55e"), Color("#eab308"),
	Color("#a855f7"), Color("#f97316"), Color("#14b8a6"), Color("#ec4899"),
	Color("#64748b"), Color("#84cc16"), Color("#06b6d4"), Color("#f43f5e"),
]

## Accent palette that secondary_for() chooses from.
const SECONDARY_COLORS := [Color("#f8fafc"), Color("#111827"), Color("#facc15"), Color("#94a3b8"),
	Color("#1e3a8a"), Color("#7f1d1d"), Color("#14532d"), Color("#fb923c")]

var league_seed: int
var rng := RandomNumberGenerator.new()
var teams: Array[Team] = []
var next_soldier_id := 1
## Unsigned soldiers: undrafted prospects, cuts and expired contracts.
var free_agents: Array[Soldier] = []


static func generate(seed_value: int, team_count := 2) -> League:
	var league := League.new()
	league.league_seed = seed_value
	league.rng.seed = seed_value
	for i in team_count:
		var t := Team.new()
		t.id = i + 1
		t.name = "%s %s" % [CITIES[i % CITIES.size()], NICKNAMES[i % NICKNAMES.size()]]
		t.abbrev = CITIES[i % CITIES.size()].left(3).to_upper()
		t.color = COLORS[i % COLORS.size()]
		t.color2 = secondary_for(t.color, i)
		var quality := league.rng.randf_range(70.0, 82.0)
		t.roster = PlayerGenerator.generate_roster(league.rng, league.next_soldier_id, quality)
		league.next_soldier_id += t.roster.size()
		for s in t.roster:
			s.home_state = LeagueData.random_state(league.rng)
		t.auto_lineup()
		league.teams.append(t)
	if not league.teams.is_empty():
		league.teams[0].user_controlled = true
	league.ensure_callsigns()
	return league


const DATA_PATH := "res://data/league.json"


## The fixed franchise league: every team, player and free agent from data/league.json.
static func load_fixed(seed_value: int, path := DATA_PATH) -> League:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("League data missing or invalid: %s" % path)
		return generate(seed_value, LeagueData.TEAMS.size())
	var league := League.new()
	league.league_seed = seed_value
	league.rng.seed = seed_value
	for i in LeagueData.TEAMS.size():
		league.teams.append(team_from_row(LeagueData.TEAMS[i], i + 1))
	var by_abbrev := {}
	for t in league.teams:
		by_abbrev[t.abbrev] = t
	var max_id := 0
	for d: Dictionary in data["players"]:
		var s := soldier_from_dict(d)
		max_id = maxi(max_id, s.id)
		var team: Team = by_abbrev.get(String(d.get("team", "")))
		if team != null:
			team.roster.append(s)
		else:
			league.free_agents.append(s)
			s.fa_since = int(d.get("fa_since", 0))
	league.next_soldier_id = max_id + 1
	for t in league.teams:
		t.auto_lineup()
	league.ensure_callsigns()
	return league


static func team_from_row(row: Array, id: int) -> Team:
	var t := Team.new()
	t.id = id
	t.abbrev = row[0]
	t.city = row[1]
	t.nickname = row[2]
	t.name = "%s %s" % [row[1], row[2]]
	t.color = Color(row[3])
	t.color2 = Color(row[4])
	t.division = row[5]
	t.home_state = row[6]
	t.backstory = row[8]
	return t


## A soldier from his league.json entry (stats keyed by Stats abbreviations, caps by group).
static func soldier_from_dict(d: Dictionary) -> Soldier:
	var s := Soldier.new()
	s.id = int(d["id"])
	s.first_name = d["first"]
	s.last_name = d["last"]
	s.callsign = d.get("callsign", "")
	s.age = int(d["age"])
	s.home_state = d.get("state", "")
	s.potential = int(d["potential"])
	s.draft_year = int(d.get("draft_year", 0))
	var st: Dictionary = d["stats"]
	for k in Stats.ALL:
		s.stats[k] = int(st.get(Stats.ABBREV[k], 60))
	var caps: Dictionary = d["caps"]
	for g in Stats.UPGRADABLE_GROUPS:
		s.group_caps[g] = int(caps.get(String(g), s.group_rating(g)))
	if d.has("salary"):
		s.contract = Contract.make(int(d["salary"]), int(d["years"]), int(d.get("signed", 2026)), bool(d.get("rookie", false)))
	if d.has("dna"):
		var dna := Dna.new()
		for k: String in d["dna"]:
			dna.set(k, int(d["dna"][k]))
		s.dna = dna
	s.look = Look.generate(s.id, s.age, Scheme.best_role(s.stats))
	return s


## Auto-picks a contrasting accent colour for `primary` (deterministic per team index).
static func secondary_for(primary: Color, index: int) -> Color:
	var ok: Array[Color] = []
	for c: Color in SECONDARY_COLORS:
		var hue_gap := absf(c.h - primary.h)
		hue_gap = minf(hue_gap, 1.0 - hue_gap)
		var contrast := absf(c.get_luminance() - primary.get_luminance())
		if contrast >= 0.28 or (c.s > 0.3 and hue_gap > 0.18 and contrast >= 0.12):
			ok.append(c)
	if ok.is_empty():
		return Color("#111827") if primary.get_luminance() > 0.5 else Color("#f8fafc")
	return ok[(index * 7 + 3) % ok.size()]


func all_soldiers() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for t in teams:
		out.append_array(t.roster)
	return out


## Puts a soldier into the free-agent pool (clearing his contract).
func add_free_agent(s: Soldier, year: int) -> void:
	s.contract = null
	s.fa_since = year
	s.ask_mult = 1.0
	s.injury_weeks = 0
	s.injury_name = ""
	if not free_agents.has(s):
		free_agents.append(s)
	give_callsign(s)


## Lower-cased callsigns of every active soldier (rosters and free agents).
func taken_callsigns(except: Soldier = null) -> Dictionary:
	var out := {}
	for s in all_soldiers():
		if s != except and s.callsign != "":
			out[s.callsign.to_lower()] = true
	for s in free_agents:
		if s != except and s.callsign != "":
			out[s.callsign.to_lower()] = true
	return out


## Gives `s` a callsign if he doesn't have one (or his is taken by someone else).
func give_callsign(s: Soldier) -> void:
	var taken := taken_callsigns(s)
	if s.callsign == "" or taken.has(s.callsign.to_lower()):
		s.callsign = Callsigns.pick(s, taken)


## Safety net: every active soldier gets a unique callsign.
func ensure_callsigns() -> void:
	var taken := {}
	var pool: Array[Soldier] = all_soldiers()
	pool.append_array(free_agents)
	for s in pool:
		if s.callsign == "" or taken.has(s.callsign.to_lower()):
			s.callsign = Callsigns.pick(s, taken)
		taken[s.callsign.to_lower()] = true


func team_by_abbrev(abbrev: String) -> Team:
	for t in teams:
		if t.abbrev == abbrev:
			return t
	return null


func team_of(s: Soldier) -> Team:
	for t in teams:
		if t.roster.has(s):
			return t
	return null
