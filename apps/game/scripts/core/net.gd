extends Node
## Autoload "Net": REST client, guest authentication and the offline-first sync loop.
## The game never waits on the network: every call is best-effort and failures simply leave
## operations queued (with exponential backoff) until connectivity returns.

signal online_changed(online: bool)
signal synced
signal daily_loaded(date: String)

const TIMEOUT := 10.0
const SYNC_INTERVAL := 60.0

var base_url := ""
var online := false
var _access_token := ""
var _access_exp := 0
var _syncing := false
var _cfg := {}
## Test seam: when set, called as transport.call(method, path, body, headers) instead of HTTP and must
## return (or resolve to) {result, code, body}. Never set in the shipped game.
var transport := Callable()
## Single-flight refresh: concurrent callers share one in-flight authentication.
var _auth_inflight := false
var _auth_result := false
var last_auth_error := ""  # "", "offline", "transient", "revoked", "guest_failed"
signal _auth_done(ok: bool)

const AUTH_RETRIES := 2


static func client_config() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://config/client.json"))
	return parsed if parsed is Dictionary else {}


func _ready() -> void:
	_cfg = client_config()
	base_url = str(_cfg.get("apiBaseUrl", "")).trim_suffix("/")
	var t := Timer.new()
	t.wait_time = SYNC_INTERVAL
	t.autostart = true
	t.timeout.connect(sync)
	add_child(t)
	if Game.state != null:
		Game.state_changed.connect(_on_state_changed)
	call_deferred("_startup")


func _startup() -> void:
	await fetch_config()
	await sync()


var _sync_soon := false


func _on_state_changed() -> void:
	# Debounced sync shortly after local changes.
	if _sync_soon or Game.state.data["syncQueue"].is_empty():
		return
	_sync_soon = true
	await get_tree().create_timer(3.0).timeout
	_sync_soon = false
	sync()


func enabled() -> bool:
	return base_url != "" and bool(Game.settings().get("cloudSync", true))


func _set_online(v: bool) -> void:
	if v != online:
		online = v
		online_changed.emit(v)


## Low-level request. Returns {ok, code, body}. Never throws; code 0 means network failure.
func call_api(method: int, path: String, body: Variant = null, auth := true) -> Dictionary:
	if base_url == "":
		return {"ok": false, "code": 0, "body": null}
	if auth:
		var ok := await _ensure_token()
		if not ok:
			return {"ok": false, "code": 401, "body": null}
	var res := await _raw(method, path, body, auth)
	if auth and res["code"] == 401:
		_access_token = ""
		if await _ensure_token():
			res = await _raw(method, path, body, auth)
	return res


