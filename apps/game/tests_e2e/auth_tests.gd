extends SceneTree
## Client authentication resilience (audit R3), headless, no server needed:
##   godot --headless --path apps/game -s res://tests_e2e/auth_tests.gd
## A fake token server is plugged into Net.transport. It rotates refresh tokens exactly like the API
## (single use) and can stall, drop, rate-limit or fail responses, so these tests exercise the real
## Net code paths: single-flight refresh, transient-error handling and guest continuity.
## Uses its own save file so a developer's progress is never touched.

var failures := 0
var checks := 0
var Game: Node
var Net: Node


func check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("ok   ", msg)
	else:
		failures += 1
		printerr("FAIL ", msg)


class FakeServer:
	extends RefCounted
	signal release
	var tree: SceneTree
	var player := "player-A"
	var live := {}          # refresh token -> player
	var used := {}          # rotated tokens
	var n := 0
	var refresh_calls := 0
	var guest_calls := 0
	var api_calls := 0
	var hold := false       # stall every response until release is emitted
	var script_refresh: Array = []  # queued forced outcomes for /auth/refresh: "429", "500", "drop", "lose", "401"
	var offline := false
	var grace := true       # mirror of the API's lost-response recovery

	func issue(p: String) -> Dictionary:
		n += 1
		var t := "rt-%d" % n
		live[t] = p
		return {"accessToken": "at-%d" % n, "accessTokenExpiresIn": 900, "refreshToken": t}

	func handle(method: int, path: String, body: Variant, headers: Dictionary) -> Dictionary:
		if hold:
			await release
		else:
			await tree.process_frame
		if offline:
			return {"result": 1}
		if path == "/api/v1/auth/refresh":
			refresh_calls += 1
			var forced: String = script_refresh.pop_front() if not script_refresh.is_empty() else ""
			match forced:
				"429":
					return {"result": 0, "code": 429, "body": {"error": {"code": "rate_limited"}}}
				"500":
					return {"result": 0, "code": 503, "body": null}
				"drop":
					return {"result": 1}
				"401":
					return {"result": 0, "code": 401, "body": {"error": {"code": "refresh_token_reused"}}}
			var t := str(body["refreshToken"])
			if used.has(t):
				if grace and used[t] == "lost":
					used[t] = "recovered"
					return {"result": 0, "code": 200, "body": issue(player)}
				return {"result": 0, "code": 401, "body": {"error": {"code": "refresh_token_reused"}}}
			if not live.has(t):
				return {"result": 0, "code": 401, "body": {"error": {"code": "invalid_refresh_token"}}}
			live.erase(t)
			used[t] = "ok"
			var out := issue(player)
			if forced == "lose":
				used[t] = "lost"  # rotated on the server, response never arrives
				return {"result": 1}
			return {"result": 0, "code": 200, "body": out}
		if path == "/api/v1/auth/guest":
			guest_calls += 1
			player = "player-G%d" % guest_calls
			var g := issue(player)
			g["player"] = {"id": player, "displayName": "Guest %d" % guest_calls}
			return {"result": 0, "code": 201, "body": g}
		api_calls += 1
		var auth := str(headers.get("Authorization", ""))
		if not auth.begins_with("Bearer at-"):
			return {"result": 0, "code": 401, "body": null}
		return {"result": 0, "code": 200, "body": {"ok": true}}


func _initialize() -> void:
	_run.call_deferred()


func _fresh(server: FakeServer, linked := false) -> void:
	Game.state.data = load("res://scripts/core/game_state.gd").defaults()
	Game.state.data["settings"]["analyticsAsked"] = true
	var t := server.issue("player-A")
	Game.state.data["auth"] = {"playerId": "player-A", "refreshToken": t["refreshToken"], "displayName": "Ada", "linked": linked}
	Net._access_token = ""
	Net._access_exp = 0
	Net.base_url = "http://fake.invalid"
	Net.transport = server.handle


func _expire() -> void:
	Net._access_token = ""
	Net._access_exp = 0


