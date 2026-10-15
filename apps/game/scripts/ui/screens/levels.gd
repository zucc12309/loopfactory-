extends LFScreen
## Level select grid with stars and generous progressive unlocking.


func setup(_args: Dictionary) -> void:
	var sm: Vector2 = main.safe_margins()
	var root := LFStyle.vbox(24)
	var m := LFStyle.margin(root, 32, 32 + int(sm.x), 32, 24 + int(sm.y))
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var st: LFGameState = Game.state
	root.add_child(header("Levels", LFStyle.label("%d/%d" % [st.completed_count(), st.campaign.size()], 30, LFStyle.TEXT_MUTED, 800)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var col := LFStyle.vbox(22)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	# One section per world: header card (name, mechanic focus, progress) then its level grid.
	for w in LFWorlds.WORLDS.size():
		var r := LFWorlds.range_for(st.campaign, w)
		if r.y <= r.x:
			continue
		col.add_child(_world_header(w, r))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 18)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for i in range(r.x, r.y):
			grid.add_child(_cell(i))
		col.add_child(grid)


func _world_header(w: int, r: Vector2i) -> Control:
	var st: LFGameState = Game.state
	var pal: Dictionary = LFWorlds.palette(w)
	var done := 0
	for i in range(r.x, r.y):
		if st.campaign_completed(i):
			done += 1
	var card := LFStyle.card(pal["plate"], 22)
	var h := LFStyle.hbox(18)
	card.add_child(h)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(72, 72)
	badge.draw.connect(func():
		badge.draw_style_box(LFStyle.box(pal["belt"], 18, false), Rect2(Vector2.ZERO, badge.size))
		var f := LFStyle.font(800)
		var t := str(w + 1)
		var sz := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40)
		badge.draw_string(f, Vector2((badge.size.x - sz.x) / 2, 50), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, LFStyle.TEXT))
	h.add_child(badge)
	var v := LFStyle.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(LFStyle.label(pal["name"], 32, LFStyle.TEXT, 800))
	v.add_child(LFStyle.label(pal["focus"], 22, LFStyle.TEXT_MUTED, 700))
	h.add_child(v)
	var prog := LFStyle.label("%d/%d" % [done, r.y - r.x], 28, LFStyle.TEXT, 800)
	prog.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(prog)
	return card


func _cell(i: int) -> Control:
	var st: LFGameState = Game.state
	var lvl: Dictionary = st.campaign[i]
	var unlocked := st.is_unlocked(i)
	var prog = st.data["progress"].get(lvl["id"])
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 150)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.theme_type_variation = "SecondaryButton"
	var diff_col: Color = LFStyle.DIFFICULTY_COLORS.get(lvl["difficulty"], LFStyle.SECONDARY)
	if prog != null:
		b.add_theme_stylebox_override("normal", LFStyle.box(diff_col.lightened(0.55)))
	b.disabled = not unlocked
	var stars: int = int(prog["stars"]) if prog != null else 0
	b.draw.connect(func():
		var f := LFStyle.font(800)
		var txt := str(i + 1)
		var col := LFStyle.TEXT if unlocked else LFStyle.TEXT_MUTED
		var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 44)
		if unlocked:
			b.draw_string(f, Vector2((b.size.x - sz.x) / 2, b.size.y * 0.52), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, col)
			for k in 3:
				var c := Vector2(b.size.x / 2 + (k - 1) * 34, b.size.y * 0.76)
				LFIcons.draw_icon(b, "star", Rect2(c - Vector2(24, 24), Vector2(48, 48)), LFStyle.ACCENT if k < stars else Color(LFStyle.TEXT_MUTED, 0.25))
		else:
			LFIcons.draw_icon(b, "lock", Rect2(Vector2.ZERO, b.size), Color(LFStyle.TEXT_MUTED, 0.6))
		b.draw_rect(Rect2(b.size.x * 0.3, 10, b.size.x * 0.4, 6), diff_col))
	b.pressed.connect(func():
		Sfx.play("ui")
		main.goto("play", {"kind": "campaign", "index": i}))
	return b
