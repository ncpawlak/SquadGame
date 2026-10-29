class_name FieldDesigns
extends RefCounted
## Hand-designed fields, one per team (see tools/build_fields.gd, which writes them to data/fields.json).
## Each design lists the LEFT half of a field in metres; the game reflects it through the middle, so
## whatever is in the north-left appears in the south-right. Everything is axis-aligned rectangles.
##
## The left half is a ring of cells around the street that runs through the middle (y = 0):
##   x -34.4 .. -14.6 and y -24 .. -8 (north) or 8 .. 24 (south) hold buildings and yards;
##   the street cells x -34.4 .. -27.4 and -18.6 .. -13.6 are open for vehicles and street furniture;
##   x -27.2 .. -18.8, y -7.2 .. 7.2 is where the schemes hold ground, so it stays empty (decals only).
## Spawns sit beyond x -35 and the flank routes run along y = +-26.5.

const T := 1.2
const DOOR := 3.4
const CAR_COLORS := ["#b3392f", "#2f5fa8", "#c9c9c9", "#e0b83a", "#3d3d42", "#2f8f5b", "#d9822b", "#7a3fa0"]

## abbrev, venue, surface, design method.
const LIST := [
	["NYE", "Empire Block", "asphalt", "nye"],
	["DET", "Ironworks", "concrete", "det"],
	["LAS", "Sunset Strip", "asphalt", "las"],
	["BOS", "Minuteman Common", "turf", "bos"],
	["SEA", "Storm Harbor", "concrete", "sea"],
	["ARL", "Outlaw Ranch", "sand", "arl"],
	["CHI", "Lower Wacker", "concrete", "chi"],
	["STL", "Gateway Riverfront", "concrete", "stl"],
	["CHA", "Queen City Plaza", "concrete", "cha"],
	["SDV", "Viper Bay", "sand", "sdv"],
	["REN", "Biggest Little Strip", "asphalt", "ren"],
	["ATL", "Hartsfield Apron", "concrete", "atl"],
	["IND", "The Brickyard", "asphalt", "ind"],
	["MIA", "Pirates Cove", "sand", "mia"],
	["DEN", "Rocky Ridge Camp", "turf", "den"],
	["BKN", "Bridge Anchorage", "asphalt", "bkn"],
	["NSH", "Honky-Tonk Row", "concrete", "nsh"],
	["ORL", "Comet Gardens", "turf", "orl"],
	["LOU", "Churchill Flats", "turf", "lou"],
	["LRK", "Riverfront Sandbar", "sand", "lrk"],
]

var out: Array = []
var _car_i := 0
## The first-pass designs were drawn inside a safe box (clear of the old keep-outs); the redesigned ones
## turn this off and use the whole field.
var _clamp := true
## Width of an ordinary doorway (the redesigned fields use narrower ones).
var _door := DOOR

## Safe box for clamped designs.
const LIMIT_X0 := -34.9
const LIMIT_X1 := -13.9
const LIMIT_Y := 23.3


func build(method: String) -> Array:
	out = []
	_car_i = 0
	_clamp = true
	_door = DOOR
	call("d_" + method)
	return out


# --- primitives (corner coordinates) ---------------------------------------------------

func r(k: String, x0: float, y0: float, x1: float, y1: float, c := "") -> void:
	if _clamp and not ArenaMap.KINDS[StringName(k)].is_empty():
		x0 = maxf(x0, LIMIT_X0)
		x1 = minf(x1, LIMIT_X1)
		y0 = maxf(y0, -LIMIT_Y)
		y1 = minf(y1, LIMIT_Y)
	var d := {"k": k, "x": snappedf((x0 + x1) / 2.0, 0.05), "y": snappedf((y0 + y1) / 2.0, 0.05),
		"w": snappedf(absf(x1 - x0), 0.05), "h": snappedf(absf(y1 - y0), 0.05)}
	if c != "":
		d["c"] = c
	out.append(d)


func _color() -> String:
	_car_i += 1
	return CAR_COLORS[_car_i % CAR_COLORS.size()]


func car(x: float, y: float, horiz := true, c := "") -> void:
	var col := c if c != "" else _color()
	if horiz:
		r("car", x - 2.3, y - 1.0, x + 2.3, y + 1.0, col)
	else:
		r("car", x - 1.0, y - 2.3, x + 1.0, y + 2.3, col)


## n cars in a row from (x, y), stepping along the long axis.
func cars(x: float, y: float, n: int, horiz := true, gap := 0.8) -> void:
	for i in n:
		var step := i * (4.6 + gap)
		car(x + step, y, true) if horiz else car(x, y + step, false)


func truck(x: float, y: float, horiz := true, c := "", kind := "truck") -> void:
	var col := c if c != "" else _color()
	if horiz:
		r(kind, x - 3.75, y - 1.3, x + 3.75, y + 1.3, col)
	else:
		r(kind, x - 1.3, y - 3.75, x + 1.3, y + 3.75, col)


