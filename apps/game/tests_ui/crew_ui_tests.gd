extends SceneTree
## Scene-level tests for the Interdimensional Delivery Crew (real renderer, real screens):
##   xvfb-run godot --path apps/game --rendering-driver opengl3 -s res://tests_ui/crew_ui_tests.gd
## * Pixels: every cosmetic leaves the symbol area pixel-identical; body colour and white symbol
##   are preserved; compact mode ignores cosmetics entirely.
## * Board: identical results/timing with characters on and off; compact detail on small boards;
##   failure reactions cleared by edit/undo/reset; background + long frame gap; repeated Run/Stop.
## * Screens: reduced motion, The Crew equip flow, Home in hybrid and minimal variants.

const CELL := 400
const SZ := 150.0

var failures := 0
var checks := 0
var Game: Node
var Painter: GDScript
var Crew: GDScript
var Anim: GDScript


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL ", msg)


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


func _run() -> void:
	Game = root.get_node("Game")
	Painter = load("res://scripts/crew/crew_painter.gd")
	Crew = load("res://scripts/crew/crew.gd")
	Anim = load("res://scripts/crew/crew_anim.gd")
	Game.store = load("res://scripts/core/save_store.gd").new("user://crew-ui-test-save.json")
	_fresh_state()
	await _pixel_tests()
	await _readability_tests()
	await _board_tests()
	await _screen_tests()
	print("\nCrew UI tests: %d checks, %d failed" % [checks, failures])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://crew-ui-test-save.json"))
	quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------------------------- pixels

## Render jobs [[cidx, art, detail_px, colorblind]] into a grid and return the image.
func _render(jobs: Array) -> Image:
	var cols := 8
	var vp := SubViewport.new()
	vp.size = Vector2i(cols * CELL, int(ceil(jobs.size() / float(cols))) * CELL)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var c := Control.new()
	c.size = Vector2(vp.size)
	vp.add_child(c)
	root.add_child(vp)
	c.draw.connect(func():
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color("#F7F5F0"))
		for k in jobs.size():
			var j: Array = jobs[k]
			var def: Dictionary = Crew.for_color(j[0])
			var at := Vector2((k % cols + 0.5) * CELL, (k / cols + 0.5) * CELL)
			var pose: Dictionary = Painter.expression(Crew.body_of(def), "happy")
			Painter.draw_package(c, Crew.body_of(def), at, j[2], pose, {"color": Color(["#F28B66", "#4F9BEA", "#9C7BDB", "#3FB596"][j[0]]), "cidx": j[0], "detail": Painter.detail_for(j[2]), "cosmetic": j[1], "colorblind": j[3], "style": def.get("style", {})}))
	await _frames(3)
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


func _cell_origin(k: int) -> Vector2i:
	return Vector2i((k % 8) * CELL, (k / 8) * CELL)


func _region_equal(img: Image, a: int, b: int, center: Vector2, radius: float) -> bool:
	var oa := _cell_origin(a)
	var ob := _cell_origin(b)
	for y in range(int(center.y - radius), int(center.y + radius) + 1):
		for x in range(int(center.x - radius), int(center.x + radius) + 1):
			if Vector2(x, y).distance_to(center) > radius:
				continue
			# 3/255 tolerance: the software rasteriser rounds anti-aliased edges differently at
			# different screen positions (measured: at most 1/255).
			var pa := img.get_pixel(oa.x + x, oa.y + y)
			var pb := img.get_pixel(ob.x + x, ob.y + y)
			if absf(pa.r - pb.r) > 0.012 or absf(pa.g - pb.g) > 0.012 or absf(pa.b - pb.b) > 0.012:
				return false
	return true


