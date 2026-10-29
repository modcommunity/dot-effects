extends Node

## The harness and the later sections of effects_selftest.gd, split out for the size budget.

const RATE := 64

var _passed := 0
var _failed := 0
var _section_count := 0


func _manager(downed: bool = false) -> DotEffectManager:
	var m := DotEffectManager.new()
	m.rules.downed_enabled = downed
	add_child(m)
	return m


# Downed

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

	_check_shared_revive()

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


func _check_shared_revive() -> void:
	# Two pairs of hands, when the rules say they count. Before, a second begin_revive
	# replaced the first reviver and `revivers` stayed 1: downed_revive_scales did nothing.
	var shared := _manager(true)
	shared.rules.downed_revive_scales = true
	var spots := {1: Vector3.ZERO, 2: Vector3.ZERO, 3: Vector3.ZERO}
	shared.position_fn = func(e: int) -> Vector3: return spots.get(e, Vector3.ZERO)
	var _s1 := shared.report_zero_health(1)
	var _s2 := shared.begin_revive(1, 2)
	_check(shared.begin_revive(1, 3).ok and shared.downed_state(1).revivers == 2,
		"under downed_revive_scales a second reviver joins rather than replacing the first")
	var half := shared.rules.downed_revive_ticks / 2
	for t in range(1, half + 2):
		shared.advance(t)
	_check(not shared.is_down(1), "and two finish in half the time")

	var _s3 := shared.report_zero_health(1)
	var _s4 := shared.begin_revive(1, 2)
	var _s5 := shared.begin_revive(1, 3)
	spots[2] = Vector3(100, 0, 0)
	shared.advance(half + 3)
	var left := shared.downed_state(1)
	_check(left.state == DotDowned.State.REVIVING and left.reviver == 3 and left.revivers == 1,
		"when the reviver walks off, the one still holding carries on alone")
	shared.leave_revive(1, 3)
	_check(shared.downed_state(1).state == DotDowned.State.DOWN,
		"and when the last one lets go the revive stops")
	shared.queue_free()


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


# The wire

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


func _test_stack_scale() -> void:
	_section("stack scale")
	_check(is_equal_approx(DotStackScale.ramp(2.0, 0.5, 5.0, 0), 2.0), "no stacks: the base")
	_check(is_equal_approx(DotStackScale.ramp(2.0, 0.5, 5.0, 3), 3.5), "three stacks: base plus three steps")
	_check(is_equal_approx(DotStackScale.ramp(2.0, 0.5, 5.0, 99), 5.0), "any number of stacks stops at the cap")
	_check(is_equal_approx(DotStackScale.ramp(2.0, 0.5, 5.0, -4), 2.0), "negative stacks count as none")
	_check(is_equal_approx(DotStackScale.fade_alpha(0, 0.1, 0.3), 1.0), "no stacks: solid")
	_check(is_equal_approx(DotStackScale.fade_alpha(3, 0.1, 0.3), 0.7), "three stacks: 1 - 3 * step")
	_check(is_equal_approx(DotStackScale.fade_alpha(40, 0.1, 0.3), 0.3), "stops at the minimum alpha")
	_check(DotStackScale.fade_alpha(99, 0.5, 0.0) >= DotStackScale.ALPHA_FLOOR, "a minimum of 0 still leaves it visible")
	_check(is_equal_approx(DotStackScale.fade_alpha(5, -1.0, 0.3), 1.0), "a negative step never darkens the other way")


# Hazard pool

