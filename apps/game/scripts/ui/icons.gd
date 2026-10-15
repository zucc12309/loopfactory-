class_name LFIcons
## Vector icon set drawn with CanvasItem primitives.


static func draw_icon(ci: CanvasItem, name: String, area: Rect2, col: Color) -> void:
	var c := area.get_center()
	var s := minf(area.size.x, area.size.y) * 0.3
	var w := maxf(3.0, s * 0.2)
	match name:
		"back":
			ci.draw_polyline(PackedVector2Array([c + Vector2(s * 0.35, -s * 0.7), c + Vector2(-s * 0.35, 0), c + Vector2(s * 0.35, s * 0.7)]), col, w, true)
		"undo":
			ci.draw_arc(c + Vector2(s * 0.1, s * 0.1), s * 0.6, -PI * 0.5, PI * 0.6, 20, col, w, true)
			ci.draw_line(c + Vector2(s * 0.1, -s * 0.5), c + Vector2(-s * 0.6, -s * 0.5), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.85, -s * 0.5), c + Vector2(-s * 0.4, -s * 0.85), c + Vector2(-s * 0.4, -s * 0.15)]), col)
		"reset":
			ci.draw_arc(c, s * 0.65, -PI * 0.35, PI * 1.45, 28, col, w, true)
			var tip := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * s * 0.65
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(-s * 0.35, -s * 0.1), tip + Vector2(s * 0.15, -s * 0.35), tip + Vector2(s * 0.1, s * 0.25)]), col)
		"hint":
			ci.draw_circle(c + Vector2(0, -s * 0.2), s * 0.5, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.25, s * 0.3), Vector2(s * 0.5, s * 0.25)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.18, s * 0.62), Vector2(s * 0.36, s * 0.12)), col)
		"play":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.45, -s * 0.65), c + Vector2(s * 0.65, 0), c + Vector2(-s * 0.45, s * 0.65)]), col)
		"pause":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.5, -s * 0.6), Vector2(s * 0.32, s * 1.2)), col)
			ci.draw_rect(Rect2(c + Vector2(s * 0.18, -s * 0.6), Vector2(s * 0.32, s * 1.2)), col)
		"stop":
			ci.draw_rect(Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), col)
		"fast":
			for k in 2:
				var o := Vector2(-s * 0.6 + k * s * 0.6, 0)
				ci.draw_colored_polygon(PackedVector2Array([c + o + Vector2(0, -s * 0.5), c + o + Vector2(s * 0.6, 0), c + o + Vector2(0, s * 0.5)]), col)
		"gear":
			for k in 8:
				var a := k * TAU / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * s * 0.45, c + Vector2(cos(a), sin(a)) * s * 0.85, col, w * 1.3, true)
			ci.draw_circle(c, s * 0.55, col)
			ci.draw_circle(c, s * 0.22, LFStyle.SURFACE)
		"user":
			ci.draw_circle(c + Vector2(0, -s * 0.35), s * 0.38, col)
			ci.draw_arc(c + Vector2(0, s * 0.75), s * 0.7, PI, TAU, 20, col, w * 1.6, true)
		"trophy":
			ci.draw_arc(c + Vector2(0, -s * 0.25), s * 0.5, 0, PI, 16, col, w * 2.2, true)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.08, s * 0.2), Vector2(s * 0.16, s * 0.35)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.4, s * 0.55), Vector2(s * 0.8, s * 0.14)), col)
		"calendar":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.55), Vector2(s * 1.4, s * 1.25)), col, false, w)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.55), Vector2(s * 1.4, s * 0.35)), col)
			ci.draw_circle(c + Vector2(0, s * 0.25), s * 0.18, col)
		"infinity":
			ci.draw_arc(c + Vector2(-s * 0.42, 0), s * 0.38, 0, TAU, 24, col, w, true)
			ci.draw_arc(c + Vector2(s * 0.42, 0), s * 0.38, 0, TAU, 24, col, w, true)
		"grid":
			for yy in 2:
				for xx in 2:
					ci.draw_rect(Rect2(c + Vector2(-s * 0.65 + xx * s * 0.7, -s * 0.65 + yy * s * 0.7), Vector2(s * 0.55, s * 0.55)), col)
		"share":
			var pts := [c + Vector2(s * 0.5, -s * 0.55), c + Vector2(-s * 0.5, 0), c + Vector2(s * 0.5, s * 0.55)]
			ci.draw_line(pts[0], pts[1], col, w, true)
			ci.draw_line(pts[1], pts[2], col, w, true)
			for p in pts:
				ci.draw_circle(p, s * 0.22, col)
		"lock":
			ci.draw_arc(c + Vector2(0, -s * 0.15), s * 0.38, PI, TAU, 14, col, w, true)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.55, -s * 0.15), Vector2(s * 1.1, s * 0.85)), col)
		"check":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.6, 0), c + Vector2(-s * 0.15, s * 0.45), c + Vector2(s * 0.65, -s * 0.45)]), col, w * 1.3, true)
		"star":
			var poly := PackedVector2Array()
			for k in 10:
				var a := -PI / 2 + k * PI / 5
				var rr := s * (0.8 if k % 2 == 0 else 0.36)
				poly.append(c + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(poly, col)
		"rotate_cw", "rotate_ccw":
			var cw := name == "rotate_cw"
			ci.draw_arc(c, s * 0.6, -PI * 0.9, PI * 0.4, 20, col, w, true)
			var a2 := PI * 0.4 if cw else -PI * 0.9
			var tp := c + Vector2(cos(a2), sin(a2)) * s * 0.6
			var tan := Vector2(-sin(a2), cos(a2)) * (1.0 if cw else -1.0)
			ci.draw_colored_polygon(PackedVector2Array([tp + tan * s * 0.35, tp + tan.orthogonal() * s * 0.25, tp - tan.orthogonal() * s * 0.25]), col)