func tree(x: float, y: float, s := 3.4) -> void:
	r("tree", x - s / 2.0, y - s / 2.0, x + s / 2.0, y + s / 2.0)


func pillar(x: float, y: float, s := 1.8) -> void:
	r("pillar", x - s / 2.0, y - s / 2.0, x + s / 2.0, y + s / 2.0)


func planter(x: float, y: float) -> void:
	r("planter", x - 1.1, y - 1.1, x + 1.1, y + 1.1)


func hay(x: float, y: float) -> void:
	r("hay", x - 1.2, y - 1.2, x + 1.2, y + 1.2)


## Any cover rectangle by centre and size.
func cover(kind: String, x: float, y: float, w: float, h: float) -> void:
	r(kind, x - w / 2.0, y - h / 2.0, x + w / 2.0, y + h / 2.0)


func crate(x: float, y: float, s := 2.4) -> void:
	r("crate", x - s / 2.0, y - s / 2.0, x + s / 2.0, y + s / 2.0)


func barrels(x: float, y: float) -> void:
	r("barrels", x - 0.8, y - 0.8, x + 0.8, y + 0.8)


func container(x0: float, y0: float, horiz := true) -> void:
	if horiz:
		r("container", x0, y0, x0 + 6.1, y0 + 2.6)
	else:
		r("container", x0, y0, x0 + 2.6, y0 + 6.1)


## Door gaps are a centre or a [centre, width] pair.
func _cuts(a: float, b: float, gaps: Array) -> Array:
	var segs: Array = []
	var cur := a
	var g: Array = []
	for e in gaps:
		g.append([e[0], e[1]] if e is Array else [e, _door])
	g.sort_custom(func(u, v): return u[0] < v[0])
	for e in g:
		var lo: float = e[0] - e[1] / 2.0
		if lo > cur + 0.3:
			segs.append([cur, lo])
		cur = e[0] + e[1] / 2.0
	if b > cur + 0.3:
		segs.append([cur, b])
	return segs


## A wall along x from x0 to x1 centred on y, with doorways centred at `gaps`.
func wall_h(x0: float, x1: float, y: float, gaps := []) -> void:
	for s in _cuts(x0, x1, gaps):
		r("wall", s[0], y - T / 2.0, s[1], y + T / 2.0)


func wall_v(y0: float, y1: float, x: float, gaps := []) -> void:
	for s in _cuts(y0, y1, gaps):
		r("wall", x - T / 2.0, s[0], x + T / 2.0, s[1])


## A walled building (outer rectangle) with doorways per side ("n", "s", "w", "e") at absolute
## coordinates, plus an interior floor tint.
func bld(x0: float, y0: float, x1: float, y1: float, doors := {}) -> void:
	r("pad", x0 + T, y0 + T, x1 - T, y1 - T, "interior")
	wall_h(x0, x1, y0 + T / 2.0, doors.get("n", []))
	wall_h(x0, x1, y1 - T / 2.0, doors.get("s", []))
	wall_v(y0 + T, y1 - T, x0 + T / 2.0, doors.get("w", []))
	wall_v(y0 + T, y1 - T, x1 - T / 2.0, doors.get("e", []))


## Thin fences and hedges (tall) along an axis, with gaps.
func fence_h(x0: float, x1: float, y: float) -> void:
	r("fence", x0, y - 0.15, x1, y + 0.15)


func fence_v(y0: float, y1: float, x: float) -> void:
	r("fence", x - 0.15, y0, x + 0.15, y1)


func hedge_h(x0: float, x1: float, y: float, gaps := []) -> void:
	for seg in _cuts(x0, x1, gaps):
		r("hedge", seg[0], y - 0.6, seg[1], y + 0.6)


func hedge_v(y0: float, y1: float, x: float, gaps := []) -> void:
	for seg in _cuts(y0, y1, gaps):
		r("hedge", x - 0.6, seg[0], x + 0.6, seg[1])


# --- the designs -----------------------------------------------------------------------

