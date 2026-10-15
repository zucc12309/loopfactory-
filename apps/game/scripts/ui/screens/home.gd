extends LFScreen
## Home: one big Continue action, daily + endless cards, level grid, profile and settings.

var _status: Label


func setup(_args: Dictionary) -> void:
	var sm: Vector2 = main.safe_margins()
	var root := LFStyle.vbox(28)
	var m := LFStyle.margin(root, 40, 40 + int(sm.x), 40, 40 + int(sm.y))
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)

	var top := LFStyle.hbox(16)
	var title := LFStyle.label("Loop Factory", 44, LFStyle.TEXT, 800)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(title)
	var prof := LFIconButton.make("user", "", "SecondaryButton", 92)
	prof.pressed.connect(func(): main.goto("profile"))
	top.add_child(prof)
	var gear := LFIconButton.make("gear", "", "SecondaryButton", 92)
	gear.pressed.connect(func(): main.goto("settings"))
	top.add_child(gear)
	root.add_child(top)

	var logo_wrap := CenterContainer.new()
	var logo := LFLogo.new()
	logo.custom_minimum_size = Vector2(300, 300)
	logo.animate = not main.reduced_motion()
	logo_wrap.add_child(logo)
	logo_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(logo_wrap)

	var st: LFGameState = Game.state
	var done := st.completed_count()
	var total := st.campaign.size()
	var active = st.active()
	var main_card := LFStyle.card(LFStyle.PRIMARY, 28)
	var mv := LFStyle.vbox(10)
	main_card.add_child(LFStyle.margin(mv, 12, 12, 12, 12))
	var heading := "Continue"
	var sub := ""
	if active != null:
		sub = "%s · %d moves so far" % [active["level"]["name"], active["history"].size()]
	else:
		var idx := st.next_campaign_index()
		heading = "Play" if done == 0 else "Continue"
		sub = "%s · Level %d" % [LFWorlds.palette(LFWorlds.index_for(st.campaign, idx))["name"], idx + 1]
	mv.add_child(LFStyle.label(heading, 48, Color.WHITE, 800))
	mv.add_child(LFStyle.label(sub, 26, Color(1, 1, 1, 0.85), 700))
	var bar := ProgressBar.new()
	bar.max_value = total
	bar.value = done
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.add_theme_stylebox_override("background", LFStyle.box(Color(1, 1, 1, 0.25), 7, false))
	var fill := LFStyle.box(LFStyle.ACCENT, 7, false)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	bar.add_theme_stylebox_override("fill", fill)
	mv.add_child(bar)
	mv.add_child(LFStyle.label("%d of %d campaign puzzles solved" % [done, total], 22, Color(1, 1, 1, 0.8), 400))
	main_card.gui_input.connect(func(e): if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT: _continue())
	main_card.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(main_card)

	var today := LFGameState.utc_date()
	var dres = st.data["daily"]["results"].get(today)
	var daily_sub: String = "Solved · %d rotations" % dres["rotations"] if dres else "Today's puzzle"
	var open_daily := func():
		Analytics.track("daily_challenge_entry", {"surface": str(LFFlags.get_variant("daily_entry"))})
		main.goto("daily")
	var row := LFStyle.hbox(20)
	if LFFlags.get_variant("daily_entry") == "banner":
		# Experiment variant: daily as a full-width banner above Continue.
		var banner := _tile_card("calendar", "Daily challenge", daily_sub, open_daily)
		root.add_child(banner)
		root.move_child(banner, main_card.get_index())
		row.add_child(_tile_card("share", "Challenge", "Play a friend's code", func(): main.goto("challenge")))
	else:
		row.add_child(_tile_card("calendar", "Daily", daily_sub, open_daily))
	row.add_child(_tile_card("infinity", "Endless", "Puzzle #%d" % (int(st.data["endless"]["count"]) + 1), _endless))
	root.add_child(row)

	var bottom := LFStyle.hbox(16)
	var levels := LFStyle.button("All levels", "SecondaryButton", 96)
	levels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	levels.pressed.connect(func(): main.goto("levels"))
	bottom.add_child(levels)
	if LFFlags.get_variant("daily_entry") != "banner":
		var code := LFStyle.button("Friend code", "SecondaryButton", 96)
		code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code.pressed.connect(func(): main.goto("challenge"))
		bottom.add_child(code)
	root.add_child(bottom)

	_status = LFStyle.label("", 22, LFStyle.TEXT_MUTED, 400, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_status)
	_update_status()
	Net.online_changed.connect(func(_o): _update_status())
	Net.synced.connect(_update_status)


func on_shown() -> void:
	if not Game.settings().get("analyticsAsked", false):
		get_tree().create_timer(0.6).timeout.connect(_ask_consent)


func _ask_consent() -> void:
	if not is_inside_tree() or Game.settings().get("analyticsAsked", false):
		return
	var card := LFStyle.card()
	var v := LFStyle.vbox(18)
	card.add_child(LFStyle.margin(v, 16, 16, 16, 16))
	v.add_child(LFStyle.label("Help us tune the puzzles?", 36, LFStyle.TEXT, 800))
	var body := LFStyle.label("Share anonymous gameplay stats (levels played, retries, hints). No name, contacts, location or ad tracking. You can change this any time in Settings.", 25, LFStyle.TEXT_MUTED, 400)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)
	var r := LFStyle.hbox(16)
	var no := LFStyle.button("No thanks", "SecondaryButton", 88)
	var yes := LFStyle.button("Share stats", "", 88)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(func(): _consent(false))
	yes.pressed.connect(func(): _consent(true))
	r.add_child(no)
	r.add_child(yes)
	v.add_child(r)
	main.overlay(card, false)


func _consent(v: bool) -> void:
	Game.set_setting("analytics", v)
	Game.set_setting("analyticsAsked", true)
	main.close_overlay()


func _tile_card(icon: String, title: String, sub: String, action: Callable) -> Control:
	var card := LFStyle.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := LFStyle.vbox(6)
	card.add_child(LFStyle.margin(v, 4, 4, 4, 4))
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(64, 64)
	ic.draw.connect(func(): LFIcons.draw_icon(ic, icon, Rect2(Vector2.ZERO, ic.size), LFStyle.PRIMARY))
	v.add_child(ic)
	v.add_child(LFStyle.label(title, 32, LFStyle.TEXT, 800))
	var s := LFStyle.label(sub, 22, LFStyle.TEXT_MUTED, 400)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(s)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(e): if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT: Sfx.play("ui"); action.call())
	return card


func _continue() -> void:
	Sfx.play("ui")
	var st: LFGameState = Game.state
	var active = st.active()
	if active != null:
		main.goto("play", {"resume": true})
	else:
		var idx := st.next_campaign_index()
		main.goto("play", {"kind": "campaign", "index": idx})


func _endless() -> void:
	var active = Game.state.active()
	if active != null and active["kind"] == "endless":
		main.goto("play", {"resume": true})
	else:
		main.goto("play", {"kind": "endless"})


func _update_status() -> void:
	if not is_instance_valid(_status):
		return
	var pending: int = Game.state.data["syncQueue"].size()
	if not Net.enabled():
		_status.text = "Offline mode · progress saved on this device"
	elif not Net.online:
		_status.text = "Playing offline · %d change%s waiting to sync" % [pending, "" if pending == 1 else "s"] if pending > 0 else "Playing offline · progress saved on this device"
	else:
		_status.text = "Synced" if pending == 0 else "Syncing…"
