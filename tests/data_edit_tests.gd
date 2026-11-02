extends SceneTree
## Data Edit model tests (LeagueEditor on a scratch copy of league.json):
##   godot --headless --path . --script res://tests/data_edit_tests.gd

const SCRATCH := "user://data_edit_scratch.json"
var _failures := 0


func _init() -> void:
	var src := FileAccess.get_file_as_string(League.DATA_PATH)
	var f := FileAccess.open(SCRATCH, FileAccess.WRITE)
	f.store_string(src)
	f.close()
	var ed := LeagueEditor.open(SCRATCH)
	check(ed.count() > 200, "players parsed (%d)" % ed.count())
	check(ed.dirty_count() == 0, "fresh editor is clean")
	check(ed.save() == OK and FileAccess.get_file_as_string(SCRATCH) == src, "saving with no edits leaves the file byte-identical")

	var other := String(ed.rows[1]["callsign"])
	check(ed.callsign_taken(0, other.to_upper()), "duplicate callsign detected case-insensitively")
	check(not ed.callsign_taken(0, "ZzNobodyHasThis"), "free callsign allowed")

	var old_head := ed.soldier(0).get_face().head_id
	ed.set_name(0, "Zed", String(ed.rows[0]["last"]))
	check(ed.soldier(0).get_face().head_id == old_head, "renaming keeps the same head")
	ed.set_field(0, "callsign", "ZzEdit")
	ed.set_field(0, "age", 41)
	ed.set_stat(0, "SPD", 120)
	ed.set_cap(0, "accuracy", 77)
	var new_head := "16_01" if old_head != "16_01" else "16_02"
	ed.set_head(0, new_head, 7)
	check(ed.dirty_count() == 1, "one player edited")
	check(ed.save() == OK, "save ok")

	var again := LeagueEditor.open(SCRATCH)
	var s := again.soldier(0)
	check(s.first_name == "Zed" and s.callsign == "ZzEdit" and s.age == 41, "identity round trips")
	check(s.stats[Stats.SPEED] == 99, "stat clamped to 99 and saved")
	check(s.group_caps[Stats.ACCURACY] == 77, "cap saved")
	check(s.get_face().head_id == new_head, "picked head round trips")
	check(again.dirty_count() == 0, "reopened file is clean")
	check(String(again.rows[1]["callsign"]) == other, "other players untouched")
	var changed := 0
	var a := FileAccess.get_file_as_string(SCRATCH).split("\n")
	var b := src.split("\n")
	for i in b.size():
		if a[i] != b[i]:
			changed += 1
	check(changed == 1, "only one line of the file changed (%d)" % changed)

	again.reroll_morph(0, 3)
	check(again.is_dirty(0), "reroll morph marks the player edited")
	again.revert(0)
	check(not again.is_dirty(0), "revert restores the saved row")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	print("%s" % ("FAIL" if _failures > 0 else "all passed"))
	quit(1 if _failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   " + msg)
	else:
		_failures += 1
		printerr("  FAIL " + msg)
