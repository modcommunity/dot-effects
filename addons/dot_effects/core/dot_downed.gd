class_name DotDowned
extends RefCounted

## One entity, down rather than dead, and how they get back up.
##
## Left 4 Dead 2's incapacitation, which is the mechanic that turns a shooter into a
## co-operative game: a player at zero health becomes a **decision** for their team
## rather than a respawn timer, and the fifteen seconds somebody spends picking them up
## is fifteen seconds nobody is shooting.
##
## [b]The reviving is deliberately not an effect.[/b] Every other status here is a
## multiplier and a duration; this one is a two-party interaction with a distance test,
## an interruption rule and a count that persists across the whole round. Squeezing it
## into [DotEffectDef] would need four fields nothing else uses, and the fields nothing
## else uses are the ones that are silently wrong.

enum State {
	UP,       ## Fine.
	DOWN,     ## Bleeding out. Revivable.
	REVIVING, ## Somebody is picking them up.
	DEAD,     ## Out. Only a defibrillator-style revive brings them back.
}

var entity: int = 0

var state: State = State.UP

## What is left of the bleed-out pool.
var health: float = 0.0

## Who is picking them up. Zero when nobody.
var reviver: int = 0

## How many revivers are on it, when the rules say that matters.
var revivers: int = 1

## Ticks of reviving done so far.
var progress: float = 0.0

## How many times this entity has been down this round.
var incaps: int = 0

## The tick they went down on.
var down_at: int = 0


func _init(p_entity: int = 0) -> void:
	entity = p_entity


func is_down() -> bool:
	return state == State.DOWN or state == State.REVIVING


func is_dead() -> bool:
	return state == State.DEAD


## 0..1 of the way through being picked up.
func revive_fraction(rules: DotEffectRules) -> float:
	if state != State.REVIVING:
		return 0.0
	return clampf(progress / float(maxi(rules.downed_revive_ticks, 1)), 0.0, 1.0)


## 0..1 of the bleed-out pool left. What the bar on a downed player shows.
func bleed_fraction(rules: DotEffectRules) -> float:
	if not is_down():
		return 0.0
	return clampf(health / maxf(rules.downed_health, 1.0), 0.0, 1.0)


## Whether being revived again would kill instead.
##
## Public because a HUD has to draw it — the black-and-white screen exists to tell a
## player that the next one is the last one, and a player who cannot see that is one
## who takes the same risk twice.
func is_last_life(rules: DotEffectRules) -> bool:
	if rules.downed_max_incaps <= 0:
		return false
	return incaps >= rules.downed_max_incaps


func describe() -> Dictionary:
	return {
		"entity": entity,
		"state": State.keys()[state],
		"health": health,
		"incaps": incaps,
		"reviver": reviver,
	}


func to_wire() -> Dictionary:
	return {
		"e": entity,
		"s": int(state),
		"h": health,
		"r": reviver,
		"p": progress,
		"n": incaps,
	}


func apply_wire(w: Dictionary) -> void:
	state = int(w.get("s", int(state))) as State
	health = float(w.get("h", health))
	reviver = int(w.get("r", reviver))
	progress = float(w.get("p", progress))
	incaps = int(w.get("n", incaps))


func _to_string() -> String:
	return "DotDowned(%d %s %.0f)" % [entity, State.keys()[state], health]
