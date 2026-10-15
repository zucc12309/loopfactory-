extends SceneTree
## Screenshots of the beta-readiness flows for docs/BETA_READINESS_IMPLEMENTATION.md:
##   xvfb-run godot --path apps/game --rendering-driver opengl3 -s res://tests_ui/beta_shots.gd -- --out=/abs/dir
## Desktop GL renderer at a 720×1280 phone-shaped viewport; not a phone capture.

var Game: Node
var out := "user://"


func _initialize() -> void:
	_run.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _shot(vp: SubViewport, name: String) -> void:
	await process_frame
	await process_frame
	vp.get_texture().get_image().save_png(out.path_join(name))
	print("saved ", name)


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	Game = root.get_node("Game")
	Game.store = load("res://scripts/core/save_store.gd").new("user://beta-shots-save.json")
	Game.state.data = load("res://scripts/core/game_state.gd").defaults()
	Game.state.data["settings"]["sfx"] = false
	Game.state.data["settings"]["music"] = false
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 1280)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	vp.add_child(main)
	await _wait(1.0)
	# 1. c08: the hold-to-turn-back cue (frozen frame of the filling ring).
	Game.state.data["settings"]["analyticsAsked"] = true
	main.goto("play", {"kind": "campaign", "index": Game.state.campaign_index["c08"]})
	await _wait(0.9)
	await _shot(vp, "beta-reverse-cue.png")
	# 2. Consent asked after the first delivery, at the transition to level 2.
	Game.state.data = load("res://scripts/core/game_state.gd").defaults()
	Game.state.data["settings"]["sfx"] = false
	Game.state.data["settings"]["music"] = false
	Game.state.data["active"] = null
	main.goto("play", {"kind": "campaign", "index": 0})
	await _wait(0.4)
	var play = main.current
	for mv in play.level["solution"]["moves"]:
		play._on_rotate(int(mv[0]), int(mv[1]))
	play.fast = true
	play._run()
	await _wait(3.5)
	play.board.skip_celebration()
	await _wait(1.5)
	play._next(play._win_res)
	await _wait(1.2)
	await _shot(vp, "beta-consent.png")
	main.answer_consent(false)
	# 3. Challenge opened while offline: honest message, code kept.
	root.get_node("Net").base_url = ""
	main.goto("challenge", {"code": "K7MPQ2XR"})
	await _wait(0.8)
	await _shot(vp, "beta-challenge-offline.png")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://beta-shots-save.json"))
	quit()
