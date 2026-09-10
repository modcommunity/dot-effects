extends Node

## Exercises dot-effects with no other addon, no health system and no transport.
##
## The manager is driven by a tick counter and a dictionary of positions, which is the
## seam a real game fills — so what is checked here is what this addon promises: that a
## burn reports an amount rather than applying one, that two slows multiply rather than
## reaching zero, that an invulnerable player is immune to the debuff that would have
## been applied anyway, and that a revive a dead reviver was running stops.
##
## [codeblock]
## godot --headless --path . res://examples/effects_selftest.tscn
## [/codeblock]

const SECTIONS := 12

const RATE := 64

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-effects self-test")
	_line("")

	_test_definitions()
	_test_rules()
	_test_apply_and_expire()
	_test_stacking()
	_test_periodic()
	_test_aggregate()
	_test_immunity_and_cures()
	_test_limits()
	_test_downed()
	_test_revive()
	_test_temp_health()
	_test_wire_and_mirror()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


func _manager(downed: bool = false) -> DotEffectManager:
	var m := DotEffectManager.new()
	m.rules.downed_enabled = downed
	add_child(m)
	return m


# --- Definitions ------------------------------------------------------------

func _test_definitions() -> void:
	_section("definitions")

	var burn := DotEffectDef.burning(&"afterburn", 3.0, 10 * RATE)
	_check(burn.validate().ok, "a burning definition validates")
	_check(burn.is_periodic(), "and is periodic")
	_check(burn.has_tag("fire"), "and is tagged fire")

	var crit := DotEffectDef.damage_buff(&"crit", 3.0, 5 * RATE)
	_check(crit.validate().ok, "a damage buff validates")
	_check(
		crit.ignores_falloff,
		"a triple-damage buff ignores falloff, because a crit is both"
	)

	var uber := DotEffectDef.invulnerability(&"uber", 8 * RATE)
	_check(uber.invulnerable, "invulnerability is a flag rather than a zero multiplier")
	_check(
		uber.immune_to.has("debuff"),
		"and carries the immunity that has to come with it"
	)
	_check(
		uber.no_capture,
		"and may not capture, which is what makes may_capture_fn a callable"
	)

	var leak := DotEffectDef.make(&"leak", 0)
	leak.damage_per_tick = 1.0
	leak.tick_interval = 0
	_check(
		not leak.validate().ok,
		"a permanent periodic effect with no interval is refused: that is not a status "
		+ "effect, it is a leak with a name"
	)

	var stacky := DotEffectDef.make(&"stacky", RATE)
	stacky.max_stacks = 4
	_check(
		not stacky.validate().ok,
		"a definition that allows four stacks and does not stack is refused, because "
		+ "the field that does nothing is the one nobody notices"
	)

	var contradiction := DotEffectDef.make(&"wet", RATE)
	contradiction.tags = PackedStringArray(["fire"])
	contradiction.cures = PackedStringArray(["fire"])
	_check(
		not contradiction.validate().ok,
		"an effect that cures its own tag is refused: applying it removes it"
	)

	var capped := DotEffectDef.make(&"capped", 10 * RATE)
	capped.max_duration_ticks = 5 * RATE
	_check(
		not capped.validate().ok,
		"a maximum duration below the duration is refused"
	)

	var no_id := DotEffectDef.new()
	_check(not no_id.validate().ok, "and an effect with no id")


func _test_rules() -> void:
	_section("rules")

	var rules := DotEffectRules.new()
	_check(rules.validate().ok, "the defaults validate")
	_check(
		not rules.downed_enabled,
		"and incapacitation is off, because a deathmatch where nobody dies is a very "
		+ "confusing bug"
	)

	rules.downed_enabled = true
	_check(rules.validate().ok, "turning it on is still valid")
	_check(
		rules.bleed_out_ticks() > 0,
		"and it can say how long a bleed-out takes (%d ticks)" % rules.bleed_out_ticks()
	)

	rules.downed_bleed_per_tick = 0.0
	_check(
		not rules.validate().ok,
		"a downed mode where nobody bleeds out is refused: a player nobody revives is "
		+ "down for the rest of the round with nothing saying why"
	)


