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
	v.add_child(_toggle("Music", "music"))
	v.add_child(_toggle("Vibration", "haptics"))
	v.add_child(_section("Accessibility"))
	v.add_child(_toggle("Reduce motion", "reducedMotion"))
	v.add_child(_toggle("Larger shape symbols", "colorblind"))
	var data: Dictionary = Game.state.data
	if LFFlags.flag(data, "characters_enabled") and str(LFFlags.resolve(data, "presentation")) != "minimal":
		v.add_child(_section("The Crew"))
		v.add_child(_toggle("Character packages", "crewCharacters"))
		v.add_child(_toggle("Character animations", "crewAnimations"))
		v.add_child(_toggle("Captain Naps chatter", "mascotDialogue"))
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
	policy.pressed.connect(func(): _open_url("privacyPolicyUrl", "The privacy policy link isn't set in this test build."))
	v.add_child(policy)
	var support := LFStyle.button("Help & support", "SecondaryButton", 90)
	support.pressed.connect(func(): _open_url("supportUrl", "The support link isn't set in this test build."))
	v.add_child(support)
	v.add_child(_section("Account"))
	var acct := LFStyle.label(account_status(Game.state.data), 22, LFStyle.TEXT_MUTED, 400)
	acct.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	acct.name = "AccountStatus"
	v.add_child(acct)
	var del := LFStyle.button("Delete account & data", "SecondaryButton", 90)
	del.add_theme_color_override("font_color", LFStyle.ERROR)
	del.pressed.connect(func(): main.confirm("Delete everything?", "This permanently deletes your progress on this device and on our servers. It cannot be undone.", "Delete", _delete, true))
	v.add_child(del)
	var cfg := LFReleaseConfig.load_client()
	var ver := LFStyle.label("Loop Factory %s (build %d, %s)" % [ProjectSettings.get_setting("application/config/version", ""), int(cfg.get("build", 0)), str(cfg.get("environment", "development"))], 20, LFStyle.TEXT_MUTED, 400, HORIZONTAL_ALIGNMENT_CENTER)
	ver.name = "VersionLabel"
	ver.mouse_filter = Control.MOUSE_FILTER_STOP
	ver.gui_input.connect(_on_version_input)
	v.add_child(ver)


## Plain statement of what survives what (audit R5). No sign-in/restore flow ships in this beta,
## so nothing here promises that progress survives an uninstall.
static func account_status(data: Dictionary) -> String:
	var auth: Dictionary = data.get("auth", {})
	var pid := str(auth.get("playerId", ""))
	var support := ("Support ID: %s. " % pid.substr(0, 8)) if pid.length() >= 8 else ""
	if bool(auth.get("linked", false)):
		return support + "Your account is linked, so it can be restored after reinstalling."
	return support + "You're playing as a guest. Progress is saved on this device and kept through app updates. Uninstalling the app or clearing its data erases it, and guest accounts can't be restored yet."


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
	cb.focus_mode = LFStyle.focus_mode()
	LFStyle.a11y(cb, text)
	cb.custom_minimum_size = Vector2(0, 64)
	cb.toggled.connect(func(on):
		Sfx.play("ui")
		Game.set_setting(key, on)
		if key == "analytics" and not on:
			Analytics.clear())
	card.add_child(cb)
	return card


func _open_url(key: String, missing: String) -> void:
	var u := str(LFReleaseConfig.load_client().get(key, ""))
	if u == "" or LFReleaseConfig.url_problem(u, false) != "":
		main.toast(missing, LFStyle.TEXT_MUTED, 3.0)
		return
	OS.shell_open(u)


var _version_taps := 0


## Seven taps on the version line record a diagnostic test event (docs: verifying monitoring).
func _on_version_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	_version_taps += 1
	if _version_taps >= 7:
		_version_taps = 0
		LFDiagnostics.record("diagnostic_test", false, {"source": "settings"})
		main.toast("Test diagnostic recorded (%d stored on this device)." % LFDiagnostics.read_all().size(), LFStyle.PRIMARY, 3.0)


func _export() -> void:
	var data = await Net.export_data()
	var payload: Dictionary = {"local": Game.state.data.duplicate(true), "diagnostics": LFDiagnostics.read_all()}
	payload["local"]["auth"] = {"playerId": Game.state.data["auth"].get("playerId", "")}  # never export tokens
	if data != null:
		payload["server"] = data
	var json := JSON.stringify(payload, "  ")
	var note := "" if data != null else " (device data only — offline)"
	# Phones: hand the file to the share sheet (save to Files/Drive, email…). A private app path is
	# never shown as if the player could open it. Desktop: write it to Documents.
	var path := "user://loop-factory-export.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(json)
	f.close()
	if LFShare.native_available():
		if LFShare.share("Loop Factory data export", path, "application/json", "Save your data") == LFShare.OPENED:
			main.toast("Choose where to save your data%s." % note, LFStyle.PRIMARY, 3.0)
			return
	if not OS.has_feature("mobile"):
		var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		if docs != "" and DirAccess.dir_exists_absolute(docs):
			var out := docs.path_join("loop-factory-export.json")
			var g := FileAccess.open(out, FileAccess.WRITE)
			if g != null:
				g.store_string(json)
				g.close()
				main.toast("Saved to %s%s" % [out, note], LFStyle.PRIMARY, 4.0)
				return
	DisplayServer.clipboard_set(json)
	main.toast("Your data was copied to the clipboard%s. Paste it into a note or email to keep it." % note, LFStyle.PRIMARY, 4.0)


func _delete() -> void:
	var ok = await Net.delete_account()
	if ok:
		main.toast("All data deleted.", LFStyle.PRIMARY)
		main.home()
	else:
		main.toast("Couldn't reach the server. Connect and try again so we can delete your cloud data too.", LFStyle.ERROR, 3.5)