## New York: buildings packed shoulder to shoulder, room to room, with an open park in the middle that
## holds the objective. Each half is one block of rooms (a central hall plus three columns of rooms above
## and below it) with an alley around it for the flank routes; the doors are placed so every room opens
## onto a neighbour. The reflected block gets different cover in the same places.
func d_nye() -> void:
	_clamp = false
	_door = 2.6
	var w := -34.2
	var e := -13.0
	var n := -22.4
	var so := 22.4
	r("grass", -12.4, -24.6, 0, 24.6)
	# Shell: alleys run outside the north and south walls, the start area is beyond the west wall and
	# the park is beyond the east wall.
	wall_h(w - 0.6, e + 0.6, n, [-31, -24, -16.5])
	wall_h(w - 0.6, e + 0.6, so, [-30, -22, -15.8])
	wall_v(n + 0.6, so - 0.6, w, [-15, -3.5, 3.5, 12.5, 19.1])
	wall_v(n + 0.6, so - 0.6, e, [-15, [0, 10], 15])
	r("pad", w + 0.6, n + 0.6, e - 0.6, so - 0.6, "interior")
	# North of the hall: three rooms, the middle one split in two.
	wall_v(n + 0.6, -9.9, -28.0, [-19])
	wall_v(n + 0.6, -9.9, -19.0, [-12.5])
	wall_h(-27.4, -19.6, -15.8, [-23.5])
	wall_h(w + 0.6, e - 0.6, -9.3, [-31, -23.5, [-16, 4]])
	# South of the hall: the left room is split in two instead.
	wall_v(9.9, so - 0.6, -25.0, [12.5])
	wall_v(9.9, so - 0.6, -18.0, [19.1])
	wall_h(w + 0.6, -25.6, 15.8, [-30])
	wall_h(w + 0.6, e - 0.6, 9.3, [-31, -22, [-15.5, 4]])
	# Cover: a little in the rooms (kept clear of doorways) and more in the hall.
	cover("crate", -30.0, -15.0, 2.0, 2.0)
	cover("table", -22.0, -20.8, 2.6, 1.2)
	cover("crate", -23.8, 16.0, 2.0, 2.0)
	cover("crate", -29.0, 0.0, 2.4, 2.4)
	cover("crate", -17.4, 0.0, 2.2, 2.2)
	cover("barrier", -17.4, -5.0, 3.6, 1.0)
	cover("barrier", -17.4, 5.0, 3.6, 1.0)
	# The park: open, with a few trees, benches and low walls at the edges.
	tree(-9.4, -14.0, 3.0)
	tree(-9.4, 14.0, 3.0)
	cover("table", -3.6, -13.6, 3.4, 1.2)
	cover("table", -3.6, 13.6, 3.4, 1.2)
	planter(-8.8, -4.6)
	planter(-8.8, 4.6)
	cover("barrier", -2.4, -16.4, 4.0, 1.0)
	cover("barrier", -2.4, 16.4, 4.0, 1.0)


## Boston: a ballpark. The infield dirt is in the middle with the hill on the mound, grandstands behind
## each starting area, a Green Monster along the outfield, dugouts, a bullpen and a concession stand. It
## is the most open field: cover is at the edges, the middle is a fair fight.
func d_bos() -> void:
	_clamp = false
	r("dirt", -11.5, -11.5, 0, 11.5)
	# Grandstands, with an aisle straight out of each starting area.
	r("bleachers", -34.8, -24.5, -31.4, -9.5)
	r("bleachers", -34.8, 9.5, -31.4, 24.5)
	r("bleachers", -31.4, -24.5, -25.0, -21.5)
	r("bleachers", -31.4, 21.5, -28.0, 24.5)
	# The Green Monster and a foul pole.
	r("hedge", -26.5, -18.4, -13.5, -16.8)
	pillar(-13.0, -21.5, 1.4)
	# Dugouts, a bullpen and the concession stand.
	r("dugout", -30.0, -12.6, -23.0, -10.2)
	r("dugout", -30.0, 10.2, -23.0, 12.6)
	r("fence", -24.0, 14.85, -15.0, 15.15)
	r("fence", -24.0, 20.85, -20.0, 21.15)
	r("fence", -24.15, 15.0, -23.85, 21.0)
	r("fence", -15.15, 15.0, -14.85, 21.0)
	cover("table", -21.0, 17.5, 2.6, 1.2)
	cover("table", -18.0, 19.5, 2.6, 1.2)
	bld(-22.0, -14.0, -16.0, -9.0, {"s": [-19.0], "n": [-19.0]})
	cover("crate", -14.5, 20.0, 1.6, 1.6)
	cover("barrels", -14.5, -8.0, 1.6, 1.6)


## Reno: a casino in the middle of the field, with open parking lots around it. The hill is on the gaming
## floor; slot banks and tables give it cover. Outside, cars and shuttles are the cover, and the lots
## are wide open between them.
func d_ren() -> void:
	_clamp = false
	r("pad", -14.4, -14.4, 0, 14.4, "interior")
	# The casino shell: a wide entrance on each team's side, smaller doors in the corners.
	wall_v(-14.4, 14.4, -15, [[0, 7], -10.5, 10.5])
	wall_h(-15.6, 0, -15, [-8])
	wall_h(-15.6, 0, 15, [-6.5])
	# Gaming floor.
	r("stall", -13.8, -5.2, -8.8, -3.9)
	r("stall", -13.8, 3.9, -8.8, 5.2)
	r("stall", -13.8, -13.6, -9.6, -12.4)
	r("stall", -13.8, 12.4, -9.6, 13.6)
	pillar(-3.0, -12.5, 1.6)
	pillar(-3.0, 12.5, 1.6)
	cover("table", -2.0, -7.6, 2.8, 1.2)
	cover("table", -2.0, 7.6, 2.8, 1.2)
	# Parking lots.
	car(-31.5, -19, false)
	car(-29.0, -19, false)
	car(-31.5, 10, false)
	car(-29.0, 10, false)
	car(-24.0, -15.5, true)
	car(-19.1, -15.5, true)
	car(-24.0, 15.5, true)
	car(-19.1, 15.5, true)
	truck(-31.0, 0.0, false, "#c9c9c9")
	truck(-22.5, 21.5, true, "#2f5fa8", "bus")
	truck(-22.5, -21.5, true, "#e0b83a", "bus")
	cover("barrels", -33.0, -8.0, 1.6, 1.6)
	cover("barrels", -33.0, 8.0, 1.6, 1.6)
	pillar(-27.0, -23.5, 1.0)
	pillar(-17.0, 23.5, 1.0)


