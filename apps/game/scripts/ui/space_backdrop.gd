class_name LFSpaceBackdrop
extends Control
## Backdrop for the "full" presentation variant (sci-fi treatment): soft stars, a ringed planet
## and a faint portal ring behind the screen content. Light, low-contrast colours so the board,
## text and package colours keep exactly the same readability as the other variants. Static
## (drawn once) — no per-frame cost.

var tint := Color("#A7B8FF")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var star := Color(tint.darkened(0.25), 0.35)
	for k in 46:
		# Deterministic layout (no RNG): the same screen always looks the same.
		var x := fposmod(k * 157.31, w)
		var y := fposmod(k * 263.77 + k * k * 3.1, h)
		var r := 1.5 + float(k % 3)
		if k % 7 == 0:
			draw_colored_polygon(PackedVector2Array([Vector2(x, y - r * 2.5), Vector2(x + r * 0.7, y), Vector2(x, y + r * 2.5), Vector2(x - r * 0.7, y)]), star)
			draw_colored_polygon(PackedVector2Array([Vector2(x - r * 2.5, y), Vector2(x, y - r * 0.7), Vector2(x + r * 2.5, y), Vector2(x, y + r * 0.7)]), star)
		else:
			draw_circle(Vector2(x, y), r, star)
	var pc := Vector2(w * 0.86, h * 0.12)
	draw_circle(pc, 58, Color(tint, 0.22))
	draw_arc(pc, 92, PI * 0.92, PI * 2.08, 48, Color(tint.darkened(0.2), 0.25), 8, true)
	draw_arc(Vector2(w * 0.1, h * 0.9), 70, 0, TAU, 64, Color(LFStyle.ACCENT, 0.18), 10, true)
	draw_arc(Vector2(w * 0.1, h * 0.9), 46, 0, TAU, 48, Color(tint, 0.2), 6, true)
