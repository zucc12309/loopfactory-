class_name LFBoardView
extends Control
## Renders a board, handles tap (clockwise) / long-press (counter-clockwise) input, animates tile
## rotation, and plays back simulation frames. All game rules live in the engine; this node only
## interpolates between deterministic frames, so frame rate never changes the outcome.
##
## Feel notes (see docs/game-feel.md):
##  * A touch reacts on the same frame: the tile sinks into its lip and pre-tilts clockwise.
##  * The logical rotation is applied instantly on release; the visual catches up with a
##    140 ms ease-out-back "snap". Rapid taps retarget from the current visual angle, so the view
##    can never fall behind or desynchronise from the model.
##  * Packages move at constant speed while travelling and only ease when starting or stopping.
##
## Rendering: every tile is its own CanvasItem (a base node plus a rotating belt node), so rotation,
## press, pop and intro animations are transforms that cost no redraw. A tile re-records its draw
## commands only when its appearance signature changes (glow, dock fill, rollers moving under a
## package...). The board itself draws the plate; an overlay node draws packages and effects.

signal rotate_requested(index: int, dir: int)
signal locked_tapped(index: int)
signal playback_finished(result: Dictionary)
signal package_delivered(cell: int)
signal celebration_finished

const LONG_PRESS := 0.38
const ROT_TIME := 0.14
const PRE_TILT := 0.06       # quarter-turns shown while a finger is down
const MAX_CELL := 168.0
const INTRO_TIME := 0.38


class TileNode extends Node2D:
	var board: LFBoardView
	var i := 0
	var belt: Node2D
	var sig := -1

	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		board._draw_tile_base(self, i)
		board._frame_cost_us += Time.get_ticks_usec() - t0


class BeltNode extends Node2D:
	var board: LFBoardView
	var i := 0
	var sig := -1

	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		board._draw_tile_belt(self, i)
		board._frame_cost_us += Time.get_ticks_usec() - t0


class OverlayNode extends Node2D:
	var board: LFBoardView

	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		board._draw_overlay(self)
		board._frame_cost_us += Time.get_ticks_usec() - t0


var level: Dictionary = {}
var rotations: Array = []
var interactive := true
var reduced_motion := false
var colorblind := false
var palette: Dictionary = LFWorlds.WORLDS[0]

var _w := 0
var _h := 0
var _cell := 0.0
var _gap := 3.0
var _origin := Vector2.ZERO
var _rot_from: Array = []    # visual angle in quarter-turns at animation start
var _rot_to: Array = []      # target visual angle (unbounded quarter-turns)
var _rot_t: Array = []       # 0..1 progress
var _tilt: Array = []
var _tilt_target: Array = []
var _press: Array = []       # 0..1 how far the tile is pushed into its lip
var _pop: Array = []         # commit pulse 1 -> 0
var _shake: Array = []       # locked-tile nudge 1 -> 0
var _press_index := -1
var _press_time := 0.0
var _press_fired := false
var _time := 0.0
var _intro := 1.0
var _sb_cache := {}
var sb_misses := 0
var _tiles: Array = []       # TileNode per cell
var _overlay: OverlayNode
## Per-frame CPU cost of this board (process + all of its draw callbacks), microseconds. Read by
## the QA tour and the benchmark; costs a few clock reads per frame.
var perf_samples: Array = []
var _frame_cost_us := 0

# playback
var _frames: Array = []
var _cells: Array = []       # per frame: {package id: cell}
var _result: Dictionary = {}
var _frame_i := 0
var _frame_t := 0.0
var step_time := 0.3
var paused := false
var playing := false
var _flashes: Array = []     # [{cell, t, color}]
var _particles: Array = []   # [{p, v, t, life, color, size}]
var _fail_cell := -1
var _fail_path: Array = []
var _src_remaining := {}
var _trail := {}             # cell -> {color: index, t}
var _trail_order: Array = []
var _dock_hits := {}         # cell -> time of last delivery

# celebration
var celebrating := false
var _cele_t := 0.0
var _cele_len := 1.2

# hints / onboarding
var hint_tile := -1
var hint_dir := 1
var hint_taps := 0
var hint_level := 3          # 1 = area, 2 = tile, 3 = tile + rotation
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
	_rot_from = []
	_rot_to = []
	_rot_t = []
	_tilt = []
	_tilt_target = []
	_press = []
	_pop = []
	_shake = []
	for i in n:
		_rot_from.append(float(rotations[i]))
		_rot_to.append(float(rotations[i]))
		_rot_t.append(1.0)
		_tilt.append(0.0)
		_tilt_target.append(0.0)
		_press.append(0.0)
		_pop.append(0.0)
		_shake.append(0.0)
	_intro = 1.0 if reduced_motion else 0.0
	_build_nodes()
	stop_playback()
	clear_failure()
	_layout()


func _build_nodes() -> void:
	for t in _tiles:
		t.queue_free()
	if _overlay != null:
		_overlay.queue_free()
	_tiles = []
	for i in level["tiles"].size():
		var tn := TileNode.new()
		tn.board = self
		tn.i = i
		add_child(tn)
		var kind: String = level["tiles"][i]["t"]
		if kind in ["straight", "corner", "tee", "cross"]:
			var bn := BeltNode.new()
			bn.board = self
			bn.i = i
			tn.add_child(bn)
			tn.belt = bn
		_tiles.append(tn)
	_overlay = OverlayNode.new()
	_overlay.board = self
	add_child(_overlay)


# ------------------------------------------------------------------------------- rotation