func _calls(k: int) -> Array:
	var out: Array = []
	var done := [0]
	for i in k:
		var f := func():
			var r: Dictionary = await Net.call_api(HTTPClient.METHOD_GET, "/api/v1/player/me")
			out.append(r)
			done[0] += 1
		f.call()
	return [out, done]


func _until(cond: Callable, frames := 600) -> void:
	for i in frames:
		if cond.call():
			return
		await process_frame


func _run() -> void:
	Game = root.get_node("Game")
	Net = root.get_node("Net")
	Game.store = load("res://scripts/core/save_store.gd").new("user://auth-test-save.json")
	await process_frame
	var S := FakeServer

	# 1. Two simultaneous requests with an expired access token share ONE refresh.
	var srv: FakeServer = S.new()
	srv.tree = self
	_fresh(srv)
	srv.hold = true
	var c: Array = _calls(2)
	await process_frame
	srv.hold = false
	for i in 10:
		srv.release.emit()
		await process_frame
	await _until(func(): return c[1][0] == 2)
	check(srv.refresh_calls == 1, "two concurrent calls -> one refresh (got %d)" % srv.refresh_calls)
	check(c[0].all(func(r): return r["ok"]), "both concurrent calls succeed")
	check(Game.state.data["auth"]["playerId"] == "player-A", "identity kept")

	# 2. Five concurrent calls.
	srv = S.new()
	srv.tree = self
	_fresh(srv)
	c = _calls(5)
	await _until(func(): return c[1][0] == 5)
	check(srv.refresh_calls == 1, "five concurrent calls -> one refresh (got %d)" % srv.refresh_calls)
	check(c[0].all(func(r): return r["ok"]), "all five succeed")
	check(srv.guest_calls == 0, "no guest created")

	# 3. Temporary 429 then success: bounded retry, same identity.
	srv = S.new()
	srv.tree = self
	_fresh(srv)
	srv.script_refresh = ["429"]
	var r: Dictionary = await Net.call_api(HTTPClient.METHOD_GET, "/api/v1/player/me")
	check(r["ok"], "429 on refresh is retried and succeeds")
	check(srv.refresh_calls == 2 and srv.guest_calls == 0, "one retry, no guest (refresh %d guest %d)" % [srv.refresh_calls, srv.guest_calls])
	check(Game.state.data["auth"]["playerId"] == "player-A", "429: identity kept")

	# 4. Persistent 5xx: gives up after bounded retries, keeps the refresh token and identity.
	srv = S.new()
	srv.tree = self
	_fresh(srv)
	var token_before: String = Game.state.data["auth"]["refreshToken"]
	srv.script_refresh = ["500", "500", "500", "500"]
	r = await Net.call_api(HTTPClient.METHOD_GET, "/api/v1/player/me")
	check(not r["ok"], "5xx: call fails")
	check(srv.refresh_calls == Net.AUTH_RETRIES + 1, "5xx: bounded retries (%d)" % srv.refresh_calls)
	check(srv.guest_calls == 0, "5xx: no replacement guest")
	check(Game.state.data["auth"]["refreshToken"] == token_before and Game.state.data["auth"]["playerId"] == "player-A", "5xx: credentials untouched")
	check(Net.last_auth_error == "transient", "5xx classified transient")
	r = await Net.call_api(HTTPClient.METHOD_GET, "/api/v1/player/me")
	check(r["ok"] and Game.state.data["auth"]["playerId"] == "player-A", "5xx: next attempt recovers same player")

	# 5. Offline then reconnect.
	srv = S.new()
	srv.tree = self
	_fresh(srv)
	srv.offline = true
	r = await Net.call_api(HTTPClient.METHOD_GET, "/api/v1/player/me")
	check(not r["ok"] and srv.guest_calls == 0, "offline: no guest created")
	check(Net.last_auth_error == "offline" and not Net.online, "offline classified")
	srv.offline = false
	r = await Net.call_api(HTTPClient.METHOD_GET, "/api/v1/player/me")
	check(r["ok"] and Game.state.data["auth"]["playerId"] == "player-A", "reconnect: same player")

	# 6. Refresh response lost after the server rotated: the retry recovers the same identity.
	srv = S.new()
	srv.tree = self
	_fresh(srv)
	srv.script_refresh = ["lose"]
	r = await Net.call_api(HTTPClient.METHOD_GET, "/api/v1/player/me")
	check(not r["ok"], "lost response: first call fails (offline)")
	r = await Net.call_api(HTTPClient.METHOD_GET, "/api/v1/player/me")
	check(r["ok"], "lost response: retry succeeds")
	check(srv.guest_calls == 0 and Game.state.data["auth"]["playerId"] == "player-A", "lost response: identity kept")

	# 7. Restart: a successful refresh is on disk immediately (no deferred save to lose).
	srv = S.new()
	srv.tree = self
	_fresh(srv)
	_expire()
	r = await Net.call_api(HTTPClient.METHOD_GET, "/api/v1/player/me")
	var on_disk: Dictionary = Game.store.load_data()
	check(on_disk.get("auth", {}).get("refreshToken", "") == Game.state.data["auth"]["refreshToken"], "rotated refresh token persisted before use")
	# ...and a restart in the middle of a refresh (token on disk is the pre-refresh one) recovers.
	srv.hold = true
	var pre: String = Game.state.data["auth"]["refreshToken"]
	_expire()
	srv.script_refresh = ["lose"]
	c = _calls(1)
	srv.hold = false
	srv.release.emit()
	await _until(func(): return c[1][0] == 1)
	Game.state.data["auth"]["refreshToken"] = pre  # what a restarted app would read
	_expire()
	r = await Net.call_api(HTTPClient.METHOD_GET, "/api/v1/player/me")
	check(r["ok"] and Game.state.data["auth"]["playerId"] == "player-A", "restart during refresh: same player")

	# 8. Revoked credentials (unlinked guest): a new guest, old id remembered, progress replayed.
	srv = S.new()
	srv.tree = self
	_fresh(srv)
	var st = Game.state
	st.start_level("campaign", st.campaign[0])
	for mv in st.campaign[0]["solution"]["moves"]:
		st.rotate(int(mv[0]), int(mv[1]))
	st.complete_active()
	st.data["syncQueue"].clear()
	srv.script_refresh = ["401"]
	r = await Net.call_api(HTTPClient.METHOD_GET, "/api/v1/player/me")
	check(r["ok"] and srv.guest_calls == 1, "revoked: replaced by a new guest")
	check(Game.state.data["auth"]["previousPlayerIds"] == ["player-A"], "revoked: previous id kept for support")
	check(st.data["syncQueue"].any(func(o): return o["type"] == "level_complete"), "revoked: local progress re-queued for the new account")
	check(st.campaign_completed(0), "revoked: local progress intact")

	# 9. Revoked credentials on a LINKED account: never silently swapped for a guest.
	srv = S.new()
	srv.tree = self
	_fresh(srv, true)
	srv.script_refresh = ["401"]
	r = await Net.call_api(HTTPClient.METHOD_GET, "/api/v1/player/me")
	check(not r["ok"] and srv.guest_calls == 0, "linked + revoked: no guest")
	check(Net.last_auth_error == "revoked", "linked + revoked: reported for a sign-in prompt")

	# 10. Offline campaign play while authentication is unavailable.
	srv = S.new()
	srv.tree = self
	_fresh(srv)
	srv.offline = true
	await Net.sync()
	st = Game.state
	st.start_level("campaign", st.campaign[1])
	for mv in st.campaign[1]["solution"]["moves"]:
		st.rotate(int(mv[0]), int(mv[1]))
	var res: Dictionary = Game.complete_active()
	check(not res.is_empty() and st.campaign_completed(1), "offline: level completes without auth")
	await Net.sync()
	check(st.data["syncQueue"].size() >= 1 and st.data["auth"]["playerId"] == "player-A", "offline: completion queued, identity kept")
	srv.offline = false
	for op in st.data["syncQueue"]:
		op["nextAttemptAt"] = 0
	await Net.sync()
	check(srv.guest_calls == 0, "back online: still no replacement guest")

	Net.transport = Callable()
	print("\nAuth tests: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
