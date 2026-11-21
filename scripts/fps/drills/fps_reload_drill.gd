class_name FpsReloadDrill
extends FpsPopupDrill
## Active reload (RELOAD): you cannot move, the magazine holds three rounds. When it runs dry a reload starts and a green
## sweet spot shows on the ring around the crosshair. Press R again while the fill is inside it for a perfect reload (done
## at once). Too early or too late fumbles it (a slower reload); no press is a plain, normal reload.
## Score: the average timing quality over RELOADS reloads, plus a small share for hits.

const MAG := 3
const RELOADS := 5
## The sweet spot, as fractions of the reload.
const SWEET := Vector2(0.55, 0.70)
## How far outside the window (as a fraction of the reload) a press still earns something.
const TAP_FALLOFF := 0.25
const FUMBLE_SECS := 0.5
## Quality of a reload with no press at all (a normal reload): above a bad fumble, far below a perfect one.
const NO_TAP_QUALITY := 0.2
const HIT_SHARE := 0.15
const DEFAULT_RELOAD_SECS := 2.3
const SLOTS := 3
const SPACING := 2.0
const DISTANCE := 12.0

## One quality per finished reload (0..1).
var qualities: Array = []
var _ammo := MAG
var _reloading := false
var _tapped := false
var _quality := NO_TAP_QUALITY
var _rel_t := 0.0
var _rel_dur := DEFAULT_RELOAD_SECS
var _hooked: FpsWeapon = null


func _init() -> void:
	super()
	stat = Stats.RELOAD
	title = "Active reload"
	instructions = "You cannot move. Three rounds per magazine. When you reload, press R again inside the green mark on the ring."
	lock_player = true
	weapon_mode = &"semi"
	# Aim is 99 so the hits are yours; the reload rating stays standard (the drill times YOUR press).
	loadout = {Stats.SHORT_ACC: 99, Stats.MEDIUM_ACC: 99, Stats.LONG_ACC: 99}
	target_count = 30
	target_life = 3.0
	first_at = 1.0
	gap_min = 0.9
	gap_max = 1.2
	duration = 70.0
	for i in SLOTS:
		slot_points.append(Vector3((i - (SLOTS - 1) / 2.0) * SPACING, 0.0, -DISTANCE))


# ---- scoring rules (pure) -------------------------------------------------------------------------------------------

## Quality of one press: 1 anywhere inside [lo, hi], falling to 0 over TAP_FALLOFF outside, and never above 0.5 outside.
static func tap_quality(progress: float, lo: float, hi: float) -> float:
	if progress >= lo and progress <= hi:
		return 1.0
	var dist := lo - progress if progress < lo else progress - hi
	return 0.5 * FpsDrill.clamp01(1.0 - dist / TAP_FALLOFF)


## The drill score: mean quality over `reloads` (missing reloads count 0), plus a small share for hits out of `rounds` fired.
static func reload_score(quals: Array, hits_made: int, rounds: int, reloads: int = RELOADS) -> float:
	var timing := FpsDrill.mean_value(quals, reloads)
	var aim := FpsDrill.clamp01(float(hits_made) / float(maxi(rounds, 1)))
	return FpsDrill.clamp01((1.0 - HIT_SHARE) * timing + HIT_SHARE * aim * (1.0 if timing > 0.0 else 0.0))


# ---- run ------------------------------------------------------------------------------------------------------------

func _build() -> void:
	_make_targets()


func _weapon() -> FpsWeapon:
	if player == null:
		return null
	return player.get("weapon") as FpsWeapon


func _begin() -> void:
	super()
	qualities.clear()
	_ammo = MAG
	_reloading = false
	var w := _weapon()
	if w != null:
		w.mag_limit = MAG
		w.infinite_reserve = true
		w.reloading = false
		w.sweet_spot = Vector2(-1.0, -1.0)
		w.refill()
		if _hooked != w:
			_unhook()
			w.reload_tapped.connect(_on_reload_tap)
			w.reloaded.connect(_complete_reload)
			_hooked = w


func _unhook() -> void:
	if _hooked != null and is_instance_valid(_hooked):
		if _hooked.reload_tapped.is_connected(_on_reload_tap):
			_hooked.reload_tapped.disconnect(_on_reload_tap)
		if _hooked.reloaded.is_connected(_complete_reload):
			_hooked.reloaded.disconnect(_complete_reload)
	_hooked = null


func _end() -> void:
	super()
	var w := _hooked
	_unhook()
	if w != null and is_instance_valid(w):
		w.sweet_spot = Vector2(-1.0, -1.0)
		w.mag_limit = -1
		w.refill()


func _run(delta: float) -> void:
	if _reloading:
		_rel_t += delta
		var w := _weapon()
		# With a weapon, it reports the end of the reload (signal). Without one the drill keeps its own clock.
		if (w == null or not w.reloading) and _rel_t >= _rel_dur:
			_complete_reload()
	if state == State.RUNNING:
		super(delta)


## Progress through the running reload, 0..1.
func reload_progress() -> float:
	var w := _weapon()
	if w != null and w.reloading:
		return w.reload_progress()
	return clampf(_rel_t / maxf(_rel_dur, 0.001), 0.0, 1.0)


func is_reloading() -> bool:
	return _reloading


## Press "R again": through the weapon when there is one, otherwise straight into the rules (tests).
func press_reload() -> void:
	var w := _weapon()
	if w != null and w.reloading:
		w.reload_tap()
	else:
		_on_reload_tap(reload_progress())


func _shot(_hit: Dictionary) -> void:
	if _reloading:
		return
	_ammo -= 1
	if _ammo <= 0:
		_start_reload()


func _start_reload() -> void:
	_reloading = true
	_tapped = false
	_quality = NO_TAP_QUALITY
	_rel_t = 0.0
	_rel_dur = DEFAULT_RELOAD_SECS
	var w := _weapon()
	if w != null:
		if not w.reloading:
			w.reload()
		if w.reloading:
			_rel_dur = w.reload_total
			w.sweet_spot = SWEET


func _on_reload_tap(progress: float) -> void:
	if state != State.RUNNING or not _reloading or _tapped:
		return
	_tapped = true
	_quality = tap_quality(progress, SWEET.x, SWEET.y)
	var w := _weapon()
	if w != null:
		w.sweet_spot = Vector2(-1.0, -1.0)
	if _quality >= 1.0:
		# Perfect: the reload is over at once.
		if w != null and w.reloading:
			w.finish_reload_early()
		_complete_reload()
	else:
		# Fumbled: the rest of the reload takes longer.
		_rel_dur += FUMBLE_SECS
		if w != null and w.reloading:
			w.extend_reload(FUMBLE_SECS)


func _complete_reload() -> void:
	if not _reloading:
		return
	_reloading = false
	_ammo = MAG
	qualities.append(_quality)
	var w := _weapon()
	if w != null:
		w.sweet_spot = Vector2(-1.0, -1.0)
	if state == State.RUNNING and qualities.size() >= RELOADS:
		finish(_final_score())


func _final_score() -> float:
	return reload_score(qualities, hits, RELOADS * MAG)


func _hud_extra() -> String:
	var status := "RELOADING - press R in the green" if _reloading else "Mag %d" % _ammo
	return "Reload %d / %d   %s\nHits %d" % [mini(qualities.size() + (1 if _reloading else 0), RELOADS), RELOADS, status, hits]
