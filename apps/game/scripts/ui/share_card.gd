class_name LFShareCard
## Shareable result card (1080×1350 PNG, 4:5 portrait) rendered off-screen in a SubViewport, plus
## the share text. It never shows the solution — only date, difficulty, rotations vs par, stars,
## attempts and (for challenges) the code.
##
## Platform notes (docs/sharing.md): Godot has no built-in native share sheet. The card is saved
## to the app's data folder (and to Pictures on desktop) and the text is copied to the clipboard.
## A native share intent needs a small Android/iOS plugin — integration boundary: `native_share()`.

const W := 1080
const H := 1350


static func share_text(d: Dictionary) -> String:
	var stars := ""
	for k in 3:
		stars += "⭐" if k < int(d.get("stars", 0)) else "▫️"
	var head := "Loop Factory"
	match str(d.get("kind", "")):
		"daily":
			head += " Daily %s" % d.get("date", "")
		"offline_daily":
			head += " Practice %s" % d.get("date", "")
		"challenge":
			head += " Challenge %s" % d.get("code", "")
		_:
			head += " · %s" % d.get("levelName", "")
	var tries := int(d.get("attempts", 1))
	return "%s\n%s %d rotations (par %d) · %d tr%s" % [head, stars, int(d["rotations"]), int(d["par"]), tries, "y" if tries == 1 else "ies"]


## Render the card to an Image. Must be awaited (needs two frames to draw).
static func render(host: Node, d: Dictionary) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := Control.new()
	canvas.size = Vector2(W, H)
	canvas.draw.connect(func(): _draw_card(canvas, d))
	vp.add_child(canvas)
	host.add_child(vp)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


static func _text(ci: CanvasItem, s: String, pos: Vector2, size: int, color: Color, weight := 800, center := true) -> void:
	var f := LFStyle.font(weight)
	var x := pos.x
	if center:
		x -= f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x / 2.0
	ci.draw_string(f, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func _draw_card(ci: Control, d: Dictionary) -> void:
	ci.draw_rect(Rect2(0, 0, W, H), LFStyle.PRIMARY)
	# Soft belt motif behind the card.
	for k in 7:
		var y := 120.0 + k * 180.0
		ci.draw_line(Vector2(-40, y), Vector2(W + 40, y - 160), Color(1, 1, 1, 0.06), 70.0)
	var card := Rect2(70, 150, W - 140, H - 300)
	ci.draw_style_box(LFStyle.box(LFStyle.SURFACE, 48), card)
	var cx := W / 2.0
	_text(ci, "LOOP FACTORY", Vector2(cx, 105), 52, Color.WHITE)
	var label := "Daily challenge"
	match str(d.get("kind", "")):
		"offline_daily":
			label = "Practice puzzle · not ranked"
		"challenge":
			label = "Friend challenge"
		"campaign":
			label = str(d.get("levelName", ""))
		"endless":
			label = "Endless · " + str(d.get("levelName", ""))
	_text(ci, label, Vector2(cx, 260), 46, LFStyle.TEXT)
	var sub := str(d.get("date", ""))
	var diff := str(d.get("difficulty", "")).capitalize()
	if diff != "":
		sub = (sub + " · " if sub != "" else "") + diff
	_text(ci, sub, Vector2(cx, 320), 34, LFStyle.TEXT_MUTED, 700)
	for k in 3:
		var col := LFStyle.ACCENT if k < int(d.get("stars", 0)) else LFStyle.SURFACE_2
		LFIcons.draw_icon(ci, "star", Rect2(Vector2(cx - 110 + (k - 1) * 190, 340), Vector2(220, 220)), col)
	_text(ci, str(int(d["rotations"])), Vector2(cx, 760), 230, LFStyle.TEXT)
	_text(ci, "rotations · par %d" % int(d["par"]), Vector2(cx, 830), 44, LFStyle.TEXT_MUTED, 700)
	var tries := int(d.get("attempts", 1))
	var badge := "Perfect solve" if int(d["rotations"]) <= int(d["par"]) else "%d tr%s" % [tries, "y" if tries == 1 else "ies"]
	var bw := 420.0
	ci.draw_style_box(LFStyle.box(LFStyle.SUCCESS.lerp(Color.WHITE, 0.75), 36, false), Rect2(cx - bw / 2, 880, bw, 84))
	_text(ci, badge, Vector2(cx, 937), 38, LFStyle.TEXT)
	# Package symbols row — branding without revealing anything about the solution.
	for k in 4:
		var c := Vector2(cx - 180 + k * 120, 1070)
		ci.draw_style_box(LFStyle.box(LFStyle.PACKAGE[k], 18, false), Rect2(c - Vector2(40, 40), Vector2(80, 80)))
		LFStyle.draw_symbol(ci, LFStyle.SYMBOLS[k], c, 16, Color.WHITE)
	var code := str(d.get("code", ""))
	_text(ci, ("Code " + code) if code != "" else "Can you beat it?", Vector2(cx, H - 70), 44, Color.WHITE)


## Save the PNG where the player can find it. Returns the path written (desktop: Pictures folder).
static func save_png(img: Image, d: Dictionary) -> String:
	var name := "loop-factory-%s-%s.png" % [str(d.get("kind", "result")), str(d.get("date", "")).replace("-", "")]
	DirAccess.make_dir_recursive_absolute("user://share")
	var path := "user://share/" + name
	img.save_png(path)
	if not OS.has_feature("mobile"):
		var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
		if pics != "" and DirAccess.dir_exists_absolute(pics):
			var out := pics.path_join(name)
			if img.save_png(out) == OK:
				return out
	return ProjectSettings.globalize_path(path)


## Integration boundary for a native share sheet plugin (Android intent / iOS
## UIActivityViewController). Returns false when no plugin is installed (the default).
static func native_share(text: String, png_path: String) -> bool:
	if Engine.has_singleton("LoopFactoryShare"):
		Engine.get_singleton("LoopFactoryShare").call("share", text, png_path)
		return true
	return false


## Overlay with the rendered card, Copy text and Save image actions.
static func present(main: Node, d: Dictionary, on_close := Callable()) -> void:
	var img: Image = await render(main, d)
	var card := LFStyle.card()
	var v := LFStyle.vbox(16)
	card.add_child(LFStyle.margin(v, 16, 16, 16, 16))
	v.add_child(LFStyle.label("Share your result", 36, LFStyle.TEXT, 800, HORIZONTAL_ALIGNMENT_CENTER))
	var tex := TextureRect.new()
	tex.texture = ImageTexture.create_from_image(img)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.custom_minimum_size = Vector2(0, 560)
	v.add_child(tex)
	var text := share_text(d)
	var row := LFStyle.hbox(14)
	var copy := LFStyle.button("Copy text", "SecondaryButton", 92)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(text)
		Analytics.track("share_completed", {"kind": str(d.get("kind", "")), "method": "clipboard"})
		main.toast("Result copied — paste it anywhere.", LFStyle.PRIMARY))
	row.add_child(copy)
	var save := LFStyle.button("Save image", "", 92)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(func():
		var path := save_png(img, d)
		if native_share(text, path):
			Analytics.track("share_completed", {"kind": str(d.get("kind", "")), "method": "native"})
			return
		DisplayServer.clipboard_set(text)
		Analytics.track("share_completed", {"kind": str(d.get("kind", "")), "method": "image"})
		main.toast("Image saved to %s · text copied" % path, LFStyle.PRIMARY, 3.5))
	row.add_child(save)
	v.add_child(row)
	var close := LFStyle.button("Close", "SecondaryButton", 80)
	close.pressed.connect(func(): main.close_overlay(); if on_close.is_valid(): on_close.call())
	v.add_child(close)
	main.overlay(card, not on_close.is_valid())


