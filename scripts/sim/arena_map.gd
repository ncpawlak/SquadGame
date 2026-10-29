class_name ArenaMap
extends RefCounted
## One field, in metres with (0, 0) at the middle of the hill. Every team has its own home field
## (data/fields.json, authored once by tools/build_fields.gd); teams without one play on the legacy
## crate layout. Team 0 (the home side) spawns on the left (-x) facing right; team 1 is the point
## reflection (x, y) -> (-x, -y), so "left" for either team is the same side relative to its own facing.
##
## A field is a list of props (see KINDS). Every prop blocks movement; tall ones (walls, buildings,
## containers) also block line of sight and low ones (cars, dumpsters, sandbags) give a soldier
## hugging them cover (shots crossing one are less likely to hit). Fences only block movement.
## Every layout is symmetric (point reflection, or both axes for "quad"), so neither side or flank
## is favoured. Movement uses straight lines where clear, otherwise a precomputed waypoint graph
## around obstacle corners (built once per field, lazily).

const HALF := Vector2(48.0, 30.0)
const SOLDIER_RADIUS := 0.8
## Nav nodes sit this far out from each obstacle corner.
const NODE_MARGIN := 1.7
const HILL := Rect2(-5.0, -5.0, 10.0, 10.0)
const FIELDS_PATH := "res://data/fields.json"

## Floor surfaces (cosmetic for now; weather depends on the home climate, not the surface).
const SURFACES: Array[String] = ["asphalt", "concrete", "turf", "sand"]

## Prop kinds: tall = blocks sight, cover = shots across it are less likely to hit.
## The empty entries are floor decals only (no collision): interior floor, grass, boards, dirt and
## shallow water.
const KINDS := {
	&"wall": {"tall": true, "cover": false},
	&"pillar": {"tall": true, "cover": false},
	&"container": {"tall": true, "cover": false},
	&"bleachers": {"tall": true, "cover": false},
	&"tree": {"tall": true, "cover": false},
	&"hedge": {"tall": true, "cover": false},
	&"car": {"tall": false, "cover": true},
	&"truck": {"tall": false, "cover": true},
	&"bus": {"tall": false, "cover": true},
	&"dumpster": {"tall": false, "cover": true},
	&"barrels": {"tall": false, "cover": true},
	&"sandbags": {"tall": false, "cover": true},
	&"barrier": {"tall": false, "cover": true},
	&"stall": {"tall": false, "cover": true},
	&"crate": {"tall": false, "cover": true},
	&"planter": {"tall": false, "cover": true},
	&"dugout": {"tall": false, "cover": true},
	&"boat": {"tall": false, "cover": true},
	&"cabana": {"tall": false, "cover": true},
	&"hay": {"tall": false, "cover": true},
	&"table": {"tall": false, "cover": true},
	&"fence": {"tall": false, "cover": false},
	&"pad": {}, &"grass": {}, &"boards": {}, &"dirt": {}, &"water": {},
}

## Each team starts in a zone behind a vertical line this far from the middle (x = +-START_X).
const START_X := 35.0

## Props whose look is part of the place (structure, containers, trees, hedges, stands) are never re-skinned.
const FIXED_SKINS: Array[StringName] = [&"wall", &"fence", &"bleachers", &"hedge", &"container", &"tree"]

## Cover-equivalent skins. The reflected copy of a prop keeps its footprint and class, so cover is
## identical on both sides, but it is drawn as something else from the same group. Themed kinds
## (boats, dugouts, stalls, cabanas, hay) only ever appear as authored, never as a swap.
const SKINS_COVER_LONG: Array[StringName] = [&"car", &"truck", &"sandbags", &"barrier", &"barrels", &"crate", &"planter"]
const SKINS_COVER_COMPACT: Array[StringName] = [&"dumpster", &"crate", &"planter", &"barrels", &"table"]
const SKINS_TALL_COMPACT: Array[StringName] = [&"pillar", &"wall"]

## The legacy field: one quadrant (x < 0, y < 0) as [center, size], mirrored on both axes.
const _WALLS_Q := [
	[Vector2(-30, -13), Vector2(2, 8)],
	[Vector2(-14, -6), Vector2(2, 7)],
	[Vector2(-12, -22), Vector2(10, 2)],
]
const _CRATES_Q := [
	[Vector2(-37, -8), Vector2(3, 3)],
	[Vector2(-22, -17), Vector2(3, 3)],
	[Vector2(-7.5, -12), Vector2(3, 2)],
	[Vector2(-22, -2.5), Vector2(2.5, 2.5)],
	[Vector2(0, -9), Vector2(4, 2)],
]

