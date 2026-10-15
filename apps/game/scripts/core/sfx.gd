extends Node
## Autoload "Sfx": original sound effects and an ambient music loop, all synthesised at runtime
## (no audio assets to license or download), plus haptic patterns. Sound effects, music and
## haptics have independent settings (`sfx`, `music`, `haptics`).

const RATE := 22050
const MUSIC_RATE := 11025
const MUSIC_DB := -17.0
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _music_ready := false
var _music_task := -1
var _music_stream: AudioStreamWAV
var _last_play := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = MUSIC_DB
	add_child(_music)
	# Tap: tiny wooden click. Rotate: soft mechanical "tick-clack" (noise transient + low body).
	_streams["tap"] = _tone([[880.0, 0.03]], 0.18, 70.0, 0.12)
	_streams["rotate"] = _clack(420.0, 0.22)
	_streams["ccw"] = _clack(360.0, 0.22)
	_streams["locked"] = _tone([[196.0, 0.08]], 0.22, 30.0, 0.05)
	_streams["step"] = _tone([[1400.0, 0.018]], 0.05, 120.0, 0.05)
	_streams["deliver"] = _tone([[1046.5, 0.07], [1318.5, 0.15]], 0.26, 14.0, 0.0)
	_streams["fail"] = _sweep(330.0, 170.0, 0.26, 0.2, true)
	_streams["win"] = _tone([[523.25, 0.08], [659.25, 0.08], [783.99, 0.08], [1046.5, 0.3]], 0.25, 9.0, 0.0)
	_streams["perfect"] = _tone([[659.25, 0.07], [783.99, 0.07], [1046.5, 0.07], [1318.5, 0.07], [1567.98, 0.34]], 0.24, 8.0, 0.0)
	_streams["run"] = _sweep(300.0, 700.0, 0.16, 0.14)
	_streams["ui"] = _tone([[660.0, 0.035]], 0.16, 50.0, 0.0)
	_streams["unlock"] = _tone([[783.99, 0.08], [1174.66, 0.22]], 0.24, 11.0, 0.0)
	_streams["hint"] = _tone([[987.77, 0.06], [1318.5, 0.12]], 0.16, 16.0, 0.0)
	_streams["star"] = _tone([[1318.5, 0.12]], 0.16, 18.0, 0.0)
	if Game.state != null:
		Game.settings_changed.connect(_apply_music)
	_apply_music.call_deferred()


func play(name: String, pitch := 1.0) -> void:
	if Game.state == null or not Game.settings().get("sfx", true):
		return
	if not _streams.has(name):
		return
	# The same sound twice within 25 ms (e.g. two deliveries in one frame) just sounds louder.
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(name, -1000)) < 25:
		return
	_last_play[name] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.pitch_scale = pitch
	p.play()


## Haptic patterns: "light" (touch), "tick" (rotation), "medium" (delivery), "warn" (locked tile /
## failure), "success" (two pulses). Vibration is a no-op on desktop.
func haptic_pattern(kind: String) -> void:
	match kind:
		"light":
			haptic(6)
		"tick":
			haptic(10)
		"medium":
			haptic(16)
		"warn":
			haptic(35)
		"success":
			haptic(18)
			get_tree().create_timer(0.09).timeout.connect(func(): haptic(30))


func haptic(ms := 12) -> void:
	if Game.state == null or not Game.settings().get("haptics", true):
		return
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# --- music --------------------------------------------------------------------------------

func _apply_music() -> void:
	var want: bool = Game.state != null and bool(Game.settings().get("music", true))
	if not want:
		if _music.playing:
			_music.stop()
		return
	if _music_ready:
		if not _music.playing:
			_music.stream = _music_stream
			_music.play()
		return
	if _music_task == -1 and DisplayServer.get_name() != "headless":
		# ~16 s of audio is generated on a worker thread so startup is never blocked.
		_music_task = WorkerThreadPool.add_task(_build_music)
		set_process(true)


func _process(_d: float) -> void:
	if _music_task != -1 and WorkerThreadPool.is_task_completed(_music_task):
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1
		_music_ready = true
		set_process(false)
		_apply_music()


func _exit_tree() -> void:
	if _music_task != -1:
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1


func music_playing() -> bool:
	return _music.playing


## Gentle pad (Cmaj7 – Am7 – Fmaj7 – G6, 4 s each) with a sparse pentatonic pluck. Chord weights are
## cos² windows on a circular timeline, so the loop point is seamless.
func _build_music() -> void:
	var chords := [[261.63, 329.63, 392.0, 493.88], [220.0, 261.63, 329.63, 392.0], [174.61, 220.0, 261.63, 329.63], [196.0, 246.94, 293.66, 329.63]]
	var seg := 4.0
	var length := seg * chords.size()
	var n := int(MUSIC_RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var pluck_notes := [523.25, 587.33, 659.25, 783.99, 880.0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var plucks: Array = []
	var t0 := 0.5
	while t0 < length - 0.5:
		plucks.append([t0, pluck_notes[rng.randi() % pluck_notes.size()]])
		t0 += [1.0, 1.5, 2.0][rng.randi() % 3]
	for i in n:
		var t := float(i) / MUSIC_RATE
		var v := 0.0
		for c in chords.size():
			var centre := (c + 0.5) * seg
			var d := fposmod(t - centre + length / 2.0, length) - length / 2.0
			if absf(d) >= seg:
				continue
			var w := cos(d / seg * PI / 2.0)
			w *= w
			for f in chords[c]:
				v += sin(TAU * f * t) * 0.05 * w + sin(TAU * f * 0.5 * t) * 0.025 * w
		for p in plucks:
			var dt: float = t - p[0]
			if dt >= 0.0 and dt < 1.2:
				v += sin(TAU * p[1] * t) * exp(-dt * 4.0) * 0.06
		out[i] = v * (0.85 + 0.15 * sin(TAU * t / length))
	var s := _wav(out, MUSIC_RATE)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = n
	_music_stream = s


# --- synthesis ----------------------------------------------------------------------------

func _wav(samples: PackedFloat32Array, rate := RATE) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
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


## Two-part mechanical click: a bright noise "tick" then a short damped low "clack" 35 ms later.
func _clack(body_hz: float, volume: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var count := int(RATE * 0.09)
	for i in count:
		var t := float(i) / RATE
		var v := 0.0
		if t < 0.006:
			v += rng.randf_range(-1.0, 1.0) * (1.0 - t / 0.006) * 0.6
		var t2 := t - 0.035
		if t2 >= 0.0:
			v += sin(TAU * body_hz * t2) * exp(-t2 * 70.0) * 0.9
			if t2 < 0.004:
				v += rng.randf_range(-1.0, 1.0) * 0.35
		out.append(v * volume)
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