## Brooklyn: Coney Island. A boardwalk down each side by the starting areas with arcades facing it, a roller
## coaster's support columns, a bumper-car pen and snack stalls. The middle is open asphalt around the hill.
func d_bkn() -> void:
	_clamp = false
	r("boards", -34.8, -24.5, -30.8, 24.5)
	# Arcades on the boardwalk.
	bld(-30.8, -24.3, -22.0, -15.0, {"w": [-19.7], "s": [-26.5], "e": [-19.7]})
	bld(-30.8, 10.0, -25.0, 19.0, {"w": [14.5], "n": [-28.0], "e": [14.5]})
	# The coaster: support columns in a line, with a station at the north end.
	for y in [-22.0, -18.0, -14.0, -10.5, 19.0, 22.5]:
		pillar(-18.5, y, 1.2)
	bld(-17.0, -23.8, -13.4, -17.5, {"s": [-15.2], "w": [-21.0]})
	# The bumper-car pen, with a gate.
	r("fence", -22.0, 15.85, -14.5, 16.15)
	r("fence", -22.15, 8.4, -21.85, 16.0)
	r("fence", -14.65, 8.4, -14.35, 16.0)
	r("fence", -22.0, 8.25, -19.0, 8.55)
	r("fence", -16.5, 8.25, -14.5, 8.55)
	car(-19.6, 10.8, true)
	car(-17.4, 13.8, true)
	# Stalls and a service truck.
	cover("stall", -26.0, -9.5, 3.2, 1.8)
	cover("stall", -14.0, -5.5, 3.2, 1.8)
	cover("stall", -29.2, 6.0, 3.2, 1.8)
	truck(-32.9, 0.0, false, "#e0b83a")
	cover("barrels", -26.5, 21.5, 1.6, 1.6)
	cover("crate", -21.0, 21.5, 2.2, 2.2)
	cover("barrier", -12.5, -15.0, 1.0, 4.0)
	cover("planter", -13.4, 18.0, 1.8, 1.8)


## Detroit: assembly lines. Three parallel lines of machines run north to south with a conveyor barrier
## beside the first, steel columns between them, a control room and furnace blocks. The line-up is the
## cover: you fight along the lines, not across them.
func d_det() -> void:
	_clamp = false
	r("barrier", -32.1, -22.0, -31.1, -11.0)
	r("barrier", -32.1, -8.0, -31.1, 8.0)
	r("barrier", -32.1, 11.0, -31.1, 22.0)
	container(-30.2, -21.0, false)
	container(-30.2, -13.5, false)
	container(-30.2, 10.0, false)
	container(-30.2, 17.0, false)
	container(-24.6, -22.0, false)
	container(-24.6, -14.0, false)
	container(-24.6, 8.5, false)
	container(-24.6, 16.5, false)
	container(-18.4, -21.5, false)
	container(-18.4, 12.0, false)
	pillar(-15.0, -12.0, 2.0)
	pillar(-15.0, 12.0, 2.0)
	pillar(-15.0, -4.5, 2.0)
	pillar(-15.0, 4.5, 2.0)
	r("wall", -17.5, 18.0, -13.0, 22.5)
	r("wall", -14.0, -22.5, -12.6, -17.5)
	bld(-20.0, -14.0, -13.2, -8.6, {"w": [-11.3], "s": [-16.5]})
	crate(-29.0, 0.0, 2.4)
	crate(-21.0, -10.0, 2.2)
	crate(-21.5, 21.0, 2.4)
	barrels(-33.5, -12.0)
	barrels(-33.5, 14.0)
	truck(-26.0, 22.0, true, "#e0b83a")


