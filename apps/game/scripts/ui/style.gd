class_name LFStyle
## Design tokens and the shared Theme. Every screen uses these — no ad-hoc colors.

const BG := Color("#F7F5F0")
const SURFACE := Color("#FFFFFF")
const SURFACE_2 := Color("#EFEBE3")
const SHADOW := Color(0.149, 0.157, 0.227, 0.10)
## Primary is #5C6BC0 rather than the brief's #6674C8: white button text on #6674C8 is 4.2:1, on
## #5C6BC0 it is 4.7:1 (WCAG AA for normal text). The other brief colours are used as given.
const PRIMARY := Color("#5C6BC0")
const PRIMARY_DARK := Color("#4A57A6")
const SECONDARY := Color("#A7B8FF")
const ACCENT := Color("#FFAE76")
const SUCCESS := Color("#53C5A2")
const ERROR := Color("#E97979")
const TEXT := Color("#282B3C")
const TEXT_MUTED := Color("#6F7287")
const BELT := Color("#C9CEE8")
const BELT_EDGE := Color("#AEB5DA")
const BLOCKED := Color("#DDD8CC")

## Package colors: tangerine, sky, violet, teal. Each also has a symbol for colorblind mode.
const PACKAGE := [Color("#F28B66"), Color("#4F9BEA"), Color("#9C7BDB"), Color("#3FB596")]
const PACKAGE_NAMES := ["orange", "blue", "purple", "teal"]
const SYMBOLS := ["circle", "square", "triangle", "diamond"]

const RADIUS := 18
const RADIUS_SM := 12

const DIFFICULTY_COLORS := {
	"beginner": Color("#65C9A4"), "easy": Color("#7FB8E8"), "medium": Color("#A7B8FF"),
	"hard": Color("#FFB86B"), "expert": Color("#E97878"),
}

static var _fonts := {}
static var _theme: Theme


static func font(weight := 700) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var path := "res://assets/fonts/nunito-latin-%d-normal.woff2" % weight
	var f: Font = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	_fonts[weight] = f
	return f


static func box(color: Color, radius := RADIUS, shadow := true, border := Color.TRANSPARENT, border_w := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if shadow:
		sb.shadow_color = SHADOW
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 3)
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font(700)
	t.default_font_size = 28
	# Buttons (primary by default)
	t.set_stylebox("normal", "Button", box(PRIMARY))
	t.set_stylebox("hover", "Button", box(PRIMARY.lightened(0.06)))
	t.set_stylebox("pressed", "Button", box(PRIMARY_DARK, RADIUS, false))
	t.set_stylebox("disabled", "Button", box(SURFACE_2, RADIUS, false))
	t.set_stylebox("focus", "Button", focus_ring())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_MUTED)
	t.set_font_size("font_size", "Button", 30)
	# Secondary button variation
	t.add_type("SecondaryButton")
	t.set_type_variation("SecondaryButton", "Button")
	t.set_stylebox("normal", "SecondaryButton", box(SURFACE))
	t.set_stylebox("hover", "SecondaryButton", box(SURFACE.darkened(0.02)))
	t.set_stylebox("pressed", "SecondaryButton", box(SURFACE_2, RADIUS, false))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "SecondaryButton", TEXT)
	# Accent button variation
	t.add_type("AccentButton")
	t.set_type_variation("AccentButton", "Button")
	t.set_stylebox("normal", "AccentButton", box(ACCENT))
	t.set_stylebox("hover", "AccentButton", box(ACCENT.lightened(0.05)))
	t.set_stylebox("pressed", "AccentButton", box(ACCENT.darkened(0.08), RADIUS, false))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "AccentButton", TEXT)
	# Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 28)
	# Panels / cards
	t.set_stylebox("panel", "PanelContainer", box(SURFACE))
	t.set_stylebox("panel", "Panel", box(SURFACE))
	# Line edit
	var le := box(SURFACE, RADIUS_SM, false, SECONDARY, 2)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", box(SURFACE, RADIUS_SM, false, PRIMARY, 3))
	t.set_color("font_color", "LineEdit", TEXT)
	# CheckButton text
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", TEXT)
	t.set_color("font_pressed_color", "CheckButton", TEXT)
	t.set_color("font_hover_pressed_color", "CheckButton", TEXT)
	t.set_color("font_focus_color", "CheckButton", TEXT)
	t.set_font_size("font_size", "CheckButton", 28)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckButton", focus_ring())
	t.set_icon("checked", "CheckButton", _switch_icon(true))
	t.set_icon("unchecked", "CheckButton", _switch_icon(false))
	# Scroll bars: slim
	var grabber := box(SECONDARY, 6, false)
	grabber.content_margin_left = 3
	grabber.content_margin_right = 3
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	_theme = t
	return t


