class_name PlayerCareer
extends RefCounted
## Player mode (#100/#101): the user's created soldier. Phase 1 builds the soldier from the create-a-player
## choices; ratings stay at the combine floor until the combine (phase 2) awards them within the archetype's ceilings.

const START_AGE := 21
const MAX_NAME := 18
const MAX_CALLSIGN := 14


## Cleans a typed name: trimmed, single-spaced and cut to `limit`.
static func clean(text: String, limit: int) -> String:
	var t := " ".join(text.strip_edges().split(" ", false))
	return t.substr(0, limit)


## "" if the choices are valid, else a message for the create screen.
static func problem(first: String, last: String, callsign: String, head_id: String, archetype: StringName) -> String:
	if clean(first, MAX_NAME).is_empty() or clean(last, MAX_NAME).is_empty():
		return "Enter a first and last name."
	if clean(callsign, MAX_CALLSIGN).is_empty():
		return "Enter a callsign."
	if not FaceSpec.db().get("heads", {}).has(head_id):
		return "Pick a face."
	if Archetypes.find(archetype).is_empty():
		return "Pick an archetype."
	return ""


## Callsigns already in use by league soldiers, lower-cased (a created soldier may not copy one).
static func taken_callsigns(league: League) -> Dictionary:
	var taken := {}
	if league != null:
		for s in league.all_soldiers():
			if s.callsign != "":
				taken[s.callsign.to_lower()] = true
	return taken


## Builds the soldier. Every drilled stat starts at Archetypes.FLOOR; toughness and injury start at Archetypes.FIXED_STATS.
static func create_soldier(id: int, first: String, last: String, callsign: String, head_id: String,
		morph_seed: int, archetype: StringName) -> Soldier:
	var s := Soldier.new()
	s.id = id
	s.first_name = clean(first, MAX_NAME)
	s.last_name = clean(last, MAX_NAME)
	s.callsign = clean(callsign, MAX_CALLSIGN)
	s.age = START_AGE
	for stat in Stats.ALL:
		s.stats[stat] = Archetypes.FLOOR
	s.stats.merge(Archetypes.FIXED_STATS, true)
	s.dev = 2
	s.face_override = FaceSpec.make_override(head_id, morph_seed)
	s.look = Look.generate(id, s.age, Archetypes.role_of(archetype))
	return s