static func _ease_out_back(t: float) -> float:
	var c1 := 1.25
	var c3 := c1 + 1.0
	var u := t - 1.0
	return 1.0 + c3 * u * u * u + c1 * u * u


func _angle(i: int) -> float:
	var t: float = _rot_t[i]
	var base: float = _rot_to[i] if t >= 1.0 else lerpf(_rot_from[i], _rot_to[i], _ease_out_back(t))
	return base + float(_tilt[i])


## Called after the model changed rotation of `index` by `dir` (also used for undo with -dir).
func animate_rotation(index: int, dir: int) -> void:
	rotations[index] = (int(rotations[index]) + dir + 4) & 3
	var cur := _angle(index)
	_tilt[index] = 0.0
	_tilt_target[index] = 0.0
	_rot_from[index] = cur
	_rot_to[index] = float(_rot_to[index]) + dir
	_rot_t[index] = 1.0 if reduced_motion else 0.0
	_pop[index] = 0.0 if reduced_motion else 1.0
	if index == hint_tile:
		hint_taps -= 1
		if hint_taps <= 0 or hint_level < 3:
			hint_tile = -1
	_redraw_all()


## Jump all tiles to new rotations (reset / resume), animating along the shortest way.
func sync_rotations(rots: Array) -> void:
	for i in rots.size():
		var diff := (int(rots[i]) - int(rotations[i]) + 4) % 4
		if diff == 3:
			diff = -1
		if diff == 0:
			continue
		_rot_from[i] = _angle(i)
		_rot_to[i] = float(_rot_to[i]) + diff
		_rot_t[i] = 1.0 if reduced_motion else 0.0
	rotations = rots.duplicate()
	hint_tile = -1
	_redraw_all()


func show_hint(tile: int, dir: int, taps: int, p_level := 3) -> void:
	hint_tile = tile
	hint_dir = dir
	hint_taps = taps
	hint_level = p_level
	_redraw_all()


func clear_failure() -> void:
	_fail_cell = -1
	_fail_path = []
	_redraw_all()


## Visual angles in whole quarter-turns once animations settle (tests use this to prove the view
## converges to the model after any sequence of rapid taps).
func settled_rotations() -> Array:
	var out: Array = []
	for i in _rot_to.size():
		out.append(posmod(int(roundf(_rot_to[i])), 4))
	return out


func _layout() -> void:
	if _w == 0:
		return
	_cell = floorf(minf(minf(size.x / (_w + 0.3), size.y / (_h + 0.3)), MAX_CELL))
	_gap = maxf(3.0, _cell * 0.045)
	_origin = ((size - Vector2(_cell * _w, _cell * _h)) / 2.0).floor()
	_sb_cache.clear()
	_redraw_all()


func _redraw_all() -> void:
	for t in _tiles:
		t.sig = -1
		if t.belt != null:
			t.belt.sig = -1
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func cell_center(i: int) -> Vector2:
	return _origin + Vector2((i % _w + 0.5) * _cell, (i / _w + 0.5) * _cell)


func cell_rect_global(i: int) -> Rect2:
	var c := cell_center(i) + global_position
	return Rect2(c - Vector2(_cell, _cell) / 2.0, Vector2(_cell, _cell))


## Board rectangle in local coordinates (used by layout tests).
func board_rect() -> Rect2:
	return Rect2(_origin, Vector2(_cell * _w, _cell * _h))


func cell_size() -> float:
	return _cell


func _cell_at(pos: Vector2) -> int:
	var p := pos - _origin
	if p.x < 0 or p.y < 0 or _cell <= 0.0:
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
	if celebrating:
		if event.pressed:
			skip_celebration()
			accept_event()
		return
	if event.pressed:
		var i := _cell_at(event.position)
		if i < 0 or not interactive:
			return
		_press_index = i
		_press_time = 0.0
		_press_fired = false
		if LFTiles.is_rotatable(level["tiles"][i]):
			_tilt_target[i] = 0.0 if reduced_motion else PRE_TILT
			Sfx.play("tap", 1.0 + randf() * 0.08)
			Sfx.haptic(6)
		accept_event()
	else:
		if _press_index >= 0:
			var i := _press_index
			_press_index = -1
			_tilt_target[i] = 0.0
			if not _press_fired and interactive and _cell_at(event.position) == i:
				_activate(i, 1)
			accept_event()


func _activate(i: int, dir: int) -> void:
	if LFTiles.is_rotatable(level["tiles"][i]):
		rotate_requested.emit(i, dir)
	else:
		_shake[i] = 0.0 if reduced_motion else 1.0
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
	clear_failure()
	_trail = {}
	_trail_order = []
	_dock_hits = {}
	_src_remaining = {}
	_cells = []
	for f in _frames:
		var m := {}
		for p in f["packages"]:
			m[p["id"]] = p["cell"]
		_cells.append(m)
	for i in level["tiles"].size():
		var t: Dictionary = level["tiles"][i]
		if t["t"] == "source":
			_src_remaining[i] = int(t.get("n", 1))
	_count_spawns(0)
	_mark_trail(0)
	_redraw_all()


func stop_playback() -> void:
	playing = false
	celebrating = false
	_frames = []
	_cells = []
	_flashes.clear()
	_src_remaining = {}
	_trail = {}
	_trail_order = []
	_dock_hits = {}
	_redraw_all()


func _count_spawns(fi: int) -> void:
	for p in _frames[fi]["packages"]:
		if p["state"] == "spawned":
			var cell: int = p["cell"]
			if _src_remaining.has(cell):
				_src_remaining[cell] = maxi(0, _src_remaining[cell] - 1)