## Spawn, hold and overwatch spots per slot live in Scheme.LAYOUTS (team-0 frame).
## Left flex's flank route (right flex mirrors it on y), walked as flank progress builds.
const FLANK := [Vector2(-32, -26.5), Vector2(-12, -26.5), Vector2(10, -18.5)]

static var _cache: Dictionary = {}
static var _fields_json: Dictionary = {}
static var _fields_loaded := false

var id := "legacy"
var venue := "Proving Grounds"
var surface := "concrete"
## Every prop, mirrored: {"k": StringName, "rect": Rect2, "color": String}.
var props: Array[Dictionary] = []
var walls: Array[Rect2] = []  # tall: block sight
var crates: Array[Rect2] = []  # low cover
var obstacles: Array[Rect2] = []  # everything that blocks movement
## Obstacles grown by the soldier radius (for movement).
var _grown: Array[Rect2] = []
var nodes: Array[Vector2] = []
var _dist: Array = []  # Array[PackedFloat32Array]
var _next: Array = []  # Array[PackedInt32Array]
var _built := false
var _vis_cache: Dictionary = {}
var _goal_cache: Dictionary = {}
## Spots hugging each obstacle side, for soldiers looking for cover.
var cover_spots: Array[Vector2] = []


# --- construction ----------------------------------------------------------------

## Team-frame point `t` (0..1) along the flank route; `right` mirrors it to the other side.
static func flank_point(t: float, right: bool) -> Vector2:
	var seg_count := FLANK.size() - 1
	var f := clampf(t, 0.0, 1.0) * seg_count
	var i := mini(int(f), seg_count - 1)
	var p: Vector2 = (FLANK[i] as Vector2).lerp(FLANK[i + 1], f - i)
	return Vector2(p.x, -p.y) if right else p


## The field a team plays its home games on (the legacy layout if it has none).
static func for_team(abbrev: String) -> ArenaMap:
	if _cache.has(abbrev):
		return _cache[abbrev]
	_load_json()
	var field: ArenaMap
	if _fields_json.has(abbrev):
		field = from_data(abbrev, _fields_json[abbrev])
	else:
		field = legacy()
	_cache[abbrev] = field
	return field


## Abbreviations that have an authored field.
static func authored() -> Array:
	_load_json()
	return _fields_json.keys()


static func legacy() -> ArenaMap:
	if _cache.has(""):
		return _cache[""]
	var field := ArenaMap.new()
	for e in _WALLS_Q:
		field._add_quad(&"wall", e[0], e[1])
	for e in _CRATES_Q:
		field._add_quad(&"crate", e[0], e[1])
	_cache[""] = field
	return field


## The kind a prop's reflection is drawn as: same class (tall or low cover) and aspect, so the
## footprint and cover value match, but a different object. Walls, fences and decals stay as they are.
static func mirror_skin(kind: StringName, c: Vector2, size: Vector2, surface := "concrete") -> StringName:
	var def: Dictionary = KINDS[kind]
	if def.is_empty() or kind in FIXED_SKINS:
		return kind
	var long := maxf(size.x, size.y)
	var short := minf(size.x, size.y)
	var elongated := long >= short * 2.2
	var pool: Array[StringName] = []
	if def["tall"]:
		if not elongated:
			pool = SKINS_TALL_COMPACT
	else:
		pool = SKINS_COVER_LONG if elongated else SKINS_COVER_COMPACT
	var options: Array[StringName] = []
	for k in pool:
		if k != kind:
			options.append(k)
	# Greenery only grows on turf and sand.
	if def["tall"] and not elongated and (surface == "turf" or surface == "sand"):
		options.append(&"tree")
	if options.is_empty():
		return kind
	var h := (int(roundf(c.x * 10.0)) * 73856093) ^ (int(roundf(c.y * 10.0)) * 19349663)
	return options[absi(h) % options.size()]


