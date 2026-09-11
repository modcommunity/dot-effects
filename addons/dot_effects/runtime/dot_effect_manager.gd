class_name DotEffectManager
extends Node

## Status effects, incapacitation and temporary health, for every entity in a game.
##
## [codeblock]
## var effects := DotEffectManager.new()
## effects.rules.downed_enabled = true
## effects.define(DotEffectDef.burning(&"afterburn", 3.0, 10 * 64))
## add_child(effects)
##
## effects.damaged.connect(func(entity, amount, type, source):
##     health_of(entity).apply(DotDamage.make(amount, type, source, tick)))
##
## # ... once per physics tick:
## effects.advance(tick)
## [/codeblock]
##
## [b]It never touches a health value.[/b] A burning entity does not lose health here;
## [signal damaged] is emitted with an amount and the game applies it to whatever it
## keeps health in — [DotHealth] in every game in this family. dot-effects does not
## import dot-combat, because a slow, a stun and a speed boost are the same rule in a
## game with no damage in it at all, and a hard dependency would make that game one
## that cannot compile.
##
## The same seam in the other direction: this addon does not know when an entity dies.
## A game calls [method on_death], and that is also what makes the downed half work —
## [method report_zero_health] answers "down or dead", and the game does what it says.
##
## [b]No autoload.[/b] A server that simulates and a client that mirrors are two of
## these in one process, which is the family's rule and the reason it exists.

## An effect started. [param stacks] is what it is at now.
signal applied(entity: int, id: StringName, source: int, stacks: int)

## An effect ended, by expiring or by being removed.
signal removed(entity: int, id: StringName, reason: StringName)

## A periodic effect wants to hurt somebody. The game applies it.
signal damaged(entity: int, amount: float, type: StringName, source: int)

## A periodic effect wants to heal somebody. [param overheal] says whether it may go
## above the normal maximum.
signal healed(entity: int, amount: float, overheal: bool, source: int)

## An entity went down rather than dying.
signal downed(entity: int, incaps: int)

## Somebody started picking them up.
signal revive_started(entity: int, by: int)

## …and stopped, without finishing.
signal revive_stopped(entity: int, reason: StringName)

## They are back up, with this much health.
signal revived(entity: int, by: int, health: float)

## They bled out, or were down for the last time.
signal died(entity: int, reason: StringName)

## Temporary health above the maximum decayed. The game subtracts it.
signal temp_decayed(entity: int, amount: float)

@export var rules: DotEffectRules = null

## Effects this game has. Assigning this and calling [method setup] is the whole of
## loading an effect table.
@export var definitions: Array[DotEffectDef] = []

## Off on a client, which mirrors rather than simulating.
@export var authoritative: bool = true

## Where an entity is, for the revive distance test.
## [code](entity: int) -> Vector3[/code]. Unset means do not check distance.
var position_fn: Callable = Callable()

## Whether an entity is on the same side as another, for a game where only team-mates
## may revive. [code](a: int, b: int) -> bool[/code]. Unset means anybody may.
var allies_fn: Callable = Callable()

var _defs: Dictionary = {}
var _states: Dictionary = {}
var _downed: Dictionary = {}
var _temp: Dictionary = {}
var _temp_at: Dictionary = {}
var _tick: int = 0


func _init() -> void:
	if rules == null:
		rules = DotEffectRules.new()


func setup(p_defs: Array[DotEffectDef] = []) -> DotResult:
	if not p_defs.is_empty():
		definitions = p_defs
	if rules == null:
		rules = DotEffectRules.new()

	var res := rules.validate()
	if not res.ok:
		return res.wrap("effect rules")

	_defs.clear()
	for def in definitions:
		var one := define(def)
		if not one.ok:
			return one

	DotLog.info("effects", "%d effects defined" % _defs.size())
	return DotResult.success(null)


## Add one effect to the table. Refuses a duplicate rather than replacing it.
func define(def: DotEffectDef) -> DotResult:
	if def == null:
		return DotResult.fail(DotError.CODE_INVALID, "A null effect definition.")
	var res := def.validate()
	if not res.ok:
		return res
	if _defs.has(def.id) and _defs[def.id] != def:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"Two effects are called '%s'. An id is what a wire form, a HUD and a "
				+ "weapon all refer to, so a duplicate silently makes two of them one."
			) % def.id
		)
	_defs[def.id] = def
	if not definitions.has(def):
		definitions.append(def)
	return DotResult.success(null)


