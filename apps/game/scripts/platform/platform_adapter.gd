class_name LFPlatformAdapter
extends RefCounted
## Platform adapter contract and the SAFE FALLBACK used on desktop, the editor, the web, and on a
## phone whose native module is not part of the build (docs/IOS_READINESS.md). Shared game code never
## uses this class directly; it goes through LFPlatform (platform_services.gd).
##
## Results are honest: a native adapter can only ever report that the system share sheet OPENED
## (and, on iOS, whether the sheet was then dismissed or reported done). Nothing here claims that
## anyone received anything.

const OPENED := "chooser_opened"
const UNAVAILABLE := "unavailable"
const FAILED := "failed"
const INVALID_FILE := "invalid_file"

## Emitted when a deep link arrives while the app is running (native adapters only).
signal link_received(uri: String)
## Emitted when a share sheet closes: result is "completed", "cancelled" or "failed". "completed"
## means the chosen activity said it finished, NOT that a recipient got anything.
signal share_closed(result: String, activity: String)


## "android", "ios", "desktop" or "web". Reporting/diagnostics only; gameplay never branches on it.
func platform_name() -> String:
	if OS.has_feature("web"):
		return "web"
	return "desktop" if not OS.has_feature("mobile") else OS.get_name().to_lower()


## True when a native module is linked into this build.
func native_available() -> bool:
	return false


func supports_native_sharing() -> bool:
	return false


func supports_deep_links() -> bool:
	return false


func supports_haptics() -> bool:
	return OS.has_feature("mobile")


## Keychain-class storage that is not part of the save file.
func supports_secure_storage() -> bool:
	return false


## True when share_closed will fire after a sheet opens (iOS). Android's chooser reports nothing.
func reports_share_close() -> bool:
	return false


## Open the system share sheet. abs_path is an absolute path to an existing file, or "".
func share(_text: String, _abs_path: String, _mime: String, _title: String) -> String:
	return UNAVAILABLE


## The https URI the app was most recently opened with, returned once; "" when there is none.
func consume_launch_uri() -> String:
	return ""


func secure_get(_key: String) -> String:
	return ""


func secure_set(_key: String, _value: String) -> bool:
	return false


func secure_delete(_key: String) -> bool:
	return false


## The operating system's "reduce motion" preference: 1 on, 0 off, -1 unknown.
func system_reduce_motion() -> int:
	return -1


func vibrate(ms: int) -> void:
	if supports_haptics():
		Input.vibrate_handheld(ms)
