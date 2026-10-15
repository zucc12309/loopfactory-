extends LFScreen
## Guest profile, statistics, achievements, account linking and sync status.


func setup(_args: Dictionary) -> void:
	var sm: Vector2 = main.safe_margins()
	var root := LFStyle.vbox(22)
	var m := LFStyle.margin(root, 32, 32 + int(sm.x), 32, 32 + int(sm.y))
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	root.add_child(header("Profile"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var v := LFStyle.vbox(22)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var st: LFGameState = Game.state
	var auth: Dictionary = st.data["auth"]

	# Identity card
	var id_card := LFStyle.card()
	var iv := LFStyle.vbox(12)
	id_card.add_child(LFStyle.margin(iv, 8, 8, 8, 8))
	var name := str(auth.get("displayName", ""))
	iv.add_child(LFStyle.label(name if name != "" else "Guest", 40, LFStyle.TEXT, 800))
	iv.add_child(LFStyle.label("Linked account" if auth.get("linked", false) else "Guest profile · no sign-up needed", 24, LFStyle.TEXT_MUTED, 400))
	var name_row := LFStyle.hbox(12)
	var edit := LineEdit.new()
	edit.placeholder_text = "Leaderboard name"
	edit.max_length = 20
	edit.text = name
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 84)
	name_row.add_child(edit)
	var save := LFStyle.button("Save", "", 84)
	save.pressed.connect(func():
		var ok = await Net.update_display_name(edit.text.strip_edges())
		main.toast("Name saved." if ok else "Couldn't save the name — are you online?", LFStyle.PRIMARY if ok else LFStyle.ERROR))
	name_row.add_child(save)
	iv.add_child(name_row)
	# No sign-in plugin ships in this beta, so there is no "Link account" button that would lead
	# nowhere (audit R5). The status says plainly what survives an uninstall.
	var acct := LFStyle.label(load("res://scripts/ui/screens/settings.gd").account_status(st.data), 22, LFStyle.TEXT_MUTED, 400)
	acct.name = "AccountStatus"
	acct.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iv.add_child(acct)
	v.add_child(id_card)

	# Stats
	v.add_child(LFStyle.label("Statistics", 34, LFStyle.TEXT, 800))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	var s: Dictionary = st.data["stats"]
	for pair in [["Campaign", "%d/%d" % [st.completed_count(), st.campaign.size()]], ["Perfect solves", str(s["perfect"])], ["Daily puzzles", str(s["dailies"])], ["Endless", str(s["endless"])], ["Rotations", str(s["rotations"])], ["Hints used", str(s["hints"])]]:
		var c := LFStyle.card()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := LFStyle.vbox(2)
		c.add_child(cv)
		cv.add_child(LFStyle.label(pair[1], 40, LFStyle.PRIMARY, 800))
		cv.add_child(LFStyle.label(pair[0], 22, LFStyle.TEXT_MUTED, 400))
		grid.add_child(c)
	v.add_child(grid)

	# Achievements
	v.add_child(LFStyle.label("Achievements", 34, LFStyle.TEXT, 800))
	for a in st.achievements_def:
		var got: bool = st.data["achievements"].has(a["id"])
		var c := LFStyle.card(LFStyle.SURFACE if got else LFStyle.SURFACE_2, 16)
		var h := LFStyle.hbox(16)
		c.add_child(h)
		var ic := Control.new()
		ic.custom_minimum_size = Vector2(64, 64)
		ic.draw.connect(func(): LFIcons.draw_icon(ic, "trophy" if got else "lock", Rect2(Vector2.ZERO, ic.size), LFStyle.ACCENT if got else LFStyle.TEXT_MUTED))
		h.add_child(ic)
		var tv := LFStyle.vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(LFStyle.label(a["title"], 28, LFStyle.TEXT if got else LFStyle.TEXT_MUTED, 800))
		var d := LFStyle.label(a["description"], 22, LFStyle.TEXT_MUTED, 400)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(d)
		h.add_child(tv)
		v.add_child(c)

	# Global leaderboard snapshot
	v.add_child(LFStyle.label("Global ranking", 34, LFStyle.TEXT, 800))
	var lb := LFStyle.vbox(8)
	v.add_child(lb)
	lb.add_child(LFStyle.label("Loading…", 24, LFStyle.TEXT_MUTED, 400))
	_load_lb(lb)


func _load_lb(lb: VBoxContainer) -> void:
	var data = await Net.global_leaderboard("global")
	if not is_inside_tree():
		return
	for c in lb.get_children():
		c.queue_free()
	if data == null:
		lb.add_child(LFStyle.label("Available when online.", 24, LFStyle.TEXT_MUTED, 400))
		return
	for e in data.get("entries", []):
		var row := LFStyle.hbox(12)
		row.add_child(LFStyle.label("#%d" % int(e["rank"]), 24, LFStyle.PRIMARY, 800))
		var n := LFStyle.label(str(e["displayName"]), 24, LFStyle.TEXT, 700)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		row.add_child(LFStyle.label("%d solved" % int(e["score"]), 24, LFStyle.TEXT_MUTED, 700))
		lb.add_child(row)