## A field from its authored entry: {name, surface, sym, props: [{k, x, y, w, h, c?}]}. Props are
## listed once and reflected here ("point" by default, "quad" for both axes). Reflected copies are
## re-skinned (see mirror_skin) unless the entry says "vary": false.
static func from_data(abbrev: String, d: Dictionary) -> ArenaMap:
	var field := ArenaMap.new()
	field.id = abbrev
	field.venue = d.get("name", abbrev)
	field.surface = d.get("surface", "concrete")
	var quad: bool = d.get("sym", "point") == "quad"
	var vary: bool = d.get("vary", true)
	for p in d.get("props", []):
		var kind := StringName(p["k"])
		var c := Vector2(p["x"], p["y"])
		var size := Vector2(p["w"], p["h"])
		var color: String = p.get("c", "")
		if quad:
			field._add_quad(kind, c, size, color)
		else:
			field._add_prop(kind, c, size, color)
			field._add_prop(mirror_skin(kind, c, size, field.surface) if vary else kind, -c, size, color)
	return field


static func _load_json() -> void:
	if _fields_loaded:
		return
	_fields_loaded = true
	if not FileAccess.file_exists(FIELDS_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIELDS_PATH))
	if parsed is Dictionary:
		_fields_json = parsed


func _add_quad(kind: StringName, c: Vector2, size: Vector2, color := "") -> void:
	for m in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		_add_prop(kind, c * m, size, color)


## Adds a prop unless an identical one (a prop on a mirror axis) is already there.
func _add_prop(kind: StringName, c: Vector2, size: Vector2, color := "") -> void:
	if not KINDS.has(kind):
		push_error("unknown prop kind %s" % kind)
		return
	var r := Rect2(c - size / 2.0, size)
	for p in props:
		if p["k"] == kind and (p["rect"] as Rect2).is_equal_approx(r):
			return
	props.append({"k": kind, "rect": r, "color": color})
	var def: Dictionary = KINDS[kind]
	if def.is_empty():
		return
	obstacles.append(r)
	if def["tall"]:
		walls.append(r)
	elif def["cover"]:
		crates.append(r)


func ensure_built() -> void:
	if _built:
		return
	_built = true
	for r in obstacles:
		_grown.append(r.grow(SOLDIER_RADIUS))
	_build_nav()
	_build_cover_spots()


# --- geometry --------------------------------------------------------------------

## Team frame -> world (team 1 is the point reflection).
static func world(team: int, p: Vector2) -> Vector2:
	return p if team == 0 else -p


static func in_bounds(p: Vector2, r := SOLDIER_RADIUS) -> bool:
	return absf(p.x) <= HALF.x - r and absf(p.y) <= HALF.y - r


## True if a soldier centred at p overlaps an obstacle or the map edge.
func blocked(p: Vector2) -> bool:
	if not in_bounds(p):
		return true
	for r in _grown:
		if r.has_point(p):
			return true
	return false


static func on_hill(p: Vector2) -> bool:
	return HILL.has_point(p)


## Tall props block sight; low ones don't.
func line_of_sight(a: Vector2, b: Vector2) -> bool:
	var box := _seg_box(a, b)
	for r in walls:
		if r.intersects(box, true) and seg_hits_rect(a, b, r):
			return false
	return true


## A shot from a to b crosses low cover (the target is behind it).
func through_cover(a: Vector2, b: Vector2) -> bool:
	var box := _seg_box(a, b)
	for r in crates:
		if r.intersects(box, true) and seg_hits_rect(a, b, r):
			return true
	return false


## Straight walk from a to b doesn't clip any obstacle.
func walk_clear(a: Vector2, b: Vector2) -> bool:
	var box := _seg_box(a, b)
	for r in _grown:
		if r.intersects(box, true) and seg_hits_rect(a, b, r):
			return false
	return true


## The segment's bounding box (a cheap native pre-check before the exact segment test).
static func _seg_box(a: Vector2, b: Vector2) -> Rect2:
	return Rect2(minf(a.x, b.x), minf(a.y, b.y), absf(b.x - a.x), absf(b.y - a.y))


## Liang-Barsky segment vs axis-aligned rect.
static func seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var lo := r.position
	var hi := r.end
	if (a.x < lo.x and b.x < lo.x) or (a.x > hi.x and b.x > hi.x) \
			or (a.y < lo.y and b.y < lo.y) or (a.y > hi.y and b.y > hi.y):
		return false
	var dx := b.x - a.x
	var dy := b.y - a.y
	var t0 := 0.0
	var t1 := 1.0
	if absf(dx) < 0.000001:
		if a.x < lo.x or a.x > hi.x:
			return false
	else:
		var ta := (lo.x - a.x) / dx
		var tb := (hi.x - a.x) / dx
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	if absf(dy) < 0.000001:
		if a.y < lo.y or a.y > hi.y:
			return false
	else:
		var ta := (lo.y - a.y) / dy
		var tb := (hi.y - a.y) / dy
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	return true