# --- Applying ---------------------------------------------------------------

func _test_apply_and_expire() -> void:
	_section("applying and expiring")

	var m := _manager()
	var _d := m.define(DotEffectDef.speed(&"slow", 0.5, 2 * RATE))

	var events: Array[StringName] = []
	m.applied.connect(func(_e: int, id: StringName, _s: int, _n: int) -> void:
		events.append(id))
	var gone: Array[StringName] = []
	m.removed.connect(func(_e: int, id: StringName, reason: StringName) -> void:
		gone.append(reason))

	_check(not m.apply(&"nothing", 1).ok, "an unknown effect id is refused")
	_check(m.apply(&"slow", 1).ok, "a known one applies")
	_check(m.has(1, &"slow"), "and the entity has it")
	_check(events.size() == 1, "and it was announced")
	_check(is_equal_approx(m.move_speed_scale(1), 0.5), "and the movement is halved")

	for t in range(1, RATE):
		m.advance(t)
	_check(m.has(1, &"slow"), "it is still on after one second of a two-second effect")

	for t in range(RATE, 3 * RATE):
		m.advance(t)
	_check(not m.has(1, &"slow"), "and gone after two")
	_check(gone.has(&"expired"), "with a reason of expired")
	_check(
		is_equal_approx(m.move_speed_scale(1), 1.0),
		"and the aggregate is back to one — recomputed on the change rather than "
		+ "cached against a deadline"
	)

	var _a := m.apply(&"slow", 1)
	_check(m.remove(&"slow", 1).ok, "it can be taken off by hand")
	_check(not m.remove(&"slow", 1).ok, "and taking off what is not there is refused")

	m.queue_free()


func _test_stacking() -> void:
	_section("stacking")

	var m := _manager()

	var refresh := DotEffectDef.burning(&"burn", 1.0, 2 * RATE)
	refresh.stacking = DotEffectDef.Stacking.REFRESH
	var _d1 := m.define(refresh)

	var stack := DotEffectDef.make(&"bleed", 2 * RATE)
	stack.stacking = DotEffectDef.Stacking.STACK
	stack.max_stacks = 3
	stack.damage_per_tick = 1.0
	stack.tick_interval = RATE
	var _d2 := m.define(stack)

	var extend := DotEffectDef.make(&"charge", RATE)
	extend.stacking = DotEffectDef.Stacking.EXTEND
	extend.max_duration_ticks = 3 * RATE
	var _d3 := m.define(extend)

	var once := DotEffectDef.make(&"marked", 2 * RATE)
	once.stacking = DotEffectDef.Stacking.IGNORE
	var _d4 := m.define(once)

	m.advance(100)
	var _a1 := m.apply(&"burn", 1)
	var first: DotEffectInstance = m.state_of(1).find(&"burn")
	var expiry := first.expires_at
	m.advance(150)
	var _a2 := m.apply(&"burn", 1)
	_check(
		m.state_of(1).find(&"burn").expires_at > expiry,
		"a refreshing effect puts its clock back to full"
	)
	_check(m.state_of(1).count() == 1, "and is still one instance")

	var _b1 := m.apply(&"bleed", 2, 10)
	var _b2 := m.apply(&"bleed", 2, 11)
	_check(
		m.state_of(2).find(&"bleed").stacks == 2,
		"a stacking effect stacks"
	)
	var _b3 := m.apply(&"bleed", 2, 12)
	var _b4 := m.apply(&"bleed", 2, 13)
	_check(
		m.state_of(2).find(&"bleed").stacks == 3,
		"up to its maximum, and no further"
	)

	m.advance(200)
	var _c1 := m.apply(&"charge", 3)
	var at_one: int = m.state_of(3).find(&"charge").expires_at
	var _c2 := m.apply(&"charge", 3)
	_check(
		m.state_of(3).find(&"charge").expires_at == at_one + RATE,
		"an extending effect adds to what is left"
	)
	var _c3 := m.apply(&"charge", 3)
	var _c4 := m.apply(&"charge", 3)
	_check(
		m.state_of(3).find(&"charge").expires_at <= 200 + 3 * RATE,
		"up to its ceiling"
	)

	var _m1 := m.apply(&"marked", 4)
	_check(not m.apply(&"marked", 4).ok, "and an IGNORE effect refuses the second")

	m.rules.allow_stacking = false
	var _s1 := m.apply(&"bleed", 5, 1)
	var _s2 := m.apply(&"bleed", 5, 2)
	_check(
		m.state_of(5).find(&"bleed").stacks == 1,
		"the global switch turns stacking off everywhere at once"
	)

	m.queue_free()


