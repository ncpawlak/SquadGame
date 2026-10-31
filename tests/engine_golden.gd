extends SceneTree
## Match engine golden test (issue #11, telemetry): fixed seeds must keep producing the same results, scores,
## play-by-play and original box-score counters, so bookkeeping added to the engine never moves a result.
## Run: godot --headless --path . --script res://tests/engine_golden.gd
## GOLDEN_WRITE=1 rewrites tests/engine_golden.txt (only when the sim is meant to change).

const SEEDS := [101, 102, 103]
const PATH := "res://tests/engine_golden.txt"
## The box counters that existed before telemetry; new ones are not part of the golden.
const BOX_KEYS := ["team", "slot", "kills", "deaths", "assists", "shots", "hits", "headshots", "rounds_played",
	"rounds_survived", "clutches", "saves", "games", "wipes", "caps"]
const BOX_FLOATS := ["damage", "hill_s", "contest_s"]


func _init() -> void:
	Season.fixture_teams = 5
	Season.backfill_careers = false
	var lines: Array[String] = []
	for sd in SEEDS:
		lines.append("%d %s" % [sd, _signature(sd)])
	if OS.get_environment("GOLDEN_WRITE") == "1":
		var f := FileAccess.open(PATH, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("golden written")
		quit(0)
		return
	var want := FileAccess.get_file_as_string(PATH).strip_edges().split("\n")
	var ok := want.size() == lines.size()
	for i in lines.size():
		if i >= want.size() or want[i] != lines[i]:
			ok = false
			printerr("  seed %s differs:\n    want %s\n    got  %s" % [SEEDS[i], want[i] if i < want.size() else "-", lines[i]])
	print("Engine golden: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _signature(seed_value: int) -> String:
	var s := Season.new_franchise(seed_value, 0)
	s.sim_to_end_of_season()
	var parts: Array[String] = []
	var all: Array = []
	for wk: Array in s.schedule:
		all.append_array(wk)
	all.append_array(s.playoff_matches)
	for m: ScheduledMatch in all:
		var r := m.result
		if r == null:
			continue
		parts.append("%d|%s|%s|%d" % [r.winner_index, r.score, "".join(r.games.map(func(g): return str(g["score"]))), r.events.size()])
		parts.append("".join(r.events))
		var ids := r.box.keys()
		ids.sort()
		for id in ids:
			var line: Dictionary = r.box[id]
			parts.append("%d:%s" % [id, ",".join(BOX_KEYS.map(func(k): return str(line.get(k, 0))))])
			parts.append(",".join(BOX_FLOATS.map(func(k): return "%.3f" % float(line.get(k, 0.0)))))
	return "".join(parts).sha256_text()
