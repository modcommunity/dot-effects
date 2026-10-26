class_name DotStackScale
extends RefCounted

## Pure arithmetic for values that move with a stack count (a debuff, a Hard Box, a heat level).

## Never fully invisible, whatever the caller asks for: a mob that cannot be seen cannot be fought.
const ALPHA_FLOOR := 0.05


## [param base] plus [param per_stack] for each stack, capped at [param cap]. Negative stacks count as 0.
static func ramp(base: float, per_stack: float, cap: float, stacks: int) -> float:
	return minf(base + per_stack * float(maxi(stacks, 0)), cap)


## Alpha 1 (solid) falling [param step] per stack down to [param min_alpha], never below [constant ALPHA_FLOOR].
static func fade_alpha(stacks: int, step: float, min_alpha: float) -> float:
	var floor_alpha := clampf(min_alpha, ALPHA_FLOOR, 1.0)
	return clampf(1.0 - float(maxi(stacks, 0)) * maxf(step, 0.0), floor_alpha, 1.0)
