class_name FpsMazeDrill
extends FpsDrill
## First-person maze (AWARENESS): three perfect mazes in a row, reach the marked centre cell as fast as you can.
## The player walks and sprints with the real movement and stamina. Each maze is scored on time against a par from the
## shortest path; the drill score is the mean of the three (a maze not reached counts 0).

const MAZE_COUNT := 3
const COLS := 9
const ROWS := 7
const CELL := 3.0
const WALL_T := 0.3
const WALL_H := 2.6
const CENTRE_RADIUS := 1.1
## Open-passage bits of a maze cell.
const N := 1
const E := 2
const S := 4
const W := 8
## Par pace in metres per second along the shortest path (walking with sprint bursts, plus corners), a fixed lead-in,
## and the multiple of par that scores zero.
const PAR_SPEED := 5.0
const PAR_LEAD := 2.0
const LIMIT_MULT := 3.0
## World position of the north-west corner of the maze (cell (0,0)); rows run towards -Z.
const ORIGIN := Vector3(-13.5, 0.0, -2.0)

var maze_index := 0
var maze_time := 0.0
var maze: Array = []
var maze_scores: Array = []
var start_cell := Vector2i.ZERO
var _walls: Node3D
var _marker: Node3D


func _init() -> void:
	super()
	stat = Stats.AWARENESS
	title = "Maze"
	instructions = "Find your way to the marked centre. Three mazes."
	duration = 200.0
	player_spawn = FpsMazeDrill.cell_centre(Vector2i(0, ROWS - 1)) + Vector3(0, 0.1, 0)


# ---- pure helpers ---------------------------------------------------------------------------------------------------

static func dir_vec(bit: int) -> Vector2i:
	match bit:
		N: return Vector2i(0, -1)
		E: return Vector2i(1, 0)
		S: return Vector2i(0, 1)
	return Vector2i(-1, 0)


static func opposite(bit: int) -> int:
	match bit:
		N: return S
		E: return W
		S: return N
	return E


static func centre_cell(cols: int = COLS, rows: int = ROWS) -> Vector2i:
	return Vector2i(cols / 2, rows / 2)


## A perfect maze (a spanning tree of the grid) from `seed_value`, by iterative depth-first search. Returns cols*rows ints
## (index y*cols+x), each a mask of the open passages N/E/S/W.
static func generate_maze(seed_value: int, cols: int = COLS, rows: int = ROWS) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var cells: Array = []
	cells.resize(cols * rows)
	cells.fill(0)
	var seen: Array = []
	seen.resize(cols * rows)
	seen.fill(false)
	var first := Vector2i(r.randi_range(0, cols - 1), r.randi_range(0, rows - 1))
	var stack: Array[Vector2i] = [first]
	seen[first.y * cols + first.x] = true
	while not stack.is_empty():
		var c: Vector2i = stack[stack.size() - 1]
		var options: Array[int] = []
		for bit in [N, E, S, W]:
			var n: Vector2i = c + dir_vec(bit)
			if n.x >= 0 and n.y >= 0 and n.x < cols and n.y < rows and not seen[n.y * cols + n.x]:
				options.append(bit)
		if options.is_empty():
			stack.pop_back()
			continue
		var pick: int = options[r.randi_range(0, options.size() - 1)]
		var nxt: Vector2i = c + dir_vec(pick)
		cells[c.y * cols + c.x] |= pick
		cells[nxt.y * cols + nxt.x] |= opposite(pick)
		seen[nxt.y * cols + nxt.x] = true
		stack.append(nxt)
	return cells


## Number of cell-to-cell steps on the shortest path (BFS), or -1 when `to` cannot be reached.
static func shortest_path_length(cells: Array, from: Vector2i, to: Vector2i, cols: int = COLS, rows: int = ROWS) -> int:
	if from == to:
		return 0
	var dist: Dictionary = {from: 0}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for bit in [N, E, S, W]:
			if int(cells[c.y * cols + c.x]) & bit == 0:
				continue
			var n: Vector2i = c + dir_vec(bit)
			if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows or dist.has(n):
				continue
			dist[n] = int(dist[c]) + 1
			if n == to:
				return int(dist[n])
			queue.append(n)
	return -1


## Number of open passages (a perfect maze has cols*rows - 1).
static func passage_count(cells: Array) -> int:
	var total := 0
	for m in cells:
		for bit in [N, E, S, W]:
			if int(m) & bit != 0:
				total += 1
	return total / 2


static func par_time(steps: int) -> float:
	return PAR_LEAD + float(maxi(steps, 0)) * CELL / PAR_SPEED