## Los Angeles: a studio backlot. Free-standing set facades (thin walls) in a staggered scatter, trailers
## parked behind the starting areas, lights, dollies and prop crates. Almost nothing is a room; it is all
## screens to duck behind.
func d_las() -> void:
	_clamp = false
	r("wall", -31.0, -22.0, -30.0, -14.0)
	r("wall", -28.0, -12.0, -20.0, -11.0)
	r("wall", -21.0, -22.0, -20.0, -17.0)
	r("wall", -18.0, -16.0, -13.0, -15.0)
	r("wall", -27.0, 10.0, -26.0, 19.0)
	r("wall", -23.0, 12.0, -15.0, 13.0)
	r("wall", -20.0, -8.5, -13.0, -7.5)
	r("wall", -17.0, 17.0, -16.0, 22.0)
	r("wall", -33.0, 6.5, -29.0, 7.5)
	r("wall", -26.0, -22.5, -24.0, -21.5)
	truck(-33.3, -17.0, false, "#c9c9c9", "bus")
	truck(-33.3, -8.5, false, "#e0b83a")
	truck(-33.3, 13.0, false, "#2f5fa8", "bus")
	truck(-33.3, 21.0, false, "#c9c9c9")
	cover("table", -24.5, -17.0, 2.6, 1.2)
	cover("table", -22.0, 17.0, 2.6, 1.2)
	cover("crate", -29.0, -8.0, 2.4, 2.4)
	cover("crate", -29.0, 16.0, 2.4, 2.4)
	cover("crate", -15.0, 9.0, 2.2, 2.2)
	cover("barrels", -23.0, -9.0, 1.6, 1.6)
	cover("barrels", -25.0, 21.0, 1.6, 1.6)
	pillar(-26.5, -15.0, 0.9)
	pillar(-22.0, 21.0, 0.9)
	pillar(-14.5, -11.5, 0.9)
	pillar(-29.5, 12.0, 0.9)
	car(-18.0, -20.5, true)
	car(-31.5, 1.0, true)


## Seattle: a container yard. Stacks of containers in columns with aisles between them, a warehouse on
## the dock, gantry-crane legs and a truck bay, with the wet quay along the north and south edges.
func d_sea() -> void:
	_clamp = false
	r("water", -34.8, -28.5, 0, -26.0)
	for x0 in [-33.4, -28.4]:
		container(x0, -22.0, false)
		container(x0, -14.0, false)
	container(-23.4, -22.0, false)
	container(-23.4, -14.0, false)
	container(-18.4, -21.0, false)
	bld(-34.4, 9.5, -23.0, 22.8, {"n": [-28.0], "e": [16.0, 20.0], "w": [16.0]})
	truck(-18.5, 15.0, false, "#2f5fa8")
	crate(-19.5, 21.0, 3.0)
	crate(-15.8, 21.0, 2.4)
	pillar(-16.0, -10.5, 2.0)
	pillar(-16.0, 9.5, 2.0)
	pillar(-30.0, 3.5, 1.6)
	r("barrier", -22.0, 7.5, -17.0, 8.5)
	barrels(-14.5, 13.0)
	barrels(-14.5, -17.0)


## Arlington: a ranch round-up. A fenced pen around the objective with gates on each side, cattle chutes
## leading in from the west, a barn and stable, hay everywhere.
func d_arl() -> void:
	_clamp = false
	r("dirt", -13.4, -14.0, 0, 14.0)
	fence_v(-14.0, -2.0, -13.4)
	fence_v(2.0, 14.0, -13.4)
	fence_h(-13.4, -7.0, -14.0)
	fence_h(-4.0, 0.0, -14.0)
	fence_h(-13.4, -10.0, 14.0)
	fence_h(-7.0, 0.0, 14.0)
	fence_h(-19.0, -13.4, -2.1)
	fence_h(-19.0, -13.4, 2.1)
	hay(-9.0, -4.5)
	hay(-9.0, 4.5)
	hay(-3.0, -11.5)
	hay(-3.0, 11.5)
	bld(-34.6, -23.2, -27.0, -14.0, {"e": [-18.6], "s": [-30.0]})
	bld(-34.6, 10.0, -29.0, 19.5, {"e": [14.7], "n": [-31.8]})
	hay(-24.0, -18.0)
	hay(-21.5, -21.0)
	hay(-17.0, -18.5)
	hay(-25.5, 16.0)
	hay(-21.0, 19.5)
	hay(-17.0, 15.5)
	cover("barrier", -24.0, -9.5, 4.0, 1.0)
	cover("barrier", -24.0, 9.5, 4.0, 1.0)
	truck(-18.5, 21.0, true, "#b3392f")
	pillar(-28.0, 3.0, 1.8)


## Chicago: Lower Wacker. A forest of columns under the double-deck road, ramp walls, parked cars and a
## stair core. The columns block sight so the fights happen at corners and gaps.
func d_chi() -> void:
	_clamp = false
	for x in [-31.0, -23.0, -15.0]:
		for y in [-21.0, -13.0, 13.0, 21.0]:
			pillar(x, y, 2.0)
	r("wall", -27.5, -9.5, -19.5, -8.5)
	r("wall", -27.5, 8.5, -19.5, 9.5)
	r("wall", -34.0, -4.5, -33.0, 4.5)
	bld(-17.8, -7.0, -13.0, -2.5, {"w": [-4.7]})
	car(-27.0, -16.5, true)
	car(-19.5, -17.5, false)
	car(-27.0, 16.5, true)
	car(-19.0, 17.5, false)
	truck(-33.2, -12.0, false, "#e0b83a")
	cover("barrier", -31.0, 9.0, 4.0, 1.0)
	cover("crate", -15.5, 6.5, 2.2, 2.2)
	cover("barrels", -31.0, -4.0, 1.6, 1.6)


