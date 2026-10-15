extends Node
## Developer QA tour: `godot --path apps/game -- --tour=/abs/out/dir`
## Drives every screen, plays a level through the real UI code paths, and saves screenshots.
## Only active when the --tour user argument is present; never runs in normal play.

var out := ""
var main: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour="):
			out = a.substr(7)
	if out == "":
		queue_free()
		return
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("[tour] ", name)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	main = get_tree().root.get_node("Main")
	Game.set_setting("analyticsAsked", true)
	await _wait(1.6)
	await _shot("01_home")
	main.goto("levels")
	await _wait(0.6)
	await _shot("02_levels")
	main.goto("play", {"kind": "campaign", "index": 0})
	await _wait(0.8)
	await _shot("03_tutorial")
	# Solve level 6 (two colours) through the real screen API.
	main.goto("play", {"kind": "campaign", "index": 5})
	await _wait(0.6)
	var play = main.current
	await _shot("04_play_start")
	var sol: Array = play.level["solution"]["moves"]
	for i in sol.size() - 1:
		play._on_rotate(int(sol[i][0]), int(sol[i][1]))
		await _wait(0.12)
	play._hint()
	await _wait(0.5)
	await _shot("05_hint")
	var last: Array = sol[sol.size() - 1]
	play._on_rotate(int(last[0]), int(last[1]))
	await _wait(0.4)
	play._run()
	await _wait(1.0)
	await _shot("06_running")
	await _wait(3.5)
	await _shot("07_win")
	main.close_overlay()
	# A failing run on a later level.
	main.goto("play", {"kind": "campaign", "index": 7})
	await _wait(0.5)
	main.current._toggle_speed()
	main.current._run()
	await _wait(1.6)
	await _shot("08_fail")
	Game.set_setting("colorblind", true)
	main.goto("play", {"kind": "campaign", "index": 30})
	await _wait(0.7)
	await _shot("09_expert_colorblind")
	Game.set_setting("colorblind", false)
	main.goto("daily")
	await _wait(1.5)
	await _shot("10_daily")
	main.goto("profile")
	await _wait(0.8)
	await _shot("11_profile")
	main.goto("settings")
	await _wait(0.6)
	await _shot("12_settings")
	main.goto("play", {"kind": "endless"})
	await _wait(0.8)
	await _shot("13_endless")
	print("[tour] done")
	get_tree().quit()

