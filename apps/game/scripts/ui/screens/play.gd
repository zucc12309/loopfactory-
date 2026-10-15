extends LFScreen
## Gameplay: rotate belts, run the deterministic simulation, retry or advance.

const FAIL_TEXT := {
	"off_board": "A package rolled off the edge.",
	"disconnected": "A package hit a belt that isn't connected.",
	"wrong_destination": "A package reached a dock of the wrong color.",
	"deadlock": "Packages got stuck waiting for each other.",
	"loop": "A package is going around in circles.",
	"timeout": "A package is going around in circles.",
}
const STEP_NORMAL := 0.3
const STEP_FAST := 0.14

var level: Dictionary
var kind := "campaign"
var campaign_index := -1
var board: LFBoardView
var moves_label: Label
var title_label: Label
var tip_label: Label
var edit_bar: HBoxContainer
var run_bar: HBoxContainer
var run_btn: Button
var undo_btn: LFIconButton
var pause_btn: LFIconButton
var fast := false
var _failed_once := false
var _locked_told := false
var _tutorial := false


func setup(args: Dictionary) -> void:
	var st: LFGameState = Game.state
	if args.get("resume", false) and st.active() != null:
		level = st.active_level()
		kind = st.active()["kind"]
		campaign_index = st.campaign_index.get(level["id"], -1) if kind == "campaign" else -1
	else:
		kind = args.get("kind", "campaign")
		match kind:
			"campaign":
				campaign_index = int(args.get("index", 0))
				level = st.campaign[campaign_index]
			"endless":
				level = st.endless_level()
			_:
				level = args["level"]
		var resumable = st.active()
		if resumable != null and resumable["levelId"] == level["id"] and resumable["kind"] == kind:
			pass  # same puzzle already in progress — keep the player's rotations
		else:
			st.start_level(kind, level)
			if kind == "daily" or kind == "offline_daily":
				st.active()["date"] = args.get("date", "")
		Game.request_save()
	Analytics.track("level_start", {"level_id": level["id"], "kind": kind, "difficulty": level.get("difficulty", ""), "par": level["par"]})
	if kind == "daily":
		Analytics.track("daily_challenge_started", {"date": str(st.active().get("date", ""))})
	_build()


func _build() -> void:
	var sm: Vector2 = main.safe_margins()
	var root := LFStyle.vbox(20)
	var m := LFStyle.margin(root, 32, 32 + int(sm.x), 32, 36 + int(sm.y))
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)

	# Top bar
	var top := LFStyle.hbox(16)
	var back := LFIconButton.make("back", "", "SecondaryButton", 88)
	back.pressed.connect(func(): main.back())
	top.add_child(back)
	var tcol := LFStyle.vbox(0)
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label = LFStyle.label(level["name"], 34, LFStyle.TEXT, 800)
	title_label.clip_text = true
	tcol.add_child(title_label)
	var subtitle := ""
	match kind:
		"campaign":
			subtitle = "Level %d · %s" % [campaign_index + 1, str(level.get("difficulty", "")).capitalize()]
		"endless":
			subtitle = "Endless · %s" % str(level.get("difficulty", "")).capitalize()
		"daily":
			subtitle = "Daily challenge · ranked"
		"offline_daily":
			subtitle = "Offline practice · not ranked"
	tcol.add_child(LFStyle.label(subtitle, 22, LFStyle.DIFFICULTY_COLORS.get(level.get("difficulty", ""), LFStyle.TEXT_MUTED).darkened(0.25), 700))
	top.add_child(tcol)
	var mcard := LFStyle.card(LFStyle.SURFACE, 16)
	moves_label = LFStyle.label("", 26, LFStyle.TEXT, 800, HORIZONTAL_ALIGNMENT_CENTER)
	mcard.add_child(moves_label)
	top.add_child(mcard)
	root.add_child(top)

	tip_label = LFStyle.label(str(level.get("tip", "")), 25, LFStyle.TEXT_MUTED, 700, HORIZONTAL_ALIGNMENT_CENTER)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(0, 70)
	tip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(tip_label)

	board = LFBoardView.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.reduced_motion = main.reduced_motion()
	board.colorblind = bool(Game.settings().get("colorblind", false))
	root.add_child(board)
	board.set_level(level, Game.state.active()["rotations"])
	board.rotate_requested.connect(_on_rotate)
	board.locked_tapped.connect(_on_locked)
	board.playback_finished.connect(_on_finished)
	board.package_delivered.connect(func(_c): Sfx.play("deliver", 1.0 + randf() * 0.1); Sfx.haptic(15))

	# Edit controls
	edit_bar = LFStyle.hbox(14)
	undo_btn = LFIconButton.make("undo", "Undo")
	undo_btn.pressed.connect(_undo)
	var reset := LFIconButton.make("reset", "Reset")
	reset.pressed.connect(_reset)
	var hint := LFIconButton.make("hint", "Hint")
	hint.pressed.connect(_hint)
	if kind == "daily":
		hint.disabled = true
	run_btn = LFStyle.button("Run", "", 104)
	run_btn.add_theme_font_size_override("font_size", 38)
	run_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_btn.pressed.connect(_run)
	for c in [undo_btn, reset, hint, run_btn]:
		edit_bar.add_child(c)
	root.add_child(edit_bar)

	# Simulation controls
	run_bar = LFStyle.hbox(14)
	pause_btn = LFIconButton.make("pause", "Pause")
	pause_btn.pressed.connect(_toggle_pause)
	var speed := LFIconButton.make("fast", "Speed")
	speed.pressed.connect(_toggle_speed)
	var stop := LFStyle.button("Stop", "SecondaryButton", 104)
	stop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop.pressed.connect(_stop)
	for c in [pause_btn, speed, stop]:
		run_bar.add_child(c)
	run_bar.visible = false
	root.add_child(run_bar)

	_tutorial = level["id"] == "c01" and Game.state.moves_count() == 0
	if _tutorial:
		var h = LFSolver.hint(level, Game.state.active()["rotations"])
		if h != null:
			board.tutorial_tile = h["tile"]
	_refresh()


