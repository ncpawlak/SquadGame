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
	},
	Scheme.Role.CENTER: {
		&"awareness": 10, &"medium_acc": 9, &"long_acc": 8, &"teamwork": 9, &"composure": 6,
		&"short_acc": -3, &"speed": -6,
	},
	Scheme.Role.FLEX: {
		&"speed": 11, &"agility": 10, &"endurance": 8, &"medium_acc": 4, &"short_acc": 2,
		&"reload": 3, &"strength": -6, &"toughness": -6, &"long_acc": -4,
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
		s.caps[stat] = mini(Stats.MAX_RATING, s.stats[stat] + _roll_headroom(rng, s.age))
	return s


static func _roll_headroom(rng: RandomNumberGenerator, age: int) -> int:
	if age <= 22:
		return rng.randi_range(6, 25)
	if age <= 26:
		return rng.randi_range(3, 15)
	if age <= 29:
		return rng.randi_range(1, 8)
	return rng.randi_range(0, 4)


## Builds a full roster that covers the scheme: 2 frontmen, 1 center, 2 flexes, plus 3 depth players.
static func generate_roster(rng: RandomNumberGenerator, first_id: int, quality: float) -> Array[Soldier]:
	var roles: Array = [
		Scheme.Role.FRONTMAN, Scheme.Role.FRONTMAN, Scheme.Role.CENTER,
		Scheme.Role.FLEX, Scheme.Role.FLEX,
		Scheme.Role.FRONTMAN, Scheme.Role.CENTER, Scheme.Role.FLEX,
	]
	var out: Array[Soldier] = []
	for i in roles.size():
		# Starters a bit better than depth players.
		var q := quality + (rng.randfn(0.0, 3.0) if i < 5 else rng.randfn(-5.0, 3.0))
		out.append(generate(rng, first_id + i, roles[i], q))
	return out
