class_name LFShare
extends RefCounted
## Native sharing and challenge links (audit R6, R6.1, M1).
##
## Native share sheet: the Android plugin in android/share-plugin (singleton "LoopFactoryShare")
## copies the file into the app cache, exposes it through a FileProvider content:// URI with a
## temporary read grant and opens the system chooser (ACTION_SEND). It is NOT in this build until the
## plugin is compiled with the Gradle export (docs/BETA_READINESS_IMPLEMENTATION.md): without it every
## call returns UNAVAILABLE and the caller falls back to copy-text / save-image. A private user://
## path is never shown to the player as if it were a public file.
##
## What can be observed: that the chooser OPENED. Whether a target app was picked, or anyone received
## anything, is not observable here and is never reported.

const PLUGIN := "LoopFactoryShare"
const OPENED := "chooser_opened"
const UNAVAILABLE := "unavailable"
const FAILED := "failed"

## Unambiguous alphabet (no 0/O, 1/I/L), same as the server's.
const CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 8

## Test seam: replaces the plugin when set (callable(method: String, args: Array) -> Variant).
static var fake_plugin := Callable()


static func native_available() -> bool:
	return fake_plugin.is_valid() or Engine.has_singleton(PLUGIN)


static func _call(method: String, args: Array) -> Variant:
	if fake_plugin.is_valid():
		return fake_plugin.call(method, args)
	if Engine.has_singleton(PLUGIN):
		return Engine.get_singleton(PLUGIN).callv(method, args)
	return null


## Open the share chooser with text and an optional file (absolute path or user:// path).
static func share(text: String, file_path := "", mime := "image/png", title := "Share") -> String:
	if not native_available():
		return UNAVAILABLE
	var abs := ProjectSettings.globalize_path(file_path) if file_path != "" else ""
	var ok = _call("share", [text, abs, mime if abs != "" else "text/plain", title])
	return OPENED if ok == true else FAILED


## Link / launch argument → challenge code, or "" (invalid input is rejected here, before any request).
## Accepts https://<host>/c/CODE, loopfactory://challenge/CODE, --challenge=CODE or a bare code.
static func parse_challenge(s: String) -> String:
	var t := s.strip_edges()
	for prefix in ["--challenge=", "loopfactory://challenge/"]:
		if t.begins_with(prefix):
			t = t.substr(prefix.length())
	if t.begins_with("http://") or t.begins_with("https://"):
		var i := t.find("/c/")
		if i < 0:
			return ""
		t = t.substr(i + 3)
	t = t.split("?")[0].split("#")[0].trim_suffix("/").replace(" ", "").replace("-", "").to_upper()
	return t if valid_code(t) else ""


static func valid_code(code: String) -> bool:
	if code.length() != CODE_LENGTH:
		return false
	for ch in code:
		if not CODE_ALPHABET.contains(ch):
			return false
	return true


## URI the app was opened with by an Android App Link / intent (via the plugin), or "".
static func launch_uri() -> String:
	var u = _call("consumeLaunchUri", [])
	return str(u) if u is String else ""


## Share URL for a code on the configured link host (https://<host>/c/CODE), or "" when unset.
static func challenge_url(code: String, cfg: Dictionary) -> String:
	var host := str(cfg.get("appLinks", {}).get("host", ""))
	return ("https://%s/c/%s" % [host, code]) if host != "" else ""