func definition(id: StringName) -> DotEffectDef:
	return _defs.get(id, null)


func has_definition(id: StringName) -> bool:
	return _defs.has(id)


# --- Applying ---------------------------------------------------------------

## Put an effect on an entity.
##
## Refuses rather than silently doing nothing, and the refusals matter: an immunity, a
## per-entity cap and an unknown id are three very different problems that all look like
## "the burn did not apply".
func apply(id: StringName, entity: int, source: int = 0) -> DotResult:
	if not authoritative:
		return DotResult.fail(
			DotError.CODE_STATE,
			"A mirroring effect manager does not apply effects; it is told about them."
		)

	var def: DotEffectDef = _defs.get(id, null)
	if def == null:
		return DotResult.fail(
			DotError.CODE_INVALID, "No effect is defined as '%s'." % id
		)

	var state := state_of(entity)

	if state.is_immune_to(def):
		return DotResult.fail(
			DotError.CODE_FORBIDDEN,
			"Entity %d is immune to '%s'." % [entity, id]
		)

	# Curing happens before the cap is checked: an effect that cures fire and is refused
	# for being the twenty-fifth would leave the fire burning, which is the opposite of
	# what it was applied for.
	for tag in def.cures:
		_remove_tagged(state, tag, &"cured")

	var existing := state.find(id, source if def.per_source else -1)
	if existing != null:
		match def.stacking:
			DotEffectDef.Stacking.IGNORE:
				return DotResult.fail(
					DotError.CODE_STATE,
					"'%s' is already on entity %d and does not reapply." % [id, entity]
				)
			DotEffectDef.Stacking.REFRESH:
				existing.refresh(_tick)
				applied.emit(entity, id, source, existing.stacks)
				return DotResult.success(existing)
			DotEffectDef.Stacking.EXTEND:
				existing.extend(_tick)
				applied.emit(entity, id, source, existing.stacks)
				return DotResult.success(existing)
			DotEffectDef.Stacking.STACK:
				if not rules.allow_stacking:
					existing.refresh(_tick)
					applied.emit(entity, id, source, existing.stacks)
					return DotResult.success(existing)
				if existing.stacks >= def.max_stacks:
					existing.refresh(_tick)
					applied.emit(entity, id, source, existing.stacks)
					return DotResult.success(existing)
				existing.stacks += 1
				existing.refresh(_tick)
				state.recompute()
				applied.emit(entity, id, source, existing.stacks)
				return DotResult.success(existing)

	if state.count() >= rules.max_per_entity:
		return DotResult.fail(
			DotError.CODE_QUOTA,
			(
				"Entity %d already carries %d effects. An effect applied by a weapon "
				+ "is one applied as fast as that weapon fires."
			) % [entity, state.count()]
		)

	var inst := DotEffectInstance.make(def, _tick, source)
	state.instances.append(inst)
	state.recompute()
	applied.emit(entity, id, source, inst.stacks)
	return DotResult.success(inst)


## Take one off. [param source] of -1 removes every instance of it.
func remove(id: StringName, entity: int, source: int = -1) -> DotResult:
	var state: DotEffectState = _states.get(entity, null)
	if state == null:
		return DotResult.fail(DotError.CODE_INVALID, "Entity %d has none." % entity)

	var taken := 0
	for i in range(state.instances.size() - 1, -1, -1):
		var inst := state.instances[i]
		if inst.id() != id:
			continue
		if source >= 0 and inst.source != source:
			continue
		state.instances.remove_at(i)
		taken += 1

	if taken == 0:
		return DotResult.fail(
			DotError.CODE_STATE, "Entity %d does not have '%s'." % [entity, id]
		)

	state.recompute()
	removed.emit(entity, id, &"removed")
	return DotResult.success(taken)


## Take off everything with a tag. What a cleanse does.
func remove_tagged(entity: int, tag: String) -> int:
	var state: DotEffectState = _states.get(entity, null)
	if state == null:
		return 0
	return _remove_tagged(state, tag, &"cured")


