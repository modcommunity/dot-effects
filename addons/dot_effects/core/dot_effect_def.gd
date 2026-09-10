@tool
class_name DotEffectDef
extends Resource

## A status effect as a document: burning, healed, invulnerable, slowed, marked.
##
## Same rule as every other catalogue in this family — it is data, it validates before
## anything is built from it, and nothing in it names a scene, a particle or a sound.
## A server can therefore check a game's whole effect table at boot, headless, which is
## the only moment anybody is watching.
##
## [b]This is one document because the alternative is one class per effect.[/b] Team
## Fortress 2 has burning, bleeding, jarate, milk, crit-boost, mini-crit, überCharge,
## overheal, marked-for-death and stun; Left 4 Dead 2 has adrenaline, pills, incendiary,
## bile and being incapacitated. Nineteen of those twenty-one are the same six fields
## with different numbers — a duration, a periodic amount, a damage multiplier in each
## direction, a movement multiplier and a flag — and writing them as classes is writing
## the same file twenty times and then having them disagree.
##
## [b]It never touches a health value.[/b] A periodic effect emits an amount and the
## game applies it to whatever it keeps health in — [DotHealth] in every game here.
## dot-effects does not import dot-combat, because a slow, a stun and a speed boost are
## the same rule in a game with no damage in it at all.

## What a second application of the same effect does.
enum Stacking {
	REFRESH,  ## Put the duration back to full. Burning, in every game that has it.
	EXTEND,   ## Add to what is left, up to [member max_duration_ticks].
	STACK,    ## Another instance beside it. Bleeds from two players.
	IGNORE,   ## The first one wins and the second is refused.
}

@export var id: StringName = &""

@export var display_name: String = ""

## What a HUD draws beside a name. Two or three characters.
@export var label: String = ""

## Free-form labels this effect answers to.
##
## The whole of the interaction system, and deliberately no more than that: an effect
## that [member cures] "fire" cures every effect tagged fire without naming one, and an
## effect that grants immunity to "debuff" refuses every one of them. Naming ids
## directly makes a table where adding a nineteenth effect means editing eighteen.
@export var tags: PackedStringArray = PackedStringArray()

@export_group("Duration")

## How long it lasts, in ticks. Zero means until something removes it.
##
## Ticks, like everything else in this family. An effect measured in seconds on a
## server at 64 and a client at 128 is two different effects.
@export_range(0, 10000000, 1) var duration_ticks: int = 640

## The ceiling for [constant Stacking.EXTEND]. Zero means no ceiling.
@export_range(0, 10000000, 1) var max_duration_ticks: int = 0

@export var stacking: Stacking = Stacking.REFRESH

## How many instances may exist at once under [constant Stacking.STACK].
@export_range(1, 64, 1) var max_stacks: int = 1

## Whether two applications from different sources are separate instances.
##
## On for a bleed, because being cut by two people is worse than being cut by one; off
## for burning, because being set alight twice is being alight.
@export var per_source: bool = false

@export_group("Periodic")

## Ticks between periodic applications. Zero means every tick.
##
## Team Fortress 2's afterburn is every half second; a healing beam is continuous. The
## interval exists because "3 damage every 32 ticks" and "0.09 damage every tick" are
## different games: the first can be out-healed in bursts and the second cannot.
@export_range(0, 100000, 1) var tick_interval: int = 32

## Damage per application. Reported, never applied — see the class note.
@export_range(0.0, 10000.0, 0.1, "or_greater") var damage_per_tick: float = 0.0

## Which [DotDamageType] id the periodic damage is. A string, because dot-combat is not
## a dependency and an id is what both ends already agree on.
@export var damage_type: StringName = &""

## Healing per application.
@export_range(0.0, 10000.0, 0.1, "or_greater") var heal_per_tick: float = 0.0

## Whether periodic healing may push a target above its normal maximum.
@export var heal_overheals: bool = false

@export_group("Modifiers")

## Multiplies damage this entity RECEIVES. 0 is immune, 2 is double.
@export_range(0.0, 100.0, 0.01, "or_greater") var damage_taken_scale: float = 1.0

## Multiplies damage this entity DEALS. Team Fortress 2's crit is 3, its mini-crit
## 1.35.
@export_range(0.0, 100.0, 0.01, "or_greater") var damage_dealt_scale: float = 1.0

## Damage this entity deals ignores distance falloff.
##
## Separate from the multiplier because a crit is both and a mini-crit is only this at
## range. A game with no falloff reads it and does nothing, which is correct.
@export var ignores_falloff: bool = false

## Multiplies movement speed.
@export_range(0.0, 100.0, 0.01, "or_greater") var move_speed_scale: float = 1.0