## Overlay shown after creating a friend challenge.
static func present_challenge(main: Node, out: Dictionary, rotations: int, on_close := Callable()) -> void:
	var card := LFStyle.card()
	var v := LFStyle.vbox(16)
	card.add_child(LFStyle.margin(v, 16, 16, 16, 16))
	v.add_child(LFStyle.label("Challenge ready!", 40, LFStyle.TEXT, 800, HORIZONTAL_ALIGNMENT_CENTER))
	var body := LFStyle.label("Your friend plays the same puzzle and tries to beat %d rotations. They can open the link, or enter the code on the Home screen — no account needed." % rotations, 24, LFStyle.TEXT_MUTED, 400, HORIZONTAL_ALIGNMENT_CENTER)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)
	var code_card := LFStyle.card(LFStyle.SURFACE_2, 20)
	code_card.add_child(LFStyle.label(str(out["code"]), 64, LFStyle.PRIMARY, 800, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(code_card)
	var url := str(out.get("url", ""))
	var text := "Can you beat my %d rotations in Loop Factory? Challenge code %s%s" % [rotations, out["code"], ("\n" + url) if url != "" else ""]
	var copy := LFStyle.button("Copy invite", "", 96)
	copy.pressed.connect(func():
		if not native_share(text, ""):
			DisplayServer.clipboard_set(text)
			main.toast("Invite copied — send it to a friend.", LFStyle.PRIMARY)
		Analytics.track("share_completed", {"kind": "challenge", "method": "clipboard"}))
	v.add_child(copy)
	var close := LFStyle.button("Done", "SecondaryButton", 84)
	close.pressed.connect(func(): main.close_overlay(); if on_close.is_valid(): on_close.call())
	v.add_child(close)
	main.overlay(card, not on_close.is_valid())
