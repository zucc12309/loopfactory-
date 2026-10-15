extends SceneTree
## Cross-platform services (docs/IOS_READINESS.md), headless, no network and no native code:
##   godot --headless --path apps/game -s res://tests_e2e/platform_tests.gd
## * desktop fallback adapter, URL allow-list, share-file validation and pruning;
## * Android adapter contract (unchanged plugin calls) and iOS adapter contract against fakes;
## * secure refresh-token storage: Keychain write/read-back, migration, fallback, reinstall, wipe —
##   including what actually lands in the save file on disk.
## The REAL compiled iOS binding layer is exercised by scripts/ios/test-native-stub.sh.

var failures := 0
var checks := 0
var Platform: GDScript
var Adapter: GDScript
var AndroidAdapter: GDScript
var IOSAdapter: GDScript
var Tokens: GDScript
var Share: GDScript
var Game: Node
const TEST_SAVE := "user://platform-test-save.json"


func check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("ok   ", msg)
	else:
		failures += 1
		printerr("FAIL ", msg)


func _initialize() -> void:
	_run.call_deferred()


## A fake LoopFactoryIOS: same method names and return types as ios/loopfactory-native.
class FakeIOS:
	var api := 1
	var keychain := {}
	var keychain_ok := true
	var fail_writes := false
	var corrupt_reads := false
	var share_code := 0
	var calls: Array = []
	var pending := ""
	var reduce := 1

	func handle(method: String, args: Array) -> Variant:
		calls.append([method, args])
		match method:
			"apiVersion":
				return api
			"isKeychainAvailable":
				return keychain_ok
			"shareEx":
				return share_code
			"consumeLaunchUri":
				var u := pending
				pending = ""
				return u
			"keychainSet":
				if fail_writes:
					return false
				keychain[args[0]] = args[1]
				return true
			"keychainGet":
				if corrupt_reads and keychain.has(args[0]):
					return "something-else"
				return keychain.get(args[0], "")
			"keychainDelete":
				keychain.erase(args[0])
				return true
			"reduceMotion":
				return reduce
		return null


func _run() -> void:
	Platform = load("res://scripts/platform/platform_services.gd")
	Adapter = load("res://scripts/platform/platform_adapter.gd")
	AndroidAdapter = load("res://scripts/platform/android_adapter.gd")
	IOSAdapter = load("res://scripts/platform/ios_adapter.gd")
	Tokens = load("res://scripts/platform/secure_tokens.gd")
	Share = load("res://scripts/core/share.gd")
	Game = root.get_node("Game")
	Game.store = load("res://scripts/core/save_store.gd").new(TEST_SAVE)
	_fallback_tests()
	_url_tests()
	_android_tests()
	_ios_tests()
	_token_tests()
	_game_token_tests()
	_prune_tests()
	Platform.use_adapter(null)
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE + suffix))
	print("\nPlatform tests: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _png() -> String:
	DirAccess.make_dir_recursive_absolute("user://share")
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.ORANGE)
	img.save_png("user://share/platform-test.png")
	return "user://share/platform-test.png"


func _fallback_tests() -> void:
	Platform.use_adapter(null)
	var a = Platform.adapter()
	check(a.get_script() == Adapter, "desktop/editor selects the safe fallback adapter")
	check(Platform.get_platform_name() == "desktop", "platform name 'desktop' (got %s)" % Platform.get_platform_name())
	check(not Platform.supports_native_sharing() and not Platform.supports_deep_links() and not Platform.supports_secure_storage(), "fallback claims no native features")
	check(Platform.supports_haptics() == OS.has_feature("mobile"), "haptics only reported on phones")
	check(Platform.share_text("hello") == Platform.UNAVAILABLE, "share_text without a native sheet -> unavailable (caller falls back)")
	check(Platform.share_text("   ") == Platform.FAILED, "empty share text rejected")
	check(Platform.share_image("user://share/does-not-exist.png", "x") == Platform.INVALID_FILE, "missing image -> invalid_file")
	check(Platform.share_image("user://save.json", "x") == Platform.INVALID_FILE, "non-image file -> invalid_file")
	check(Platform.share_image(_png(), "x") == Platform.UNAVAILABLE, "valid image but no native sheet -> unavailable")
	check(Platform.share_file("user://nope.json", "x", "application/json") == Platform.INVALID_FILE, "missing export file -> invalid_file")
	check(Platform.consume_launch_uri() == "", "no launch link on desktop")
	check(Platform.secure_get("k") == "" and not Platform.secure_set("k", "v") and not Platform.secure_delete("k"), "no secure storage on desktop")
	check(Platform.system_reduce_motion() == -1, "system reduce-motion unknown on desktop")
	check(Share.native_available() == false and Share.launch_uri() == "", "LFShare delegates to the platform layer")


func _url_tests() -> void:
	for bad in ["http://loopfactory.app/privacy", "javascript:alert(1)", "file:///etc/passwd", "loopfactory://x", "https://bad url", "", "ftp://x"]:
		check(Platform.open_external_url(bad) == "rejected", "URL never handed to the OS: '%s'" % bad)


