class_name LFCrewPainter
## Procedural vector art for the Interdimensional Delivery Crew (no image files: every character is
## drawn from shapes at any size, so it stays crisp from a 27 px package to a 600 px portrait).
## This is v1 production-direction art drawn in code, not a final illustrator pass
## (docs/CHARACTER_ART_GUIDE.md).
##
## Characters are drawn in "unit" coordinates: the body spans -0.5..0.5 and a canvas transform
## scales it to pixels. Two detail levels for packages:
##  * FULL    – eyes with pupils, brows, mouth, arms, feet, cosmetics.
##  * COMPACT – body, dot eyes and the symbol only (small boards).
## The delivery symbol is ALWAYS drawn last, on the body, so nothing can cover it.

enum { CLASSIC, COMPACT, FULL }
const FULL_MIN := 40.0      # body size in px needed for full detail
const COMPACT_MIN := 14.0
const INK := Color("#282B3C")

const SYMBOL_FULL := Vector2(0, 0.25)
const SYMBOL_COMPACT := Vector2(0, 0.16)
## Unit-space region that must stay identical whatever cosmetic is worn (symbol + clear margin).
const SYMBOL_GUARD := 0.27

const NAPS_FUR := Color("#A9B0C8")
const NAPS_FUR_DARK := Color("#8790AD")
const NAPS_MUZZLE := Color("#F3EEE6")
const NAPS_SUIT := Color("#3D4A7A")
const NAPS_GOLD := Color("#E3B341")
const RIX_BODY := Color("#E9C46A")
const RIX_LENS := Color("#5CC8C8")

static var _rr := {}
## Current unit -> pixel transform. Points are transformed here (rather than with
## draw_set_transform) so anti-aliased edges stay 1 px wide at every size.
static var _xf := Transform2D.IDENTITY
static var _k := 1.0


static func _set_xf(origin: Vector2, rot: float, scale: Vector2) -> void:
	_xf = Transform2D(rot, scale, 0.0, origin)
	_k = (absf(scale.x) + absf(scale.y)) / 2.0


