class_name LFBoardView
extends Control
## Renders a board, handles tap (clockwise) / long-press (counter-clockwise) input, animates tile
## rotation, and plays back simulation frames. All game rules live in the engine; this node only
## interpolates between deterministic frames, so frame rate never changes the outcome.

signal rotate_requested(index: int, dir: int)
signal locked_tapped(index: int)
signal playback_finished(result: Dictionary)
signal package_delivered(cell: int)

const LONG_PRESS := 0.42
const ROT_SPEED := 16.0  # visual smoothing factor

var level: Dictionary = {}
var rotations: Array = []
var interactive := true
var reduced_motion := false
var colorblind := false

var _w := 0
var _h := 0
var _cell := 0.0
var _origin := Vector2.ZERO
var _vis_turns: Array = []   # target quarter-turns (unbounded ints)
var _vis_angle: Array = []   # current visual angle in quarter-turns (float)
var _press_scale: Array = []
var _bump: Array = []        # small pulse on rotation / locked feedback
var _press_index := -1
var _press_time := 0.0
var _press_fired := false
var _time := 0.0

# playback
var _frames: Array = []
var _result: Dictionary = {}
var _frame_i := 0
var _frame_t := 0.0
var step_time := 0.3
var paused := false
var playing := false
var _flashes: Array = []     # [{cell, t, color, kind}]
var _particles: Array = []   # [{p, v, t, color}]
var _fail_cell := -1
var _src_remaining := {}

# hint
var hint_tile := -1
var hint_dir := 1
var hint_taps := 0
var tutorial_tile := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout)


func set_level(lvl: Dictionary, rots: Array) -> void:
	level = lvl
	_w = lvl["width"]
	_h = lvl["height"]
	rotations = rots.duplicate()
	var n: int = lvl["tiles"].size()
	_vis_turns = rotations.duplicate()
	_vis_angle = []
	_press_scale = []
	_bump = []
	for i in n:
		_vis_angle.append(float(rotations[i]))
		_press_scale.append(1.0)
		_bump.append(0.0)
	stop_playback()
	_layout()


## Called after the model changed rotation of `index` by `dir` (also used for undo with -dir).
func animate_rotation(index: int, dir: int) -> void:
	rotations[index] = (int(rotations[index]) + dir + 4) & 3
	_vis_turns[index] = int(_vis_turns[index]) + dir
	if reduced_motion:
		_vis_angle[index] = float(_vis_turns[index])
	_bump[index] = 1.0
	if index == hint_tile:
		hint_taps -= 1
		if hint_taps <= 0:
			hint_tile = -1
	queue_redraw()


## Jump all tiles to new rotations (reset / resume), animating along the shortest way.
func sync_rotations(rots: Array) -> void:
	for i in rots.size():
		var diff := (int(rots[i]) - int(rotations[i]) + 4) % 4
		if diff == 3:
			diff = -1
		_vis_turns[i] = int(_vis_turns[i]) + diff
		if reduced_motion:
			_vis_angle[i] = float(_vis_turns[i])
	rotations = rots.duplicate()
	hint_tile = -1
	queue_redraw()


func show_hint(tile: int, dir: int, taps: int) -> void:
	hint_tile = tile
	hint_dir = dir
	hint_taps = taps
	queue_redraw()


func _layout() -> void:
	if _w == 0:
		return
	_cell = floorf(minf(size.x / _w, size.y / _h))
	_origin = (size - Vector2(_cell * _w, _cell * _h)) / 2.0
	queue_redraw()


func cell_center(i: int) -> Vector2:
	return _origin + Vector2((i % _w + 0.5) * _cell, (i / _w + 0.5) * _cell)


func cell_rect_global(i: int) -> Rect2:
	var c := cell_center(i) + global_position
	return Rect2(c - Vector2(_cell, _cell) / 2.0, Vector2(_cell, _cell))


func _cell_at(pos: Vector2) -> int:
	var p := pos - _origin
	if p.x < 0 or p.y < 0:
		return -1
	var x := int(p.x / _cell)
	var y := int(p.y / _cell)
	if x >= _w or y >= _h:
		return -1
	return y * _w + x


# ------------------------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		var i := _cell_at(event.position)
		if i < 0 or not interactive:
			return
		_press_index = i
		_press_time = 0.0
		_press_fired = false
		if LFTiles.is_rotatable(level["tiles"][i]):
			_press_scale[i] = 0.92
			Sfx.play("tap", 1.0 + randf() * 0.08)
		queue_redraw()
		accept_event()
	else:
		if _press_index >= 0:
			var i := _press_index
			_press_index = -1
			_press_scale[i] = 1.0
			if not _press_fired and interactive and _cell_at(event.position) == i:
				_activate(i, 1)
			queue_redraw()
			accept_event()