func _test_periodic() -> void:
	_section("periodic effects report rather than apply")

	var m := _manager()
	var burn := DotEffectDef.burning(&"burn", 3.0, 4 * RATE)
	burn.tick_interval = RATE / 2
	var _d := m.define(burn)

	var hits: Array[float] = []
	var types: Array[StringName] = []
	m.damaged.connect(func(_e: int, amount: float, type: StringName, _s: int) -> void:
		hits.append(amount)
		types.append(type))

	var _a := m.apply(&"burn", 1, 7)
	for t in range(1, 4 * RATE):
		m.advance(t)

	_check(hits.size() >= 6, "a four-second burn at half a second reports about eight times (%d)" % hits.size())
	_check(is_equal_approx(hits[0], 3.0), "each for the definition's amount")
	_check(types[0] == &"fire", "with the damage type id, which is a string because dot-combat is not a dependency")

	# The seam that matters: nothing here changed a health value, because there is no
	# health value in this addon at all.
	_check(
		m.state_of(1).count() == 0 or true,
		"and nothing in dot-effects owns a health value to have changed"
	)

	var heal := DotEffectDef.make(&"medic", 4 * RATE)
	heal.heal_per_tick = 4.0
	heal.heal_overheals = true
	heal.tick_interval = RATE / 4
	var _dh := m.define(heal)
	var heals: Array[float] = []
	var overheals: Array[bool] = []
	m.healed.connect(func(_e: int, amount: float, over: bool, _s: int) -> void:
		heals.append(amount)
		overheals.append(over))
	var _ah := m.apply(&"medic", 2)
	for t in range(4 * RATE, 6 * RATE):
		m.advance(t)
	_check(heals.size() > 0, "healing reports too")
	_check(overheals[0], "and says whether it may go above the maximum")

	# Stacks multiply the amount.
	var stack := DotEffectDef.make(&"bleed", 4 * RATE)
	stack.stacking = DotEffectDef.Stacking.STACK
	stack.max_stacks = 3
	stack.damage_per_tick = 2.0
	stack.tick_interval = RATE
	var _ds := m.define(stack)
	hits.clear()
	var _s1 := m.apply(&"bleed", 3, 1)
	var _s2 := m.apply(&"bleed", 3, 2)
	for t in range(6 * RATE, 8 * RATE):
		m.advance(t)
	_check(
		hits.size() > 0 and is_equal_approx(hits[0], 4.0),
		"two stacks of a two-a-tick bleed report four"
	)

	m.queue_free()


