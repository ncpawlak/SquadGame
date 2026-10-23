class_name Stats
extends RefCounted
## Stat definitions shared by the whole sim. All ratings are 0-99.

const MIN_RATING := 0
const MAX_RATING := 99

const AWARENESS := &"awareness"
const SHORT_ACC := &"short_acc"
const MEDIUM_ACC := &"medium_acc"
const LONG_ACC := &"long_acc"
const GROUPING := &"grouping"
const SPEED := &"speed"
const STRENGTH := &"strength"
const AGILITY := &"agility"
const ENDURANCE := &"endurance"
const RELOAD := &"reload"
const COMPOSURE := &"composure"
const TOUGHNESS := &"toughness"
const INJURY := &"injury"
const TEAMWORK := &"teamwork"

const ALL: Array[StringName] = [
	AWARENESS, SHORT_ACC, MEDIUM_ACC, LONG_ACC, GROUPING,
	SPEED, STRENGTH, AGILITY, ENDURANCE, RELOAD,
	COMPOSURE, TOUGHNESS, INJURY, TEAMWORK,
]

const LABELS := {
	AWARENESS: "Awareness",
	SHORT_ACC: "Short Range Acc",
	MEDIUM_ACC: "Medium Range Acc",
	LONG_ACC: "Long Range Acc",
	GROUPING: "Grouping Acc",
	SPEED: "Speed",
	STRENGTH: "Strength",
	AGILITY: "Agility",
	ENDURANCE: "Endurance",
	RELOAD: "Reload Speed",
	COMPOSURE: "Composure",
	TOUGHNESS: "Toughness",
	INJURY: "Injury",
	TEAMWORK: "Teamwork",
}

const ABBREV := {
	AWARENESS: "AWR",
	SHORT_ACC: "SRA",
	MEDIUM_ACC: "MRA",
	LONG_ACC: "LRA",
	GROUPING: "GRP",
	SPEED: "SPD",
	STRENGTH: "STR",
	AGILITY: "AGI",
	ENDURANCE: "END",
	RELOAD: "RLD",
	COMPOSURE: "CMP",
	TOUGHNESS: "TGH",
	INJURY: "INJ",
	TEAMWORK: "TWK",
}


static func clamp_rating(value: float) -> int:
	return clampi(roundi(value), MIN_RATING, MAX_RATING)


static func make_uniform(value: int) -> Dictionary:
	var d := {}
	for s in ALL:
		d[s] = value
	return d
