class_name LFShare
extends RefCounted
## Sharing and challenge links (audit R6, R6.1, M1) — platform-neutral.
##
## The native share sheet is reached ONLY through LFPlatform (scripts/platform/): the Android
## "LoopFactoryShare" plugin, the iOS "LoopFactoryIOS" GDExtension, or the safe fallback when neither
## is in the build (every call returns UNAVAILABLE and the caller offers copy-text / save-image). A
## private user:// path is never shown to the player as if it were a public file.
##
## What can be observed: that the share sheet OPENED (iOS can also report that it was dismissed).
## Whether anyone received anything is not observable here and is never reported.

const OPENED := LFPlatform.OPENED
const UNAVAILABLE := LFPlatform.UNAVAILABLE
const FAILED := LFPlatform.FAILED
const INVALID_FILE := LFPlatform.INVALID_FILE

## Unambiguous alphabet (no 0/O, 1/I/L), same as the server's.
const CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 8


static func native_available() -> bool:
	return LFPlatform.supports_native_sharing()


## Open the share sheet with text and an optional file (user:// or absolute path).
static func share(text: String, file_path := "", mime := "image/png", title := "Share") -> String:
	if file_path == "":
		return LFPlatform.share_text(text, title)
	if mime.begins_with("image/"):
		return LFPlatform.share_image(file_path, text, title)
	return LFPlatform.share_file(file_path, text, mime, title)


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


## URI the app was opened with (Android App Link / iOS Universal Link, via LFPlatform), or "".
static func launch_uri() -> String:
	return LFPlatform.consume_launch_uri()


## Share URL for a code on the configured link host (https://<host>/c/CODE), or "" when unset.
static func challenge_url(code: String, cfg: Dictionary) -> String:
	var host := str(cfg.get("appLinks", {}).get("host", ""))
	return ("https://%s/c/%s" % [host, code]) if host != "" else ""