func _activate(i: int, dir: int) -> void:
	if LFTiles.is_rotatable(level["tiles"][i]):
		rotate_requested.emit(i, dir)
	else:
		_bump[i] = 0.6
		locked_tapped.emit(i)


# ------------------------------------------------------------------------------- playback

func start_playback(result: Dictionary, p_step_time: float) -> void:
	_frames = result["frames"]
	_result = result
	_frame_i = 0
	_frame_t = 0.0
	step_time = p_step_time
	paused = false
	playing = true
	_fail_cell = -1
	_src_remaining = {}
	for i in level["tiles"].size():
		var t: Dictionary = level["tiles"][i]
		if t["t"] == "source":
			_src_remaining[i] = int(t.get("n", 1))
	_count_spawns(0)
	queue_redraw()


func stop_playback() -> void:
	playing = false
	_frames = []
	_fail_cell = -1
	_flashes.clear()
	_src_remaining = {}
	queue_redraw()


func _count_spawns(fi: int) -> void:
	for p in _frames[fi]["packages"]:
		if p["state"] == "spawned":
			var cell: int = p["cell"]
			if _src_remaining.has(cell):
				_src_remaining[cell] = maxi(0, _src_remaining[cell] - 1)


func _advance_frame() -> void:
	_frame_i += 1
	_count_spawns(_frame_i)
	var f: Dictionary = _frames[_frame_i]
	for p in f["packages"]:
		match p["state"]:
			"delivered":
				_flashes.append({"cell": p["cell"], "t": 0.0, "color": LFStyle.PACKAGE[p["color"]], "kind": "deliver"})
				_burst(cell_center(p["cell"]), LFStyle.PACKAGE[p["color"]])
				package_delivered.emit(p["cell"])
			"crashed":
				var c = _result.get("failureCell")
				_fail_cell = c if c != null else -1
	if _frame_i >= _frames.size() - 1:
		if not _result["success"]:
			var cell = _result.get("failureCell")
			if cell == null:
				cell = _result.get("failurePackage")  # off-board: highlight nothing specific
				cell = -1
			_fail_cell = cell


func _burst(at: Vector2, color: Color) -> void:
	if reduced_motion:
		return
	for k in 10:
		var a := k * TAU / 10.0 + randf() * 0.3
		_particles.append({"p": at, "v": Vector2(cos(a), sin(a)) * _cell * (1.6 + randf()), "t": 0.0, "color": color})


func _process(delta: float) -> void:
	_time += delta
	var dirty := false
	# Long press => counter-clockwise
	if _press_index >= 0 and not _press_fired:
		_press_time += delta
		if _press_time >= LONG_PRESS:
			_press_fired = true
			_press_scale[_press_index] = 1.0
			Sfx.haptic(20)
			_activate(_press_index, -1)
	for i in _vis_angle.size():
		var target := float(_vis_turns[i])
		if absf(_vis_angle[i] - target) > 0.001:
			_vis_angle[i] = lerpf(_vis_angle[i], target, minf(1.0, delta * ROT_SPEED))
			if absf(_vis_angle[i] - target) < 0.002:
				_vis_angle[i] = target
			dirty = true
		if _bump[i] > 0.0:
			_bump[i] = maxf(0.0, _bump[i] - delta * 5.0)
			dirty = true
	if playing:
		dirty = true
		if not paused and _frame_i < _frames.size() - 1:
			_frame_t += delta / step_time
			while _frame_t >= 1.0 and _frame_i < _frames.size() - 1:
				_frame_t -= 1.0
				_advance_frame()
			if _frame_i >= _frames.size() - 1:
				_frame_t = 0.0
				playing = false
				queue_redraw()
				var res := _result
				get_tree().create_timer(0.45 if not reduced_motion else 0.1).timeout.connect(func(): playback_finished.emit(res))
	for f in _flashes:
		f["t"] += delta
	_flashes = _flashes.filter(func(f): return f["t"] < 0.7)
	for p in _particles:
		p["t"] += delta
		p["p"] += p["v"] * delta
		p["v"] *= 0.9
	_particles = _particles.filter(func(p): return p["t"] < 0.6)
	if not _flashes.is_empty() or not _particles.is_empty() or hint_tile >= 0 or tutorial_tile >= 0 or _fail_cell >= 0:
		dirty = true
	if dirty:
		queue_redraw()


