class_name LFNativeAdapter
extends LFPlatformAdapter
## Shared plumbing for adapters backed by a native singleton (Android plugin, iOS GDExtension).
## Both natives implement the same core contract:
##   share(text, absPath, mime, title) -> bool   true = the system sheet was asked to open
##   consumeLaunchUri() -> String                  each incoming link once, "" when none
## A test can pass a Callable(method: String, args: Array) -> Variant instead of a real object.

var _native: Object
var _fake := Callable()


func _init(native: Variant) -> void:
	if native is Callable:
		_fake = native
	elif native is Object:
		_native = native
		_connect_signals()


func native_available() -> bool:
	return _fake.is_valid() or (_native != null and is_instance_valid(_native))


func supports_native_sharing() -> bool:
	return native_available()


func supports_deep_links() -> bool:
	return native_available()


func call_native(method: String, args: Array = []) -> Variant:
	if _fake.is_valid():
		return _fake.call(method, args)
	if native_available() and _native.has_method(method):
		return _native.callv(method, args)
	return null


func share(text: String, abs_path: String, mime: String, title: String) -> String:
	if not native_available():
		return UNAVAILABLE
	var ok = call_native("share", [text, abs_path, mime, title])
	return OPENED if ok == true else FAILED


func consume_launch_uri() -> String:
	var u = call_native("consumeLaunchUri")
	return str(u) if u is String else ""


## Test helper: lets a fake native deliver events the way the real one does.
func emit_link(uri: String) -> void:
	link_received.emit(uri)


func emit_share_closed(result: String, activity := "") -> void:
	share_closed.emit(result, activity)


func _connect_signals() -> void:
	if _native.has_signal("launch_uri_received"):
		_native.connect("launch_uri_received", emit_link)
	if _native.has_signal("share_finished"):
		_native.connect("share_finished", emit_share_closed)
