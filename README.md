This is the **effects** asset for TMC's **Dot** collection. It adds status effects such as burning, crits, invulnerability, slows, stuns and marks. It also adds temporary health, and incapacitation: a player who reaches zero health goes down instead of dying, and a teammate can pick them back up.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## What it does
An effect is something that happens to an entity for a while: it burns, it bleeds, it is healed over time, it deals or takes more damage, it moves faster or slower, it cannot attack, move or jump, or it cannot be hurt at all. Every one of these is the same `DotEffectDef` document with different numbers, so a new effect is data and not a new class.

The addon never changes a health value itself. A burning entity makes the manager emit `damaged` with an amount, and your game applies it however it already applies damage. A slowed entity makes `move_speed_scale()` return less than 1, and your movement code reads it. This means effects work in a game with no damage system at all, and that a burn tick goes through the same armour and friendly-fire rules as any other hit.

It also has two related systems: temporary health that decays (overheal, pills), and being **downed** at zero health so a teammate can pick you up.

## Getting started
You need [Godot 4.7](https://godotengine.org/download). The easiest way to get this addon and the ones it needs is [dot-bootstrap](https://github.com/modcommunity/dot-bootstrap), which clones every project and links the addons into each one.

To add it to your own project by hand, copy `addons/dot_effects/` and [dot-core](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into it and enable dot-effects in **Project → Project Settings → Plugins**. dot-core is the only dependency.

## Using it

```gdscript
var effects := DotEffectManager.new()
effects.setup()
add_child(effects)

effects.define(DotEffectDef.burning(&"afterburn", 3.0, 10 * 64))  # 3 damage every 32 ticks, for 10 seconds
effects.define(DotEffectDef.damage_buff(&"crit", 3.0, 5 * 64))
effects.define(DotEffectDef.invulnerability(&"invuln", 8 * 64))
effects.define(DotEffectDef.speed(&"adrenaline", 1.4, 15 * 64))

effects.damaged.connect(func(entity, amount, type, source):
    health_of(entity).apply(DotDamage.make(amount, type, source, tick)))

effects.apply(&"afterburn", victim_id, attacker_id)   # a DotResult; refused if the victim is immune
effects.advance(tick)                                 # once per server tick
```

Entities are `int` ids. Your game asks the manager what an entity's effects add up to wherever it needs to know:

```gdscript
speed *= effects.move_speed_scale(id)
damage = effects.scale_damage(damage, attacker_id, victim_id)   # crit on one side, a vulnerability on the other
if not effects.may_attack(id): return
```

There are also `may_move`, `may_jump`, `may_capture`, `jump_scale`, `fire_rate_scale` and `is_invulnerable`. Call `on_death(id)` when an entity dies and `on_round_reset()` between rounds, so effects marked to clear on those are removed.

### What an effect can do
The four factories above cover the common cases. Everything else is a field on `DotEffectDef`:

| Field | Default | What it does |
| --- | --- | --- |
| `duration_ticks` | 640 | How long it lasts (10 seconds at 64 ticks) |
| `stacking` | `REFRESH` | A second application: `REFRESH` the duration, `EXTEND` it, `STACK` another beside it, or `IGNORE` it |
| `max_stacks` / `max_duration_ticks` | 1 / 0 | Limits for `STACK` and `EXTEND`. 0 means no limit |
| `per_source` | false | Each attacker gets their own instance (a bleed from two players) |
| `tick_interval` | 32 | How often the periodic part fires |
| `damage_per_tick` / `damage_type` | 0 / none | Damage each interval, and its type |
| `heal_per_tick` / `heal_overheals` | 0 / false | Healing each interval, and whether it can go over maximum |
| `damage_taken_scale` / `damage_dealt_scale` | 1.0 | Damage multipliers in each direction |
| `ignores_falloff` | false | Tells your damage code to skip distance falloff (a full crit). Read it with `state_of(id).ignores_falloff()` |
| `move_speed_scale` / `jump_scale` / `fire_rate_scale` | 1.0 | Movement, jump and fire rate multipliers |
| `invulnerable` | false | Takes no damage |
| `no_attack` / `no_move` / `no_jump` / `no_capture` | false | What the entity cannot do (a stun, a freeze) |
| `cures` / `immune_to` | none | Tags this effect removes when applied, and tags it refuses while active |
| `clear_on_death` / `clear_on_round` | true | Removed on death, and between rounds |

## Downed instead of dead
Turn on `rules.downed_enabled` and ask the manager what should happen whenever an entity reaches zero health:

```gdscript
var what := effects.report_zero_health(entity)
if str(what.value) == "down":
    player.play_downed()
else:
    player.die()
```

A downed player bleeds out over about 90 seconds. A teammate who holds revive on them for 5 seconds (`begin_revive(entity, by)`) brings them back with 30 health, and moving away or being downed cancels it and loses the progress. The bleed-out pool keeps draining while a revive is held (a rescue started in the last seconds is a gamble). The third time down is death. `position_fn` and `allies_fn` let the manager check that the reviver is close enough and on the same side. `defibrillate()` brings somebody back from dead.

## Settings
The rules live in a `DotEffectRules` resource, set on the manager's `rules` (it makes a default one if you do not). Like every Dot config it is layered: inspector defaults, then a JSON file, then the environment, then the command line. Call `load_layered()` on it before `setup()` to apply them:

```gdscript
var rules := DotEffectRules.new()
rules.load_layered("user://effects.json")
effects.rules = rules
```

```bash
DOT_EFFECTS_DOWNED_ENABLED=true godot --headless -- --effects-downed-max-incaps=3
```

| Setting | Default | What it does |
| --- | --- | --- |
| `max_per_entity` | 24 | Most effects one entity can have at once |
| `allow_stacking` | true | Off makes every `STACK` effect refresh instead |
| `downed_enabled` | false | Go down at zero health instead of dying |
| `downed_health` | 300 | The pool a downed player bleeds through |
| `downed_bleed_per_tick` | 0.052 | How fast it drains (about 90 seconds at 64 ticks) |
| `downed_revive_ticks` | 320 | How long a revive takes (5 seconds) |
| `downed_revive_health` | 30 | Health a revived player comes back with |
| `downed_revive_radius` | 2.0 | How close the reviver must stay. 0 skips the check |
| `downed_revive_scales` | false | More revivers make it faster: a second `begin_revive` joins instead of replacing, `leave_revive(entity, by)` lets one go and the rest carry on |
| `downed_max_incaps` | 2 | Revives before the next down is death. 0 is unlimited |
| `downed_defib_health` | 50 | Health after `defibrillate()`. 0 turns it off |
| `temp_decay_per_tick` | 0.1 | How fast temporary health drains. 0 keeps it |
| `temp_grace_ticks` | 0 | Ticks after a top-up before it starts to drain |

## Testing

```bash
godot --headless --path . --import
godot --headless --path . res://examples/effects_selftest.tscn
```

## License
MIT. See [LICENSE](LICENSE).