func _mark_trail(fi: int) -> void:
	for p in _frames[fi]["packages"]:
		if p["state"] == "crashed":
			continue
		var cell: int = p["cell"]
		if not _trail.has(cell):
			_trail_order.append(cell)
		_trail[cell] = {"color": int(p["color"]), "t": _time}


func _advance_frame() -> void:
	_frame_i += 1
	_count_spawns(_frame_i)
	_mark_trail(_frame_i)
	var f: Dictionary = _frames[_frame_i]
	for p in f["packages"]:
		if p["state"] == "delivered":
			var col: Color = LFStyle.PACKAGE[p["color"]]
			_flashes.append({"cell": p["cell"], "t": 0.0, "color": col})
			_dock_hits[p["cell"]] = _time
			_burst(cell_center(p["cell"]), col, 10)
			package_delivered.emit(p["cell"])
	if _frame_i >= _frames.size() - 1 and not _result["success"]:
		_compute_failure()


## Locate the failure: the reported cell, or (off-board) the package's last cell; plus the path the
## failing package travelled so the player can see where the route went wrong.
func _compute_failure() -> void:
	var pid = _result.get("failurePackage")
	var cell = _result.get("failureCell")
	_fail_path = []
	if pid != null:
		for m in _cells:
			if m.has(pid) and (_fail_path.is_empty() or _fail_path[-1] != m[pid]):
				_fail_path.append(m[pid])
		if cell == null and not _fail_path.is_empty():
			cell = _fail_path[-1]
	_fail_cell = int(cell) if cell != null else -1


## {reason, cell, color} for the last failed run, or {} if none.
func failure_info() -> Dictionary:
	if _result.is_empty() or _result["success"]:
		return {}
	var color := -1
	var pid = _result.get("failurePackage")
	if pid != null:
		for f in _frames:
			for p in f["packages"]:
				if p["id"] == pid:
					color = p["color"]
	return {"reason": str(_result.get("reason", "")), "cell": _fail_cell, "color": color}


func _burst(at: Vector2, color: Color, n: int, speed := 1.0) -> void:
	if reduced_motion:
		return
	for k in n:
		var a := k * TAU / n + randf() * 0.4
		var v := Vector2(cos(a), sin(a)) * _cell * (1.4 + randf()) * speed
		_particles.append({"p": at, "v": v, "t": 0.0, "life": 0.55 + randf() * 0.25, "color": color, "size": 0.05 + randf() * 0.03})


# ------------------------------------------------------------------------------- celebration

## Factory-wide success moment: a light wave runs along every travelled belt in delivery order,
## docks pop and confetti bursts. Tapping skips it. Emits `celebration_finished` exactly once.
func celebrate(duration: float) -> void:
	celebrating = true
	_cele_t = 0.0
	_cele_len = 0.25 if reduced_motion else maxf(0.3, duration)
	if not reduced_motion:
		for i in level["tiles"].size():
			if level["tiles"][i]["t"] == "dest":
				_burst(cell_center(i), LFStyle.PACKAGE[int(level["tiles"][i].get("c", 0))], 16, 1.3)
				_burst(cell_center(i), LFStyle.ACCENT, 6, 1.6)
	queue_redraw()


func skip_celebration() -> void:
	if celebrating:
		_cele_t = _cele_len


# ------------------------------------------------------------------------------- frame update

func _process(delta: float) -> void:
	if _frame_cost_us > 0:
		perf_samples.append(_frame_cost_us)
		if perf_samples.size() > 240:
			perf_samples.pop_front()
	_frame_cost_us = 0
	var t0 := Time.get_ticks_usec()
	_time += delta
	if _intro < 1.0:
		_intro = minf(1.0, _intro + delta / INTRO_TIME)
	# Long press => counter-clockwise
	if _press_index >= 0 and not _press_fired:
		_press_time += delta
		if _press_time >= LONG_PRESS:
			_press_fired = true
			_tilt_target[_press_index] = 0.0
			Sfx.haptic(20)
			_activate(_press_index, -1)
	var k := minf(1.0, delta * 30.0)
	for i in _rot_t.size():
		if _rot_t[i] < 1.0:
			_rot_t[i] = minf(1.0, _rot_t[i] + delta / ROT_TIME)
		var pt := 1.0 if i == _press_index and not _press_fired and LFTiles.is_rotatable(level["tiles"][i]) else 0.0
		if absf(_press[i] - pt) > 0.001 or absf(_tilt[i] - _tilt_target[i]) > 0.0005:
			_press[i] = lerpf(_press[i], pt, k)
			_tilt[i] = lerpf(_tilt[i], _tilt_target[i], k)
		if _pop[i] > 0.0:
			_pop[i] = maxf(0.0, _pop[i] - delta * 6.0)
		if _shake[i] > 0.0:
			_shake[i] = maxf(0.0, _shake[i] - delta * 3.5)
	if playing:
		if not paused and _frame_i < _frames.size() - 1:
			_frame_t += delta / step_time
			while _frame_t >= 1.0 and _frame_i < _frames.size() - 1:
				_frame_t -= 1.0
				_advance_frame()
			if _frame_i >= _frames.size() - 1:
				_frame_t = 0.0
				playing = false
				var res := _result
				var wait := 0.1 if reduced_motion else (0.18 if res["success"] else 0.35)
				get_tree().create_timer(wait).timeout.connect(func(): playback_finished.emit(res))
	if celebrating:
		_cele_t += delta
		queue_redraw()  # plate ring
		if _cele_t >= _cele_len:
			celebrating = false
			celebration_finished.emit()
	for f in _flashes:
		f["t"] += delta
	_flashes = _flashes.filter(func(f): return f["t"] < 0.7)
	for p in _particles:
		p["t"] += delta
		p["p"] += p["v"] * delta
		p["v"] = p["v"] * 0.9 + Vector2(0, _cell * 2.2 * delta)
	_particles = _particles.filter(func(p): return p["t"] < p["life"])
	_update_tiles()
	if _overlay != null and (not _frames.is_empty() or not _flashes.is_empty() or not _particles.is_empty() or hint_tile >= 0 or tutorial_tile >= 0 or _fail_cell >= 0):
		_overlay.queue_redraw()
	_frame_cost_us += Time.get_ticks_usec() - t0


