class_name LeagueEditor
extends RefCounted
## Data Edit's model: every player row of data/league.json, edited in place and written back one line per player
## (so the file's layout and the git diff stay small). Only identity, ratings and the hand-picked face are edited;
## contracts, personality, career and morale are left alone.

const NAME_MAX := 16

var path := League.DATA_PATH
var lines := PackedStringArray()
## Player index (file order) -> parsed row, and the line of the file it lives on.
var rows: Array[Dictionary] = []
var line_of: Array[int] = []
var originals: Array[String] = []


static func open(file := League.DATA_PATH) -> LeagueEditor:
	var e := LeagueEditor.new()
	e.path = file
	e.lines = FileAccess.get_file_as_string(file).split("\n")
	for i in e.lines.size():
		var raw := e.lines[i].strip_edges().trim_suffix(",")
		if not raw.begins_with("{\"age\""):
			continue
		var d: Variant = JSON.parse_string(raw)
		if typeof(d) == TYPE_DICTIONARY:
			e.rows.append(d)
			e.line_of.append(i)
			e.originals.append(_encode(d))
	return e


func count() -> int:
	return rows.size()


func soldier(k: int) -> Soldier:
	return League.soldier_from_dict(rows[k])


func team_of(k: int) -> String:
	return String(rows[k].get("team", ""))


func is_dirty(k: int) -> bool:
	return _encode(rows[k]) != originals[k]


func dirty_count() -> int:
	var n := 0
	for k in rows.size():
		if is_dirty(k):
			n += 1
	return n


func revert(k: int) -> void:
	rows[k] = JSON.parse_string(originals[k])


## True if another player already has this callsign (case-insensitive).
func callsign_taken(k: int, text: String) -> bool:
	var low := text.strip_edges().to_lower()
	for j in rows.size():
		if j != k and String(rows[j].get("callsign", "")).to_lower() == low:
			return true
	return false


func set_field(k: int, key: String, value: Variant) -> void:
	rows[k][key] = value


func set_stat(k: int, abbrev: String, value: int) -> void:
	rows[k]["stats"][abbrev] = clampi(value, Stats.MIN_RATING, Stats.MAX_RATING)


func set_cap(k: int, group: String, value: int) -> void:
	rows[k]["caps"][group] = clampi(value, Stats.MIN_RATING, Stats.MAX_RATING)


## Renaming changes the head the name-based roll would pick, so the current face is frozen first.
func set_name(k: int, first: String, last: String) -> void:
	var d := rows[k]
	if not d.has("face_ov") and (first != d["first"] or last != d["last"]):
		d["face_ov"] = soldier(k).get_face().to_override()
	d["first"] = first
	d["last"] = last


func set_head(k: int, head_id: String, seed_value: int) -> void:
	rows[k]["face_ov"] = FaceSpec.make_override(head_id, seed_value)


func reroll_morph(k: int, seed_value: int) -> void:
	var d := rows[k]
	if not d.has("face_ov"):
		d["face_ov"] = soldier(k).get_face().to_override()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value * 15485863 + 31)
	d["face_ov"]["morph"] = FaceSpec.roll_morph(rng)


## Writes the changed lines back. Returns OK, or the file error.
func save() -> Error:
	for k in rows.size():
		if not is_dirty(k):
			continue
		var line := lines[line_of[k]]
		var tail := "\r" if line.ends_with("\r") else ""
		var comma := "," if line.strip_edges().ends_with(",") else ""
		lines[line_of[k]] = _encode(rows[k]) + comma + tail
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string("\n".join(lines))
	f.close()
	for k in rows.size():
		originals[k] = _encode(rows[k])
	return OK


## One row as a JSON line: whole numbers print as ints (JSON.parse reads every number as a float).
static func _encode(d: Dictionary) -> String:
	return JSON.stringify(_ints(d))


static func _ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if is_equal_approx(v, roundf(v)) else snappedf(v, 0.0001)
		TYPE_DICTIONARY:
			var out := {}
			for key in v:
				out[key] = _ints(v[key])
			return out
		TYPE_ARRAY:
			return v.map(_ints)
	return v