func _pixel_tests() -> void:
	var jobs: Array = []
	var pairs: Array = []  # [base job index, cosmetic job index, label, detail_px]
	for cidx in 4:
		var def: Dictionary = Crew.for_color(cidx)
		for cb in [false, true]:
			for px in [SZ, 30.0]:
				var base := jobs.size()
				jobs.append([cidx, "", px, cb])
				for cos in def.get("cosmetics", []):
					pairs.append([base, jobs.size(), "%s %s cb=%s px=%d" % [def["id"], cos["art"], cb, px], px])
					jobs.append([cidx, str(cos["art"]), px, cb])
	var img := await _render(jobs)
	if OS.get_environment("CREW_DUMP") != "":
		img.save_png(OS.get_environment("CREW_DUMP"))
	var half := CELL / 2.0
	for p in pairs:
		var px: float = p[3]
		var full: bool = px >= Painter.FULL_MIN
		var sc: Vector2 = Painter.symbol_center(Painter.FULL if full else Painter.COMPACT)
		var guard: float = Painter.SYMBOL_GUARD * px + 1.0
		var center := Vector2(half, half) + sc * px
		check(_region_equal(img, p[0], p[1], center, guard), "%s leaves the symbol area untouched" % p[2])
		if not full:
			check(_region_equal(img, p[0], p[1], Vector2(half, half), CELL * 0.48), "%s: compact characters ignore cosmetics" % p[2])
	# Identity: body colour and a white symbol at the symbol centre (full detail, no cosmetic).
	for k in jobs.size():
		var j: Array = jobs[k]
		if j[1] != "" or j[2] != SZ:
			continue
		var o := _cell_origin(k)
		var col: Color = [Color("#F28B66"), Color("#4F9BEA"), Color("#9C7BDB"), Color("#3FB596")][j[0]]
		var body := img.get_pixel(o.x + int(half + 0.36 * SZ), o.y + int(half + 0.05 * SZ))
		check(body.is_equal_approx(col) or (absf(body.r - col.r) < 0.02 and absf(body.g - col.g) < 0.02 and absf(body.b - col.b) < 0.02), "colour %d body keeps its package colour (%s vs %s)" % [j[0], body.to_html(), col.to_html()])
		var sym := img.get_pixel(o.x + int(half), o.y + int(half + Painter.SYMBOL_FULL.y * SZ))
		check(sym.r > 0.95 and sym.g > 0.95 and sym.b > 0.95, "colour %d symbol is white at its centre" % j[0])


## Readability at real displayed body sizes (16/24/32/48 px): the symbol is visible and the four
## symbols stay distinguishable from each other (binary masks of the white symbol pixels differ).
func _readability_tests() -> void:
	var sizes := [16.0, 24.0, 32.0, 48.0]
	var jobs: Array = []
	for px in sizes:
		for cb in [false, true]:
			for cidx in 4:
				jobs.append([cidx, "", px, cb])
	var img := await _render(jobs)
	var half := CELL / 2.0
	var masks := {}
	var report: PackedStringArray = []
	for k in jobs.size():
		var j: Array = jobs[k]
		var px: float = j[2]
		var det: int = Painter.detail_for(px)
		var c: Vector2 = Vector2(half, half) + Painter.symbol_center(det) * px
		var r: float = Painter.symbol_radius(det, j[3]) * px * 1.5 + 1.0
		var o := _cell_origin(k)
		var mask := {}
		for y in range(int(c.y - r), int(c.y + r) + 1):
			for x in range(int(c.x - r), int(c.x + r) + 1):
				var p := img.get_pixel(o.x + x, o.y + y)
				if p.r > 0.8 and p.g > 0.8 and p.b > 0.8:
					mask[Vector2i(x - int(c.x), y - int(c.y))] = true
		masks[k] = mask
		if j[0] == 0:
			report.append("%dpx%s=%d" % [int(px), " cb" if j[3] else "", mask.size()])
		check(mask.size() >= 4, "symbol visible at %d px (colour %d, larger symbols %s): %d white px" % [int(px), j[0], j[3], mask.size()])
	print("     symbol pixels (colour 0): ", ", ".join(report))
	for k in range(0, jobs.size(), 4):
		for a in 4:
			for b in range(a + 1, 4):
				var ma: Dictionary = masks[k + a]
				var mb: Dictionary = masks[k + b]
				var diff := 0
				for key in ma:
					if not mb.has(key):
						diff += 1
				for key in mb:
					if not ma.has(key):
						diff += 1
				check(diff >= 3, "%d px%s: %s vs %s symbols distinguishable (%d px differ)" % [int(jobs[k][2]), " (larger)" if jobs[k][3] else "", ["circle", "square", "triangle", "diamond"][a], ["circle", "square", "triangle", "diamond"][b], diff])


# ---------------------------------------------------------------------------------- board

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


## Run the current puzzle and return [result, playback duration in board time].
func _run_and_wait(play) -> Array:
	var out := []
	play.board.playback_finished.connect(func(r): out.append([r, play.board._time]), CONNECT_ONE_SHOT)
	play._run()
	var t0: float = play.board._time
	var n := 0
	while out.is_empty() and n < 3000:
		await process_frame
		n += 1
	return [out[0][0], out[0][1] - t0] if not out.is_empty() else [{}, -1.0]


