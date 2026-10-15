extends SceneTree
## iPhone compatibility scene tests (real screens and autoloads; docs/IOS_DEVICE_TEST_MATRIX.md):
##   xvfb-run godot --path apps/game --rendering-driver opengl3 -s res://tests_ui/ios_ui_tests.gd
## * Safe areas: on four iPhone geometries (home button, notch, Dynamic Island, Pro Max) with their
##   real top/bottom insets simulated, no button, field or scroll area sits under the notch /
##   Dynamic Island or the home indicator, and nothing is wider than the screen.
## * Challenge links delivered while the game runs (signal and resume poll): valid, invalid,
##   repeated, consecutive, offline, and never consumed during the splash.
## * Lifecycle: pause / memory warning save immediately; system Reduce Motion seeds the setting once.
## * Share card with an iOS native module: Share button, honest events, sheet-closed result.
## Desktop simulation of iOS geometry and events — NOT a substitute for a simulator or an iPhone.

var failures := 0
var checks := 0
var Game: Node
var Main: GDScript
var Platform: GDScript
var IOSAdapter: GDScript

## [name, physical pixels, top inset px, bottom inset px] (points × scale, portrait).
const PHONES := [
	["iPhone SE (3rd gen)", Vector2i(750, 1334), 0, 0],
	["iPhone 13 mini", Vector2i(1080, 2340), 150, 102],
	["iPhone 16", Vector2i(1179, 2556), 177, 102],
	["iPhone 16 Pro Max", Vector2i(1320, 2868), 186, 102],
]
const SCREENS := ["home", "levels", "play", "daily", "challenge", "crew", "profile", "settings"]


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL ", msg)
	else:
		print("ok   ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _fresh_state() -> void:
	Game.state.data = load("res://scripts/core/game_state.gd").defaults()
	Game.state.data["settings"]["analyticsAsked"] = true
	Game.state.data["settings"]["sfx"] = false
	Game.state.data["settings"]["music"] = false
	Game.state.data["settings"]["systemPrefsApplied"] = true


func _make_main(size: Vector2i) -> Array:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	root.add_child(vp)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	vp.add_child(main)
	await _frames(2)
	return [vp, main]


func _run() -> void:
	Game = root.get_node("Game")
	Main = load("res://scripts/ui/main.gd")
	Platform = load("res://scripts/platform/platform_services.gd")
	IOSAdapter = load("res://scripts/platform/ios_adapter.gd")
	Game.store = load("res://scripts/core/save_store.gd").new("user://ios-ui-test-save.json")
	root.get_node("Net").base_url = ""  # offline: nothing here touches a server
	_fresh_state()
	await _safe_area_tests()
	await _link_tests()
	await _lifecycle_tests()
	await _share_tests()
	Main.simulate_safe_area(Vector2i(), Rect2i())
	Platform.use_adapter(null)
	print("\niOS UI tests: %d checks, %d failed" % [checks, failures])
	for s in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ios-ui-test-save.json" + s))
	quit(1 if failures > 0 else 0)


func _has_scroll_ancestor(c: Node) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


# ------------------------------------------------------------------------------- safe areas

func _safe_area_tests() -> void:
	for phone in PHONES:
		var px: Vector2i = phone[1]
		var top_px: int = phone[2]
		var bottom_px: int = phone[3]
		Main.simulate_safe_area(px, Rect2i(0, top_px, px.x, px.y - top_px - bottom_px))
		var vh := int(round(720.0 * px.y / px.x))
		var scale := float(vh) / px.y
		var top := top_px * scale
		var bottom := vh - bottom_px * scale
		var made: Array = await _make_main(Vector2i(720, vh))
		var main: Control = made[1]
		await _wait(0.9)
		var sm: Vector2 = main.safe_margins()
		check(absf(sm.x - top_px * scale) < 0.5 and absf(sm.y - bottom_px * scale) < 0.5, "%s: safe margins %.0f / %.0f viewport units" % [phone[0], sm.x, sm.y])
		for name in SCREENS:
			var args := {}
			if name == "play":
				Game.state.data["active"] = null
				args = {"kind": "campaign", "index": 0}
			main.goto(name, args)
			await _wait(0.45)
			var bad: Array = []
			var wide: Array = []
			for c in main.current.find_children("*", "Control", true, false):
				var ctl := c as Control
				if not ctl.is_visible_in_tree() or ctl.size.x <= 0 or ctl.size.y <= 0:
					continue
				var interactive := ctl is BaseButton or ctl is LineEdit or ctl is ScrollContainer or ctl.get_class() == "Control" and ctl.has_method("cell_center")
				if interactive and not _has_scroll_ancestor(ctl):
					var r := ctl.get_global_rect()
					if r.position.y < top - 0.5 or r.end.y > bottom + 0.5 or r.position.x < -0.5 or r.end.x > 720.5:
						bad.append("%s %s" % [ctl.name, r])
				if ctl is Label and not _has_scroll_ancestor(ctl) and ctl.get_global_rect().end.x > 720.5:
					wide.append(ctl.name)
			check(bad.is_empty(), "%s / %s: controls clear of the notch and home indicator %s" % [phone[0], name, bad.slice(0, 3)])
			check(wide.is_empty(), "%s / %s: no text wider than the screen %s" % [phone[0], name, wide.slice(0, 3)])
			main.home()
			await _wait(0.3)
		made[0].queue_free()
		await _frames(2)
	Main.simulate_safe_area(Vector2i(), Rect2i())


# ------------------------------------------------------------------------------------ links

class FakeIOS:
	var pending := ""
	var reduce := -1
	var share_code := 0
	var keychain := {}

	func handle(method: String, args: Array) -> Variant:
		match method:
			"apiVersion":
				return 1
			"isKeychainAvailable":
				return true
			"consumeLaunchUri":
				var u := pending
				pending = ""
				return u
			"shareEx":
				return share_code
			"reduceMotion":
				return reduce
			"keychainSet":
				keychain[args[0]] = args[1]
				return true
			"keychainGet":
				return keychain.get(args[0], "")
			"keychainDelete":
				keychain.erase(args[0])
				return true
		return null


func _link_tests() -> void:
	_fresh_state()
	var f := FakeIOS.new()
	var a = IOSAdapter.new(f.handle)
	Platform.use_adapter(a)
	var made: Array = await _make_main(Vector2i(720, 1561))
	var main: Control = made[1]
	# A link arriving during the splash is left for the splash's own launch check.
	f.pending = "https://play.example/c/K7MPQ2XR"
	main._poll_link()
	check(f.pending != "", "link not consumed while the splash is showing")
	await _wait(1.0)
	check(main.current_name == "challenge" and f.pending == "", "cold start: launch link opens the challenge screen")
	check(main.current._input.text == "K7MPQ2XR", "cold start: code filled in")
	await _wait(0.4)
	check(str(Game.state.data["challenges"].get("pending", "")) == "K7MPQ2XR", "offline: code kept for the next online launch")
	main.home()
	await _wait(0.4)
	# Running app (foreground): signal from the native module.
	f.pending = "https://play.example/c/ABCDEFGH"
	a.emit_link(f.pending)
	await _wait(0.5)
	check(main.current_name == "challenge" and main.current._input.text == "ABCDEFGH", "foreground link routed via the native signal")
	# Same challenge again: reopened, not stacked.
	var depth: int = main._stack.size()
	f.pending = "https://play.example/c/ABCDEFGH"
	a.emit_link(f.pending)
	await _wait(0.5)
	check(main.current_name == "challenge" and main._stack.size() == depth, "same link again: reopened without stacking screens")
	# Different links consecutively: the latest wins.
	f.pending = "https://play.example/c/BBBBBBBB"
	a.emit_link(f.pending)
	await _wait(0.5)
	check(main.current._input.text == "BBBBBBBB" and main._stack.size() == depth, "consecutive different links: latest shown")
	# Backgrounded app: delivered while paused, picked up on resume.
	main.home()
	await _wait(0.4)
	f.pending = "https://play.example/c/CCCCCCCC"
	main._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _wait(0.5)
	check(main.current_name == "challenge" and main.current._input.text == "CCCCCCCC", "background → resume: pending link routed")
	# Invalid link: rejected before any request, player stays where they are.
	main.home()
	await _wait(0.4)
	f.pending = "https://play.example/c/bad!"
	main._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _wait(0.4)
	check(main.current_name == "home", "invalid link: no navigation")
	var toast_text := ""
	for l in main._toast_layer.find_children("*", "Label", true, false):
		toast_text += (l as Label).text
	check(toast_text.contains("isn't a Loop Factory challenge"), "invalid link: plain explanation shown")
	# Nothing pending: resume does nothing.
	main._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _wait(0.3)
	check(main.current_name == "home", "resume without a link: no navigation")
	# Manual entry still works with the native module present.
	main.goto("challenge")
	await _wait(0.4)
	main.current._input.text = "k7mp-q2xr"
	main.current._open()
	await _wait(0.3)
	check(str(Game.state.data["challenges"].get("pending", "")) == "K7MPQ2XR", "manual code entry still works (normalised, kept offline)")
	made[0].queue_free()
	await _frames(2)


# -------------------------------------------------------------------------------- lifecycle

func _lifecycle_tests() -> void:
	_fresh_state()
	Platform.use_adapter(null)
	Game.state.data["stats"]["moves"] = 123
	Game._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(FileAccess.get_file_as_string(Game.store.path).contains("\\\"moves\\\":123"), "app paused (backgrounded): state saved at once")
	Game.state.data["stats"]["moves"] = 124
	LFDiagnostics.clear()
	Game._notification(Node.NOTIFICATION_OS_MEMORY_WARNING)
	check(FileAccess.get_file_as_string(Game.store.path).contains("\\\"moves\\\":124"), "memory warning: state saved at once")
	check(LFDiagnostics.read_all().any(func(e): return e["category"] == "memory_warning"), "memory warning recorded locally")
	LFDiagnostics.clear()
	# System Reduce Motion seeds the setting once; the player's choice wins afterwards.
	var f := FakeIOS.new()
	f.reduce = 1
	Platform.use_adapter(IOSAdapter.new(f.handle))
	Game.state.data["settings"].erase("systemPrefsApplied")
	Game.state.data["settings"]["reducedMotion"] = false
	Game._apply_system_preferences()
	check(Game.state.data["settings"]["reducedMotion"] == true, "iOS Reduce Motion on -> reduced motion on at first launch")
	Game.state.data["settings"]["reducedMotion"] = false
	Game._apply_system_preferences()
	check(Game.state.data["settings"]["reducedMotion"] == false, "player's later choice is not overridden")
	Platform.use_adapter(null)


# ------------------------------------------------------------------------------------ share

func _share_tests() -> void:
	_fresh_state()
	Game.state.data["settings"]["analytics"] = true
	var An: Node = root.get_node("Analytics")
	An.clear()
	var f := FakeIOS.new()
	var a = IOSAdapter.new(f.handle)
	Platform.use_adapter(a)
	var made: Array = await _make_main(Vector2i(720, 1561))
	var main: Control = made[1]
	await _wait(0.9)
	var Card: GDScript = load("res://scripts/ui/share_card.gd")
	await Card.present(main, {"kind": "campaign", "date": "2026-10-15", "rotations": 6, "par": 6, "stars": 3, "attempts": 1, "levelName": "Test"})
	await _frames(2)
	var nb: Button = main.find_child("ShareNative", true, false)
	check(nb != null, "iOS: Share button shown when the native module is present")
	nb.pressed.emit()
	a.emit_share_closed("cancelled", "")
	await _frames(2)
	var names: Array = []
	for e in An.queued():
		names.append(str(e.get("event", "")))
	check(names.has("share_sheet_opened") and names.has("share_sheet_closed"), "sheet opened + closed (cancelled) tracked %s" % [names.slice(-4)])
	check(not names.has("share_text_copied"), "opened sheet is not also counted as a copy")
	check(a.share_closed.get_connections().is_empty(), "one-shot close handler released after the sheet closed")
	f.share_code = 0
	Card.share_native(main, "again", "", "campaign")
	Card.share_native(main, "again", "", "campaign")
	check(a.share_closed.get_connections().size() == 1, "repeated shares keep a single close handler")
	var conn: Dictionary = a.share_closed.get_connections()[0] if a.share_closed.get_connections().size() == 1 else {}
	check(conn.has("callable") and (conn["callable"] as Callable).get_object() == An, "close handler owned by the Analytics node (no free lambda left at exit)")
	a.emit_share_closed("completed", "")
	# Android: its chooser reports nothing back, so nothing may stay connected.
	var droid = load("res://scripts/platform/android_adapter.gd").new(func(_m, _a): return true)
	Platform.use_adapter(droid)
	check(Card.share_native(main, "android", "", "campaign") == Platform.OPENED and droid.share_closed.get_connections().is_empty(), "Android share leaves no pending close handler")
	Platform.use_adapter(a)
	f.share_code = 3
	var r: String = Card.share_native(main, "fallback text", "user://share/none.png", "campaign")
	check(r == Platform.INVALID_FILE and DisplayServer.clipboard_get() == "fallback text", "invalid file: falls back to copying the text")
	made[0].queue_free()
	await _frames(2)
	Platform.use_adapter(null)
