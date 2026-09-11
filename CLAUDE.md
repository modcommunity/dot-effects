# dot-effects

Status effects, incapacitation and temporary health. Burning, crits, invulnerability,
slows, stuns and marks as **one document rather than one class each**; and Left 4 Dead's
down-rather-than-dead, with the revive that is a decision.

**The distributable is `addons/dot_effects/`.** It requires [dot-core](../dot-core), a
separate repository, and nothing else.

```bash
ln -s ../../dot-core/addons/dot_core addons/dot_core
```

## Why this exists

[dot-combat](../dot-combat) resolves one hit: a trace, a hitbox, a multiplier, a number
subtracted from a `DotHealth`. Everything that happens *over time* to the entity on either
end of that hit had nowhere to live, so every game reinvented it — and there is a lot of
it. Team Fortress 2 alone has burning, bleeding, jarate, milk, crit-boost, mini-crit,
überCharge, overheal, marked-for-death and stun; Left 4 Dead 2 has adrenaline, pills,
incendiary, bile and being incapacitated.

Nineteen of those twenty-one are the **same six fields with different numbers**: a
duration, a periodic amount, a multiplier on damage taken, a multiplier on damage dealt, a
multiplier on movement, and a flag. Writing them as classes is writing the same file
twenty times and then having them disagree — which is this family's most repeated bug in
its most expensive form.

## The one idea: it never touches a health value

A burning entity does not lose health here. `damaged` is emitted with an amount, a type id
and a source, and the **game** applies it to whatever it keeps health in.

That is not squeamishness, it is what makes the addon usable:

- dot-effects does not import dot-combat, so a slow, a stun and a speed boost work in a
  game with no damage system at all — game-hungario, where being eaten is a mass ratio.
- The damage type is a `StringName` rather than a `DotDamageType`, because an id is what
  both ends already agree on and a class reference is a hard dependency.
- A game that wants lag compensation, armour, friendly-fire rules or damage falloff
  applied to an afterburn tick gets all of them for free, because the tick goes through
  the same `DotDamageResolver` as everything else.

The same seam in the other direction: this addon does not know when an entity dies. A game
calls `on_death()`, and `report_zero_health()` answers **"down" or "dead"** so the whole of
that decision lives in one place rather than at every damage site.

## The pieces

| | |
| --- | --- |
| `DotEffectDef` | The document. One resource, six kinds of field, twenty effects. |
| `DotEffectInstance` | One application to one entity. Never the definition. |
| `DotEffectState` | Everything on one entity, and what it adds up to. |
| `DotEffectRules` | Limits, and the whole downed/revive half. Layered `DotConfig`. |
| `DotDowned` | One entity, down rather than dead. |
| `DotEffectManager` | The one node a game holds. |

## Decisions

### 1. The aggregate is recomputed on change, never cached against a deadline

`DotEffectState.recompute()` runs when an effect is applied, removed or expires — not per
tick and never per query. The obvious optimisation is a cache with a validity window, and
this family already paid for that one: `DotNetInterest.relevant_for` cached per peer, an
entity spawned since was in nobody's cached set, and on a host ticking faster than the wall
clock the cache never expired and the entity was **never sent once**. A cached answer that
misses what changed looks exactly like a wrong answer, and you look for it in the producer.

### 2. Modifiers multiply, and stacks multiply too

Two 0.5 slows are 0.25, not 0. An additive scheme reaches zero at two entries and the third
is a movement bug with no visible cause. This is the property that makes the effect table
safe for a game to extend without re-deriving the whole thing.

### 3. Invulnerability is a flag, not a zero multiplier

"Immune" and "takes zero damage" differ where it matters: a game draws one and not the
other, an objective refuses a capture from one (`no_capture`), and a resolver that
multiplies by zero still records a hit and still fires a hit sound.

### 4. `may_block` is not `may_capture`, and the same rule applies here

`DotObjectiveDef` has two questions for a reason and so does this: `no_capture` is separate
from `no_attack`, because Team Fortress 2's invulnerable player may not capture, may not be
hurt, and may absolutely still shoot.

### 5. Interaction is by tag, never by id

An effect that `cures` "fire" cures everything tagged fire. An effect that is `immune_to`
"debuff" refuses every one of them. Naming ids directly produces a table where adding a
nineteenth effect means editing eighteen — and where the one you forget is the bug.

Curing happens **before** the per-entity cap is checked, because an effect that cures fire
and is refused for being the twenty-fifth would leave the fire burning, which is the
opposite of what it was applied for.

### 6. A cancelled revive throws its progress away

Keeping it makes a revive something two players can chip at from cover, which removes the
entire reason it is a decision. Left 4 Dead's number, and its reasoning.

### 7. A revive re-tests its own preconditions every tick

The reviver alive, in range, and not down themselves. A game that only calls
`cancel_revive()` from its death handler has one path to get wrong; this has none. Same
shape as dot-objective's defuse.

### 8. A mirror does not simulate

`authoritative = false` refuses `apply()` outright and makes `advance()` a no-op. Two
machines expiring the same effect disagree by whatever their tick rates differ by.

The wire form is **per entity** rather than everything at once, deliberately: effects are
the one thing here that is genuinely per-player and mostly private — an enemy's überCharge
is public and their afterburn is not — so who gets which is the game's decision. A manager
that only offered "everything" would have made it.

## Two bugs found by running it

**`on_death()` read the downed dictionary directly instead of creating on demand**, so an
entity that had never been *down* was never recorded as *dead* — and a defibrillator could
not bring back the one player who went straight from full health to a rocket, which is most
of them. Every other accessor in the class creates on demand; this one did not, and nothing
errored, because "not dead" is a legitimate thing for an entity to be.

**Three of the eight aggregates had no facade on the manager.** `DotEffectState` computes
`jump_scale`, `fire_rate_scale` and `may_jump` on every mutation alongside the five that
`DotEffectManager` forwards — and a game holds a manager, never a state, so those three
were reachable only by going round the facade through `state_of()`. `no_jump` is an
exported field of `DotEffectDef`, it is aggregated, and it crosses the wire; the one thing
missing was the question.

**The asymmetry is worse than the absence would have been.** Somebody who wires
`may_move` off the manager — which every consumer does — and then looks for `may_jump`
beside it finds nothing and concludes this addon has no such concept. That is how a
documented field ends up read by nobody without anything ever failing.

Found by the family's mechanical detector run over methods rather than settings, and it
is a variant worth naming: not "declared and called by nothing", but **declared on the
inner object and not on the one anybody holds.** The suite now asks for all eight through
the manager, which is the object under test.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/effects_selftest.tscn   # 108 checks
```

## Things deliberately not here

- **No particles, no sounds, no icons.** dot-ui's rule for dot-ui's reason. `label` and
  `tags` are what a HUD draws from.
- **No health.** See above. This is the whole design.
- **No classes.** A Team Fortress class is a loadout, a set of tunables and a health value
  — dot-loadout, `DotFpsTunables` and dot-combat respectively. A "class" resource here
  would be a fourth place to write the same three things.
- **No cooldowns or charges.** When a player may *use* something is a weapon's business and
  `DotWeaponState` has it.
- **No prediction.** Effects are server-authoritative and unpredicted, for dot-props'
  reason: a client that predicts its own crit and is wrong has shown the player a number
  that did not happen.
