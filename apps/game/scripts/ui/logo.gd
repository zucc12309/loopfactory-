class_name LFLogo
extends Control
## Animated brand mark: a looping conveyor with a package travelling around it.

var t := 0.0
var animate := true


func _ready() -> void:
	custom_minimum_size = Vector2(220, 220)


func _process(delta: float) -> void:
	if animate:
		t += delta
		queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) * 0.32
	var bw := r * 0.42
	draw_style_box(LFStyle.box(LFStyle.SURFACE, int(r * 0.5), true), Rect2(c - Vector2(r, r) * 1.45, Vector2(r, r) * 2.9))
	draw_arc(c, r, 0, TAU, 64, LFStyle.BELT, bw, true)
	for k in 12:
		var a := k * TAU / 12.0 + t * 0.6
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (r - bw * 0.3), c + d * (r + bw * 0.3), LFStyle.BELT_EDGE, 3.0, true)
	var colors := LFStyle.PACKAGE
	for k in 3:
		var a := t * 1.2 + k * TAU / 3.0
		var p := c + Vector2(cos(a), sin(a)) * r
		var s := bw * 0.8
		draw_set_transform(p, a + PI / 2, Vector2.ONE)
		draw_style_box(LFStyle.box(colors[k], int(s * 0.25), false), Rect2(-Vector2(s, s) / 2, Vector2(s, s)))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	draw_circle(c, r * 0.38, LFStyle.PRIMARY)
	draw_circle(c, r * 0.16, LFStyle.SURFACE)