func _test_hazard_pool() -> void:
	_section("hazard pool: damage only inside, ramp, cap, lifetime, trail, slow")
	var profile := DotHazardProfile.new()
	profile.kind = &"goo"
	profile.radius = 2.0
	profile.seconds = 4.0
	profile.dps = 10.0
	profile.dps_start = 10.0
	profile.ramp_seconds = 0.0
	profile.grow_seconds = 0.0
	profile.slow_factor = 0.5
	profile.fade_seconds = 2.0
	profile.max_per_owner = 2
	profile.global_cap = 3
	profile.trail_spacing = 2.0
	profile.trail_interval = 0.5
	profile.trail_radius = 1.0
	profile.trail_seconds = 2.0

	var victims := {1: Vector3(0.5, 0, 0), 2: Vector3(9, 0, 0)}
	var paid := {}
	var pool := DotHazardPool.new()
	pool.occupants = func(at: Vector3, radius: float, _reach: float) -> Array:
		var out := []
		for v: int in victims:
			if (victims[v] as Vector3).distance_to(at) <= radius:
				out.append(v)
		return out
	pool.damage_sink = func(v: int, amount: float, _o: int, _k: StringName) -> void:
		paid[v] = float(paid.get(v, 0.0)) + amount
	var events := []
	pool.added.connect(func(id: int, _k: StringName, _a: Vector3, _r: float, _s: float) -> void: events.append(id))
	pool.ended.connect(func(id: int) -> void: events.append(-id))

	var id := pool.add(profile, Vector3.ZERO, 0.0, 7)
	_check(events == [id], "a puddle is announced once when laid")
	for i in range(10):
		pool.tick(0.1 * float(i + 1), 0.1)
	_check(is_equal_approx(float(paid.get(1, 0.0)), 10.0), "a victim inside takes dps over a second (%.2f)" % float(paid.get(1, 0.0)))
	_check(not paid.has(2), "a victim outside takes nothing")
	_check(is_equal_approx(pool.slow_of(1), 0.5) and is_equal_approx(pool.slow_of(2), 1.0), "slow applies inside only")
	_check(is_equal_approx(pool.alpha_of(id, 1.0), 1.0) and is_equal_approx(pool.alpha_of(id, 3.0), 0.5), "alpha holds then fades over fade_seconds")
	pool.tick(4.0, 3.0)
	_check(pool.areas.is_empty() and events.back() == -id, "it ends at its lifetime and says so")
	pool.tick(4.1, 0.1)
	_check(is_equal_approx(float(paid.get(1, 0.0)), 10.0) and is_equal_approx(pool.slow_of(1), 1.0), "an ended puddle neither hurts nor slows")

	var a := pool.add(profile, Vector3(20, 0, 0), 10.0, 7)
	var _b := pool.add(profile, Vector3(21, 0, 0), 10.1, 7)
	var _c := pool.add(profile, Vector3(22, 0, 0), 10.2, 7)
	_check(pool.count(&"goo", 7) == 2 and not pool.areas.has(a), "per-owner cap evicts that owner's oldest")
	var _d := pool.add(profile, Vector3(23, 0, 0), 10.3, 8)
	var _e := pool.add(profile, Vector3(24, 0, 0), 10.4, 8)
	_check(pool.count(&"goo") == 3 and pool.count(&"goo", 8) == 2, "global cap holds at 3")

	pool.clear()
	var dropped := 0
	var last := Vector3.ZERO
	for i in range(40):
		last = Vector3(float(i) * 0.25, 0, 0)
		if pool.trail(profile, 5, last, float(i) * 0.1) != 0:
			dropped += 1
	_check(dropped == 5 and pool.count(&"goo", 5) == 2, "a trail drops every 2 m: 5 over 10 m, 2 alive under the owner cap (got %d)" % dropped)
	pool.end_trail(5)
	_check(pool.trail(profile, 5, last, 99.0) != 0, "after end_trail the next step drops at once")
	var tr := pool.add(profile, Vector3.ZERO, 0.0, 9, -1.0, profile.trail_radius, profile.trail_seconds)
	_check(is_equal_approx(float((pool.areas[tr] as Dictionary)["radius"]), 1.0), "trail puddles use trail radius")

	var ramp := DotHazardProfile.new()
	ramp.grow_seconds = 1.0
	var rp := DotHazardPool.new()
	var rid := rp.add(ramp, Vector3.ZERO, 0.0, 0, 3.0)
	_check(is_equal_approx(rp.radius_at(rid, 0.0), ramp.radius * ramp.start_fraction) and is_equal_approx(rp.radius_at(rid, 5.0), ramp.radius), "a puddle spreads from 20% to full over its first second")
	var got := DotHazardProfile.from_values({"radius": 99999, "dps": 5, "kind": "oil", "bogus": 1})
	_check(got.radius == 50.0 and got.dps == 5.0 and got.kind == &"oil", "from_values clamps and ignores unknown keys")
	var screen := DotEffectDef.screen_impair(&"goo_blind", 320, 3)
	_check(screen.stacking == DotEffectDef.Stacking.STACK and screen.max_stacks == 3 and "screen_impair" in screen.tags, "screen_impair is a stacking tagged status")


# Harness

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
