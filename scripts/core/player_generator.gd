class_name PlayerGenerator
extends RefCounted
## Builds soldiers from role archetypes plus noise. All randomness comes from the passed RNG.

const FIRST_NAMES := [
	"Alex", "Marcus", "Diego", "Tariq", "Jonah", "Wes", "Kai", "Nico", "Owen", "Rafael",
	"Ivan", "Luca", "Mateo", "Theo", "Andre", "Malik", "Hugo", "Felix", "Jasper", "Dante",
	"Ezra", "Silas", "Cole", "Rhys", "Bruno", "Kenji", "Omar", "Viktor", "Elias", "Sami",
	"Tomas", "Reed", "Jalen", "Arlo", "Cyrus", "Damon", "Emil", "Gage", "Hank", "Idris",
	"Jordan", "Tyler", "Caleb", "Isaiah", "Darius", "Trent", "Brody", "Colton", "Devin", "Garrett",
	"Jamal", "Keegan", "Landon", "Miles", "Nolan", "Pierce", "Quentin", "Rashad", "Shane", "Troy",
	"Victor", "Wyatt", "Xavier", "Zeke", "Aaron", "Beau", "Cody", "Derek", "Evan", "Finn",
	"Grady", "Hector", "Javier", "Kendrick", "Logan", "Mason", "Nate", "Oscar", "Preston", "Ray",
	"Santiago", "Travis", "Ulysses", "Vince", "Warren", "Yusuf", "Zach", "Brock", "Chase", "Dmitri",
]
const LAST_NAMES := [
	"Reyes", "Novak", "Okafor", "Lindqvist", "Hart", "Moreau", "Kowalski", "Tanaka", "Silva",
	"Brennan", "Vance", "Ortiz", "Petrov", "Haddad", "Fischer", "Mbeki", "Calloway", "Ruiz",
	"Sato", "Grant", "Ivers", "Duarte", "Kerr", "Lowe", "Mercer", "Nash", "Pike", "Quinn",
	"Rourke", "Stone", "Thorne", "Ueda", "Voss", "Wilder", "Yates", "Zane", "Bishop", "Cruz",
	"Adams", "Barrett", "Carver", "Dalton", "Ellison", "Foster", "Garza", "Holloway", "Ingram", "Jennings",
	"Keller", "Lawson", "Maddox", "Navarro", "O'Neal", "Palmer", "Ramsey", "Sutton", "Tate", "Underwood",
	"Vaughn", "Whitaker", "York", "Abbott", "Brooks", "Cannon", "Delgado", "Easton", "Fletcher", "Gibbs",
	"Hayes", "Irwin", "Jacobs", "Kimura", "Lockhart", "Mendez", "Nolan", "Oduya", "Park", "Rhodes",
	"Salazar", "Townsend", "Valdez", "Webb", "Boone", "Crawford", "Drake", "Fuentes", "Hale", "Knox",
]

## Stat offsets relative to the soldier's base quality.
const ARCHETYPES := {
	Scheme.Role.FRONTMAN: {
		&"short_acc": 10, &"strength": 9, &"toughness": 9, &"agility": 3, &"reload": 5,
		&"grouping": 4, &"composure": 3, &"long_acc": -6, &"medium_acc": -2, &"speed": -2,
		&"breach": 9, &"anchor": 2,
	},
	Scheme.Role.CENTER: {
		&"awareness": 10, &"medium_acc": 9, &"long_acc": 8, &"teamwork": 9, &"composure": 6,
		&"short_acc": -3, &"speed": -6, &"anchor": 9, &"obj_iq": 5, &"breach": -4, &"sway": 6,
	},
	Scheme.Role.FLEX: {
		&"speed": 11, &"agility": 10, &"endurance": 8, &"medium_acc": 4, &"short_acc": 2,
		&"reload": 3, &"strength": -6, &"toughness": -6, &"long_acc": -4,
		&"obj_iq": 7, &"breach": 3, &"anchor": -5, &"sway": 2,
	},
}

const MIN_AGE := 19
const MAX_AGE := 34


## quality: rough centre of the soldier's ratings (e.g. 55 = average pro, 70 = star).
static func generate(rng: RandomNumberGenerator, id: int, role: Scheme.Role, quality: float, age := -1) -> Soldier:
	var s := Soldier.new()
	s.id = id
	s.first_name = FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)]
	s.last_name = LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)]
	s.age = age if age > 0 else rng.randi_range(MIN_AGE, MAX_AGE)

	# Younger players are rawer now but have more room to grow.
	var age_quality_shift := 0.0
	if s.age <= 22:
		age_quality_shift = -6.0
	elif s.age <= 25:
		age_quality_shift = -2.0
	elif s.age >= 30:
		age_quality_shift = 2.0

	var archetype: Dictionary = ARCHETYPES[role]
	for stat in Stats.ALL:
		var base := quality + age_quality_shift + float(archetype.get(stat, 0))
		if stat == Stats.INJURY:
			base = rng.randf_range(70.0, 95.0)
		s.stats[stat] = Stats.clamp_rating(base + rng.randfn(0.0, 6.0))
	s.dev = roll_dev(rng, s.age)
	roll_caps(s, rng)
	s.look = Look.generate(s.id, s.age, role)
	return s


