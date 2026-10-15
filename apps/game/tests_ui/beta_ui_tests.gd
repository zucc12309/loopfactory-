extends SceneTree
## Beta-readiness scene tests (real screens and autoloads):
##   xvfb-run godot --path apps/game --rendering-driver opengl3 -s res://tests_ui/beta_ui_tests.gd
## * Reset after a failed run (B-BUILD-1): zero moves, one move, undo-to-zero, repeated, reduced motion.
## * Reverse rotation taught on c08 before it is needed; the ↺ toggle as a long-press alternative.
## * Hint copy for every solver outcome.
## * Minimal and Crew presentations: same puzzle, scoring, save schema and controls.
## Uses its own save file.

var failures := 0
var checks := 0
var Game: Node
var Tiles: GDScript
var Sim: GDScript
var Play: GDScript


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL ", msg)
	else:
		print("ok   ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _fresh_state() -> void:
	Game.state.data = load("res://scripts/core/game_state.gd").defaults()
	Game.state.data["settings"]["analyticsAsked"] = true
	Game.state.data["settings"]["sfx"] = false
	Game.state.data["settings"]["music"] = false


func _make_main(size: Vector2i) -> Array:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	root.add_child(vp)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	vp.add_child(main)
	await _frames(2)
	return [vp, main]


func _play(main: Control, id: String) -> Variant:
	Game.state.data["active"] = null
	main.goto("play", {"kind": "campaign", "index": Game.state.campaign_index[id]})
	await _wait(0.35)
	return main.current


func _run_and_wait(play) -> Dictionary:
	var out := []
	play.board.playback_finished.connect(func(r): out.append(r), CONNECT_ONE_SHOT)
	play.fast = true
	play._run()
	var n := 0
	while out.is_empty() and n < 3000:
		await process_frame
		n += 1
	await _frames(2)
	return out[0] if not out.is_empty() else {}


## Real pointer input on a tile (press, optional hold, release).
func _tap(board, i: int, hold := 0.0) -> void:
	var pos: Vector2 = board.cell_center(i)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	board._gui_input(down)
	if hold > 0.0:
		await _wait(hold)
	else:
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	board._gui_input(up)
	await process_frame


func _first_rotatable(level: Dictionary) -> int:
	for i in level["tiles"].size():
		if Tiles.is_rotatable(level["tiles"][i]):
			return i
	return -1


func _settled_ok(play) -> bool:
	var settled: Array = play.board.settled_rotations()
	var model: Array = Game.state.active()["rotations"]
	for i in model.size():
		if Tiles.is_rotatable(play.level["tiles"][i]) and (int(settled[i]) & 3) != (int(model[i]) & 3):
			return false
	return true


func _clean_after_reset(play, tag: String, expect_moves: int, start: Array) -> void:
	check(play._banner_kind != "fail", tag + ": failure banner cleared (kind '%s')" % play._banner_kind)
	check(play.board._fail_cell < 0, tag + ": failure highlight cleared")
	check(Game.state.moves_count() == expect_moves, tag + ": move count %d (got %d)" % [expect_moves, Game.state.moves_count()])
	check(Game.state.active()["rotations"] == start, tag + ": rotations back at the level start")
	check(_settled_ok(play), tag + ": drawn belts match the model")
	check(play.undo_btn.disabled == (expect_moves == 0), tag + ": undo button state")


func _run() -> void:
	Game = root.get_node("Game")
	Tiles = load("res://scripts/engine/tiles.gd")
	Sim = load("res://scripts/engine/simulation.gd")
	Play = load("res://scripts/ui/screens/play.gd")
	Game.store = load("res://scripts/core/save_store.gd").new("user://beta-ui-test-save.json")
	_fresh_state()
	await _reset_tests(false)
	await _reset_tests(true)
	await _reverse_tests()
	await _hint_tests()
	await _presentation_tests()
	await _consent_tests()
	await _share_tests()
	await _a11y_tests()
	print("\nBeta UI tests: %d checks, %d failed" % [checks, failures])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://beta-ui-test-save.json"))
	quit(1 if failures > 0 else 0)


# ------------------------------------------------------------------------------------ Reset

func _reset_tests(reduced: bool) -> void:
	_fresh_state()
	Game.state.data["settings"]["reducedMotion"] = reduced
	var made: Array = await _make_main(Vector2i(720, 1280))
	var main: Control = made[1]
	var rm := " (reduced motion)" if reduced else ""
	var play = await _play(main, "c06")
	var start: Array = Game.state.active()["rotations"].duplicate()
	var progress_before: Dictionary = Game.state.data["progress"].duplicate(true)

	# 1. Failed run with zero rotations, then Reset.
	var r := await _run_and_wait(play)
	check(not r.get("success", true) and play._banner_kind == "fail" and play.board._fail_cell >= 0, "zero-move run fails with banner + highlight" + rm)
	play._reset()
	_clean_after_reset(play, "reset after zero-move failure" + rm, 0, start)

	# 2. Failed run after one rotation, then Reset.
	var t := _first_rotatable(play.level)
	play._on_rotate(t, 1)
	r = await _run_and_wait(play)
	check(not r.get("success", true), "one-move run fails" + rm)
	play._reset()
	_clean_after_reset(play, "reset after one-move failure" + rm, 0, start)

	# 3. Undo back to zero after a failure, then Reset.
	play._on_rotate(t, 1)
	r = await _run_and_wait(play)
	play._undo()
	check(play.board._fail_cell < 0 and play._banner_kind != "fail", "undo clears the failure" + rm)
	play._reset()
	_clean_after_reset(play, "undo to zero then reset" + rm, 0, start)

	# 4. Repeated Reset (with and without a failure in between).
	r = await _run_and_wait(play)
	for k in 4:
		play._reset()
	_clean_after_reset(play, "repeated reset" + rm, 0, start)

	# No scoring or save corruption: nothing was completed, nothing queued as a completion.
	check(Game.state.data["progress"] == progress_before, "no progress recorded by failed runs/resets" + rm)
	check(not Game.state.data["syncQueue"].any(func(o): return o["type"] == "level_complete"), "no completion queued" + rm)
	# A real solve after all that still scores normally.
	for mv in play.level["solution"]["moves"]:
		play._on_rotate(int(mv[0]), int(mv[1]))
	r = await _run_and_wait(play)
	check(r.get("success", false), "solve after resets succeeds" + rm)
	await _wait(0.3)
	play.board.skip_celebration()
	await _wait(1.6)
	var p: Dictionary = Game.state.data["progress"].get("c06", {})
	check(int(p.get("best", -1)) == int(play.level["par"]) and int(p.get("stars", 0)) == 3, "optimal solve scores 3 stars at par" + rm)
	main.close_overlay()
	made[0].queue_free()
	await _frames(2)


# ----------------------------------------------------------------------- Reverse rotation

func _reverse_tests() -> void:
	_fresh_state()
	var made: Array = await _make_main(Vector2i(720, 1280))
	var main: Control = made[1]
	var lvl: Dictionary = Game.state.campaign[Game.state.campaign_index["c08"]]
	var needs_ccw: bool = lvl["solution"]["moves"].any(func(m): return int(m[1]) == -1)
	check(needs_ccw, "c08's par solution uses a counter-clockwise turn (why it is taught here)")
	check(Game.state.campaign_index["c08"] < Game.state.campaign_index["c09"], "c08 comes before the formal lesson (c09)")

	# Earlier levels: no toggle (keep the bar simple), no cue.
	var early = await _play(main, "c06")
	check(not early.reverse_btn.visible, "no ↺ toggle before c08")
	check(early._reverse_tile < 0 and not early.board.tutorial_hold, "no reverse cue before c08")
	# Contextual tip: three clockwise taps on one belt.
	var t := _first_rotatable(early.level)
	for k in 3:
		early._on_rotate(t, 1)
	check(early._banner_kind == "coach" and early.banner_text.text.contains("Hold to turn ↺"), "three ↻ taps on one belt earn the hold tip")
	early._on_rotate(t, 1)
	check(early._reverse_tip_shown, "tip shown once")

	# c08: cue on the tile that needs ↺, short copy, in every presentation.
	for variant in ["hybrid", "minimal"]:
		_fresh_state()
		Game.state.data["remoteConfig"] = {"experiments": {"presentation": {"force": variant}}}
		var play = await _play(main, "c08")
		var want := -1
		for mv in lvl["solution"]["moves"]:
			if int(mv[1]) == -1:
				want = int(mv[0])
				break
		check(play._reverse_tile == want and play.board.tutorial_tile == want and play.board.tutorial_hold, "%s: c08 shows the hold cue on tile %d" % [variant, want])
		check(play.banner_text.text == "Tap to turn ↻. Hold to turn ↺.", "%s: c08 copy" % variant)
		check(play.reverse_btn.visible, "%s: ↺ toggle offered from c08" % variant)
		# Turning ↻ doesn't end the lesson; one ↺ does, permanently.
		var other := -1
		for i in play.level["tiles"].size():
			if Tiles.is_rotatable(play.level["tiles"][i]) and i != want:
				other = i
				break
		play._on_rotate(other, 1)
		check(play.board.tutorial_hold, "%s: clockwise turns keep the cue" % variant)
		play._on_rotate(want, -1)
		check(play._reverse_tile < 0 and not play.board.tutorial_hold and play.board.tutorial_tile < 0, "%s: a ↺ turn ends the lesson" % variant)
		check(bool(Game.state.data["onboarding"]["reverseLearned"]), "%s: learned flag saved" % variant)
		var again = await _play(main, "c08")
		check(again._reverse_tile < 0, "%s: no repeat once learned" % variant)
	Game.state.data["remoteConfig"] = {}

	# The toggle: taps turn ↺ while on; holds turn ↻; scoring counts one move per turn.
	_fresh_state()
	var play2 = await _play(main, "c08")
	play2.reverse_btn.button_pressed = true
	check(play2.board.reverse_mode, "toggle switches the board to reverse taps")
	var tt := _first_rotatable(play2.level)
	var before := int(Game.state.active()["rotations"][tt])
	await _tap(play2.board, tt)
	check(int(Game.state.active()["rotations"][tt]) == (before + 3) % 4, "a tap with the toggle on turns counter-clockwise")
	check(Game.state.moves_count() == 1, "one move counted")
	check(bool(Game.state.data["onboarding"]["reverseLearned"]), "using the toggle also counts as learned")
	play2.reverse_btn.button_pressed = false
	check(not play2.board.reverse_mode, "toggle off restores normal taps")
	var b2 := int(Game.state.active()["rotations"][tt])
	await _tap(play2.board, tt)
	check(int(Game.state.active()["rotations"][tt]) == (b2 + 1) % 4, "a tap with the toggle off turns clockwise")
	var b3 := int(Game.state.active()["rotations"][tt])
	await _tap(play2.board, tt, 0.6)
	check(int(Game.state.active()["rotations"][tt]) == (b3 + 3) % 4, "a long press still turns counter-clockwise")

	# Reduced motion: the cue is static (same drawing at two different times).
	_fresh_state()
	Game.state.data["settings"]["reducedMotion"] = true
	var play3 = await _play(main, "c08")
	check(play3.board.reduced_motion and play3.board.tutorial_hold, "cue still shown with reduced motion")
	# Persistence: an old save (no reverseLearned key) loads with the lesson pending.
	var old: Dictionary = load("res://scripts/core/game_state.gd").defaults()
	old["onboarding"].erase("reverseLearned")
	Game.state.load_from(old)
	check(Game.state.data["onboarding"].has("reverseLearned") and not Game.state.data["onboarding"]["reverseLearned"], "old saves gain the flag (lesson pending)")
	# Players who already finished c09 aren't taught again.
	var d: Dictionary = load("res://scripts/core/game_state.gd").defaults()
	d["progress"]["c09"] = {"completed": true, "best": 3, "par": 3, "stars": 3, "completedAt": 1, "kind": "campaign"}
	check(Play.reverse_teach_tile(lvl, "campaign", d, Game.state.campaign) == -1, "skipped for players past c09")
	made[0].queue_free()
	await _frames(2)


# ------------------------------------------------------------------------------------ Hints

func _hint_tests() -> void:
	_fresh_state()
	var made: Array = await _make_main(Vector2i(720, 1280))
	var main: Control = made[1]
	check(Play.hint_copy("solved")[1] == "Your belts are ready. Hit Run!", "solved copy")
	check(Play.hint_copy("exhausted")[1] == "No hint found yet. Try again or reset.", "exhausted copy")
	check(not Play.hint_copy("unsolvable")[1].contains("you"), "unsolvable copy is non-accusatory")
	var play = await _play(main, "c06")
	# Real hint.
	play._hint()
	check(play._banner_kind == "hint" and play.banner_title.text.begins_with("Hint 1"), "a hint shows a verified next move")
	check(play.board.hint_tile >= 0, "hint highlights a belt")
	# Already solved.
	for mv in play.level["solution"]["moves"]:
		play._on_rotate(int(mv[0]), int(mv[1]))
	play._hint()
	check(play.banner_text.text == "Your belts are ready. Hit Run!", "solved board: ready copy (not a fake hint)")
	# Search exhausted: tiny budget.
	play._reset()
	play._hint_budget = 1
	play._hint()
	check(play.banner_text.text == "No hint found yet. Try again or reset.", "exhausted search: honest copy")
	check(play._hint_budget > 1, "retry searches deeper")
	made[0].queue_free()
	await _frames(2)


# ----------------------------------------------------------------------- Presentations

func _presentation_tests() -> void:
	var results := {}
	for variant in ["hybrid", "minimal", "full"]:
		_fresh_state()
		Game.state.data["remoteConfig"] = {"experiments": {"presentation": {"force": variant}}}
		var made: Array = await _make_main(Vector2i(720, 1280))
		var main: Control = made[1]
		var play = await _play(main, "c20")
		var controls := [play.undo_btn.visible, play.hint_btn.visible, play.run_btn.visible, play.reverse_btn.visible]
		var sym := true
		for i in play.level["tiles"].size():
			if play.level["tiles"][i]["t"] == "dest" and play.board.colorblind != bool(Game.settings().get("colorblind", false)):
				sym = false
		for mv in play.level["solution"]["moves"]:
			play._on_rotate(int(mv[0]), int(mv[1]))
		var r := await _run_and_wait(play)
		await _wait(0.3)
		play.board.skip_celebration()
		await _wait(1.6)
		var p: Dictionary = Game.state.data["progress"].get("c20", {})
		var keys: Array = Game.state.data.keys()
		keys.sort()
		var op_types: Array = Game.state.data["syncQueue"].map(func(o): return o["type"])
		results[variant] = {
			"level": play.level["tiles"].hash(), "par": play.level["par"], "success": r.get("success"), "ticks": r.get("ticks"),
			"best": p.get("best"), "stars": p.get("stars"), "keys": keys, "ops": op_types, "controls": controls, "symbols": sym,
		}
		main.close_overlay()
		made[0].queue_free()
		await _frames(2)
	Game.state.data["remoteConfig"] = {}
	for v in ["minimal", "full"]:
		for k in results["hybrid"]:
			check(results[v][k] == results["hybrid"][k], "%s vs hybrid: same %s (%s vs %s)" % [v, k, results[v][k], results["hybrid"][k]])


# ------------------------------------------------------------------------- Consent timing

func _consent_card(main: Control) -> Node:
	return main.find_child("ConsentCard", true, false)


func _consent_tests() -> void:
	# Fresh install: nothing on Home, nothing before or during the first puzzle and its celebration.
	Game.state.data = load("res://scripts/core/game_state.gd").defaults()
	Game.state.data["settings"]["sfx"] = false
	Game.state.data["settings"]["music"] = false
	var made: Array = await _make_main(Vector2i(720, 1280))
	var main: Control = made[1]
	main.home()
	await _wait(1.2)
	check(_consent_card(main) == null, "fresh install: no consent prompt on Home")
	var play = await _play(main, "c01")
	await _wait(1.0)
	check(_consent_card(main) == null, "no consent prompt over the first puzzle")
	for mv in play.level["solution"]["moves"]:
		play._on_rotate(int(mv[0]), int(mv[1]))
	var r := await _run_and_wait(play)
	check(r.get("success", false), "first delivery")
	check(_consent_card(main) == null, "no consent prompt over the celebration")
	await _wait(1.8)
	check(_consent_card(main) == null, "no consent prompt stacked on the win card")
	check(not bool(Game.settings()["analytics"]), "still opted out (never silently opted in)")
	# Transition: Next level -> prompt appears over the new board.
	play._next(play._win_res)
	await _wait(1.0)
	var card := _consent_card(main)
	check(card != null, "consent asked at the transition after the first delivery")
	if card != null:
		var no: Button = card.find_child("ConsentNo", true, false)
		var yes: Button = card.find_child("ConsentYes", true, false)
		check(no != null and yes != null and no.size.y >= 88 and yes.size.y >= 88, "both answers are large one-tap buttons")
		yes.pressed.emit()
	await _frames(2)
	check(bool(Game.settings()["analytics"]) and bool(Game.settings()["analyticsAsked"]), "accept recorded")
	check(_consent_card(main) == null, "prompt closed")
	main.home()
	await _wait(1.0)
	check(_consent_card(main) == null, "asked only once")
	# Decline path, and a player who reaches Home after a win without seeing the transition.
	Game.state.data["settings"]["analyticsAsked"] = false
	Game.state.data["settings"]["analytics"] = false
	main.goto("settings")
	await _wait(0.4)
	main.home()
	await _wait(1.2)
	card = _consent_card(main)
	check(card != null, "Home asks once progress exists")
	if card != null:
		(card.find_child("ConsentNo", true, false) as Button).pressed.emit()
	await _frames(2)
	check(not bool(Game.settings()["analytics"]) and bool(Game.settings()["analyticsAsked"]), "decline recorded")
	# Settings keeps an accessible entry to change it later.
	main.goto("settings")
	await _wait(0.4)
	var found := false
	for cb in main.current.find_children("*", "CheckButton", true, false):
		if (cb as CheckButton).text == "Share anonymous gameplay stats":
			found = true
	check(found, "Settings keeps the analytics toggle")
	made[0].queue_free()
	await _frames(2)


# ------------------------------------------------------------------- Sharing & challenge links

func _events() -> Array:
	return root.get_node("Analytics").queued().map(func(e): return e["event"])


func _share_tests() -> void:
	var Share: GDScript = load("res://scripts/core/share.gd")
	var Card: GDScript = load("res://scripts/ui/share_card.gd")
	var An: Node = root.get_node("Analytics")
	# Link parsing / validation happens before any request.
	check(Share.parse_challenge("https://play.host.app/c/k7mpq2xr") == "K7MPQ2XR", "https link parsed")
	check(Share.parse_challenge("loopfactory://challenge/K7MPQ2XR?x=1") == "K7MPQ2XR", "scheme link parsed")
	check(Share.parse_challenge("--challenge=K7MP-Q2XR") == "K7MPQ2XR", "launch argument parsed")
	for bad in ["", "K7MPQ2X", "K7MPQ2XRR", "K7MPQ2X0", "K7MPQ2XI", "https://host/x/K7MPQ2XR", "<script>", "../../etc"]:
		check(Share.parse_challenge(bad) == "", "invalid link rejected: '%s'" % bad)

	_fresh_state()
	Game.state.data["settings"]["analytics"] = true
	An.clear()
	var made: Array = await _make_main(Vector2i(720, 1280))
	var main: Control = made[1]
	var d := {"kind": "campaign", "date": "2026-10-15", "rotations": 6, "par": 6, "stars": 3, "attempts": 1, "levelName": "Test"}
	# No plugin (this build): no native button, copy works, honest events, no private path shown.
	Share.fake_plugin = Callable()
	check(not Share.native_available(), "no native share plugin in this build")
	await Card.present(main, d)
	await _frames(2)
	check(main.find_child("ShareNative", true, false) == null, "no Share button without the plugin")
	var copy: Button = main.find_child("ShareCopy", true, false)
	check(copy != null, "copy-text fallback offered")
	copy.pressed.emit()
	check(DisplayServer.clipboard_get().contains("Loop Factory"), "text copied")
	var ev := _events()
	check(ev.has("share_card_created") and ev.has("share_text_copied"), "card created + text copied tracked (%s)" % [ev])
	check(not ev.has("share_sheet_opened"), "never claims a share sheet opened")
	main.close_overlay()
	await _frames(2)
	# With a plugin that opens the chooser: content handed over as a real file, only "opened" tracked.
	var calls: Array = []
	Share.fake_plugin = func(method: String, args: Array):
		calls.append([method, args])
		return true
	An.clear()
	await Card.present(main, d)
	await _frames(2)
	var nb: Button = main.find_child("ShareNative", true, false)
	check(nb != null, "Share button with the plugin")
	nb.pressed.emit()
	check(calls.size() == 1 and calls[0][0] == "share", "plugin asked to share")
	var path: String = calls[0][1][1] if calls.size() == 1 else ""
	check(path.is_absolute_path() and FileAccess.file_exists(path) and calls[0][1][2] == "image/png", "an existing PNG file is handed to the plugin")
	ev = _events()
	check(ev.has("share_sheet_opened") and not ev.has("share_text_copied"), "chooser opened tracked; nothing about recipients")
	main.close_overlay()
	# Plugin failure / cancellation: falls back to copying text.
	Share.fake_plugin = func(_m: String, _a: Array): return false
	An.clear()
	DisplayServer.clipboard_set("")
	var r: String = Card.share_native(main, "hello share", "", "campaign")
	check(r == Share.FAILED and DisplayServer.clipboard_get() == "hello share", "failed share falls back to copied text")
	check(_events().has("share_text_copied") and not _events().has("share_sheet_opened"), "failure not counted as a share")
	Share.fake_plugin = Callable()
	# Invite text always carries the code (manual entry), and only an https link.
	var inv: String = Card.invite_text({"code": "K7MPQ2XR", "url": "/c/K7MPQ2XR"}, 6)
	check(inv.contains("K7MPQ2XR") and not inv.contains("/c/K7MPQ2XR"), "invite has the code; relative links dropped")

	# Challenge screen: invalid / offline (code kept for next launch) / unknown.
	var Net: Node = root.get_node("Net")
	var saved_url: String = Net.base_url
	main.goto("challenge", {"code": "NOPE"})
	await _wait(0.5)
	var msg: Label = main.current.find_child("ChallengeMessage", true, false)
	check(msg != null and msg.text.contains("isn't a challenge code"), "invalid code explained without a request")
	Net.base_url = ""
	An.clear()
	main.goto("challenge", {"code": "k7mp q2xr"})
	await _wait(0.5)
	msg = main.current.find_child("ChallengeMessage", true, false)
	check(msg != null and msg.text.contains("offline"), "offline explained")
	check(Game.state.data["challenges"].get("pending", "") == "K7MPQ2XR", "code kept for the next launch")
	check(main.launch_challenge_code() == "K7MPQ2XR", "pending code reopened at launch")
	Net.base_url = "http://127.0.0.1:9"  # nothing listens: a network failure, not a 404
	main.goto("challenge", {"code": "K7MPQ2XR"})
	await _wait(1.5)
	msg = main.current.find_child("ChallengeMessage", true, false)
	check(msg != null and msg.text.contains("offline"), "unreachable server treated as offline, not 'expired'")
	Net.base_url = saved_url
	Game.state.data["challenges"].erase("pending")
	made[0].queue_free()
	await _frames(2)


# ----------------------------------------------------------------------------- Accessibility

func _a11y_tests() -> void:
	_fresh_state()
	var made: Array = await _make_main(Vector2i(720, 1280))
	var main: Control = made[1]
	main.home()
	await _wait(0.5)
	var close: Control = main.current.find_child("BubbleClose", true, false)
	if close != null:
		check(close.custom_minimum_size.x >= 88 and close.custom_minimum_size.y >= 88, "Captain Naps dismiss target is at least 88×88")
		check(close.tooltip_text != "", "dismiss button has an accessible name")
	var named := true
	for b in main.current.find_children("*", "LFIconButton", true, false):
		if (b as Control).tooltip_text == "":
			named = false
	check(named, "every icon button on Home has an accessible name")
	# Touch-only: no focus rings.
	check(main.get_viewport().gui_get_focus_owner() == null, "touch play leaves nothing focused")
	var play = await _play(main, "c08")
	check(play.reverse_btn.tooltip_text != "" and play.undo_btn.tooltip_text == "Undo", "play controls are named")
	# First key press: everything becomes focusable and something has focus.
	var ev := InputEventKey.new()
	ev.keycode = KEY_DOWN
	ev.pressed = true
	main._input(ev)
	await _frames(2)
	var owner: Control = main.get_viewport().gui_get_focus_owner()
	check(owner != null, "keyboard / D-pad input focuses a control")
	check(play.run_btn.focus_mode == Control.FOCUS_ALL and play.undo_btn.focus_mode == Control.FOCUS_ALL, "controls become focusable")
	main.goto("settings")
	await _wait(0.4)
	var all_focusable := true
	for b in main.current.find_children("*", "BaseButton", true, false):
		if (b as Control).focus_mode != Control.FOCUS_ALL:
			all_focusable = false
	check(all_focusable, "screens opened later are focusable too")
	load("res://scripts/ui/style.gd").set_keyboard_nav(false)
	made[0].queue_free()
	await _frames(2)
