@tool
class_name DotEffectRules
extends DotConfig

## Every policy about effects in general, and the whole of the downed/revive half.
##
## Layered like every [DotConfig] here. The downed numbers come from the co-operative
## survival shooters, where being incapacitated rather than killed is the central
## mechanic and the values are twenty years of playtesting away from obvious.

@export_group("Limits")

## Most effects one entity may carry at once. A new one past this is refused.
##
## Not a performance number — it is a griefing one. An effect applied by a weapon is an
## effect applied as fast as that weapon fires, and an unbounded list is a server that
## spends its tick iterating one player's status.
@export_range(1, 256, 1) var max_per_entity: int = 24

## Turn the whole stacking half off. Everything becomes REFRESH.
@export var allow_stacking: bool = true

@export_group("Downed", "downed_")

## Whether an entity at zero health goes down instead of dying.
##
## Off by default, because a deathmatch where nobody dies is a very confusing bug and
## this is a mode's decision rather than an addon's.
@export var downed_enabled: bool = false

## The pool a downed entity bleeds through. The co-operative shooters' 300.
@export_range(1.0, 100000.0, 1.0, "or_greater") var downed_health: float = 300.0

## How fast it bleeds, per tick. 300 over about 90 seconds at 64 Hz.
@export_range(0.0, 1000.0, 0.001, "or_greater") var downed_bleed_per_tick: float = 0.052

## Ticks of uninterrupted reviving. The co-operative shooters' five seconds.
@export_range(1, 100000, 1) var downed_revive_ticks: int = 320

## Health an entity comes back with.
@export_range(1.0, 100000.0, 1.0, "or_greater") var downed_revive_health: float = 30.0

## How close a reviver must be. Zero means do not check, for a game with no positions.
@export_range(0.0, 100.0, 0.1, "or_greater") var downed_revive_radius: float = 2.0

## More than one reviver is faster.
##
## Off, as in the co-operative shooters: a second player standing there is a second
## player not shooting, and making it faster removes the decision. On, they share the
## work.
@export var downed_revive_scales: bool = false

## How many times an entity may be revived before the next one kills them.
##
## Two, the co-operative shooters' number: the third time down is the last, and the two
## before it are what makes the second one frightening. Zero means unlimited.
@export_range(0, 64, 1) var downed_max_incaps: int = 2

## Health a defibrillator-style revive from dead comes back with. Zero disables it.
@export_range(0.0, 100000.0, 1.0, "or_greater") var downed_defib_health: float = 50.0

@export_group("Temporary health", "temp_")

## Health above the normal maximum decays at this rate per tick.
##
## A team shooter's overheal and a co-operative shooter's pills are the same mechanic: a
## number that is real while you have it and cannot be kept. Zero means it never decays, which
## is what a game with a hard overheal cap and no decay wants.
@export_range(0.0, 1000.0, 0.0001, "or_greater") var temp_decay_per_tick: float = 0.1

## Ticks before decay starts after the last top-up.
@export_range(0, 100000, 1) var temp_grace_ticks: int = 0


func env_prefix() -> String:
	return "DOT_EFFECTS_"


func cli_prefix() -> String:
	return "effects-"


func validate() -> DotResult:
	if downed_enabled and downed_bleed_per_tick <= 0.0 and downed_health > 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"Downed entities never bleed out, so a player nobody revives is down "
				+ "for the rest of the round with nothing saying why. Set a bleed rate "
				+ "or turn downed off."
			)
		)
	return DotResult.success(null)


## How long a bleed-out takes from full, in ticks. What a HUD needs to draw the bar.
func bleed_out_ticks() -> int:
	if downed_bleed_per_tick <= 0.0:
		return -1
	return int(ceilf(downed_health / downed_bleed_per_tick))
