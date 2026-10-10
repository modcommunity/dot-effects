# dot-effects design

Why the addon is shaped the way it is, and why the obvious alternative is wrong at each point. The rules are one line each in [CLAUDE.md](../CLAUDE.md).

## Why this exists

[dot-combat](../../dot-combat) resolves one hit: a trace, a hitbox, a multiplier, a number subtracted from a `DotHealth`. Everything that happens over time to the entity on either end of that hit had nowhere to live, so every game reinvented it, and there is a lot of it. A class-based team shooter alone has burning, bleeding, blinding, dousing, crit-boost, mini-crit, invulnerability, overheal, marked-for-death and stun; a co-operative survival shooter has a stimulant, a heal-over-time, an incendiary, a lure and being incapacitated.

Nearly all of those are the same few fields with different numbers: a duration, a periodic amount, multipliers on damage taken, damage dealt, movement, jump and fire rate, and some flags. Writing them as classes is writing the same file twenty times and then having them disagree, which is this family's most repeated bug in its most expensive form. So an effect is one `DotEffectDef` resource, and `DotEffectDef.make`, `burning`, `damage_buff`, `invulnerability` and `speed` are the stock constructors.

## It never touches a health value

A burning entity does not lose health here. `DotEffectManager.damaged` is emitted with an amount, a type id and a source, and the game applies it to whatever it keeps health in. That is what makes the addon usable:

- dot-effects does not import dot-combat, so a slow, a stun and a speed boost work in a game with no damage system at all (one where being eaten is a mass ratio, say).
- The damage type is a `StringName` rather than a `DotDamageType`, because an id is what both ends already agree on and a class reference is a hard dependency.
- A game that wants lag compensation, armour, friendly-fire rules or damage falloff applied to an afterburn tick gets all of them for free, because the tick goes through the same `DotDamageResolver` as everything else.

The same seam in the other direction: this addon does not know when an entity dies. A game calls `on_death()`, and `report_zero_health()` answers "down" or "dead", so the whole of that decision lives in one place rather than at every damage site.

## The aggregate is recomputed on change, never cached against a deadline

`DotEffectState.recompute()` runs when an effect is applied, removed or expires: not per tick and never per query. The obvious optimisation is a cache with a validity window, and this family already paid for that one: dot-net's `DotNetInterest.relevant_for` cached per peer, an entity spawned since was in nobody's cached set, and on a host ticking faster than the wall clock the cache never expired and the entity was never sent once. A cached answer that misses what changed looks exactly like a wrong answer, and you look for it in the producer.

## Modifiers multiply, and stacks multiply too

Two 0.5 slows are 0.25, not 0. An additive scheme reaches zero at two entries and the third is a movement bug with no visible cause. This is the property that makes the effect table safe for a game to extend without re-deriving the whole thing.

## Invulnerability is a flag, not a zero multiplier

"Immune" and "takes zero damage" differ where it matters: a game draws one and not the other, an objective refuses a capture from one (`no_capture`), and a resolver that multiplies by zero still records a hit and still fires a hit sound.

`no_capture` is separate from `no_attack` for the reason dot-objective's presence asks `may_capture` and `may_block` separately: the team shooters' invulnerable player may not capture, may not be hurt, and may absolutely still shoot.

## Interaction is by tag, never by id

An effect that `cures` "fire" cures everything tagged fire. An effect that is `immune_to` "debuff" refuses every one of them. Naming ids directly produces a table where adding a nineteenth effect means editing eighteen, and where the one you forget is the bug.

Curing happens before the per-entity cap (`DotEffectRules.max_per_entity`) is checked, because an effect that cures fire and is refused for being one too many would leave the fire burning, which is the opposite of what it was applied for.

## Downed and revived

A cancelled revive throws its progress away. Keeping it makes a revive something two players can chip at from cover, which removes the entire reason it is a decision.

A revive re-tests its own preconditions every tick: the reviver alive, in range, and not down themselves. A game that only calls `cancel_revive()` from its death handler has one path to get wrong; this has none. Same shape as dot-objective's defuse.

Downed state is created on demand by every accessor, `on_death()` included; reading `_downed` directly loses the "dead" record of anyone who was never down ([history](history.md#on_death-skipped-anyone-never-down)).

## A mirror does not simulate

`authoritative = false` refuses `apply()` outright and makes `advance()` a no-op. Two machines expiring the same effect disagree by whatever their tick rates differ by.

The wire form is per entity (`to_wire(entity)` / `apply_wire`) rather than everything at once, deliberately: effects are the one thing here that is genuinely per-player and mostly private (an enemy's invulnerability charge is public and their afterburn is not), so who gets which is the game's decision. A manager that only offered "everything" would have made it.

## Every aggregate has a facade on the manager

A game holds a `DotEffectManager`, never a `DotEffectState`. Every aggregate the state computes needs a forwarding method on the manager, or it is reachable only through `state_of()` and reads as a concept the addon does not have ([history](history.md#three-aggregates-had-no-facade-on-the-manager)). The suite asks for them through the manager, which is the object under test.

## Deliberately not here

- **No particles, no sounds, no icons.** dot-ui's rule for dot-ui's reason. `label` and `tags` are what a HUD draws from.
- **No health.** The whole design, above.
- **No classes.** A class in a class-based shooter is a loadout, a set of tunables and a health value: dot-loadout, `DotFpsTunables` and dot-combat respectively. A "class" resource here would be a fourth place to write the same three things.
- **No cooldowns or charges.** When a player may use something is a weapon's business, and dot-weapon's arsenal has it.
- **No prediction.** Effects are server-authoritative and unpredicted, for dot-props' reason: a client that predicts its own crit and is wrong has shown the player a number that did not happen.
