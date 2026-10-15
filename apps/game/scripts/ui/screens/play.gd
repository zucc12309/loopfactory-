extends LFScreen
## Gameplay: rotate belts, run the deterministic simulation, retry or advance.
## Feedback never covers the board: tips, coaching and failure explanations live in the banner
## between the header and the board; toasts appear at the top of the screen.

const FAIL_TEXT := {
	"off_board": "rolled off the edge of the factory.",
	"disconnected": "hit a belt that isn't connected on that side.",
	"wrong_destination": "reached a dock of the wrong colour.",
	"deadlock": "is stuck — packages are blocking each other.",
	"loop": "is going round in circles.",
	"timeout": "is going round in circles.",
}
const FAIL_TIP := {
	"off_board": "Turn the marked belt so the route stays on the board.",
	"disconnected": "The marked tile doesn't accept packages from that side.",
	"wrong_destination": "Every colour needs its own dock — reroute it.",
	"deadlock": "Give the routes room so they don't block each other.",
	"loop": "Break the loop at the marked tile.",
	"timeout": "Break the loop at the marked tile.",
}
const COACH := {
	"c01": {"title": "Rotate a conveyor", "text": "Tap the glowing belt to turn it.", "finger": "all"},
	"c02": {"title": "Connect the path", "text": "Turn the corners until the belt reaches the matching dock.", "finger": "all"},
	"c03": {"title": "Deliver the package", "text": "Only connect the belts the route needs.", "finger": "first"},
	"c04": {"title": "Pinned belts", "text": "Belts with a pin are locked. Build your route around them.", "finger": "none"},
	"c05": {"title": "Plan ahead", "text": "Fewest turns wins. Match par for three stars.", "finger": "none"},
}
const HINT_CAPTIONS := ["Hint", "Closer", "Show me", "Show me"]
## First level whose par needs a counter-clockwise turn (audit G1); taught here, before c09's tip.
const REVERSE_TEACH_LEVEL := "c08"
const REVERSE_COPY := {"title": "Turn it back", "text": "Tap to turn ↻. Hold to turn ↺."}
## Hint copy per outcome (audit G3). Never claims a solution exists without one.
const HINT_COPY := {
	"solved": ["Looks ready", "Your belts are ready. Hit Run!"],
	"exhausted": ["No hint yet", "No hint found yet. Try again or reset."],
	"unsolvable": ["No route from here", "These belts can't reach every dock from this position. Reset to start fresh."],
}
const STEP_NORMAL := 0.3
const STEP_FAST := 0.14

var level: Dictionary
var kind := "campaign"
var campaign_index := -1
var challenge: Dictionary = {}
var board: LFBoardView
var moves_view: Control
var title_label: Label
var banner: PanelContainer
var banner_icon: Control
var banner_title: Label
var banner_text: Label
var edit_bar: HBoxContainer
var run_bar: HBoxContainer
var run_btn: Button
var undo_btn: LFIconButton
var hint_btn: LFIconButton
var pause_btn: LFIconButton
var fast := false
var _failed_once := false
var _locked_told := false
var _coach: Dictionary = {}
var _banner_kind := ""
var _fail_color := -1
var _win_res: Dictionary = {}
var _date := ""
var _banner_speaker := ""      # crew member shown in the banner icon ("" = none)
var _last_fail_reason := ""
var _poked := false
var _moments: Array = []
var _win_line: Dictionary = {}
var reverse_btn: LFIconButton
var _reverse_tile := -1        # tile the "hold to turn back" cue points at (-1 = not teaching)
var _cw_streak := [-1, 0]      # [tile, consecutive clockwise taps] for the contextual tip
var _reverse_tip_shown := false
var _hint_budget := 100000


func setup(args: Dictionary) -> void:
	var st: LFGameState = Game.state
	if args.get("resume", false) and st.active() != null:
		level = st.active_level()
		kind = st.active()["kind"]
		campaign_index = st.campaign_index.get(level["id"], -1) if kind == "campaign" else -1
		challenge = st.active().get("challenge", {})
		_date = str(st.active().get("date", ""))
	else:
		kind = args.get("kind", "campaign")
		match kind:
			"campaign":
				campaign_index = int(args.get("index", 0))
				level = st.campaign[campaign_index]
			"endless":
				level = st.endless_level()
			_:
				level = LFTiles.normalize_level(args["level"])
		challenge = args.get("challenge", {})
		_date = str(args.get("date", ""))
		var resumable = st.active()
		if resumable != null and resumable["levelId"] == level["id"] and resumable["kind"] == kind:
			pass  # same puzzle already in progress — keep the player's rotations
		else:
			st.start_level(kind, level)
			if kind == "daily" or kind == "offline_daily":
				st.active()["date"] = args.get("date", "")
			if kind == "challenge":
				st.active()["challenge"] = challenge
		Game.request_save()
	Analytics.track("level_start", {"level_id": level["id"], "kind": kind, "difficulty": level.get("difficulty", ""), "par": level["par"], "level_number": campaign_index + 1})
	if kind == "daily":
		Analytics.track("daily_challenge_started", {"date": str(st.active().get("date", ""))})
	if kind == "campaign" and LFFlags.get_variant("tutorial_flow") == "coach":
		_coach = COACH.get(level["id"], {})
	if level["id"] == "c01" and not st.data["onboarding"]["tutorialStarted"]:
		st.data["onboarding"]["tutorialStarted"] = true
		Analytics.track("tutorial_start", {"flow": str(LFFlags.get_variant("tutorial_flow"))})
	_build()


