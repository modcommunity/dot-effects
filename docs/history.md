# dot-effects history

Bugs found by running it, kept because each could come back. The live rule from each is in [design.md](design.md).

## `on_death` skipped anyone never down

`on_death()` read the downed dictionary directly instead of creating on demand, so an entity that had never been down was never recorded as dead, and a defibrillator could not bring back the one player who went straight from full health to a rocket, which is most of them. Every other accessor in the class created on demand; this one did not, and nothing errored, because "not dead" is a legitimate thing for an entity to be.

## Three aggregates had no facade on the manager

`DotEffectState` computed `jump_scale`, `fire_rate_scale` and `may_jump` on every mutation alongside the five that `DotEffectManager` forwarded, and a game holds a manager, never a state, so those three were reachable only through `state_of()`. `no_jump` was an exported field of `DotEffectDef`, aggregated, and on the wire; the one thing missing was the question.

The asymmetry is worse than the absence would have been. Somebody who wires `may_move` off the manager and then looks for `may_jump` beside it finds nothing and concludes this addon has no such concept. That is how a documented field ends up read by nobody without anything ever failing.

Found by the family's mechanical detector run over methods rather than settings ([detectors](../../../docs/detectors.md)), and it is a variant worth naming: not "declared and called by nothing", but declared on the inner object and not on the one anybody holds. `ignores_falloff` is the same shape and is still open (see [CLAUDE.md](../CLAUDE.md#open)).
