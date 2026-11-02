extends SceneTree
## Dev tool: sims several seasons for a few seeds, writes every Weekly News issue to markdown and prints
## how varied the paper is: lede and format spread, paragraph counts, repeated headlines and repeated
## sentence openings. Used to compare the paper before and after a change. Not part of the test suite.
##   godot --headless --path . --script res://tests/newsroom_metrics.gd -- <out.md> [seasons] [seeds, comma separated]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://news_metrics.md"
	var seasons := int(args[1]) if args.size() > 1 else 3
	var seeds: Array = []
	for t in (args[2] if args.size() > 2 else "61").split(","):
		seeds.append(int(t))
	var md := PackedStringArray()
	var issues: Array = []
	for seed_value: int in seeds:
		Season.fixture_teams = 0
		var s := Season.new_franchise(seed_value, 1)
		Season.fixture_teams = 5
		for i in seasons:
			s.sim_to_end_of_season()
			var NS := load("res://tests/newsroom_sample.gd")
			NS._act_offseason(s)
			s.start_next_season()
		for a in s.newsroom.issues:
			md.append(NS_render(a))
			issues.append(a)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string("\n\n---\n\n".join(md))
	f.close()
	report(issues)
	print("-> %s" % out_path)
	quit(0)


static func NS_render(a: Dictionary) -> String:
	return load("res://tests/newsroom_sample.gd").render(a)


## Prints the variety numbers for a list of issues.
static func report(issues: Array) -> void:
	var by_kind := {}
	var ledes := {}
	var shapes := {}
	var heads := {}
	var para_counts: Array = []
	var openings := {}
	var sentences := 0
	var game_issues := 0
	var spans_bad := 0
	for a: Dictionary in issues:
		by_kind[a["kind"]] = int(by_kind.get(a["kind"], 0)) + 1
		var body: Array = a["body"]
		para_counts.append(body.size())
		heads[a["headline"]] = int(heads.get(a["headline"], 0)) + 1
		if a["kind"] == "game":
			game_issues += 1
			var angs: Array = a["angles"]
			if not angs.is_empty():
				ledes[angs[0]] = int(ledes.get(angs[0], 0)) + 1
			shapes[body.size()] = int(shapes.get(body.size(), 0)) + 1
		for p in body:
			var text := String(p)
			if text.contains(" -1 weeks") or text.contains("zero weeks") or text.contains("in 0 week"):
				spans_bad += 1
			for sent in text.split(". "):
				var words := sent.strip_edges().split(" ", false)
				if words.size() >= 4:
					sentences += 1
					var key := " ".join(words.slice(0, 4)).to_lower()
					openings[key] = int(openings.get(key, 0)) + 1
	var repeated_heads := 0
	for h in heads:
		repeated_heads += int(heads[h]) - 1
	var repeated_open := 0
	for o in openings:
		if int(openings[o]) > 1:
			repeated_open += int(openings[o]) - 1
	para_counts.sort()
	print("issues: %d  game: %d  kinds: %s" % [issues.size(), game_issues, by_kind])
	print("game ledes (%d distinct): %s" % [ledes.size(), ledes])
	print("game body paragraph counts: %s" % shapes)
	print("paragraphs per issue: min %d  median %d  max %d" % [para_counts[0], para_counts[para_counts.size() / 2], para_counts[-1]])
	print("repeated headlines: %d of %d" % [repeated_heads, issues.size()])
	print("repeated sentence openings (first 4 words): %d of %d sentences (%.0f%%)" % [repeated_open, sentences, 100.0 * repeated_open / maxf(sentences, 1)])
	print("bad week spans: %d" % spans_bad)