# ------------------------------------------------------------------------------- drawing

func _draw() -> void:
	if _w == 0 or _cell < 8.0:
		return
	var gap := maxf(3.0, _cell * 0.05)
	var tiles: Array = level["tiles"]
	# Board plate
	var plate := Rect2(_origin - Vector2(gap, gap) * 2, Vector2(_cell * _w, _cell * _h) + Vector2(gap, gap) * 4)
	draw_style_box(LFStyle.box(LFStyle.SURFACE_2, int(_cell * 0.22), false), plate)
	for i in tiles.size():
		_draw_tile(i, tiles[i], gap)
	if playing or not _frames.is_empty():
		_draw_packages()
	for f in _flashes:
		var k: float = f["t"] / 0.7
		var col: Color = f["color"]
		col.a = 1.0 - k
		draw_arc(cell_center(f["cell"]), _cell * (0.3 + k * 0.5), 0, TAU, 32, col, _cell * 0.06 * (1.0 - k) + 1.0, true)
	for p in _particles:
		var col: Color = p["color"]
		col.a = 1.0 - p["t"] / 0.6
		draw_rect(Rect2(p["p"] - Vector2(3, 3) * (_cell / 60.0), Vector2(6, 6) * (_cell / 60.0)), col)
	if _fail_cell >= 0:
		var pulse := 0.5 + 0.5 * sin(_time * 10.0)
		var rc := Rect2(cell_center(_fail_cell) - Vector2(_cell, _cell) * 0.46, Vector2(_cell, _cell) * 0.92)
		draw_style_box(LFStyle.box(Color(0, 0, 0, 0), int(_cell * 0.16), false, Color(LFStyle.ERROR, 0.6 + 0.4 * pulse), int(maxf(3.0, _cell * 0.06))), rc)
	if hint_tile >= 0:
		_draw_hint(hint_tile, hint_dir, hint_taps)
	if tutorial_tile >= 0:
		_draw_tutorial(tutorial_tile)


func _draw_tile(i: int, t: Dictionary, gap: float) -> void:
	var c := cell_center(i)
	var s := _cell - gap * 2
	var kind: String = t["t"]
	var sc: float = _press_scale[i] * (1.0 + 0.05 * sin(_bump[i] * PI))
	var r := Rect2(c - Vector2(s, s) * sc / 2.0, Vector2(s, s) * sc)
	var radius := int(s * 0.18)
	match kind:
		"empty":
			draw_circle(c, s * 0.04, Color(LFStyle.TEXT_MUTED, 0.25))
			return
		"blocked":
			draw_style_box(LFStyle.box(LFStyle.BLOCKED, radius, false), r)
			for k in 3:
				var o := (k - 1) * s * 0.22
				draw_line(c + Vector2(o - s * 0.15, s * 0.15), c + Vector2(o + s * 0.15, -s * 0.15), Color(LFStyle.TEXT, 0.08), s * 0.05, true)
			return
	var rotatable := LFTiles.is_rotatable(t)
	var bg := LFStyle.SURFACE if rotatable else LFStyle.SURFACE.darkened(0.035)
	draw_style_box(LFStyle.box(bg, radius, true), r)
	var half := s * sc / 2.0
	var bw := s * sc * 0.34
	var angle := float(_vis_angle[i]) * PI / 2.0
	match kind:
		"source":
			_draw_source(i, t, c, half, bw)
		"dest":
			_draw_dest(t, c, half)
		_:
			draw_set_transform(c, angle, Vector2.ONE)
			_draw_belt(kind, half, bw)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if t.get("l", false):
				# Pin marking a locked belt.
				draw_circle(c + Vector2(-half * 0.68, -half * 0.68), s * 0.075, LFStyle.TEXT_MUTED)
				draw_circle(c + Vector2(-half * 0.68, -half * 0.68), s * 0.035, LFStyle.SURFACE)


func _belt_stripes(from: Vector2, to: Vector2, bw: float) -> void:
	var dirv := (to - from)
	var length := dirv.length()
	if length < 1.0 or bw < 2.0:
		return
	var n := dirv / length
	var perp := Vector2(-n.y, n.x) * bw * 0.32
	var spacing := bw * 0.55
	var offset := fmod(_time * bw * 1.4, spacing) if playing and not paused and not reduced_motion else 0.0
	var d := offset + spacing * 0.5
	while d < length:
		var p := from + n * d
		draw_line(p - perp, p + perp, LFStyle.BELT_EDGE, maxf(2.0, bw * 0.09), true)
		d += spacing