## Large, high-contrast toggle switch drawn into an image (no asset files).
static func _switch_icon(on: bool) -> ImageTexture:
	var w := 84
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := PRIMARY if on else Color("#D6D2C8")
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var r := h / 2.0
			var cx := clampf(p.x, r, w - r)
			var d := p.distance_to(Vector2(cx, r))
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			var col := track
			var knob_c := Vector2(w - r if on else r, r)
			var kd := p.distance_to(knob_c)
			var ka := clampf((r - 5.0) - kd + 0.5, 0.0, 1.0)
			col = col.lerp(Color.WHITE, ka)
			col.a = a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func label(text: String, size := 28, color := TEXT, weight := 700, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if weight != 700:
		l.add_theme_font_override("font", font(weight))
	l.horizontal_alignment = align
	return l


## Keyboard / D-pad navigation (audit U2). Touch-only play keeps focus rings hidden (a tap must not
## leave a ring behind); the first key or D-pad press switches every control to focusable, shows a
## visible ring and focuses the first control (main.gd).
static var keyboard_nav := false


static func set_keyboard_nav(on: bool) -> void:
	keyboard_nav = on


static func focus_mode() -> int:
	return Control.FOCUS_ALL if keyboard_nav else Control.FOCUS_NONE


static func focus_ring() -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.set_border_width_all(5)
	f.border_color = ACCENT
	f.set_corner_radius_all(RADIUS + 4)
	f.set_expand_margin_all(5)
	return f


## Accessible name for a control: tooltip (desktop) and, on engines with screen-reader support
## (Godot 4.5+ AccessKit), the accessibility name. Screen-reader behaviour is NOT verified on a phone.
static func a11y(c: Control, name: String) -> Control:
	c.tooltip_text = name
	if "accessibility_name" in c:
		c.set("accessibility_name", name)
	return c


static func button(text: String, variation := "", height := 96) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	if variation != "":
		b.theme_type_variation = variation
	b.focus_mode = focus_mode()
	b.pressed.connect(func(): Sfx.play("ui"); Sfx.haptic(8))
	return b


static func card(color := SURFACE, radius := RADIUS) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, radius))
	return p


static func vbox(sep := 16) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 16) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func margin(node: Control, l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	m.add_child(node)
	return m


static func spacer(h := 0, expand := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Draw a colorblind symbol (or plain dot) centred at `c`.
static func draw_symbol(ci: CanvasItem, kind: String, c: Vector2, r: float, color: Color) -> void:
	match kind:
		"circle":
			ci.draw_circle(c, r, color)
		"square":
			ci.draw_rect(Rect2(c - Vector2(r, r) * 0.85, Vector2(r, r) * 1.7), color)
		"triangle":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.05), c + Vector2(r, r * 0.8), c + Vector2(-r, r * 0.8)]), color)
		"diamond":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.1), c + Vector2(r * 1.1, 0), c + Vector2(0, r * 1.1), c + Vector2(-r * 1.1, 0)]), color)