## St. Louis: the riverfront. The arch's legs are huge blocks either side of the objective, Laclede's Landing
## warehouses stand along the starting areas, steps run along the north levee and a plaza of trees and
## vendors fills the south.
func d_stl() -> void:
	_clamp = false
	r("wall", -17.2, -3.0, -13.2, 3.0)
	r("bleachers", -30.0, -24.4, -17.0, -21.2)
	bld(-34.5, -19.0, -28.5, -9.0, {"e": [-14.0], "w": [-14.0]})
	bld(-34.5, 9.0, -28.5, 19.0, {"e": [14.0], "s": [-31.5]})
	bld(-34.5, 19.5, -28.5, 23.5, {"e": [21.5]})
	for p in [[-24.0, 12.0], [-20.0, 12.0], [-24.0, 17.0], [-20.0, 17.0], [-15.5, 15.0]]:
		tree(p[0], p[1], 3.0)
	cover("stall", -16.5, -10.5, 3.2, 2.0)
	cover("stall", -26.0, -15.0, 3.2, 2.0)
	cover("table", -22.0, -17.0, 2.4, 1.2)
	cover("barrier", -14.5, 20.0, 4.0, 1.0)
	cover("crate", -28.0, 6.0, 2.2, 2.2)
	cover("planter", -28.0, -6.0, 2.0, 2.0)


## Charlotte: the uptown plaza. Bank towers as solid blocks, a fountain with a ring of planters, benches,
## and stepped terraces. All of it is open ground between big shapes.
func d_cha() -> void:
	_clamp = false
	r("wall", -33.5, -22.5, -26.0, -15.0)
	r("wall", -20.0, -22.5, -14.5, -17.0)
	r("water", -31.0, 10.0, -21.0, 20.0)
	for p in [[-32.0, 9.0], [-20.0, 9.0], [-32.0, 21.0], [-20.0, 21.0], [-26.0, 8.6], [-26.0, 21.4]]:
		planter(p[0], p[1])
	r("bleachers", -17.5, 10.0, -14.5, 21.5)
	cover("table", -24.0, -9.5, 2.8, 1.2)
	cover("table", -33.5, 2.0, 1.2, 2.8)
	cover("table", -33.5, -2.0, 1.2, 2.8)
	cover("barrier", -23.0, -17.0, 1.0, 4.0)
	tree(-17.0, -10.5, 2.8)
	r("stall", -29.5, -11.5, -26.5, -9.7)
	car(-16.0, -6.0, true)
	truck(-31.0, 4.0, true, "#c9c9c9", "bus")


## San Diego: a naval bay. The bay fills the south-west corner (and, reflected, the north-east), crossed
## by two piers with boats moored beside them; the dry corners hold sandbag bunkers, a Quonset hut and a
## watchtower.
func d_sdv() -> void:
	_clamp = false
	r("water", -34.8, 8.0, -12.0, 24.5)
	r("boards", -29.5, 8.0, -26.5, 24.5)
	r("boards", -21.0, 8.0, -18.0, 24.5)
	r("boat", -33.8, 11.0, -31.2, 18.5)
	r("boat", -25.3, 13.0, -22.7, 20.5)
	r("boat", -16.8, 12.0, -14.2, 19.5)
	r("sandbags", -31.0, -20.0, -24.0, -18.8)
	r("sandbags", -31.0, -20.0, -29.8, -14.0)
	r("sandbags", -31.0, -15.2, -24.0, -14.0)
	bld(-22.0, -22.8, -14.5, -15.0, {"s": [-18.0]})
	r("wall", -13.0, -15.1, -10.8, -12.9)
	crate(-28.0, -9.0, 2.2)
	barrels(-30.0, -23.0)
	cover("barrier", -17.0, -10.5, 4.0, 1.0)
	cover("crate", -33.0, 4.0, 2.2, 2.2)


## Atlanta: the airport apron. A parked jet in each of the north-west and south-west corners (a tall
## fuselage with low wings and tail), baggage carts, a fuel truck and a gate building.
func d_atl() -> void:
	_clamp = false
	r("wall", -33.5, -17.1, -19.5, -14.9)
	r("barrier", -27.5, -23.0, -26.0, -9.0)
	r("barrier", -21.5, -19.2, -20.5, -12.8)
	r("wall", -22.1, 9.0, -19.9, 22.5)
	r("barrier", -29.0, 15.0, -13.5, 16.5)
	r("barrier", -24.2, 21.0, -17.8, 22.0)
	bld(-34.5, -7.5, -29.5, -2.0, {"e": [-4.7]})
	crate(-31.0, 4.0, 2.0)
	crate(-31.0, 7.0, 2.0)
	crate(-16.5, -10.0, 2.2)
	truck(-14.5, -4.5, true, "#d9822b")
	cover("table", -13.8, 9.0, 1.2, 2.8)
	cover("crate", -32.0, 20.0, 2.4, 2.4)
	cover("barrels", -15.0, -21.0, 1.6, 1.6)
	fence_h(-34.5, -30.0, 12.0)