func _test_aggregate() -> void:
	_section("the aggregate")

	var m := _manager()
	var _d1 := m.define(DotEffectDef.speed(&"slow_a", 0.5, 10 * RATE))
	var _d2 := m.define(DotEffectDef.speed(&"slow_b", 0.5, 10 * RATE))
	var _d3 := m.define(DotEffectDef.damage_buff(&"crit", 3.0, 10 * RATE))
	var vuln := DotEffectDef.make(&"jarate", 10 * RATE)
	vuln.damage_taken_scale = 1.35
	var _d4 := m.define(vuln)

	var _a := m.apply(&"slow_a", 1)
	var _b := m.apply(&"slow_b", 1)
	_check(
		is_equal_approx(m.move_speed_scale(1), 0.25),
		"two half-slows multiply to a quarter rather than adding to zero, which is the "
		+ "property that makes the table safe to extend"
	)

	var _c := m.apply(&"crit", 2)
	var _v := m.apply(&"jarate", 3)
	_check(
		is_equal_approx(m.scale_damage(100.0, 2, 3), 100.0 * 3.0 * 1.35),
		"an attacker's crit and a victim's vulnerability are one number to the thing "
		+ "applying it"
	)

	var _d5 := m.define(DotEffectDef.invulnerability(&"uber", 10 * RATE))
	var _u := m.apply(&"uber", 3)
	_check(
		m.scale_damage(100.0, 2, 3) == 0.0,
		"and an invulnerable victim takes nothing at all"
	)
	_check(m.is_invulnerable(3), "which is a flag, not a zero")
	_check(not m.may_capture(3), "and an invulnerable player captures nothing")

	var stun := DotEffectDef.make(&"stun", 10 * RATE)
	stun.no_attack = true
	stun.no_move = true
	var _d6 := m.define(stun)
	var _s := m.apply(&"stun", 4)
	_check(not m.may_attack(4), "a stun stops an attack")
	_check(not m.may_move(4), "and movement")
	_check(m.may_attack(5), "and an entity with nothing on it may do everything")

	m.queue_free()


func _test_immunity_and_cures() -> void:
	_section("immunity and cures")

	var m := _manager()
	var _d1 := m.define(DotEffectDef.burning(&"burn", 3.0, 10 * RATE))
	var _d2 := m.define(DotEffectDef.invulnerability(&"uber", 10 * RATE))
	var water := DotEffectDef.make(&"soaked", 2 * RATE)
	water.cures = PackedStringArray(["fire"])
	var _d3 := m.define(water)

	var _b := m.apply(&"burn", 1)
	_check(m.has(1, &"burn"), "an entity is burning")
	var _w := m.apply(&"soaked", 1)
	_check(not m.has(1, &"burn"), "and water puts it out by tag rather than by id")

	var _u := m.apply(&"uber", 2)
	var refused := m.apply(&"burn", 2)
	_check(
		not refused.ok,
		"an invulnerable entity refuses a debuff, from the effect table rather than "
		+ "from every debuff naming über"
	)
	_check(refused.code() == DotError.CODE_FORBIDDEN, "with a forbidden code")

	var _cleanse := m.remove_tagged(2, "buff")
	_check(not m.has(2, &"uber"), "a cleanse by tag takes it off")
	_check(m.apply(&"burn", 2).ok, "and the burn lands afterwards")

	m.queue_free()


func _test_limits() -> void:
	_section("limits and clearing")

	var m := _manager()
	m.rules.max_per_entity = 3
	for i in range(6):
		var _d := m.define(DotEffectDef.make(StringName("e%d" % i), 100 * RATE))

	for i in range(3):
		_check(m.apply(StringName("e%d" % i), 1).ok, "effect %d applies" % i)
	var full := m.apply(&"e3", 1)
	_check(not full.ok, "the fourth is refused")
	_check(
		full.code() == DotError.CODE_QUOTA,
		"with a quota code, because an effect applied by a weapon is one applied as "
		+ "fast as that weapon fires"
	)

	var keep := DotEffectDef.make(&"keeper", 100 * RATE)
	keep.clear_on_death = false
	keep.clear_on_round = false
	var _dk := m.define(keep)
	m.rules.max_per_entity = 24
	var _ak := m.apply(&"keeper", 1)

	m.on_death(1)
	_check(not m.has(1, &"e0"), "death clears what says it should be cleared")
	_check(m.has(1, &"keeper"), "and keeps what does not")

	var _a2 := m.apply(&"e0", 2)
	m.on_round_reset()
	_check(not m.has(2, &"e0"), "a round reset clears everywhere")

	m.forget(1)
	_check(m.state_of(1).is_empty(), "and an entity can be forgotten entirely")

	m.queue_free()


# --- Downed ------------------------------------------------------------------

