# dot-effects

Status effects, incapacitation and temporary health. Burning, crits, invulnerability, slows, stuns and marks as one document rather than one class each; and the co-operative shooters' down-rather-than-dead, with the revive that is a decision. It never touches a health value: it emits `damaged` and the game applies it.

Read the family [CLAUDE.md](../../CLAUDE.md) first.

**The distributable is `addons/dot_effects/`.** It requires [dot-core](../dot-core) and nothing else (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored). It does not import dot-combat.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | changing anything: why one document, why no health, recompute on change, multiplying stacks, flags, tags, downed and revive, mirrors, facades, what is deliberately not here |
| [docs/history.md](docs/history.md) | `on_death` and the never-downed entity, the aggregates with no facade |

## Layout

| Path | What |
| --- | --- |
| `core/dot_effect_def.gd` | `DotEffectDef`: the document (duration, periodic amount, scales, flags, `tags`, `cures`, `immune_to`) and stock constructors |
| `core/dot_effect_instance.gd` | `DotEffectInstance`: one application to one entity |
| `core/dot_effect_state.gd` | `DotEffectState`: everything on one entity and its aggregate (`recompute`) |
| `core/dot_effect_rules.gd` | `DotEffectRules`: limits, temporary health, the downed/revive half; layered `DotConfig` |
| `core/dot_downed.gd` | `DotDowned`: one entity, down rather than dead |
| `core/dot_stack_scale.gd` | `DotStackScale`: `ramp` (base plus a step per stack, capped) and `fade_alpha` (solid down to a visible floor); pure arithmetic a game feeds its own cvars |
| `runtime/dot_effect_manager.gd` | `DotEffectManager`: the one node a game holds; queries, `damaged`, `on_death`, `report_zero_health`, wire form |
| `examples/effects_selftest.tscn` | the suite |

Paths except `examples/` are in `addons/dot_effects/`.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 120 godot --headless --path . res://examples/effects_selftest.tscn`.

## Rules that bite

- Never touch a health value or name a dot-combat class; damage leaves as `damaged(entity, amount, type: StringName, source)`. [design](docs/design.md#it-never-touches-a-health-value)
- A new effect is a `DotEffectDef`, never a class. [design](docs/design.md#why-this-exists)
- The aggregate is recomputed on apply, remove and expiry; never cache it against a deadline. [design](docs/design.md#the-aggregate-is-recomputed-on-change-never-cached-against-a-deadline)
- Scales multiply, stacks included; never add them. [design](docs/design.md#modifiers-multiply-and-stacks-multiply-too)
- Invulnerability is a flag, not a zero multiplier; `no_capture` and `no_attack` stay separate. [design](docs/design.md#invulnerability-is-a-flag-not-a-zero-multiplier)
- `cures` and `immune_to` name tags, never ids; curing runs before the per-entity cap. [design](docs/design.md#interaction-is-by-tag-never-by-id)
- A cancelled revive loses its progress; a revive re-tests its preconditions every tick; downed state is created on demand by every accessor. [design](docs/design.md#downed-and-revived)
- `authoritative = false` refuses `apply()` and makes `advance()` a no-op; the wire form is per entity. [design](docs/design.md#a-mirror-does-not-simulate)
- Every aggregate on `DotEffectState` gets a forwarding method on `DotEffectManager`, and the suite asks through the manager. [design](docs/design.md#every-aggregate-has-a-facade-on-the-manager)

## Open


Deliberately not here: particles, sounds, icons, health, classes, cooldowns, prediction. [design](docs/design.md#deliberately-not-here)