## Push transforms every frame (cheap) and re-record draw commands only for tiles whose appearance
## signature changed.
func _update_tiles() -> void:
	if _tiles.is_empty() or _cell <= 0.0:
		return
	var s := _cell - _gap * 2
	var tiles: Array = level["tiles"]
	for i in _tiles.size():
		var tn: TileNode = _tiles[i]
		var t: Dictionary = tiles[i]
		var rotatable := LFTiles.is_rotatable(t)
		var depth := s * (0.065 if rotatable else 0.025)
		var press: float = _press[i]
		var pop: float = _pop[i]
		var sk: float = _shake[i]
		var sc := _tile_intro(i) * (1.0 - 0.035 * press + 0.06 * sin(clampf(pop, 0.0, 1.0) * PI))
		tn.position = cell_center(i) + Vector2(sin(sk * 28.0) * s * 0.035 * sk, 0)
		tn.scale = Vector2(sc, sc)
		tn.visible = sc > 0.01
		var sig := _tile_sig(i, t, press)
		if sig != tn.sig:
			tn.sig = sig
			tn.queue_redraw()
		if tn.belt != null:
			tn.belt.position = Vector2(0, -depth / 2.0 + depth * press)
			tn.belt.rotation = _angle(i) * PI / 2.0
			var bsig := _belt_sig(i)
			if bsig != tn.belt.sig:
				tn.belt.sig = bsig
				tn.belt.queue_redraw()


## [glow amount (quantised), colour index] for a cell: -2 success, -1 error, 0..3 package colour.
func _glow(i: int) -> Array:
	var glow := 0.0
	var col := -2
	if _trail.has(i):
		var tr: Dictionary = _trail[i]
		glow = 0.16 + 0.22 * clampf(1.0 - (_time - float(tr["t"])) / 0.5, 0.0, 1.0)
		col = int(tr["color"])
	var cg := _cele_glow(i)
	if cg > 0.0:
		glow = maxf(glow, 0.25 + 0.4 * cg)
	if _fail_path.has(i):
		glow = 0.2
		col = -1
	return [roundf(glow * 32.0) / 32.0, col]


func _glow_color(idx: int) -> Color:
	if idx == -1:
		return LFStyle.ERROR
	if idx == -2:
		return LFStyle.SUCCESS
	return LFStyle.PACKAGE[idx]


func _tile_sig(i: int, t: Dictionary, press: float) -> int:
	var g := _glow(i)
	var h := int(g[0] * 32.0) * 7 + int(g[1]) + 2
	h = h * 31 + int(roundf(press * 16.0))
	match str(t["t"]):
		"dest":
			var hit := 0.0
			if _dock_hits.has(i):
				hit = clampf(1.0 - (_time - float(_dock_hits[i])) / 0.35, 0.0, 1.0)
			var filled := _dock_hits.has(i) or _cele_glow(i) > 0.0
			h = h * 64 + int(roundf(hit * 16.0)) * 2 + (1 if filled else 0)
		"source":
			h = h * 64 + int(_src_remaining.get(i, -1)) + 2 + (32 if not _frames.is_empty() else 0)
	return h


func _belt_sig(i: int) -> int:
	var g := _glow(i)
	var h := int(g[0] * 32.0) * 7 + int(g[1]) + 2
	if playing and not paused and not reduced_motion and _trail.has(i):
		h = h * 64 + 1 + int(fmod(_time * 1.6, 1.0) * 24.0)  # rollers move under packages
	return h


# ------------------------------------------------------------------------------- drawing helpers

func _sb(color: Color, radius: int, shadow := false, border := Color.TRANSPARENT, bw := 0) -> StyleBoxFlat:
	# Animated alphas and radii are quantised so the cache stays small and nothing is allocated
	# per frame; the integer key avoids string formatting in the hot path.
	color.a = roundf(color.a * 32.0) / 32.0
	border.a = roundf(border.a * 32.0) / 32.0
	radius = radius & ~1
	var key := (color.to_rgba32() << 22) ^ (border.to_rgba32() * 2654435761) ^ (radius << 6) ^ (bw << 1) ^ int(shadow)
	var sb: StyleBoxFlat = _sb_cache.get(key)
	if sb == null:
		sb_misses += 1
		sb = StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_corner_radius_all(radius)
		sb.anti_aliasing = true
		if shadow:
			sb.shadow_color = Color(0.157, 0.169, 0.235, 0.16)
			sb.shadow_size = maxi(2, int(_cell * 0.06))
			sb.shadow_offset = Vector2(0, maxf(1.0, _cell * 0.03))
		if bw > 0:
			sb.border_color = border
			sb.set_border_width_all(bw)
		if _sb_cache.size() > 600:
			_sb_cache.clear()
		_sb_cache[key] = sb
	return sb