func _android_tests() -> void:
	var calls: Array = []
	var ret := [true]
	var fake := func(method: String, args: Array) -> Variant:
		calls.append([method, args])
		if method == "share":
			return ret[0]
		if method == "consumeLaunchUri":
			return "https://play.example/c/K7MPQ2XR"
		return null
	var a = AndroidAdapter.new(fake)
	Platform.use_adapter(a)
	check(Platform.get_platform_name() == "android" and Platform.supports_native_sharing() and Platform.supports_deep_links(), "Android adapter: sharing + App Links")
	check(not Platform.supports_secure_storage(), "Android adapter: no secure-storage backend (token stays in the save, as before)")
	check(Platform.share_text("invite K7MPQ2XR") == Platform.OPENED, "Android text share -> chooser opened")
	check(calls[-1][0] == "share" and calls[-1][1] == ["invite K7MPQ2XR", "", "text/plain", "Share"], "plugin share(text, '', text/plain, title) unchanged")
	var png := _png()
	check(Platform.share_image(png, "result") == Platform.OPENED, "Android image share -> chooser opened")
	check(calls[-1][1][1] == ProjectSettings.globalize_path(png) and calls[-1][1][2] == "image/png", "plugin gets an absolute PNG path")
	ret[0] = false
	check(Platform.share_text("x") == Platform.FAILED, "plugin failure reported as failed, never as opened")
	check(Share.launch_uri() == "https://play.example/c/K7MPQ2XR" and Share.parse_challenge(Share.launch_uri()) == "K7MPQ2XR", "App Link consumed through LFShare")


func _ios_tests() -> void:
	var f := FakeIOS.new()
	var a = IOSAdapter.new(f.handle)
	Platform.use_adapter(a)
	check(Platform.get_platform_name() == "ios", "iOS adapter platform name")
	check(Platform.supports_native_sharing() and Platform.supports_deep_links() and Platform.supports_secure_storage(), "iOS adapter: share sheet, Universal Links, Keychain")
	var png := _png()
	var expect := {0: Platform.OPENED, 1: Platform.UNAVAILABLE, 2: Platform.FAILED, 3: Platform.INVALID_FILE}
	for code in expect:
		f.share_code = code
		check(Platform.share_image(png, "result") == expect[code], "native shareEx %d -> %s" % [code, expect[code]])
	check(f.calls.filter(func(c): return c[0] == "shareEx")[-1][1] == ["result", ProjectSettings.globalize_path(png), "image/png", "Share"], "image + text handed over together")
	f.share_code = 0
	check(Platform.share_text("Beat 6 rotations: https://play.example/c/K7MPQ2XR") == Platform.OPENED, "challenge URL shared as text")
	check(Share.share("data", "user://missing.json", "application/json") == Platform.INVALID_FILE, "missing export never reaches the native sheet")
	var closed: Array = []
	a.share_closed.connect(func(r, act): closed.append([r, act]))
	a.emit_share_closed("cancelled", "")
	a.emit_share_closed("completed", "com.apple.UIKit.activity.Message")
	check(closed == [["cancelled", ""], ["completed", "com.apple.UIKit.activity.Message"]], "share sheet close results forwarded (cancel / done)")
	var links: Array = []
	a.link_received.connect(func(u): links.append(u))
	f.pending = "https://play.example/c/ABCDEFGH"
	a.emit_link(f.pending)
	check(links == ["https://play.example/c/ABCDEFGH"], "Universal Link signal forwarded")
	check(Platform.consume_launch_uri() == "https://play.example/c/ABCDEFGH" and Platform.consume_launch_uri() == "", "each link consumed exactly once")
	check(Platform.system_reduce_motion() == 1, "system Reduce Motion read from iOS")
	f.api = 0
	check(not a.native_available(), "an older native module (api < %d) is ignored" % IOSAdapter.API_VERSION)
	f.api = 1
	f.keychain_ok = false
	check(not Platform.supports_secure_storage(), "Keychain probe failure -> no secure storage")


