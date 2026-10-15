extends SceneTree
## Board rendering micro-benchmark (not part of CI):
##   xvfb-run godot --path apps/game --rendering-driver opengl3 -s res://tests_ui/bench_board.gd
## Plays a small and the largest campaign board and reports the board's own per-frame CPU work
## (process + draw-command recording). Results are recorded in docs/performance.md.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var Game = root.get_node("Game")
	Game.state.data["settings"]["sfx"] = false
	var Sim = load("res://scripts/engine/simulation.gd")
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 1280)
	root.add_child(vp)
	var board = load("res://scripts/ui/board_view.gd").new()
	board.size = Vector2(664, 900)
	vp.add_child(board)
	for id in ["c06", "c34"]:
		var lvl: Dictionary = Game.state.campaign[Game.state.campaign_index[id]]
		board.set_level(lvl, lvl["solution"]["rotations"])
		var res = Sim.simulate(lvl, lvl["solution"]["rotations"])
		board.start_playback(res, 0.3)
		for i in 30:
			await process_frame
		board.perf_samples.clear()
		var m0: int = board.sb_misses
		var o0 := Performance.get_monitor(Performance.OBJECT_COUNT)
		for i in 120:
			await process_frame
		var s: Array = board.perf_samples.duplicate()
		s.sort()
		print("%s %dx%d: board work p50 %.2f ms p95 %.2f ms max %.2f ms (%d frames), stylebox misses %d, objects %+d" % [id, lvl["width"], lvl["height"], s[s.size() / 2] / 1000.0, s[int(s.size() * 0.95)] / 1000.0, s[-1] / 1000.0, s.size(), board.sb_misses - m0, Performance.get_monitor(Performance.OBJECT_COUNT) - o0])
	quit()