func _tile_intro(i: int) -> float:
	if _intro >= 1.0:
		return 1.0
	var x := i % _w
	var y := i / _w
	var stagger := float(x + y) / float(_w + _h) * 0.55
	var t := clampf((_intro - stagger) / 0.45, 0.0, 1.0)
	return _ease_out_back(t)


func _cele_glow(cell: int) -> float:
	if not celebrating or _trail_order.is_empty():
		return 0.0
	var idx := _trail_order.find(cell)
	if idx < 0:
		return 0.0
	var phase := _cele_t / (_cele_len * 0.7)
	var pos := float(idx) / float(maxi(1, _trail_order.size() - 1))
	var d := (phase - pos) * 5.0
	return clampf(exp(-d * d), 0.0, 1.0) + (0.35 if phase > 1.0 else 0.0)


# ------------------------------------------------------------------------------- drawing: board

func _draw() -> void:
	if _w == 0 or _cell < 8.0:
		return
	var t0 := Time.get_ticks_usec()
	var gap := _gap
	var plate := Rect2(_origin - Vector2(gap, gap) * 2.5, Vector2(_cell * _w, _cell * _h) + Vector2(gap, gap) * 5)
	draw_style_box(_sb(palette["plate"], int(_cell * 0.24), true), plate)
	_draw_motif(plate)
	if celebrating:
		var k := clampf(_cele_t / _cele_len, 0.0, 1.0)
		var grow := plate.grow(gap * 2.0 * k)
		draw_style_box(_sb(Color(0, 0, 0, 0), int(_cell * 0.28), false, Color(LFStyle.SUCCESS, 0.8 * (1.0 - k)), int(maxf(3.0, _cell * 0.05))), grow)
	_frame_cost_us += Time.get_ticks_usec() - t0


func _draw_motif(plate: Rect2) -> void:
	var col := Color(palette["rail"], 0.55)
	var inset := _cell * 0.09
	var corners := [plate.position + Vector2(inset, inset), plate.position + Vector2(plate.size.x - inset, inset),
		plate.position + Vector2(inset, plate.size.y - inset), plate.end - Vector2(inset, inset)]
	var r := maxf(2.0, _cell * 0.025)
	match str(palette.get("motif", "")):
		"bolts":
			for c in corners:
				draw_circle(c, r, col)
		"sprinkles":
			for k in corners.size():
				var c: Vector2 = corners[k]
				var a := 0.6 + k * 0.9
				draw_line(c - Vector2(cos(a), sin(a)) * r * 1.6, c + Vector2(cos(a), sin(a)) * r * 1.6, Color(LFStyle.PACKAGE[k % 4], 0.6), r, true)
		"stripes", "traces":
			for c in corners:
				draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2), col)
		"stars":
			for c in corners:
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 2), c + Vector2(r * 0.6, 0), c + Vector2(0, r * 2), c + Vector2(-r * 0.6, 0)]), col)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 2, 0), c + Vector2(0, -r * 0.6), c + Vector2(r * 2, 0), c + Vector2(0, r * 0.6)]), col)


# ------------------------------------------------------------------------------- drawing: tiles
# Tile nodes draw in local coordinates centred on the cell; scale and shake come from the node.

func _draw_tile_base(ci: CanvasItem, i: int) -> void:
	if _cell < 8.0:
		return
	var t: Dictionary = level["tiles"][i]
	var kind: String = t["t"]
	var s := _cell - _gap * 2
	if kind == "empty":
		ci.draw_circle(Vector2.ZERO, s * 0.035, Color(palette["rail"], 0.45))
		return
	var radius := int(s * 0.2)
	if kind == "blocked":
		ci.draw_style_box(_sb(Color(palette["plate"]).darkened(0.07), radius), Rect2(-Vector2(s, s) / 2.0, Vector2(s, s)))
		for k in 3:
			var o := (k - 1) * s * 0.22
			ci.draw_line(Vector2(o - s * 0.13, s * 0.13), Vector2(o + s * 0.13, -s * 0.13), Color(LFStyle.TEXT, 0.09), s * 0.05, true)
		return
	var rotatable := LFTiles.is_rotatable(t)
	var fixed_belt := not rotatable and kind != "source" and kind != "dest"
	# Raised tiles (rotatable) have a visible lip; fixed tiles sit almost flush with the plate.
	var depth := s * (0.065 if rotatable else 0.025)
	var press: float = _press[i]
	var sz := Vector2(s, s - depth)
	var face_rect := Rect2(Vector2(0, -depth / 2.0 + depth * press) - sz / 2.0, sz)
	var face := LFStyle.SURFACE
	if fixed_belt:
		face = Color(palette["plate"]).lerp(Color.WHITE, 0.55)
	var lip_rect := Rect2(-sz / 2.0 + Vector2(0, depth * 0.5), sz)
	ci.draw_style_box(_sb(face.darkened(0.13 if rotatable else 0.08), radius, rotatable), lip_rect)
	ci.draw_style_box(_sb(face, radius), face_rect)
	# Path illumination: cells a package has travelled glow in its colour.
	var g := _glow(i)
	var glow: float = g[0]
	if glow > 0.0:
		ci.draw_style_box(_sb(Color(_glow_color(g[1]), glow * 0.6), radius), face_rect.grow(-s * 0.03))
	var half := sz.x / 2.0
	var tc := face_rect.get_center()
	match kind:
		"source":
			_draw_source(ci, i, t, tc, half, sz.x * 0.34)
		"dest":
			_draw_dest(ci, i, t, tc, half)