## Indianapolis: the Brickyard. A column of pit garages beside each starting area, a pit wall in front of
## them, grandstands on the north and south edges, scoring pylons and tyre stacks.
func d_ind() -> void:
	_clamp = false
	bld(-34.6, -23.0, -30.0, -16.4, {"e": [-19.7]})
	bld(-34.6, -15.4, -30.0, -8.8, {"e": [-12.1]})
	bld(-34.6, 8.8, -30.0, 15.4, {"e": [12.1]})
	bld(-34.6, 16.4, -30.0, 23.0, {"e": [19.7]})
	r("barrier", -28.5, -23.0, -27.5, -21.4)
	r("barrier", -28.5, -18.0, -27.5, -13.8)
	r("barrier", -28.5, -10.4, -27.5, -9.0)
	r("barrier", -28.5, 9.0, -27.5, 10.4)
	r("barrier", -28.5, 13.8, -27.5, 18.0)
	r("barrier", -28.5, 21.4, -27.5, 23.0)
	r("bleachers", -26.0, -24.0, -16.0, -21.0)
	r("bleachers", -24.0, 21.0, -16.0, 24.0)
	r("wall", -20.5, -14.0, -18.5, -12.0)
	r("wall", -22.0, 12.0, -20.0, 14.0)
	for p in [[-24.5, -17.0], [-24.5, -15.5], [-24.5, -14.0], [-17.5, 17.0], [-17.5, 18.5], [-17.5, 20.0]]:
		barrels(p[0], p[1])
	car(-23.0, -9.5, true, "#b3392f")
	car(-17.0, 8.5, true, "#2f5fa8")
	cover("crate", -15.0, -12.0, 2.2, 2.2)
	cover("crate", -29.0, 0.0, 2.4, 2.4)


## Miami: the cove. Rock outcrops in the north-west and south-east, a wrecked boat on the sand, a tiki bar
## and cabanas in the pocket by the objective, palms along the shore and surf along the south edge.
func d_mia() -> void:
	_clamp = false
	r("water", -34.8, 21.6, 0, 24.4)
	r("wall", -31.0, -22.0, -27.0, -18.5)
	r("wall", -28.5, -19.5, -24.0, -16.0)
	r("wall", -26.0, -23.0, -23.0, -20.8)
	r("wall", -32.0, -17.5, -30.0, -14.5)
	r("wall", -20.0, 15.0, -15.5, 19.0)
	r("wall", -17.5, 12.5, -14.0, 15.5)
	r("wall", -22.0, 19.5, -18.0, 22.5)
	r("boat", -34.0, 9.5, -26.5, 12.1)
	bld(-24.0, -14.0, -17.5, -8.6, {"s": [-20.7]})
	r("cabana", -11.0, -6.0, -8.0, -3.0)
	cover("cabana", -29.0, 5.0, 3.0, 3.0)
	tree(-16.0, -12.0, 3.2)
	tree(-14.5, 10.0, 3.2)
	tree(-33.0, 17.0, 3.2)
	tree(-27.0, 19.0, 3.2)
	cover("barrels", -21.0, -20.5, 1.6, 1.6)
	cover("sandbags", -30.0, -9.5, 4.0, 1.2)
	car(-30.5, 1.5, true, "#d9822b")


## Denver: a mountain camp. A dense pine forest in the north-west, a creek down the middle of the left half
## with footbridges, a lodge and cabins to the south and boulders by the objective.
func d_den() -> void:
	_clamp = false
	r("water", -17.0, -24.5, -14.6, 24.5)
	r("boards", -18.0, 10.5, -13.6, 13.5)
	r("boards", -18.0, -13.5, -13.6, -10.5)
	for p in [[-32.0, -22.0, 3.4], [-29.5, -19.5, 3.0], [-27.0, -22.0, 3.4], [-31.0, -16.5, 3.4], [-27.5, -16.0, 3.0],
			[-24.0, -19.0, 3.4], [-33.0, -12.0, 3.0], [-29.0, -11.5, 3.4], [-25.0, -13.5, 3.0], [-21.0, -21.0, 3.4], [-22.5, -16.5, 3.0]]:
		tree(p[0], p[1], p[2])
	bld(-34.4, 10.0, -24.0, 21.0, {"e": [15.5], "n": [-31.0]})
	wall_v(10.6, 20.4, -29.0, [15.5])
	bld(-23.0, 17.0, -18.6, 22.5, {"n": [-20.8]})
	r("wall", -13.0, -6.0, -10.5, -3.8)
	cover("barrels", -21.0, -9.5, 1.6, 1.6)
	cover("barrels", -19.4, -9.2, 1.6, 1.6)
	cover("table", -22.0, 9.5, 2.6, 1.2)
	truck(-31.0, 4.5, true, "#2f8f5b")


