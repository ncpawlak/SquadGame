class_name SaveSystem
extends RefCounted
## Franchise save/load: 3 manual slots + 1 autosave slot under user://saves.
##
## The Season is written with a generic object-graph serializer: every scripted object is stored
## once in a table and referenced by id, so shared references (the same Soldier on a roster, in a
## match box score and in a dictionary key) and cycles survive a round trip. Script variables are
## discovered through get_property_list(), so new fields are saved without touching this file.
## The resulting Variant tree is turned into text with var_to_str(), which keeps StringName,
## Color, PackedArrays and int/float distinct (JSON would not).

const SLOTS := 3
const AUTO_SLOT := 0
const VERSION := 1
const DIR := "user://saves"
const COMPRESSION := FileAccess.COMPRESSION_ZSTD

# Tags for encoded containers / references. Raw values are never Dictionaries or Arrays, so any
# Dictionary in the encoded tree is one of these.
const TAG := "_"
const T_REF := "R"
const T_ARRAY := "A"
const T_DICT := "D"
const T_FLOAT := "F"


# --- slot API -------------------------------------------------------------------------------

static func slot_path(slot: int) -> String:
	return "%s/slot_%d.save" % [DIR, slot]


static func meta_path(slot: int) -> String:
	return "%s/slot_%d.meta" % [DIR, slot]


## Writes the season to a slot. Returns "" on success, else an error message.
static func save(season, slot: int, label := "") -> String:
	if slot < AUTO_SLOT or slot > SLOTS:
		return "Invalid save slot %d." % slot
	if season == null:
		return "Nothing to save."
	var err := DirAccess.make_dir_recursive_absolute(DIR)
	if err != OK:
		return "Could not create save folder (%s)." % error_string(err)
	var text := to_text(season)
	var tmp := slot_path(slot) + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, COMPRESSION)
	if f == null:
		return "Could not write save file (%s)." % error_string(FileAccess.get_open_error())
	f.store_string(text)
	f.close()
	# Write-then-rename so a failed save never clobbers the previous one.
	DirAccess.remove_absolute(slot_path(slot))
	err = DirAccess.rename_absolute(tmp, slot_path(slot))
	if err != OK:
		return "Could not finalize save file (%s)." % error_string(err)
	var mf := FileAccess.open(meta_path(slot), FileAccess.WRITE)
	if mf == null:
		return "Could not write save header (%s)." % error_string(FileAccess.get_open_error())
	mf.store_string(var_to_str(_header(season, label)))
	mf.close()
	return ""


static func autosave(season) -> String:
	return save(season, AUTO_SLOT, "Autosave")


## Loads a slot; null if it is empty, unreadable or from a newer save version.
static func load_slot(slot: int) -> Season:
	if not has_slot(slot):
		return null
	var info := slot_info(slot)
	if int(info.get("version", VERSION)) > VERSION:
		push_warning("Save slot %d was written by a newer version." % slot)
		return null
	var f := FileAccess.open_compressed(slot_path(slot), FileAccess.READ, COMPRESSION)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	return from_text(text)


## Header of a slot ({} if empty): version, saved_at, team, abbrev, year, week, label, size.
static func slot_info(slot: int) -> Dictionary:
	if not has_slot(slot):
		return {}
	var info := {}
	if FileAccess.file_exists(meta_path(slot)):
		var parsed = str_to_var(FileAccess.get_file_as_string(meta_path(slot)))
		if parsed is Dictionary:
			info = parsed
	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f != null:
		info["size"] = f.get_length()
		f.close()
	info["slot"] = slot
	return info


static func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


