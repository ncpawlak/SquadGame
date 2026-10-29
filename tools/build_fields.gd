extends SceneTree
## Authoring tool for team fields: writes data/fields.json from the hand-made designs in
## tools/field_designs.gd (venue name, floor surface and props per team). The game never runs this; it
## only loads the JSON. A field marked "locked": true in the JSON is kept as is when this is re-run, so
## hand edits to the JSON survive. Every design is checked before it is written: no prop on a spawn, hold
## or flank-route spot, one connected floor and enough open sight lanes.
##   godot --headless --path . -s tools/build_fields.gd
##   godot --headless --path . -s tools/build_fields.gd -- sheet=C:/path/sheet.png   (also renders a contact sheet)
##
## Layouts are point-symmetric: the designs cover the left half and the game reflects them, so spawns,
## holds, the flank routes and the hill stay clear and neither team is favoured.

const OUT := "res://data/fields.json"
const EDGE_MARGIN := 1.0
const MIN_SIGHT := 0.03
## Soldiers must be able to stand on every spawn, hold and flank point, so props stay this far off them.
const POINT_CLEARANCE := 1.6

var _keepout: Array[Rect2] = []
var _keep_points: Array[Vector2] = []


func _init() -> void:
	_build_keepouts()
	var data := _load_existing()
	var failed: Array = []
	for entry in FieldDesigns.LIST:
		var abbrev: String = entry[0]
		if data.has(abbrev) and data[abbrev].get("locked", false):
			print("%s locked, kept" % abbrev)
			continue
		var props := FieldDesigns.new().build(entry[3])
		var field := ArenaMap.from_data(abbrev, {"props": props})
		var t0 := Time.get_ticks_msec()
		var report := _validate(field, props)
		var nav_ms := Time.get_ticks_msec() - t0
		print("%s %-22s %3d props  %3d obstacles  area %3.0f  sight %.2f  reach %.3f  %s  (%d ms)" % [
			abbrev, entry[1], props.size(), field.obstacles.size(), report["area"], report["sight"], report["reach"],
			"OK" if report["ok"] else "REJECTED", nav_ms])
		for w in report["why"]:
			print("    - %s" % w)
		if not report["ok"]:
			failed.append(abbrev)
			continue
		data[abbrev] = {"name": entry[1], "surface": entry[2], "sym": "point", "props": props}
	if not failed.is_empty():
		push_error("rejected: %s (fields.json not written)" % ", ".join(failed))
		quit(1)
		return
	_write(data)
	print("wrote %s" % OUT)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("sheet="):
			_sheet(data, arg.substr(6))
	quit()


# --- keep-outs ---------------------------------------------------------------------

## Everything a prop must stay off: every scheme's holds and watch spots and both flank routes (just far
## enough that a soldier can stand there), the hill, and the two starting areas. Reflected for team 1.
func _build_keepouts() -> void:
	var pts: Array[Vector2] = []
	var radii: Array[float] = []
	for sid in Scheme.LAYOUTS:
		for slot in Scheme.LAYOUTS[sid]:
			var e: Dictionary = Scheme.LAYOUTS[sid][slot]
			for key in ["spawn", "hold", "watch"]:
				if e.has(key):
					pts.append(e[key])
					radii.append(POINT_CLEARANCE)
	for right in [false, true]:
		for i in 26:
			var p := ArenaMap.flank_point(i / 25.0, right)
			pts.append(p)
			radii.append(POINT_CLEARANCE)
			pts.append(p - Vector2(4.0, 0.0))
			radii.append(POINT_CLEARANCE)
	for i in pts.size():
		for p in [pts[i], -pts[i]]:
			_keepout.append(Rect2(p - Vector2(radii[i], radii[i]), Vector2(radii[i], radii[i]) * 2.0))
			_keep_points.append(p)
	_keepout.append(ArenaMap.HILL.grow(1.0))
	for sign in [-1.0, 1.0]:
		var x0 := -ArenaMap.HALF.x if sign < 0.0 else ArenaMap.START_X
		_keepout.append(Rect2(x0, -ArenaMap.HALF.y, ArenaMap.HALF.x - ArenaMap.START_X, ArenaMap.HALF.y * 2.0))


# --- validation --------------------------------------------------------------------

static func _rect(p: Dictionary) -> Rect2:
	var size := Vector2(p["w"], p["h"])
	return Rect2(Vector2(p["x"], p["y"]) - size / 2.0, size)


