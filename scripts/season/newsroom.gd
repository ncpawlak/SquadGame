class_name Newsroom
extends "res://scripts/season/news/news_offseason.gd"
## The Weekly News: one feature article a week (and one per offseason step) about the user's
## club, written by its beat writer (LeagueData.PRESS) in a shared house voice.
##
## Nothing here is a fill-in-the-names template. Each issue gathers that week's facts (the
## game-by-game swing, holds and rounds, box scores, clutch finishes, standings, schemes,
## weather, injuries, contracts, morale and DNA), scores every angle the facts support and leads
## with the biggest one; the rest of the piece is assembled from whichever angles are left. Every
## sentence quotes facts that are true. Phrasing comes from small grammars whose choices each
## paper remembers (`used`), so a turn of phrase doesn't come back for weeks, and `memory`
## carries threads from issue to issue (streaks, the scheme question, injuries, the table).
## Quotes come from the soldiers themselves: temperament sets the voice, morale the mood and the
## top DNA motivation what they bring up.
##
## Generated on its own RNG seeded from the league, year and step: the league RNG is never touched
## and nothing in the league changes. Issues are plain dictionaries (saved with the Season):
##   {n, year, when, kind, team, paper, writer, section, headline, dek, dateline, body: [String],
##    pull_quote: {text, who}, sidebar: [{title, rows: [[label, value]]}], roundup: [{head, text}],
##    grade, angles: [String]}


func latest() -> Dictionary:
	return issues[-1] if not issues.is_empty() else {}


func count() -> int:
	return issues.size()


func issue(i: int) -> Dictionary:
	return issues[i] if i >= 0 and i < issues.size() else {}

## Marks issue index `i` read (and everything before it).
func mark_read(i: int) -> void:
	var a := issue(i)
	if not a.is_empty():
		read_upto = maxi(read_upto, int(a["n"]))


func is_read(i: int) -> bool:
	var a := issue(i)
	return a.is_empty() or int(a["n"]) <= read_upto

## Issues newer than the last one the user opened.
func unread() -> int:
	var n := 0
	for a in issues:
		if int(a["n"]) > read_upto:
			n += 1
	return n

## Story tag per game-article angle (angles that are stories carry their own tag, see NewsStories).
const ANGLE_TAGS := {"playoffs": "Playoffs", "comeback": "Comeback", "collapse": "Collapse", "sweep": "Sweep", "swept": "Swept",
	"clutch": "Clutch", "upset_win": "Upset", "upset_loss": "Upset", "streak_win": "Streak", "streak_loss": "Slide", "snapped": "Streak",
	"rivalry": "Rivalry", "star": "Star Turn", "injury": "Injury", "weather": "Weather", "first_win": "First Win", "hill": "Hill",
	"scheme": "Scheme", "goat": "Struggles"}
const KIND_TAGS := {"bye": "Bye Week", "sidelined": "Sidelines", "wrap": "Season Review", "resign": "Re-signing", "free_agency": "Free Agency",
	"draft": "Draft", "review": "Roster", "camp": "Camp", "preseason": "Preview"}

## After a regular-season or playoff week is played (the season is still on).
func publish_week(season: Season, wk: int) -> void:
	NewsHistory.record_week(history, season, wk)
	if not _open(season, season.week_label(wk), wk):
		return
	var m := _match_of(wk)
	var art: Dictionary
	if m != null and m.is_played():
		art = _game_article(m, wk)
	elif wk > season.regular_weeks:
		art = _sidelined_article(wk)
	else:
		art = _bye_article(wk)
	_close(art)

## After the final: the season in review (and the final itself if we played in it).
func publish_wrap(season: Season, wk: int) -> void:
	NewsHistory.record_week(history, season, wk)
	if not _open(season, "Season Review", wk):
		return
	_close(_wrap_article(wk))

## After an offseason step resolves: "Re-signing", "FA Day N", "Draft", "Roster Review", "Camp".
func publish_offseason(season: Season, step: String) -> void:
	if not _open(season, step, 0):
		return
	var art: Dictionary
	if step == "Re-signing":
		art = _resign_article()
	elif step.begins_with("FA Day"):
		art = _fa_article(step)
	elif step == "Draft":
		art = _draft_article()
	elif step == "Roster Review":
		art = _review_article()
	elif step == "Camp":
		art = _camp_article()
	else:
		_clear()
		return
	_add_take(art, _offseason_take())
	_close(art)

