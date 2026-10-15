extends SceneTree
## Binding-layer tests for the LoopFactoryIOS GDExtension, against the REAL compiled C++ class built
## for the host with the stub bridge (ios/loopfactory-native, LF_STUB_BRIDGE). Run through
##   scripts/ios/test-native-stub.sh
## which compiles the extension and loads it into a scratch copy of the project with Godot 4.5.x.
## What this proves: the extension loads, registers the "LoopFactoryIOS" singleton, its methods and
## signals match what LFIOSAdapter / LFSecureTokens / main.gd expect, and deferred signal delivery
## works. What it does NOT prove: anything UIKit does (share sheet, Universal Links, Keychain) —
## that needs a simulator or an iPhone (docs/IOS_DEVICE_TEST_MATRIX.md).

var failures := 0
var checks := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("ok   ", msg)
	else:
		failures += 1
		printerr("FAIL ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var Platform: GDScript = load("res://scripts/platform/platform_services.gd")
	var IOSAdapter: GDScript = load("res://scripts/platform/ios_adapter.gd")
	var Tokens: GDScript = load("res://scripts/platform/secure_tokens.gd")
	check(Engine.has_singleton("LoopFactoryIOS"), "extension loaded and singleton registered")
	if not Engine.has_singleton("LoopFactoryIOS"):
		print("\niOS native binding tests: %d checks, %d failed" % [checks, failures + 1])
		quit(1)
		return
	var n: Object = Engine.get_singleton("LoopFactoryIOS")
	check(n.get_class() == "LoopFactoryIOS", "class registered as LoopFactoryIOS")
	check(n.apiVersion() == IOSAdapter.API_VERSION, "native API version matches the adapter (%d)" % IOSAdapter.API_VERSION)
	check(n.isNativeIOS() == false, "host build identifies itself as the stub")
	for m in ["share", "shareEx", "consumeLaunchUri", "isKeychainAvailable", "keychainSet", "keychainGet", "keychainDelete", "reduceMotion"]:
		check(n.has_method(m), "method bound: %s" % m)
	check(n.has_signal("launch_uri_received") and n.has_signal("share_finished"), "signals bound")

	# Adapter selection through the normal path (no test seam).
	Platform.use_adapter(null)
	var a = Platform.adapter()
	check(a.get_script() == IOSAdapter, "LFPlatform selects the iOS adapter when the extension is present")
	check(Platform.get_platform_name() == "ios" and Platform.supports_native_sharing() and Platform.supports_secure_storage(), "capabilities reported from the native module")

	# Share
	DirAccess.make_dir_recursive_absolute("user://share")
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.save_png("user://share/native-test.png")
	check(Platform.share_image("user://share/native-test.png", "result text") == Platform.OPENED, "image + text share -> opened")
	var closed: Array = []
	a.share_closed.connect(func(r, act): closed.append([r, act]))
	check(Platform.share_text("second while open") == Platform.FAILED, "a second sheet while one is open -> failed")
	n.stubFinishShare("cancelled", "")
	await _frames(2)
	check(closed == [["cancelled", ""]], "share_finished delivered (deferred) to the adapter: cancelled")
	check(Platform.share_text("invite https://play.example/c/K7MPQ2XR") == Platform.OPENED, "text share -> opened")
	n.stubFinishShare("completed", "com.apple.UIKit.activity.Message")
	await _frames(2)
	check(closed.size() == 2 and closed[1][0] == "completed", "completed result forwarded (no claim about recipients)")
	check(n.shareEx("x", "/definitely/missing.png", "image/png", "t") == 3, "missing file -> invalid_file code from native")
	check(n.shareEx("", "", "text/plain", "t") == 2, "nothing to share -> failed code")

	# Links
	var links: Array = []
	a.link_received.connect(func(u): links.append(u))
	n.stubDeliverLink("https://play.example/c/ABCDEFGH")
	await _frames(2)
	check(links == ["https://play.example/c/ABCDEFGH"], "launch_uri_received delivered to the adapter")
	check(Platform.consume_launch_uri() == "https://play.example/c/ABCDEFGH", "pending link consumed")
	check(Platform.consume_launch_uri() == "", "consumed only once")
	n.stubDeliverLink("https://play.example/c/AAAAAAAA")
	n.stubDeliverLink("https://play.example/c/BBBBBBBB")
	check(Platform.consume_launch_uri() == "https://play.example/c/BBBBBBBB", "consecutive links: latest wins")
	n.stubDeliverLink("http://insecure.example/c/AAAAAAAA")
	check(Platform.consume_launch_uri() == "", "non-https links ignored by the native layer")

	# Keychain through LFSecureTokens + Game
	check(Platform.secure_set("k", "v ü ✓") and Platform.secure_get("k") == "v ü ✓", "UTF-8 round trip through the native store")
	check(Platform.secure_delete("k") and Platform.secure_get("k") == "", "delete")
	check(not n.keychainSet("", "x") and n.keychainGet("") == "", "empty keys rejected")
	var game: Node = root.get_node("Game")
	game.store = load("res://scripts/core/save_store.gd").new("user://native-binding-save.json")
	game.state.data["auth"]["refreshToken"] = "native-rt-123"
	game.save_now()
	var text := FileAccess.get_file_as_string("user://native-binding-save.json")
	check(not text.contains("native-rt-123") and text.contains(Tokens.MARKER), "save file written without the token")
	check(n.keychainGet(Tokens.KEY) == "native-rt-123", "token held by the native store")
	for s in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://native-binding-save.json" + s))
	check(Platform.system_reduce_motion() == -1, "reduce motion unknown on the host stub")

	# Drop the adapter (and the lambdas connected to it above) while the script runtime is alive.
	Platform.use_adapter(load("res://scripts/platform/platform_adapter.gd").new())
	print("\niOS native binding tests: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