## 1 at par or faster, 0 at LIMIT_MULT times par.
static func maze_score(secs: float, steps: int) -> float:
	var par := FpsMazeDrill.par_time(steps)
	return FpsDrill.time_score(secs, par, par * LIMIT_MULT)


static func cell_centre(c: Vector2i) -> Vector3:
	return ORIGIN + Vector3((float(c.x) + 0.5) * CELL, 0.0, -(float(c.y) + 0.5) * CELL)


## Mean of the per-maze scores over all MAZE_COUNT mazes (those not reached count 0).
static func mean_score(scores: Array) -> float:
	return FpsDrill.mean_value(scores, MAZE_COUNT)


# ---- drill ----------------------------------------------------------------------------------------------------------

func _build() -> void:
	_walls = Node3D.new()
	add_child(_walls)
	var pad := add_box(cell_centre(centre_cell()) + Vector3(0, 0.03, 0), Vector3(CELL * 0.8, 0.06, CELL * 0.8), Color(0.95, 0.8, 0.1))
	pad.collision_layer = 0
	_marker = add_box(cell_centre(centre_cell()) + Vector3(0, 4.0, 0), Vector3(0.25, 8.0, 0.25), Color(0.95, 0.8, 0.1))
	_marker.collision_layer = 0
	_new_maze()


func _begin() -> void:
	maze_index = 0
	maze_scores.clear()
	maze_time = 0.0
	_new_maze()
	_place_player()


func _run(delta: float) -> void:
	maze_time += delta
	if player == null:
		return
	var c := cell_centre(centre_cell())
	if Vector2(player.global_position.x - c.x, player.global_position.z - c.z).length() <= CENTRE_RADIUS:
		complete_maze()


## The centre was reached (also callable by tests): score this maze and move on to the next, or finish after the last.
func complete_maze() -> void:
	if state != State.RUNNING:
		return
	var steps := shortest_path_length(maze, start_cell, centre_cell())
	maze_scores.append(FpsMazeDrill.maze_score(maze_time, steps))
	maze_index += 1
	if maze_index >= MAZE_COUNT:
		finish(_final_score())
		return
	maze_time = 0.0
	_new_maze()
	_place_player()


func _final_score() -> float:
	return FpsMazeDrill.mean_score(maze_scores)


func _hud_extra() -> String:
	return "Maze %d / %d   %.1fs" % [mini(maze_index + 1, MAZE_COUNT), MAZE_COUNT, maze_time]


func _new_maze() -> void:
	maze = generate_maze(rng.randi(), COLS, ROWS)
	var corners: Array[Vector2i] = [Vector2i(0, ROWS - 1), Vector2i(COLS - 1, ROWS - 1), Vector2i(0, 0), Vector2i(COLS - 1, 0)]
	start_cell = corners[rng.randi_range(0, corners.size() - 1)]
	player_spawn = cell_centre(start_cell) + Vector3(0, 0.1, 0)
	_build_walls()


func _place_player() -> void:
	if player == null:
		return
	player.position = player_spawn
	if "velocity" in player:
		player.set("velocity", Vector3.ZERO)
	# Face an open passage of the start cell.
	var m: int = maze[start_cell.y * COLS + start_cell.x]
	for bit in [N, E, S, W]:
		if m & bit != 0:
			var d := dir_vec(bit)
			player.rotation.y = atan2(-float(d.x), float(d.y))
			break


func _build_walls() -> void:
	for ch in _walls.get_children():
		_walls.remove_child(ch)
		ch.queue_free()
	var col := Color(0.55, 0.5, 0.45)
	var y := WALL_H * 0.5
	for cy in ROWS:
		for cx in COLS:
			var m: int = maze[cy * COLS + cx]
			var c := cell_centre(Vector2i(cx, cy))
			if cx == 0:
				_wall(c + Vector3(-CELL * 0.5, y, 0), Vector3(WALL_T, WALL_H, CELL + WALL_T), col)
			if cy == 0:
				_wall(c + Vector3(0, y, CELL * 0.5), Vector3(CELL + WALL_T, WALL_H, WALL_T), col)
			if m & E == 0:
				_wall(c + Vector3(CELL * 0.5, y, 0), Vector3(WALL_T, WALL_H, CELL + WALL_T), col)
			if m & S == 0:
				_wall(c + Vector3(0, y, -CELL * 0.5), Vector3(CELL + WALL_T, WALL_H, WALL_T), col)


func _wall(center: Vector3, size: Vector3, color: Color) -> void:
	var b := add_box(center, size, color)
	remove_child(b)
	_walls.add_child(b)