func _palette() -> Dictionary:
	if kind == "campaign" and campaign_index >= 0:
		return LFWorlds.palette(LFWorlds.index_for(Game.state.campaign, campaign_index))
	return LFWorlds.palette_for_level(level)


func _build() -> void:
	var pal := _palette()
	var bg := ColorRect.new()
	bg.color = pal["bg"]
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	if LFCrew.current()["scifi"]:
		var space := LFSpaceBackdrop.new()
		space.tint = pal["rail"]
		space.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(space)
	var sm: Vector2 = main.safe_margins()
	var root := LFStyle.vbox(16)
	var m := LFStyle.margin(root, 28, 24 + int(sm.x), 28, 28 + int(sm.y))
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)

	# Top bar
	var top := LFStyle.hbox(16)
	var back := LFIconButton.make("back", "", "SecondaryButton", 88)
	back.pressed.connect(func(): main.back())
	top.add_child(back)
	var tcol := LFStyle.vbox(0)
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.alignment = BoxContainer.ALIGNMENT_CENTER
	title_label = LFStyle.label(level["name"], 34, LFStyle.TEXT, 800)
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tcol.add_child(title_label)
	var sub := LFStyle.label(_subtitle(), 22, LFStyle.DIFFICULTY_COLORS.get(level.get("difficulty", ""), LFStyle.TEXT_MUTED).darkened(0.3), 700)
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tcol.add_child(sub)
	top.add_child(tcol)
	moves_view = _make_moves_view()
	top.add_child(moves_view)
	root.add_child(top)

	banner = _make_banner()
	root.add_child(banner)

	board = LFBoardView.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.reduced_motion = main.reduced_motion()
	board.colorblind = bool(Game.settings().get("colorblind", false))
	board.palette = pal
	LFCrew.configure_board(board, Game.state.data, pal)
	root.add_child(board)
	board.set_level(level, Game.state.active()["rotations"])
	board.rotate_requested.connect(_on_rotate)
	board.locked_tapped.connect(_on_locked)
	board.source_tapped.connect(_on_source)
	board.playback_finished.connect(_on_finished)
	board.package_delivered.connect(func(_c): Sfx.play("deliver", 1.0 + randf() * 0.1); Sfx.haptic_pattern("medium"))

	# Edit controls
	edit_bar = LFStyle.hbox(12)
	undo_btn = LFIconButton.make("undo", "Undo")
	undo_btn.pressed.connect(_undo)
	var reset := LFIconButton.make("reset", "Reset")
	reset.pressed.connect(_reset)
	hint_btn = LFIconButton.make("hint", "Hint")
	hint_btn.pressed.connect(_hint)
	if kind == "daily" or kind == "challenge":
		hint_btn.disabled = true  # ranked / head-to-head puzzles are hint-free
	run_btn = LFStyle.button("Run", "", 104)
	run_btn.add_theme_font_size_override("font_size", 38)
	run_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_btn.pressed.connect(_run)
	# Accessible alternative to long-press (audit G1/U2): a toggle that makes taps turn ↺.
	reverse_btn = LFIconButton.make("rotate_ccw", "Turn ↺", "SecondaryButton", 96)
	reverse_btn.toggle_mode = true
	reverse_btn.tooltip_text = "Taps turn belts counter-clockwise while on"
	reverse_btn.toggled.connect(_on_reverse_toggled)
	reverse_btn.visible = reverse_available(kind, campaign_index, Game.state.campaign)
	for c in [undo_btn, reset, hint_btn, reverse_btn, run_btn]:
		edit_bar.add_child(c)
	root.add_child(edit_bar)

	# Simulation controls
	run_bar = LFStyle.hbox(12)
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

	_reverse_tile = reverse_teach_tile(level, kind, Game.state.data, Game.state.campaign)
	_update_coach()
	if _coach.is_empty() and _reverse_tile < 0:
		_crew_intro()
	_refresh()
	if board.crew_on:
		_expose.call_deferred()


func _expose() -> void:
	if is_instance_valid(board):
		LFCrew.expose("board", {"detail": ["classic", "compact", "full"][board.crew_detail()], "level_id": level["id"]})


