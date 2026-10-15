extends Node
## Autoload "Analytics": consent-gated, privacy-conscious event tracking with pluggable providers.
## - Nothing is sent unless the player opted in (settings.analytics).
## - Identity is a random analytics ID (not device IDs, not the account ID); reset on data deletion.
## - Events are batched in memory and flushed periodically; offline batches are retried, then dropped.
## Providers: "none" (default), "debug" (prints), "posthog" (HTTP capture API). Configure in
## res://config/client.json. See docs/analytics.md for the event taxonomy.

## Event taxonomy (docs/analytics.md). object_action, snake_case, past tense for outcomes.
const EVENTS := [
	# lifecycle
	"app_open", "first_launch", "session_start", "session_end", "app_background", "app_resume",
	"previous_session_unclean",
	# onboarding & core loop
	"tutorial_start", "tutorial_complete", "level_start", "level_complete", "level_fail", "level_retry",
	"hint_used", "replay_viewed",
	# daily
	"daily_challenge_entry", "daily_challenge_started", "daily_challenge_completed",
	# sharing & friend challenges
	"share_clicked", "share_completed", "challenge_create_clicked", "challenge_created",
	"challenge_link_opened", "challenge_completed",
	# Interdimensional Delivery Crew
	"character_exposed", "character_animation_played", "character_collection_opened",
	"cosmetic_unlocked", "cosmetic_equipped", "character_dialogue_shown", "character_dialogue_dismissed",
	# monetization (interfaces only; no store integrated)
	"purchase_started", "purchase_completed",
]
## A new session starts if the app was in the background longer than this.
const SESSION_GAP_MS := 30 * 60 * 1000
const MAX_QUEUE := 200

var provider := "none"
var last_event := ""
var _cfg := {}
var _queue: Array = []
var _http: HTTPRequest
var _session_id := ""
var _sending := false
var _session_started_ms := 0
var _background_at_ms := 0


func _ready() -> void:
	_cfg = Net.client_config().get("analytics", {})
	provider = str(_cfg.get("provider", "none"))
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_done)
	_session_id = LFGameState.uuid4()
	_session_started_ms = Time.get_ticks_msec()
	var t := Timer.new()
	t.wait_time = 30.0
	t.autostart = true
	t.timeout.connect(flush)
	add_child(t)
	var guard: Dictionary = Game.state.data.get("sessionGuard", {})
	if bool(guard.get("open", false)):
		# The last session never reached background/close: the app crashed or was killed in the
		# foreground. Used as the crash-free-sessions proxy until native crash reporting exists.
		track("previous_session_unclean", {"previous_session_id": str(guard.get("id", ""))})
	Game.state.data["sessionGuard"] = {"open": true, "id": _session_id}
	track("app_open")
	if int(Game.state.data["stats"].get("sessions", 0)) <= 1:
		track("first_launch")
	track("session_start")


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if _background_at_ms == 0:
				_background_at_ms = Time.get_ticks_msec()
				track("app_background", {"session_seconds": (_background_at_ms - _session_started_ms) / 1000, "screen": _screen()})
				_close_guard()
				flush()
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
					track("session_start", {"resumed": true})
				else:
					track("app_resume", {"away_seconds": away / 1000})
		NOTIFICATION_WM_CLOSE_REQUEST:
			track("session_end", {"session_seconds": (Time.get_ticks_msec() - _session_started_ms) / 1000, "reason": "close"})
			_close_guard()
			flush()


func _close_guard() -> void:
	if Game.state != null:
		Game.state.data["sessionGuard"] = {"open": false, "id": _session_id}
		Game.save_now()


func _screen() -> String:
	var m := get_tree().root.get_node_or_null("Main")
	return str(m.get("current_name")) if m != null else ""


func consented() -> bool:
	return Game.state != null and bool(Game.settings().get("analytics", false))


func track(event: String, props := {}) -> void:
	if not EVENTS.has(event):
		push_warning("Unknown analytics event " + event)
		return
	if not consented():
		return
	last_event = event
	var p := props.duplicate()
	p["session_id"] = _session_id
	p["app_version"] = ProjectSettings.get_setting("application/config/version", "0")
	p["platform"] = OS.get_name()
	var exps := LFFlags.active_assignments(Game.state.data)
	for k in exps:
		p["exp_" + k] = exps[k]
	_queue.append({"event": event, "properties": p, "timestamp": Time.get_datetime_string_from_system(true) + "Z"})
	if _queue.size() > MAX_QUEUE:
		_queue = _queue.slice(_queue.size() - MAX_QUEUE)
	if provider == "debug":
		print("[analytics] ", event, " ", p)


## Called when the player withdraws consent or deletes their data.
func clear() -> void:
	_queue.clear()


func flush() -> void:
	if _queue.is_empty() or _sending or not consented():
		return
	if provider != "posthog":
		_queue.clear()
		return
	var key := str(_cfg.get("posthogKey", ""))
	var host := str(_cfg.get("posthogHost", "https://eu.i.posthog.com"))
	if key.is_empty():
		_queue.clear()
		return
	var distinct: String = Game.state.data["analyticsId"]
	var batch: Array = []
	for e in _queue:
		batch.append({"event": e["event"], "properties": e["properties"].merged({"distinct_id": distinct, "$process_person_profile": false}), "timestamp": e["timestamp"]})
	_sending = true
	var sent := _queue.size()
	var err := _http.request(host + "/batch/", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"api_key": key, "batch": batch}))
	if err != OK:
		_sending = false
		return
	_http.set_meta("sent", sent)


func _on_done(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_sending = false
	if result == HTTPRequest.RESULT_SUCCESS and code < 300:
		var sent: int = _http.get_meta("sent", 0)
		_queue = _queue.slice(sent)
