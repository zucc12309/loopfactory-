class_name LFIOSAdapter
extends LFNativeAdapter
## iOS: the "LoopFactoryIOS" GDExtension (ios/loopfactory-native). It adds, on top of the shared
## native contract:
##   * UIActivityViewController share sheet, presented on the main thread, anchored for iPad, and a
##     share_finished(result, activity) signal ("completed" / "cancelled" / "failed");
##   * Universal Links captured from the app delegate (cold start and running app), queued until
##     the game consumes them, plus a launch_uri_received(uri) signal;
##   * Keychain storage (kSecClassGenericPassword, this-device-only) for the refresh token;
##   * the system Reduce Motion preference.
## The extension is only linked into iOS builds made with scripts/build-ios.sh --native; without it
## this adapter is never selected and the game uses the safe fallback (copy text / manual code entry).

const SINGLETON := "LoopFactoryIOS"
## Native API version this script understands (LoopFactoryIOS.apiVersion()).
const API_VERSION := 1


func platform_name() -> String:
	return "ios"


func native_available() -> bool:
	if not _linked():
		return false
	var v = call_native("apiVersion")
	return v is int and int(v) >= API_VERSION


func reports_share_close() -> bool:
	return native_available()


func supports_secure_storage() -> bool:
	return native_available() and call_native("isKeychainAvailable") == true


func share(text: String, abs_path: String, mime: String, title: String) -> String:
	if not native_available():
		return UNAVAILABLE
	# shareEx distinguishes a missing/unreadable file from other failures.
	var code = call_native("shareEx", [text, abs_path, mime, title])
	match int(code) if (code is int or code is float) else -1:
		0:
			return OPENED
		1:
			return UNAVAILABLE
		3:
			return INVALID_FILE
		_:
			return FAILED


func secure_get(key: String) -> String:
	var v = call_native("keychainGet", [key])
	return str(v) if v is String else ""


func secure_set(key: String, value: String) -> bool:
	return call_native("keychainSet", [key, value]) == true


func secure_delete(key: String) -> bool:
	return call_native("keychainDelete", [key]) == true


func system_reduce_motion() -> int:
	var v = call_native("reduceMotion")
	return int(v) if (v is int or v is float) else -1
