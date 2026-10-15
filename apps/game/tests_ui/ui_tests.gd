extends SceneTree
## Scene-level UI tests (real screens, real autoloads, headless):
##   godot --headless --path apps/game -s res://tests_ui/ui_tests.gd
## * Layout: on five aspect ratios the board never overlaps the header, banner or controls, stays
##   fully on screen, keeps comfortable cells and the win card fits.
## * Feel: 40 rapid taps with no frames in between converge to exactly the model's rotations.
## * Flow: failure feedback lands in the banner + board; the celebration is skippable.
## Uses a separate save file so a developer's own progress is never touched.

const SIZES := [Vector2i(720, 960), Vector2i(720, 1280), Vector2i(720, 1440), Vector2i(720, 1560), Vector2i(720, 1600)]
const MIN_CELL := 72.0
const MIN_BUTTON := 88.0

# Classes are loaded at runtime: this script compiles before autoloads exist, and the game's
# classes reference autoloads (Game, Sfx), so static references here would fail to compile.
var Tiles: GDScript
var failures := 0
var checks := 0
var Game: Node


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _make_main(size: Vector2i) -> Array:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	root.add_child(vp)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	vp.add_child(main)
	await _frames(2)
	return [vp, main]


func _rect(c: Control) -> Rect2:
	return c.get_global_rect()


func _run() -> void:
	Game = root.get_node("Game")
	Tiles = load("res://scripts/engine/tiles.gd")
	Game.store = load("res://scripts/core/save_store.gd").new("user://ui-test-save.json")
	Game.state.data = load("res://scripts/core/game_state.gd").defaults()
	Game.state.data["settings"]["analyticsAsked"] = true
	Game.state.data["settings"]["sfx"] = false
	Game.state.data["settings"]["music"] = false
	var st = Game.state
	var idx := {}
	for i in st.campaign.size():
		idx[st.campaign[i]["id"]] = i
	var probe_levels := [0, idx["c08"], idx["c20"], idx["c34"]]

	for size in SIZES:
		var made: Array = await _make_main(size)
		var vp: SubViewport = made[0]
		var main: Control = made[1]
		for li in probe_levels:
			Game.state.data["active"] = null
			main.goto("play", {"kind": "campaign", "index": li})
			await _wait(0.35)  # let the screen transition finish before measuring
			var play = main.current
			var tag := "%dx%d %s" % [size.x, size.y, st.campaign[li]["id"]]
			var screen := Rect2(Vector2.ZERO, Vector2(size))
			var board = play.board
			var br := Rect2(board.global_position + board.board_rect().position, board.board_rect().size)
			check(screen.encloses(br), "%s board fully on screen %s" % [tag, br])
			check(_rect(board).encloses(br), "%s board drawn inside its control" % tag)
			var banner_r := _rect(play.banner)
			var edit_r := _rect(play.edit_bar)
			check(banner_r.end.y <= _rect(board).position.y + 0.5, "%s banner above board" % tag)
			check(_rect(board).end.y <= edit_r.position.y + 0.5, "%s controls below board" % tag)
			check(edit_r.end.y <= size.y, "%s controls on screen" % tag)
			check(banner_r.end.x <= size.x + 0.5 and _rect(play.moves_view).end.x <= size.x + 0.5, "%s header and banner don't overflow horizontally (banner %s, moves %s)" % [tag, banner_r, _rect(play.moves_view)])
			check(board.cell_size() >= MIN_CELL, "%s cell %.0f >= %.0f" % [tag, board.cell_size(), MIN_CELL])
			for b in play.edit_bar.get_children():
				check(b.size.y >= MIN_BUTTON and b.size.x >= MIN_BUTTON, "%s button %s tappable %s" % [tag, b.name, b.size])
			# Long failure copy must wrap inside the banner, not widen the screen.
			play._set_banner("fail", "The purple package hit a belt that isn't connected on that side.", "The marked tile doesn't accept packages from that side.")
			await _frames(3)
			check(_rect(play.banner).end.x <= size.x + 0.5, "%s long banner wraps" % tag)
			check(_rect(play.banner).end.y <= _rect(play.board).position.y + 0.5, "%s long banner stays above board" % tag)
		# Win card fits on this screen.
		Game.state.data["active"] = null
		main.goto("play", {"kind": "campaign", "index": idx["c34"]})
		await _frames(3)
		var p2 = main.current
		var lvl: Dictionary = p2.level
		for mv in lvl["solution"]["moves"]:
			p2._on_rotate(int(mv[0]), int(mv[1]))
		p2.fast = true
		p2._run()
		for i in 600:
			await process_frame
			if p2.board.celebrating:
				break
		check(p2.board.celebrating, "%dx%d celebration starts after a winning run" % [size.x, size.y])
		p2.board.skip_celebration()
		await _frames(3)
		check(main.has_overlay(), "%dx%d skipping the celebration shows the result card immediately" % [size.x, size.y])
		var card: Control = main._overlay_layer.get_child(1).get_child(0)
		await _frames(2)
		check(Rect2(Vector2.ZERO, Vector2(size)).encloses(_rect(card)), "%dx%d result card fits %s" % [size.x, size.y, _rect(card)])
		# Closing the card while the stars are still animating must not touch freed nodes
		# (regression: the star tween used to outlive the card; any SCRIPT ERROR fails the run).
		main.close_overlay()
		await _wait(0.3)
		vp.queue_free()
		await _frames(2)

	# ---- rapid taps: visual state converges to the model with no lost or extra rotations
	var made2: Array = await _make_main(Vector2i(720, 1280))
	var main2: Control = made2[1]
	Game.state.data["active"] = null
	main2.goto("play", {"kind": "campaign", "index": idx["c34"]})
	await _frames(3)
	var play: Variant = main2.current
	var tiles: Array = play.level["tiles"]
	var rot_idx: Array = []
	for i in tiles.size():
		if Tiles.is_rotatable(tiles[i]):
			rot_idx.append(i)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for k in 40:
		var i: int = rot_idx[rng.randi() % rot_idx.size()]
		play._on_rotate(i, 1 if rng.randf() < 0.7 else -1)
		if k % 7 == 0:
			play._undo()
	await _wait(0.4)
	var model: Array = Game.state.active()["rotations"]
	var settled: Array = play.board.settled_rotations()
	var match_all := true
	for i in model.size():
		if Tiles.is_rotatable(tiles[i]) and posmod(int(settled[i]) - int(model[i]), Tiles.PERIOD[tiles[i]["t"]]) != 0:
			match_all = false
	check(match_all, "visual rotations converge to the model after 40 rapid taps + undos")
	var anim_done := true
	for t in play.board._rot_t:
		if t < 1.0:
			anim_done = false
	check(anim_done, "all rotation animations finished within 0.4 s")
	eq_moves(play)

	# ---- failure feedback
	play._reset()
	await _frames(2)
	play.fast = true
	play._run()
	for i in 600:
		await process_frame
		if play.edit_bar.visible:
			break
	check(play._banner_kind == "fail", "failed run explains itself in the banner (got '%s')" % play._banner_kind)
	check(play.board._fail_cell >= 0, "failed run marks a tile on the board")
	check(not main2.has_overlay(), "failure never opens a modal over the board")

	print("\nUI tests: %d checks, %d failed" % [checks, failures])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ui-test-save.json"))
	quit(1 if failures > 0 else 0)


func eq_moves(play) -> void:
	check(Game.state.moves_count() == Game.state.active()["history"].size(), "move counter matches history")