func _board_tests() -> void:
	var made: Array = await _make_main(Vector2i(720, 1280))
	var main: Control = made[1]
	# --- identical results with characters on and off
	var runs := {}
	for variant in ["hybrid", "minimal"]:
		Game.state.data["remoteConfig"] = {"experiments": {"presentation": {"force": variant}}}
		var play = await _play(main, "c20")
		check(play.board.crew_on == (variant == "hybrid"), "%s: characters %s" % [variant, "on" if variant == "hybrid" else "off"])
		for mv in play.level["solution"]["moves"]:
			play._on_rotate(int(mv[0]), int(mv[1]))
		var delivered := [0]
		play.board.package_delivered.connect(func(_c): delivered[0] += 1)
		var r: Array = await _run_and_wait(play)
		runs[variant] = [r[0].get("success"), r[0].get("ticks"), r[0].get("delivered"), r[0].get("reason"), delivered[0], r[1]]
		play.board.skip_celebration()
		await _frames(3)
		main.close_overlay()
	check(runs["hybrid"].slice(0, 5) == runs["minimal"].slice(0, 5), "same result and deliveries with and without characters %s" % [runs])
	check(absf(float(runs["hybrid"][5]) - float(runs["minimal"][5])) <= 0.06, "same playback length (%.2f s vs %.2f s)" % [runs["hybrid"][5], runs["minimal"][5]])
	Game.state.data["remoteConfig"] = {}

	# --- detail levels
	var big = await _play(main, "c06")
	check(big.board.crew_detail() == Painter.FULL, "4×4 board at 720×1280 uses full characters (cell %.0f)" % big.board.cell_size())
	var made_small: Array = await _make_main(Vector2i(720, 960))
	var small = await _play(made_small[1], "c34")
	var cell: float = small.board.cell_size()
	check(small.board.crew_detail() == Painter.COMPACT, "6×7 board at 720×960 switches to compact characters (cell %.0f)" % cell)
	check(Painter.symbol_radius(Painter.COMPACT, false) * cell * small.board.CREW_K >= 4.5, "compact symbol stays at least 9 px across")
	made_small[0].queue_free()
	await _frames(2)

	# --- failure reaction cleared by edit, undo and reset
	var play = await _play(main, "c34")
	play.fast = true
	var res: Array = await _run_and_wait(play)
	await _frames(2)
	check(not res[0].get("success", true), "unsolved start fails")
	check(not play.board._src_mood.is_empty(), "the failing character shows its reaction in its source")
	var rot := -1
	for i in play.level["tiles"].size():
		if load("res://scripts/engine/tiles.gd").is_rotatable(play.level["tiles"][i]):
			rot = i
			break
	play._on_rotate(rot, 1)
	check(play.board._src_mood.is_empty(), "an edit clears the reaction")
	await _run_and_wait(play)
	await _frames(2)
	play._undo()
	check(play.board._src_mood.is_empty() and play.board._fail_cell < 0, "undo clears the reaction")
	await _run_and_wait(play)
	await _frames(2)
	play._reset()
	check(play.board._src_mood.is_empty(), "reset clears the reaction")
	var settled: Array = play.board.settled_rotations()
	var start: Array = Game.state.active()["rotations"]
	var same := true
	var Tiles: GDScript = load("res://scripts/engine/tiles.gd")
	for i in start.size():
		if Tiles.is_rotatable(play.level["tiles"][i]) and posmod(int(settled[i]) - int(start[i]), Tiles.PERIOD[play.level["tiles"][i]["t"]]) != 0:
			same = false
	check(same, "reset restores every belt visually")

	# --- background mid-run + one huge frame gap (app resumed after minutes)
	var p2 = await _play(main, "c20")
	for mv in p2.level["solution"]["moves"]:
		p2._on_rotate(int(mv[0]), int(mv[1]))
	var out := []
	p2.board.playback_finished.connect(func(r): out.append(r), CONNECT_ONE_SHOT)
	p2._run()
	await _frames(8)
	Game.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	p2.board._process(45.0)
	Game.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	for i in 120:
		if not out.is_empty():
			break
		await process_frame
	check(not out.is_empty() and out[0]["success"] == true and int(out[0]["ticks"]) == int(runs["hybrid"][1]), "a long background gap finishes the same run with the same result")
	await _frames(3)
	check(is_finite(p2.board._time), "board time stays finite")
	p2.board.skip_celebration()
	await _frames(3)
	main.close_overlay()

	# --- repeated Run/Stop leaves no duplicate animations behind
	var p3 = await _play(main, "c34")
	for k in 12:
		p3._run()
		await _frames(1 + k % 3)
		p3._stop()
	await _frames(3)
	check(not p3.board.playing and p3.board._frames.is_empty() and not p3.board.celebrating, "Run/Stop ×12 ends clean")
	check(p3.board.crew_draws == 0, "no characters left drawing after Stop (%d)" % p3.board.crew_draws)
	check(p3.board._particles.size() < 80, "no particle build-up (%d)" % p3.board._particles.size())
	check(p3.edit_bar.visible and not p3.run_bar.visible, "edit controls back")

	# --- tapping a source pokes its character, never the 'pinned belt' coach
	var src := -1
	for i in p3.level["tiles"].size():
		if p3.level["tiles"][i]["t"] == "source":
			src = i
			break
	p3.board._activate(src, 1)
	check(p3.board._src_poke.has(src), "source tap starts the character's reaction")
	check(p3._banner_kind != "coach", "source tap doesn't show the pinned-belt message")
	made[0].queue_free()
	await _frames(2)


