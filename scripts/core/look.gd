class_name Look
extends RefCounted
## A soldier's procedurally generated appearance (drawn by Portrait). Rolled once from the
## soldier id with its own RNG, lightly biased by age and role. Gear colours are not stored:
## they come from the soldier's current team (primary on headgear/masks, secondary on accents).

enum Head { BOONIE, HELMET, BEANIE, BEANIE_HEADSET, HELMET_GOGGLES, CAP_FORWARD, CAP_BACKWARD, HAIR }
enum Eyes { GOGGLES_CLEAR, GOGGLES_TINTED, SUNGLASSES, NORMAL, NIGHT_VISION }
enum Face { NORMAL, BALACLAVA, FACE_PAINT, EYE_BLACK }
enum Lower { BALACLAVA, BANDANA, HALF_MASK, SHEMAGH, SHAVED, GOATEE, SHORT_BEARD, BIG_BEARD }

const HEAD_NAMES := ["Boonie hat", "Infantry helmet", "Beanie", "Beanie + headset", "Helmet + goggles",
	"Ball cap", "Backward cap", "Bare head"]
const EYES_NAMES := ["Clear goggles", "Tinted goggles", "Sunglasses", "Eyes", "Night vision"]
const FACE_NAMES := ["Face", "Balaclava", "Face paint", "Eye black"]
const LOWER_NAMES := ["Balaclava", "Bandana", "Half mask", "Shemagh", "Clean shaven", "Goatee", "Short beard", "Big beard"]

const SKIN := [Color("#f6d5b8"), Color("#ecbf98"), Color("#d9a47a"), Color("#c08a5e"), Color("#a06d45"),
	Color("#80522f"), Color("#633e23"), Color("#4a2d19")]
const HAIR := [Color("#16110e"), Color("#3b2618"), Color("#5c3b22"), Color("#8a6239"), Color("#c9a464"), Color("#9a4a22")]
const EYE_COLORS := [Color("#5a3a1e"), Color("#1c130d"), Color("#3f7fbf")]
const EYE_COLOR_NAMES := ["Brown", "Black", "Blue"]
## Goggle lens tints: amber, smoke, mirrored blue, rose.
const TINTS := [Color(0.98, 0.62, 0.12, 0.92), Color(0.12, 0.13, 0.15, 0.92), Color(0.2, 0.5, 0.95, 0.9), Color(0.9, 0.35, 0.4, 0.9)]
const HAIR_STYLES := 4 # buzz, crop, swept, shaved bald

var skin := 0
var hair_color := 0
var hair_style := 0
## Age at which hair starts going gray.
var gray_onset := 34
var head: Head = Head.HAIR
var eyes: Eyes = Eyes.NORMAL
var eye_color := 0
var face: Face = Face.NORMAL
var lower: Lower = Lower.SHAVED
var tint := 0


