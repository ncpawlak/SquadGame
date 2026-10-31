class_name HallOfFame
extends RefCounted
## The Hall of Fame: retired soldiers are scored on their careers and, WAIT_SEASONS after they retire,
## the best of them above THRESHOLD are inducted (at most CLASS_MAX a year).
##
## The score has four parts, all weighted from the constants below:
## - production: career totals and kills per death, each as a percentile among every qualified
##   career in the league, so the bar rises and falls with the league itself;
## - awards: Season MVPs, other awards and All-League picks;
## - titles: seasons played for the champion;
## - peak: the best single season (kills), again as a percentile.
##
## Entries (Season.hall_of_fame): {soldier, year (inducted), score, club (Team or null), honors: Array[String]}

## Seasons a soldier waits after retiring before the Hall votes on him.
const WAIT_SEASONS := 3
const CLASS_MAX := 3
## Score needed to be inducted (the scale tops out near 110). Tuned with tools/hall_tune.gd: over
## 14 seasons it inducts about 2 a year from ~72 retirees, once careers are long enough to score.
const THRESHOLD := 65.0

## Career matches needed to be scored at all, and matches in a season for it to count as a title.
const MIN_MATCHES := 30
const MIN_TITLE_MATCHES := 4

## Share of the production points each career stat carries (kd is kills per death).
const WEIGHTS := {"kills": 3.0, "assists": 1.0, "damage": 2.0, "mvps": 3.0, "clutches": 1.0, "kd": 2.0}
const PRODUCTION_POINTS := 50.0
const MVP_POINTS := 12.0
const AWARD_POINTS := 5.0
const ALL_LEAGUE_POINTS := 3.0
const AWARDS_CAP := 40.0
const TITLE_POINTS := 4.0
const TITLES_CAP := 16.0
const PEAK_POINTS := 10.0


## Sorted value lists to rank careers and seasons against, built once per vote.
static func context(season: Season) -> Dictionary:
	var ctx := {"career": {}, "peak": [], "champions": {}}
	for stat in WEIGHTS:
		ctx["career"][stat] = []
	for so: Soldier in Records.soldiers(season):
		if int(so.career["matches"]) >= MIN_MATCHES:
			for stat in WEIGHTS:
				ctx["career"][stat].append(_career_value(so, stat))
		for year in so.season_lines:
			ctx["peak"].append(float(so.season_lines[year].get("kills", 0)))
	for stat in WEIGHTS:
		ctx["career"][stat].sort()
	ctx["peak"].sort()
	for snap: SeasonSnapshot in season.history:
		if snap.champion != null:
			ctx["champions"][snap.year] = snap.champion.abbrev
	return ctx


static func _career_value(so: Soldier, stat: String) -> float:
	if stat == "kd":
		return float(so.career["kills"]) / maxf(1.0, float(so.career["deaths"]))
	return float(so.career[stat])


## Fraction of `sorted` strictly below `v` (0 to 1).
static func _percentile(sorted: Array, v: float) -> float:
	return float(sorted.bsearch(v)) / maxf(1.0, float(sorted.size())) if not sorted.is_empty() else 0.0


## The soldier's Hall score and where it came from: {score, production, awards, titles, peak,
## titles_won, honors}. A career shorter than MIN_MATCHES scores 0.
static func breakdown(season: Season, ctx: Dictionary, so: Soldier) -> Dictionary:
	var out := {"score": 0.0, "production": 0.0, "awards": 0.0, "titles": 0.0, "peak": 0.0, "titles_won": 0, "honors": []}
	if int(so.career["matches"]) < MIN_MATCHES:
		return out
	var weight_sum := 0.0
	var pct_sum := 0.0
	for stat in WEIGHTS:
		weight_sum += WEIGHTS[stat]
		pct_sum += WEIGHTS[stat] * _percentile(ctx["career"][stat], _career_value(so, stat))
	out["production"] = PRODUCTION_POINTS * pct_sum / weight_sum
	var awards := 0.0
	for rev: SeasonReview in season.review_history:
		for a in rev.award_for(so):
			out["honors"].append("%d %s" % [rev.year, a])
			if a == RetiredCallsigns.MVP_AWARD:
				awards += MVP_POINTS
			elif a == "All-League":
				awards += ALL_LEAGUE_POINTS
			else:
				awards += AWARD_POINTS
	out["awards"] = minf(awards, AWARDS_CAP)
	var titles := 0
	var best_season := 0.0
	for year in so.season_lines:
		var line: Dictionary = so.season_lines[year]
		best_season = maxf(best_season, float(line.get("kills", 0)))
		if line.get("team", "") != "" and ctx["champions"].get(int(year), "") == line["team"] and int(line.get("matches", 0)) >= MIN_TITLE_MATCHES:
			titles += 1
	out["titles_won"] = titles
	out["titles"] = minf(titles * TITLE_POINTS, TITLES_CAP)
	out["peak"] = PEAK_POINTS * _percentile(ctx["peak"], best_season)
	out["score"] = out["production"] + out["awards"] + out["titles"] + out["peak"]
	return out


static func is_member(season: Season, so: Soldier) -> bool:
	return entry_of(season, so) != {}


static func entry_of(season: Season, so: Soldier) -> Dictionary:
	for e in season.hall_of_fame:
		if e["soldier"] == so:
			return e
	return {}


## The class inducted in `year`, best score first.
static func class_of(season: Season, year: int) -> Array:
	return season.hall_of_fame.filter(func(e: Dictionary): return e["year"] == year)


## Retirees whose wait ends this year: they retired WAIT_SEASONS ago and are not in yet.
static func candidates(season: Season) -> Array:
	var out: Array = []
	for r in season.retirements:
		if r["year"] == season.year - WAIT_SEASONS and not is_member(season, r["soldier"]):
			out.append(r["soldier"])
	return out


## The yearly vote (run at season rollover). Returns the new entries; their callsigns are
## retired too unless somebody is wearing them now.
static func run(season: Season, threshold := THRESHOLD) -> Array:
	var cands := candidates(season)
	if cands.is_empty():
		return []
	var ctx := context(season)
	var scored: Array = []
	for so: Soldier in cands:
		var b := breakdown(season, ctx, so)
		if b["score"] >= threshold:
			scored.append({"soldier": so, "year": season.year, "score": b["score"],
				"club": RetiredCallsigns.club_of(season, so).get("team"), "honors": b["honors"]})
	scored.sort_custom(func(a: Dictionary, b: Dictionary):
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["soldier"].id < b["soldier"].id)
	var inducted: Array = scored.slice(0, CLASS_MAX)
	for e in inducted:
		season.hall_of_fame.append(e)
		RetiredCallsigns.propose(season, RetiredCallsigns.make_entry(season, e["soldier"], true))
	return inducted