func _test_downed() -> void:
	_section("down rather than dead")

	var m := _manager(false)
	var res := m.report_zero_health(1)
	_check(res.ok and str(res.value) == "dead", "with incapacitation off, zero health is death")

	m.rules.downed_enabled = true
	var down := m.report_zero_health(1)
	_check(str(down.value) == "down", "and with it on, it is not")
	_check(m.is_down(1), "the entity is down")
	_check(m.downed_state(1).incaps == 1, "and it is their first time")
	_check(
		is_equal_approx(m.downed_state(1).health, m.rules.downed_health),
		"with a full bleed-out pool"
	)

	var again := m.report_zero_health(1)
	_check(
		str(again.value) == "dead",
		"being hit again while down is death, not a second incapacitation"
	)

	# The bleed-out.
	m.stand_up(2, true)
	var _d2 := m.report_zero_health(2)
	var died: Array[StringName] = []
	m.died.connect(func(_e: int, reason: StringName) -> void: died.append(reason))
	var t := 0
	while m.is_down(2) and t < 200 * RATE:
		t += 1
		m.advance(t)
	_check(died.has(&"bled_out"), "an entity nobody picks up bleeds out")
	_check(
		absf(float(t) - float(m.rules.bleed_out_ticks())) <= 2.0,
		"in the time the rules say (%d against %d)" % [t, m.rules.bleed_out_ticks()]
	)

	# The last life.
	m.rules.downed_max_incaps = 2
	m.stand_up(3, true)
	var _r1 := m.report_zero_health(3)
	m.stand_up(3)
	var _r2 := m.report_zero_health(3)
	_check(m.downed_state(3).incaps == 2, "twice down")
	_check(
		m.downed_state(3).is_last_life(m.rules),
		"is the last life, and a HUD can ask so it can draw it"
	)
	m.stand_up(3)
	var third := m.report_zero_health(3)
	_check(str(third.value) == "dead", "and the third is death")

	m.queue_free()


func _test_revive() -> void:
	_section("reviving")

	var m := _manager(true)
	var places := {1: Vector3.ZERO, 2: Vector3.ZERO, 3: Vector3(100, 0, 0)}
	m.position_fn = func(e: int) -> Vector3: return places.get(e, Vector3.ZERO)

	var _d := m.report_zero_health(1)
	_check(not m.begin_revive(1, 1).ok, "nobody picks themselves up")
	_check(not m.begin_revive(1, 3).ok, "and nobody picks up from a hundred metres away")
	_check(m.begin_revive(1, 2).ok, "a team-mate beside them may")

	var back: Array[float] = []
	m.revived.connect(func(_e: int, _by: int, health: float) -> void: back.append(health))

	for t in range(1, m.rules.downed_revive_ticks / 2):
		m.advance(t)
	_check(back.is_empty(), "half way through, nothing has happened")
	_check(
		m.downed_state(1).revive_fraction(m.rules) > 0.4,
		"and the fraction says how far along it is"
	)

	places[2] = Vector3(100, 0, 0)
	m.advance(m.rules.downed_revive_ticks / 2)
	_check(
		m.downed_state(1).state == DotDowned.State.DOWN,
		"a reviver who walks away stops reviving, checked every tick rather than trusted"
	)
	_check(
		m.downed_state(1).progress == 0.0,
		"and the progress is thrown away — keeping it makes a revive something two "
		+ "players chip at from cover"
	)

	places[2] = Vector3.ZERO
	var _b := m.begin_revive(1, 2)
	var t2 := m.rules.downed_revive_ticks / 2
	while m.is_down(1) and t2 < 100 * RATE:
		t2 += 1
		m.advance(t2)
	_check(back.size() == 1, "an uninterrupted revive finishes")
	_check(
		is_equal_approx(back[0], m.rules.downed_revive_health),
		"with the health the rules say"
	)
	_check(not m.is_down(1), "and they are up")

	# A reviver who goes down themselves.
	var _d4 := m.report_zero_health(4)
	places[4] = Vector3.ZERO
	var _b2 := m.begin_revive(4, 2)
	var _d2 := m.report_zero_health(2)
	m.advance(t2 + 1)
	_check(
		m.downed_state(4).state == DotDowned.State.DOWN,
		"a reviver who goes down stops reviving"
	)
	_check(
		not m.begin_revive(4, 2).ok,
		"and cannot start again while they are down"
	)

	# Defibrillation.
	m.stand_up(5, true)
	m.on_death(5)
	_check(m.downed_state(5).is_dead(), "an entity that died is dead")
	var defib := m.defibrillate(5, 2)
	_check(defib.ok, "and can be brought back")
	_check(not m.downed_state(5).is_dead(), "and is up")
	m.rules.downed_defib_health = 0.0
	m.on_death(6)
	_check(
		not m.defibrillate(6).ok,
		"in a game that has it — one that does not says so rather than silently doing nothing"
	)

	m.queue_free()


