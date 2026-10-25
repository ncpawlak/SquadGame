class_name PlayerGenerator
extends RefCounted
## Builds soldiers from role archetypes plus noise. All randomness comes from the passed RNG.

const FIRST_NAMES := [
	"Alex", "Marcus", "Diego", "Tariq", "Jonah", "Wes", "Kai", "Nico", "Owen", "Rafael",
	"Ivan", "Luca", "Mateo", "Theo", "Andre", "Malik", "Hugo", "Felix", "Jasper", "Dante",
	"Ezra", "Silas", "Cole", "Rhys", "Bruno", "Kenji", "Omar", "Viktor", "Elias", "Sami",
	"Tomas", "Reed", "Jalen", "Arlo", "Cyrus", "Damon", "Emil", "Gage", "Hank", "Idris",
]
const LAST_NAMES := [
	"Reyes", "Novak", "Okafor", "Lindqvist", "Hart", "Moreau", "Kowalski", "Tanaka", "Silva",
	"Brennan", "Vance", "Ortiz", "Petrov", "Haddad", "Fischer", "Mbeki", "Calloway", "Ruiz",
	"Sato", "Grant", "Ivers", "Duarte", "Kerr", "Lowe", "Mercer", "Nash", "Pike", "Quinn",
	"Rourke", "Stone", "Thorne", "Ueda", "Voss", "Wilder", "Yates", "Zane", "Bishop", "Cruz",
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
	s.potential = roll_potential(rng, s.age)
	roll_caps(s, rng)
	s.look = Look.generate(s.id, s.age, role)
	return s


## Chance weights for F, D, C, B, A by age band: young players skew high.
const POTENTIAL_WEIGHTS := [
	[22, [5, 15, 35, 30, 15]],
	[26, [10, 25, 35, 22, 8]],
	[30, [25, 35, 30, 8, 2]],
	[99, [50, 35, 13, 2, 0]],
]
## Cap headroom multiplier per potential grade (F..A).
const POTENTIAL_HEADROOM := [0.4, 0.7, 1.0, 1.35, 1.7]


static func roll_potential(rng: RandomNumberGenerator, age: int) -> int:
	for band in POTENTIAL_WEIGHTS:
		if age <= band[0]:
			var weights: Array = band[1]
			var total := 0
			for w in weights:
				total += w
			var roll := rng.randi_range(1, total)
			for i in weights.size():
				roll -= weights[i]
				if roll <= 0:
					return i
	return 0


## Rolls every group cap: age-based headroom x the potential multiplier x a random per-group
## factor, so higher potential means higher caps overall but which groups get them is random.
static func roll_caps(s: Soldier, rng: RandomNumberGenerator, extra := 0) -> void:
	for g in Stats.UPGRADABLE_GROUPS:
		var room: float = float(roll_group_headroom(rng, s.age, g)) * POTENTIAL_HEADROOM[s.potential] * rng.randf_range(0.3, 1.7)
		s.group_caps[g] = mini(Stats.MAX_RATING, s.group_rating(g) + roundi(room) + extra)


## Group cap headroom by age. Physical peak ends ~29, skill peak ~33; mentality keeps growing.
static func roll_group_headroom(rng: RandomNumberGenerator, age: int, group: StringName) -> int:
	var peak := 33
	if group == Stats.PHYSICALITY:
		peak = 29
	elif group == Stats.MENTALITY:
		peak = 36
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
