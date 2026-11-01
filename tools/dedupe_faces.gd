extends SceneTree
## One-time pass over data/league.json: gives each team's players distinct heads by storing a "face" salt
## (see FaceSpec.dedupe). Idempotent; keeps the file's line layout. Run:
##   godot --headless --path . --script res://tools/dedupe_faces.gd

const PATH := "res://data/league.json"


func _init() -> void:
	var text := FileAccess.get_file_as_string(PATH)
	var lines := text.split("\n")
	var rows := {} # line index -> parsed dict
	var by_team := {}
	for i in lines.size():
		var raw := lines[i].strip_edges().trim_suffix(",")
		if not raw.begins_with("{\"age\""):
			continue
		var d: Dictionary = JSON.parse_string(raw)
		rows[i] = d
		var team: String = d.get("team", "")
		if team != "":
			if not by_team.has(team):
				by_team[team] = []
			by_team[team].append(i)
	var changed := 0
	var touched := {}
	var clashes := 0
	for team in by_team:
		var roster := []
		for i in by_team[team]:
			roster.append(League.soldier_from_dict(rows[i]))
		var seen := {}
		for s: Soldier in roster:
			var h := FaceSpec.generate(s.id, s.first_name, s.last_name, s.face_salt).head_id
			if seen.has(h):
				clashes += 1
			seen[h] = true
		FaceSpec.dedupe(roster)
		for k in roster.size():
			var s: Soldier = roster[k]
			var d: Dictionary = rows[by_team[team][k]]
			if s.face_salt != int(d.get("face", 0)):
				d["face"] = s.face_salt
				touched[by_team[team][k]] = true
				changed += 1
	for i in touched: # only lines that changed are rewritten, so the diff stays small
		var line := lines[i]
		var tail := "\r" if line.ends_with("\r") else ""
		var comma := "," if line.strip_edges().ends_with(",") else ""
		lines[i] = JSON.stringify(rows[i]) + comma + tail
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	print("teams %d, repeated heads before: %d, players re-rolled: %d" % [by_team.size(), clashes, changed])
	quit()
