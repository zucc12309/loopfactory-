extends LFScreen
## Daily challenge: the official, server-published puzzle (ranked) — or, when it cannot be
## downloaded, a clearly-labelled offline practice puzzle that is never presented as official.

var _content: VBoxContainer
var _board_holder: Control
var _lb: VBoxContainer
var _date := ""


func setup(_args: Dictionary) -> void:
	_date = LFGameState.utc_date()
	var sm: Vector2 = main.safe_margins()
	var root := LFStyle.vbox(22)
	var m := LFStyle.margin(root, 32, 32 + int(sm.x), 32, 32 + int(sm.y))
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	root.add_child(header("Daily puzzle"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_content = LFStyle.vbox(22)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	_content.add_child(LFStyle.label("Loading today's puzzle…", 26, LFStyle.TEXT_MUTED, 400))
	_load()


func _load() -> void:
	var entry = await Net.fetch_daily(_date)
	if not is_inside_tree():
		return
	for c in _content.get_children():
		c.queue_free()
	if entry != null:
		_render_official(entry)
	else:
		_render_offline()


func _render_official(entry: Dictionary) -> void:
	var lvl: Dictionary = entry["level"]
	_presenter(Game.state.data["daily"]["results"].has(_date))
	var card := LFStyle.card()
	var v := LFStyle.vbox(12)
	card.add_child(LFStyle.margin(v, 8, 8, 8, 8))
	v.add_child(LFStyle.label(_date + " · UTC", 24, LFStyle.TEXT_MUTED, 700))
	v.add_child(LFStyle.label(str(entry.get("tier", lvl.get("difficulty", ""))).capitalize() + " · par %d" % lvl["par"], 36, LFStyle.TEXT, 800))
	var res = Game.state.data["daily"]["results"].get(_date)
	var status := "Not solved yet — everyone gets the same puzzle today. Fewest rotations wins; hints are off."
	if res != null:
		var tries := int(res.get("attempts", 0))
		status = "Your best: %d rotations%s%s" % [res["rotations"], (" · %d tr%s" % [tries, "y" if tries == 1 else "ies"]) if tries > 0 else "", "" if res.get("submitted", false) else " (will upload when online)"]
	var sl := LFStyle.label(status, 24, LFStyle.TEXT_MUTED, 400)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sl)
	var play := LFStyle.button("Play today's puzzle" if res == null else "Play again", "", 100)
	play.pressed.connect(func(): main.goto("play", {"kind": "daily", "level": lvl, "date": _date}))
	v.add_child(play)
	_content.add_child(card)
	_content.add_child(LFStyle.label("Leaderboard", 34, LFStyle.TEXT, 800))
	_lb = LFStyle.vbox(8)
	_content.add_child(_lb)
	_lb.add_child(LFStyle.label("Loading…", 24, LFStyle.TEXT_MUTED, 400))
	var data = await Net.daily_leaderboard(_date)
	if not is_inside_tree():
		return
	for c in _lb.get_children():
		c.queue_free()
	if data == null:
		_lb.add_child(LFStyle.label("Leaderboard unavailable offline.", 24, LFStyle.TEXT_MUTED, 400))
		return
	var entries: Array = data.get("entries", [])
	if entries.is_empty():
		_lb.add_child(LFStyle.label("No solves yet. Be the first!", 24, LFStyle.TEXT_MUTED, 400))
	for e in entries:
		_lb.add_child(_row(int(e["rank"]), str(e["displayName"]), int(e["rotations"]), bool(e.get("isMe", false))))
	var me = data.get("me")
	if me != null and int(me.get("rank", 0)) > entries.size():
		_lb.add_child(_row(int(me["rank"]), "You", int(me["rotations"]), true))


func _row(rank: int, name: String, rotations: int, me: bool) -> Control:
	var card := LFStyle.card(LFStyle.SECONDARY.lightened(0.6) if me else LFStyle.SURFACE, 14)
	var h := LFStyle.hbox(16)
	card.add_child(h)
	h.add_child(LFStyle.label("#%d" % rank, 26, LFStyle.PRIMARY, 800))
	var n := LFStyle.label(name, 26, LFStyle.TEXT, 700)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	h.add_child(n)
	h.add_child(LFStyle.label("%d" % rotations, 26, LFStyle.TEXT, 800))
	return card


## Captain Naps presents today's puzzle (optional line; the puzzle and ranking are unchanged).
func _presenter(solved: bool) -> void:
	if not LFCrew.current()["characters"]:
		return
	var row := LFStyle.hbox(12)
	var p := LFCrewPortrait.make("naps", 120, LFCrew.current()["animations"])
	p.cosmetic = LFCrew.art_for(Game.state.data, "naps")
	row.add_child(p)
	var line := LFCrew.say("DAILY_CHALLENGE", {"solved": solved})
	if not line.is_empty():
		p.expression = str(line.get("anim", "neutral"))
		var bubble := LFStyle.card(LFStyle.SURFACE, 20)
		bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var l := LFStyle.label("“%s”" % line["text"], 24, LFStyle.TEXT, 700)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bubble.add_child(l)
		row.add_child(bubble)
	_content.add_child(row)
	LFCrew.expose("daily", {"character": "naps"})


func _render_offline() -> void:
	_presenter(Game.state.data["daily"]["results"].has(_date))
	var card := LFStyle.card(LFStyle.ACCENT.lightened(0.6))
	var v := LFStyle.vbox(12)
	card.add_child(LFStyle.margin(v, 8, 8, 8, 8))
	v.add_child(LFStyle.label("Offline practice", 36, LFStyle.TEXT, 800))
	var l := LFStyle.label("Today's official daily puzzle couldn't be downloaded. Here's a practice puzzle for %s instead — it is not the ranked daily and won't appear on leaderboards." % _date, 24, LFStyle.TEXT, 400)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	var play := LFStyle.button("Play practice puzzle", "", 100)
	play.pressed.connect(func():
		var lvl = LFGameState.offline_daily_level(_date)
		if lvl == null:
			main.toast("Couldn't build a practice puzzle.")
			return
		lvl["date"] = _date
		main.goto("play", {"kind": "offline_daily", "level": lvl, "date": _date}))
	v.add_child(play)
	var retry := LFStyle.button("Try download again", "SecondaryButton", 90)
	retry.pressed.connect(func():
		for c in _content.get_children():
			c.queue_free()
		_load())
	v.add_child(retry)
	_content.add_child(card)
