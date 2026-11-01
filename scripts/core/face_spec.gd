class_name FaceSpec
extends RefCounted
## A soldier's photo face: which baked head, mirrored or not, hair tint, eye colour and the morph sliders.
## Rolled from the soldier id + name + age (so it never changes and is never saved). The head's skin group is drawn
## from the name (see FacePrior); everything else comes from the same seeded RNG.

const HEADS_JSON := "res://assets/portraits/heads.json"
const HEADS_DIR := "res://assets/portraits/heads/"

## Approved morph limits (low, high): fractions of face width/height, or of the feature's own size.
## Mirrors LIMITS in tools/portraits/warp.py; brow size and the ear sliders are intentionally absent.
const LIMITS := {
	"eye_x": [-0.025, 0.025], "eye_y": [-0.04, 0.02], "eye_size": [-0.19, 0.09], "brow_y": [-0.04, 0.04],
	"nose_y": [-0.02, 0.04], "nose_w": [-0.18, 0.09], "mouth_y": [-0.025, 0.025], "mouth_w": [-0.15, 0.075],
	"mouth_len": [-0.25, 0.35], "head_w": [-0.10, 0.025],
}
## Hair tint: [name, brightness multiplier, additive warmth (r, g, b)]. Applied by the portrait shader to the hair/brow mask.
const HAIR_TINTS := [
	["keep", 1.0, [0.0, 0.0, 0.0]], ["darker", 0.62, [0.0, 0.0, 0.0]], ["lighter", 1.28, [0.03, 0.02, 0.0]],
	["warmer", 0.95, [0.07, 0.015, -0.03]], ["ash", 1.12, [-0.01, 0.0, 0.015]],
]
## Allowed tints by group (indexes into HAIR_TINTS): darker skin groups keep naturally dark hair.
const TINTS_BY_GROUP := {"light": [0, 0, 1, 2, 3, 4], "dark": [0, 0, 0, 1], "brown": [0, 0, 1, 3], "asian": [0, 0, 0, 1]}
## Eye colours (hue 0-1 as the shader uses it, saturation) by group, weighted.
const EYE_COLORS := {
	"brown": [0.07, 0.62], "hazel": [0.12, 0.55], "green": [0.30, 0.42], "blue": [0.58, 0.48], "gray": [0.55, 0.12],
}
const EYES_BY_GROUP := {
	"light": {"brown": 35, "hazel": 15, "green": 15, "blue": 30, "gray": 5}, "dark": {"brown": 92, "hazel": 8},
	"brown": {"brown": 80, "hazel": 15, "green": 5}, "asian": {"brown": 96, "hazel": 4},
}

static var _db: Dictionary = {}

var head_id := ""
var group := "light"
var flip := false
var tint := 0
var eye_color := "brown"
var morph := {}
## Age at which hair starts going gray (shared with Look so the existing aging stays the same).
var gray_onset := 34


static func db() -> Dictionary:
	if _db.is_empty():
		var f := FileAccess.open(HEADS_JSON, FileAccess.READ)
		if f != null:
			_db = JSON.parse_string(f.get_as_text())
	return _db


## Heads available per group, sorted for determinism.
static func heads_in(group_name: String) -> Array:
	var out := []
	var heads: Dictionary = db().get("heads", {})
	for id in heads:
		if heads[id]["group"] == group_name:
			out.append(id)
	out.sort()
	return out


## `salt` > 0 re-rolls everything except the skin group (used to keep two soldiers on a team from sharing a head).
static func generate(id: int, first: String, last: String, salt := 0) -> FaceSpec:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id * 73939 + 1301)
	var f := FaceSpec.new()
	f.group = FacePrior.pick_group(rng, first, last)
	if salt > 0:
		rng.seed = hash(id * 73939 + 1301 + salt * 7919)
	var pool := heads_in(f.group)
	if pool.is_empty(): # a group with no baked heads yet falls back to any head
		pool = heads_in("light")
	f.head_id = pool[rng.randi_range(0, pool.size() - 1)]
	f.flip = rng.randf() < 0.5
	var tints: Array = TINTS_BY_GROUP[f.group]
	f.tint = tints[rng.randi_range(0, tints.size() - 1)]
	f.eye_color = _pick_name(rng, EYES_BY_GROUP[f.group])
	for k in LIMITS:
		var lim: Array = LIMITS[k]
		f.morph[k] = rng.randf_range(lim[0], lim[1])
	f.gray_onset = rng.randi_range(29, 40)
	return f


## Gives every soldier in `roster` (one team, in order) his own head: a repeat re-rolls with a higher salt.
## Salts are stored (league.json "face"), so faces never change when players move teams.
static func dedupe(roster: Array) -> void:
	var used := {}
	for s: Soldier in roster:
		var salt := s.face_salt
		var f := generate(s.id, s.first_name, s.last_name, salt)
		while used.has(f.head_id) and salt < 64:
			salt += 1
			f = generate(s.id, s.first_name, s.last_name, salt)
		s.face_salt = salt
		s.face = f
		used[f.head_id] = true


## Hair gray amount 0..0.85 at `age`.
func gray_at(age: int) -> float:
	return clampf((age - gray_onset) / 7.0, 0.0, 0.85)


## Identity key: two soldiers with the same key would look identical.
func key() -> String:
	var parts := [head_id, str(flip), str(tint), eye_color]
	for k in morph:
		parts.append("%d" % roundi(morph[k] * 1000.0))
	return "|".join(parts)


static func _pick_name(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0
	for k in weights:
		total += int(weights[k])
	var roll := rng.randi_range(1, maxi(1, total))
	for k in weights:
		roll -= int(weights[k])
		if roll <= 0:
			return k
	return weights.keys()[0]
