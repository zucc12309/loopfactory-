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
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for i in st.campaign.size():
		grid.add_child(_cell(i))


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
				var c := Vector2(b.size.x / 2 + (k - 1) * 30, b.size.y * 0.76)
				LFIcons.draw_icon(b, "star", Rect2(c - Vector2(16, 16), Vector2(32, 32)), LFStyle.ACCENT if k < stars else Color(LFStyle.TEXT_MUTED, 0.25))
		else:
			LFIcons.draw_icon(b, "lock", Rect2(Vector2.ZERO, b.size), Color(LFStyle.TEXT_MUTED, 0.6))
		b.draw_rect(Rect2(b.size.x * 0.3, 10, b.size.x * 0.4, 6), diff_col))
	b.pressed.connect(func():
		Sfx.play("ui")
		main.goto("play", {"kind": "campaign", "index": i}))
	return b