func _draw_tile_belt(ci: CanvasItem, i: int) -> void:
	if _cell < 8.0:
		return
	var t: Dictionary = level["tiles"][i]
	var s := _cell - _gap * 2
	var rotatable := LFTiles.is_rotatable(t)
	var depth := s * (0.065 if rotatable else 0.025)
	var half := s / 2.0
	var bw := (s - depth) * 0.34
	var belt_col: Color = palette["belt"]
	var g := _glow(i)
	if g[0] > 0.0:
		belt_col = belt_col.lerp(_glow_color(g[1]), minf(0.45, g[0]))
	var rollers := playing and not paused and not reduced_motion and _trail.has(i)
	_draw_belt(ci, str(t["t"]), half - depth / 2.0, bw, belt_col, rollers)
	if not rotatable:
		# A pin marks a locked belt; it turns with the belt so it reads as part of the piece.
		_draw_pin(ci, Vector2(-half * 0.68, -half * 0.68), s * 0.085)


func _draw_pin(ci: CanvasItem, at: Vector2, r: float) -> void:
	ci.draw_circle(at + Vector2(0, r * 0.25), r, Color(LFStyle.TEXT, 0.12))
	ci.draw_circle(at, r, LFStyle.TEXT_MUTED)
	ci.draw_circle(at, r * 0.42, LFStyle.SURFACE)


func _belt_rollers(ci: CanvasItem, from: Vector2, to: Vector2, bw: float, rail: Color, moving: bool) -> void:
	var dirv := (to - from)
	var length := dirv.length()
	if length < 1.0 or bw < 2.0:
		return
	var n := dirv / length
	var perp := Vector2(-n.y, n.x) * bw * 0.3
	var spacing := bw * 0.5
	var offset := fmod(_time * bw * 1.6, spacing) if moving else 0.0
	var d := offset + spacing * 0.5
	var w := maxf(1.5, bw * 0.08)
	while d < length:
		var p := from + n * d
		ci.draw_line(p - perp, p + perp, rail, w, true)
		d += spacing


func _straight(ci: CanvasItem, a: Vector2, b: Vector2, bw: float, col: Color, rail: Color, moving: bool) -> void:
	var n := (b - a).normalized()
	var perp := Vector2(-n.y, n.x) * bw / 2.0
	ci.draw_colored_polygon(PackedVector2Array([a + perp, b + perp, b - perp, a - perp]), col)
	var rw := maxf(1.5, bw * 0.07)
	ci.draw_line(a + perp, b + perp, rail, rw, true)
	ci.draw_line(a - perp, b - perp, rail, rw, true)
	_belt_rollers(ci, a, b, bw, rail, moving)


## Draws the belt in its base orientation (r = 0) in local coordinates centred on the tile.
func _draw_belt(ci: CanvasItem, kind: String, half: float, bw: float, col: Color, moving: bool) -> void:
	var rail: Color = palette["rail"]
	match kind:
		"straight":
			_straight(ci, Vector2(0, -half), Vector2(0, half), bw, col, rail, moving)
		"corner":
			# Quarter ring centred on the top-right corner, joining N and E edge midpoints.
			var o := Vector2(half, -half)
			ci.draw_arc(o, half, PI * 0.5, PI, 24, col, bw, true)
			var rw := maxf(1.5, bw * 0.07)
			ci.draw_arc(o, half - bw / 2.0, PI * 0.5, PI, 16, rail, rw, true)
			ci.draw_arc(o, half + bw / 2.0, PI * 0.5, PI, 24, rail, rw, true)
			var phase := fmod(_time * 1.6, 1.0) if moving else 0.0
			for k in 3:
				var a := PI * 0.5 + (k + 0.5 + phase) * PI * 0.5 / 3.0
				if a > PI:
					continue
				var dv := Vector2(cos(a), sin(a))
				ci.draw_line(o + dv * (half - bw * 0.3), o + dv * (half + bw * 0.3), rail, maxf(1.5, bw * 0.08), true)
		"tee":
			_straight(ci, Vector2(0, -half), Vector2(0, half), bw, col, rail, moving)
			_straight(ci, Vector2(bw / 2, 0), Vector2(half, 0), bw, col, rail, moving)
			# Junction hub so the branch reads as one piece.
			ci.draw_circle(Vector2.ZERO, bw * 0.22, rail)
		"cross":
			_straight(ci, Vector2(-half, 0), Vector2(half, 0), bw, col.darkened(0.06), rail, moving)
			# Overpass: vertical belt on top with a shadow gap.
			ci.draw_rect(Rect2(Vector2(-bw / 2 - bw * 0.12, -half), Vector2(bw * 1.24, half * 2)), Color(LFStyle.TEXT, 0.10))
			_straight(ci, Vector2(0, -half), Vector2(0, half), bw, col, rail, moving)


