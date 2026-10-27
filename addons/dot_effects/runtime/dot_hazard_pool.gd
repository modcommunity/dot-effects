class_name DotHazardPool
extends RefCounted

## Ground hazards the server simulates and announces once: puddles of acid, goo or oil that hurt whoever stands in them.
##
## Damage leaves through [member damage_sink] (a game's combat manager); who stands where comes from
## [member occupants]. Clients are told each puddle once ([signal added], [signal ended]) and draw it from
## [method radius_at] and [method alpha_of], so nothing is sent per tick. No node, no autoload.

## A puddle appeared; the same arguments a game puts on the wire.
signal added(id: int, kind: StringName, at: Vector3, radius: float, seconds: float)
signal ended(id: int)
## Damage is owed to [param victim]; mirrors [member damage_sink] for listeners.
signal damaged(victim: Variant, amount: float, owner: int, kind: StringName)

## Callable(at: Vector3, radius: float, reach: float) -> Array of victims.
var occupants: Callable = Callable()
## Callable(victim, amount: float, owner: int, kind: StringName).
var damage_sink: Callable = Callable()
## Callable(victim) -> stable key (default: the victim itself).
var victim_key: Callable = Callable()
## Callable() -> int, so ids share a counter with a game's other hazards; empty uses an own counter.
var id_source: Callable = Callable()

## id -> {kind, at, radius, until, since, amount, owner, profile, grow, paid}
var areas: Dictionary = {}

var _next_id: int = 1
var _stood: Dictionary = {}
var _slow: Dictionary = {}
var _trails: Dictionary = {}


## Lays a puddle. [param amount] below 0 uses [member DotHazardProfile.dps] as the full rate; otherwise the full rate
## is amount times [member DotHazardProfile.amount_mult]. Evicts the oldest puddle of the owner or kind first when a cap is full.
func add(profile: DotHazardProfile, at: Vector3, now: float, owner: int = 0, amount: float = -1.0,
		radius: float = -1.0, seconds: float = -1.0) -> int:
	_enforce_caps(profile, owner)
	var id := id_source.call() as int if id_source.is_valid() else _take_id()
	var r := radius if radius > 0.0 else profile.radius
	var s := seconds if seconds > 0.0 else profile.seconds
	areas[id] = {"kind": profile.kind, "at": at, "radius": r, "until": now + s, "since": now,
		"amount": amount if amount >= 0.0 else profile.dps / maxf(profile.amount_mult, 0.0001), "owner": owner,
		"profile": profile}
	added.emit(id, profile.kind, at, r, s)
	return id


## Removes a puddle early.
func remove(id: int) -> void:
	if areas.erase(id):
		ended.emit(id)


## Puddles of [param kind] now (every kind when empty).
func count(kind: StringName = &"", owner: int = -1) -> int:
	var n := 0
	for a: Dictionary in areas.values():
		if (kind == &"" or a["kind"] == kind) and (owner < 0 or int(a["owner"]) == owner):
			n += 1
	return n


## The puddle's radius at [param now]: it spreads rather than appearing whole.
func radius_at(id: int, now: float) -> float:
	if not areas.has(id):
		return 0.0
	var a: Dictionary = areas[id]
	var p: DotHazardProfile = a["profile"]
	if p.grow_seconds <= 0.0:
		return float(a["radius"])
	return float(a["radius"]) * clampf((now - float(a["since"])) / p.grow_seconds, p.start_fraction, 1.0)


## 1 until [member DotHazardProfile.fade_seconds] before the end, then falling to 0.
func alpha_of(id: int, now: float) -> float:
	if not areas.has(id):
		return 0.0
	var a: Dictionary = areas[id]
	var fade := (a["profile"] as DotHazardProfile).fade_seconds
	if fade <= 0.0:
		return 1.0
	return clampf((float(a["until"]) - now) / fade, 0.0, 1.0)


## The movement multiplier for [param key] (what [member victim_key] returns) from puddles stood in at the last tick; 1 when none.
func slow_of(key: Variant) -> float:
	return float(_slow.get(key, 1.0))