## Multiplies jump height or thrust.
@export_range(0.0, 100.0, 0.01, "or_greater") var jump_scale: float = 1.0

## Multiplies the rate of fire.
@export_range(0.0, 100.0, 0.01, "or_greater") var fire_rate_scale: float = 1.0

## Refuses all damage while it lasts. überCharge.
##
## A flag rather than [member damage_taken_scale] = 0, because "immune" and "takes zero
## damage" differ where it matters: a game shows one and not the other, an objective
## may refuse a capture from one, and a resolver that multiplies by zero still records
## a hit.
@export var invulnerable: bool = false

@export_group("Prevents")

## Cannot attack. A stun, a taunt, being grabbed.
@export var no_attack: bool = false

## Cannot move under their own power.
@export var no_move: bool = false

@export var no_jump: bool = false

## Cannot capture an objective. Feeds [DotObjectivePresence.may_capture_fn] directly,
## which is why that seam exists as a callable and not as a boolean on a player.
@export var no_capture: bool = false

@export_group("Interaction")

## Tags this removes when it is applied. Water cures fire.
@export var cures: PackedStringArray = PackedStringArray()

## Tags that may not be applied while this is active.
##
## überCharge is immune to "debuff" and the effect table says so once, rather than
## every debuff naming über.
@export var immune_to: PackedStringArray = PackedStringArray()

## Effects removed when this entity dies. Off for anything that should survive, which
## in practice is nothing — the default is here so a game can say otherwise.
@export var clear_on_death: bool = true

## Removed when a round ends.
@export var clear_on_round: bool = true


static func make(p_id: StringName, p_duration: int) -> DotEffectDef:
	var d := DotEffectDef.new()
	d.id = p_id
	d.display_name = String(p_id).capitalize()
	d.duration_ticks = p_duration
	return d


## Burning: periodic damage, refreshed rather than stacked, cured by anything wet.
static func burning(p_id: StringName, per_tick: float, ticks: int) -> DotEffectDef:
	var d := make(p_id, ticks)
	d.tags = PackedStringArray(["fire", "debuff"])
	d.damage_per_tick = per_tick
	d.damage_type = &"fire"
	d.stacking = Stacking.REFRESH
	return d


## A damage multiplier for what this entity deals. Crit, mini-crit, a damage powerup.
static func damage_buff(p_id: StringName, scale: float, ticks: int) -> DotEffectDef:
	var d := make(p_id, ticks)
	d.tags = PackedStringArray(["buff"])
	d.damage_dealt_scale = scale
	d.ignores_falloff = scale >= 2.0
	return d


## Invulnerability, with the immunity that has to come with it.
static func invulnerability(p_id: StringName, ticks: int) -> DotEffectDef:
	var d := make(p_id, ticks)
	d.tags = PackedStringArray(["buff"])
	d.invulnerable = true
	d.immune_to = PackedStringArray(["debuff"])
	d.no_capture = true
	return d


## A movement multiplier. Adrenaline, a slow, concrete boots.
static func speed(p_id: StringName, scale: float, ticks: int) -> DotEffectDef:
	var d := make(p_id, ticks)
	d.tags = PackedStringArray(["buff" if scale > 1.0 else "debuff"])
	d.move_speed_scale = scale
	return d


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func is_periodic() -> bool:
	return damage_per_tick > 0.0 or heal_per_tick > 0.0


func validate() -> DotResult:
	if String(id).strip_edges() == "":
		return DotResult.fail(DotError.CODE_INVALID, "An effect needs an id.")

	if duration_ticks == 0 and is_periodic() and tick_interval == 0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"Effect '%s' is permanent, periodic and has no interval, so it applies "
				+ "its amount every tick for ever. That is not a status effect, it is "
				+ "a leak with a name."
			) % id
		)

	if max_duration_ticks > 0 and max_duration_ticks < duration_ticks:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"Effect '%s' has a maximum duration (%d) below its own duration (%d), "
				+ "so one application already exceeds the cap."
			) % [id, max_duration_ticks, duration_ticks]
		)

	if stacking != Stacking.STACK and max_stacks > 1:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"Effect '%s' allows %d stacks and does not stack. One of the two is a "
				+ "typo, and the field that does nothing is the one nobody notices."
			) % [id, max_stacks]
		)

	for tag in cures:
		if tags.has(tag):
			return DotResult.fail(
				DotError.CODE_INVALID,
				(
					"Effect '%s' cures '%s' and is tagged '%s', so applying it removes "
					+ "it."
				) % [id, tag, tag]
			)

	return DotResult.success(null)


func describe() -> Dictionary:
	return {
		"id": String(id),
		"name": display_name,
		"tags": Array(tags),
		"duration": duration_ticks,
		"stacking": Stacking.keys()[stacking],
		"periodic": is_periodic(),
	}
