extends LFScreen
## Minimal splash: brand mark, then straight to Home (no artificial loading).


func setup(_args: Dictionary) -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := LFStyle.vbox(24)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)
	var logo := LFLogo.new()
	logo.custom_minimum_size = Vector2(260, 260)
	v.add_child(logo)
	v.add_child(LFStyle.label("Loop Factory", 56, LFStyle.TEXT, 800, HORIZONTAL_ALIGNMENT_CENTER))
	get_tree().create_timer(0.15 if main.reduced_motion() else 0.7).timeout.connect(_go)


func _go() -> void:
	main.replace("home")
	var code: String = main.launch_challenge_code()
	if code != "":
		main.goto("challenge", {"code": code})