func _remove_tagged(state: DotEffectState, tag: String, reason: StringName) -> int:
	var taken := 0
	for i in range(state.instances.size() - 1, -1, -1):
		var inst := state.instances[i]
		if inst.def == null or not inst.def.has_tag(tag):
			continue
		var id := inst.id()
		state.instances.remove_at(i)
		taken += 1
		removed.emit(state.entity, id, reason)
	if taken > 0:
		state.recompute()
	return taken


## Everything an entity has. Created on demand, so a caller never gets a null.
func state_of(entity: int) -> DotEffectState:
	var state: DotEffectState = _states.get(entity, null)
	if state == null:
		state = DotEffectState.new(entity)
		_states[entity] = state
	return state


func has(entity: int, id: StringName) -> bool:
	var state: DotEffectState = _states.get(entity, null)
	return state != null and state.has(id)


## Forget an entity entirely. What a game calls on disconnect.
func forget(entity: int) -> void:
	_states.erase(entity)
	_downed.erase(entity)
	_temp.erase(entity)
	_temp_at.erase(entity)


# --- The aggregate, for a game to ask -------------------------------------

func damage_taken_scale(entity: int) -> float:
	var state: DotEffectState = _states.get(entity, null)
	return state.damage_taken_scale() if state != null else 1.0


func damage_dealt_scale(entity: int) -> float:
	var state: DotEffectState = _states.get(entity, null)
	return state.damage_dealt_scale() if state != null else 1.0


func move_speed_scale(entity: int) -> float:
	var state: DotEffectState = _states.get(entity, null)
	return state.move_speed_scale() if state != null else 1.0


func is_invulnerable(entity: int) -> bool:
	var state: DotEffectState = _states.get(entity, null)
	return state != null and state.is_invulnerable()


func may_capture(entity: int) -> bool:
	var state: DotEffectState = _states.get(entity, null)
	if state != null and not state.may_capture():
		return false
	return not is_down(entity)


func may_attack(entity: int) -> bool:
	var state: DotEffectState = _states.get(entity, null)
	if state != null and not state.may_attack():
		return false
	return not is_down(entity)


func may_move(entity: int) -> bool:
	var state: DotEffectState = _states.get(entity, null)
	if state != null and not state.may_move():
		return false
	return not is_down(entity)


## [b]The three below are on the state and were once only on the state.[/b] A game holds
## a manager, not a [DotEffectState], so an aggregate with no facade here is one that is
## recomputed on every mutation and asked for by nobody — and the asymmetry is worse than
## the absence: somebody who wires [method may_move] from the manager and then looks for
## [method may_jump] beside it concludes this addon has no such concept, when the field,
## the aggregation and the wire format have all been carrying it the whole time.
func may_jump(entity: int) -> bool:
	var state: DotEffectState = _states.get(entity, null)
	if state != null and not state.may_jump():
		return false
	return not is_down(entity)


func jump_scale(entity: int) -> float:
	var state: DotEffectState = _states.get(entity, null)
	return state.jump_scale() if state != null else 1.0


func fire_rate_scale(entity: int) -> float:
	var state: DotEffectState = _states.get(entity, null)
	return state.fire_rate_scale() if state != null else 1.0


## The one call a damage resolver wants: how much of this actually lands.
##
## Pointed at [member DotDamageResolver.adjust] in every game here, which is why it
## takes both ends — an attacker's crit and a victim's resistance are one number to
## the thing applying it, and asking for them separately is two chances to forget one.
func scale_damage(amount: float, attacker: int, victim: int) -> float:
	if is_invulnerable(victim):
		return 0.0
	return amount * damage_dealt_scale(attacker) * damage_taken_scale(victim)


# --- Downed ------------------------------------------------------------------

## The state of an entity's incapacitation, created on demand.
func downed_state(entity: int) -> DotDowned:
	var d: DotDowned = _downed.get(entity, null)
	if d == null:
		d = DotDowned.new(entity)
		_downed[entity] = d
	return d


func is_down(entity: int) -> bool:
	var d: DotDowned = _downed.get(entity, null)
	return d != null and d.is_down()