# --- navigation -----------------------------------------------------------------

func _build_nav() -> void:
	for r in obstacles:
		var g := r.grow(NODE_MARGIN)
		for p in [g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]:
			if not blocked(p):
				nodes.append(p)
	var n := nodes.size()
	for i in n:
		var d := PackedFloat32Array()
		var nx := PackedInt32Array()
		d.resize(n)
		nx.resize(n)
		for j in n:
			d[j] = 0.0 if i == j else INF
			nx[j] = j if i == j else -1
		_dist.append(d)
		_next.append(nx)
	for i in n:
		var di: PackedFloat32Array = _dist[i]
		var ni: PackedInt32Array = _next[i]
		for j in n:
			if i != j and walk_clear(nodes[i], nodes[j]):
				di[j] = nodes[i].distance_to(nodes[j])
				ni[j] = j
		_dist[i] = di
		_next[i] = ni
	for k in n:
		var dk: PackedFloat32Array = _dist[k]
		for i in n:
			var di: PackedFloat32Array = _dist[i]
			var dik := di[k]
			if dik == INF:
				continue
			var ni: PackedInt32Array = _next[i]
			for j in n:
				var alt := dik + dk[j]
				if alt < di[j]:
					di[j] = alt
					ni[j] = ni[k]
			_dist[i] = di
			_next[i] = ni


## Next point to walk toward on the way from `from` to `to`: `to` itself when the straight line is
## clear, otherwise the first waypoint of the shortest route through the nav graph. Visibility
## from 1 m cells and per-goal-cell route costs are cached, so planning stays cheap.
func next_waypoint(from: Vector2, to: Vector2) -> Vector2:
	if walk_clear(from, to):
		return to
	var costs := _goal_costs(to)
	var best := INF
	var best_node := -1
	for a in _visible_nodes(from):
		var p := nodes[a]
		var da := from.distance_to(p)
		# Standing on a node: route through its neighbours instead of back to it.
		if da < 0.6:
			continue
		var cost := da + costs[a]
		if cost < best:
			best = cost
			best_node = a
	if best_node == -1:
		return to
	return nodes[best_node]


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


func _visible_nodes(p: Vector2) -> PackedInt32Array:
	var key := _cell(p)
	if _vis_cache.has(key):
		return _vis_cache[key]
	var centre := Vector2(key) + Vector2(0.5, 0.5)
	var out := PackedInt32Array()
	for i in nodes.size():
		if walk_clear(centre, nodes[i]):
			out.append(i)
	_vis_cache[key] = out
	return out


## For every nav node: cheapest route length from it to the goal cell.
func _goal_costs(goal: Vector2) -> PackedFloat32Array:
	var key := _cell(goal)
	if _goal_cache.has(key):
		return _goal_cache[key]
	var centre := Vector2(key) + Vector2(0.5, 0.5)
	var ends := _visible_nodes(goal)
	var out := PackedFloat32Array()
	out.resize(nodes.size())
	for a in nodes.size():
		var row: PackedFloat32Array = _dist[a]
		var best := INF
		for b in ends:
			var c := row[b] + nodes[b].distance_to(centre)
			if c < best:
				best = c
		out[a] = best
	_goal_cache[key] = out
	return out


func _build_cover_spots() -> void:
	var off := SOLDIER_RADIUS + 0.3
	for r in obstacles:
		var c := r.get_center()
		for p in [Vector2(r.position.x - off, c.y), Vector2(r.end.x + off, c.y),
				Vector2(c.x, r.position.y - off), Vector2(c.x, r.end.y + off)]:
			if not blocked(p):
				cover_spots.append(p)


## Closest cover spot within `radius` of `p` that hides it from `threat` (behind a wall, or with a
## crate in between). Vector2.INF if none.
func find_cover(p: Vector2, threat: Vector2, radius: float) -> Vector2:
	var best := Vector2.INF
	var best_d := radius * radius
	for s in cover_spots:
		var d := p.distance_squared_to(s)
		if d > best_d:
			continue
		if not line_of_sight(threat, s) or through_cover(threat, s):
			best = s
			best_d = d
	return best
