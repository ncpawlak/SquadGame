extends SceneTree
## Dev tool: sims a fixed 20-team league for one season and offseason and writes every Weekly
## News issue to markdown for reading. Not part of the test suite.
##   godot --headless --path . --script res://tests/newsroom_sample.gd -- <out.md> [seed] [team_index]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://news_samples.md"
	var seed_value := int(args[1]) if args.size() > 1 else 61
	var team_index := int(args[2]) if args.size() > 2 else 1
	Season.fixture_teams = 0
	var s := Season.new_franchise(seed_value, team_index)
	Season.fixture_teams = 5
	s.sim_to_end_of_season()
	_act_offseason(s)
	s.start_next_season()
	var md := PackedStringArray()
	var unfilled := 0
	for a in s.newsroom.issues:
		md.append(render(a))
		for p in a["body"]:
			if String(p).contains("{"):
				unfilled += 1
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string("\n\n---\n\n".join(md))
	f.close()
	print("issues: %d  unfilled: %d  -> %s" % [s.newsroom.issues.size(), unfilled, out_path])
	quit(0)


## Plays the offseason roughly like a user would: keeps his best expiring player, bids on a
## couple of free agents and runs camp, so the offseason issues have something to report.
static func _act_offseason(s: Season) -> void:
	var us := s.user_team()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	while s.offseason_stage != Season.OFF_DONE:
		match s.offseason_stage:
			Season.OFF_RESIGN:
				var exp: Array = Contracts.expiring(us)
				exp.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
				for so: Soldier in exp.slice(0, 2):
					var err := s.resign_player(us, so, 2)
					if err != "":
						print("re-sign %s: %s" % [so.last_name, err])
			Season.OFF_FREE_AGENCY:
				if s.fa_day <= 2:
					var pool: Array = s.league.free_agents.duplicate()
					pool.sort_custom(func(a: Soldier, b: Soldier): return a.best_ovr() > b.best_ovr())
					var made := 0
					for so: Soldier in pool:
						if made >= 2 - (s.fa_day - 1):
							break
						var yrs := Contracts.preferred_years(so)
						if s.fa.make_offer(s, us, so, int(Contracts.asking(so, yrs) * 1.1), yrs) == "":
							made += 1
			Season.OFF_CAMP:
				if s.camp != null:
					s.camp.ai_run(us, rng)
		s.advance_offseason()


static func render(a: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("<!-- #%d %s %s (%s) angles=%s -->" % [a["n"], a["year"], a["when"], a["kind"], ",".join(a["angles"])])
	lines.append("**%s** | %s" % [a["paper"], a["section"]])
	lines.append("# %s" % a["headline"])
	lines.append("*%s*" % a["dek"])
	lines.append("By %s, %s staff writer%s" % [a["writer"], a["paper"], "  |  Grade: **%s**" % a["grade"] if a["grade"] != "" else ""])
	lines.append("")
	var first := true
	for p in a["body"]:
		lines.append(("%s - " % a["dateline"] if first else "") + String(p))
		lines.append("")
		first = false
	if not a["pull_quote"].is_empty():
		lines.append("> \"%s\"  \n> - %s" % [a["pull_quote"]["text"], a["pull_quote"]["who"]])
		lines.append("")
	for box in a["sidebar"]:
		lines.append("**%s**: %s" % [box["title"], "; ".join(box["rows"].map(func(r): return "%s %s" % [r[0], r[1]]))])
	if not a["roundup"].is_empty():
		lines.append("")
		lines.append("**Around the League**")
		for r in a["roundup"]:
			lines.append("- **%s.** %s" % [r["head"], r["text"]])
	return "\n".join(lines)
