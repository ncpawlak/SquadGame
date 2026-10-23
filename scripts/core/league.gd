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
	return league


func all_soldiers() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for t in teams:
		out.append_array(t.roster)
	return out
