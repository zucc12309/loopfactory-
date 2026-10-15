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
}

var current: LFScreen
var current_name := ""
var _stack: Array = []
var _layer: Control
var _overlay_layer: Control
var _toast_layer: Control
var _bg: ColorRect


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
	goto("splash", {}, false)
	if Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--tour=")):
		add_child(load("res://scripts/core/dev_tour.gd").new())


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
		close_overlay()
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
	var old := current
	var scr: LFScreen = load(SCREENS[name]).new()
	scr.main = self
	scr.set_meta("args", args)
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(scr)
	scr.setup(args)
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
	card.position = Vector2(48, vw.y - 260 - card.size.y - safe_margins().y)
	card.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.15)
	tw.tween_interval(duration)
	tw.tween_property(card, "modulate:a", 0.0, 0.25)
	tw.tween_callback(card.queue_free)


## Full-screen dimmed modal hosting `content` (centred card). Returns the dim node.
func overlay(content: Control, dismissable := true) -> Control:
	close_overlay()
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


func close_overlay() -> void:
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


func _on_achievements(list: Array) -> void:
	for a in list:
		Sfx.play("unlock")
		toast("Achievement unlocked · " + str(a["title"]), LFStyle.PRIMARY, 2.6)
