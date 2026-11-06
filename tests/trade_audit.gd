extends SceneTree
## Audit of CPU-generated trades (issue #103). Not a pass/fail test: it generates many AI offers to
## the user and AI-to-AI deals across seeded 20-team leagues and prints how many are lopsided or
## nonsensical, so the logic can be compared before and after a change:
##   godot --headless --path . --script res://tests/trade_audit.gd
## SEEDS=<n> sets how many leagues (default 12), ROUNDS=<n> how many offer attempts per league.

var _offers := []
var _ai_deals := []


func _init() -> void:
	Trades.difficulty_override = Trades.Difficulty.NORMAL
	Season.fixture_teams = 0
	Season.backfill_careers = false
	Season.seed_records = false
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 12
	var rounds := int(OS.get_environment("ROUNDS")) if OS.get_environment("ROUNDS") != "" else 30
	for sd in seeds:
		var s := Season.new_franchise(900 + sd, sd % 20)
		var rng := RandomNumberGenerator.new()
		rng.seed = 5000 + sd
		var tr := s.trades
		for r in rounds:
			tr.offers.clear()
			for t in s.league.teams:
				tr.patience[t.abbrev] = Trades.PATIENCE
			# Put a couple of the user's players on the block now and then.
			tr.block.clear()
			if r % 3 == 0:
				var mine: Array = s.user_team().roster.filter(func(x: Soldier): return Trades.tradeable(x))
				if not mine.is_empty():
					tr.block[mine[rng.randi() % mine.size()].id] = true
			var made := tr.offer_to_user(s, rng)
			if made:
				_offers.append(_record_offer(s, tr.offers.back()))
			tr.offers.clear()
			var before := tr.history.size()
			tr.ai_to_ai(s, rng)
			if tr.history.size() > before:
				_ai_deals.append(_record_deal(s, tr.history.back()))
			if r % 10 == 9:
				s.sim_week()
	_report()
	quit(0)


func _record_offer(s: Season, o: Dictionary) -> Dictionary:
	var tr := s.trades
	var ai: Team = o["team"]
	var user := s.user_team()
	var give: Array = o["give"]
	var get: Array = o["get"]
	var best: Soldier = ai.roster.reduce(func(a: Soldier, b: Soldier): return a if a.best_ovr() >= b.best_ovr() else b)
	var gives_best := give.any(func(a): return not Trades.is_pick(a) and a["soldier"] == best)
	var got_back: bool = give.any(func(a): return not Trades.is_pick(a) and a["soldier"].best_ovr() >= best.best_ovr() - 3)
	return {
		"fair": tr.fair_ratio(s, give, get),
		"ai_interest": tr.interest(s, ai, get, give),
		"mode": tr.mode(s, ai),
		"best_for_filler": gives_best and not got_back,
		"ai_after": ai.roster.size() - give.filter(func(a): return not Trades.is_pick(a)).size() + get.filter(func(a): return not Trades.is_pick(a)).size(),
		"user_after": user.roster.size() - get.filter(func(a): return not Trades.is_pick(a)).size() + give.filter(func(a): return not Trades.is_pick(a)).size(),
		"n_give": give.size(),
		"valid": tr.validate(s, user, get, ai, give) == "",
		"reason": String(o.get("reason", "")),
		"text": "%s gives [%s] for [%s]" % [ai.abbrev, ", ".join(PackedStringArray(give.map(func(a): return Trades.asset_text(s, a)))),
			", ".join(PackedStringArray(get.map(func(a): return Trades.asset_text(s, a))))],
	}


func _record_deal(s: Season, e: Dictionary) -> Dictionary:
	var a: Team = e["a"]
	var b: Team = e["b"]
	return {"fair": float(e["fair"]), "text": "%s gave [%s] to %s for [%s]" % [a.abbrev, ", ".join(PackedStringArray(e["a_gave"])), b.abbrev, ", ".join(PackedStringArray(e["b_gave"]))],
		"a_after": a.roster.size(), "b_after": b.roster.size()}


func _in_band(f: float) -> bool:
	return f >= Trades.FAIR_LOW and f <= Trades.FAIR_HIGH


func _report() -> void:
	print("\n=== CPU offers to the user: %d ===" % _offers.size())
	if not _offers.is_empty():
		var fairs: Array = _offers.map(func(o): return o["fair"])
		fairs.sort()
		print("  user-side market ratio: min %.2f  median %.2f  max %.2f" % [fairs[0], fairs[fairs.size() / 2], fairs[-1]])
		var out_band := _offers.filter(func(o): return not _in_band(o["fair"]))
		print("  outside the %.2f-%.2f band: %d (%.0f%%)" % [Trades.FAIR_LOW, Trades.FAIR_HIGH, out_band.size(), 100.0 * out_band.size() / _offers.size()])
		print("  user gets under 60%% of market value: %d" % _offers.filter(func(o): return o["fair"] < 0.6).size())
		print("  AI trades best player for filler: %d" % _offers.filter(func(o): return o["best_for_filler"]).size())
		print("  AI roster over %d after: %d   user roster over %d after: %d" % [Team.ROSTER_SIZE,
			_offers.filter(func(o): return o["ai_after"] > Team.ROSTER_SIZE).size(), Team.ROSTER_SIZE,
			_offers.filter(func(o): return o["user_after"] > Team.ROSTER_SIZE).size()])
		print("  fails validate(): %d   with a reason: %d" % [_offers.filter(func(o): return not o["valid"]).size(), _offers.filter(func(o): return o["reason"] != "").size()])
		for m in [Trades.CONTENDER, Trades.BALANCED, Trades.REBUILDING]:
			var of: Array = _offers.filter(func(o): return o["mode"] == m)
			if of.is_empty():
				continue
			var avg := 0.0
			for o in of:
				avg += o["fair"]
			print("  %-10s %3d offers, mean market ratio %.2f" % [m, of.size(), avg / of.size()])
		var worst: Array = _offers.duplicate()
		worst.sort_custom(func(a, b): return a["fair"] < b["fair"])
		print("  worst for the user:")
		for o in worst.slice(0, 5):
			print("    %.2f  %s" % [o["fair"], o["text"]])
	print("\n=== AI-to-AI deals: %d ===" % _ai_deals.size())
	if not _ai_deals.is_empty():
		var out_band := _ai_deals.filter(func(d): return not _in_band(d["fair"]))
		print("  outside the band: %d (%.0f%%)" % [out_band.size(), 100.0 * out_band.size() / _ai_deals.size()])
		var worst: Array = _ai_deals.duplicate()
		worst.sort_custom(func(a, b): return absf(log(a["fair"])) > absf(log(b["fair"])))
		for d in worst.slice(0, 5):
			print("    %.2f  %s" % [d["fair"], d["text"]])
