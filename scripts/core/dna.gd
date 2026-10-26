class_name Dna
extends RefCounted
## Player DNA: who a soldier is at the negotiating table (all 0-99, shown on the player card).
##
## Motivations - what he wants from a contract:
##   money (salary), winning (a contender), playing time (starting), loyalty (staying with his
##   club), security (long deals), hometown (playing near home: his home state, then his region).
## Temperament - how he takes hardball: high = thick-skinned, low = takes criticism personally.
## Savvy - negotiating smarts: high = demands closer to his real market value, respects evidence
##   and pushes back on weak arguments.
##
## Rolled once from the soldier id (its own RNG, so it never disturbs the league RNG). Young
## players lean money / playing time, veterans lean winning / security.

const MOTIVATIONS: Array[StringName] = [&"money", &"winning", &"playing_time", &"loyalty", &"security", &"hometown"]
const LABELS := {&"money": "Money", &"winning": "Winning", &"playing_time": "Playing Time", &"loyalty": "Loyalty",
	&"security": "Security", &"hometown": "Hometown", &"temperament": "Temperament", &"savvy": "Savvy"}
const BLURBS := {&"money": "chases the biggest paycheck", &"winning": "wants to play for a contender",
	&"playing_time": "needs to start", &"loyalty": "values staying with his club", &"security": "wants a long, safe deal",
	&"hometown": "wants to play close to home"}

var money := 50
var winning := 50
var playing_time := 50
var loyalty := 50
var security := 50
var hometown := 50
var temperament := 50
var savvy := 50


static func generate(id: int, age: int) -> Dna:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([id, 0xD7A])
	var d := Dna.new()
	var youth := clampf((28.0 - age) / 8.0, -1.0, 1.0)  # +1 young, -1 veteran
	d.money = _roll(rng, 8.0 * youth)
	d.winning = _roll(rng, -12.0 * youth)
	d.playing_time = _roll(rng, 10.0 * youth)
	d.loyalty = _roll(rng, -6.0 * youth)
	d.security = _roll(rng, -10.0 * youth)
	d.temperament = _roll(rng, 0.0)
	d.savvy = _roll(rng, -8.0 * youth)
	d.hometown = _roll(rng, -4.0)
	# Give everyone a clear headline motivation.
	var lead: StringName = MOTIVATIONS[rng.randi_range(0, MOTIVATIONS.size() - 1)]
	d.set(lead, clampi(d.get(lead) + rng.randi_range(15, 30), 1, 99))
	return d


## 0..1: how much `s` wants to play for `team` because it's near home (full pull for his home
## state's club, half for a club in his home region), scaled by his Hometown motivation.
static func hometown_pull(s: Soldier, team: Team) -> float:
	if s.home_state == "" or team == null or team.home_state == "":
		return 0.0
	var near := 0.0
	if team.home_state == s.home_state:
		near = 1.0
	elif LeagueData.region_of(team.home_state) == LeagueData.region_of(s.home_state):
		near = 0.5
	return near * s.get_dna().n(&"hometown")


static func _roll(rng: RandomNumberGenerator, shift: float) -> int:
	return clampi(roundi((rng.randf_range(5.0, 95.0) + rng.randf_range(5.0, 95.0)) / 2.0 + shift), 1, 99)


func value(trait_name: StringName) -> int:
	return int(get(trait_name))


## 0..1 for the formulas.
func n(trait_name: StringName) -> float:
	return value(trait_name) / 99.0


## Motivations, strongest first.
func ranked() -> Array[StringName]:
	var out: Array[StringName] = MOTIVATIONS.duplicate()
	out.sort_custom(func(a, b): return value(a) > value(b))
	return out


func headline() -> String:
	var r := ranked()
	return "%s, then %s" % [LABELS[r[0]], LABELS[r[1]].to_lower()]


func temperament_label() -> String:
	if temperament >= 70:
		return "Thick-skinned"
	if temperament <= 30:
		return "Thin-skinned"
	return "Even-keeled"


func savvy_label() -> String:
	if savvy >= 70:
		return "Sharp negotiator"
	if savvy <= 30:
		return "Naive negotiator"
	return "Average negotiator"