## Optional, non-blocking introductions in the banner: Dr. Rix presents a new mechanic, Captain
## Naps a new world. The level's tip stays underneath, so nothing is lost.
func _crew_intro() -> void:
	if kind != "campaign" or not board.crew_on:
		return
	var mech := LFCrew.mechanic_intro(Game.state.campaign, campaign_index)
	var line := {}
	if mech != "":
		line = LFCrew.say("NEW_MECHANIC", {"mechanic": mech})
	else:
		var world := LFCrew.world_intro(Game.state.campaign, campaign_index)
		if world != "":
			line = LFCrew.say("NEW_WORLD", {"world": world})
	if line.is_empty():
		return
	_banner_speaker = str(line["character"])
	var tip := str(level.get("tip", ""))
	_set_banner("crew", "“%s”" % line["text"], tip if tip != "" else "Deliver every package to its matching dock.")


func _subtitle() -> String:
	match kind:
		"campaign":
			var w: Dictionary = _palette()
			return "%s · Level %d" % [w["name"], campaign_index + 1]
		"endless":
			return "Endless · %s" % str(level.get("difficulty", "")).capitalize()
		"daily":
			return "Daily challenge · ranked"
		"offline_daily":
			return "Offline practice · not ranked"
		"challenge":
			return "Challenge from %s · beat %d" % [str(challenge.get("creatorName", "a friend")), int(challenge.get("creatorRotations", 0))]
	return ""


# ----------------------------------------------------------------- header widgets

## Moves counter with a live star preview (3 stars at or under par, 2 up to par + 3).
func _make_moves_view() -> Control:
	var card := LFStyle.card(LFStyle.SURFACE, 16)
	card.custom_minimum_size = Vector2(150, 88)
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(c)
	c.draw.connect(func():
		var n := Game.state.moves_count() if Game.state.active() != null else int(_win_res.get("moves", 0))
		var par: int = level["par"]
		var f := LFStyle.font(800)
		var w := c.size.x
		var txt := "%d / %d" % [n, par]
		var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30)
		c.draw_string(f, Vector2((w - sz.x) / 2, 28), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, LFStyle.TEXT)
		var stars := LFGameState.stars_for(n, par)
		for k in 3:
			var col := LFStyle.ACCENT if k < stars else LFStyle.SURFACE_2
			LFIcons.draw_icon(c, "star", Rect2(Vector2(w / 2 - 25 + (k - 1) * 34, 32), Vector2(50, 50)), col))
	return card


func _make_banner() -> PanelContainer:
	var p := LFStyle.card(LFStyle.SURFACE, 18)
	p.custom_minimum_size = Vector2(0, 92)
	var h := LFStyle.hbox(14)
	p.add_child(h)
	banner_icon = Control.new()
	banner_icon.custom_minimum_size = Vector2(52, 52)
	banner_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	banner_icon.draw.connect(_draw_banner_icon)
	h.add_child(banner_icon)
	var v := LFStyle.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_title = LFStyle.label("", 24, LFStyle.TEXT, 800)
	banner_text = LFStyle.label("", 22, LFStyle.TEXT_MUTED, 700)
	banner_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(banner_title)
	v.add_child(banner_text)
	h.add_child(v)
	return p


func _draw_banner_icon() -> void:
	var r := Rect2(Vector2.ZERO, banner_icon.size)
	match _banner_kind:
		"crew":
			banner_icon.draw_circle(r.get_center(), 26, LFStyle.SECONDARY.lerp(Color.WHITE, 0.4))
			LFCrewPainter.draw_character(banner_icon, LFCrew.get_def(_banner_speaker), r.get_center() + Vector2(0, 2), 50, LFCrewAnim.IDLE, 0.0, 0.0, {"motion": false, "expression": "happy"})
		"fail":
			if _fail_color >= 0 and board != null and board.crew_on:
				# The package that failed, looking suitably confused.
				LFCrewPainter.draw_character(banner_icon, LFCrew.for_color(_fail_color), r.get_center() + Vector2(0, 2), 64, LFCrewAnim.FAILED, 1.0, 0.0, {"motion": false, "expression": "confused"})
			elif _fail_color >= 0:
				var col: Color = LFStyle.PACKAGE[_fail_color]
				banner_icon.draw_style_box(LFStyle.box(col, 12, false), r.grow(-4))
				LFStyle.draw_symbol(banner_icon, LFStyle.SYMBOLS[_fail_color], r.get_center(), 9, Color.WHITE)
			else:
				banner_icon.draw_circle(r.get_center(), 22, LFStyle.ERROR)
		"coach":
			banner_icon.draw_circle(r.get_center(), 24, LFStyle.PRIMARY)
			LFIcons.draw_icon(banner_icon, "hint", r.grow(-6), Color.WHITE)
		"hint":
			banner_icon.draw_circle(r.get_center(), 24, LFStyle.ACCENT)
			LFIcons.draw_icon(banner_icon, "hint", r.grow(-6), LFStyle.TEXT)
		_:
			banner_icon.draw_circle(r.get_center(), 24, LFStyle.SURFACE_2)
			LFIcons.draw_icon(banner_icon, "check" if _banner_kind == "ready" else "play", r.grow(-10), LFStyle.PRIMARY)


