extends Control
## Root router: screen stack, transitions, toasts, modal overlays, Android back button.

const SCREENS := {
	"splash": "res://scripts/ui/screens/splash.gd",
	"home": "res://scripts/ui/screens/home.gd",
	"levels": "res://scripts/ui/screens/levels.gd",
	"play": "res://scripts/ui/screens/play.gd",
	"daily": "res://scripts/ui/screens/daily.gd",
	"profile": "res://scripts/ui/screens/profile.gd",
	"settings": "res://scripts/ui/screens/settings.gd",
	"replay": "res://scripts/ui/screens/replay.gd",
	"challenge": "res://scripts/ui/screens/challenge.gd",
	"crew": "res://scripts/ui/screens/crew.gd",
}

var current: LFScreen
var current_name := ""
var _stack: Array = []
var _layer: Control
var _overlay_layer: Control
var _toast_layer: Control
var _bg: ColorRect
var _overlay_back := Callable()


func _ready() -> void:
	theme = LFStyle.theme()
	get_tree().set_auto_accept_quit(false)
	get_tree().set_quit_on_go_back(false)
	_bg = ColorRect.new()
	_bg.color = LFStyle.BG
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_layer = Control.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_layer)
	_overlay_layer = Control.new()
	_overlay_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay_layer)
	_toast_layer = Control.new()
	_toast_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_layer)
	Game.achievements_unlocked.connect(_on_achievements)
	Game.cosmetics_unlocked.connect(_on_cosmetics)
	goto("splash", {}, false)
	_check_build_config.call_deferred()
	if Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--tour=")):
		add_child(load("res://scripts/core/dev_tour.gd").new())


## Challenge code from an App Link (via the share plugin), a launch argument
## (`--challenge=CODE`, `loopfactory://challenge/CODE`, `https://<host>/c/CODE`), or a code saved
## while offline. Invalid codes are dropped here, before any request. Android App Links only reach
## an INSTALLED app (and only once the domain is verified, docs/sharing.md); they do not survive an
## install from the store, so the landing page always shows the code for manual entry.
func launch_challenge_code() -> String:
	var uri := LFShare.launch_uri()
	if uri != "":
		Analytics.track("challenge_link_opened", {"source": "app_link"})
		var c := LFShare.parse_challenge(uri)
		if c != "":
			return c
	var args := Array(OS.get_cmdline_args()) + Array(OS.get_cmdline_user_args())
	for a in args:
		var s := str(a)
		if s.begins_with("--challenge=") or s.begins_with("loopfactory://") or (s.begins_with("http") and s.contains("/c/")):
			var code := LFShare.parse_challenge(s)
			if code != "":
				Analytics.track("challenge_link_opened", {"source": "launch_argument"})
				return code
	return str(Game.state.data["challenges"].get("pending", ""))


## First keyboard / D-pad input: make every control focusable and focus the first one.
func _input(event: InputEvent) -> void:
	if LFStyle.keyboard_nav:
		return
	if (event is InputEventKey and event.pressed) or (event is InputEventJoypadButton and event.pressed):
		enable_keyboard_nav()


func enable_keyboard_nav() -> void:
	LFStyle.set_keyboard_nav(true)
	var first: Control = null
	for c in find_children("*", "BaseButton", true, false) + find_children("*", "LineEdit", true, false):
		var ctl := c as Control
		ctl.focus_mode = Control.FOCUS_ALL
		if first == null and ctl.is_visible_in_tree() and not (ctl is BaseButton and (ctl as BaseButton).disabled):
			first = ctl
	if first != null:
		first.grab_focus()


## A staging build with a broken config or no error monitoring says so on screen, so testers never
## assume problems are being collected. (Release builds can't be produced with an invalid config:
## scripts/client-config.ts fails the build.) Problems are also recorded as diagnostics.
func _check_build_config() -> void:
	var cfg := LFReleaseConfig.load_client()
	var errs := LFReleaseConfig.validate(cfg)
	var mon := LFDiagnostics.monitoring_status(cfg)
	if errs.is_empty() and (mon == "ok" or mon == "not_configured"):
		return
	LFDiagnostics.record("config", false, {"problems": errs.size(), "monitoring": mon})
	if str(cfg.get("environment", "")) == "staging":
		var what := ("config: " + str(errs[0])) if not errs.is_empty() else ("error monitoring " + mon)
		toast("Staging build problem — %s" % what, LFStyle.ERROR, 6.0)