## Draws the belt in its base orientation (r = 0) in local coordinates centred on the tile.
func _draw_belt(kind: String, half: float, bw: float) -> void:
	var col := LFStyle.BELT
	match kind:
		"straight":
			draw_rect(Rect2(Vector2(-bw / 2, -half), Vector2(bw, half * 2)), col)
			_belt_stripes(Vector2(0, -half), Vector2(0, half), bw)
		"corner":
			# Quarter ring centred on the top-right corner, joining N and E edge midpoints.
			draw_arc(Vector2(half, -half), half, PI * 0.5, PI, 24, col, bw, true)
			for k in 3:
				var a := PI * 0.5 + (k + 0.5) * PI * 0.5 / 3.0
				var dv := Vector2(cos(a), sin(a))
				draw_line(Vector2(half, -half) + dv * (half - bw * 0.32), Vector2(half, -half) + dv * (half + bw * 0.32), LFStyle.BELT_EDGE, maxf(2.0, bw * 0.09), true)
		"tee":
			draw_rect(Rect2(Vector2(-bw / 2, -half), Vector2(bw, half * 2)), col)
			draw_rect(Rect2(Vector2(0, -bw / 2), Vector2(half, bw)), col)
			_belt_stripes(Vector2(0, -half), Vector2(0, half), bw)
			_belt_stripes(Vector2(bw / 2, 0), Vector2(half, 0), bw)
		"cross":
			draw_rect(Rect2(Vector2(-half, -bw / 2), Vector2(half * 2, bw)), col)
			_belt_stripes(Vector2(-half, 0), Vector2(half, 0), bw)
			# Overpass: vertical belt drawn on top with a soft outline.
			draw_rect(Rect2(Vector2(-bw / 2 - 3, -half), Vector2(bw + 6, half * 2)), LFStyle.SURFACE)
			draw_rect(Rect2(Vector2(-bw / 2, -half), Vector2(bw, half * 2)), col.darkened(0.04))
			_belt_stripes(Vector2(0, -half), Vector2(0, half), bw)