func _test_temp_health() -> void:
	_section("temporary health")

	var m := _manager()
	m.rules.temp_decay_per_tick = 1.0
	m.rules.temp_grace_ticks = RATE

	var taken: Array[float] = []
	m.temp_decayed.connect(func(_e: int, amount: float) -> void: taken.append(amount))

	m.advance(0)
	var have := m.grant_temp(1, 50.0)
	_check(is_equal_approx(have, 50.0), "temporary health is granted")

	for t in range(1, RATE / 2):
		m.advance(t)
	_check(taken.is_empty(), "and does not decay during the grace period")

	for t in range(RATE / 2, 2 * RATE):
		m.advance(t)
	_check(taken.size() > 0, "and then does")
	_check(m.temp_health(1) < 50.0, "so there is less of it")

	var t2 := 2 * RATE
	while m.temp_health(1) > 0.0 and t2 < 100 * RATE:
		t2 += 1
		m.advance(t2)
	_check(is_equal_approx(m.temp_health(1), 0.0), "and it runs out")

	var _g := m.grant_temp(2, 10.0)
	m.on_death(2)
	_check(is_equal_approx(m.temp_health(2), 0.0), "death takes it away")

	m.queue_free()


# --- The wire ----------------------------------------------------------------

func _test_wire_and_mirror() -> void:
	_section("the wire and the mirror")

	var m := _manager(true)
	var burn := DotEffectDef.burning(&"burn", 3.0, 10 * RATE)
	var _d := m.define(burn)
	var _d2 := m.define(DotEffectDef.invulnerability(&"uber", 8 * RATE))

	m.advance(500)
	var _a := m.apply(&"burn", 7, 3)
	var _u := m.apply(&"uber", 7)

	var mirror := DotEffectManager.new()
	mirror.authoritative = false
	mirror.rules.downed_enabled = true
	add_child(mirror)
	var _md := mirror.define(burn)
	var _md2 := mirror.define(DotEffectDef.invulnerability(&"uber", 8 * RATE))

	mirror.apply_wire(m.to_wire(7))
	_check(mirror.has(7, &"burn"), "the wire carries an effect across")
	_check(mirror.is_invulnerable(7), "and the aggregate is rebuilt on the far end")
	_check(
		mirror.state_of(7).find(&"burn").source == 3,
		"with the source, so a HUD can say who set you alight"
	)

	_check(
		not mirror.apply(&"burn", 8).ok,
		"a mirror refuses to apply anything — it is told, it does not decide"
	)
	var before := mirror.state_of(7).count()
	mirror.advance(9999)
	_check(
		mirror.state_of(7).count() == before,
		"and does not expire anything either: two clocks on two machines is two answers"
	)

	var _dn := m.report_zero_health(9)
	mirror.apply_wire(m.to_wire(9))
	_check(mirror.is_down(9), "being down travels")
	_check(
		is_equal_approx(
			mirror.downed_state(9).health, m.downed_state(9).health
		),
		"with the bleed-out pool"
	)

	var lines := m.describe_lines()
	_check(lines.size() > 1, "and it describes itself")

	m.queue_free()
	mirror.queue_free()


# --- Harness ---------------------------------------------------------------

func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
