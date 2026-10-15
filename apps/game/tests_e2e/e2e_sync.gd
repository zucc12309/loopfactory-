extends SceneTree
## End-to-end: real client autoloads against a running API (scripts/e2e.sh starts it).
## Offline play -> queue -> reconnect -> guest auth -> sync -> daily replay submission -> leaderboard.

var failures := 0
# Classes are loaded at runtime (like tests_ui): they reference autoloads, which don't exist yet when
# this script is compiled, so static references would log a spurious compile error first.
var LFGameState: GDScript
var LFSolver: GDScript
var LFTiles: GDScript


func check(cond: bool, msg: String) -> void:
	if cond:
		print("ok   ", msg)
	else:
		failures += 1
		printerr("FAIL ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LFGameState = load("res://scripts/core/game_state.gd")
	LFSolver = load("res://scripts/engine/solver.gd")
	LFTiles = load("res://scripts/engine/tiles.gd")
	var api := OS.get_environment("LF_API")
	var Game = root.get_node("Game")
	var Net = root.get_node("Net")
	Game.wipe_local()
	var st = Game.state
	# 1. Offline: no server reachable.
	Net.base_url = "http://127.0.0.1:9"
	for i in 2:
		st.start_level("campaign", st.campaign[i])
		for mv in st.campaign[i]["solution"]["moves"]:
			st.rotate(int(mv[0]), int(mv[1]))
		check(not st.complete_active().is_empty(), "offline completion %d" % i)
	Game.set_setting("sfx", false)
	await Net.sync()
	check(not Net.online, "detected offline")
	var queued: int = st.data["syncQueue"].size()
	check(queued == 3, "3 operations queued offline (got %d)" % queued)
	# Backoff was applied; make them due again for the test.
	for op in st.data["syncQueue"]:
		op["nextAttemptAt"] = 0
	# 2. Connectivity returns.
	Net.base_url = api
	await Net.sync()
	check(Net.online, "online after reconnect")
	check(str(st.data["auth"]["playerId"]).length() == 36, "guest account created")
	check(st.data["syncQueue"].is_empty(), "queue drained (left %d)" % st.data["syncQueue"].size())
	# 3. Official daily: download, solve with the client solver (server strips solutions), submit.
	var date: String = LFGameState.utc_date()
	var entry = await Net.fetch_daily(date)
	check(entry != null, "daily downloaded")
	if entry == null:
		quit(1)
		return
	var lvl: Dictionary = entry["level"]
	check(not lvl.has("solution"), "daily arrives without solution")
	var sol: Dictionary = LFSolver.solve(lvl, LFTiles.start_rotations(lvl))
	check(sol["status"] == "solved", "client solver solves the daily")
	st.start_level("daily", lvl)
	st.active()["date"] = date
	for mv in sol["moves"]:
		st.rotate(int(mv[0]), int(mv[1]))
	var res: Dictionary = st.complete_active()
	check(not res.is_empty(), "daily completed")
	await Net.sync()
	check(st.data["daily"]["results"][date]["submitted"], "daily submission accepted by server")
	var lb = await Net.daily_leaderboard(date)
	check(lb != null and lb["me"] != null and int(lb["me"]["rotations"]) == sol["moves"].size(), "player appears on daily leaderboard with verified rotations")
	# 4. Server snapshot merged back: a fresh state merging the server snapshot sees both levels.
	var snap: Dictionary = await Net.call_api(HTTPClient.METHOD_GET, "/api/v1/progress")
	check(snap["ok"] and snap["body"]["progress"].size() == 2, "server holds both offline completions")
	check(snap["body"]["settings"]["sfx"] == false, "settings synced")
	var fresh = LFGameState.new(st.campaign, st.achievements_def)
	fresh.merge_remote(snap["body"])
	check(fresh.completed_count() == 2, "reinstall-style merge restores progress")
	# 5. Friend challenge: create from a solve, then a second (silent guest) player accepts it.
	var c6: Dictionary = st.campaign[5]
	var created = await Net.create_challenge("campaign", c6, c6["solution"]["moves"])
	check(created != null and str(created["code"]).length() == 8, "challenge created from a verified solve")
	if created != null:
		var own = await Net.submit_challenge_attempt(str(created["code"]), c6["solution"]["moves"])
		check(own == null, "creator cannot attempt their own challenge")
		# Become a different player without any sign-up step (new guest identity).
		st.data["auth"] = {"playerId": "", "refreshToken": "", "displayName": ""}
		Net._access_token = ""
		var view = await Net.get_challenge(str(created["code"]).to_lower())
		check(view != null and not view["level"].has("solution"), "recipient fetches the puzzle without its solution")
		check(view != null and int(view["creatorRotations"]) == c6["solution"]["moves"].size(), "recipient sees the score to beat")
		if view != null:
			var sol2: Dictionary = LFSolver.solve(view["level"], LFTiles.start_rotations(view["level"]))
			var out = await Net.submit_challenge_attempt(str(created["code"]), sol2["moves"])
			check(out != null and out["valid"] and out["outcome"] == "tie", "server-verified comparison (tie at par)")
	# 6. Account recovery boundary (audit R5): link a verified identity, reinstall, restore.
	var b_id: String = st.data["auth"]["playerId"]
	var subject := "dev:e2e_%d" % (Time.get_ticks_usec() % 100000000)
	var linked: Dictionary = await Net.link_identity("dev", subject)
	check(linked["ok"] and linked["mode"] == "linked" and st.data["auth"]["linked"], "guest links a verified identity")
	# Reinstall: everything local is gone; one level is solved offline before signing in again.
	Game.wipe_local()
	st = Game.state
	Net._access_token = ""
	st.start_level("campaign", st.campaign[2])
	for mv in st.campaign[2]["solution"]["moves"]:
		st.rotate(int(mv[0]), int(mv[1]))
	st.complete_active()
	await Net.sync()
	var c_id: String = st.data["auth"]["playerId"]
	check(c_id.length() == 36 and c_id != b_id, "reinstall starts as a new guest")
	var refused: Dictionary = await Net.link_identity("dev", subject)
	check(not refused["ok"] and refused["error"] == "identity_in_use", "restore needs explicit confirmation to switch")
	var restored: Dictionary = await Net.link_identity("dev", subject, true)
	check(restored["ok"] and restored["mode"] == "switched", "restore switches to the linked account")
	check(st.data["auth"]["playerId"] == b_id and st.data["auth"]["previousPlayerIds"].has(c_id), "device adopts the restored account id")
	var snap2: Dictionary = await Net.call_api(HTTPClient.METHOD_GET, "/api/v1/progress")
	var keys: Array = snap2["body"]["progress"].map(func(p): return str(p["levelId"])) if snap2["ok"] else []
	check(keys.has(str(st.campaign[2]["id"])), "offline progress from the reinstall merged into the restored account")
	var verified: bool = snap2["ok"] and snap2["body"]["progress"].any(func(p): return str(p["levelId"]) == str(st.campaign[2]["id"]) and p["verified"])
	check(verified, "replayed completion arrives verified (replay re-simulated)")
	print("\nE2E: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