func tick(now: float, delta: float) -> void:
	var stood_now := {}
	var slow_now := {}

	for id: int in areas.keys():
		var a: Dictionary = areas[id]

		if float(a["until"]) <= now:
			areas.erase(id)
			ended.emit(id)
			continue

		if not occupants.is_valid():
			continue

		var p: DotHazardProfile = a["profile"]
		var at: Vector3 = a["at"]
		var full: float = float(a["amount"]) * p.amount_mult
		var inside: Array = occupants.call(at, radius_at(id, now), p.reach)

		for victim: Variant in inside:
			var key: Variant = _key(victim)
			var stood: float = float(_stood.get(key, 0.0)) + delta
			stood_now[key] = stood
			slow_now[key] = minf(float(slow_now.get(key, 1.0)), p.slow_factor)
			var rate := lerpf(p.dps_start, full, clampf(stood / p.ramp_seconds, 0.0, 1.0)) if p.ramp_seconds > 0.0 else full
			_pay(a, victim, rate, delta, p)

	_stood = stood_now
	_slow = slow_now


## Drops a puddle behind a moving [param owner] at [param pos] when it has gone [member DotHazardProfile.trail_spacing]
## since the last one and [member DotHazardProfile.trail_interval] has passed. Returns the id, or 0 when none dropped.
func trail(profile: DotHazardProfile, owner: int, pos: Vector3, now: float) -> int:
	var t: Dictionary = _trails.get(owner, {})

	if not t.is_empty():
		var moved: float = (t["pos"] as Vector3).distance_to(pos)
		if moved < profile.trail_spacing or now - float(t["time"]) < profile.trail_interval:
			return 0

	_trails[owner] = {"pos": pos, "time": now}
	return add(profile, pos, now, owner, -1.0, profile.trail_radius, profile.trail_seconds)


## Forgets an owner's trail (it died or teleported), so the next step drops at once.
func end_trail(owner: int) -> void:
	_trails.erase(owner)


func clear() -> void:
	for id: int in areas.keys():
		ended.emit(id)
	areas.clear()
	_stood.clear()
	_slow.clear()
	_trails.clear()


func describe() -> Dictionary:
	return {"areas": areas.size(), "trails": _trails.size()}


func _pay(a: Dictionary, victim: Variant, rate: float, delta: float, p: DotHazardProfile) -> void:
	if p.tick_interval <= 0.0:
		_deliver(victim, rate * delta, int(a["owner"]), p.kind)
		return

	# Payments are per puddle and victim in effect: the clock is the puddle's.
	var key := "%s" % [_key(victim)]
	var paid: Dictionary = a.get("paid_by", {})
	var owed: float = float(paid.get(key, 0.0)) + delta
	if owed >= p.tick_interval:
		_deliver(victim, rate * owed, int(a["owner"]), p.kind)
		owed = 0.0
	paid[key] = owed
	a["paid_by"] = paid


func _deliver(victim: Variant, amount: float, owner: int, kind: StringName) -> void:
	if damage_sink.is_valid():
		damage_sink.call(victim, amount, owner, kind)
	damaged.emit(victim, amount, owner, kind)


func _enforce_caps(profile: DotHazardProfile, owner: int) -> void:
	if profile.max_per_owner > 0:
		while count(profile.kind, owner) >= profile.max_per_owner:
			remove(_oldest(profile.kind, owner))
	if profile.global_cap > 0:
		while count(profile.kind) >= profile.global_cap:
			remove(_oldest(profile.kind, -1))


func _oldest(kind: StringName, owner: int) -> int:
	var best := -1
	for id: int in areas:
		var a: Dictionary = areas[id]
		if a["kind"] == kind and (owner < 0 or int(a["owner"]) == owner):
			if best < 0 or float(a["since"]) < float((areas[best] as Dictionary)["since"]):
				best = id
	return best


func _key(victim: Variant) -> Variant:
	return victim_key.call(victim) if victim_key.is_valid() else victim


func _take_id() -> int:
	_next_id += 1
	return _next_id - 1
