class_name FpsBotBrain
extends RefCounted
## Pure bot decision logic: stats -> tuning numbers, and (tuning, situation) -> next state.
## FpsBot feeds it a context Dictionary built from the live world; tests feed it a fake one.

const HOLD := &"hold"
const PUSH := &"push"
const COVER := &"cover"
const ROTATE := &"rotate"
const TRADE := &"trade"

const COVER_HP := 0.35
const COVER_MIN_S := 2.5
const TRADE_WINDOW_S := 4.0


static func _n(soldier: Soldier, stat: StringName) -> float:
	var v := 50
	if soldier != null and soldier.stats.has(stat):
		v = soldier.get_stat(stat)
	return clampf(float(v) / 99.0, 0.0, 1.0)


## Everything the ratings control, as plain numbers.
static func tuning(soldier: Soldier, role: int = Scheme.Role.FLEX) -> Dictionary:
	var aw := _n(soldier, Stats.AWARENESS)
	var comp := _n(soldier, Stats.COMPOSURE)
	var tw := _n(soldier, Stats.TEAMWORK)
	var iq := _n(soldier, Stats.OBJ_IQ)
	var anc := _n(soldier, Stats.ANCHOR)
	var spd := _n(soldier, Stats.SPEED)
	var agi := _n(soldier, Stats.AGILITY)
	var value := clampf(0.15 + iq * 0.5 + anc * 0.25 + (0.1 if role == Scheme.Role.FRONTMAN else 0.0), 0.0, 1.0)
	return {
		"spot_range": 22.0 + aw * 45.0,
		"reaction_s": 0.6 - aw * 0.45,
		# multiplier on aim error while hurt or under fire: 1.0 is calm, higher is worse
		"fire_error_mult": 1.0 + (1.0 - comp) * 2.5,
		# metres the bot tries to stay within of the nearest teammate
		"stack_dist": lerpf(14.0, 3.0, tw),
		"trade_chance": tw,
		"point_value": value,
		"move_speed": 4.0 + spd * 3.0 + agi * 0.5,
		"role": role,
	}


## ctx keys:
##   state, state_time, hp_frac, since_damaged, visible_enemies, on_point,
##   zone ("empty"|"mine"|"enemy"|"contested"), allies_on_point, enemies_on_point,
##   allies_near (within stack range), dist_to_point, trade_age (-1 = none), tun
static func decide(ctx: Dictionary) -> StringName:
	var tun: Dictionary = ctx["tun"]
	var state: StringName = ctx.get("state", HOLD)
	var hp: float = ctx.get("hp_frac", 1.0)
	var seen: int = ctx.get("visible_enemies", 0)
	var since_hit: float = ctx.get("since_damaged", 99.0)
	# Hurt: break contact. Stay behind cover until calm for a moment.
	if hp < COVER_HP and (seen > 0 or since_hit < 3.0):
		return COVER
	if state == COVER and ctx.get("state_time", 0.0) < COVER_MIN_S and since_hit < 3.0:
		return COVER
	# A teammate just died: swing on the killer if teamwork says to, and we are not the one holding alone.
	var trade_age: float = ctx.get("trade_age", -1.0)
	if trade_age >= 0.0 and trade_age < TRADE_WINDOW_S and ctx.get("trade_roll", 1.0) < tun["trade_chance"]:
		return TRADE
	var on_point: bool = ctx.get("on_point", false)
	var zone: String = ctx.get("zone", "empty")
	var value: float = tun["point_value"]
	var dist: float = ctx.get("dist_to_point", 30.0)
	match zone:
		"empty":
			if on_point:
				return HOLD
			return PUSH if dist < 14.0 else ROTATE
		"mine":
			if on_point:
				return HOLD
			# Teammates already own it: a high-value player still piles on if it is thinly held.
			if value > 0.55 and ctx.get("allies_on_point", 0) < 2:
				return ROTATE
			return HOLD
		_:
			# enemy-held or contested
			var even: bool = ctx.get("allies_near", 0) + (1 if on_point else 0) >= ctx.get("enemies_on_point", 1)
			if on_point:
				return PUSH if (zone == "contested" and even) or value > 0.5 else HOLD
			if even or value > 0.6:
				return PUSH if dist < 25.0 else ROTATE
			return HOLD
	return HOLD
