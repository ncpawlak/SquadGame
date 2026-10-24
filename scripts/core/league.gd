class_name League
extends RefCounted
## Container for teams. Milestone 1 uses 2 teams + single matches; a full league/season comes next.

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
		var quality := league.rng.randf_range(62.0, 74.0)
		t.roster = PlayerGenerator.generate_roster(league.rng, league.next_soldier_id, quality)
		league.next_soldier_id += t.roster.size()
		t.auto_lineup()
		league.teams.append(t)
	if not league.teams.is_empty():
		league.teams[0].user_controlled = true
	league.ensure_callsigns()
	return league


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


func team_of(s: Soldier) -> Team:
	for t in teams:
		if t.roster.has(s):
			return t
	return null
