class_name DotEffectState
extends RefCounted

## Everything affecting one entity, and what it adds up to.
##
## [b]The aggregate is recomputed on every change rather than cached against a
## deadline.[/b] That is a deliberate choice against the obvious optimisation, and the
## reason is in this family's own notes: [code]DotNetInterest.relevant_for[/code] cached
## per peer, an entity spawned since was in nobody's cached set, and on a host ticking
## faster than the wall clock the cache never expired and the entity was never sent
## once. A cached answer that misses what changed since looks exactly like a wrong
## answer, and the producer is where you look for it.
##
## Recomputing is a loop over at most a handful of instances and happens when an effect
## is applied, removed or expires — not per tick, and never per query.

var entity: int = 0

var instances: Array[DotEffectInstance] = []

# The aggregate. Read through the accessors; they are what a game asks.
var _damage_taken: float = 1.0
var _damage_dealt: float = 1.0
var _move_speed: float = 1.0
var _jump: float = 1.0
var _fire_rate: float = 1.0
var _invulnerable: bool = false
var _no_attack: bool = false
var _no_move: bool = false
var _no_jump: bool = false
var _no_capture: bool = false
var _ignores_falloff: bool = false
var _immune: Dictionary = {}


func _init(p_entity: int = 0) -> void:
	entity = p_entity


func is_empty() -> bool:
	return instances.is_empty()


func count() -> int:
	return instances.size()


func has(id: StringName) -> bool:
	for inst in instances:
		if inst.id() == id:
			return true
	return false


func find(id: StringName, source: int = -1) -> DotEffectInstance:
	for inst in instances:
		if inst.id() != id:
			continue
		if source >= 0 and inst.source != source:
			continue
		return inst
	return null


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for inst in instances:
		if not out.has(inst.id()):
			out.append(inst.id())
	return out


## Whether anything here has this tag. What "am I on fire" asks.
func has_tag(tag: String) -> bool:
	for inst in instances:
		if inst.def != null and inst.def.has_tag(tag):
			return true
	return false


## Whether a new effect with these tags would be refused.
func is_immune_to(def: DotEffectDef) -> bool:
	if def == null:
		return false
	for tag in def.tags:
		if _immune.has(tag):
			return true
	return false


# --- The aggregate ---------------------------------------------------------

func damage_taken_scale() -> float:
	return _damage_taken


func damage_dealt_scale() -> float:
	return _damage_dealt


func move_speed_scale() -> float:
	return _move_speed


func jump_scale() -> float:
	return _jump


func fire_rate_scale() -> float:
	return _fire_rate


func is_invulnerable() -> bool:
	return _invulnerable


func may_attack() -> bool:
	return not _no_attack


func may_move() -> bool:
	return not _no_move


func may_jump() -> bool:
	return not _no_jump


func may_capture() -> bool:
	return not _no_capture


func ignores_falloff() -> bool:
	return _ignores_falloff


## Recompute the aggregate from the instances. Called on every mutation.
##
## [b]Multiplicative, and stacks multiply too.[/b] Two 0.5 slows are 0.25 rather than
## zero, which is the property that makes the table safe to extend: an additive scheme
## reaches zero at two entries and then a third one is a movement bug with no visible
## cause.
func recompute() -> void:
	_damage_taken = 1.0
	_damage_dealt = 1.0
	_move_speed = 1.0
	_jump = 1.0
	_fire_rate = 1.0
	_invulnerable = false
	_no_attack = false
	_no_move = false
	_no_jump = false
	_no_capture = false
	_ignores_falloff = false
	_immune.clear()

	for inst in instances:
		var def := inst.def
		if def == null:
			continue
		var n := maxi(inst.stacks, 1)
		_damage_taken *= pow(def.damage_taken_scale, n)
		_damage_dealt *= pow(def.damage_dealt_scale, n)
		_move_speed *= pow(def.move_speed_scale, n)
		_jump *= pow(def.jump_scale, n)
		_fire_rate *= pow(def.fire_rate_scale, n)
		_invulnerable = _invulnerable or def.invulnerable
		_no_attack = _no_attack or def.no_attack
		_no_move = _no_move or def.no_move
		_no_jump = _no_jump or def.no_jump
		_no_capture = _no_capture or def.no_capture
		_ignores_falloff = _ignores_falloff or def.ignores_falloff
		for tag in def.immune_to:
			_immune[tag] = true


func to_wire() -> Array:
	var out: Array = []
	for inst in instances:
		out.append(inst.to_wire())
	return out


func describe() -> Dictionary:
	return {
		"entity": entity,
		"effects": count(),
		"damage_taken": _damage_taken,
		"damage_dealt": _damage_dealt,
		"move": _move_speed,
		"invulnerable": _invulnerable,
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append(
		"entity %d: %d effect(s) taken=%.2f dealt=%.2f move=%.2f%s"
			% [
				entity, count(), _damage_taken, _damage_dealt, _move_speed,
				" INVULNERABLE" if _invulnerable else "",
			]
	)
	for inst in instances:
		out.append(
			"    %s x%d from %d until %d"
				% [inst.id(), inst.stacks, inst.source, inst.expires_at]
		)
	return out
