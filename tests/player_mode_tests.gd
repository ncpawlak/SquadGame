extends SceneTree
## Player mode phase 1 tests (archetypes, created soldier, save round trip):
##   godot --headless --path . --script res://tests/player_mode_tests.gd
## Exits with code 0 if all tests pass, 1 otherwise.

var _failures := 0
var _passes := 0
var _current := ""


func _init() -> void:
	var tests: Array = []
	for method in get_method_list():
		if String(method["name"]).begins_with("test_"):
			tests.append(String(method["name"]))
	for t in tests:
		_current = t
		var before := _failures
		call(t)
		if _failures == before:
			_passes += 1
			print("  PASS  ", t)
		else:
			print("  FAIL  ", t)
	print("\n%d passed, %d failed" % [_passes, tests.size() - _passes])
	quit(0 if _passes == tests.size() else 1)


func check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("    [%s] %s" % [_current, msg])


func test_archetype_data_is_complete() -> void:
	var seen := {}
	for role in [Scheme.Role.FRONTMAN, Scheme.Role.CENTER, Scheme.Role.FLEX]:
		var list := Archetypes.for_role(role)
		check(list.size() >= 5, "role %d has only %d archetypes" % [role, list.size()])
		for a in list:
			check(not seen.has(a["id"]), "duplicate archetype id %s" % a["id"])
			seen[a["id"]] = true
			check(String(a["name"]) != "" and String(a["blurb"]) != "", "%s lacks a name or blurb" % a["id"])
			for key in a.get("up", {}):
				check(Stats.ALL.has(StringName(key)), "%s: unknown stat %s in up" % [a["id"], key])
				check(int(a["up"][key]) > 0, "%s: up %s is not positive" % [a["id"], key])
			for key in a.get("down", {}):
				check(Stats.ALL.has(StringName(key)), "%s: unknown stat %s in down" % [a["id"], key])
				check(int(a["down"][key]) < 0, "%s: down %s is not negative" % [a["id"], key])


func test_ceilings_cover_every_drilled_stat() -> void:
	for a in Archetypes.all():
		var c := Archetypes.ceilings(StringName(a["id"]))
		for stat in Stats.ALL:
			if stat == Stats.INJURY:
				check(not c.has(stat), "injury must not be drilled")
				continue
			check(c.has(stat), "%s has no ceiling for %s" % [a["id"], stat])
			if c.has(stat):
				check(int(c[stat]) > Archetypes.FLOOR and int(c[stat]) <= Stats.MAX_RATING,
					"%s %s ceiling %d out of range" % [a["id"], stat, c[stat]])


func test_specialty_moves_ceilings_the_right_way() -> void:
	var sniper := Archetypes.ceilings(&"sniper")
	var wall := Archetypes.ceilings(&"wall")
	var runner := Archetypes.ceilings(&"runner")
	check(sniper[Stats.LONG_ACC] > wall[Stats.LONG_ACC], "a sniper out-ranges a wall at long range")
	check(runner[Stats.SPEED] > sniper[Stats.SPEED], "a runner out-runs a sniper")
	# A Center can't match a Frontman's strength, however well the drills go.
	check(sniper[Stats.STRENGTH] < Archetypes.ceilings(&"bruiser")[Stats.STRENGTH], "bruiser must out-lift a sniper")
	check(sniper[Stats.SPEED] < Archetypes.ceilings(&"rusher")[Stats.SPEED], "a sniper must be slower than a rusher at the cap")


func test_start_cap_can_bind_for_every_archetype() -> void:
	# If a perfect combine could not reach the cap, the 75 limit would never matter.
	for a in Archetypes.all():
		var m := Archetypes.max_ovr(StringName(a["id"]))
		check(m >= Archetypes.START_OVR_CAP, "%s maxes at %d, below the start cap" % [a["id"], m])


func test_create_soldier() -> void:
	var heads: Array = FaceSpec.db().get("heads", {}).keys()
	heads.sort()
	check(not heads.is_empty(), "no heads in the face database")
	var s := PlayerCareer.create_soldier(900, "  Ada   Marie ", "Stone", "  Longshot  ", heads[0], 3, &"sniper")
	check(s.first_name == "Ada Marie", "name not cleaned: '%s'" % s.first_name)
	check(s.callsign == "Longshot", "callsign not trimmed")
	check(s.age == PlayerCareer.START_AGE, "wrong start age")
	check(s.best_ovr() <= Archetypes.START_OVR_CAP, "new soldier above the start cap")
	check(s.get_face().head_id == heads[0], "face override not applied")
	check(Scheme.best_role(s.stats) != null, "no role")


func test_problem_messages() -> void:
	var heads: Array = FaceSpec.db().get("heads", {}).keys()
	var h: String = heads[0]
	check(PlayerCareer.problem("A", "B", "C", h, &"sniper") == "", "valid choices rejected")
	check(PlayerCareer.problem("", "B", "C", h, &"sniper") != "", "empty first name accepted")
	check(PlayerCareer.problem("A", "  ", "C", h, &"sniper") != "", "blank last name accepted")
	check(PlayerCareer.problem("A", "B", "", h, &"sniper") != "", "empty callsign accepted")
	check(PlayerCareer.problem("A", "B", "C", "nope", &"sniper") != "", "unknown head accepted")
	check(PlayerCareer.problem("A", "B", "C", h, &"nope") != "", "unknown archetype accepted")
	check(PlayerCareer.clean("x".repeat(40), PlayerCareer.MAX_NAME).length() == PlayerCareer.MAX_NAME, "long name not cut")


func test_player_mode_survives_save() -> void:
	var season := Season.new_franchise(4321)
	var heads: Array = FaceSpec.db().get("heads", {}).keys()
	heads.sort()
	season.player_mode = true
	season.player_archetype = &"shotcaller"
	season.player = PlayerCareer.create_soldier(season.league.next_soldier_id, "Ada", "Stone", "Zzyzx", heads[1], 5, &"shotcaller")
	season.league.next_soldier_id += 1
	var text := SaveSystem.to_text(season)
	var loaded := SaveSystem.from_text(text)
	check(loaded != null, "from_text returned null")
	if loaded == null:
		return
	check(loaded.player_mode, "player_mode lost")
	check(loaded.player_archetype == &"shotcaller", "archetype lost")
	check(loaded.player != null and loaded.player.callsign == "Zzyzx", "player soldier lost")
	check(SaveSystem.to_text(loaded) == text, "re-serialization not stable")
	check(loaded.player.get_face().head_id == heads[1], "player's face lost")
	var plain := SaveSystem.from_text(SaveSystem.to_text(Season.new_franchise(4321)))
	check(plain != null and not plain.player_mode and plain.player == null, "manager saves must stay manager saves")