# ---------------------------------------------------------------------------------- screens

func _screen_tests() -> void:
	var made: Array = await _make_main(Vector2i(720, 1280))
	var main: Control = made[1]
	# Reduced motion stops character animation but keeps characters.
	Game.state.data["settings"]["reducedMotion"] = true
	var p = await _play(main, "c06")
	check(p.board.crew_on and not p.board.crew_motion, "reduced motion: characters stay, motion stops")
	Game.state.data["settings"]["reducedMotion"] = false
	Game.state.data["settings"]["crewAnimations"] = false
	p = await _play(main, "c06")
	check(p.board.crew_on and not p.board.crew_motion, "character animations setting")
	Game.state.data["settings"]["crewAnimations"] = true
	Game.state.data["settings"]["crewCharacters"] = false
	p = await _play(main, "c06")
	check(not p.board.crew_on, "character packages setting restores classic boxes")
	Game.state.data["settings"]["crewCharacters"] = true

	# The Crew: roster, detail, equip, persistence through save + reload.
	for i in 10:
		Game.state.data["progress"][Game.state.campaign[i]["id"]] = {"completed": true, "best": 1, "par": 1, "stars": 3, "completedAt": 1, "kind": "campaign"}
	Crew.evaluate_unlocks(Game.state.data, Game.state.campaign, 1)
	main.goto("crew")
	await _wait(0.4)
	check(main.current_name == "crew", "The Crew opens")
	main.goto("crew", {"id": "bloop"})
	await _wait(0.4)
	main.current._wear("bloop_crown")
	await _frames(2)
	check(Crew.equipped(Game.state.data, "bloop") == "bloop_crown", "equip from the detail page")
	check(main.current._portrait.cosmetic == "crown", "preview wears the new look")
	check(Game.state.data["crew"]["seen"].has("bloop_crown"), "opening the page marks looks seen")
	Game.save_now()
	var st2 = load("res://scripts/core/game_state.gd").new(Game.state.campaign, Game.state.achievements_def)
	st2.load_from(Game.store.load_data())
	check(Crew.equipped(st2.data, "bloop") == "bloop_crown", "equipped look survives save and reload")
	p = await _play(main, "c06")
	check(p.board.crew_art.get(0, "") == "crown", "the board uses the equipped look")

	# Home: Captain Naps in hybrid (never covering navigation), the logo in minimal.
	main.home()
	await _wait(0.4)
	var home = main.current
	check(home._naps != null, "Captain Naps on Home")
	var cont: Control = null
	for c in home.find_children("*", "PanelContainer", true, false):
		if c.get_global_rect().size.y > 150 and c.mouse_filter == Control.MOUSE_FILTER_STOP:
			cont = c
			break
	check(cont != null and not home._naps.get_global_rect().intersects(cont.get_global_rect()), "Captain Naps never overlaps Continue")
	Game.state.data["remoteConfig"] = {"experiments": {"presentation": {"force": "minimal"}}}
	main.home()
	await _wait(0.4)
	check(main.current._naps == null and not main.current.find_children("*", "LFLogo", true, false).is_empty(), "minimal variant shows the original logo")
	Game.state.data["remoteConfig"] = {}
	made[0].queue_free()
	await _frames(2)
