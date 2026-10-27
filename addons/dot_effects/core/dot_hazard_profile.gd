class_name DotHazardProfile
extends RefCounted

## What one kind of ground hazard (acid, goo, oil) does: the document a [DotHazardPool] reads.

## Replicated kind name; clients draw the puddle from it.
var kind: StringName = &"acid"
## Final radius in metres; a puddle spreads from [member start_fraction] over [member grow_seconds].
var radius: float = 3.2
## Seconds a puddle lives.
var seconds: float = 7.0
## Damage per second once a victim has stood in it [member ramp_seconds]; the full rate.
var dps: float = 12.0
## Damage per second the moment a victim steps in.
var dps_start: float = 2.0
## Seconds of standing to reach [member dps] from [member dps_start]; 0 is the full rate at once.
var ramp_seconds: float = 2.0
## Seconds between damage payments; 0 pays every tick.
var tick_interval: float = 0.0
## Movement multiplier for victims inside (1 is none); read through [method DotHazardPool.slow_of].
var slow_factor: float = 1.0
## Reach above and below the puddle's centre that still counts as inside.
var reach: float = 1.2
## The puddle spreads over this many seconds, starting at [member start_fraction] of its radius.
var grow_seconds: float = 1.0
var start_fraction: float = 0.2
## Seconds before the end that [method DotHazardPool.alpha_of] fades to nothing.
var fade_seconds: float = 0.0
## Drawing hint for clients; the wire does not carry it.
var color: Color = Color(0.4, 0.9, 0.2, 0.8)
## Puddles one owner may have at once (the oldest goes first); 0 is no limit.
var max_per_owner: int = 0
## Puddles of this kind at once on the whole server; 0 is no limit.
var global_cap: int = 0
## A trail drops a puddle after the owner moves this far, and no more often than [member trail_interval].
var trail_spacing: float = 1.5
var trail_interval: float = 0.2
## A trail puddle's radius and life; 0 uses [member radius] and [member seconds].
var trail_radius: float = 0.0
var trail_seconds: float = 0.0
## [method DotHazardPool.add] given an amount sets the full rate to amount times this (acid: 4).
var amount_mult: float = 4.0

## Property name -> [default, min, max] for a game to publish as cvar or profile keys.
const KEYS := {
	"radius": [3.2, 0.1, 50.0], "seconds": [7.0, 0.1, 600.0], "dps": [12.0, 0.0, 1000.0],
	"dps_start": [2.0, 0.0, 1000.0], "ramp_seconds": [2.0, 0.0, 60.0], "tick_interval": [0.0, 0.0, 10.0],
	"slow_factor": [1.0, 0.05, 1.0], "reach": [1.2, 0.1, 20.0], "grow_seconds": [1.0, 0.0, 30.0],
	"start_fraction": [0.2, 0.0, 1.0], "fade_seconds": [0.0, 0.0, 60.0], "max_per_owner": [0, 0, 10000],
	"global_cap": [0, 0, 100000], "trail_spacing": [1.5, 0.1, 50.0], "trail_interval": [0.2, 0.0, 10.0],
	"trail_radius": [0.0, 0.0, 50.0], "trail_seconds": [0.0, 0.0, 600.0], "amount_mult": [4.0, 0.0, 100.0],
}


## The shipped acid pool of a spitter.
static func acid() -> DotHazardProfile:
	return DotHazardProfile.new()


## Reads every key present in [param values] (a dot-profile's values, a cvar dump), clamped; unknown keys are ignored.
static func from_values(values: Dictionary, base: DotHazardProfile = null) -> DotHazardProfile:
	var p := base if base != null else DotHazardProfile.new()
	for key: String in KEYS:
		if not values.has(key):
			continue
		var limits: Array = KEYS[key]
		var v: Variant = values[key]
		p.set(key, clampi(int(v), int(limits[1]), int(limits[2])) if p.get(key) is int else clampf(float(v), float(limits[1]), float(limits[2])))
	if values.has("kind"):
		p.kind = StringName(str(values["kind"]))
	if values.has("color"):
		p.color = Color(str(values["color"])) if values["color"] is String else values["color"]
	return p


func to_values() -> Dictionary:
	var out := {"kind": String(kind), "color": color.to_html()}
	for key: String in KEYS:
		out[key] = get(key)
	return out


func describe() -> String:
	return "DotHazardProfile %s r=%.1f %.1fs dps=%.1f cap=%d/%d" % [kind, radius, seconds, dps, max_per_owner, global_cap]