func _set_banner(k: String, title: String, text: String) -> void:
	_banner_kind = k
	var bgc := LFStyle.SURFACE
	match k:
		"fail":
			bgc = LFStyle.ERROR.lerp(Color.WHITE, 0.82)
		"coach":
			bgc = LFStyle.SECONDARY.lerp(Color.WHITE, 0.7)
		"hint":
			bgc = LFStyle.ACCENT.lerp(Color.WHITE, 0.75)
		"ready":
			bgc = LFStyle.SUCCESS.lerp(Color.WHITE, 0.78)
		"crew":
			bgc = LFStyle.SECONDARY.lerp(Color.WHITE, 0.78)
	banner.add_theme_stylebox_override("panel", LFStyle.box(bgc, 18, k == ""))
	banner_title.text = title
	banner_title.visible = title != ""
	banner_text.text = text
	banner_text.add_theme_color_override("font_color", LFStyle.TEXT if k != "" else LFStyle.TEXT_MUTED)
	banner_icon.queue_redraw()


## Default banner: the level's tip, otherwise its goal.
func _show_tip() -> void:
	var tip := str(level.get("tip", ""))
	var total := LFSimulation.total_packages(level)
	var goal := "Deliver %d package%s to matching docks · par %d" % [total, "" if total == 1 else "s", level["par"]]
	if kind == "challenge":
		goal = "Solve it in fewer than %d rotations to win the challenge." % int(challenge.get("creatorRotations", 0))
	_set_banner("", "", tip if tip != "" else goal)


# ----------------------------------------------------------------- onboarding

## Tile to teach "hold to turn back" on, or -1. Only on the first level that needs it, only until the
## player has turned a belt counter-clockwise once (or already finished the formal lesson, c09).
static func reverse_teach_tile(lvl: Dictionary, p_kind: String, data: Dictionary, campaign: Array) -> int:
	if p_kind != "campaign" or str(lvl.get("id", "")) != REVERSE_TEACH_LEVEL:
		return -1
	if bool(data.get("onboarding", {}).get("reverseLearned", false)):
		return -1
	for i in campaign.size():
		if str(campaign[i]["id"]) == "c09" and data.get("progress", {}).has("c09"):
			return -1
	for mv in lvl.get("solution", {}).get("moves", []):
		if int(mv[1]) == -1:
			return int(mv[0])
	return -1


## The ↺ toggle is offered from the first level that needs reverse turns, and on every non-campaign
## puzzle; earlier levels keep the bar uncluttered.
static func reverse_available(p_kind: String, index: int, campaign: Array) -> bool:
	if p_kind != "campaign":
		return true
	for i in campaign.size():
		if str(campaign[i]["id"]) == REVERSE_TEACH_LEVEL:
			return index >= i
	return true


func _on_reverse_toggled(on: bool) -> void:
	board.reverse_mode = on
	reverse_btn.icon_color = LFStyle.PRIMARY if on else LFStyle.TEXT
	reverse_btn.queue_redraw()


func _update_coach() -> void:
	board.tutorial_tile = -1
	board.tutorial_hold = false
	if _reverse_tile >= 0:
		if LFSimulation.is_solved(level, Game.state.active()["rotations"]):
			_set_banner("ready", "Path ready!", "Press Run to send the packages.")
			return
		board.tutorial_tile = _reverse_tile
		board.tutorial_hold = true
		_set_banner("coach", REVERSE_COPY["title"], REVERSE_COPY["text"])
		return
	if _coach.is_empty():
		_show_tip()
		return
	var rots: Array = Game.state.active()["rotations"]
	if LFSimulation.is_solved(level, rots):
		_set_banner("ready", "Path ready!", "Press Run to send the packages.")
		_pulse(run_btn)
		return
	var finger: String = _coach["finger"]
	if finger == "all" or (finger == "first" and Game.state.moves_count() == 0):
		var h = LFSolver.hint(level, rots)
		if h != null:
			board.tutorial_tile = h["tile"]
	_set_banner("coach", _coach["title"], _coach["text"])


# ----------------------------------------------------------------- state

func _refresh() -> void:
	moves_view.get_child(0).queue_redraw()
	undo_btn.disabled = Game.state.moves_count() == 0


