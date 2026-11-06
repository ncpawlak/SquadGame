extends SceneTree
## Headless tests for the UI animation helpers (Fx) and the animated CapBar:
##   godot --headless --path . --script res://tests/fx_tests.gd
## The animations are visual, so these check end states: skipping lands on the real values, and
## "Reduce animations" applies them immediately.

var ok := true


func _init() -> void:
	var was_reduced := Fx.is_reduced()
	Fx.set_reduced(false)
	await _normal_mode()
	Fx.set_reduced(true)
	await _reduced_mode()
	Fx.set_reduced(was_reduced)
	print("Fx tests: ", "ok" if ok else "FAIL")
	quit(0 if ok else 1)


func _normal_mode() -> void:
	var holder := Control.new()
	root.add_child(holder)

	# A count-up starts at the old value and a skip lands on the new one.
	var l := Label.new()
	holder.add_child(l)
	Fx.count_between(l, 0, 40, "%d", 1.0)
	await process_frame
	_check(Fx.busy(), "count animation registers as skippable")
	Fx.skip_all()
	await process_frame
	_check(l.text == "40", "skipped count lands on the final value (%s)" % l.text)
	_check(not Fx.busy(), "nothing is running after a skip")

	# count_memo: first show is static, a later change animates from the old number.
	var m := Label.new()
	holder.add_child(m)
	Fx.count_memo(m, "test:memo", 10)
	_check(m.text == "10", "first show of a remembered number is static")
	var m2 := Label.new()
	holder.add_child(m2)
	Fx.count_memo(m2, "test:memo", 14)
	_check(m2.text == "10" and Fx.memo("test:memo", 14) == 14, "a changed number starts from the remembered value (%s)" % m2.text)
	Fx.skip_all()
	await process_frame
	_check(m2.text == "14", "...and skip lands on the new value")

	# Score pair.
	var sc := Label.new()
	holder.add_child(sc)
	Fx.count_pair(sc, 3, 1, "%d - %d", 1.0)
	Fx.skip_all()
	await process_frame
	_check(sc.text == "3 - 1", "score pair lands on the final score (%s)" % sc.text)
	holder.queue_free()


func _reduced_mode() -> void:
	var holder := Control.new()
	root.add_child(holder)
	_check(Fx.dur(1.0) == 0.0, "durations collapse to zero")
	var l := Label.new()
	holder.add_child(l)
	Fx.count_between(l, 0, 25, "%d", 1.0)
	_check(l.text == "25" and not Fx.busy(), "count shows the final value at once")
	var c := Control.new()
	holder.add_child(c)
	Fx.stamp(c)
	Fx.reveal(c)
	await process_frame
	_check(is_equal_approx(c.modulate.a, 1.0) and c.scale == Vector2.ONE, "stamp and reveal leave the control untouched")
	var fade := Control.new()
	holder.add_child(fade)
	UiKit.fade_in(fade, 0.0, 0.3)
	_check(is_equal_approx(fade.modulate.a, 1.0), "fade_in leaves the control visible")
	holder.queue_free()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		ok = false
		printerr("  FAIL: ", msg)