static func delete_slot(slot: int) -> void:
	for p in [slot_path(slot), meta_path(slot), slot_path(slot) + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


static func _header(season, label: String) -> Dictionary:
	var team_name := ""
	var abbrev := ""
	if season.has_method("user_team"):
		var t = season.user_team()
		if t != null:
			team_name = t.name
			abbrev = t.abbrev
	var when := ""
	if season.get("phase") == &"offseason":
		when = "Offseason"
	elif season.has_method("week_label"):
		when = season.week_label(season.week)
	return {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"team": team_name,
		"abbrev": abbrev,
		"year": season.get("year"),
		"week": when,
		"phase": season.get("phase"),
		"label": label,
	}


# --- in-memory round trip -------------------------------------------------------------------

static func to_text(season) -> String:
	return var_to_str(_Writer.new().write(season))


static func from_text(text: String) -> Season:
	var tree = str_to_var(text)
	if not (tree is Dictionary) or not tree.has("objects"):
		return null
	var root = _Reader.new().read(tree)
	var s := root as Season
	if s != null and s.has_method("_stamp_log"):
		s._stamp_log()
		s.market.ensure(s)
		s.ensure_history()
		s.league.ensure_callsigns()
	return s


## Script variables of an object worth persisting.
static func _saved_props(obj: Object) -> Array[String]:
	var out: Array[String] = []
	for p in obj.get_property_list():
		var usage: int = p["usage"]
		# Plain script vars carry only SCRIPT_VARIABLE (no STORAGE) on RefCounted objects.
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(p["name"])
	return out


static func _script_path(scr: Script) -> String:
	return scr.resource_path if scr != null else ""


class _Writer:
	var ids := {}  # instance id -> table index
	var queue: Array[Object] = []
	var table: Array = []

	func write(root: Object) -> Dictionary:
		_ref(root)
		var i := 0
		while i < queue.size():
			table[i] = _object_entry(queue[i])
			i += 1
		return {"version": SaveSystem.VERSION, "objects": table}

	func _ref(o: Object) -> Variant:
		if o == null or not is_instance_valid(o) or o is Node:
			return null
		var iid := o.get_instance_id()
		if not ids.has(iid):
			if not _supported(o):
				return null
			ids[iid] = queue.size()
			queue.append(o)
			table.append(null)
		return {SaveSystem.TAG: SaveSystem.T_REF, "i": ids[iid]}

	func _supported(o: Object) -> bool:
		if o is RandomNumberGenerator:
			return true
		var scr: Script = o.get_script()
		return scr != null and (scr.get_global_name() != &"" or scr.resource_path != "")

	func _object_entry(o: Object) -> Dictionary:
		if o is RandomNumberGenerator and o.get_script() == null:
			return {"n": "RandomNumberGenerator", "seed": o.seed, "state": o.state}
		var scr: Script = o.get_script()
		var entry := {}
		if scr.get_global_name() != &"":
			entry["c"] = String(scr.get_global_name())
		else:
			entry["p"] = scr.resource_path
		var props := {}
		for name in SaveSystem._saved_props(o):
			props[name] = enc(o.get(name))
		entry["v"] = props
		return entry

	func enc(v: Variant) -> Variant:
		match typeof(v):
			TYPE_OBJECT:
				return _ref(v)
			TYPE_ARRAY:
				var arr: Array = v
				var items := []
				items.resize(arr.size())
				for i in arr.size():
					items[i] = enc(arr[i])
				var out := {SaveSystem.TAG: SaveSystem.T_ARRAY, "v": items}
				if arr.is_typed():
					out["t"] = [arr.get_typed_builtin(), arr.get_typed_class_name(),
						SaveSystem._script_path(arr.get_typed_script())]
				return out
			TYPE_DICTIONARY:
				var d: Dictionary = v
				var keys := []
				var vals := []
				for k in d:
					keys.append(enc(k))
					vals.append(enc(d[k]))
				var out := {SaveSystem.TAG: SaveSystem.T_DICT, "k": keys, "v": vals}
				if d.is_typed():
					out["t"] = [d.get_typed_key_builtin(), d.get_typed_key_class_name(),
						SaveSystem._script_path(d.get_typed_key_script()),
						d.get_typed_value_builtin(), d.get_typed_value_class_name(),
						SaveSystem._script_path(d.get_typed_value_script())]
				return out
			TYPE_FLOAT:
				# var_to_str can drop the last bit of a double; keep those exact as raw bits.
				if str_to_var(var_to_str(v)) == v:
					return v
				var pa := PackedFloat64Array([v])
				return {SaveSystem.TAG: SaveSystem.T_FLOAT, "b": pa.to_byte_array().decode_s64(0)}
			TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
				return null
		return v


class _Reader:
	var objects: Array = []
	var _class_paths := {}

	func read(tree: Dictionary) -> Object:
		for g in ProjectSettings.get_global_class_list():
			_class_paths[String(g["class"])] = g["path"]
		var table: Array = tree["objects"]
		# Phase 1: instantiate everything so forward references resolve.
		objects.resize(table.size())
		for i in table.size():
			objects[i] = _instantiate(table[i])
		# Phase 2: fill properties.
		for i in table.size():
			var o: Object = objects[i]
			var entry: Dictionary = table[i]
			if o == null or not entry.has("v"):
				continue
			var known := {}
			for name in SaveSystem._saved_props(o):
				known[name] = true
			var props: Dictionary = entry["v"]
			for name in props:
				if known.has(name):
					_assign(o, name, dec(props[name]))
				elif o.has_method("_migrate_prop"):
					# Renamed/removed fields from older saves.
					o._migrate_prop(name, dec(props[name]))
		return objects[0] if not objects.is_empty() else null

	func _instantiate(entry: Dictionary) -> Object:
		if entry.get("n", "") == "RandomNumberGenerator":
			var rng := RandomNumberGenerator.new()
			rng.seed = entry["seed"]
			rng.state = entry["state"]  # after seed: setting seed resets state
			return rng
		var path: String = entry.get("p", "")
		if entry.has("c"):
			path = _class_paths.get(entry["c"], "")
		if path == "" or not ResourceLoader.exists(path):
			push_warning("SaveSystem: unknown class %s" % entry.get("c", path))
			return null
		var scr = load(path)
		return scr.new() if scr is Script else null

	func _assign(o: Object, name: String, val: Variant) -> void:
		var cur = o.get(name)
		if cur is Array and val is Array and cur.is_typed() and not cur.is_same_typed(val):
			cur.assign(val)
		elif cur is Dictionary and val is Dictionary and cur.is_typed() and not cur.is_same_typed(val):
			cur.assign(val)
		else:
			o.set(name, val)

	func dec(v: Variant) -> Variant:
		if not (v is Dictionary):
			return v
		match v.get(SaveSystem.TAG, ""):
			SaveSystem.T_FLOAT:
				var bytes := PackedByteArray()
				bytes.resize(8)
				bytes.encode_s64(0, v["b"])
				return bytes.decode_double(0)
			SaveSystem.T_REF:
				var i: int = v["i"]
				return objects[i] if i >= 0 and i < objects.size() else null
			SaveSystem.T_ARRAY:
				var items := []
				for x in v["v"]:
					items.append(dec(x))
				if v.has("t"):
					var t: Array = v["t"]
					var scr = _script(t[2])
					if t[2] == "" or scr != null:
						return Array(items, t[0], t[1], scr)
				return items
			SaveSystem.T_DICT:
				var d := {}
				var keys: Array = v["k"]
				var vals: Array = v["v"]
				for i in keys.size():
					d[dec(keys[i])] = dec(vals[i])
				if v.has("t"):
					var t: Array = v["t"]
					var ks = _script(t[2])
					var vs = _script(t[5])
					if (t[2] == "" or ks != null) and (t[5] == "" or vs != null):
						return Dictionary(d, t[0], t[1], ks, t[3], t[4], vs)
				return d
		return null

	func _script(path: String) -> Script:
		if path == "" or not ResourceLoader.exists(path):
			return null
		return load(path) as Script