func on_back() -> bool:
	if board.celebrating:
		board.skip_celebration()
		return true
	if board.playing or not board._frames.is_empty():
		_stop()
		return true
	var a = Game.state.active()
	if a != null and kind != "offline_daily" and kind != "challenge":
		Game.state.enqueue("active_puzzle", {"kind": a["kind"], "levelId": a["levelId"], "rotations": a["rotations"].duplicate(), "history": a["history"].duplicate(true), "updatedAt": a["updatedAt"]})
	Game.save_now()
	return false


func _after_edit() -> void:
	board.clear_failure()
	if _banner_kind == "fail" or _banner_kind == "hint" or _banner_kind == "crew":
		_show_tip()
	if not _coach.is_empty() or _reverse_tile >= 0:
		_update_coach()
	_refresh()
	Game.request_save()


func _on_rotate(i: int, dir: int) -> void:
	if not Game.state.rotate(i, dir):
		return
	board.animate_rotation(i, dir)
	Sfx.play("rotate" if dir == 1 else "ccw", 0.97 + randf() * 0.06)
	Sfx.haptic_pattern("tick")
	_note_direction(i, dir)
	_after_edit()


## Reverse-turn learning: the first counter-clockwise turn ends the lesson for good. Before then,
## three clockwise taps in a row on one belt earn a one-time tip (that's one ↺ turn, not three).
func _note_direction(i: int, dir: int) -> void:
	var ob: Dictionary = Game.state.data["onboarding"]
	if dir == -1:
		if not bool(ob.get("reverseLearned", false)):
			ob["reverseLearned"] = true
		if _reverse_tile >= 0:
			_reverse_tile = -1
			board.tutorial_tile = -1
			board.tutorial_hold = false
			_show_tip()
		return
	if bool(ob.get("reverseLearned", false)) or _reverse_tip_shown or kind != "campaign":
		return
	_cw_streak = [i, _cw_streak[1] + 1] if _cw_streak[0] == i else [i, 1]
	if _cw_streak[1] >= 3:
		_reverse_tip_shown = true
		_set_banner("coach", "Tip: turn it back", "Tap to turn ↻. Hold to turn ↺ — one move instead of three.")


## Tapping a source pokes the character waiting in it.
func _on_source(i: int) -> void:
	if not board.crew_on:
		Sfx.play("locked")
		return
	var cidx := int(level["tiles"][i].get("c", 0))
	Sfx.play("boop", [1.0, 1.25, 0.85, 0.75][cidx])
	Sfx.haptic_pattern("light")
	if not _poked:
		_poked = true
		Analytics.track("character_animation_played", {"character": str(LFCrew.for_color(cidx)["id"]), "animation": "selected", "surface": "board"})


func _on_locked(_i: int) -> void:
	Sfx.play("locked")
	Sfx.haptic_pattern("warn")
	if not _locked_told:
		_locked_told = true
		_set_banner("coach", "Pinned belt", "Tiles with a pin can't be turned — route around them.")


func _undo() -> void:
	var mv = Game.state.undo()
	if mv == null:
		return
	board.animate_rotation(int(mv[0]), -int(mv[1]))
	Sfx.play("ccw" if int(mv[1]) == 1 else "rotate", 0.9)
	_after_edit()


func _reset() -> void:
	if Game.state.moves_count() == 0:
		# Nothing to undo, but Reset should still clear the last failure's marks and reactions.
		_after_edit()
		return
	Game.state.reset()
	board.sync_rotations(Game.state.active()["rotations"])
	_after_edit()


## Banner [title, text] for a hint outcome that has no move to show.
static func hint_copy(outcome_kind: String) -> Array:
	return HINT_COPY.get(outcome_kind, HINT_COPY["exhausted"])


## Three-step hints from a solver-verified solution: area → tile → exact rotation. When there is no
## move to show, the banner says exactly why (solved / search ran out / no route from here).
func _hint() -> void:
	var o := LFSolver.hint_outcome(level, Game.state.active()["rotations"], _hint_budget)
	if o["kind"] != "hint":
		var copy := hint_copy(o["kind"])
		_set_banner("ready" if o["kind"] == "solved" else "hint", copy[0], copy[1])
		if o["kind"] == "exhausted":
			_hint_budget = mini(_hint_budget * 4, 1600000)  # "try again" searches deeper
		return
	var h: Dictionary = o["hint"]
	var step := Game.state.next_hint_step(int(h["tile"]))
	board.show_hint(h["tile"], h["dir"], h["taps"], step)
	Sfx.play("hint")
	match step:
		1:
			_set_banner("hint", "Hint 1 of 3", "Look in the highlighted area — one belt there needs to turn.")
		2:
			_set_banner("hint", "Hint 2 of 3", "This belt is pointing the wrong way.")
		_:
			_set_banner("hint", "Hint 3 of 3", "Turn it %s%s." % ["clockwise" if int(h["dir"]) == 1 else "counter-clockwise (long-press)", "" if int(h["taps"]) == 1 else " ×%d" % int(h["taps"])])
	hint_btn.caption = HINT_CAPTIONS[mini(step, 3)]
	hint_btn.queue_redraw()
	Analytics.track("hint_used", {"level_id": level["id"], "kind": kind, "step": step})
	Game.request_save()


