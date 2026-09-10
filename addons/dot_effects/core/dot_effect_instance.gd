class_name DotEffectInstance
extends RefCounted

## One application of one effect to one entity.
##
## Separate from [DotEffectDef] for the reason every catalogue in this family separates
## them: the definition is shared by every application and mutating it to store "when
## does this one expire" would make two burning players one burning player. This family
## has shipped that aliasing bug five times — a scoped leaderboard and its template
## ending up one object, a zone payload shared between two zones — and it is always the
## same fix.

var def: DotEffectDef = null

## Who applied it. Zero means nobody in particular: a map hazard, a round rule.
var source: int = 0

## The tick it stops on. [code]-1[/code] means it does not expire by itself.
var expires_at: int = -1

## The next tick a periodic effect applies on.
var next_periodic: int = 0

## How many are folded into this one under [constant DotEffectDef.Stacking.STACK].
var stacks: int = 1

## The tick it was applied on, for a HUD that wants to draw elapsed rather than left.
var applied_at: int = 0


static func make(
	p_def: DotEffectDef, tick: int, p_source: int = 0
) -> DotEffectInstance:
	var inst := DotEffectInstance.new()
	inst.def = p_def
	inst.source = p_source
	inst.applied_at = tick
	inst.expires_at = -1 if p_def.duration_ticks <= 0 else tick + p_def.duration_ticks
	inst.next_periodic = tick + maxi(p_def.tick_interval, 1)
	return inst


func id() -> StringName:
	return def.id if def != null else &""


func is_expired(tick: int) -> bool:
	return expires_at >= 0 and tick >= expires_at


## Ticks left, or -1 for one that does not expire.
func remaining(tick: int) -> int:
	if expires_at < 0:
		return -1
	return maxi(expires_at - tick, 0)


## 0..1 of the way through. 0 for one that does not expire, which a HUD draws as a
## full bar rather than an empty one — the opposite convention loses überCharge.
func elapsed_fraction(tick: int) -> float:
	if expires_at < 0 or def == null or def.duration_ticks <= 0:
		return 0.0
	return clampf(
		float(tick - applied_at) / float(def.duration_ticks), 0.0, 1.0
	)


## Put the clock back to full.
func refresh(tick: int) -> void:
	applied_at = tick
	if def != null and def.duration_ticks > 0:
		expires_at = tick + def.duration_ticks


## Add to what is left, up to the definition's ceiling.
func extend(tick: int) -> void:
	if def == null or def.duration_ticks <= 0:
		return
	if expires_at < 0:
		expires_at = tick + def.duration_ticks
		return
	expires_at += def.duration_ticks
	if def.max_duration_ticks > 0:
		expires_at = mini(expires_at, tick + def.max_duration_ticks)


func describe() -> Dictionary:
	return {
		"id": String(id()),
		"source": source,
		"expires_at": expires_at,
		"stacks": stacks,
	}


func to_wire() -> Dictionary:
	return {
		"i": String(id()),
		"s": source,
		"e": expires_at,
		"n": stacks,
		"a": applied_at,
	}


func _to_string() -> String:
	return "DotEffectInstance(%s x%d until %d)" % [id(), stacks, expires_at]