static func _pts(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = _xf * pts[i]
	return out


static func _circle(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(_xf * c, r * _k, col)


static func _line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float, _aa := true) -> void:
	ci.draw_line(_xf * a, _xf * b, col, maxf(1.0, w * _k), true)


static func _arc(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, w: float, _aa := true) -> void:
	var rot := _xf.get_rotation()
	ci.draw_arc(_xf * c, r * _k, a0 + rot, a1 + rot, n, col, maxf(1.0, w * _k), true)


static func _pline(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, _aa := true) -> void:
	ci.draw_polyline(_pts(pts), col, maxf(1.0, w * _k), true)


static func _poly(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	ci.draw_colored_polygon(_pts(pts), col)


static var _sbc := {}


## Rounded box drawn natively (StyleBoxFlat, anti-aliased in pixels). Much cheaper than a GDScript
## polygon: the hot path for every package body on the board.
static func _box(ci: CanvasItem, c: Vector2, w: float, h: float, r: float, col: Color) -> void:
	var sx := _xf.x.length()
	var sy := _xf.y.length()
	var pw := w * sx
	var ph := h * sy
	col.a = roundf(col.a * 32.0) / 32.0
	var rad := int(r * minf(sx, sy)) & ~1
	var key := (col.to_rgba32() << 8) ^ rad
	var sb: StyleBoxFlat = _sbc.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(rad)
		sb.anti_aliasing = true
		sb.corner_detail = 6
		if _sbc.size() > 400:
			_sbc.clear()
		_sbc[key] = sb
	ci.draw_set_transform(_xf * c, _xf.get_rotation(), Vector2.ONE)
	ci.draw_style_box(sb, Rect2(-pw / 2.0, -ph / 2.0, pw, ph))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Ellipse via a natively drawn circle under a scaled transform (no per-point GDScript work).
static func _oval(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	ci.draw_set_transform(_xf * c, _xf.get_rotation(), Vector2(rx * _xf.x.length(), ry * _xf.y.length()))
	ci.draw_circle(Vector2.ZERO, 1.0, col)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _rect(ci: CanvasItem, r: Rect2, col: Color) -> void:
	_poly(ci, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), col)


static func detail_for(px: float) -> int:
	if px >= FULL_MIN:
		return FULL
	if px >= COMPACT_MIN:
		return COMPACT
	return CLASSIC


static func symbol_center(detail: int) -> Vector2:
	return SYMBOL_FULL if detail == FULL else SYMBOL_COMPACT


static func symbol_radius(detail: int, colorblind: bool) -> float:
	if detail == FULL:
		return 0.17 if colorblind else 0.13
	return 0.21 if colorblind else 0.17


## Unit rounded rectangle centred on `c` (cached point list, closed).
static func rrect(w: float, h: float, r: float) -> PackedVector2Array:
	var key := "%.3f:%.3f:%.3f" % [w, h, r]
	if _rr.has(key):
		return _rr[key]
	var pts := PackedVector2Array()
	var hw := w / 2.0
	var hh := h / 2.0
	r = minf(r, minf(hw, hh))
	var corners := [Vector2(hw - r, -hh + r), Vector2(hw - r, hh - r), Vector2(-hw + r, hh - r), Vector2(-hw + r, -hh + r)]
	var starts := [-PI / 2.0, 0.0, PI / 2.0, PI]
	for k in 4:
		for s in 7:
			var a: float = starts[k] + s * (PI / 2.0) / 6.0
			pts.append(corners[k] + Vector2(cos(a), sin(a)) * r)
	_rr[key] = pts
	if _rr.size() > 64:
		_rr.clear()
	return pts


static func _offset(pts: PackedVector2Array, o: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = pts[i] + o
	return out


static func _ellipse(c: Vector2, rx: float, ry: float, n := 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## Filled polygon; `outline` adds a 1 px anti-aliased edge (polygons themselves are not AA).
static func _fill(ci: CanvasItem, pts: PackedVector2Array, col: Color, outline: Variant = 0.0) -> void:
	var tp := _pts(pts)
	ci.draw_colored_polygon(tp, col)
	if float(outline) > 0.0:
		tp.append(tp[0])
		ci.draw_polyline(tp, col, 1.0, true)


static func _star(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	return pts


static func _reset(_ci: CanvasItem) -> void:
	_xf = Transform2D.IDENTITY
	_k = 1.0


# =================================================================================== packages

## Draw one package character. `opts`: color (Color, may be tinted e.g. toward red on a crash),
## cidx (0..3), detail, colorblind, alpha, cosmetic (art key), accent ("scan"/"visor"/""), t.
static func draw_package(ci: CanvasItem, body: String, pos: Vector2, sz: float, pose: Dictionary, opts: Dictionary) -> void:
	if sz < 2.0:
		return
	var detail: int = opts.get("detail", detail_for(sz))
	var color: Color = opts.get("color", LFStyle.PACKAGE[0])
	var cidx: int = opts.get("cidx", 0)
	var alpha: float = opts.get("alpha", 1.0)
	var art: String = opts.get("cosmetic", "") if detail == FULL else ""
	var style: Dictionary = opts.get("style", {})
	var size_k: float = style.get("size", 1.0)
	var radius: float = style.get("radius", 0.3)
	var s := sz * size_k
	var aa := 1.1 / s
	# Contact shadow stays on the ground while the body hops.
	_set_xf(pos + Vector2(float(pose["dx"]) * s, 0), 0.0, Vector2(s, s))
	_oval(ci, Vector2(0, 0.58), 0.4 * float(pose["sx"]), 0.07, Color(0, 0, 0, 0.13 * alpha))
	_set_xf(pos + Vector2(float(pose["dx"]), float(pose["dy"])) * s, float(pose["rot"]), Vector2(s * float(pose["sx"]), s * float(pose["sy"])))
	var dark := color.darkened(0.22)
	dark.a = alpha
	var col := Color(color, alpha)
	var shape := rrect(1.0, 1.0, radius)
	if art in ["cape", "backpack"]:
		_cosmetic_back(ci, art, col, alpha, aa)
	if float(pose["ghost"]) > 0.0:
		var g: float = pose["ghost"]
		_fill(ci, _offset(shape, Vector2(-0.08 * g, 0)), Color(0.3, 0.9, 1.0, 0.4 * g * alpha))
		_fill(ci, _offset(shape, Vector2(0.08 * g, 0.02)), Color(1.0, 0.3, 0.8, 0.4 * g * alpha))
	if detail == FULL:
		_limbs(ci, pose, dark, alpha)
	_box(ci, Vector2(0, 0.07), 1.0, 1.0, radius, dark)
	_box(ci, Vector2.ZERO, 1.0, 1.0, radius, col)
	if detail == FULL:
		_box(ci, Vector2(-0.24, -0.39), 0.2, 0.07, 0.035, Color(1, 1, 1, 0.3 * alpha))
		if art in ["holo", "pajamas"]:
			_cosmetic_skin(ci, art, alpha, float(opts.get("t", 0.0)))
		_extras(ci, body, art, color, alpha, pose)
		_face(ci, body, pose, color, alpha)
		if art in ["goggles", "glasses", "pixel_shades"]:
			_cosmetic_eyes(ci, art, body, alpha)
		if art in ["crown", "headphones", "helmet", "alien_antenna", "sleep_cap"]:
			_cosmetic_head(ci, art, alpha)
		var accent: String = opts.get("accent", "")
		if accent == "visor":
			_arc(ci, Vector2(0, -0.08), 0.66, PI * 1.05, PI * 1.95, 24, Color(1, 1, 1, 0.55 * alpha), 0.035, true)
		elif accent == "scan":
			_line(ci, Vector2(-0.36, -0.5), Vector2(0.36, -0.5), Color(0.55, 1.0, 0.95, 0.7 * alpha), 0.04, true)
	elif detail == COMPACT:
		_face_compact(ci, pose, alpha)
	# The delivery symbol is drawn last so no face, cosmetic or effect can ever hide it.
	var sym_c := symbol_center(detail)
	ci.draw_set_transform_matrix(_xf)
	LFStyle.draw_symbol(ci, LFStyle.SYMBOLS[clampi(cidx, 0, 3)], sym_c, symbol_radius(detail, bool(opts.get("colorblind", false))), Color(1, 1, 1, alpha))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	_reset(ci)


static func _limbs(ci: CanvasItem, pose: Dictionary, dark: Color, alpha: float) -> void:
	var arms: String = pose["arms"]
	var la := Vector2(-0.55, 0.1)
	var ra := Vector2(0.55, 0.1)
	match arms:
		"up":
			la = Vector2(-0.58, -0.3)
			ra = Vector2(0.58, -0.3)
		"wave":
			la = Vector2(-0.6, -0.26)
			ra = Vector2(0.57, 0.02)
	_circle(ci, la, 0.08, dark)
	_circle(ci, ra, 0.08, dark)
	var foot_col := Color(dark.darkened(0.35), alpha)
	var lift: float = float(pose["foot"]) * 0.07
	_oval(ci, Vector2(-0.18, 0.55), 0.12, 0.06, foot_col)
	_oval(ci, Vector2(0.18, 0.55 - lift), 0.12, 0.06, foot_col)


static func _extras(ci: CanvasItem, body: String, art: String, color: Color, alpha: float, pose: Dictionary) -> void:
	match body:
		"glitch":
			if art != "alien_antenna":
				_line(ci, Vector2(0.1, -0.5), Vector2(0.2, -0.66), Color(INK, alpha), 0.035, true)
				_circle(ci, Vector2(0.2, -0.68), 0.055, Color(LFStyle.ACCENT, alpha))
			_rect(ci, Rect2(0.28, -0.4, 0.07, 0.07), Color(1, 1, 1, 0.5 * alpha))
			_rect(ci, Rect2(0.37, -0.3, 0.045, 0.045), Color(1, 1, 1, 0.35 * alpha))
		"mochi":
			_oval(ci, Vector2(-0.3, -0.04), 0.07, 0.04, Color(1, 0.55, 0.65, 0.45 * alpha))
			_oval(ci, Vector2(0.3, -0.04), 0.07, 0.04, Color(1, 0.55, 0.65, 0.45 * alpha))
	if pose["sweat"]:
		_fill(ci, PackedVector2Array([Vector2(0.4, -0.5), Vector2(0.45, -0.38), Vector2(0.4, -0.33), Vector2(0.35, -0.38)]), Color(0.7, 0.88, 1.0, alpha))
	if pose["z"]:
		var z := Vector2(0.38, -0.62)
		var zc := Color(INK, 0.6 * alpha)
		_pline(ci, PackedVector2Array([z, z + Vector2(0.1, 0), z + Vector2(0, 0.1), z + Vector2(0.1, 0.1)]), zc, 0.03, true)


static func _eye_layout(body: String) -> Array:
	match body:
		"zip":
			return [[Vector2(-0.18, -0.19), 0.125], [Vector2(0.18, -0.19), 0.125]]
		"glitch":
			return [[Vector2(-0.16, -0.2), 0.14], [Vector2(0.2, -0.17), 0.085]]
	return [[Vector2(-0.17, -0.19), 0.105], [Vector2(0.17, -0.19), 0.105]]


static func _face(ci: CanvasItem, body: String, pose: Dictionary, color: Color, alpha: float) -> void:
	var ink := Color(INK, alpha)
	var white := Color(1, 1, 1, alpha)
	var eyes: String = pose["eyes"]
	var look: Vector2 = pose["look"]
	if look.length() > 1.0:
		look = look.normalized()
	var layout := _eye_layout(body)
	for k in 2:
		var c: Vector2 = layout[k][0]
		var r: float = layout[k][1]
		var mode := eyes
		if eyes == "confused":
			mode = "open" if k == 0 else "squint"
		match mode:
			"closed":
				_arc(ci, c + Vector2(0, -0.02), r * 0.75, PI * 0.12, PI * 0.88, 12, ink, 0.035, true)
			"happy":
				_arc(ci, c + Vector2(0, 0.04), r * 0.8, PI * 1.12, PI * 1.88, 12, ink, 0.04, true)
			"squint":
				_line(ci, c + Vector2(-r * 0.8, 0), c + Vector2(r * 0.8, -r * 0.2), ink, 0.04, true)
			"star":
				_fill(ci, _star(c, r * 1.15), Color(LFStyle.ACCENT, alpha))
				_circle(ci, c + Vector2(-r * 0.25, -r * 0.3), r * 0.18, white)
			_:
				var er := r * (1.15 if mode == "wide" else 1.0)
				_circle(ci, c, er, white)
				var pr := er * (0.36 if mode == "wide" else 0.52)
				var pc := c + look * er * 0.42
				if mode == "sleepy":
					pc += Vector2(0, er * 0.3)
				_circle(ci, pc, pr, ink)
				_circle(ci, pc + Vector2(-pr * 0.35, -pr * 0.4), pr * 0.32, white)
				if mode == "sleepy":
					# Heavy eyelid in body colour.
					var lid := PackedVector2Array()
					for i in 11:
						var a := PI + PI * i / 10.0
						lid.append(c + Vector2(cos(a), sin(a)) * er * 1.08)
					lid.append(c + Vector2(er * 1.08, er * 0.05))
					lid.append(c + Vector2(-er * 1.08, er * 0.05))
					_poly(ci, lid, Color(color, alpha))
					_line(ci, c + Vector2(-er, er * 0.05), c + Vector2(er, er * 0.05), ink, 0.03, true)
	var brow := Color(color.darkened(0.5), alpha)
	match str(pose["brows"]):
		"confident":
			_line(ci, Vector2(-0.27, -0.35), Vector2(-0.09, -0.34), brow, 0.04, true)
			_line(ci, Vector2(0.08, -0.38), Vector2(0.27, -0.43), brow, 0.04, true)
		"worried":
			_line(ci, Vector2(-0.29, -0.33), Vector2(-0.1, -0.4), brow, 0.04, true)
			_line(ci, Vector2(0.1, -0.4), Vector2(0.29, -0.33), brow, 0.04, true)
	var m := Vector2(0, -0.04)
	match str(pose["mouth"]):
		"smile":
			_arc(ci, m + Vector2(0, -0.04), 0.07, PI * 0.2, PI * 0.8, 10, ink, 0.032, true)
		"smirk":
			_arc(ci, m + Vector2(0.02, -0.05), 0.075, PI * 0.08, PI * 0.62, 10, ink, 0.032, true)
		"grin":
			var g := PackedVector2Array()
			for i in 11:
				var a := PI * i / 10.0
				g.append(m + Vector2(cos(a) * 0.085, -0.025 + sin(a) * 0.075))
			_poly(ci, g, ink)
			_circle(ci, m + Vector2(0, 0.03), 0.03, Color(1, 0.5, 0.55, alpha))
		"o":
			_circle(ci, m + Vector2(0, 0.0), 0.042, ink)
		"whistle":
			_circle(ci, m + Vector2(0.06, 0.0), 0.025, ink)
		"flat":
			_line(ci, m + Vector2(-0.055, 0), m + Vector2(0.055, 0), ink, 0.032, true)
		"wobble":
			_pline(ci, PackedVector2Array([m + Vector2(-0.07, 0.01), m + Vector2(-0.035, -0.015), m + Vector2(0, 0.01), m + Vector2(0.035, -0.015), m + Vector2(0.07, 0.01)]), ink, 0.028, true)
		"yawn":
			_fill(ci, _ellipse(m + Vector2(0, 0.005), 0.045, 0.06, 14), ink)
		"tongue":
			_arc(ci, m + Vector2(0, -0.04), 0.07, PI * 0.15, PI * 0.85, 10, ink, 0.032, true)
			_circle(ci, m + Vector2(0.025, 0.035), 0.03, Color(1, 0.5, 0.55, alpha))


static func _face_compact(ci: CanvasItem, pose: Dictionary, alpha: float) -> void:
	var ink := Color(INK, alpha)
	var eyes: String = pose["eyes"]
	for x in [-0.17, 0.17]:
		var c := Vector2(x, -0.2)
		match eyes:
			"closed":
				_line(ci, c + Vector2(-0.07, 0), c + Vector2(0.07, 0), ink, 0.05, true)
			"happy", "star":
				_arc(ci, c + Vector2(0, 0.04), 0.07, PI * 1.15, PI * 1.85, 8, ink, 0.05, true)
			"wide":
				_circle(ci, c, 0.085, ink)
			"sleepy":
				_line(ci, c + Vector2(-0.07, 0.01), c + Vector2(0.07, 0.01), ink, 0.06, true)
			_:
				_circle(ci, c, 0.068, ink)


# ---------------------------------------------------------------------------------- cosmetics

static func _cosmetic_back(ci: CanvasItem, art: String, col: Color, alpha: float, aa: float) -> void:
	match art:
		"cape":
			_fill(ci, PackedVector2Array([Vector2(-0.42, -0.25), Vector2(0.42, -0.25), Vector2(0.66, 0.62), Vector2(0.2, 0.55), Vector2(-0.2, 0.62), Vector2(-0.66, 0.55)]), Color("#D9455F", alpha), aa)
		"backpack":
			_fill(ci, _offset(rrect(0.34, 0.5, 0.1), Vector2(-0.5, 0.02)), Color("#8D6E57", alpha), aa)
			_rect(ci, Rect2(-0.64, 0.02, 0.12, 0.12), Color("#6F5544", alpha))


static func _cosmetic_skin(ci: CanvasItem, art: String, alpha: float, t: float) -> void:
	match art:
		"holo":
			var cols := [Color(0.5, 1, 1, 0.35 * alpha), Color(1, 0.6, 0.9, 0.35 * alpha), Color(1, 1, 0.6, 0.35 * alpha)]
			var sh := fposmod(t * 0.2, 0.06)
			for k in 3:
				var o := k * 0.09 + sh
				_line(ci, Vector2(-0.46, -0.08 - o), Vector2(-0.08 - o, -0.46), cols[k], 0.04, true)
				_line(ci, Vector2(0.46, 0.14 + o), Vector2(0.3 + o, 0.46), cols[k], 0.04, true)
		"pajamas":
			for c in [Vector2(-0.36, 0.3), Vector2(0.36, 0.33), Vector2(-0.39, -0.41), Vector2(0.4, -0.38), Vector2(-0.39, 0.02)]:
				_fill(ci, _star(c, 0.05), Color(1, 1, 1, 0.6 * alpha))


static func _cosmetic_eyes(ci: CanvasItem, art: String, body: String, alpha: float) -> void:
	var layout := _eye_layout(body)
	var l: Vector2 = layout[0][0]
	var r: Vector2 = layout[1][0]
	match art:
		"goggles":
			_line(ci, Vector2(-0.5, l.y), Vector2(0.5, r.y), Color("#5A3E2B", alpha), 0.06, true)
			for c in [l, r]:
				_circle(ci, c, 0.15, Color(0.75, 0.9, 1.0, 0.35 * alpha))
				_arc(ci, c, 0.15, 0, TAU, 20, Color("#F2A541", alpha), 0.05, true)
		"glasses":
			for c in [l, r]:
				_arc(ci, c, 0.13, 0, TAU, 20, Color(INK, alpha), 0.028, true)
			_line(ci, l + Vector2(0.13, 0), r - Vector2(0.13, 0), Color(INK, alpha), 0.028, true)
		"pixel_shades":
			var k := Color(0.07, 0.07, 0.1, alpha)
			_rect(ci, Rect2(-0.34, -0.26, 0.68, 0.06), k)
			_rect(ci, Rect2(-0.32, -0.2, 0.26, 0.09), k)
			_rect(ci, Rect2(0.06, -0.2, 0.26, 0.09), k)
			_rect(ci, Rect2(-0.28, -0.11, 0.18, 0.04), k)
			_rect(ci, Rect2(0.1, -0.11, 0.18, 0.04), k)
			_rect(ci, Rect2(-0.28, -0.19, 0.05, 0.04), Color(1, 1, 1, 0.8 * alpha))
			_rect(ci, Rect2(0.1, -0.19, 0.05, 0.04), Color(1, 1, 1, 0.8 * alpha))


static func _cosmetic_head(ci: CanvasItem, art: String, alpha: float) -> void:
	match art:
		"crown":
			_fill(ci, PackedVector2Array([Vector2(-0.2, -0.48), Vector2(0.2, -0.48), Vector2(0.22, -0.68), Vector2(0.1, -0.58), Vector2(0, -0.72), Vector2(-0.1, -0.58), Vector2(-0.22, -0.68)]), Color("#F4C542", alpha), 0.02)
			_circle(ci, Vector2(0, -0.55), 0.035, Color("#E05A6D", alpha))
		"headphones":
			_arc(ci, Vector2(0, -0.12), 0.52, PI * 1.12, PI * 1.88, 24, Color(INK, alpha), 0.06, true)
			for x in [-0.53, 0.53]:
				_fill(ci, _offset(rrect(0.13, 0.24, 0.05), Vector2(x, -0.12)), Color("#F28B66", alpha) if x < 0 else Color("#5C6BC0", alpha))
		"helmet":
			var dome := PackedVector2Array()
			for i in 13:
				var a := PI + PI * i / 12.0
				dome.append(Vector2(cos(a) * 0.46, -0.34 + sin(a) * 0.3))
			_fill(ci, dome, Color("#F4C542", alpha), 0.02)
			_line(ci, Vector2(-0.52, -0.34), Vector2(0.52, -0.34), Color("#D9A520", alpha), 0.06, true)
			_line(ci, Vector2(0, -0.64), Vector2(0, -0.36), Color("#D9A520", alpha), 0.05, true)
		"alien_antenna":
			for s in [-1.0, 1.0]:
				_line(ci, Vector2(0.14 * s, -0.5), Vector2(0.26 * s, -0.72), Color(INK, alpha), 0.035, true)
				_circle(ci, Vector2(0.26 * s, -0.74), 0.065, Color("#7EE081", alpha))
		"sleep_cap":
			_fill(ci, PackedVector2Array([Vector2(-0.44, -0.4), Vector2(0.38, -0.44), Vector2(0.3, -0.62), Vector2(0.5, -0.8), Vector2(-0.1, -0.66)]), Color("#7FA7E8", alpha), 0.02)
			_line(ci, Vector2(-0.44, -0.42), Vector2(0.38, -0.46), Color(1, 1, 1, alpha), 0.06, true)
			_circle(ci, Vector2(0.5, -0.8), 0.07, Color(1, 1, 1, alpha))


# ====================================================================== named expressions

## Static pose for one of the five catalogue expressions (neutral, happy, surprised, confused,
## celebrating). Used for portraits, banner faces and the share card.
static func expression(body: String, name: String) -> Dictionary:
	var ctx := {"motion": false}
	match name:
		"happy":
			var p := LFCrewAnim.pose(body, LFCrewAnim.DELIVERED, LFCrewAnim.DELIVER, 0.0, 0, ctx)
			p["arms"] = "down"
			return p
		"surprised":
			return LFCrewAnim.pose(body, LFCrewAnim.SURPRISED, 0.0, 0.0, 0, ctx)
		"confused":
			var p := LFCrewAnim.pose(body, LFCrewAnim.FAILED, 0.0, 0.0, 0, ctx)
			p["eyes"] = "confused"
			p["mouth"] = "flat"
			p["sweat"] = false
			p["arms"] = "down"
			return p
		"celebrating":
			return LFCrewAnim.pose(body, LFCrewAnim.CELEBRATING, 0.0, 0.0, 0, ctx)
	return LFCrewAnim.pose(body, LFCrewAnim.IDLE, 0.0, 0.0, 0, ctx)


# ===================================================================== Captain Naps & Dr. Rix

## Captain Naps: a sleepy space cat in an oversized helmet. `expr`: neutral, happy, surprised,
## confused, celebrating, sleeping. Unit space: roughly -0.55..0.55 wide, -0.55..0.6 tall.
static func draw_naps(ci: CanvasItem, pos: Vector2, sz: float, expr: String, t: float, opts := {}) -> void:
	var motion: bool = opts.get("motion", true)
	var art: String = opts.get("cosmetic", "")
	var breathe := sin(t * 2.0) * 0.015 if motion else 0.0
	var hop := 0.0
	if expr == "celebrating" and motion:
		hop = -absf(sin(t * 7.0)) * 0.06
	var aa := 1.1 / sz
	_set_xf(pos, 0.0, Vector2(sz, sz))
	_fill(ci, _ellipse(Vector2(0, 0.6), 0.32, 0.05), Color(0, 0, 0, 0.12))
	_set_xf(pos + Vector2(0, hop) * sz, 0.0, Vector2(sz, sz * (1.0 + breathe)))
	# Tail
	var sway := sin(t * 1.3) * 0.08 if motion else 0.0
	_arc(ci, Vector2(0.34, 0.3), 0.18, PI * 0.5, PI * (1.9 + sway), 16, NAPS_FUR_DARK, 0.075, true)
	# Suit
	var suit := NAPS_SUIT
	if art == "naps_gold":
		suit = NAPS_GOLD
	_fill(ci, _offset(rrect(0.5, 0.36, 0.14), Vector2(0, 0.36)), suit, aa)
	if art == "naps_lab":
		_fill(ci, _offset(rrect(0.54, 0.38, 0.12), Vector2(0, 0.37)), Color("#F6F7FB"), aa)
		_fill(ci, PackedVector2Array([Vector2(-0.08, 0.2), Vector2(0, 0.38), Vector2(0.08, 0.2)]), suit)
		_rect(ci, Rect2(0.1, 0.38, 0.1, 0.08), Color("#C9CEE8"))
	if art != "naps_lab":
		_line(ci, Vector2(-0.25, 0.44), Vector2(0.25, 0.44), suit.darkened(0.25), 0.04, true)
	var badge_c := Vector2(-0.12, 0.33)
	_circle(ci, badge_c, 0.055, LFStyle.ACCENT)
	if art == "naps_gold":
		_fill(ci, _star(badge_c, 0.04), Color.WHITE)
	else:
		_circle(ci, badge_c, 0.022, Color.WHITE)
	# Boots and paws
	for x in [-0.13, 0.13]:
		_fill(ci, _ellipse(Vector2(x, 0.56), 0.1, 0.05, 12), suit.darkened(0.35))
	var paws_up := expr == "celebrating" or expr == "surprised"
	for s in [-1.0, 1.0]:
		var pc := Vector2(0.3 * s, 0.16) if paws_up else Vector2(0.28 * s, 0.38)
		_circle(ci, pc, 0.07, NAPS_FUR)
	# Helmet glass (behind the head), then the head
	_circle(ci, Vector2(0, -0.1), 0.42, Color(0.86, 0.93, 1.0, 0.55))
	for s in [-1.0, 1.0]:
		_fill(ci, PackedVector2Array([Vector2(0.27 * s, -0.22), Vector2(0.22 * s, -0.44), Vector2(0.08 * s, -0.3)]), NAPS_FUR)
		_fill(ci, PackedVector2Array([Vector2(0.23 * s, -0.25), Vector2(0.2 * s, -0.38), Vector2(0.12 * s, -0.3)]), Color("#E9B8C2"))
	_fill(ci, _ellipse(Vector2(0, -0.1), 0.29, 0.25, 28), NAPS_FUR, aa)
	_fill(ci, _ellipse(Vector2(0, -0.02), 0.16, 0.1, 20), NAPS_MUZZLE)
	_naps_face(ci, expr, t, motion)
	# Helmet rim, highlight and collar
	_arc(ci, Vector2(0, -0.1), 0.42, 0, TAU, 40, Color(1, 1, 1, 0.9), 0.03, true)
	_arc(ci, Vector2(0, -0.1), 0.35, PI * 1.15, PI * 1.45, 12, Color(1, 1, 1, 0.8), 0.04, true)
	_fill(ci, _offset(rrect(0.56, 0.1, 0.05), Vector2(0, 0.24)), Color("#E8ECF4"), aa)
	if art == "naps_detective":
		_fill(ci, PackedVector2Array([Vector2(-0.24, -0.47), Vector2(-0.2, -0.62), Vector2(-0.08, -0.71), Vector2(0.08, -0.71), Vector2(0.2, -0.62), Vector2(0.24, -0.47)]), Color("#9B7A55"), aa)
		_line(ci, Vector2(-0.32, -0.47), Vector2(0.32, -0.47), Color("#7A5C3E"), 0.05, true)
		_line(ci, Vector2(-0.22, -0.55), Vector2(0.22, -0.55), Color("#5E4630"), 0.035, true)
		_circle(ci, Vector2(0, -0.72), 0.03, Color("#7A5C3E"))
	if expr == "sleeping" or expr == "neutral":
		var k := fposmod(t * 0.4, 1.0) if motion else 0.5
		var zc := Color(INK, 0.7 * (1.0 - k) if motion else 0.5)
		var z := Vector2(0.36 + k * 0.1, -0.5 - k * 0.2)
		var w := 0.09
		if expr == "sleeping" or motion:
			_pline(ci, PackedVector2Array([z, z + Vector2(w, 0), z + Vector2(0, w), z + Vector2(w, w)]), zc, 0.025, true)
	_reset(ci)


static func _naps_face(ci: CanvasItem, expr: String, t: float, motion: bool) -> void:
	var ink := INK
	var blink := motion and fposmod(t, 4.1) < 0.15
	for s in [-1.0, 1.0]:
		var c := Vector2(0.11 * s, -0.13)
		match expr:
			"happy", "celebrating":
				_arc(ci, c + Vector2(0, 0.03), 0.055, PI * 1.12, PI * 1.88, 10, ink, 0.025, true)
			"surprised":
				_circle(ci, c, 0.06, Color.WHITE)
				_circle(ci, c, 0.032, ink)
			"confused":
				if s < 0:
					_circle(ci, c, 0.05, Color.WHITE)
					_circle(ci, c + Vector2(0.01, 0.01), 0.026, ink)
				else:
					_line(ci, c + Vector2(-0.05, 0), c + Vector2(0.05, -0.015), ink, 0.025, true)
			"sleeping":
				_arc(ci, c + Vector2(0, -0.02), 0.045, PI * 0.15, PI * 0.85, 10, ink, 0.025, true)
			_:
				# Neutral: heavy-lidded, unimpressed.
				if blink:
					_line(ci, c + Vector2(-0.05, 0), c + Vector2(0.05, 0), ink, 0.025, true)
				else:
					_circle(ci, c + Vector2(0, 0.01), 0.05, Color.WHITE)
					_circle(ci, c + Vector2(0, 0.02), 0.028, ink)
					var lid := PackedVector2Array()
					for i in 9:
						var a := PI + PI * i / 8.0
						lid.append(c + Vector2(cos(a), sin(a)) * 0.056)
					lid.append(c + Vector2(0.056, 0.008))
					lid.append(c + Vector2(-0.056, 0.008))
					_poly(ci, lid, NAPS_FUR)
					_line(ci, c + Vector2(-0.058, 0.008), c + Vector2(0.058, 0.008), ink, 0.02, true)
	_poly(ci, PackedVector2Array([Vector2(-0.03, -0.05), Vector2(0.03, -0.05), Vector2(0, -0.02)]), Color("#E9919B"))
	if expr == "surprised":
		_circle(ci, Vector2(0, 0.02), 0.025, ink)
	else:
		_arc(ci, Vector2(-0.025, -0.01), 0.025, PI * 0.1, PI * 0.9, 8, ink, 0.018, true)
		_arc(ci, Vector2(0.025, -0.01), 0.025, PI * 0.1, PI * 0.9, 8, ink, 0.018, true)
	for s in [-1.0, 1.0]:
		_line(ci, Vector2(0.14 * s, -0.02), Vector2(0.3 * s, -0.05), Color(ink, 0.5), 0.012, true)
		_line(ci, Vector2(0.14 * s, 0.0), Vector2(0.3 * s, 0.02), Color(ink, 0.5), 0.012, true)


## Dr. Rix: a mustard, pear-shaped alien engineer with goggles pushed up and a wrench.
static func draw_rix(ci: CanvasItem, pos: Vector2, sz: float, expr: String, t: float, opts := {}) -> void:
	var motion: bool = opts.get("motion", true)
	var hover := sin(t * 3.0) * 0.025 if motion else 0.0
	var aa := 1.1 / sz
	_set_xf(pos, 0.0, Vector2(sz, sz))
	_fill(ci, _ellipse(Vector2(0, 0.6), 0.26, 0.045), Color(0, 0, 0, 0.12))
	_set_xf(pos + Vector2(0, hover) * sz, 0.0, Vector2(sz, sz))
	var dark := RIX_BODY.darkened(0.2)
	# Arms (one waving a wrench)
	var wave := sin(t * 5.0) * 0.1 if motion and expr in ["happy", "celebrating"] else 0.0
	_line(ci, Vector2(-0.3, 0.2), Vector2(-0.46, 0.05 + wave), dark, 0.07, true)
	_line(ci, Vector2(0.3, 0.2), Vector2(0.48, 0.32), dark, 0.07, true)
	_line(ci, Vector2(-0.46, 0.05 + wave), Vector2(-0.5, -0.18 + wave), Color("#9AA3B5"), 0.05, true)
	_arc(ci, Vector2(-0.5, -0.22 + wave), 0.05, PI * 0.2, PI * 1.8, 10, Color("#9AA3B5"), 0.035, true)
	for x in [-0.14, 0.14]:
		_fill(ci, _ellipse(Vector2(x, 0.54), 0.09, 0.05, 12), dark.darkened(0.2))
	_fill(ci, _ellipse(Vector2(0, 0.22), 0.34, 0.32, 28), RIX_BODY, aa)
	_fill(ci, _ellipse(Vector2(0, -0.14), 0.25, 0.27, 28), RIX_BODY, aa)
	# Tool belt
	_line(ci, Vector2(-0.33, 0.3), Vector2(0.33, 0.3), Color("#7A5C3E"), 0.06, true)
	_rect(ci, Rect2(0.1, 0.27, 0.1, 0.1), Color("#5C6BC0"))
	# Goggles pushed up on the forehead
	_line(ci, Vector2(-0.25, -0.3), Vector2(0.25, -0.3), INK, 0.035, true)
	for x in [-0.1, 0.1]:
		_circle(ci, Vector2(x, -0.3), 0.085, Color("#4A4F66"))
		_circle(ci, Vector2(x, -0.3), 0.06, RIX_LENS)
		_circle(ci, Vector2(x - 0.02, -0.32), 0.018, Color(1, 1, 1, 0.8))
	for x in [-0.1, 0.1]:
		var c := Vector2(x, -0.12)
		match expr:
			"happy", "celebrating":
				_arc(ci, c + Vector2(0, 0.03), 0.055, PI * 1.12, PI * 1.88, 10, INK, 0.028, true)
			"confused":
				if x < 0:
					_circle(ci, c, 0.065, Color.WHITE)
					_circle(ci, c, 0.03, INK)
				else:
					_line(ci, c + Vector2(-0.05, 0), c + Vector2(0.05, -0.02), INK, 0.028, true)
			_:
				var r := 0.075 if expr == "surprised" else 0.065
				_circle(ci, c, r, Color.WHITE)
				_circle(ci, c, r * 0.48, INK)
	for f in [Vector2(-0.16, -0.02), Vector2(-0.12, 0.0), Vector2(0.15, -0.01)]:
		_circle(ci, f, 0.013, dark)
	if expr == "surprised":
		_circle(ci, Vector2(0, 0.04), 0.035, INK)
	else:
		_arc(ci, Vector2(0, 0.0), 0.07, PI * 0.15, PI * 0.85, 10, INK, 0.028, true)
	_reset(ci)


## Portrait helper for any roster entry. `state` is an LFCrewAnim state for package characters;
## mascots map it to the nearest expression.
static func draw_character(ci: CanvasItem, def: Dictionary, pos: Vector2, sz: float, state: int, age: float, t: float, opts := {}) -> void:
	var body := str(def.get("style", {}).get("body", def.get("id", "")))
	match str(def.get("kind", "package")):
		"mascot", "engineer":
			var expr: String = opts.get("expression", mascot_expression(state))
			if body == "rix":
				draw_rix(ci, pos, sz, expr, t, opts)
			else:
				draw_naps(ci, pos, sz, expr, t, opts)
		_:
			var cidx := clampi(int(def.get("color", 0)), 0, 3)
			var pose: Dictionary
			if opts.has("expression"):
				pose = expression(body, str(opts["expression"]))
			else:
				pose = LFCrewAnim.pose(body, state, age, t, int(opts.get("seed", 0)), opts)
			var o := opts.duplicate()
			o["cidx"] = cidx
			o["color"] = LFStyle.PACKAGE[cidx]
			o["style"] = def.get("style", {})
			o["t"] = t
			draw_package(ci, body, pos, sz, pose, o)


static func mascot_expression(state: int) -> String:
	match state:
		LFCrewAnim.SELECTED, LFCrewAnim.DELIVERED, LFCrewAnim.MOVING:
			return "happy"
		LFCrewAnim.SURPRISED:
			return "surprised"
		LFCrewAnim.FAILED:
			return "confused"
		LFCrewAnim.CELEBRATING:
			return "celebrating"
		LFCrewAnim.WAITING:
			return "sleeping"
	return "neutral"