func _run() -> void:
	board.stop_playback()
	board.clear_failure()
	var runs := Game.state.record_run()
	var result := LFSimulation.simulate(level, Game.state.active()["rotations"])
	if _failed_once:
		Analytics.track("level_retry", {"level_id": level["id"], "kind": kind, "attempt": runs})
	board.interactive = false
	board.hint_tile = -1
	board.tutorial_tile = -1
	edit_bar.visible = false
	run_bar.visible = true
	board.paused = false
	pause_btn.icon_name = "pause"
	pause_btn.caption = "Pause"
	pause_btn.queue_redraw()
	Sfx.play("run")
	board.start_playback(result, STEP_FAST if fast else STEP_NORMAL)
	Game.request_save()


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
		var res := Game.complete_active()
		if res.is_empty():
			_back_to_edit()
			return
		_win_res = res
		var perfect: bool = res["moves"] <= res["par"]
		Sfx.play("perfect" if perfect else "win")
		Sfx.haptic_pattern("success")
		Analytics.track("level_complete", {"level_id": level["id"], "kind": kind, "moves": res["moves"], "par": res["par"], "stars": res["stars"], "hints": res["hints"], "attempts": res["runs"], "level_number": campaign_index + 1})
		if kind == "daily":
			Analytics.track("daily_challenge_completed", {"moves": res["moves"], "attempts": res["runs"]})
		if level["id"] == "c05" and not Game.state.data["onboarding"]["tutorialDone"]:
			Game.state.data["onboarding"]["tutorialDone"] = true
			Analytics.track("tutorial_complete", {"flow": str(LFFlags.get_variant("tutorial_flow"))})
		run_bar.visible = false
		_set_banner("ready", "Perfect!" if perfect else "Delivered!", "Tap the board to skip.")
		_moments = LFCrewMoments.detect(result, level, int(res["moves"]))
		board.crew_ctx["perfect"] = perfect
		if board.crew_on:
			Analytics.track("character_animation_played", {"character": "crew", "animation": "celebrating", "surface": "board", "moment": LFCrewMoments.headline(_moments)})
		board.celebration_finished.connect(func(): _show_win(res), CONNECT_ONE_SHOT)
		board.celebrate(float(LFFlags.get_variant("celebration_ms")) / 1000.0)
	else:
		_failed_once = true
		Sfx.play("fail")
		Sfx.haptic_pattern("warn")
		Analytics.track("level_fail", {"level_id": level["id"], "kind": kind, "reason": str(result["reason"])})
		var info := board.failure_info()
		_fail_color = int(info.get("color", -1))
		var reason := str(result["reason"])
		var who := "A package"
		if _fail_color >= 0:
			who = "The %s package" % LFStyle.PACKAGE_NAMES[_fail_color]
		var tip: String = FAIL_TIP.get(reason, "Adjust the route and try again.")
		if board.crew_on:
			if _fail_color >= 0:
				who = LFCrew.for_color(_fail_color)["name"]
			# The tip comes first; a repeat of the same failure may get a character quip instead.
			if reason == _last_fail_reason:
				var line := LFCrew.say("FAILED_ATTEMPT", {"character": LFCrew.body_of(LFCrew.for_color(maxi(_fail_color, 0)))})
				if not line.is_empty():
					tip = "%s: “%s” %s" % [line["speaker"], line["text"], tip]
		_last_fail_reason = reason
		_set_banner("fail", "%s %s" % [who, FAIL_TEXT.get(reason, "didn't make it.")], tip)
		var keep_cell := board._fail_cell
		var keep_path := board._fail_path
		board.stop_playback()
		board._fail_cell = keep_cell
		board._fail_path = keep_path
		_back_to_edit()


# ----------------------------------------------------------------- results

