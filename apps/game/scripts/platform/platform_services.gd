class_name LFPlatform
extends RefCounted
## Cross-platform services (docs/IOS_READINESS.md). The ONLY entry point shared game code uses for
## anything that differs between Android, iOS and desktop: sharing, links, external URLs, haptics,
## secure storage and system accessibility hints. Screens never ask which platform they run on.
##
## Adapter selection (once, lazily):
##   iOS GDExtension "LoopFactoryIOS" present        -> LFIOSAdapter
##   Android plugin "LoopFactoryShare" present        -> LFAndroidAdapter
##   otherwise (desktop, editor, plain mobile build)  -> LFPlatformAdapter (safe fallback)
## Native modules are optional: a build without them still plays fully and falls back to copying
## text and manual challenge-code entry.

const OPENED := LFPlatformAdapter.OPENED
const UNAVAILABLE := LFPlatformAdapter.UNAVAILABLE
const FAILED := LFPlatformAdapter.FAILED
const INVALID_FILE := LFPlatformAdapter.INVALID_FILE

## Folder for generated share images; old files are pruned at startup.
const SHARE_DIR := "user://share"
const SHARE_MAX_AGE_S := 24 * 3600
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg"]
## Only these schemes are ever handed to the OS by open_external_url().
const URL_SCHEMES := ["https://", "mailto:"]

static var _adapter: LFPlatformAdapter = null


static func adapter() -> LFPlatformAdapter:
	if _adapter == null:
		_adapter = _select()
	return _adapter


## Test seam: force an adapter (null re-runs normal selection).
static func use_adapter(a: LFPlatformAdapter) -> void:
	_adapter = a


static func _select() -> LFPlatformAdapter:
	if Engine.has_singleton(LFIOSAdapter.SINGLETON):
		var ios := LFIOSAdapter.new(Engine.get_singleton(LFIOSAdapter.SINGLETON))
		if ios.native_available():
			return ios
	if Engine.has_singleton(LFAndroidAdapter.SINGLETON):
		return LFAndroidAdapter.new(Engine.get_singleton(LFAndroidAdapter.SINGLETON))
	return LFPlatformAdapter.new()


static func get_platform_name() -> String:
	return adapter().platform_name()


static func supports_native_sharing() -> bool:
	return adapter().supports_native_sharing()


static func supports_deep_links() -> bool:
	return adapter().supports_deep_links()


static func supports_haptics() -> bool:
	return adapter().supports_haptics()


static func supports_secure_storage() -> bool:
	return adapter().supports_secure_storage()


## Share plain text (a result line, an invite with a challenge URL).
static func share_text(text: String, title := "Share") -> String:
	if text.strip_edges() == "":
		return FAILED
	return adapter().share(text, "", "text/plain", title)


## Share a generated image with optional accompanying text. The file must exist and be an image.
static func share_image(image_path: String, text := "", title := "Share") -> String:
	var ext := image_path.get_extension().to_lower()
	if image_path == "" or not IMAGE_EXTENSIONS.has(ext) or not FileAccess.file_exists(image_path):
		return INVALID_FILE
	return adapter().share(text, ProjectSettings.globalize_path(image_path), "image/jpeg" if ext != "png" else "image/png", title)


## Share any existing file (the privacy data export).
static func share_file(path: String, text: String, mime: String, title := "Share") -> String:
	if path == "" or not FileAccess.file_exists(path):
		return INVALID_FILE
	return adapter().share(text, ProjectSettings.globalize_path(path), mime, title)


## Open an https (or mailto) URL in the system browser/app. Returns "opened", "rejected" (scheme
## not allowed, never handed to the OS) or "failed". "opened" means the OS accepted the request.
static func open_external_url(url: String) -> String:
	var ok := false
	for s in URL_SCHEMES:
		ok = ok or url.begins_with(s)
	if not ok or url.contains(" ") or url.length() > 2048:
		return "rejected"
	return "opened" if OS.shell_open(url) == OK else "failed"


## The deep link the app was opened with (or has just received), returned once.
static func consume_launch_uri() -> String:
	return adapter().consume_launch_uri()


static func vibrate(ms: int) -> void:
	adapter().vibrate(ms)


## Copy text for the manual fallback. The clipboard is never read back (reading it shows a paste
## prompt on iOS).
static func copy_to_clipboard(text: String) -> void:
	DisplayServer.clipboard_set(text)


static func system_reduce_motion() -> int:
	return adapter().system_reduce_motion()


static func secure_get(key: String) -> String:
	return adapter().secure_get(key)


static func secure_set(key: String, value: String) -> bool:
	return adapter().secure_set(key, value)


static func secure_delete(key: String) -> bool:
	return adapter().secure_delete(key)


## Delete generated share files older than max_age_s. Returns how many were removed.
static func prune_share_files(max_age_s := SHARE_MAX_AGE_S, now := -1) -> int:
	var d := DirAccess.open(SHARE_DIR)
	if d == null:
		return 0
	var t := int(Time.get_unix_time_from_system()) if now < 0 else now
	var removed := 0
	for f in d.get_files():
		var p := SHARE_DIR.path_join(f)
		if t - int(FileAccess.get_modified_time(p)) > max_age_s and d.remove(f) == OK:
			removed += 1
	return removed
