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
	play._hint()
	await _wait(0.5)
	await _shot("05_hint")
	var last: Array = sol[sol.size() - 1]
	play._on_rotate(int(last[0]), int(last[1]))
	await _wait(0.4)
	play._run()
	await _wait(1.0)
	await _shot("06_running")
	while not play.board.celebrating and not main.has_overlay():
		await get_tree().process_frame
	await _shot("06b_celebration")
	await _wait(1.6)
	await _shot("07_win")
	main.close_overlay()
	# Replay of the solution just made (clean presentation).
	var rp = Game.state.replay_for(play.level["id"])
	main.goto("replay", {"key": play.level["id"], "title": "Your solution"})
	await _wait(0.7 + 0.32 * rp["moves"].size() + 0.2)
	await _shot("07b_replay")
	main.current._set_clean(true)
	await _wait(1.2)
	await _shot("07c_replay_clean")
	# Share card render (the same image the Save image button writes).
	var img: Image = await LFShareCard.render(main, {"kind": "daily", "date": "2026-10-15", "difficulty": "medium", "rotations": 9, "par": 8, "stars": 2, "attempts": 3})
	img.save_png(out.path_join("07d_share_card.png"))
	print("[tour] 07d_share_card")
	LFShareCard.present(main, {"kind": "daily", "date": "2026-10-15", "difficulty": "medium", "rotations": 9, "par": 8, "stars": 2, "attempts": 3})
	await _wait(0.8)
	await _shot("07e_share_sheet")
	main.close_overlay()
	main.goto("challenge")
	await _wait(0.6)
	await _shot("07f_challenge")
	# A failing run on a later level.
	main.goto("play", {"kind": "campaign", "index": 7})
	await _wait(0.5)
	main.current._hint()
	await _wait(0.4)
	await _shot("08a_hint_area")
	main.current._reset()
	await _wait(0.5)
	main.current._toggle_speed()
	main.current._run()
	await _wait(1.6)
	await _shot("08_fail")
	Game.set_setting("colorblind", true)
	main.goto("play", {"kind": "campaign", "index": Game.state.campaign_index["c31"]})
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
	main.goto("play", {"kind": "campaign", "index": Game.state.campaign_index["x26"]})
	await _wait(0.8)
	await _shot("14_neon_world")
	main.goto("play", {"kind": "campaign", "index": 1})
	await _wait(0.8)
	await _shot("15_coach_connect")
	# --- The Interdimensional Delivery Crew
	main.goto("play", {"kind": "campaign", "index": Game.state.campaign_index["c07"]})
	await _wait(0.8)
	await _shot("16_rix_intro")
	Game.state.data["remoteConfig"] = {"experiments": {"presentation": {"force": "full"}}}
	main.goto("play", {"kind": "campaign", "index": Game.state.campaign_index["x31"]})
	await _wait(0.8)
	await _shot("17_scifi_variant")
	Game.state.data["remoteConfig"] = {}
	# Simulate a player who has finished the first world and a bit more, to show unlocked looks.
	for i in 12:
		var lvl: Dictionary = Game.state.campaign[i]
		if not Game.state.data["progress"].has(lvl["id"]):
			Game.state.data["progress"][lvl["id"]] = {"completed": true, "best": lvl["par"], "par": lvl["par"], "stars": 3, "completedAt": 1, "kind": "campaign"}
	Game.state.data["stats"]["perfect"] = 12
	LFCrew.evaluate_unlocks(Game.state.data, Game.state.campaign, LFGameState.now_ms())
	LFCrew.equip(Game.state.data, "bloop", "bloop_crown")
	LFCrew.equip(Game.state.data, "glitch", "glitch_shades")
	LFCrew.equip(Game.state.data, "naps", "naps_detective")
	main.home()
	await _wait(0.8)
	await _shot("18_home_crew")
	main.goto("crew")
	await _wait(0.8)
	await _shot("19_crew")
	main.goto("crew", {"id": "bloop"})
	await _wait(1.0)
	await _shot("20_crew_bloop")
	main.goto("play", {"kind": "campaign", "index": Game.state.campaign_index["c20"]})
	await _wait(0.6)
	var p = main.current
	for mv in p.level["solution"]["moves"]:
		p._on_rotate(int(mv[0]), int(mv[1]))
	await _wait(0.4)
	p._run()
	await _wait(1.5)
	await _shot("21_crew_running")
	while not p.board.celebrating and not main.has_overlay():
		await get_tree().process_frame
	await _wait(0.35)
	await _shot("22_crew_celebration")
	await _wait(1.6)
	await _shot("23_crew_win")
	var img2: Image = await LFShareCard.render(main, {"kind": "daily", "date": "2026-10-15", "difficulty": "medium", "rotations": 8, "par": 8, "stars": 3, "attempts": 2, "crew": true, "featured": 2, "reaction": "Glitch: “That was probably supposed to happen.”"})
	img2.save_png(out.path_join("24_crew_share_card.png"))
	print("[tour] done")
	get_tree().quit()

