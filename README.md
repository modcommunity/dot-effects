This is the **effects** asset for TMC's **Dot** collection. It adds status effects — burning, crits, invulnerability, slows, stuns, marks — plus temporary health and incapacitation, where a player at zero health becomes a decision for their team rather than a respawn timer.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## One document, not twenty classes

Count up the status effects a team shooter and a co-operative shooter ship between them and you get about twenty-one: burning, bleeding, blinding, dousing, crit-boost, mini-crit, invulnerability, overheal, marked-for-death, stun, a stimulant, a heal-over-time, an incendiary and being incapacitated among them. Nineteen of the twenty-one are the same six fields with different numbers — a duration, a periodic amount, a multiplier on damage taken, a multiplier on damage dealt, a multiplier on movement, and a flag.

```gdscript
effects.define(DotEffectDef.burning(&"afterburn", 3.0, 10 * 64))
effects.define(DotEffectDef.damage_buff(&"crit", 3.0, 5 * 64))
effects.define(DotEffectDef.invulnerability(&"invuln", 8 * 64))
effects.define(DotEffectDef.speed(&"adrenaline", 1.4, 15 * 64))
```

## It never touches a health value

A burning entity does not lose health here. The manager emits an amount and **your game** applies it, through whatever it already uses:

```gdscript
effects.damaged.connect(func(entity, amount, type, source):
    health_of(entity).apply(DotDamage.make(amount, type, source, tick)))
```

That is what lets a slow, a stun and a speed boost work in a game with no damage system at all — and it means an afterburn tick goes through the same lag compensation, armour and friendly-fire rules as every other hit, because it *is* every other hit.

## Down rather than dead

```gdscript
effects.rules.downed_enabled = true

# One place decides, rather than every damage site:
var what := effects.report_zero_health(entity)
if str(what.value) == "down":
    player.play_downed()
else:
    player.die()
```

A downed player bleeds out over ninety seconds, is picked up in five, comes back with 30 health, and the third time is the last. A cancelled revive throws its progress away — keeping it makes a revive something two players chip at from cover, which removes the whole reason it is a decision.

## Installing

Copy `addons/dot_effects/` and [`dot-core`](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your project and enable dot-effects in **Project → Project Settings → Plugins**.

## Dependencies

[dot-core](https://github.com/modcommunity/dot-core). Nothing else.

## License

MIT.