func _show_win(res: Dictionary, first_show := true) -> void:
	if not is_inside_tree():
		return
	var card := LFStyle.card()
	var v := LFStyle.vbox(16)
	card.add_child(LFStyle.margin(v, 20, 24, 20, 20))
	var perfect: bool = res["moves"] <= res["par"]
	v.add_child(LFStyle.label("Perfect!" if perfect else "Delivered!", 56, LFStyle.TEXT, 800, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_stars_view(int(res["stars"]), first_show))
	v.add_child(LFStyle.label("%d rotations · par %d" % [res["moves"], res["par"]], 30, LFStyle.TEXT, 700, HORIZONTAL_ALIGNMENT_CENTER))
	var note := ""
	if perfect:
		note = "The fewest rotations possible."
	elif res["newBest"]:
		note = "New personal best!"
	elif not res["first"]:
		note = "Your best: %d rotations" % res["best"]
	else:
		note = "Par is %d — can you find it?" % res["par"]
	v.add_child(LFStyle.label(note, 24, LFStyle.TEXT_MUTED, 400, HORIZONTAL_ALIGNMENT_CENTER))
	var naps := _naps_reaction(res, first_show)
	if naps != null:
		v.add_child(naps)
	if kind == "challenge" and first_show:
		var cmp := LFStyle.label("Checking result…", 26, LFStyle.PRIMARY, 800, HORIZONTAL_ALIGNMENT_CENTER)
		cmp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(cmp)
		_submit_challenge(res, cmp)

	# Primary action — always the biggest thing on the card.
	var primary_row := LFStyle.hbox(14)
	var nxt := LFStyle.button(_next_label(), "", 112)
	nxt.add_theme_font_size_override("font_size", 36)
	nxt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nxt.pressed.connect(func(): _next(res))
	primary_row.add_child(nxt)
	var can_challenge := kind in ["campaign", "endless", "daily", "offline_daily"]
	if can_challenge and LFFlags.get_variant("challenge_button") == "beside_next":
		var ch := LFIconButton.make("share", "Challenge", "AccentButton", 112)
		ch.pressed.connect(func(): _challenge(res))
		primary_row.add_child(ch)
		can_challenge = false
	v.add_child(primary_row)

	var row := LFStyle.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var replay := LFIconButton.make("play", "Replay", "SecondaryButton")
	replay.pressed.connect(func(): main.close_overlay(); main.goto("replay", {"level": res["level"], "moves": res["history"], "title": "Your solution"}))
	row.add_child(replay)
	if can_challenge:
		var ch2 := LFIconButton.make("share", "Challenge", "SecondaryButton")
		ch2.pressed.connect(func(): _challenge(res))
		row.add_child(ch2)
	if kind == "daily" or kind == "offline_daily" or kind == "challenge":
		var share := LFIconButton.make("trophy", "Share", "SecondaryButton")
		share.pressed.connect(func(): _share(res))
		row.add_child(share)
	var home := LFIconButton.make("grid", "Home", "SecondaryButton")
	home.pressed.connect(func(): main.close_overlay(); main.home())
	row.add_child(home)
	v.add_child(row)
	main.overlay(card, false, func(): main.back())


## Captain Naps reacts to what actually happened (first win, perfect, all-together arrival…). One
## short line on the card: never a separate popup, never blocks "Next".
func _naps_reaction(res: Dictionary, first_show: bool) -> Control:
	if not board.crew_on:
		return null
	if first_show:
		var ev := "SUCCESS"
		var head := LFCrewMoments.headline(_moments)
		if kind == "campaign" and res["first"] and int(Game.state.data["stats"]["campaign"]) == 1:
			ev = "FIRST_SUCCESS"
		elif head != "":
			ev = LFCrewMoments.EVENT[head]
		_win_line = LFCrew.say(ev)
		if _win_line.is_empty() and ev != "SUCCESS":
			_win_line = LFCrew.say("SUCCESS")
	if _win_line.is_empty():
		return null
	var row := LFStyle.hbox(12)
	var p := LFCrewPortrait.make("naps", 104, board.crew_motion)
	p.expression = str(_win_line.get("anim", "happy"))
	p.cosmetic = LFCrew.art_for(Game.state.data, "naps")
	row.add_child(p)
	var bubble := LFStyle.card(LFStyle.SECONDARY.lerp(Color.WHITE, 0.8), 18)
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := LFStyle.label("“%s”" % _win_line["text"], 23, LFStyle.TEXT, 700)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.add_child(l)
	row.add_child(bubble)
	return row


func _stars_view(n: int, animate := true) -> Control:
	var stars := Control.new()
	stars.custom_minimum_size = Vector2(0, 110)
	var t0 := Time.get_ticks_msec()
	var rm: bool = main.reduced_motion() or not animate
	stars.draw.connect(func():
		var w := stars.size.x
		for k in 3:
			var c := Vector2(w / 2 + (k - 1) * 110, 55)
			var age := (Time.get_ticks_msec() - t0) / 1000.0 - 0.1 - k * 0.16
			var sc := 1.0 if rm else LFBoardView._ease_out_back(clampf(age * 4.0, 0.0, 1.0))
			var col := LFStyle.ACCENT if k < n else LFStyle.SURFACE_2
			if sc > 0.0:
				LFIcons.draw_icon(stars, "star", Rect2(c - Vector2(56, 56) * sc, Vector2(112, 112) * sc), col))
	# Bound to the stars node, so closing the card early simply stops the animation.
	var tw := stars.create_tween()
	tw.tween_method(func(_x): stars.queue_redraw(), 0.0, 1.0, 1.0)
	if not rm:
		for k in n:
			get_tree().create_timer(0.12 + k * 0.16).timeout.connect(func(): Sfx.play("star", 1.0 + k * 0.12))
	return stars


func _next_label() -> String:
	match kind:
		"campaign":
			return "Next level" if campaign_index + 1 < Game.state.campaign.size() else "Done"
		"endless":
			return "Next puzzle"
		"daily", "offline_daily":
			return "Share result"
	return "Continue"


func _next(res: Dictionary) -> void:
	match kind:
		"campaign":
			main.close_overlay()
			if campaign_index + 1 < Game.state.campaign.size():
				main.replace("play", {"kind": "campaign", "index": campaign_index + 1})
			else:
				main.home()
		"endless":
			main.close_overlay()
			main.replace("play", {"kind": "endless"})
		"daily", "offline_daily":
			_share(res)
		_:
			main.close_overlay()
			main.home()


# ----------------------------------------------------------------- sharing & challenges

func _share(res: Dictionary) -> void:
	var date := _date if _date != "" else LFGameState.utc_date()
	var card_data := {
		"kind": kind, "date": date, "difficulty": str(level.get("difficulty", "")), "rotations": int(res["moves"]),
		"par": int(res["par"]), "stars": int(res["stars"]), "attempts": int(res.get("runs", 1)), "levelName": str(level["name"]),
		"code": str(challenge.get("code", "")),
	}
	if board.crew_on:
		var featured := _featured_color()
		var def := LFCrew.for_color(featured)
		card_data["crew"] = true
		card_data["featured"] = featured
		card_data["starry"] = bool(board.crew_ctx.get("starry", false))
		card_data["reaction"] = ("%s: “%s”" % [_win_line["speaker"], _win_line["text"]]) if not _win_line.is_empty() else ("%s: “%s”" % [def["name"], def.get("line", "")])
	LFShareCard.present(main, card_data, func(): _show_win(res, false))
	Analytics.track("share_clicked", {"kind": kind, "surface": "result_card"})


## Featured character for the share card: the colour that made the last delivery in this run
## (a real gameplay fact), else the first source colour.
func _featured_color() -> int:
	var frames: Array = board._frames
	for fi in range(frames.size() - 1, -1, -1):
		for p in frames[fi]["packages"]:
			if p["state"] == "delivered":
				return int(p["color"])
	for t in level["tiles"]:
		if t["t"] == "source":
			return int(t.get("c", 0))
	return 0


func _challenge(res: Dictionary) -> void:
	Analytics.track("challenge_create_clicked", {"kind": kind, "level_id": level["id"]})
	if not Net.enabled():
		main.toast("Challenges need an online connection.", LFStyle.ERROR)
		return
	main.toast("Creating challenge…", LFStyle.PRIMARY, 1.2)
	var out = await Net.create_challenge(kind, res["level"], res["history"])
	if not is_inside_tree():
		return
	if out == null:
		main.toast("Couldn't create the challenge — check your connection.", LFStyle.ERROR, 3.0)
		return
	Game.state.data["challenges"]["created"][str(out["code"])] = {"levelId": level["id"], "rotations": int(res["moves"]), "createdAt": LFGameState.now_ms()}
	Game.request_save()
	Analytics.track("challenge_created", {"kind": kind, "level_id": level["id"]})
	LFShareCard.present_challenge(main, out, int(res["moves"]), func(): _show_win(res, false))


func _submit_challenge(res: Dictionary, label: Label) -> void:
	var out = await Net.submit_challenge_attempt(str(challenge.get("code", "")), res["history"])
	if not is_instance_valid(label):
		return
	var creator := int(challenge.get("creatorRotations", 0))
	if out == null:
		var mine: int = res["moves"]
		label.text = "You: %d · %s: %d (unverified — offline)" % [mine, str(challenge.get("creatorName", "Friend")), creator]
		return
	var outcome := str(out.get("outcome", ""))
	var text := {"win": "You beat %s! %d vs %d", "tie": "Tied with %s at %d vs %d", "lose": "%s still leads: you %d vs %d"}
	label.text = text.get(outcome, "%s · %d vs %d") % [str(challenge.get("creatorName", "your friend")), int(out.get("rotations", res["moves"])), creator]
	Game.state.data["challenges"]["played"][str(challenge.get("code", ""))] = {"rotations": int(out.get("rotations", res["moves"])), "outcome": outcome}
	Game.request_save()
	Analytics.track("challenge_completed", {"outcome": outcome})


func _pulse(c: Control) -> void:
	if main.reduced_motion() or not is_instance_valid(c):
		return
	c.pivot_offset = c.size / 2
	var tw := create_tween().set_loops(3)
	tw.tween_property(c, "scale", Vector2(1.06, 1.06), 0.25)
	tw.tween_property(c, "scale", Vector2.ONE, 0.25)