## An entity has reached zero health. Answers what should happen to it.
##
## [b]This is the whole of the downed decision and it belongs in one place.[/b] A game
## that asks "am I in a mode with incapacitation" at every damage site has as many
## copies of the rule as it has damage sites, and the copies drift.
##
## Returns a [DotResult] whose value is [code]&"down"[/code] or [code]&"dead"[/code].
func report_zero_health(entity: int, tick: int = -1) -> DotResult:
	var at := tick if tick >= 0 else _tick
	if not rules.downed_enabled:
		return DotResult.success(&"dead")

	var d := downed_state(entity)
	if d.is_down():
		# Already down and hit again: that is death, not a second incapacitation.
		return _kill(d, &"executed")

	if d.is_last_life(rules):
		return _kill(d, &"final")

	d.state = DotDowned.State.DOWN
	d.health = rules.downed_health
	d.progress = 0.0
	d.reviver = 0
	d.incaps += 1
	d.down_at = at
	downed.emit(entity, d.incaps)
	return DotResult.success(&"down")


func _kill(d: DotDowned, reason: StringName) -> DotResult:
	d.state = DotDowned.State.DEAD
	d.health = 0.0
	d.reviver = 0
	d.progress = 0.0
	died.emit(d.entity, reason)
	return DotResult.success(&"dead")


## Start picking somebody up.
func begin_revive(entity: int, by: int) -> DotResult:
	if not authoritative:
		return DotResult.fail(DotError.CODE_STATE, "A mirror does not revive anybody.")
	var d: DotDowned = _downed.get(entity, null)
	if d == null or not d.is_down():
		return DotResult.fail(
			DotError.CODE_STATE, "Entity %d is not down." % entity
		)
	if by == entity:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "Nobody picks themselves up."
		)
	if is_down(by):
		return DotResult.fail(
			DotError.CODE_STATE, "Entity %d is down and cannot revive anybody." % by
		)
	if allies_fn.is_valid() and not bool(allies_fn.call(by, entity)):
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "Entity %d is not on that side." % by
		)
	var near := _within_revive_range(by, entity)
	if not near.ok:
		return near

	if d.state == DotDowned.State.REVIVING and d.reviver == by:
		return DotResult.success(null)

	d.state = DotDowned.State.REVIVING
	d.reviver = by
	d.revivers = 1
	revive_started.emit(entity, by)
	return DotResult.success(null)


func cancel_revive(entity: int, reason: StringName = &"cancelled") -> void:
	var d: DotDowned = _downed.get(entity, null)
	if d == null or d.state != DotDowned.State.REVIVING:
		return
	d.state = DotDowned.State.DOWN
	d.reviver = 0
	# The progress is deliberately thrown away. Keeping it makes a revive something two
	# players can chip at from cover, which removes the whole reason it is a decision.
	d.progress = 0.0
	revive_stopped.emit(entity, reason)


## Bring somebody back from dead. A defibrillator, a respawn closet, an admin.
func defibrillate(entity: int, by: int = 0) -> DotResult:
	var d: DotDowned = _downed.get(entity, null)
	if d == null or d.state != DotDowned.State.DEAD:
		return DotResult.fail(DotError.CODE_STATE, "Entity %d is not dead." % entity)
	if rules.downed_defib_health <= 0.0:
		return DotResult.fail(
			DotError.CODE_UNSUPPORTED, "This game has no revive-from-dead."
		)
	d.state = DotDowned.State.UP
	d.health = 0.0
	d.progress = 0.0
	d.reviver = 0
	revived.emit(entity, by, rules.downed_defib_health)
	return DotResult.success(rules.downed_defib_health)


## Put somebody back on their feet without any of the above. A round reset.
func stand_up(entity: int, reset_incaps: bool = false) -> void:
	var d: DotDowned = _downed.get(entity, null)
	if d == null:
		return
	d.state = DotDowned.State.UP
	d.health = 0.0
	d.progress = 0.0
	d.reviver = 0
	if reset_incaps:
		d.incaps = 0


func _within_revive_range(by: int, entity: int) -> DotResult:
	if rules.downed_revive_radius <= 0.0 or not position_fn.is_valid():
		return DotResult.success(null)
	var a: Vector3 = position_fn.call(by)
	var b: Vector3 = position_fn.call(entity)
	var d := a.distance_to(b)
	if d > rules.downed_revive_radius:
		return DotResult.fail(
			DotError.CODE_STATE,
			"Too far to revive (%.1f > %.1f)." % [d, rules.downed_revive_radius]
		)
	return DotResult.success(null)


