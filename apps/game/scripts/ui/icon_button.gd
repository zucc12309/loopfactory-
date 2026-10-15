class_name LFIconButton
extends Button
## Round button with a procedurally drawn vector icon (no image assets, crisp at any DPI).

var icon_name := ""
var icon_color := LFStyle.TEXT
var caption := ""
## Spoken / tooltip names for icon-only buttons.
const NAMES := {"back": "Back", "gear": "Settings", "user": "Profile", "trophy": "Leaderboards", "share": "Share", "pause": "Pause", "fast": "Speed", "play": "Play", "rotate_ccw": "Turn counter-clockwise"}


static func make(p_icon: String, p_caption := "", variation := "SecondaryButton", size := 104) -> LFIconButton:
	var b := LFIconButton.new()
	b.icon_name = p_icon
	b.caption = p_caption
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = LFStyle.focus_mode()
	LFStyle.a11y(b, p_caption if p_caption != "" else NAMES.get(p_icon, p_icon.capitalize()))
	b.icon_color = Color.WHITE if variation == "" else LFStyle.TEXT
	b.pressed.connect(func(): Sfx.play("ui"); Sfx.haptic(8))
	return b


func _draw() -> void:
	var col := icon_color if not disabled else LFStyle.TEXT_MUTED
	var area := Rect2(Vector2.ZERO, size)
	var icon_area := area
	if caption != "":
		icon_area = Rect2(Vector2(0, 0), Vector2(size.x, size.y * 0.72))
		var f := LFStyle.font(700)
		var fs := int(size.y * 0.17)
		var w := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(f, Vector2((size.x - w) / 2.0, size.y * 0.88), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	LFIcons.draw_icon(self, icon_name, icon_area, col)