func _refresh() -> void:
	var n := Game.state.moves_count()
	moves_label.text = "Moves %d\nPar %d" % [n, level["par"]]
	undo_btn.disabled = n == 0


func on_back() -> bool:
	if board.playing or not board._frames.is_empty():
		_stop()
		return true
	Game.save_now()
	return false


func _on_rotate(i: int, dir: int) -> void:
	if not Game.state.rotate(i, dir):
		return
	board.animate_rotation(i, dir)
	board._fail_cell = -1
	Sfx.play("rotate" if dir == 1 else "ccw", 1.0 + randf() * 0.06)
	Sfx.haptic(10)
	if _tutorial:
		board.tutorial_tile = -1
		tip_label.text = "Path ready? Press Run."
		_pulse(run_btn)
	_refresh()
	Game.request_save()


func _on_locked(_i: int) -> void:
	Sfx.haptic(30)
	if not _locked_told:
		_locked_told = true
		main.toast("That tile can't be turned.")


func _undo() -> void:
	var mv = Game.state.undo()
	if mv == null:
		return
	board.animate_rotation(int(mv[0]), -int(mv[1]))
	_refresh()
	Game.request_save()


func _reset() -> void:
	if Game.state.moves_count() == 0:
		return
	Game.state.reset()
	board.sync_rotations(Game.state.active()["rotations"])
	board._fail_cell = -1
	_refresh()
	Game.request_save()


func _hint() -> void:
	var h = LFSolver.hint(level, Game.state.active()["rotations"])
	if h == null:
		main.toast("Looks ready — try Run!")
		return
	Game.state.record_hint()
	board.show_hint(h["tile"], h["dir"], h["taps"])
	Analytics.track("hint_used", {"level_id": level["id"], "kind": kind})
	Game.request_save()


func _run() -> void:
	board.stop_playback()
	var result := LFSimulation.simulate(level, Game.state.active()["rotations"])
	if _failed_once:
		Analytics.track("level_retry", {"level_id": level["id"], "kind": kind})
	board.interactive = false
	board.hint_tile = -1
	edit_bar.visible = false
	run_bar.visible = true
	board.paused = false
	pause_btn.icon_name = "pause"
	pause_btn.caption = "Pause"
	pause_btn.queue_redraw()
	Sfx.play("run")
	board.start_playback(result, STEP_FAST if fast else STEP_NORMAL)


func _toggle_pause() -> void:
	board.paused = not board.paused
	pause_btn.icon_name = "play" if board.paused else "pause"
	pause_btn.caption = "Resume" if board.paused else "Pause"
	pause_btn.queue_redraw()


func _toggle_speed() -> void:
	fast = not fast
	board.step_time = STEP_FAST if fast else STEP_NORMAL
	main.toast("Speed ×2" if fast else "Normal speed", LFStyle.TEXT, 0.8)


func _stop() -> void:
	board.stop_playback()
	_back_to_edit()


func _back_to_edit() -> void:
	board.interactive = true
	edit_bar.visible = true
	run_bar.visible = false
	_refresh()


