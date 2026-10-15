class_name LFCrewAnim
## Character animation state machine for the Interdimensional Delivery Crew.
##
## A pose is a pure function of (character, state, age in that state, global time, seed). There
## are no per-character tweens or timers to cancel, so every state is interruptible: undo, reset,
## replay, backgrounding, save/restore and rapid Run/Stop simply change the inputs and the next
## frame draws the right pose. Nothing here reads or writes simulation data, so animations cannot
## change timing, collisions, scoring or solvability (tests/test_crew.gd checks this).
##
## Durations are starting values to tune on devices (docs/CHARACTER_ANIMATIONS.md).

enum { IDLE, SELECTED, MOVING, WAITING, SURPRISED, FAILED, DELIVERED, CELEBRATING }
const NAMES := ["idle", "selected", "moving", "waiting", "surprised", "failed", "delivered", "celebrating"]

const BLINK := 0.14
const SELECT := 0.16
const DELIVER := 0.38
const FAIL := 0.3
const GROUP := 0.8


static func state_name(s: int) -> String:
	return NAMES[clampi(s, 0, NAMES.size() - 1)]


static func state_from_name(n: String) -> int:
	var i := NAMES.find(n)
	return i if i >= 0 else IDLE


## Neutral pose. Units are fractions of the character's body size.
static func base() -> Dictionary:
	return {
		"dx": 0.0, "dy": 0.0, "sx": 1.0, "sy": 1.0, "rot": 0.0,
		"eyes": "open", "look": Vector2.ZERO, "mouth": "smile", "brows": "",
		"arms": "down", "foot": 0.0, "ghost": 0.0, "sweat": false, "z": false,
	}


## Deterministic 0..1 noise (no RandomNumberGenerator: the same inputs always give the same pose,
## so replays and screenshots look identical every time).
static func noise(seed: int, step: int) -> float:
	return float(LFRng.fnv1a32("%d:%d" % [seed, step]) % 1000) / 1000.0


static func _blinking(t: float, seed: int, period: float, dur := BLINK) -> bool:
	return fposmod(t + float(seed % 97) * 0.37, period) < dur


## `body` is the character's style id ("bloop", "zip", "glitch", "mochi"; anything else gets a
## generic personality). `ctx` may hold: dir (Vector2 travel direction), motion (bool, false for
## reduced motion / animations off), bounce (celebration height multiplier), starry, perfect.
static func pose(body: String, state: int, age: float, t: float, seed := 0, ctx := {}) -> Dictionary:
	var p := base()
	var motion: bool = ctx.get("motion", true)
	var dir: Vector2 = ctx.get("dir", Vector2.ZERO)
	match state:
		IDLE:
			_idle(p, body, t, seed)
		SELECTED:
			var k := clampf(age / maxf(SELECT, 0.01), 0.0, 1.0)
			p["dy"] = -sin(k * PI) * 0.12
			p["sy"] = 1.0 - 0.08 * sin(k * PI * 2.0)
			p["sx"] = 1.0 + 0.06 * sin(k * PI * 2.0)
			match body:
				"bloop":
					p["brows"] = "confident"
					p["mouth"] = "grin"
					p["arms"] = "up"
					p["dy"] = -sin(k * PI) * 0.16
				"zip":
					p["eyes"] = "wide"
					p["mouth"] = "o"
					p["sweat"] = true
					p["dy"] = -sin(k * PI) * 0.08
					p["dx"] = -sin(k * PI) * 0.04
				"glitch":
					p["ghost"] = 1.0 - k
					p["mouth"] = "tongue"
				"mochi":
					p["eyes"] = "wide" if k < 0.6 else "open"
					p["mouth"] = "o"
		MOVING:
			var wob := sin(t * 14.0 + seed)
			p["sy"] = 1.0 + 0.05 * wob
			p["sx"] = 1.0 - 0.04 * wob
			p["rot"] = dir.x * 0.12
			p["look"] = dir
			match body:
				"bloop":
					p["rot"] = dir.x * 0.18
					p["mouth"] = "grin"
					p["brows"] = "confident"
				"zip":
					p["dx"] = sin(t * 61.0 + seed) * 0.012
					p["mouth"] = "wobble"
					p["eyes"] = "wide"
					p["brows"] = "worried"
				"glitch":
					p["rot"] += sin(t * 9.0 + seed) * 0.12
					p["mouth"] = "tongue"
				"mochi":
					var sq := sin(t * 8.0 + seed)
					p["sy"] = 1.0 + 0.09 * sq
					p["sx"] = 1.0 - 0.07 * sq
					p["eyes"] = "sleepy"
		WAITING:
			p["look"] = dir
			match body:
				"bloop":
					p["foot"] = absf(sin(t * 10.0))
					p["mouth"] = "flat"
					p["brows"] = "confident"
				"zip":
					p["eyes"] = "closed" if _blinking(t, seed, 0.7) else "wide"
					p["brows"] = "worried"
					p["mouth"] = "wobble"
				"glitch":
					p["mouth"] = ["tongue", "o", "grin"][int(t * 2.0) % 3]
					p["eyes"] = "side"
					p["look"] = Vector2(1 if int(t * 2.0) % 2 == 0 else -1, 0)
				"mochi":
					var yawn := fposmod(t + seed * 0.3, 2.4) < 0.9
					p["mouth"] = "yawn" if yawn else "smile"
					p["eyes"] = "closed" if yawn else "sleepy"
				_:
					p["mouth"] = "flat"
		SURPRISED:
			var k := clampf(age / 0.25, 0.0, 1.0)
			p["dy"] = -sin(k * PI) * 0.1
			p["eyes"] = "wide"
			p["mouth"] = "o"
			p["arms"] = "up"
			p["sweat"] = body == "zip"
		FAILED:
			_failed(p, body, age, t, seed)
		DELIVERED:
			var k := clampf(age / DELIVER, 0.0, 1.0)
			p["eyes"] = "happy"
			p["mouth"] = "grin"
			match body:
				"bloop":
					p["dy"] = -sin(k * PI) * 0.3
					p["arms"] = "up"
				"zip":
					p["mouth"] = "smile"
					p["dy"] = sin(k * PI) * 0.04
				"glitch":
					p["rot"] = k * TAU
				"mochi":
					p["dy"] = -absf(sin(k * PI * 2.0)) * 0.12
					p["sy"] = 1.0 - 0.1 * sin(k * PI * 2.0)
				_:
					p["dy"] = -sin(k * PI) * 0.15
		CELEBRATING:
			var bounce: float = ctx.get("bounce", 1.0)
			var period := 0.45
			var ph := fposmod(age + seed * 0.07, period) / period
			p["dy"] = -absf(sin(ph * PI)) * 0.14 * bounce
			p["sy"] = 1.0 + 0.06 * cos(ph * TAU)
			p["sx"] = 1.0 - 0.05 * cos(ph * TAU)
			p["eyes"] = "star" if ctx.get("starry", false) else "happy"
			p["mouth"] = "grin"
			p["arms"] = "up" if ph < 0.5 else "wave"
			if body == "glitch" and ctx.get("perfect", false):
				p["rot"] = fposmod(age, 0.9) / 0.9 * TAU
	if not motion:
		_freeze(p, body, state)
	return p