## Optional analytics consent is due once: after the first completed puzzle, if never answered.
func consent_due() -> bool:
	return not bool(Game.settings().get("analyticsAsked", false)) and not Game.state.data["progress"].is_empty() and _overlay_layer.get_child_count() == 0


## The consent card. Both answers are one tap; Back dismisses without answering (asked again later).
func ask_consent() -> void:
	if not consent_due():
		return
	var card := LFStyle.card()
	card.name = "ConsentCard"
	var v := LFStyle.vbox(18)
	card.add_child(LFStyle.margin(v, 16, 16, 16, 16))
	v.add_child(LFStyle.label("Help us tune the puzzles?", 36, LFStyle.TEXT, 800))
	var body := LFStyle.label("Share anonymous gameplay stats (levels played, retries, hints). No name, contacts, location or ad tracking. You can change this any time in Settings.", 25, LFStyle.TEXT_MUTED, 400)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)
	var r := LFStyle.hbox(16)
	var no := LFStyle.button("No thanks", "SecondaryButton", 88)
	var yes := LFStyle.button("Share stats", "", 88)
	no.name = "ConsentNo"
	yes.name = "ConsentYes"
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(func(): answer_consent(false))
	yes.pressed.connect(func(): answer_consent(true))
	r.add_child(no)
	r.add_child(yes)
	v.add_child(r)
	overlay(card, false)


func answer_consent(v: bool) -> void:
	Game.set_setting("analyticsAsked", true)
	Game.set_setting("analytics", v)
	close_overlay()


func reduced_motion() -> bool:
	return bool(Game.settings().get("reducedMotion", false))


## Safe-area top/bottom padding in viewport units (notches, gesture bars).
func safe_margins() -> Vector2:
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if screen.y <= 0 or safe.size.y <= 0:
		return Vector2(0, 0)
	var scale := get_viewport_rect().size.y / float(screen.y)
	return Vector2(safe.position.y * scale, (screen.y - safe.end.y) * scale)


func goto(name: String, args := {}, push := true) -> void:
	if push and current_name != "" and current_name != "splash":
		_stack.append([current_name, current.get_meta("args", {})])
	_show(name, args, 1)


func replace(name: String, args := {}) -> void:
	_show(name, args, 1)


func back() -> void:
	if _overlay_layer.get_child_count() > 0:
		var cb := _overlay_back
		close_overlay()
		if cb.is_valid():
			cb.call()
		return
	if current and current.on_back():
		return
	if _stack.is_empty():
		if current_name == "home":
			Game.save_now()
			get_tree().quit()
			return
		_show("home", {}, -1)
		return
	var prev: Array = _stack.pop_back()
	_show(prev[0], prev[1], -1)


func home() -> void:
	_stack.clear()
	_show("home", {}, -1)


func _show(name: String, args: Dictionary, direction: int) -> void:
	# Toasts belong to the screen that raised them.
	for c in _toast_layer.get_children():
		c.queue_free()
	var old := current
	var scr: LFScreen = load(SCREENS[name]).new()
	scr.main = self
	scr.set_meta("args", args)
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(scr)
	scr.setup(args)
	if LFStyle.keyboard_nav:
		for c in scr.find_children("*", "BaseButton", true, false):
			(c as Control).focus_mode = Control.FOCUS_ALL
	current = scr
	current_name = name
	if old:
		old.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if reduced_motion():
			old.queue_free()
		else:
			var w := get_viewport_rect().size.x
			scr.position.x = w * 0.08 * direction
			scr.modulate.a = 0.0
			var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(scr, "position:x", 0.0, 0.22)
			tw.tween_property(scr, "modulate:a", 1.0, 0.18)
			tw.tween_property(old, "modulate:a", 0.0, 0.12)
			tw.chain().tween_callback(old.queue_free)
	scr.on_shown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		Game.save_now()
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		back()


