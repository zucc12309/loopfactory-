extends Node
## Autoload "Analytics": consent-gated, privacy-conscious event tracking with pluggable providers.
## - Nothing is queued, stored or sent unless the player opted in (settings.analytics). Events that
##   happen before consent are never backfilled; consent is asked after the first delivery, so the
##   observable funnel starts at `consent_granted` (docs/analytics.md, "Consented cohorts").
## - Identity is a random analytics ID (not device IDs, not the account ID); reset on data deletion.
## - Each event carries a random `uuid`, so a batch retried after a lost response is deduplicated by
##   the provider instead of double counted.
## - The queue persists to user://analytics-queue.json ONLY while consent is on (offline sends survive
##   a restart); withdrawing consent deletes it immediately.
## - A session continues across a quick restart (process killed in the background and relaunched
##   within SESSION_GAP_MS): no duplicate session_start.
## Providers: "none" (default), "debug" (prints), "posthog" (HTTP batch API). Configure in
## res://config/client.json. See docs/analytics.md for the event taxonomy.

## Bumped when event names or properties change meaning.
const SCHEMA_VERSION := 2

## Event taxonomy (docs/analytics.md). object_action, snake_case, past tense for outcomes.
const EVENTS := [
	# lifecycle
	"app_open", "first_launch", "session_start", "session_end", "app_background", "app_resume",
	"previous_session_unclean", "guest_identity_created",
	# consent & cohort anchors
	"consent_granted",
	# onboarding & core loop
	"tutorial_start", "tutorial_complete", "first_rotation", "first_run", "first_delivery",
	"level_start", "level_complete", "level_fail", "level_retry", "hint_used", "replay_viewed",
	# daily
	"daily_challenge_entry", "daily_challenge_started", "daily_challenge_completed",
	# sharing & friend challenges (see docs/sharing.md for exactly what each one can and can't prove)
	"share_card_created", "share_image_saved", "share_text_copied", "share_sheet_opened",
	"share_sheet_closed",
	"challenge_create_clicked", "challenge_created", "challenge_link_opened", "challenge_loaded",
	"challenge_started", "challenge_completed",
	# diagnostics
	"network_error", "app_error",
	# Interdimensional Delivery Crew
	"character_exposed", "character_animation_played", "character_collection_opened",
	"cosmetic_unlocked", "cosmetic_equipped", "character_dialogue_shown", "character_dialogue_dismissed",
	# monetization (interfaces only; no store integrated)
	"purchase_started", "purchase_completed",
]
## One-time events: recorded at most once per install, and only if consent was on at that moment.
const ONCE := ["first_launch", "tutorial_start", "first_rotation", "first_run", "first_delivery", "consent_granted"]
## A new session starts if the app was in the background (or closed) longer than this.
const SESSION_GAP_MS := 30 * 60 * 1000
const MAX_QUEUE := 200
const QUEUE_PATH := "user://analytics-queue.json"

var provider := "none"
var last_event := ""
var queue_path := QUEUE_PATH
## Test seam: when valid, called as send_transport.call(batch_dict) -> bool (true = accepted).
var send_transport := Callable()
var _cfg := {}
var _client := {}
var _queue: Array = []
var _http: HTTPRequest
var _session_id := ""
var _sending := false
var _session_started_ms := 0
var _background_at_ms := 0
var _was_consented := false


func _ready() -> void:
	_client = Net.client_config()
	_cfg = _client.get("analytics", {})
	provider = str(_cfg.get("provider", "none"))
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_done)
	var t := Timer.new()
	t.wait_time = 30.0
	t.autostart = true
	t.timeout.connect(flush)
	add_child(t)
	Game.settings_changed.connect(_on_settings_changed)
	boot()