static func generate(id: int, age: int, role: Scheme.Role) -> Look:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id * 92821 + 4099)
	var l := Look.new()
	l.skin = rng.randi_range(0, SKIN.size() - 1)
	# Darker skin tones skew toward darker hair and eyes.
	var dark := l.skin >= 4
	l.hair_color = _pick(rng, [30, 30, 20, 10, 5, 5] if dark else [16, 20, 22, 16, 16, 10])
	l.hair_style = rng.randi_range(0, HAIR_STYLES - 1)
	l.gray_onset = rng.randi_range(29, 40)
	l.eye_color = _pick(rng, [55, 40, 5] if dark else [45, 20, 35])
	l.tint = rng.randi_range(0, TINTS.size() - 1)

	var hw := [6, 22, 10, 9, 10, 10, 8, 14] # Head weights
	var ew := [14, 16, 20, 42, 10] # Eyes weights
	var lw := [0, 7, 6, 6, 26, 14, 18, 13] # Lower weights (balaclava comes from Face)
	match role:
		Scheme.Role.FRONTMAN: # breachers: armour and masks
			hw[Head.HELMET] += 14; hw[Head.HELMET_GOGGLES] += 10
			ew[Eyes.GOGGLES_TINTED] += 10; ew[Eyes.NIGHT_VISION] += 6
			lw[Lower.HALF_MASK] += 6
		Scheme.Role.CENTER: # marksmen/anchors: boonies and shemaghs
			hw[Head.BOONIE] += 16; hw[Head.BEANIE_HEADSET] += 6
			ew[Eyes.SUNGLASSES] += 8
			lw[Lower.SHEMAGH] += 7
		Scheme.Role.FLEX: # runners: light gear
			hw[Head.CAP_FORWARD] += 10; hw[Head.CAP_BACKWARD] += 10; hw[Head.BEANIE_HEADSET] += 8
			ew[Eyes.SUNGLASSES] += 10
			lw[Lower.BANDANA] += 5
	# Facial hair grows with age; the youngest are mostly clean.
	if age <= 22:
		lw[Lower.SHAVED] += 18; lw[Lower.BIG_BEARD] -= 8; lw[Lower.SHORT_BEARD] -= 6
	elif age >= 29:
		lw[Lower.SHAVED] -= 10; lw[Lower.SHORT_BEARD] += 8; lw[Lower.BIG_BEARD] += 10; lw[Lower.GOATEE] += 4

	l.head = _pick(rng, hw) as Head
	if l.head in [Head.HELMET, Head.HELMET_GOGGLES]:
		ew[Eyes.NIGHT_VISION] += 6
	else:
		ew[Eyes.NIGHT_VISION] = 0 # NVGs need a helmet mount
	if l.head in [Head.CAP_FORWARD, Head.BOONIE]: # brims sit where goggles would
		ew[Eyes.SUNGLASSES] += ew[Eyes.GOGGLES_CLEAR] + ew[Eyes.GOGGLES_TINTED]
		ew[Eyes.GOGGLES_CLEAR] = 0; ew[Eyes.GOGGLES_TINTED] = 0
	if l.head == Head.HELMET_GOGGLES: # goggles already ride on the helmet
		ew[Eyes.GOGGLES_CLEAR] = 0; ew[Eyes.GOGGLES_TINTED] = 0; ew[Eyes.NIGHT_VISION] = 0
	l.eyes = _pick(rng, ew) as Eyes
	l.face = _pick(rng, [68, 8, 12, 12]) as Face
	if l.face == Face.EYE_BLACK and l.eyes != Eyes.NORMAL and l.eyes != Eyes.SUNGLASSES:
		l.face = Face.NORMAL # eye black would be hidden under goggles/NVGs
	if l.face == Face.BALACLAVA:
		l.lower = Lower.BALACLAVA
	else:
		for i in lw.size():
			lw[i] = maxi(0, lw[i])
		l.lower = _pick(rng, lw) as Lower
	return l


func is_masked() -> bool:
	return lower in [Lower.BALACLAVA, Lower.BANDANA, Lower.HALF_MASK, Lower.SHEMAGH]


func has_helmet() -> bool:
	return head in [Head.HELMET, Head.HELMET_GOGGLES]


## Hair/beard colour at `age`, graying past the soldier's onset age.
func hair_at(age: int) -> Color:
	var base: Color = HAIR[hair_color]
	var g := clampf((age - gray_onset) / 7.0, 0.0, 0.85)
	return base.lerp(Color("#bdbab4"), g)


func describe() -> String:
	var parts: Array[String] = [HEAD_NAMES[head]]
	if eyes == Eyes.NORMAL:
		parts.append("%s eyes" % EYE_COLOR_NAMES[eye_color])
	else:
		parts.append(EYES_NAMES[eyes])
	if face != Face.NORMAL:
		parts.append(FACE_NAMES[face])
	if lower != Lower.BALACLAVA:
		parts.append(LOWER_NAMES[lower])
	return ", ".join(parts)


static func _pick(rng: RandomNumberGenerator, weights: Array) -> int:
	var total := 0
	for w in weights:
		total += maxi(0, w)
	var roll := rng.randi_range(1, maxi(1, total))
	for i in weights.size():
		roll -= maxi(0, weights[i])
		if roll <= 0:
			return i
	return weights.size() - 1