## Nashville: the auditorium. A big hall of pews facing a stage on the north-west, with honky-tonk bars along the south and tour buses
## outside. The aisles between the pew rows are the lanes.
func d_nsh() -> void:
	_clamp = false
	bld(-34.5, -22.8, -14.0, -9.5, {"s": [-30.0, -24.0], "w": [-16.5], "e": [-16.0]})
	r("boards", -17.5, -21.6, -14.8, -10.7)
	for x in [-31.5, -29.0, -26.5, -24.0, -21.5]:
		r("barrier", x, -21.5, x + 0.9, -15.5)
		r("barrier", x, -13.5, x + 0.9, -10.7)
	for i in 3:
		var x0 := -34.5 + i * 5.8
		bld(x0, 10.0, x0 + 5.8, 17.5, {"n": [x0 + 2.9]})
	truck(-15.5, 20.0, true, "#3d3d42", "bus")
	truck(-22.0, 21.5, true, "#d9822b")
	cover("stall", -16.0, 12.0, 3.2, 2.0)
	cover("crate", -29.0, 5.0, 2.4, 2.4)
	cover("table", -29.0, -5.5, 2.8, 1.2)
	car(-14.5, 6.0, false)


## Orlando: the garden maze. Two hedge rings with offset gaps around the objective, a spire in the corner
## and a fountain pond; a fight through the maze is all corners.
func d_orl() -> void:
	_clamp = false
	hedge_v(-21.0, 21.0, -30.0, [-12.0, 10.0])
	hedge_h(-30.0, -14.0, -21.0, [-22.0])
	hedge_h(-30.0, -14.0, 21.0, [-18.0])
	hedge_v(-21.0, -9.5, -14.0, [-15.0])
	hedge_v(9.5, 21.0, -14.0, [15.0])
	hedge_h(-26.0, -19.0, -12.0, [-22.5])
	hedge_h(-26.0, -19.0, 12.0, [-22.5])
	r("water", -18.0, -3.0, -14.5, 3.0)
	cover("planter", -8.5, -12.5, 3.0, 3.0)
	tree(-33.0, -23.0, 3.0)
	tree(-33.0, 23.0, 3.0)
	tree(-32.5, 0.0, 3.0)
	cover("table", -24.0, -16.5, 2.6, 1.2)
	cover("table", -22.0, 17.0, 2.6, 1.2)
	cover("barrels", -16.5, -17.0, 1.6, 1.6)


## Louisville: Churchill Flats. A dirt track ringing the infield (the objective is the infield), a grandstand and
## stables beside the track, rails with crossing gaps and a starting gate.
func d_lou() -> void:
	_clamp = false
	r("dirt", -28.0, -20.0, -22.0, 20.0)
	r("dirt", -28.0, -20.0, 0, -14.0)
	r("dirt", -28.0, 14.0, 0, 20.0)
	fence_v(-20.0, -7.0, -28.3)
	fence_v(7.0, 20.0, -28.3)
	fence_h(-28.3, -14.0, -20.3)
	fence_h(-28.3, -14.0, 20.3)
	fence_h(-22.0, -13.0, -14.2)
	fence_h(-22.0, -13.0, 14.2)
	r("bleachers", -34.8, -24.4, -29.5, -9.0)
	r("bleachers", -34.8, 9.0, -29.5, 24.4)
	bld(-27.0, -23.3, -14.5, -21.0, {"s": [-24.0, -18.0]})
	r("wall", -9.0, -14.6, -3.0, -13.8)
	r("barrier", -27.9, -13.0, -27.1, -8.0)
	r("barrier", -27.9, 8.0, -27.1, 13.0)
	hay(-33.0, 0.0)
	hay(-16.0, 22.0)
	cover("table", -17.0, 6.5, 2.6, 1.2)
	cover("crate", -17.0, -6.5, 2.2, 2.2)
	cover("planter", -10.0, 14.0, 2.0, 2.0)


## Little Rock: a river crossing. The river runs down the left of the field; two truss bridges (tall side
## rails over a plank deck) cross it, with fishing shacks and driftwood on the east bank.
func d_lrk() -> void:
	_clamp = false
	r("water", -33.0, -24.5, -28.0, 24.5)
	r("boards", -33.4, -16.0, -27.6, -12.0)
	r("boards", -33.4, 10.0, -27.6, 14.0)
	r("wall", -33.4, -16.2, -27.6, -15.6)
	r("wall", -33.4, -12.4, -27.6, -11.8)
	r("wall", -33.4, 9.8, -27.6, 10.4)
	r("wall", -33.4, 13.6, -27.6, 14.2)
	r("boards", -25.0, -23.0, -17.5, -16.5)
	bld(-24.0, -22.5, -18.5, -17.0, {"s": [-21.2]})
	r("boards", -25.0, 17.0, -17.5, 23.0)
	bld(-24.0, 17.5, -18.5, 23.0, {"n": [-21.2]})
	r("barrier", -22.0, -10.0, -17.0, -9.0)
	r("barrier", -22.0, 9.0, -17.0, 10.0)
	r("boat", -16.5, -14.0, -13.9, -6.5)
	tree(-15.0, 15.0, 3.6)
	tree(-28.5, 3.0, 3.0)
	crate(-14.5, 10.0, 2.4)
	barrels(-28.5, -4.0)
	cover("table", -33.5, 0.0, 1.2, 2.8)