static func _idle(p: Dictionary, body: String, t: float, seed: int) -> void:
	var step := int((t + seed * 0.61) / 1.6)
	var n := noise(seed, step)
	p["dy"] = sin(t * 2.0 + seed) * 0.012
	match body:
		"bloop":
			p["brows"] = "confident"
			p["mouth"] = "smirk"
			p["look"] = Vector2(-1, 0) if n < 0.33 else (Vector2(1, 0) if n < 0.66 else Vector2.ZERO)
			p["eyes"] = "closed" if _blinking(t, seed, 3.4) else "open"
		"zip":
			p["brows"] = "worried"
			p["mouth"] = "wobble"
			var j := noise(seed, int(t / 0.6))
			p["look"] = Vector2(cos(j * TAU), sin(j * TAU) * 0.5)
			p["eyes"] = "closed" if _blinking(t, seed, 2.6) else "open"
		"glitch":
			p["mouth"] = "smile"
			p["eyes"] = "confused" if n > 0.8 else "open"
			p["look"] = Vector2(cos(t * 2.3 + seed), sin(t * 1.7 + seed))
		"mochi":
			p["mouth"] = "smile"
			p["eyes"] = "closed" if _blinking(t, seed, 2.2, 0.4) else "sleepy"
			p["z"] = n > 0.7
		_:
			p["eyes"] = "closed" if _blinking(t, seed, 3.0) else "open"


static func _failed(p: Dictionary, body: String, age: float, t: float, seed: int) -> void:
	var early := age < FAIL
	p["mouth"] = "flat"
	match body:
		"bloop":
			if early:
				p["eyes"] = "wide"
				p["mouth"] = "o"
				p["dy"] = -sin(age / FAIL * PI) * 0.08
			else:
				# Pretends nothing happened.
				p["eyes"] = "side"
				p["look"] = Vector2(1, -0.3)
				p["brows"] = "confident"
				p["mouth"] = "whistle"
		"zip":
			p["eyes"] = "wide"
			p["mouth"] = "wobble"
			p["sweat"] = true
			p["arms"] = "up"
			p["dx"] = sin(t * 50.0 + seed) * (0.03 if early else 0.012)
		"glitch":
			p["eyes"] = "confused"
			p["rot"] = 0.15
			p["ghost"] = 0.4 if early else 0.0
		"mochi":
			p["eyes"] = "sleepy"
			p["rot"] = -0.12
		_:
			p["eyes"] = "confused"
			p["rot"] = 0.1


## Reduced motion / animations off: keep the expression (it carries meaning) but drop every
## movement, wobble, blink and glitch effect.
static func _freeze(p: Dictionary, body: String, state: int) -> void:
	p["dx"] = 0.0
	p["dy"] = 0.0
	p["sx"] = 1.0
	p["sy"] = 1.0
	p["rot"] = 0.0
	p["foot"] = 0.0
	p["ghost"] = 0.0
	p["z"] = false
	if p["eyes"] == "closed":
		p["eyes"] = "sleepy" if body == "mochi" else "open"
	if p["mouth"] == "yawn":
		p["mouth"] = "smile"
	if state == IDLE:
		p["look"] = Vector2.ZERO
		if body == "glitch":
			p["eyes"] = "open"
	elif state == WAITING and body == "glitch":
		p["mouth"] = "tongue"
		p["look"] = Vector2.ZERO
	elif state == CELEBRATING:
		p["arms"] = "up"