# --- Temporary health --------------------------------------------------------

## Give an entity health above its maximum. Overheal, pills, adrenaline.
##
## Tracked here rather than in [DotHealth] because it is a *decaying* number with a
## grace period and a source, and because a game with no dot-combat in it still has
## pills. The game keeps the real value; this says how much of it is temporary and
## emits [signal temp_decayed] as it goes.
func grant_temp(entity: int, amount: float) -> float:
	var have := float(_temp.get(entity, 0.0)) + maxf(amount, 0.0)
	_temp[entity] = have
	_temp_at[entity] = _tick
	return have


func temp_health(entity: int) -> float:
	return float(_temp.get(entity, 0.0))


func clear_temp(entity: int) -> void:
	_temp.erase(entity)
	_temp_at.erase(entity)


# --- The tick ----------------------------------------------------------------

## One tick. The only thing that expires an effect or moves a revive.
func advance(tick: int) -> void:
	_tick = tick
	if not authoritative:
		return

	_advance_effects(tick)
	_advance_downed(tick)
	_advance_temp(tick)


func _advance_effects(tick: int) -> void:
	for entity: Variant in _states.keys():
		var state: DotEffectState = _states[entity]
		if state.is_empty():
			continue

		var dirty := false
		for i in range(state.instances.size() - 1, -1, -1):
			var inst := state.instances[i]
			if inst.is_expired(tick):
				var id := inst.id()
				state.instances.remove_at(i)
				dirty = true
				removed.emit(int(entity), id, &"expired")
				continue

			var def := inst.def
			if def == null or not def.is_periodic():
				continue
			if tick < inst.next_periodic:
				continue
			inst.next_periodic = tick + maxi(def.tick_interval, 1)

			var n := float(maxi(inst.stacks, 1))
			if def.damage_per_tick > 0.0:
				damaged.emit(
					int(entity), def.damage_per_tick * n, def.damage_type, inst.source
				)
			if def.heal_per_tick > 0.0:
				healed.emit(
					int(entity), def.heal_per_tick * n, def.heal_overheals, inst.source
				)

		if dirty:
			state.recompute()


func _advance_downed(tick: int) -> void:
	if not rules.downed_enabled:
		return

	for entity: Variant in _downed.keys():
		var d: DotDowned = _downed[entity]
		if not d.is_down():
			continue

		if d.state == DotDowned.State.REVIVING:
			# Re-tested every tick rather than trusted: a reviver who died, walked away
			# or went down themselves must stop reviving, and a game that only calls
			# cancel_revive() from its death handler has one path to get wrong.
			var still := _within_revive_range(d.reviver, int(entity))
			var reviver_down := is_down(d.reviver)
			if not still.ok or reviver_down:
				cancel_revive(int(entity), &"interrupted" if reviver_down else &"moved")
			else:
				var rate := float(d.revivers) if rules.downed_revive_scales else 1.0
				d.progress += rate
				if d.progress >= float(rules.downed_revive_ticks):
					var by := d.reviver
					d.state = DotDowned.State.UP
					d.progress = 0.0
					d.reviver = 0
					d.health = 0.0
					revived.emit(int(entity), by, rules.downed_revive_health)
					continue

		d.health -= rules.downed_bleed_per_tick
		if d.health <= 0.0:
			var _res := _kill(d, &"bled_out")

	var _unused := tick


func _advance_temp(tick: int) -> void:
	if rules.temp_decay_per_tick <= 0.0:
		return
	for entity: Variant in _temp.keys():
		var have := float(_temp[entity])
		if have <= 0.0:
			continue
		if tick - int(_temp_at.get(entity, 0)) < rules.temp_grace_ticks:
			continue
		var take := minf(rules.temp_decay_per_tick, have)
		_temp[entity] = have - take
		temp_decayed.emit(int(entity), take)


# --- Round and death ----------------------------------------------------------

