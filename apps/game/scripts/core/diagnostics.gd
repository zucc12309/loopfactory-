class_name LFDiagnostics
extends RefCounted
## Minimal beta diagnostics (audit R8). What it CAN see:
##  * errors the game itself detects: save write failures, recovered/corrupt saves, sync/network
##    failures (recoverable), and an unclean previous exit (fatal proxy: crash or kill in foreground);
##  * an explicit test event (tap the version label in Settings 7 times).
## What it can NOT see: native crashes (signals/ANRs inside the engine) and arbitrary GDScript runtime
## errors — Godot 4.3 has no hook for either, and no native crash SDK is integrated (no credentials /
## plugin). So it never reports a crash-free-session rate; see docs/BETA_READINESS_IMPLEMENTATION.md.
##
## Every record is kept locally (ring buffer, user://diagnostics.json, included in data export and
## erased with the rest of local data) and, only with analytics consent, sent as `app_error` /
## `network_error`. Details are scrubbed: no tokens, no URLs/challenge links, no player ids.

const PATH := "user://diagnostics.json"
const MAX := 50
const CATEGORIES := ["save_failed", "save_recovered", "unclean_exit", "network", "auth", "config", "diagnostic_test", "share"]

static var path := PATH
static var _seen := {}  # category -> true: network/auth are recorded once per session


static func record(category: String, fatal := false, detail := {}) -> Dictionary:
	if not CATEGORIES.has(category):
		category = "config"
	if (category == "network" or category == "auth") and _seen.has(category):
		return {}
	_seen[category] = true
	var entry := {
		"ts": Time.get_datetime_string_from_system(true) + "Z", "category": category, "fatal": fatal,
		"recoverable": not fatal, "detail": scrub(detail),
	}
	entry.merge(context())
	var list := read_all()
	list.append(entry)
	if list.size() > MAX:
		list = list.slice(list.size() - MAX)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(list))
		f.close()
	var event := "network_error" if category == "network" or category == "auth" else "app_error"
	var a: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Analytics") if Engine.get_main_loop() is SceneTree else null
	if a != null:
		a.track(event, {"category": category, "fatal": fatal, "detail": entry["detail"]})
	return entry


## Build/environment/device context (no identifiers).
static func context() -> Dictionary:
	var cfg := LFReleaseConfig.load_client()
	return {
		"app_version": str(ProjectSettings.get_setting("application/config/version", "0")),
		"build": int(cfg.get("build", 0)), "environment": str(cfg.get("environment", "development")),
		"platform": OS.get_name(), "os_major": str(OS.get_version()).split(".")[0],
	}


## Keep only short scalar values; drop anything that looks like a secret, a link or an id.
static func scrub(detail: Dictionary) -> Dictionary:
	var out := {}
	for k in detail:
		var key := str(k).to_lower()
		if key.contains("token") or key.contains("auth") or key.contains("url") or key.contains("code") or key.contains("player") or key.contains("password") or key.contains("secret"):
			continue
		var v = detail[k]
		if v is bool or v is int or v is float:
			out[k] = v
		elif v is String:
			var s: String = v
			if s.contains("://") or s.to_lower().contains("bearer") or s.length() > 120:
				s = "[redacted]"
			out[k] = s
	return out


## Tests point the store elsewhere.
static func use_path(p: String) -> void:
	path = p


static func read_all() -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Array else []


static func clear() -> void:
	_seen.clear()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Monitoring state of a build's config: "ok" (provider "local": this diagnostics boundary is on),
## "not_configured" (development without it), "misconfigured" (a staging/production build without
## it), "unsupported" (a provider this client has no SDK for, e.g. "sentry"). Staging builds show the
## last two as a visible warning so a tester never assumes errors are being collected.
static func monitoring_status(cfg: Dictionary) -> String:
	var cr: Dictionary = cfg.get("crashReporting", {})
	var prov := str(cr.get("provider", "none"))
	var env := str(cfg.get("environment", "development"))
	match prov:
		"local":
			return "ok"
		"none":
			return "not_configured" if env == "development" else "misconfigured"
	return "unsupported"