## A new season is about to start: the preview issue.
func publish_preseason(season: Season) -> void:
	if not _open(season, "Preseason", 0):
		return
	var art := _preseason_article()
	_add_take(art, _offseason_take())
	_close(art)


# --- issue plumbing -----------------------------------------------------------------


## Puts a writer's line second to last, so the piece still ends on its closing paragraph.
func _add_take(art: Dictionary, take: String) -> void:
	var body: Array = art["body"]
	if take != "" and body.size() >= 2:
		body.insert(body.size() - 1, take)


func _open(season: Season, when: String, wk: int) -> bool:
	_s = season
	_us = season.user_team()
	if _us == null:
		_s = null
		return false
	_r.seed = Season._mix([season.league.league_seed, season.year, when.hash(), wk, _us.id, issues.size(), 0x4E35])
	# Threads that count weeks start over with the season; last year's week numbers mean nothing in this one.
	if int(memory.get("year", -1)) != season.year:
		for k in ["goat", "bench", "scheme_doubt"]:
			memory.erase(k)
		memory["year"] = season.year
	_seen = {}
	_ids = {}
	for t in season.league.teams:
		for so in t.roster:
			_ids[so.id] = so
	for so in season.league.free_agents:
		_ids[so.id] = so
	_table = season.standings()
	_f = {"us_city": _city(_us), "us_nick": _nick(_us), "us_full": _full(_us), "us_abbr": _us.abbrev,
		"us_poss": _poss(_nick(_us)),
		"when": when, "year": str(season.year), "us_scheme": _us.scheme.display_name, "record": _record(_us),
		"div": _division(_us)}
	return true


func _close(art: Dictionary) -> void:
	var press := LeagueData.press_for(_us)
	art["n"] = (int(issues[-1]["n"]) + 1) if not issues.is_empty() else 1
	art["year"] = _s.year
	art["when"] = _f["when"]
	art["team"] = _us.abbrev
	art["paper"] = press[0]
	art["writer"] = press[1]
	art["dateline"] = String(art.get("dateline", _city(_us))).to_upper()
	for k in ["section", "headline", "dek", "grade"]:
		if not art.has(k):
			art[k] = ""
	for k in ["body", "sidebar", "roundup", "angles"]:
		if not art.has(k):
			art[k] = []
	if not art.has("pull_quote"):
		art["pull_quote"] = {}
	var body: Array = []
	for p in art["body"]:
		if String(p).strip_edges() != "":
			body.append(_polish(String(p)))
	art["body"] = body
	art["dek"] = _polish(art["dek"])
	if not art["pull_quote"].is_empty():
		art["pull_quote"]["text"] = _polish(art["pull_quote"]["text"])
	for r in art["roundup"]:
		r["text"] = _polish(r["text"])
	art["tags"] = _tags_for(art)
	art["links"] = _links_for_seen()
	memory["rank"] = _rank_of(_us)
	memory["buzz"] = _us.buzz
	if not memory.has("buzz_said"):
		memory["buzz_said"] = _us.buzz
	if not (art["angles"] as Array).is_empty():
		memory["lede"] = art["angles"][0]
		var ledes: Array = memory.get("ledes", [])
		ledes.append(art["angles"][0])
		memory["ledes"] = ledes.slice(maxi(0, ledes.size() - 5))
	issues.append(art)
	if issues.size() > MAX_ISSUES:
		issues.pop_front()
	_clear()


## Short labels for what an issue is about: story tags for the leading angles, or the kind of offseason issue.
func _tags_for(art: Dictionary) -> Array:
	var tags: Array = []
	if art["kind"] != KIND_GAME:
		return [KIND_TAGS.get(art["kind"], "News")]
	for angle: String in art["angles"]:
		var tag: String = STORIES[angle]["tag"] if STORIES.has(angle) else String(ANGLE_TAGS.get(angle, ""))
		if tag != "" and not tags.has(tag):
			tags.append(tag)
		if tags.size() >= 2:
			break
	return tags


## The soldiers the issue named in full, for linking their names to their pages: [{id, name, last}].
func _links_for_seen() -> Array:
	var out: Array = []
	for id in _seen:
		var so: Soldier = _ids.get(id)
		if so != null:
			out.append({"id": so.id, "name": so.display_name(), "last": so.last_name})
	return out


func _clear() -> void:
	_s = null
	_us = null
	_f = {}
	_seen = {}
	_ids = {}
	_table = []


# --- grammar --------------------------------------------------------------------