func _draw_source(ci: CanvasItem, i: int, t: Dictionary, c: Vector2, half: float, bw: float) -> void:
	var cidx := int(t.get("c", 0))
	var color: Color = LFStyle.PACKAGE[cidx]
	var dir: int = int(rotations[i])
	var dv := Vector2(LFTiles.DX[dir], LFTiles.DY[dir])
	var perp := Vector2(-dv.y, dv.x)
	ci.draw_colored_polygon(PackedVector2Array([c + perp * bw / 2, c + perp * bw / 2 + dv * half, c - perp * bw / 2 + dv * half, c - perp * bw / 2]), palette["belt"])
	var box := Rect2(c - Vector2(half, half) * 0.64, Vector2(half, half) * 1.28)
	ci.draw_style_box(_sb(color.darkened(0.2), int(half * 0.36)), Rect2(box.position + Vector2(0, half * 0.08), box.size))
	ci.draw_style_box(_sb(color, int(half * 0.36)), box)
	var tip := c + dv * half * 0.5
	ci.draw_colored_polygon(PackedVector2Array([tip, c + perp * half * 0.28 + dv * half * 0.12, c - perp * half * 0.28 + dv * half * 0.12]), Color.WHITE)
	var sym_r := half * (0.17 if colorblind else 0.12)
	LFStyle.draw_symbol(ci, LFStyle.SYMBOLS[cidx], c - dv * half * 0.24, sym_r, Color(1, 1, 1, 0.95))
	var n: int = _src_remaining.get(i, int(t.get("n", 1))) if not _frames.is_empty() else int(t.get("n", 1))
	if int(t.get("n", 1)) > 1:
		var bc := c + Vector2(half * 0.64, half * 0.64)
		ci.draw_circle(bc, half * 0.29, LFStyle.TEXT)
		var f := LFStyle.font(800)
		var fs := int(half * 0.36)
		var txt := str(n)
		var tsz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		ci.draw_string(f, bc + Vector2(-tsz.x / 2, tsz.y * 0.32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_dest(ci: CanvasItem, i: int, t: Dictionary, c: Vector2, half: float) -> void:
	var cidx := int(t.get("c", 0))
	var color: Color = LFStyle.PACKAGE[cidx]
	var hit := 0.0
	if _dock_hits.has(i):
		hit = clampf(1.0 - (_time - float(_dock_hits[i])) / 0.35, 0.0, 1.0)
	var filled := _dock_hits.has(i) or _cele_glow(i) > 0.0
	var r := half * (0.64 + 0.12 * sin(hit * PI))
	ci.draw_circle(c, r + half * 0.04, Color(color, 0.16))
	if filled:
		ci.draw_circle(c, r * 0.86, color)
	ci.draw_arc(c, r * 0.86, 0, TAU, 40, color.darkened(0.08), half * 0.15, true)
	var sym_col := Color.WHITE if filled else color
	LFStyle.draw_symbol(ci, LFStyle.SYMBOLS[cidx], c, half * (0.24 if colorblind else 0.19), sym_col)


# ------------------------------------------------------------------------------- drawing: overlay

func _draw_overlay(ci: CanvasItem) -> void:
	if _w == 0 or _cell < 8.0:
		return
	if not _frames.is_empty():
		_draw_packages(ci)
	for f in _flashes:
		var k: float = f["t"] / 0.7
		var col: Color = f["color"]
		col.a = 1.0 - k
		ci.draw_arc(cell_center(f["cell"]), _cell * (0.3 + k * 0.55), 0, TAU, 36, col, _cell * 0.07 * (1.0 - k) + 1.0, true)
	for p in _particles:
		var col: Color = p["color"]
		col.a = 1.0 - p["t"] / p["life"]
		var s: float = _cell * p["size"]
		ci.draw_rect(Rect2(p["p"] - Vector2(s, s) / 2, Vector2(s, s)), col)
	if _fail_cell >= 0:
		var pulse := 0.5 + 0.5 * sin(_time * 9.0)
		var rc := Rect2(cell_center(_fail_cell) - Vector2(_cell, _cell) * 0.47, Vector2(_cell, _cell) * 0.94)
		ci.draw_style_box(_sb(Color(0, 0, 0, 0), int(_cell * 0.18), false, Color(LFStyle.ERROR, 0.55 + 0.45 * pulse), int(maxf(3.0, _cell * 0.06))), rc)
		_draw_fail_mark(ci, cell_center(_fail_cell) + Vector2(_cell * 0.34, -_cell * 0.34))
	if hint_tile >= 0:
		_draw_hint(ci, hint_tile, hint_dir, hint_taps)
	if tutorial_tile >= 0:
		_draw_tutorial(ci, tutorial_tile)


func _draw_fail_mark(ci: CanvasItem, c: Vector2) -> void:
	var r := _cell * 0.14
	ci.draw_circle(c, r, LFStyle.ERROR)
	var k := r * 0.45
	ci.draw_line(c - Vector2(k, k), c + Vector2(k, k), Color.WHITE, maxf(2.0, r * 0.28), true)
	ci.draw_line(c + Vector2(-k, k), c + Vector2(k, -k), Color.WHITE, maxf(2.0, r * 0.28), true)


func _moved(fi: int, id: int) -> bool:
	if fi <= 0 or fi >= _cells.size():
		return false
	var a: Dictionary = _cells[fi - 1]
	var b: Dictionary = _cells[fi]
	return a.has(id) and b.has(id) and a[id] != b[id]


func _draw_packages(ci: CanvasItem) -> void:
	var cur: Dictionary = _frames[_frame_i]
	var animating := _frame_i < _frames.size() - 1
	var nxt: Dictionary = _frames[_frame_i + 1] if animating else cur
	var t := clampf(_frame_t, 0.0, 1.0)
	var prev_pos: Dictionary = _cells[_frame_i]
	var size_px := _cell * 0.38
	var list: Array = nxt["packages"]
	for p in list:
		var color: Color = LFStyle.PACKAGE[p["color"]]
		var id: int = p["id"]
		var to := cell_center(p["cell"])
		var pos := to
		var scale := 1.0
		var alpha := 1.0
		var state: String = p["state"]
		if not animating:
			if state == "delivered":
				continue
			if state == "crashed":
				var shake := sin(_time * 40.0) * _cell * 0.03 * (1.0 if not reduced_motion else 0.0)
				pos = to + Vector2(p.get("toX", 0) - p["cell"] % _w, p.get("toY", 0) - p["cell"] / _w) * _cell * 0.4 + Vector2(shake, 0)
				color = color.lerp(LFStyle.ERROR, 0.4)
		elif state == "spawned":
			scale = _ease_out_back(t)
		elif prev_pos.has(id):
			var from := cell_center(prev_pos[id])
			# Constant speed while travelling; ease only on start/stop.
			var before := _moved(_frame_i, id)
			var after := state != "delivered" and _moved(_frame_i + 2, id)
			var e := t
			if before and not after:
				e = sin(t * PI * 0.5)
			elif after and not before:
				e = 1.0 - cos(t * PI * 0.5)
			elif not before and not after:
				e = t * t * (3.0 - 2.0 * t)
			if state == "crashed":
				var target := to + Vector2(p.get("toX", 0) - p["cell"] % _w, p.get("toY", 0) - p["cell"] / _w) * _cell * 0.4
				pos = from.lerp(target, e)
				color = color.lerp(LFStyle.ERROR, e * 0.4)
			else:
				pos = from.lerp(to, e)
			if state == "delivered":
				scale = 1.0 - e * 0.65
				alpha = 1.0 - e * 0.5
		_draw_package(ci, pos, size_px * scale, color, int(p["color"]), alpha)


func _draw_package(ci: CanvasItem, pos: Vector2, sz: float, color: Color, cidx: int, alpha: float) -> void:
	if sz < 2.0:
		return
	var rect := Rect2(pos - Vector2(sz, sz) / 2.0, Vector2(sz, sz))
	# Soft contact shadow, then a darker base for depth, then the lid.
	ci.draw_style_box(_sb(Color(0, 0, 0, 0.13 * alpha), int(sz * 0.3)), Rect2(rect.position + Vector2(-sz * 0.02, sz * 0.14), rect.size + Vector2(sz * 0.04, 0)))
	ci.draw_style_box(_sb(Color(color.darkened(0.22), alpha), int(sz * 0.24)), Rect2(rect.position + Vector2(0, sz * 0.07), rect.size))
	ci.draw_style_box(_sb(Color(color, alpha), int(sz * 0.24)), rect)
	ci.draw_line(rect.position + Vector2(sz / 2, sz * 0.06), rect.position + Vector2(sz / 2, sz * 0.94), Color(1, 1, 1, 0.35 * alpha), maxf(1.5, sz * 0.09))
	LFStyle.draw_symbol(ci, LFStyle.SYMBOLS[cidx], pos, sz * (0.2 if colorblind else 0.15), Color(1, 1, 1, alpha))


func _hint_area(i: int) -> Rect2:
	var tx := i % _w
	var ty := i / _w
	var x0 := clampi(tx - 1 - ((tx + ty) % 2), 0, maxi(0, _w - 3))
	var y0 := clampi(ty - 1 - ((tx * 3 + ty) % 2), 0, maxi(0, _h - 3))
	return Rect2(_origin + Vector2(x0, y0) * _cell, Vector2(mini(3, _w), mini(3, _h)) * _cell)


func _draw_hint(ci: CanvasItem, i: int, dir: int, taps: int) -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	if hint_level <= 1:
		var r := _hint_area(i).grow(-_cell * 0.04)
		ci.draw_style_box(_sb(Color(LFStyle.ACCENT, 0.12 + 0.08 * pulse), int(_cell * 0.22)), r)
		ci.draw_style_box(_sb(Color(0, 0, 0, 0), int(_cell * 0.22), false, Color(LFStyle.ACCENT, 0.85), int(maxf(3.0, _cell * 0.045))), r)
		return
	var c := cell_center(i)
	ci.draw_arc(c, _cell * (0.48 + 0.03 * pulse), 0, TAU, 44, Color(LFStyle.ACCENT, 0.7 + 0.3 * pulse), maxf(3.0, _cell * 0.06), true)
	if hint_level < 3:
		return
	var badge := c + Vector2(_cell * 0.36, -_cell * 0.36)
	ci.draw_circle(badge, _cell * 0.17, LFStyle.ACCENT)
	LFIcons.draw_icon(ci, "rotate_cw" if dir == 1 else "rotate_ccw", Rect2(badge - Vector2(_cell, _cell) * 0.13, Vector2(_cell, _cell) * 0.26), LFStyle.TEXT)
	if taps > 1:
		var f := LFStyle.font(800)
		ci.draw_string(f, badge + Vector2(_cell * 0.12, _cell * 0.22), "×%d" % taps, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_cell * 0.17), LFStyle.TEXT)


func _draw_tutorial(ci: CanvasItem, i: int) -> void:
	var c := cell_center(i)
	var k := fmod(_time, 1.4) / 1.4
	ci.draw_arc(c, _cell * (0.2 + k * 0.35), 0, TAU, 32, Color(LFStyle.PRIMARY, 1.0 - k), maxf(3.0, _cell * 0.05), true)
	# Finger
	var tip := c + Vector2(_cell * 0.12, _cell * 0.12) + Vector2(0, sin(_time * 5.0) * _cell * 0.03)
	ci.draw_circle(tip + Vector2(_cell * 0.1, _cell * 0.16), _cell * 0.13, Color(LFStyle.TEXT, 0.85))
	ci.draw_rect(Rect2(tip + Vector2(0.02, 0) * _cell, Vector2(_cell * 0.11, _cell * 0.2)), Color(LFStyle.TEXT, 0.85))
