extends SceneTree
## One-time pass over data/league.json: gives every player outside SKIP_TEAMS a new name from the wide pool
## (PlayerGenerator.first_pool / last_pool) so no first name and no last name repeats across the league, then clears
## their stored face salt and hand-picked face so the likeness is re-rolled from the new name (see FacePrior), and
## re-dedupes heads within each team. Stats, call signs and everything else are left alone. Run:
##   godot --headless --path . --script res://tools/reseed_names.gd

const PATH := "res://data/league.json"
const SKIP_TEAMS := ["BKN"]
const SEED := 20260


func _init() -> void:
	var lines := FileAccess.get_file_as_string(PATH).split("\n")
	var rows := {} # line index -> parsed dict
	for i in lines.size():
		var raw := lines[i].strip_edges().trim_suffix(",")
		if raw.begins_with("{\"age\""):
			rows[i] = JSON.parse_string(raw)

	# Names the kept teams already use are off limits, so nobody new shares a first or last name with them.
	var used_first := {}
	var used_last := {}
	for i in rows:
		if rows[i].get("team", "") in SKIP_TEAMS:
			used_first[rows[i]["first"]] = true
			used_last[rows[i]["last"]] = true
	var firsts: Array = PlayerGenerator.first_pool().filter(func(n): return not used_first.has(n))
	var lasts: Array = PlayerGenerator.last_pool().filter(func(n): return not used_last.has(n))
	var targets := []
	for i in rows:
		if not rows[i].get("team", "") in SKIP_TEAMS:
			targets.append(i)
	if firsts.size() < targets.size() or lasts.size() < targets.size():
		push_error("name pool too small: %d firsts / %d lasts for %d players" % [firsts.size(), lasts.size(), targets.size()])
		quit(1)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_shuffle(firsts, rng)
	_shuffle(lasts, rng)

	var by_team := {}
	for k in targets.size():
		var d: Dictionary = rows[targets[k]]
		d["first"] = firsts[k]
		d["last"] = lasts[k]
		d.erase("face")
		d.erase("face_ov")
	for i in rows:
		var team: String = rows[i].get("team", "")
		if team != "" and not team in SKIP_TEAMS:
			if not by_team.has(team):
				by_team[team] = []
			by_team[team].append(i)
	var salted := 0
	for team in by_team:
		var roster := []
		for i in by_team[team]:
			roster.append(League.soldier_from_dict(rows[i]))
		FaceSpec.dedupe(roster)
		for k in roster.size():
			var s: Soldier = roster[k]
			if s.face_salt > 0:
				rows[by_team[team][k]]["face"] = s.face_salt
				salted += 1

	for i in targets: # only the renamed players' lines are rewritten, so the diff stays small
		var line := lines[i]
		var tail := "\r" if line.ends_with("\r") else ""
		var comma := "," if line.strip_edges().ends_with(",") else ""
		lines[i] = LeagueEditor._encode(rows[i]) + comma + tail
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	print("renamed %d players, %d needed a head salt" % [targets.size(), salted])
	quit()


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