func _raw(method: int, path: String, body: Variant, auth: bool) -> Dictionary:
	if transport.is_valid():
		var hdrs := {"Authorization": "Bearer " + _access_token} if auth and _access_token != "" else {}
		var t: Dictionary = await transport.call(method, path, body, hdrs)
		if int(t.get("result", 0)) != 0:
			_set_online(false)
			return {"ok": false, "code": 0, "body": null}
		_set_online(true)
		var c := int(t.get("code", 0))
		return {"ok": c >= 200 and c < 300, "code": c, "body": t.get("body")}
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json", "X-Client-Version: " + str(ProjectSettings.get_setting("application/config/version", "0"))])
	if auth and _access_token != "":
		headers.append("Authorization: Bearer " + _access_token)
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(base_url + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		_set_online(false)
		return {"ok": false, "code": 0, "body": null}
	var r: Array = await http.request_completed
	http.queue_free()
	var result: int = r[0]
	var code: int = r[1]
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_online(false)
		return {"ok": false, "code": 0, "body": null}
	_set_online(true)
	var text: String = r[3].get_string_from_utf8()
	var parsed = JSON.parse_string(text) if text != "" else null
	return {"ok": code >= 200 and code < 300, "code": code, "body": parsed}


## True when a valid access token is available. Concurrent callers share one refresh (single
## flight), so a rotated refresh token is never presented twice by this client.
func _ensure_token() -> bool:
	var now := int(Time.get_unix_time_from_system())
	if _access_token != "" and now < _access_exp - 30:
		return true
	if _auth_inflight:
		return await _auth_done
	_auth_inflight = true
	var ok := await _authenticate()
	_auth_inflight = false
	_auth_result = ok
	_auth_done.emit(ok)
	return ok


static func is_transient(code: int) -> bool:
	return code == 0 or code == 408 or code == 429 or code >= 500


## Refresh, or create a guest only when there is no usable identity. Temporary failures (offline,
## timeout, 429, 5xx) NEVER replace the stored guest: the refresh token is kept and the game simply
## stays offline until the next attempt.
func _authenticate() -> bool:
	var auth: Dictionary = Game.state.data["auth"]
	last_auth_error = ""
	if str(auth.get("refreshToken", "")) != "":
		var r := {}
		for attempt in AUTH_RETRIES + 1:
			var sent := str(auth["refreshToken"])
			r = await _raw(HTTPClient.METHOD_POST, "/api/v1/auth/refresh", {"refreshToken": sent}, false)
			if r["ok"]:
				# Persist the successor before anything else can fail: losing it would strand the identity.
				_store_tokens(r["body"], true)
				return true
			if r["code"] == 0:
				last_auth_error = "offline"
				return false
			if not is_transient(r["code"]):
				break
			last_auth_error = "transient"
			if attempt < AUTH_RETRIES:
				await _backoff(attempt)
		if is_transient(r["code"]):
			return false
		# A definitive 4xx: the refresh token is expired, revoked or unknown.
		last_auth_error = "revoked"
		if auth.get("linked", false):
			# A linked account is recoverable by signing in again; never silently swap it for a guest.
			return false
		var lost_id := str(auth.get("playerId", ""))
		auth["refreshToken"] = ""
		if lost_id != "":
			auth["previousPlayerIds"] = (auth.get("previousPlayerIds", []) as Array) + [lost_id]
		Game.save_now()
	var g := await _raw(HTTPClient.METHOD_POST, "/api/v1/auth/guest", {"platform": OS.get_name()}, false)
	if not g["ok"]:
		if last_auth_error == "":
			last_auth_error = "offline" if g["code"] == 0 else "guest_failed"
		return false
	auth["playerId"] = g["body"]["player"]["id"]
	auth["displayName"] = g["body"]["player"]["displayName"]
	_store_tokens(g["body"], true)
	Analytics.track("guest_identity_created", {"replaced": last_auth_error == "revoked"})
	# A fresh server account: replay everything we know so it catches up.
	_requeue_all_progress()
	return true


## Bounded exponential backoff with full jitter (0.4–1.2 s, then 0.8–2.4 s).
func _backoff(attempt: int) -> void:
	if transport.is_valid():
		return
	var base := 0.4 * pow(2.0, attempt)
	await get_tree().create_timer(base + randf() * base * 2.0).timeout


func _store_tokens(b: Dictionary, durable := false) -> void:
	_access_token = str(b["accessToken"])
	_access_exp = int(b.get("accessTokenExpiresIn", 900)) + int(Time.get_unix_time_from_system())
	if b.has("refreshToken"):
		Game.state.data["auth"]["refreshToken"] = str(b["refreshToken"])
	if durable:
		Game.save_now()
	else:
		Game.request_save()


func _requeue_all_progress() -> void:
	# Replays the local campaign progress to a new/restored server account. Levels with a stored best
	# replay are re-sent WITH their moves, so the server re-simulates them and they stay verified
	# (ranked); only legacy entries without a replay go up unverified (kept, not ranked). Levels with a
	# completion still queued are skipped — that op will deliver the result.
	var pending := {}
	for op in Game.state.data["syncQueue"]:
		if op["type"] == "level_complete":
			pending[str(op["payload"]["levelId"])] = true
	for key in Game.state.data["progress"]:
		if pending.has(key):
			continue
		var p: Dictionary = Game.state.data["progress"][key]
		var kind := str(p.get("kind", "campaign"))
		if kind != "campaign":
			continue
		var rep = p.get("replay")
		var moves = null
		var version := 1
		if rep is Dictionary and rep.get("moves") is Array:
			moves = (rep["moves"] as Array).duplicate(true)
			version = int(rep.get("contentVersion", 1))
		Game.state.enqueue("level_complete", {"kind": kind, "levelId": key, "contentVersion": version, "moves": moves, "rotations": p["best"] if moves == null else (moves as Array).size(), "hints": 0, "completedAt": p.get("completedAt", 0)})


## Upload queued operations, then merge the server snapshot. Safe to call any time.
func sync() -> void:
	if _syncing or not enabled():
		return
	_syncing = true
	var now := LFGameState.now_ms()
	var due := Game.state.due_ops(now)
	var batch: Array = []
	for op in due:
		if op["type"] == "daily_submit":
			var r := await call_api(HTTPClient.METHOD_POST, "/api/v1/challenges/daily/submit", op["payload"])
			if r["ok"] or (r["code"] >= 400 and r["code"] < 500 and r["code"] != 401 and r["code"] != 429):
				# Accepted, or permanently rejected (e.g. too late) — either way stop retrying.
				Game.state.ack_ops([op["opId"]])
				var date: String = op["payload"]["date"]
				if r["ok"] and Game.state.data["daily"]["results"].has(date):
					Game.state.data["daily"]["results"][date]["submitted"] = true
			else:
				Game.state.retry_later([op["opId"]], now)
		else:
			batch.append({"opId": op["opId"], "type": op["type"], "payload": op["payload"], "clientTs": op["clientTs"]})
	var r2 := await call_api(HTTPClient.METHOD_POST, "/api/v1/progress/sync", {"operations": batch})
	if r2["ok"]:
		var acked: Array = []
		for res in r2["body"].get("results", []):
			acked.append(res["opId"])
		Game.state.ack_ops(acked)
		Game.state.merge_remote(r2["body"].get("snapshot", {}))
		synced.emit()
	elif not batch.is_empty():
		Game.state.retry_later(batch.map(func(o): return o["opId"]), now)
		LFDiagnostics.record("network", false, {"status": int(r2["code"]), "queued": batch.size(), "reason": last_auth_error})
	Game.request_save()
	_syncing = false


func fetch_config() -> void:
	if base_url == "":
		return
	var r := await call_api(HTTPClient.METHOD_GET, "/api/v1/config", null, false)
	if r["ok"] and r["body"] is Dictionary:
		Game.state.data["remoteConfig"] = r["body"].get("config", {})
		Game.request_save()


## Fetch and cache the official daily puzzle. Returns the cached entry or null.
func fetch_daily(date: String) -> Variant:
	var cache: Dictionary = Game.state.data["daily"]["cache"]
	if cache.has(date):
		return cache[date]
	if base_url == "":
		return null
	var r := await call_api(HTTPClient.METHOD_GET, "/api/v1/challenges/daily?date=" + date, null, false)
	if r["ok"] and r["body"] is Dictionary:
		var lvl := LFTiles.normalize_level(r["body"]["level"])
		if LFTiles.validate_board(lvl) == "":
			lvl["date"] = date
			cache[date] = {"level": lvl, "tier": r["body"].get("tier", ""), "date": date}
			# Keep the cache small.
			var keys := cache.keys()
			keys.sort()
			while keys.size() > 7:
				cache.erase(keys.pop_front())
			Game.request_save()
			daily_loaded.emit(date)
			return cache[date]
	return null


func daily_leaderboard(date: String) -> Variant:
	var r := await call_api(HTTPClient.METHOD_GET, "/api/v1/challenges/daily/leaderboard?date=%s&limit=20" % date)
	return r["body"] if r["ok"] else null


func global_leaderboard(kind: String) -> Variant:
	var r := await call_api(HTTPClient.METHOD_GET, "/api/v1/leaderboards/%s?limit=20" % kind)
	return r["body"] if r["ok"] else null


func update_display_name(name: String) -> bool:
	var r := await call_api(HTTPClient.METHOD_PATCH, "/api/v1/player/me", {"displayName": name})
	if r["ok"]:
		Game.state.data["auth"]["displayName"] = r["body"]["displayName"]
		Game.request_save()
	return r["ok"]


## Account recovery boundary (audit R5). Links a verified third-party identity (an ID token from a
## platform sign-in plugin) to this guest, or switches to the account that already owns it (restore
## after reinstall). No sign-in plugin ships yet, so the UI never calls this; it is exercised by the
## e2e suite with the server's dev provider. Merge rules (docs/BETA_READINESS_IMPLEMENTATION.md):
##  * linked:   nothing moves; the guest simply becomes recoverable.
##  * switched: the device adopts the restored account. Local completions are replayed to it (the
##              server keeps the minimum, so nothing regresses), looks re-derive from progress, the
##              old guest id is remembered for support.
## Returns {ok, mode, error}.
func link_identity(provider: String, id_token: String, allow_switch := false) -> Dictionary:
	var body := {"provider": provider, "idToken": id_token}
	if allow_switch:
		body["onConflict"] = "switch"
	var r := await call_api(HTTPClient.METHOD_POST, "/api/v1/auth/link", body)
	if not r["ok"]:
		var code := ""
		if r["body"] is Dictionary and r["body"].get("error") is Dictionary:
			code = str(r["body"]["error"].get("code", ""))
		return {"ok": false, "mode": "", "error": code if code != "" else ("offline" if r["code"] == 0 else str(r["code"]))}
	var auth: Dictionary = Game.state.data["auth"]
	var mode := str(r["body"].get("mode", ""))
	auth["linked"] = true
	auth["linkedProvider"] = provider
	if mode == "switched":
		var old := str(auth.get("playerId", ""))
		if old != "":
			auth["previousPlayerIds"] = (auth.get("previousPlayerIds", []) as Array) + [old]
		auth["playerId"] = r["body"]["player"]["id"]
		auth["displayName"] = r["body"]["player"]["displayName"]
		_store_tokens(r["body"]["tokens"], true)
		_requeue_all_progress()
		await sync()
	Game.save_now()
	return {"ok": true, "mode": mode, "error": ""}


func export_data() -> Variant:
	var r := await call_api(HTTPClient.METHOD_GET, "/api/v1/privacy/export")
	return r["body"] if r["ok"] else null


## Deletes the server account (if any) then local data. Returns false if the server call failed.
func delete_account() -> bool:
	if Game.state.data["auth"].get("refreshToken", "") != "":
		var r := await call_api(HTTPClient.METHOD_POST, "/api/v1/privacy/delete-request", {"confirm": true})
		if not r["ok"]:
			return false
	_access_token = ""
	Analytics.clear()
	Game.wipe_local()
	return true


# ---------------------------------------------------------------- friend challenges

## How the server can rebuild the exact puzzle: campaign id, daily date, or generator parameters.
static func level_ref(kind: String, level: Dictionary) -> Variant:
	match kind:
		"campaign":
			return {"type": "campaign", "levelId": str(level["id"])}
		"daily":
			return {"type": "daily", "date": str(level.get("date", ""))}
		_:
			var g = level.get("generator")
			if g is Dictionary:
				return {"type": "generated", "seed": int(g["seed"]), "tier": str(g["tier"]), "version": str(g["version"])}
	return null


## Create a challenge from a verified solve. Returns {code, url, rotations} or null.
func create_challenge(kind: String, level: Dictionary, moves: Array) -> Variant:
	var ref = level_ref(kind, level)
	if ref == null:
		return null
	var r := await call_api(HTTPClient.METHOD_POST, "/api/v1/challenges/friend", {"level": ref, "moves": moves})
	return r["body"] if r["ok"] and r["body"] is Dictionary else null


## Fetch a challenge by code. Returns {code, level, creatorName, creatorRotations, attempts} or
## null. The response never contains the creator's moves.
func get_challenge(code: String) -> Variant:
	var r := await get_challenge_result(code)
	return r["body"] if r["status"] == "ok" else null


## Like get_challenge, but says why it failed: {status: ok | invalid | not_found | offline | error, body}.
## "not_found" covers unknown and expired codes (the server doesn't distinguish them).
func get_challenge_result(code: String) -> Dictionary:
	var clean := code.strip_edges().to_upper().replace(" ", "").replace("-", "")
	if not LFShare.valid_code(clean):
		return {"status": "invalid", "body": null}
	if base_url == "":
		return {"status": "offline", "body": null}
	var r := await call_api(HTTPClient.METHOD_GET, "/api/v1/challenges/friend/" + clean.uri_encode(), null, false)
	if r["code"] == 0:
		return {"status": "offline", "body": null}
	if r["code"] == 404 or r["code"] == 400:
		return {"status": "not_found", "body": null}
	if r["ok"] and r["body"] is Dictionary:
		var lvl := LFTiles.normalize_level(r["body"]["level"])
		if LFTiles.validate_board(lvl) == "":
			r["body"]["level"] = lvl
			return {"status": "ok", "body": r["body"]}
	return {"status": "error", "body": null}


## Submit an attempt; the server re-simulates it. Returns {rotations, creatorRotations, outcome} or null.
func submit_challenge_attempt(code: String, moves: Array) -> Variant:
	if code.is_empty():
		return null
	var r := await call_api(HTTPClient.METHOD_POST, "/api/v1/challenges/friend/%s/attempts" % code.uri_encode(), {"moves": moves})
	return r["body"] if r["ok"] and r["body"] is Dictionary else null