func _on_finished(result: Dictionary) -> void:
	if not is_inside_tree():
		return
	if result["success"]:
		Sfx.play("win")
		Sfx.haptic(40)
		var res := Game.complete_active()
		if res.is_empty():
			_back_to_edit()
			return
		Analytics.track("level_complete", {"level_id": level["id"], "kind": kind, "moves": res["moves"], "par": res["par"], "stars": res["stars"], "hints": 0})
		if kind == "daily":
			Analytics.track("daily_challenge_completed", {"moves": res["moves"]})
		_show_win(res)
	else:
		_failed_once = true
		Sfx.play("fail")
		Sfx.haptic(60)
		Analytics.track("level_fail", {"level_id": level["id"], "kind": kind, "reason": str(result["reason"])})
		main.toast(FAIL_TEXT.get(str(result["reason"]), "Not quite.") + " Adjust and try again.", LFStyle.ERROR)
		var keep_fail: int = board._fail_cell
		board.stop_playback()
		board._fail_cell = keep_fail
		_back_to_edit()


func _show_win(res: Dictionary) -> void:
	var card := LFStyle.card()
	var v := LFStyle.vbox(18)
	card.add_child(LFStyle.margin(v, 20, 24, 20, 20))
	v.add_child(LFStyle.label("Delivered!", 56, LFStyle.TEXT, 800, HORIZONTAL_ALIGNMENT_CENTER))
	var stars := Control.new()
	stars.custom_minimum_size = Vector2(0, 110)
	var n: int = res["stars"]
	var t0 := Time.get_ticks_msec()
	var rm: bool = main.reduced_motion()
	stars.draw.connect(func():
		var w := stars.size.x
		for k in 3:
			var c := Vector2(w / 2 + (k - 1) * 110, 55)
			var age := (Time.get_ticks_msec() - t0) / 1000.0 - k * 0.15
			var sc := 1.0 if rm else clampf(age * 4.0, 0.0, 1.0)
			var col := LFStyle.ACCENT if k < n else LFStyle.SURFACE_2
			LFIcons.draw_icon(stars, "star", Rect2(c - Vector2(60, 60) * sc, Vector2(120, 120) * sc), col))
	stars.set_process(true)
	var tw := create_tween()
	tw.tween_method(func(_x): stars.queue_redraw(), 0.0, 1.0, 1.0)
	v.add_child(stars)
	var line := "%d moves · par %d" % [res["moves"], res["par"]]
	v.add_child(LFStyle.label(line, 30, LFStyle.TEXT, 700, HORIZONTAL_ALIGNMENT_CENTER))
	var note := ""
	if res["moves"] <= res["par"]:
		note = "Perfect — the fewest rotations possible."
	elif res["newBest"]:
		note = "New personal best!"
	else:
		note = "Best: %d moves" % res["best"]
	v.add_child(LFStyle.label(note, 24, LFStyle.TEXT_MUTED, 400, HORIZONTAL_ALIGNMENT_CENTER))
	var row := LFStyle.hbox(16)
	var home := LFStyle.button("Home", "SecondaryButton", 96)
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home.pressed.connect(func(): main.close_overlay(); main.home())
	row.add_child(home)
	match kind:
		"campaign":
			var nxt := LFStyle.button("Next", "", 96)
			nxt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var has_next := campaign_index + 1 < Game.state.campaign.size()
			nxt.text = "Next" if has_next else "Done"
			nxt.pressed.connect(func():
				main.close_overlay()
				if has_next:
					main.replace("play", {"kind": "campaign", "index": campaign_index + 1})
				else:
					main.home())
			row.add_child(nxt)
		"endless":
			var nxt2 := LFStyle.button("Next puzzle", "", 96)
			nxt2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nxt2.pressed.connect(func(): main.close_overlay(); main.replace("play", {"kind": "endless"}))
			row.add_child(nxt2)
		"daily", "offline_daily":
			var share := LFStyle.button("Share", "AccentButton", 96)
			share.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			share.pressed.connect(func(): _share(res))
			row.add_child(share)
	v.add_child(row)
	main.overlay(card, false)


func _share(res: Dictionary) -> void:
	var date := str(level.get("date", LFGameState.utc_date()))
	var squares := ""
	for k in 3:
		squares += "🟧" if k < res["stars"] else "⬜"
	var label := "Daily" if kind == "daily" else "Practice"
	var text := "Loop Factory %s %s\n%s %d rotations (par %d)" % [label, date, squares, res["moves"], res["par"]]
	DisplayServer.clipboard_set(text)
	Analytics.track("share_clicked", {"kind": kind})
	main.toast("Result copied — paste it anywhere.", LFStyle.PRIMARY)


func _pulse(c: Control) -> void:
	if main.reduced_motion():
		return
	c.pivot_offset = c.size / 2
	var tw := create_tween().set_loops(3)
	tw.tween_property(c, "scale", Vector2(1.06, 1.06), 0.25)
	tw.tween_property(c, "scale", Vector2.ONE, 0.25)
