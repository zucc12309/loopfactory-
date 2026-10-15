extends LFScreen
## Deterministic replay of a solution: start rotations → each recorded rotation (highlighted) →
## the real simulation → celebration. "Clean view" hides every control so the portrait frame shows
## only the board and a caption — suitable for screen-recording short clips.
## Args: {level, moves, title} or {key} (a progress key with a stored replay).

const MOVE_GAP := 0.32

var level: Dictionary
var moves: Array = []
var board: LFBoardView
var _chrome: Array[Control] = []
var _caption: Label
var _clean := false
var _run_id := 0


func setup(args: Dictionary) -> void:
	if args.has("key"):
		var rp = Game.state.replay_for(str(args["key"]))
		if rp != null:
			moves = rp["moves"]
			if rp.has("level"):
				level = LFTiles.normalize_level(rp["level"])
			elif Game.state.campaign_index.has(rp["levelId"]):
				level = Game.state.campaign[Game.state.campaign_index[rp["levelId"]]]
	else:
		level = LFTiles.normalize_level(args["level"])
		moves = args.get("moves", [])
	if level.is_empty():
		var l := LFStyle.label("Replay unavailable.", 30)
		add_child(l)
		return
	var sm: Vector2 = main.safe_margins()
	var root := LFStyle.vbox(18)
	var m := LFStyle.margin(root, 28, 24 + int(sm.x), 28, 28 + int(sm.y))
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var head := header(str(args.get("title", "Replay")))
	root.add_child(head)
	_chrome.append(head)
	_caption = LFStyle.label("", 30, LFStyle.TEXT, 800, HORIZONTAL_ALIGNMENT_CENTER)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_caption)
	board = LFBoardView.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.interactive = false
	board.reduced_motion = main.reduced_motion()
	board.colorblind = bool(Game.settings().get("colorblind", false))
	board.palette = LFWorlds.palette(LFWorlds.index_for(Game.state.campaign, Game.state.campaign_index[level["id"]])) if Game.state.campaign_index.has(level["id"]) else LFWorlds.palette_for_level(level)
	LFCrew.configure_board(board, Game.state.data, board.palette)
	root.add_child(board)
	board.gui_input.connect(func(e): if _clean and e is InputEventMouseButton and e.pressed: _set_clean(false))
	var row := LFStyle.hbox(14)
	var again := LFStyle.button("Replay again", "", 100)
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(_play)
	row.add_child(again)
	var clean := LFIconButton.make("play", "Clean view", "SecondaryButton", 100)
	clean.custom_minimum_size.x = 150
	clean.pressed.connect(func(): _set_clean(true))
	row.add_child(clean)
	root.add_child(row)
	_chrome.append(row)
	Analytics.track("replay_viewed", {"level_id": str(level.get("id", "")), "moves": moves.size()})
	_play.call_deferred()


func _set_clean(on: bool) -> void:
	_clean = on
	for c in _chrome:
		c.visible = not on


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _play() -> void:
	_run_id += 1
	var my := _run_id
	var rots := LFTiles.start_rotations(level)
	board.set_level(level, rots)
	_caption.text = "%s · %d rotation%s" % [level["name"], moves.size(), "" if moves.size() == 1 else "s"]
	await _wait(0.7)
	for mv in moves:
		if my != _run_id or not is_inside_tree():
			return
		var i := int(mv[0])
		var dir := int(mv[1])
		board.animate_rotation(i, dir)
		board._flashes.append({"cell": i, "t": 0.0, "color": LFStyle.PRIMARY})
		rots[i] = (int(rots[i]) + dir + 4) & 3
		Sfx.play("rotate" if dir == 1 else "ccw")
		await _wait(MOVE_GAP)
	if my != _run_id or not is_inside_tree():
		return
	await _wait(0.25)
	var result := LFSimulation.simulate(level, rots)
	Sfx.play("run")
	board.start_playback(result, 0.24)
	var res: Dictionary = await board.playback_finished
	if my != _run_id or not is_inside_tree():
		return
	if res["success"]:
		Sfx.play("perfect" if moves.size() <= int(level["par"]) else "win")
		_caption.text = "Solved in %d · par %d" % [moves.size(), level["par"]]
		board.crew_ctx["perfect"] = moves.size() <= int(level["par"])
		board.celebrate(1.0)
	else:
		_caption.text = "This replay no longer solves the puzzle (content changed)."
