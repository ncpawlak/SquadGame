"""Summarises the JSON lines written by tools/plan_tune.gd.

    python tools/plan_tune_report.py <results dir> [tag]

Prints, per age and plan style (averaged over seeds): OVR by season, the season each star was earned in, games
played, brand, average fatigue, the provisional Hall of Fame score, and the Hall verdicts when the run included
the vote. Used to tune the weekly plan numbers (#138).
"""
import glob
import json
import os
import statistics
import sys

folder = sys.argv[1]
tag = sys.argv[2] if len(sys.argv) > 2 else ""
rows = []
for path in glob.glob(os.path.join(folder, (tag + "_" if tag else "") + "*.jsonl")):
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line.startswith("{"):
            rows.append(json.loads(line))

groups = {}
for r in rows:
    groups.setdefault((r["style"], r["age"]), []).append(r)


def mean(xs):
    xs = [x for x in xs if x is not None]
    return statistics.mean(xs) if xs else float("nan")


def star_season(r, dev):
    for i, s in enumerate(r["seasons"]):
        if s["dev"] >= dev:
            return i + 1
    return None


print("runs:", len(rows))
for (style, age) in sorted(groups):
    g = groups[(style, age)]
    n = max(len(r["seasons"]) for r in g)
    ovr = " ".join("%.0f" % mean([r["seasons"][i]["ovr"] for r in g if len(r["seasons"]) > i]) for i in range(n))
    games = " ".join("%.0f" % mean([r["seasons"][i]["games"] for r in g if len(r["seasons"]) > i]) for i in range(n))
    stars = " ".join("%s" % ("-" if mean([star_season(r, d) for r in g]) != mean([star_season(r, d) for r in g]) else "%.1f" % mean([star_season(r, d) for r in g])) for d in (2, 3, 4))
    brand = mean([r["seasons"][-1]["brand"] for r in g])
    fat = mean([s["fatigue"] for r in g for s in r["seasons"]])
    hof = mean([r["seasons"][-1]["hof"] for r in g])
    verdicts = [r.get("verdict") for r in g if r.get("verdict")]
    final = [r.get("final_hof") for r in g if r.get("final_hof") is not None]
    print("\n%-8s age %d  (%d runs)" % (style, age, len(g)))
    print("  ovr by season :", ovr)
    print("  games / season:", games)
    def first(r, lvl):
        for i, s in enumerate(r["seasons"]):
            if s["ovr"] >= lvl:
                return str(i + 1)
        return "-"
    print("  first season at 90 / 95 / 99 OVR:", "  ".join("%s/%s/%s" % (first(r, 90), first(r, 95), first(r, 99)) for r in g))
    print("  base ovr      :", " ".join("%.0f" % mean([r["seasons"][i].get("base", 0) for r in g if len(r["seasons"]) > i]) for i in range(n)))
    print("  avg group cap :", " ".join("%.0f" % mean([r["seasons"][i].get("caps", 0) for r in g if len(r["seasons"]) > i]) for i in range(n)))
    print("  cash / deals  :", " ".join("%.0f/%.0f" % (mean([r["seasons"][i].get("cash", 0) for r in g if len(r["seasons"]) > i]), mean([r["seasons"][i].get("deals", 0) for r in g if len(r["seasons"]) > i])) for i in range(n)))
    print("  raises / stories (end):", "%.0f / %.0f" % (mean([r["seasons"][-1].get("raises", 0) for r in g]), mean([r["seasons"][-1].get("stories", 0) for r in g])))
    print("  wear by season:", " ".join("%.0f" % mean([r["seasons"][i].get("wear", 0) for r in g if len(r["seasons"]) > i]) for i in range(n)))
    print("  star 2/3/4 in season:", stars, "  brand end: %.0f  mean fatigue: %.0f  hof score end: %.0f" % (brand, fat, hof))
    if verdicts:
        print("  hall: %s  final scores %s" % (verdicts, final))