## Session bookkeeping for a (cold) start. Separate from _ready so tests can simulate a restart.
func boot() -> void:
	_queue.clear()
	_sending = false
	_background_at_ms = 0
	_was_consented = consented()
	if _was_consented:
		_load_queue()
	var sess: Dictionary = Game.state.data.get("analyticsSession", {}).duplicate()
	var guard: Dictionary = Game.state.data.get("sessionGuard", {})
	if bool(guard.get("open", false)):
		# The last session never reached background/close: the app crashed or was killed in the
		# foreground. Used as the crash-free-sessions proxy until native crash reporting exists.
		track("previous_session_unclean", {"previous_session_id": str(guard.get("id", ""))})
		LFDiagnostics.record("unclean_exit", true)
	var now := LFGameState.now_ms()
	var resumed := str(sess.get("id", "")) != "" and now - int(sess.get("lastActiveMs", 0)) < SESSION_GAP_MS
	_session_id = str(sess["id"]) if resumed else LFGameState.uuid4()
	_session_started_ms = Time.get_ticks_msec()
	Game.state.data["sessionGuard"] = {"open": true, "id": _session_id}
	_touch()
	track("app_open", {"cold_start": true})
	if int(Game.state.data["stats"].get("sessions", 0)) <= 1:
		once("first_launch")
	if resumed:
		track("app_resume", {"cold_start": true})
	else:
		track("session_start", {"trigger": "launch"})


func _touch() -> void:
	if Game.state != null:
		Game.state.data["analyticsSession"] = {"id": _session_id, "lastActiveMs": LFGameState.now_ms()}


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if _background_at_ms == 0:
				_background_at_ms = Time.get_ticks_msec()
				track("app_background", {"session_seconds": (_background_at_ms - _session_started_ms) / 1000, "screen": _screen()})
				_touch()
				_close_guard()
				flush()
				_persist()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			if _background_at_ms > 0:
				var away := Time.get_ticks_msec() - _background_at_ms
				_background_at_ms = 0
				if Game.state != null:
					Game.state.data["sessionGuard"] = {"open": true, "id": _session_id}
				if away > SESSION_GAP_MS:
					track("session_end", {"session_seconds": maxi(0, (Time.get_ticks_msec() - away - _session_started_ms) / 1000), "reason": "background_timeout"})
					_session_id = LFGameState.uuid4()
					_session_started_ms = Time.get_ticks_msec()
					track("session_start", {"trigger": "return"})
				else:
					track("app_resume", {"away_seconds": away / 1000, "cold_start": false})
				_touch()
		NOTIFICATION_WM_CLOSE_REQUEST:
			track("session_end", {"session_seconds": (Time.get_ticks_msec() - _session_started_ms) / 1000, "reason": "close"})
			_touch()
			_close_guard()
			flush()
			_persist()


func _close_guard() -> void:
	if Game.state != null:
		Game.state.data["sessionGuard"] = {"open": false, "id": _session_id}
		Game.save_now()


func _screen() -> String:
	var m := get_tree().root.get_node_or_null("Main")
	return str(m.get("current_name")) if m != null else ""


func consented() -> bool:
	return Game.state != null and bool(Game.settings().get("analytics", false))


## Consent transitions. Granting starts an observable session right away (the cohort anchor);
## withdrawing drops everything queued or stored, so nothing collected under consent is sent later.
func _on_settings_changed() -> void:
	var now := consented()
	if now == _was_consented:
		return
	_was_consented = now
	if now:
		var st: Dictionary = Game.state.data["stats"]
		once("consent_granted", {"levels_completed": Game.state.completed_count(), "sessions": int(st.get("sessions", 0)), "surface": _screen()})
		track("session_start", {"trigger": "consent"})
		_persist()
	else:
		clear()


## Track a one-time event. Marked as done even without consent, so it is never sent later (no backfill).
func once(event: String, props := {}) -> void:
	if Game.state == null:
		return
	var done: Dictionary = Game.state.data.get("analyticsOnce", {})
	if done.has(event):
		return
	done[event] = true
	Game.state.data["analyticsOnce"] = done
	track(event, props)


