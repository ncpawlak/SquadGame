extends SceneTree
## Hall of Fame threshold tuning: plays several seasons headless and prints how every vote's
## candidates scored, so HallOfFame.THRESHOLD can be set to induct a small share of retirees.
##   SEASONS=14 SEED=7 godot --headless --path . --script res://tools/hall_tune.gd

const CUTOFFS := [40, 45, 50, 55, 60, 65, 70, 75, 80]


func _init() -> void:
	var seasons := int(OS.get_environment("SEASONS")) if OS.get_environment("SEASONS") != "" else 12
	var seed_value := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7
	Season.fixture_teams = 0
	var s := Season.new_franchise(seed_value, 1)
	var all_scores: Array = []
	var inducted := 0
	for i in seasons:
		var started := Time.get_ticks_msec()
		s.sim_to_end_of_season()
		# The vote has already run for this year: its class is in the Hall, the rest are still candidates.
		var ctx := HallOfFame.context(s)
		var cls := HallOfFame.class_of(s, s.year)
		var scores: Array = cls.map(func(e): return e["score"])
		for so: Soldier in HallOfFame.candidates(s):
			scores.append(HallOfFame.breakdown(s, ctx, so)["score"])
		scores.sort()
		scores.reverse()
		all_scores.append_array(scores)
		inducted += cls.size()
		print("%d: %d candidates, %d inducted, top scores %s  (%d s)" % [s.year, scores.size(), cls.size(),
			scores.slice(0, 5).map(func(x): return snappedf(x, 0.1)), (Time.get_ticks_msec() - started) / 1000])
		while s.offseason_stage != Season.OFF_DONE:
			s.advance_offseason()
		s.start_next_season()
	print("\nretirees voted on: %d, inducted at THRESHOLD %.0f: %d (%.1f%%)" % [all_scores.size(), HallOfFame.THRESHOLD, inducted, 100.0 * inducted / maxf(1.0, all_scores.size())])
	for c in CUTOFFS:
		var n := all_scores.filter(func(x): return x >= c).size()
		print("  score >= %d: %d (%.1f%%)" % [c, n, 100.0 * n / maxf(1.0, all_scores.size())])
	print("Hall of Fame now: %d members" % s.hall_of_fame.size())
	for e in s.hall_of_fame:
		print("  %d  %-28s %.1f  %s" % [e["year"], e["soldier"].full_name(), e["score"], ", ".join(PackedStringArray(e["honors"]))])
	print("retired callsigns: %d" % s.league.retired_callsigns.size())
	quit()
