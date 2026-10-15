extends Node
## Autoload "Sfx": original sound effects synthesized at startup (no audio assets to license or
## download) plus optional haptics. Respects the sfx/haptics settings.

const RATE := 22050
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_streams["tap"] = _tone([[880.0, 0.035]], 0.25, 60.0, 0.15)
	_streams["rotate"] = _sweep(620.0, 480.0, 0.07, 0.22)
	_streams["ccw"] = _sweep(480.0, 620.0, 0.07, 0.22)
	_streams["deliver"] = _tone([[1046.5, 0.09], [1318.5, 0.16]], 0.28, 14.0, 0.0)
	_streams["fail"] = _sweep(330.0, 150.0, 0.32, 0.25, true)
	_streams["win"] = _tone([[523.25, 0.09], [659.25, 0.09], [783.99, 0.09], [1046.5, 0.26]], 0.26, 10.0, 0.0)
	_streams["run"] = _sweep(300.0, 700.0, 0.16, 0.16)
	_streams["ui"] = _tone([[660.0, 0.04]], 0.2, 45.0, 0.0)
	_streams["unlock"] = _tone([[783.99, 0.08], [1174.66, 0.2]], 0.24, 12.0, 0.0)


func play(name: String, pitch := 1.0) -> void:
	if Game.state == null or not Game.settings().get("sfx", true):
		return
	if not _streams.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.pitch_scale = pitch
	p.play()


func haptic(ms := 12) -> void:
	if Game.state == null or not Game.settings().get("haptics", true):
		return
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# --- synthesis ----------------------------------------------------------------------------

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	return s


## Sequence of [freq, duration] notes with exponential decay; `noise` adds a click transient.
func _tone(notes: Array, volume: float, decay: float, noise: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for n in notes:
		var freq: float = n[0]
		var count := int(RATE * float(n[1]))
		for i in count:
			var t := float(i) / RATE
			var env := exp(-t * decay) * minf(1.0, t * 400.0)
			var v := sin(TAU * freq * t) * 0.8 + sin(TAU * freq * 2.0 * t) * 0.15
			if noise > 0.0 and t < 0.01:
				v += rng.randf_range(-1.0, 1.0) * noise
			out.append(v * env * volume)
	return _wav(out)


func _sweep(f0: float, f1: float, dur: float, volume: float, triangle := false) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var count := int(RATE * dur)
	var phase := 0.0
	for i in count:
		var k := float(i) / count
		var f := lerpf(f0, f1, k)
		phase += TAU * f / RATE
		var v := (asin(sin(phase)) * 2.0 / PI) if triangle else sin(phase)
		var env := sin(PI * k) * (1.0 - k * 0.3)
		out.append(v * env * volume)
	return _wav(out)
