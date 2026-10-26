class_name ArenaMap
extends RefCounted
## The one arena every match is played on, in metres with (0, 0) at the middle of the hill.
## Team 0 spawns on the left (-x) facing right; team 1 is the point reflection (x, y) -> (-x, -y),
## so "left" for either team is the same side relative to its own facing.
##
## Walls are tall: they block movement and line of sight. Crates are waist high: they block
## movement and give a soldier hugging them cover (shots crossing a crate are less likely to hit),
## but don't block line of sight. The layout is mirrored on both axes so neither side or flank is
## favoured. Movement uses straight lines where clear, otherwise a precomputed waypoint graph
## around obstacle corners (built once per process).

const HALF := Vector2(48.0, 30.0)
const SOLDIER_RADIUS := 0.8
## Nav nodes sit this far out from each obstacle corner.
const NODE_MARGIN := 1.7
const HILL := Rect2(-5.0, -5.0, 10.0, 10.0)

## One quadrant (x < 0, y < 0) of the layout as [center, size]; mirrored on both axes.
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

## Team-0 frame. Spawn formation is the Swing: two frontmen up, the center behind them,
## flexes far out on each side.
const SPAWN := {
	&"FM1": Vector2(-40, -4), &"FM2": Vector2(-40, 4), &"CTR": Vector2(-44, 0),
	&"LFX": Vector2(-41, -19), &"RFX": Vector2(-41, 19),
}
## Where each slot settles in a deathmatch: frontmen just in front of the mid walls, the center
## watching the middle lane, flexes running the outside lanes (start -> end of the flank).
const HOLD := {
	&"FM1": Vector2(-6, -9), &"FM2": Vector2(-6, 9), &"CTR": Vector2(-25, 0),
}
## Left flex's flank route (right flex mirrors it on y), walked as flank progress builds.
const FLANK := [Vector2(-32, -26.5), Vector2(-12, -26.5), Vector2(10, -18.5)]
## KOTH overwatch for soldiers not playing the point.
const OVERWATCH := {
	&"FM1": Vector2(-10, -9), &"FM2": Vector2(-10, 9), &"CTR": Vector2(-21, 0),
}


## Team-frame point `t` (0..1) along the flank route; `right` mirrors it to the other side.
static func flank_point(t: float, right: bool) -> Vector2:
	var seg_count := FLANK.size() - 1
	var f := clampf(t, 0.0, 1.0) * seg_count
	var i := mini(int(f), seg_count - 1)
	var p: Vector2 = (FLANK[i] as Vector2).lerp(FLANK[i + 1], f - i)
	return Vector2(p.x, -p.y) if right else p

static var walls: Array[Rect2] = []
static var crates: Array[Rect2] = []
static var obstacles: Array[Rect2] = []
## Obstacles grown by the soldier radius (for movement).
static var _grown: Array[Rect2] = []
static var nodes: Array[Vector2] = []
static var _dist: Array = []  # Array[PackedFloat32Array]
static var _next: Array = []  # Array[PackedInt32Array]
static var _built := false


static func ensure_built() -> void:
	if _built:
		return
	_built = true
	walls = _mirror_all(_WALLS_Q)
	crates = _mirror_all(_CRATES_Q)
	obstacles.assign(walls + crates)
	for r in obstacles:
		_grown.append(r.grow(SOLDIER_RADIUS))
	_build_nav()
	_build_cover_spots()


static func _mirror_all(quadrant: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for entry in quadrant:
		var c: Vector2 = entry[0]
		var size: Vector2 = entry[1]
		for m in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var r := Rect2(c * m - size / 2.0, size)
			var dup := false
			for o in out:
				if o.is_equal_approx(r):
					dup = true
			if not dup:
				out.append(r)
	return out


## Team frame -> world (team 1 is the point reflection).
static func world(team: int, p: Vector2) -> Vector2:
	return p if team == 0 else -p


static func spawn_point(team: int, slot: StringName) -> Vector2:
	return world(team, SPAWN.get(slot, Vector2(-42, 0)))


static func in_bounds(p: Vector2, r := SOLDIER_RADIUS) -> bool:
	return absf(p.x) <= HALF.x - r and absf(p.y) <= HALF.y - r


## True if a soldier centred at p overlaps an obstacle or the map edge.
static func blocked(p: Vector2) -> bool:
	if not in_bounds(p):
		return true
	for r in _grown:
		if r.has_point(p):
			return true
	return false


static func on_hill(p: Vector2) -> bool:
	return HILL.has_point(p)


## Tall walls block sight; crates don't.
static func line_of_sight(a: Vector2, b: Vector2) -> bool:
	var box := _seg_box(a, b)
	for r in walls:
		if r.intersects(box, true) and seg_hits_rect(a, b, r):
			return false
	return true


## A shot from a to b crosses a crate (the target is behind cover).
static func through_cover(a: Vector2, b: Vector2) -> bool:
	var box := _seg_box(a, b)
	for r in crates:
		if r.intersects(box, true) and seg_hits_rect(a, b, r):
			return true
	return false


## Straight walk from a to b doesn't clip any obstacle.
static func walk_clear(a: Vector2, b: Vector2) -> bool:
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

static func _build_nav() -> void:
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
static func next_waypoint(from: Vector2, to: Vector2) -> Vector2:
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


static var _vis_cache: Dictionary = {}
static var _goal_cache: Dictionary = {}


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


static func _visible_nodes(p: Vector2) -> PackedInt32Array:
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
static func _goal_costs(goal: Vector2) -> PackedFloat32Array:
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


## Spots hugging each obstacle side, for soldiers looking for cover.
static var cover_spots: Array[Vector2] = []


static func _build_cover_spots() -> void:
	var off := SOLDIER_RADIUS + 0.3
	for r in obstacles:
		var c := r.get_center()
		for p in [Vector2(r.position.x - off, c.y), Vector2(r.end.x + off, c.y),
				Vector2(c.x, r.position.y - off), Vector2(c.x, r.end.y + off)]:
			if not blocked(p):
				cover_spots.append(p)


## Closest cover spot within `radius` of `p` that hides it from `threat` (behind a wall, or with a
## crate in between). Vector2.INF if none.
static func find_cover(p: Vector2, threat: Vector2, radius: float) -> Vector2:
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