## An entity died. Clears what says it should be cleared.
func on_death(entity: int) -> void:
	var state: DotEffectState = _states.get(entity, null)
	if state != null:
		for i in range(state.instances.size() - 1, -1, -1):
			var inst := state.instances[i]
			if inst.def != null and not inst.def.clear_on_death:
				continue
			var id := inst.id()
			state.instances.remove_at(i)
			removed.emit(entity, id, &"died")
		state.recompute()
	clear_temp(entity)

	# Created on demand, like every other accessor here. Reading the dictionary
	# directly meant an entity that had never been down was never recorded as dead —
	# so a defibrillator could not bring back the one player who had gone straight
	# from full health to a rocket, which is most of them. Nothing errored: "not dead"
	# is a legitimate thing for an entity to be.
	if rules.downed_enabled:
		var d := downed_state(entity)
		d.state = DotDowned.State.DEAD
		d.reviver = 0
		d.progress = 0.0


## A round ended or began. Clears what says it should be cleared, everywhere.
func on_round_reset() -> void:
	for entity: Variant in _states.keys():
		var state: DotEffectState = _states[entity]
		for i in range(state.instances.size() - 1, -1, -1):
			var inst := state.instances[i]
			if inst.def != null and not inst.def.clear_on_round:
				continue
			var id := inst.id()
			state.instances.remove_at(i)
			removed.emit(int(entity), id, &"round")
		state.recompute()
	for entity: Variant in _downed.keys():
		var d: DotDowned = _downed[entity]
		d.state = DotDowned.State.UP
		d.health = 0.0
		d.progress = 0.0
		d.reviver = 0
		d.incaps = 0
	_temp.clear()
	_temp_at.clear()


# --- The wire ------------------------------------------------------------------

## One entity's whole status, for a client to draw.
##
## Per entity rather than all at once: effects are the one thing here that is genuinely
## per-player and mostly private — an enemy's überCharge is public and their afterburn
## is not — so who gets which is the game's decision, and a manager that only offered
## "everything" would have made it.
func to_wire(entity: int) -> Dictionary:
	var state: DotEffectState = _states.get(entity, null)
	var d: DotDowned = _downed.get(entity, null)
	return {
		"e": entity,
		"fx": state.to_wire() if state != null else [],
		"dn": d.to_wire() if d != null else {},
		"tp": float(_temp.get(entity, 0.0)),
	}


func apply_wire(w: Dictionary) -> void:
	var entity := int(w.get("e", 0))
	if entity == 0:
		return

	var state := state_of(entity)
	state.instances.clear()
	for row: Variant in (w.get("fx", []) as Array):
		var entry := row as Dictionary
		var def: DotEffectDef = _defs.get(StringName(str(entry.get("i", ""))), null)
		if def == null:
			# An effect the client does not have a definition for. Skipping it is right
			# and saying so is why this is a warning: the alternative is a HUD quietly
			# missing an icon on a build that is one addon out of date.
			DotLog.warn(
				"effects",
				"No definition for effect '%s' sent for entity %d."
					% [str(entry.get("i", "")), entity]
			)
			continue
		var inst := DotEffectInstance.new()
		inst.def = def
		inst.source = int(entry.get("s", 0))
		inst.expires_at = int(entry.get("e", -1))
		inst.stacks = int(entry.get("n", 1))
		inst.applied_at = int(entry.get("a", 0))
		state.instances.append(inst)
	state.recompute()

	var packed: Dictionary = w.get("dn", {})
	if not packed.is_empty():
		downed_state(entity).apply_wire(packed)

	_temp[entity] = float(w.get("tp", 0.0))


func describe() -> Dictionary:
	return {
		"authoritative": authoritative,
		"definitions": _defs.size(),
		"entities": _states.size(),
		"downed": _downed.size(),
		"tick": _tick,
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append(
		"DotEffectManager %s tick=%d defs=%d entities=%d"
			% [
				"authoritative" if authoritative else "mirroring",
				_tick, _defs.size(), _states.size(),
			]
	)
	var ids: Array = _states.keys()
	ids.sort()
	for entity: Variant in ids:
		var state: DotEffectState = _states[entity]
		if state.is_empty():
			continue
		for line in state.describe_lines():
			out.append("  " + line)
	var down_ids: Array = _downed.keys()
	down_ids.sort()
	for entity: Variant in down_ids:
		var d: DotDowned = _downed[entity]
		if d.state == DotDowned.State.UP:
			continue
		out.append(
			"  entity %d %s %.0f/%.0f incaps=%d"
				% [
					int(entity), DotDowned.State.keys()[d.state],
					d.health, rules.downed_health, d.incaps,
				]
		)
	return out