func track(event: String, props := {}) -> void:
	if not EVENTS.has(event):
		push_warning("Unknown analytics event " + event)
		return
	if not consented():
		return
	last_event = event
	var p := props.duplicate()
	p.merge(common_properties())
	p["session_id"] = _session_id
	var exps := LFFlags.active_assignments(Game.state.data)
	for k in exps:
		p["exp_" + k] = exps[k]
	_queue.append({"event": event, "uuid": LFGameState.uuid4(), "properties": p, "timestamp": Time.get_datetime_string_from_system(true) + "Z"})
	if _queue.size() > MAX_QUEUE:
		_queue = _queue.slice(_queue.size() - MAX_QUEUE)
	_touch()
	_persist_soon()
	if provider == "debug":
		print("[analytics] ", event, " ", p)


## Non-identifying context on every event: build, environment and a coarse device class.
func common_properties() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"app_version": str(ProjectSettings.get_setting("application/config/version", "0")),
		"build": int(_client.get("build", 0)),
		"environment": str(_client.get("environment", "development")),
		"platform": OS.get_name(),
		"os_major": str(OS.get_version()).split(".")[0],
		"device_class": device_class(),
	}


## "phone" / "tablet" from the physical screen size; "desktop" elsewhere. Never a model or ID.
static func device_class() -> String:
	if not OS.has_feature("mobile"):
		return "desktop"
	var px := DisplayServer.screen_get_size()
	var dpi := maxi(1, DisplayServer.screen_get_dpi())
	var inches := sqrt(float(px.x * px.x + px.y * px.y)) / float(dpi)
	return "tablet" if inches >= 7.0 else "phone"


func queued() -> Array:
	return _queue


## Called when the player withdraws consent or deletes their data.
func clear() -> void:
	_queue.clear()
	if _http != null and _sending:
		_http.cancel_request()  # a batch in flight when consent is withdrawn is abandoned
	_sending = false
	if FileAccess.file_exists(queue_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(queue_path))


var _persist_pending := false


## Coalesce writes: at most one queue write per frame, so a kill loses at most the current frame.
func _persist_soon() -> void:
	if _persist_pending:
		return
	_persist_pending = true
	(func():
		_persist_pending = false
		_persist()).call_deferred()


func _persist() -> void:
	if not consented():
		return
	var f := FileAccess.open(queue_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_queue))
		f.close()


func _load_queue() -> void:
	if not FileAccess.file_exists(queue_path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(queue_path))
	if parsed is Array:
		_queue = parsed.slice(maxi(0, parsed.size() - MAX_QUEUE))


func flush() -> void:
	if _queue.is_empty() or _sending or not consented():
		return
	if provider != "posthog" and not send_transport.is_valid():
		_queue.clear()
		_persist()
		return
	var key := str(_cfg.get("posthogKey", ""))
	var host := str(_cfg.get("posthogHost", "https://eu.i.posthog.com"))
	if key.is_empty() and not send_transport.is_valid():
		_queue.clear()
		_persist()
		return
	var distinct: String = Game.state.data["analyticsId"]
	var batch: Array = []
	for e in _queue:
		batch.append({"event": e["event"], "uuid": e.get("uuid", ""), "properties": e["properties"].merged({"distinct_id": distinct, "$process_person_profile": false}), "timestamp": e["timestamp"]})
	_sending = true
	var sent := _queue.size()
	var body := {"api_key": key, "batch": batch}
	if send_transport.is_valid():
		var ok: bool = await send_transport.call(body)
		_finish(ok, sent)
		return
	var err := _http.request(host + "/batch/", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_sending = false
		return
	_http.set_meta("sent", sent)


func _on_done(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_finish(result == HTTPRequest.RESULT_SUCCESS and code < 300, int(_http.get_meta("sent", 0)))


func _finish(ok: bool, sent: int) -> void:
	_sending = false
	if ok:
		_queue = _queue.slice(sent)
	_persist()
