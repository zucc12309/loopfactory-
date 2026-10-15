extends SceneTree
## Renders the character sheet used in docs/CHARACTER_ART_GUIDE.md (all expressions, compact
## detail and every look) straight from the game's painter:
##   xvfb-run godot --path apps/game --rendering-driver opengl3 -s res://tests_ui/crew_sheet.gd -- --out=/abs/sheet.png

const COL := 150
const ROW := 170
const LEFT := 150


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://crew_sheet.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var Painter: GDScript = load("res://scripts/crew/crew_painter.gd")
	var Crew: GDScript = load("res://scripts/crew/crew.gd")
	var font: Font = load("res://assets/fonts/nunito-latin-800-normal.woff2")
	var exprs := ["neutral", "happy", "surprised", "confused", "celebrating"]
	var vp := SubViewport.new()
	vp.size = Vector2i(LEFT + COL * 9 + 20, 90 + ROW * 6 + 20)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var c := Control.new()
	c.size = Vector2(vp.size)
	vp.add_child(c)
	root.add_child(vp)
	var ink := Color("#282B3C")
	var muted := Color("#6F7287")
	c.draw.connect(func():
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color("#F7F5F0"))
		var heads := exprs + ["compact / zzz", "look 1", "look 2", "look 3"]
		for k in heads.size():
			var w := font.get_string_size(heads[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			c.draw_string(font, Vector2(LEFT + k * COL + COL / 2.0 - w / 2.0, 50), heads[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, muted)
		var ids := ["bloop", "zip", "glitch", "mochi", "naps", "rix"]
		for r in ids.size():
			var def: Dictionary = Crew.get_def(ids[r])
			var y := 90 + r * ROW + ROW / 2.0
			c.draw_string(font, Vector2(20, y + 8), str(def["name"]).replace("Captain ", "Capt. "), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ink)
			var mascot: bool = def["kind"] != "package"
			var sz := 118.0 if mascot else 92.0
			var dy := 0.0 if mascot else 6.0
			var row_exprs: Array = exprs.duplicate()
			if ids[r] == "naps":
				row_exprs.append("sleeping")
			for k in row_exprs.size():
				Painter.draw_character(c, def, Vector2(LEFT + k * COL + COL / 2.0, y + dy), sz, 0, 0.0, 0.0, {"motion": false, "expression": row_exprs[k]})
			if not mascot:
				Painter.draw_character(c, def, Vector2(LEFT + 5 * COL + COL / 2.0, y + 4), 32, 0, 0.0, 0.0, {"motion": false, "expression": "happy"})
			var cos: Array = def.get("cosmetics", [])
			for k in cos.size():
				Painter.draw_character(c, def, Vector2(LEFT + (6 + k) * COL + COL / 2.0, y + dy), sz, 0, 0.0, 0.0, {"motion": false, "expression": "happy", "cosmetic": cos[k]["art"]})
	)
	await process_frame
	await process_frame
	await process_frame
	vp.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
