extends LFScreen
## Home: one big Continue action, daily + endless cards, level grid, profile and settings.
## With the crew enabled, Captain Naps idles where the logo was: optional one-line bubble, tap the mascot
## for another line, never in the way of Continue.

var _status: Label
var _naps: LFCrewPortrait
var _bubble: PanelContainer
var _bubble_text: Label
var _line: Dictionary = {}


func setup(_args: Dictionary) -> void:
	if LFCrew.current()["scifi"]:
		var space := LFSpaceBackdrop.new()
		space.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(space)
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

	var pres := LFCrew.current()
	var logo_wrap := CenterContainer.new()
	if pres["characters"]:
		logo_wrap.add_child(_mascot(pres))
	else:
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
	var levels := LFStyle.button("Worlds" if pres["collection"] else "All levels", "SecondaryButton", 96)
	levels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	levels.pressed.connect(func(): main.goto("levels"))
	bottom.add_child(levels)
	if pres["collection"]:
		var unseen := LFCrew.unseen_count(st.data)
		# Accent colour marks new looks waiting in the collection.
		var crew := LFStyle.button("The Crew", "AccentButton" if unseen > 0 else "SecondaryButton", 96)
		crew.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crew.pressed.connect(func(): main.goto("crew"))
		bottom.add_child(crew)
	if LFFlags.get_variant("daily_entry") != "banner":
		var code := LFStyle.button("Friends", "SecondaryButton", 96)
		code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code.pressed.connect(func(): main.goto("challenge"))
		bottom.add_child(code)
	root.add_child(bottom)

	_status = LFStyle.label("", 22, LFStyle.TEXT_MUTED, 400, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_status)
	_update_status()
	Net.online_changed.connect(func(_o): _update_status())
	Net.synced.connect(_update_status)


func _mascot(pres: Dictionary) -> Control:
	var row := LFStyle.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_naps = LFCrewPortrait.make("naps", 230, pres["animations"])
	_naps.cosmetic = LFCrew.art_for(Game.state.data, "naps")
	_naps.mouse_filter = Control.MOUSE_FILTER_STOP
	_naps.tapped.connect(_poke_naps)
	row.add_child(_naps)
	_bubble = LFStyle.card(LFStyle.SURFACE, 22)
	_bubble.custom_minimum_size = Vector2(300, 0)
	_bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bh := LFStyle.hbox(6)
	_bubble.add_child(bh)
	_bubble_text = LFStyle.label("", 24, LFStyle.TEXT, 700)
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(_bubble_text)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(44, 44)
	close.add_theme_color_override("font_color", LFStyle.TEXT_MUTED)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(_dismiss_bubble)
	bh.add_child(close)
	row.add_child(_bubble)
	_show_line(_home_line())
	LFCrew.expose("home", {"character": "naps"})
	return row


## First launch, a world about to open, otherwise an occasional progress remark. Cooldowns stop
## lines repeating; on most visits Captain Naps is simply asleep.
func _home_line() -> Dictionary:
	var st: LFGameState = Game.state
	var vars := {"done": st.completed_count(), "total": st.campaign.size(), "stars": LFCrew.total_stars(st.data, st.campaign)}
	var line := LFCrew.say("FIRST_LAUNCH", {}, vars) if st.completed_count() == 0 else {}
	if line.is_empty() and st.active() == null:
		var world := LFCrew.world_intro(st.campaign, st.next_campaign_index())
		if world != "":
			line = LFCrew.say("NEW_WORLD", {"world": world}, vars)
	if line.is_empty() and st.completed_count() > 0:
		line = LFCrew.say("HOME_IDLE", {}, vars)
	return line


func _show_line(line: Dictionary) -> void:
	_line = line
	_bubble.visible = not line.is_empty()
	if line.is_empty():
		_naps.expression = "sleeping"
	else:
		_bubble_text.text = str(line["text"])
		_naps.expression = str(line.get("anim", "neutral"))
	_naps.queue_redraw()


func _poke_naps() -> void:
	var st: LFGameState = Game.state
	var line := LFCrew.say("HOME_TAP", {}, {"done": st.completed_count()}, true)
	Sfx.play("mrrp", 0.95 + randf() * 0.1)
	Sfx.haptic_pattern("light")
	Analytics.track("character_animation_played", {"character": "naps", "animation": "tap", "surface": "home"})
	if line.is_empty():
		_naps.expression = "surprised"
		_naps.queue_redraw()
		return
	_show_line(line)


func _dismiss_bubble() -> void:
	Sfx.play("ui")
	if not _line.is_empty():
		Analytics.track("character_dialogue_dismissed", {"character": str(_line.get("character", "")), "line_id": str(_line.get("id", "")), "surface": "home"})
	_line = {}
	_bubble.visible = false
	_naps.expression = "sleeping"
	_naps.queue_redraw()


func on_shown() -> void:
	# Never on a fresh install: the optional consent waits until the player has delivered a package.
	if main.consent_due():
		get_tree().create_timer(0.6).timeout.connect(func(): if is_inside_tree() and main.current == self: main.ask_consent())


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