## Chance weights for 1-4 dev stars by age band: young players skew a little higher; 3 and 4
## stars stay rare (about 15% / 5% league-wide).
const DEV_WEIGHTS := [
	[22, [34, 42, 17, 7]],
	[26, [38, 42, 15, 5]],
	[30, [44, 39, 13, 4]],
	[99, [50, 36, 11, 3]],
]
## Cap headroom multiplier per dev star (1..4). Kept loose on purpose: a per-player ceiling roll
## (CEILING_ROLL) also scales it, so a 1-2 star player can still have a high ceiling (see #33).
const DEV_HEADROOM := [0.8, 1.0, 1.25, 1.5]
const CEILING_ROLL := [0.5, 1.5]


static func roll_dev(rng: RandomNumberGenerator, age: int) -> int:
	for band in DEV_WEIGHTS:
		if age <= band[0]:
			var weights: Array = band[1]
			var total := 0
			for w in weights:
				total += w
			var roll := rng.randi_range(1, total)
			for i in weights.size():
				roll -= weights[i]
				if roll <= 0:
					return Soldier.DEV_MIN + i
	return Soldier.DEV_MIN


## Highest cap allowed outside a soldier's top ELITE_GROUPS groups: everyone keeps a hole or two.
const NON_ELITE_CAP := 84
const ELITE_GROUPS := 2


## Rolls every group cap: age-based headroom x the dev multiplier x a per-player ceiling roll x a
## random per-group factor, so faster developers tend to have more room but a slow developer can
## still have a high ceiling, and which groups get the room is random.
## Only the two highest caps may go past NON_ELITE_CAP (a group already above it keeps its rating).
static func roll_caps(s: Soldier, rng: RandomNumberGenerator, extra := 0) -> void:
	var mult: float = DEV_HEADROOM[clampi(s.dev, Soldier.DEV_MIN, Soldier.DEV_MAX) - Soldier.DEV_MIN] * rng.randf_range(CEILING_ROLL[0], CEILING_ROLL[1])
	for g in Stats.UPGRADABLE_GROUPS:
		var room: float = float(roll_group_headroom(rng, s.age, g)) * mult * rng.randf_range(0.3, 1.7)
		s.group_caps[g] = mini(Stats.MAX_RATING, s.group_rating(g) + roundi(room) + extra)
	limit_elite_caps(s)


## Raises caps (top groups first, every group by one per pass) until his ceiling reaches
## `min_ceiling` or nothing can move. For draft standouts promised a high Potential grade.
static func raise_ceiling(s: Soldier, min_ceiling: int) -> void:
	for i in 40:
		if s.potential_ovr() >= min_ceiling:
			return
		for g in Stats.UPGRADABLE_GROUPS:
			s.group_caps[g] = mini(Stats.MAX_RATING, s.group_cap(g) + 1)
		limit_elite_caps(s)


## Holds every group outside the top ELITE_GROUPS caps to NON_ELITE_CAP (or its current rating).
static func limit_elite_caps(s: Soldier) -> void:
	var order: Array = Stats.UPGRADABLE_GROUPS.duplicate()
	order.sort_custom(func(a, b): return s.group_cap(a) > s.group_cap(b))
	for g in order.slice(ELITE_GROUPS):
		s.group_caps[g] = maxi(s.group_rating(g), mini(s.group_cap(g), NON_ELITE_CAP))


## Group cap headroom by age. Physical growth ends ~28, skills ~30, mentality ~33.
static func roll_group_headroom(rng: RandomNumberGenerator, age: int, group: StringName) -> int:
	var peak := 30
	if group == Stats.PHYSICALITY:
		peak = 28
	elif group == Stats.MENTALITY:
		peak = 33
	var years_left := peak - age
	if years_left <= 0:
		return rng.randi_range(0, 1)
	if years_left <= 3:
		return rng.randi_range(1, 4)
	if years_left <= 7:
		return rng.randi_range(2, 9)
	if years_left <= 10:
		return rng.randi_range(4, 14)
	return rng.randi_range(6, 20)


## Builds a full roster that covers the scheme: 2 frontmen, 1 center, 2 flexes, then 7 depth
## players (a backup for every starter, a 2nd backup center and an extra flex).
static func generate_roster(rng: RandomNumberGenerator, first_id: int, quality: float) -> Array[Soldier]:
	var roles: Array = [
		Scheme.Role.FRONTMAN, Scheme.Role.FRONTMAN, Scheme.Role.CENTER,
		Scheme.Role.FLEX, Scheme.Role.FLEX,
		Scheme.Role.FRONTMAN, Scheme.Role.CENTER, Scheme.Role.FLEX,
		Scheme.Role.FRONTMAN, Scheme.Role.FLEX, Scheme.Role.CENTER, Scheme.Role.FLEX,
	]
	var out: Array[Soldier] = []
	for i in roles.size():
		# Starters a bit better than the first backups, who beat the deep reserves.
		var q := quality + (rng.randfn(0.0, 3.0) if i < 5 else rng.randfn(-5.0, 3.0) if i < 8 else rng.randfn(-8.0, 3.0))
		out.append(generate(rng, first_id + i, roles[i], q))
	return out
