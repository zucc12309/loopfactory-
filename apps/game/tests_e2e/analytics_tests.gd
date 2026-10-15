extends SceneTree
## Consent-aware analytics, diagnostics and local deletion (audit R7, R8, L1, R1), headless:
##   godot --headless --path apps/game -s res://tests_e2e/analytics_tests.gd
## A fake provider (Analytics.send_transport) records every batch; no network is used.

var failures := 0
var checks := 0
var Game: Node
var Analytics: Node
var sent: Array = []        # every accepted batch's events
var accept := true          # fake provider up/down


func check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("ok   ", msg)
	else:
		failures += 1
		printerr("FAIL ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _provider(body: Dictionary) -> bool:
	await process_frame
	if not accept:
		return false
	for e in body["batch"]:
		sent.append(e)
	return true


func _fresh() -> void:
	Game.state.data = load("res://scripts/core/game_state.gd").defaults()
	Game.state.data["stats"]["sessions"] = 1
	Analytics.clear()
	sent.clear()
	accept = true


func _events() -> Array:
	return sent.map(func(e): return e["event"])


func _queued() -> Array:
	return Analytics.queued().map(func(e): return e["event"])


func _flush() -> void:
	await Analytics.flush()
	await process_frame


func _grant(v: bool) -> void:
	Game.set_setting("analyticsAsked", true)
	Game.set_setting("analytics", v)


func _run() -> void:
	Game = root.get_node("Game")
	Analytics = root.get_node("Analytics")
	Game.store = load("res://scripts/core/save_store.gd").new("user://analytics-test-save.json")
	Analytics.queue_path = "user://analytics-test-queue.json"
	var Diag: GDScript = load("res://scripts/core/diagnostics.gd")
	Diag.use_path("user://diagnostics-test.json")
	Analytics.send_transport = _provider
	await process_frame

	# 1. Fresh install, no consent: nothing queued, stored or sent.
	_fresh()
	Analytics.boot()
	Analytics.once("first_rotation")
	Analytics.track("level_complete", {"level_id": "c01"})
	await _flush()
	check(Analytics.queued().is_empty() and sent.is_empty(), "no consent: nothing queued or sent")
	check(not FileAccess.file_exists(Analytics.queue_path), "no consent: nothing written to disk")

	# 2. Consent accepted after the first win: no backfill, cohort anchor + session start.
	Analytics.once("first_delivery")
	_grant(true)
	var q := _queued()
	check(q.has("consent_granted") and q.has("session_start"), "consent: consent_granted + session_start queued (%s)" % [q])
	check(not q.has("first_rotation") and not q.has("first_delivery") and not q.has("level_complete"), "consent: earlier events not backfilled")
	var anchor: Dictionary = Analytics.queued().filter(func(e): return e["event"] == "consent_granted")[0]
	check(anchor["properties"].has("levels_completed") and anchor["properties"]["schema"] == Analytics.SCHEMA_VERSION, "anchor carries cohort context + schema version")
	for k in ["app_version", "build", "environment", "platform", "device_class", "session_id"]:
		check(anchor["properties"].has(k), "common property " + k)
	for k in ["playerId", "refreshToken", "displayName", "player_id"]:
		check(not anchor["properties"].has(k), "no identifier " + k)
	Analytics.once("first_delivery")
	check(not _queued().has("first_delivery"), "one-time event already passed before consent stays unsent")
	await _flush()
	check(_events().has("consent_granted") and Analytics.queued().is_empty(), "flushed to provider")

	# 3. Consent declined: nothing ever.
	_fresh()
	_grant(false)
	Analytics.track("level_start", {})
	await _flush()
	check(sent.is_empty() and Analytics.queued().is_empty(), "declined: nothing sent")

	# 4. Offline acceptance and reconnect: kept, persisted, sent once, uuids unique.
	_fresh()
	accept = false
	_grant(true)
	Analytics.track("level_start", {"level_id": "c02"})
	await _flush()
	check(sent.is_empty() and Analytics.queued().size() >= 3, "offline: events kept (%d)" % Analytics.queued().size())
	check(FileAccess.file_exists(Analytics.queue_path), "offline: queue persisted (consented)")
	var uuids: Array = Analytics.queued().map(func(e): return e["uuid"])
	accept = true
	await _flush()
	var sent_uuids: Array = sent.map(func(e): return e["uuid"])
	check(sent_uuids == uuids, "reconnect: same events with the same uuids (provider can dedupe a lost-response retry)")
	var uniq := {}
	for u in sent_uuids:
		uniq[u] = true
	check(uniq.size() == sent_uuids.size(), "uuids unique")
	await _flush()
	check(sent.size() == sent_uuids.size(), "no duplicate send after a second flush")

	# 5. Restart: persisted queue reloaded; a quick relaunch continues the session (no new session_start).
	_fresh()
	_grant(true)
	accept = false
	Analytics.track("level_start", {"level_id": "c03"})
	Analytics._persist()
	var before: int = Analytics.queued().size()
	var sid: String = Game.state.data["analyticsSession"]["id"]
	Analytics.boot()  # simulated cold start
	check(Analytics.queued().size() >= before, "restart: queued events survive (%d -> %d)" % [before, Analytics.queued().size()])
	var after: Array = _queued().slice(before)
	check(after.has("app_resume") and not after.has("session_start"), "restart within 30 min: continues the session (%s)" % [after])
	check(Game.state.data["analyticsSession"]["id"] == sid, "same session id")
	Game.state.data["analyticsSession"]["lastActiveMs"] = 0
	var n: int = Analytics.queued().size()
	Analytics.boot()
	check(_queued().slice(n).has("session_start"), "restart after the gap: new session")

	# 6. Background / resume.
	_fresh()
	_grant(true)
	Analytics._notification(NOTIFICATION_APPLICATION_PAUSED)
	Analytics._notification(NOTIFICATION_APPLICATION_RESUMED)
	var lc := _queued()
	check(lc.has("app_background") and lc.has("app_resume"), "background + resume tracked")
	check(bool(Game.state.data["sessionGuard"]["open"]), "session guard reopened on resume")
	for k in 3:
		await process_frame  # let the flush started by backgrounding finish

	# 7. Revocation clears the queue and the stored file; nothing afterwards.
	accept = false
	Analytics.track("level_start", {})
	Analytics._persist()
	_grant(false)
	check(Analytics.queued().is_empty() and not FileAccess.file_exists(Analytics.queue_path), "revoked: queue and file erased")
	accept = true
	sent.clear()
	Analytics.track("level_start", {})
	await _flush()
	check(sent.is_empty(), "revoked: nothing sent")

	# 8. Duplicate prevention for one-time events, across restarts.
	_fresh()
	_grant(true)
	for k in 3:
		Analytics.once("first_run")
		await process_frame  # the queue reaches disk within a frame
		Analytics.boot()
	check(_queued().count("first_run") == 1, "first_run recorded once across restarts")
	check(_queued().count("consent_granted") == 1, "consent_granted once")
	Game.set_setting("analytics", false)
	check(Analytics.queued().is_empty(), "revoking clears the queue")
	Game.set_setting("analytics", true)
	check(_queued().count("consent_granted") == 0 and _queued().has("session_start"), "re-granting starts a session but doesn't re-anchor the cohort")

	# 9. Diagnostics: scrubbed, local ring buffer, sent only with consent.
	_fresh()
	Diag.clear()
	var e: Dictionary = Diag.record("diagnostic_test", false, {"refreshToken": "rt-123", "url": "https://x.y/c/ABCD2345", "note": "see https://x.y", "code": "ABCD2345", "count": 3})
	check(not e["detail"].has("refreshToken") and not e["detail"].has("url") and not e["detail"].has("code"), "diagnostics drop tokens, links and codes")
	check(e["detail"]["note"] == "[redacted]" and e["detail"]["count"] == 3, "diagnostics redact URLs in text, keep scalars")
	check(e["recoverable"] and not e["fatal"] and e.has("app_version") and e.has("environment"), "diagnostics carry build context + recoverable flag")
	check(Analytics.queued().is_empty(), "diagnostic not sent without consent")
	_grant(true)
	Diag.record("unclean_exit", true)
	var ae: Array = Analytics.queued().filter(func(x): return x["event"] == "app_error")
	check(ae.size() == 1 and ae[0]["properties"]["fatal"], "fatal diagnostic sent as app_error with consent")
	Diag.record("network", false, {"status": 0})
	Diag.record("network", false, {"status": 0})
	check(Analytics.queued().filter(func(x): return x["event"] == "network_error").size() == 1, "network errors recorded once per session")
	check(Diag.read_all().size() == 3, "kept locally")
	check(Diag.monitoring_status({"environment": "staging", "crashReporting": {"provider": "none"}}) == "misconfigured", "staging without monitoring is flagged")
	check(Diag.monitoring_status({"environment": "production", "crashReporting": {"provider": "sentry", "dsn": "x"}}) == "unsupported", "a provider without an SDK is not claimed")
	check(Diag.monitoring_status({"environment": "development", "crashReporting": {"provider": "local"}}) == "ok", "local boundary ok")

	# 10. Release config rules (same cases as scripts/client-config.ts).
	var RC: GDScript = load("res://scripts/core/release_config.gd")
	var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/config-cases.json"))
	for c in fx["cases"]:
		var errs: Array = RC.validate(c["config"])
		check(errs.is_empty() == bool(c["valid"]), "config: %s %s" % [c["name"], "" if errs.is_empty() == bool(c["valid"]) else str(errs)])
	check(RC.validate(RC.load_client()).is_empty(), "packaged development config is valid")

	# 11. Complete local deletion removes every residual file; ordinary saves keep backups.
	_fresh()
	_grant(true)
	Game.save_now()
	Game.save_now()
	check(FileAccess.file_exists(Game.store.path + ".bak"), "ordinary saves keep a backup")
	var f := FileAccess.open(Game.store.path + ".corrupt", FileAccess.WRITE)
	f.store_string("{bad")
	f.close()
	DirAccess.make_dir_recursive_absolute("user://share")
	f = FileAccess.open("user://share/test-card.png", FileAccess.WRITE)
	f.store_string("png")
	f.close()
	f = FileAccess.open("user://loop-factory-export.json", FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	Diag.record("diagnostic_test")
	Analytics.track("level_start", {})
	Analytics._persist()
	check(Game.residual_files().size() >= 6, "residual files present before deletion (%s)" % [Game.residual_files()])
	Game.wipe_local()
	var left: Array = Game.residual_files().filter(func(p): return p != Game.store.path)
	check(left.is_empty(), "complete deletion leaves nothing but the fresh empty save (%s)" % [left])
	check(Game.state.data["progress"].is_empty() and Game.state.data["auth"]["playerId"] == "", "state reset")
	check(not bool(Game.settings()["analytics"]), "consent reset with the data")

	Analytics.send_transport = Callable()
	Game.wipe_local()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.store.path))
	print("\nAnalytics tests: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