func _token_tests() -> void:
	var f := FakeIOS.new()
	Platform.use_adapter(IOSAdapter.new(f.handle))
	var data := {"auth": {"playerId": "p1", "refreshToken": "rt-1", "displayName": "A"}, "progress": {}}
	var disk: Dictionary = Tokens.for_disk(data)
	check(not disk["auth"].has("refreshToken") and disk["auth"][Tokens.MARKER] == "keychain", "save copy has no token, only the marker")
	check(f.keychain.get(Tokens.KEY, "") == "rt-1", "token written to the Keychain")
	check(data["auth"]["refreshToken"] == "rt-1", "in-memory state untouched")
	# Reload
	var loaded := {"auth": disk["auth"].duplicate()}
	loaded["auth"]["refreshToken"] = ""
	Tokens.after_load(loaded, false)
	check(loaded["auth"]["refreshToken"] == "rt-1" and not loaded["auth"].has(Tokens.MARKER), "token restored from the Keychain on load")
	# Rotation
	data["auth"]["refreshToken"] = "rt-2"
	Tokens.for_disk(data)
	check(f.keychain[Tokens.KEY] == "rt-2", "rotated token replaces the Keychain copy")
	# Migration of a plaintext save (older build)
	f.keychain.clear()
	var old := {"auth": {"playerId": "p1", "refreshToken": "rt-old"}}
	Tokens.after_load(old, false)
	check(old["auth"]["refreshToken"] == "rt-old", "plaintext token kept in memory on load")
	var mig: Dictionary = Tokens.for_disk(old)
	check(f.keychain.get(Tokens.KEY, "") == "rt-old" and not mig["auth"].has("refreshToken"), "plaintext token migrated to the Keychain on the next save")
	# Write failure: identity is never dropped.
	f.keychain.clear()
	f.fail_writes = true
	Tokens.last_problem = ""
	var d2 := {"auth": {"refreshToken": "rt-3"}}
	var out: Dictionary = Tokens.for_disk(d2)
	check(out["auth"].get("refreshToken", "") == "rt-3" and Tokens.last_problem == "write_failed", "Keychain write failure keeps the token in the file")
	f.fail_writes = false
	f.corrupt_reads = true
	out = Tokens.for_disk({"auth": {"refreshToken": "rt-4"}})
	check(out["auth"].get("refreshToken", "") == "rt-4", "read-back mismatch keeps the token in the file")
	f.corrupt_reads = false
	# Fresh install: stale Keychain token from an earlier install is removed.
	f.keychain[Tokens.KEY] = "stale"
	var fresh := {"auth": {"refreshToken": ""}}
	Tokens.after_load(fresh, true)
	check(not f.keychain.has(Tokens.KEY) and fresh["auth"]["refreshToken"] == "", "reinstall starts a new guest (stale Keychain token deleted)")
	# Marker but nothing in the Keychain.
	Tokens.last_problem = ""
	var lost := {"auth": {"refreshToken": "", Tokens.MARKER: "keychain"}}
	Tokens.after_load(lost, false)
	check(lost["auth"]["refreshToken"] == "" and Tokens.last_problem == "token_missing", "missing Keychain item reported, not invented")
	# Saved with the extension, loaded without it.
	Platform.use_adapter(load("res://scripts/platform/platform_adapter.gd").new())
	Tokens.last_problem = ""
	var nok := {"auth": {"refreshToken": "", Tokens.MARKER: "keychain"}}
	Tokens.after_load(nok, false)
	check(Tokens.last_problem == "secure_store_unavailable", "build without the extension reports the unreachable token")
	var same := {"auth": {"refreshToken": "rt-file"}}
	check(Tokens.for_disk(same) == same, "without secure storage the save is written exactly as before")
	# Wipe
	f.keychain[Tokens.KEY] = "x"
	Platform.use_adapter(IOSAdapter.new(f.handle))
	Tokens.wipe()
	check(not f.keychain.has(Tokens.KEY), "local deletion removes the Keychain token")


func _game_token_tests() -> void:
	var f := FakeIOS.new()
	Platform.use_adapter(IOSAdapter.new(f.handle))
	Tokens.after_load({"auth": {}}, false)  # reset cache
	Game.state.data = load("res://scripts/core/game_state.gd").defaults()
	Game.state.data["auth"]["playerId"] = "p-ios"
	Game.state.data["auth"]["refreshToken"] = "secret-refresh-token-xyz"
	Game.save_now()
	var text := FileAccess.get_file_as_string(TEST_SAVE)
	check(text != "" and not text.contains("secret-refresh-token-xyz"), "the save file on disk holds no refresh token on iOS")
	check(text.contains("p-ios"), "the rest of the save is written normally")
	check(f.keychain.get(Tokens.KEY, "") == "secret-refresh-token-xyz", "Game.save_now puts the token in the Keychain")
	var st = load("res://scripts/core/game_state.gd").new([], [])
	st.load_from(Game.store.load_data())
	Tokens.after_load(st.data, false)
	check(st.data["auth"]["refreshToken"] == "secret-refresh-token-xyz", "restart: token restored into state")
	# Android / desktop: unchanged on-disk format.
	Platform.use_adapter(AndroidAdapter.new(func(_m, _a): return null))
	Game.save_now()
	check(FileAccess.get_file_as_string(TEST_SAVE).contains("secret-refresh-token-xyz"), "Android keeps the token in the save file (unchanged)")
	Game.state.data["auth"]["refreshToken"] = ""


func _prune_tests() -> void:
	Platform.use_adapter(null)
	DirAccess.make_dir_recursive_absolute(Platform.SHARE_DIR)
	for n in ["old-a.png", "old-b.png"]:
		var fa := FileAccess.open(Platform.SHARE_DIR.path_join(n), FileAccess.WRITE)
		fa.store_string("x")
		fa.close()
	check(Platform.prune_share_files(Platform.SHARE_MAX_AGE_S) == 0, "fresh share files are kept")
	var later: int = int(Time.get_unix_time_from_system()) + int(Platform.SHARE_MAX_AGE_S) + 60
	check(Platform.prune_share_files(Platform.SHARE_MAX_AGE_S, later) >= 2, "share files older than a day are pruned")
	check(not FileAccess.file_exists(Platform.SHARE_DIR.path_join("old-a.png")), "pruned file removed")