func _draw_source(i: int, t: Dictionary, c: Vector2, half: float, bw: float) -> void:
	var color: Color = LFStyle.PACKAGE[int(t.get("c", 0))]
	var dir: int = int(rotations[i])
	var dv := Vector2(LFTiles.DX[dir], LFTiles.DY[dir])
	# Output belt stub toward the exit edge
	var perp := Vector2(-dv.y, dv.x)
	draw_colored_polygon(PackedVector2Array([c + perp * bw / 2, c + perp * bw / 2 + dv * half, c - perp * bw / 2 + dv * half, c - perp * bw / 2]), LFStyle.BELT)
	draw_style_box(LFStyle.box(color, int(half * 0.35), false), Rect2(c - Vector2(half, half) * 0.62, Vector2(half, half) * 1.24))
	var tip := c + dv * half * 0.48
	draw_colored_polygon(PackedVector2Array([tip, c + perp * half * 0.3 + dv * half * 0.05, c - perp * half * 0.3 + dv * half * 0.05]), Color.WHITE)
	if colorblind:
		LFStyle.draw_symbol(self, LFStyle.SYMBOLS[int(t.get("c", 0))], c - dv * half * 0.22, half * 0.14, Color(1, 1, 1, 0.9))
	var n: int = _src_remaining.get(i, int(t.get("n", 1))) if playing or not _frames.is_empty() else int(t.get("n", 1))
	if int(t.get("n", 1)) > 1:
		var bc := c + Vector2(half * 0.62, half * 0.62)
		draw_circle(bc, half * 0.28, LFStyle.TEXT)
		var f := LFStyle.font(800)
		var fs := int(half * 0.36)
		var txt := str(n)
		var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(f, bc + Vector2(-sz.x / 2, sz.y * 0.32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_dest(t: Dictionary, c: Vector2, half: float) -> void:
	var color: Color = LFStyle.PACKAGE[int(t.get("c", 0))]
	draw_circle(c, half * 0.7, Color(color, 0.18))
	draw_arc(c, half * 0.62, 0, TAU, 40, color, half * 0.16, true)
	if colorblind:
		LFStyle.draw_symbol(self, LFStyle.SYMBOLS[int(t.get("c", 0))], c, half * 0.2, color)
	else:
		draw_circle(c, half * 0.16, color)


func _pkg_pos(cell: int) -> Vector2:
	return cell_center(cell)


func _draw_packages() -> void:
	if _frames.is_empty():
		return
	var cur: Dictionary = _frames[_frame_i]
	var nxt: Dictionary = _frames[mini(_frame_i + 1, _frames.size() - 1)]
	var t := clampf(_frame_t, 0.0, 1.0)
	var e := t * t * (3.0 - 2.0 * t)  # smoothstep for a gentle conveyor feel
	var prev_pos := {}
	for p in cur["packages"]:
		if p["state"] != "delivered" and p["state"] != "crashed":
			prev_pos[p["id"]] = p["cell"]
	var size_px := _cell * 0.36
	var animating := _frame_i < _frames.size() - 1
	var list: Array = nxt["packages"] if animating else cur["packages"]
	for p in list:
		var color: Color = LFStyle.PACKAGE[p["color"]]
		var to := _pkg_pos(p["cell"])
		var pos := to
		var scale := 1.0
		var alpha := 1.0
		var state: String = p["state"]
		if not animating:
			if state == "delivered":
				continue
			if state == "crashed":
				var shake := sin(_time * 40.0) * _cell * 0.03
				pos = _pkg_pos(p["cell"]) + Vector2(p.get("toX", 0) - p["cell"] % _w, p.get("toY", 0) - p["cell"] / _w) * _cell * 0.4 + Vector2(shake, 0)
				color = color.lerp(LFStyle.ERROR, 0.4)
		elif state == "spawned":
			scale = e
		elif prev_pos.has(p["id"]):
			var from := _pkg_pos(prev_pos[p["id"]])
			if state == "crashed":
				var target := _pkg_pos(p["cell"]) + Vector2(p.get("toX", 0) - p["cell"] % _w, p.get("toY", 0) - p["cell"] / _w) * _cell * 0.4
				pos = from.lerp(target, e)
				color = color.lerp(LFStyle.ERROR, e * 0.4)
			else:
				pos = from.lerp(to, e)
			if state == "delivered":
				scale = 1.0 - e * 0.7
				alpha = 1.0 - e * 0.6
		var rect := Rect2(pos - Vector2(size_px, size_px) * scale / 2.0, Vector2(size_px, size_px) * scale)
		draw_rect(Rect2(rect.position + Vector2(0, size_px * 0.08), rect.size), Color(0, 0, 0, 0.12 * alpha))
		draw_style_box(LFStyle.box(Color(color, alpha), int(size_px * 0.22 * scale), false, color.darkened(0.25), int(maxf(1.0, size_px * 0.06))), rect)
		# Packing tape
		draw_line(rect.position + Vector2(rect.size.x / 2, 0), rect.position + Vector2(rect.size.x / 2, rect.size.y), Color(1, 1, 1, 0.45 * alpha), maxf(1.5, size_px * 0.1))
		if colorblind:
			LFStyle.draw_symbol(self, LFStyle.SYMBOLS[p["color"]], pos, size_px * 0.17 * scale, Color(1, 1, 1, alpha))


func _draw_hint(i: int, dir: int, taps: int) -> void:
	var c := cell_center(i)
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	draw_arc(c, _cell * (0.48 + 0.03 * pulse), 0, TAU, 40, Color(LFStyle.ACCENT, 0.7 + 0.3 * pulse), maxf(3.0, _cell * 0.06), true)
	var badge := c + Vector2(_cell * 0.36, -_cell * 0.36)
	draw_circle(badge, _cell * 0.17, LFStyle.ACCENT)
	LFIcons.draw_icon(self, "rotate_cw" if dir == 1 else "rotate_ccw", Rect2(badge - Vector2(_cell, _cell) * 0.17, Vector2(_cell, _cell) * 0.34), LFStyle.TEXT)
	if taps > 1:
		var f := LFStyle.font(800)
		draw_string(f, badge + Vector2(_cell * 0.12, _cell * 0.2), "×%d" % taps, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_cell * 0.16), LFStyle.TEXT)


func _draw_tutorial(i: int) -> void:
	var c := cell_center(i)
	var k := fmod(_time, 1.4) / 1.4
	draw_arc(c, _cell * (0.2 + k * 0.35), 0, TAU, 32, Color(LFStyle.PRIMARY, 1.0 - k), maxf(3.0, _cell * 0.05), true)
	# Finger
	var tip := c + Vector2(_cell * 0.12, _cell * 0.12) + Vector2(0, sin(_time * 5.0) * _cell * 0.03)
	draw_circle(tip + Vector2(_cell * 0.1, _cell * 0.16), _cell * 0.13, Color(LFStyle.TEXT, 0.85))
	draw_rect(Rect2(tip + Vector2(0.02, 0) * _cell, Vector2(_cell * 0.11, _cell * 0.2)), Color(LFStyle.TEXT, 0.85))