# ----------------------------------------------------------------- toasts & overlays

func toast(text: String, color := LFStyle.TEXT, duration := 2.2) -> void:
	for c in _toast_layer.get_children():
		c.queue_free()
	var vw := get_viewport_rect().size
	var card := LFStyle.card(color, 40)
	var l := LFStyle.label(text, 26, Color.WHITE, 700, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(vw.x - 96 - 40, 0)
	card.add_child(l)
	_toast_layer.add_child(card)
	card.reset_size()
	# Toasts sit at the top edge so they never cover the board or the controls under the thumb.
	card.position = Vector2(48, 20 + safe_margins().x)
	card.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.15)
	tw.tween_interval(duration)
	tw.tween_property(card, "modulate:a", 0.0, 0.25)
	tw.tween_callback(card.queue_free)


## Full-screen dimmed modal hosting `content` (centred card). Returns the dim node.
func overlay(content: Control, dismissable := true, on_back := Callable()) -> Control:
	close_overlay()
	_overlay_back = on_back
	_overlay_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(LFStyle.TEXT, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_layer.add_child(dim)
	if dismissable:
		dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close_overlay())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(center)
	content.custom_minimum_size.x = get_viewport_rect().size.x - 80
	center.add_child(content)
	if not reduced_motion():
		content.pivot_offset = content.custom_minimum_size / 2
		content.scale = Vector2(0.92, 0.92)
		content.modulate.a = 0.0
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(content, "scale", Vector2.ONE, 0.25)
		tw.tween_property(content, "modulate:a", 1.0, 0.15)
	return dim


func has_overlay() -> bool:
	return _overlay_layer.get_child_count() > 0


func close_overlay() -> void:
	_overlay_back = Callable()
	for c in _overlay_layer.get_children():
		c.queue_free()
	_overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE


func confirm(title: String, body: String, ok_text: String, on_ok: Callable, danger := false) -> void:
	var card := LFStyle.card()
	var v := LFStyle.vbox(20)
	card.add_child(LFStyle.margin(v, 16, 16, 16, 16))
	v.add_child(LFStyle.label(title, 38, LFStyle.TEXT, 800))
	var b := LFStyle.label(body, 26, LFStyle.TEXT_MUTED, 400)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(b)
	var row := LFStyle.hbox(16)
	var cancel := LFStyle.button("Cancel", "SecondaryButton", 88)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(close_overlay)
	var ok := LFStyle.button(ok_text, "", 88)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if danger:
		ok.add_theme_stylebox_override("normal", LFStyle.box(LFStyle.ERROR))
		ok.add_theme_stylebox_override("hover", LFStyle.box(LFStyle.ERROR.lightened(0.05)))
	ok.pressed.connect(func(): close_overlay(); on_ok.call())
	row.add_child(cancel)
	row.add_child(ok)
	v.add_child(row)
	overlay(card)


## New crew looks: one short toast, no popup. Details wait in The Crew (a dot marks them).
func _on_cosmetics(list: Array) -> void:
	for d in list:
		Analytics.track("cosmetic_unlocked", {"cosmetic_id": str(d["id"]), "character": str(d.get("character", ""))})
	if not LFCrew.current()["collection"]:
		return
	var d: Dictionary = list[0]
	var who := str(LFCrew.get_def(str(d.get("character", ""))).get("name", "")) if str(d.get("character", "")) != "" else "the crew"
	var more := "" if list.size() == 1 else " (+%d more)" % (list.size() - 1)
	# Let an achievement toast raised in the same frame finish first.
	var delay := 3.0 if _toast_layer.get_child_count() > 0 else 0.4
	get_tree().create_timer(delay).timeout.connect(func():
		Sfx.play("unlock")
		toast("New look for %s · %s%s" % [who, d["name"], more], LFStyle.PRIMARY, 2.6))


func _on_achievements(list: Array) -> void:
	for a in list:
		Sfx.play("unlock")
		toast("Achievement unlocked · " + str(a["title"]), LFStyle.PRIMARY, 2.6)