func _validate(field: ArenaMap, props: Array) -> Dictionary:
	var out := {"ok": false, "why": [], "area": 0.0, "sight": 0.0, "reach": 0.0}
	var inner := Rect2(-ArenaMap.HALF + Vector2(EDGE_MARGIN, EDGE_MARGIN), (ArenaMap.HALF - Vector2(EDGE_MARGIN, EDGE_MARGIN)) * 2.0)
	for p in props:
		if not ArenaMap.KINDS.has(StringName(p["k"])):
			out["why"].append("unknown prop kind %s" % p["k"])
			continue
		if ArenaMap.KINDS[StringName(p["k"])].is_empty():
			continue
		var r := _rect(p)
		if not inner.encloses(r):
			out["why"].append("%s at (%s, %s) is outside the playable edge" % [p["k"], p["x"], p["y"]])
		for k in _keepout:
			if k.intersects(r):
				out["why"].append("%s at (%s, %s) sits on a spawn, hold, flank point, the hill or a starting area %s" % [p["k"], p["x"], p["y"], k])
				break
	if not out["why"].is_empty():
		return out
	field.ensure_built()
	for r in field.obstacles:
		out["area"] += r.get_area()
	for p in _keep_points:
		if field.blocked(p):
			out["why"].append("keep point blocked %s" % p)
	# Flood fill on a 1 m grid from the middle: everything free must be one region.
	var seen := {}
	var queue: Array[Vector2i] = [Vector2i(0, 0)]
	seen[Vector2i(0, 0)] = true
	var free := 0
	for x in range(-47, 47):
		for y in range(-29, 29):
			if not field.blocked(Vector2(x + 0.5, y + 0.5)):
				free += 1
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or n.x < -47 or n.x >= 47 or n.y < -29 or n.y >= 29:
				continue
			if field.blocked(Vector2(n.x + 0.5, n.y + 0.5)):
				continue
			seen[n] = true
			queue.append(n)
	out["reach"] = float(seen.size()) / maxf(1.0, free)
	if out["reach"] < 0.985:
		# Name the cut-off area (bounding box of unreachable free cells).
		var lo := Vector2i(999, 999)
		var hi := Vector2i(-999, -999)
		var cells: Array[String] = []
		for x in range(-47, 47):
			for y in range(-29, 29):
				if not seen.has(Vector2i(x, y)) and not field.blocked(Vector2(x + 0.5, y + 0.5)):
					lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
					hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
					if x < 0 and cells.size() < 24:
						cells.append("(%d,%d)" % [x, y])
		out["why"].append("cut-off floor between (%d, %d) and (%d, %d)" % [lo.x, lo.y, hi.x, hi.y])
		out["why"].append("left-half cells: %s" % " ".join(cells))
		out["why"].append("floor is not one region (%.3f reachable)" % out["reach"])
	# Sight lanes between the two halves, so matches don't stall behind a maze.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var clear := 0
	var n_pairs := 600
	for i in n_pairs:
		var a := Vector2(rng.randf_range(-44, -10), rng.randf_range(-26, 26))
		var b := Vector2(rng.randf_range(10, 44), rng.randf_range(-26, 26))
		if not field.blocked(a) and not field.blocked(b) and field.line_of_sight(a, b):
			clear += 1
	out["sight"] = float(clear) / n_pairs
	if out["sight"] < MIN_SIGHT:
		out["why"].append("too closed in (sight %.2f)" % out["sight"])
	out["ok"] = out["why"].is_empty()
	return out


# --- output ------------------------------------------------------------------------

func _load_existing() -> Dictionary:
	if not FileAccess.file_exists(OUT):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUT))
	return parsed if parsed is Dictionary else {}


## One prop per line so hand edits stay readable.
func _write(data: Dictionary) -> void:
	var lines: Array[String] = ["{"]
	var keys := data.keys()
	keys.sort()
	for ki in keys.size():
		var d: Dictionary = data[keys[ki]]
		lines.append("\"%s\": {" % keys[ki])
		lines.append("\t\"name\": %s, \"surface\": %s, \"sym\": %s%s," % [
			JSON.stringify(d["name"]), JSON.stringify(d["surface"]), JSON.stringify(d.get("sym", "point")),
			", \"locked\": true" if d.get("locked", false) else ""])
		lines.append("\t\"props\": [")
		var props: Array = d["props"]
		for i in props.size():
			lines.append("\t\t%s%s" % [JSON.stringify(props[i]), "," if i < props.size() - 1 else ""])
		lines.append("\t]")
		lines.append("}%s" % ("," if ki < keys.size() - 1 else ""))
	lines.append("}")
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()


# --- contact sheet (flat colours; the real look is FieldPainter) -------------------------

const _PX := 8
const _FLOORS := {"asphalt": Color("#2b2e35"), "concrete": Color("#4d525a"), "turf": Color("#2f5d34"), "sand": Color("#b9a678")}


func _sheet(data: Dictionary, path: String) -> void:
	var keys := data.keys()
	keys.sort()
	var w := int(ArenaMap.HALF.x * 2.0) * _PX
	var h := int(ArenaMap.HALF.y * 2.0) * _PX
	var cols := 4
	var rows := ceili(keys.size() / float(cols))
	var sheet := Image.create(cols * (w + 10) + 10, rows * (h + 10) + 10, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#0b0d12"))
	for i in keys.size():
		var field := ArenaMap.from_data(keys[i], data[keys[i]])
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(_FLOORS.get(field.surface, Color.GRAY))
		for p in field.props:
			var r: Rect2 = p["rect"]
			var rect_px := Rect2i(Vector2i(((r.position + ArenaMap.HALF) * _PX).round()), Vector2i((r.size * _PX).round()))
			img.fill_rect(rect_px, Color("#14161b") if p["k"] == &"wall" else (Color(0.5, 0.5, 0.5) if ArenaMap.KINDS[p["k"]].is_empty() else Color("#a8825a")))
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(10 + (i % cols) * (w + 10), 10 + (i / cols) * (h + 10)))
	sheet.save_png(path)
	print("sheet -> %s" % path)
