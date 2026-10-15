extends LFScreen
## Audio, haptics, accessibility, privacy, sync and account management.


func setup(_args: Dictionary) -> void:
	var sm: Vector2 = main.safe_margins()
	var root := LFStyle.vbox(22)
	var m := LFStyle.margin(root, 32, 32 + int(sm.x), 32, 32 + int(sm.y))
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	root.add_child(header("Settings"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var v := LFStyle.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	v.add_child(_section("Feel"))
	v.add_child(_toggle("Sound effects", "sfx"))
	v.add_child(_toggle("Vibration", "haptics"))
	v.add_child(_section("Accessibility"))
	v.add_child(_toggle("Reduce motion", "reducedMotion"))
	v.add_child(_toggle("Color symbols (colorblind aid)", "colorblind"))
	var tip := LFStyle.label("Tip: long-press a belt to rotate it counter-clockwise.", 22, LFStyle.TEXT_MUTED, 400)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tip)
	v.add_child(_section("Privacy & data"))
	v.add_child(_toggle("Share anonymous gameplay stats", "analytics"))
	v.add_child(_toggle("Cloud sync", "cloudSync"))
	var export_btn := LFStyle.button("Export my data", "SecondaryButton", 90)
	export_btn.pressed.connect(_export)
	v.add_child(export_btn)
	var policy := LFStyle.button("Privacy policy", "SecondaryButton", 90)
	policy.pressed.connect(func(): OS.shell_open(str(Net.client_config().get("privacyPolicyUrl", "https://loopfactory.example/privacy"))))
	v.add_child(policy)
	v.add_child(_section("Account"))
	var del := LFStyle.button("Delete account & data", "SecondaryButton", 90)
	del.add_theme_color_override("font_color", LFStyle.ERROR)
	del.pressed.connect(func(): main.confirm("Delete everything?", "This permanently deletes your progress on this device and on our servers. It cannot be undone.", "Delete", _delete, true))
	v.add_child(del)
	v.add_child(LFStyle.label("Loop Factory %s" % ProjectSettings.get_setting("application/config/version", ""), 20, LFStyle.TEXT_MUTED, 400, HORIZONTAL_ALIGNMENT_CENTER))


func _section(text: String) -> Label:
	var l := LFStyle.label(text.to_upper(), 22, LFStyle.PRIMARY, 800)
	l.custom_minimum_size = Vector2(0, 56)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


func _toggle(text: String, key: String) -> Control:
	var card := LFStyle.card(LFStyle.SURFACE, 16)
	var cb := CheckButton.new()
	cb.text = text
	cb.button_pressed = bool(Game.settings().get(key, false))
	cb.focus_mode = Control.FOCUS_NONE
	cb.custom_minimum_size = Vector2(0, 64)
	cb.toggled.connect(func(on):
		Sfx.play("ui")
		Game.set_setting(key, on)
		if key == "analytics" and not on:
			Analytics.clear())
	card.add_child(cb)
	return card


func _export() -> void:
	var data = await Net.export_data()
	var payload: Dictionary = {"local": Game.state.data.duplicate(true)}
	payload["local"]["auth"] = {"playerId": Game.state.data["auth"].get("playerId", "")}  # never export tokens
	if data != null:
		payload["server"] = data
	var path := "user://loop-factory-export.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(payload, "  "))
	f.close()
	main.toast("Saved to %s%s" % [ProjectSettings.globalize_path(path), "" if data != null else " (device data only — offline)"], LFStyle.PRIMARY, 4.0)


func _delete() -> void:
	var ok = await Net.delete_account()
	if ok:
		main.toast("All data deleted.", LFStyle.PRIMARY)
		main.home()
	else:
		main.toast("Couldn't reach the server. Connect and try again so we can delete your cloud data too.", LFStyle.ERROR, 3.5)
