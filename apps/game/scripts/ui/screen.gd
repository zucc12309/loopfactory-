class_name LFScreen
extends Control
## Base class for screens. `main` is the router (scripts/ui/main.gd).

var main: Node


func setup(_args: Dictionary) -> void:
	pass


## Return true if the screen handled the back action itself.
func on_back() -> bool:
	return false


func on_shown() -> void:
	pass


## Standard header: back button + title (+ optional right-side control).
func header(title: String, right: Control = null) -> HBoxContainer:
	var h := LFStyle.hbox(16)
	var back := LFIconButton.make("back", "", "SecondaryButton", 88)
	back.pressed.connect(func(): main.back())
	h.add_child(back)
	var l := LFStyle.label(title, 40, LFStyle.TEXT, 800)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	if right:
		h.add_child(right)
	return h
