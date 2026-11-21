class_name FpsRatings
extends RefCounted
## The rating map for the 3D game: every rating's effect in one place, as plain static functions so tests and the HUD need no
## scene. Ratings are 0-99. A rating never aims for you: it shrinks the penalty for human mistakes (spread, climb, flinch).
## Each function returns a multiplier or a small number; the callers (FpsWeapon, FpsPlayer, FpsBot, FpsHud) apply them.
##
##   Accuracy   short/medium/long -> base spread by distance      (FpsWeapon.base_spread)
##   Grouping   how fast the crosshair opens and how slowly it closes      expand_mult, recover_mult
##   Sway       how far the crosshair climbs while firing                  climb_mult (and idle sway, moving spread)
##   Reload     reload time, shown as the ring around the crosshair        FpsWeapon.reload_time
##   Speed      move speed; fast movers are slightly harder to hurt        graze_mult
##   Agility    left/right (strafe) speed                                  strafe_mult
##   Strength   damage absorption only                                     damage_taken_mult
##   Endurance  stamina; lingering fatigue that opens the crosshair         fatigue_gain, fatigue_spread_mult
##   Awareness  how far you sense enemies (edge ticks), hit direction      awareness_radius
##   Composure  how much being shot at shakes the crosshair                flinch_scale, suppress_spread_mult
##   Teamwork   better stats near teammates                                team_bonus
##   Anchor     holding the hill: less damage taken, steadier             anchor_damage_mult, anchor_spread_mult
##   Breach     attacking a held hill: better aim and damage              breach_spread_mult, breach_damage_mult
##   Obj IQ     how much the hill readout tells you                       intel_level

const HILL_NEAR_M := 14.0  ## a teammate this close counts for the teamwork bonus


static func norm(stats: Dictionary, id: StringName) -> float:
	return clampf(float(stats.get(id, 50)) / 99.0, 0.0, 1.0)


# --- handling ------------------------------------------------------------------------------

## Bloom added per shot: the worse the grouping, the quicker the crosshair opens. 1.6x at 0, 0.6x at 99.
static func expand_mult(stats: Dictionary) -> float:
	return lerpf(1.6, 0.6, norm(stats, Stats.GROUPING))


## How fast the crosshair closes again: the worse the grouping, the slower. 0.5x at 0, 1.5x at 99.
static func recover_mult(stats: Dictionary) -> float:
	return lerpf(0.5, 1.5, norm(stats, Stats.GROUPING))


## Muzzle climb while firing: the worse the sway, the more the crosshair rises. 1.8x at 0, 0.3x at 99.
static func climb_mult(stats: Dictionary) -> float:
	return lerpf(1.8, 0.3, norm(stats, Stats.SWAY))


# --- physicality ---------------------------------------------------------------------------

## Left/right speed from agility: 0.8x at 0, 1.2x at 99.
static func strafe_mult(stats: Dictionary) -> float:
	return lerpf(0.8, 1.2, norm(stats, Stats.AGILITY))


## Strength only absorbs damage: up to 25% less at 99.
static func damage_taken_mult(stats: Dictionary) -> float:
	return 1.0 - norm(stats, Stats.STRENGTH) * 0.25


## Fatigue (0..1) gained per second of sprinting; endurance slows it. About 0.045 at 0, 0.012 at 99.
static func fatigue_gain(stats: Dictionary) -> float:
	return lerpf(0.045, 0.012, norm(stats, Stats.ENDURANCE))


## Fatigue lost per second when not sprinting (endurance helps you recover): 0.03 at 0, 0.07 at 99.
static func fatigue_recover(stats: Dictionary) -> float:
	return lerpf(0.03, 0.07, norm(stats, Stats.ENDURANCE))


## A tired soldier's spread: up to +40% at full fatigue.
static func fatigue_spread_mult(fatigue: float) -> float:
	return 1.0 + clampf(fatigue, 0.0, 1.0) * 0.4


## A fast soldier is slightly harder to hurt: a damage multiplier of 1.0 down to 0.92, scaled by how fast he is moving.
static func graze_mult(stats: Dictionary, move_fraction: float) -> float:
	var s := norm(stats, Stats.SPEED)
	return 1.0 - clampf((s - 0.6) / 0.4, 0.0, 1.0) * 0.08 * clampf(move_fraction, 0.0, 1.0)


# --- mentality -----------------------------------------------------------------------------

## How far (metres) awareness lets you sense an enemy: 10 at 0, 32 at 99.
static func awareness_radius(stats: Dictionary) -> float:
	return lerpf(10.0, 32.0, norm(stats, Stats.AWARENESS))


## Scales the crosshair kick and shake when you take fire: 1.5x at 0, 0.4x at 99.
static func flinch_scale(stats: Dictionary) -> float:
	return lerpf(1.5, 0.4, norm(stats, Stats.COMPOSURE))


## Spread multiplier while under fire. `suppression` 0..1.5 builds when you are hit or shot near.
static func suppress_spread_mult(stats: Dictionary, suppression: float) -> float:
	return 1.0 + clampf(suppression, 0.0, 1.5) * 0.7 * flinch_scale(stats)


## Teamwork: stats get better the closer teammates are. `distances` are metres to living teammates.
## Returns 0 (alone) up to about 0.12 (two or more close, teamwork 99): a fractional bonus.
static func team_bonus(stats: Dictionary, distances: Array) -> float:
	var near := 0.0
	for d in distances:
		var dd := float(d)
		if dd <= HILL_NEAR_M:
			near += 1.0 - dd / (HILL_NEAR_M * 1.4)
	return clampf(near / 2.0, 0.0, 1.0) * lerpf(0.03, 0.12, norm(stats, Stats.TEAMWORK))


# --- objective -----------------------------------------------------------------------------

## On the hill: damage taken. 1.0 at 0, 0.65 at 99 (the sim's 35%).
static func anchor_damage_mult(stats: Dictionary) -> float:
	return 1.0 - norm(stats, Stats.ANCHOR) * 0.35


## On the hill: spread. 1.1 at 0 (shaky), 0.8 at 99.
static func anchor_spread_mult(stats: Dictionary) -> float:
	return lerpf(1.1, 0.8, norm(stats, Stats.ANCHOR))


## Attacking enemies that hold the hill (you are off it, they are on it): spread 1.05 at 0, 0.8 at 99.
static func breach_spread_mult(stats: Dictionary) -> float:
	return lerpf(1.05, 0.8, norm(stats, Stats.BREACH))


## ...and damage 0.95 at 0, up to 1.15 at 99.
static func breach_damage_mult(stats: Dictionary) -> float:
	return lerpf(0.95, 1.15, norm(stats, Stats.BREACH))


## What the hill readout shows: 0 a marker only, 1 plus who holds it, 2 plus the exact timers.
static func intel_level(stats: Dictionary) -> int:
	var iq := float(stats.get(Stats.OBJ_IQ, 50))
	if iq < 45.0:
		return 0
	if iq < 72.0:
		return 1
	return 2
