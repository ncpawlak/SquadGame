class_name CapMeters
extends RefCounted
## Career-mode ceiling meters (#141). Each upgradable stat group has a hidden meter. What the player does in matches
## fills it (kills and headshots feed Accuracy and Handling, captures feed Objective, running feeds Physicality, and
## so on), scaled by how well the match went; weekly practice fills it a little. A full meter is one point on that
## group's offseason ceiling raise (CapRaise adds it as the "Play" part); the leftover carries over. Specialist trainers
## (see Assets) make one group's meter fill faster. Career mode only: nothing here touches AI soldiers.

const FULL := 100.0  # meter points per ceiling point (no cost curve yet)
## Match grade scales every gain: x0.5 at a score of 50 or less, x1.5 at 90 or more.
const GRADE_LOW := 50.0
const GRADE_HIGH := 90.0
## Passive fill from a week's practice level (0-3): Physicality gets more (running is mostly invisible in a match).
const TRAIN_PHYSICALITY := [0.0, 1.0, 2.0, 3.0]
const TRAIN_OTHER := [0.0, 0.3, 0.6, 0.9]
## Per-group scale on match gains, tuned so a strong season earns each group a comparable ~1-2 ceiling points
## (kills are plentiful, captures and distance are not).
const GROUP_SCALE := {Stats.ACCURACY: 0.4, Stats.HANDLING: 0.35, Stats.PHYSICALITY: 4.0, Stats.MENTALITY: 0.9, Stats.OBJECTIVE: 3.5}


static func grade_factor(score: float) -> float:
	return clampf(0.5 + (score - GRADE_LOW) / (GRADE_HIGH - GRADE_LOW), 0.5, 1.5)


static func value(p: Soldier, group: StringName) -> float:
	return float(p.meters.get(group, 0.0))


## Whole ceiling points the meter holds.
static func points(p: Soldier, group: StringName) -> int:
	return int(value(p, group) / FULL)


static func _add(p: Soldier, group: StringName, amount: float) -> void:
	if amount <= 0.0 or not Stats.UPGRADABLE_GROUPS.has(group):
		return
	p.meters[group] = value(p, group) + amount * Assets.meter_mult(p, group)


## What one match line (the box score) is worth to each group, before the grade scales it.
static func match_gains(b: Dictionary) -> Dictionary:
	var kills := float(b.get("kills", 0))
	var hs := float(b.get("headshots", 0))
	return {
		Stats.ACCURACY: kills * 1.0 + hs * 1.5 + float(b.get("kills_long", 0)) * 1.0 + float(b.get("opening_kills", 0)) * 1.0,
		Stats.HANDLING: kills * 0.5 + hs * 1.0 + float(b.get("kills_short", 0)) * 1.0 + float(b.get("bursts", 0)) * 0.1,
		Stats.PHYSICALITY: float(b.get("distance", 0.0)) / 1000.0 + float(b.get("rounds_survived", 0)) * 0.3,
		Stats.MENTALITY: float(b.get("assists", 0)) * 1.0 + float(b.get("clutches", 0)) * 3.0 + float(b.get("saves", 0)) * 1.0 + float(b.get("wipes", 0)) * 1.0,
		Stats.OBJECTIVE: float(b.get("caps", 0)) * 2.0 + float(b.get("hill_s", 0.0)) / 20.0 * 0.5 + float(b.get("contest_s", 0.0)) / 30.0 * 0.5,
	}


## After a played match (`b` is his box-score line, `score` his grade).
static func after_match(season: Season, b: Dictionary, score: float) -> void:
	var p := season.player
	if p == null or not season.player_mode:
		return
	var f := grade_factor(score)
	var gains := match_gains(b)
	for g in gains:
		_add(p, g, float(gains[g]) * f * float(GROUP_SCALE.get(g, 1.0)))


## Once a week as the plan is applied: practice fills every meter a little.
static func train(p: Soldier, practice_level: int) -> void:
	var lv := clampi(practice_level, 0, 3)
	for g in Stats.UPGRADABLE_GROUPS:
		_add(p, g, float(TRAIN_PHYSICALITY[lv]) if g == Stats.PHYSICALITY else float(TRAIN_OTHER[lv]))


## Takes `n` ceiling points out of a group's meter when a raise uses them (the rest carries over).
static func spend(p: Soldier, group: StringName, n: int) -> void:
	p.meters[group] = maxf(0.0, value(p, group) - float(n) * FULL)
