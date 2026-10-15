extends LFScreen
## The Crew: an optional collection. Roster → character detail with an animation preview and
## looks (cosmetics) that unlock through normal play. Nothing here is required to keep playing and
## nothing is for sale. Looks never change a package's colour or delivery symbol.
## Args: {} for the roster, {"id": "<character>"} for a detail page.

const PREVIEW := [
	["Idle", LFCrewAnim.IDLE], ["Picked", LFCrewAnim.SELECTED], ["Moving", LFCrewAnim.MOVING],
	["Waiting", LFCrewAnim.WAITING], ["Delivered", LFCrewAnim.DELIVERED], ["Oops", LFCrewAnim.FAILED],
	["Party", LFCrewAnim.CELEBRATING],
]

var _id := ""
var _portrait: LFCrewPortrait
var _looks: VBoxContainer
var _animate := true


func setup(args: Dictionary) -> void:
	_id = str(args.get("id", ""))
	_animate = LFCrew.current()["animations"]
	var sm: Vector2 = main.safe_margins()
	var root := LFStyle.vbox(20)
	var m := LFStyle.margin(root, 32, 32 + int(sm.x), 32, 32 + int(sm.y))
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := LFStyle.vbox(18)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	if _id == "":
		root.add_child(header("The Crew"))
		root.add_child(scroll)
		_roster(v)
		Analytics.track("character_collection_opened", {"unseen": LFCrew.unseen_count(Game.state.data)})
	else:
		root.add_child(header(str(LFCrew.get_def(_id).get("name", ""))))
		root.add_child(scroll)
		_detail(v)


# ----------------------------------------------------------------------------- roster

func _roster(v: VBoxContainer) -> void:
	var intro := LFStyle.label("The Interdimensional Delivery Crew. New looks unlock as you play — nothing to buy, nothing to grind.", 24, LFStyle.TEXT_MUTED, 400)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for def in LFCrew.roster():
		grid.add_child(_roster_card(def))
	v.add_child(grid)
	v.add_child(_celebration_card())


func _roster_card(def: Dictionary) -> Control:
	var data: Dictionary = Game.state.data
	var id := str(def["id"])
	var card := LFStyle.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cv := LFStyle.vbox(4)
	card.add_child(cv)
	var p := LFCrewPortrait.make(id, 170, _animate)
	p.cosmetic = LFCrew.art_for(data, id)
	p.anim_seed = id.hash() % 97
	cv.add_child(p)
	cv.add_child(LFStyle.label(str(def.get("name", id)), 30, LFStyle.TEXT, 800, HORIZONTAL_ALIGNMENT_CENTER))
	var role := LFStyle.label(str(def.get("role", "")), 20, LFStyle.TEXT_MUTED, 700, HORIZONTAL_ALIGNMENT_CENTER)
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(role)
	var cos: Array = def.get("cosmetics", [])
	var got := 0
	var fresh := 0
	for c in cos:
		if LFCrew.is_unlocked(data, str(c["id"])):
			got += 1
			if not data["crew"]["seen"].has(str(c["id"])):
				fresh += 1
	var status := "%d/%d looks" % [got, cos.size()] if not cos.is_empty() else "Appears with new machinery"
	if fresh > 0:
		status += " · New!"
	cv.add_child(LFStyle.label(status, 22, LFStyle.PRIMARY if fresh > 0 else LFStyle.TEXT_MUTED, 800, HORIZONTAL_ALIGNMENT_CENTER))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(e): if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT: Sfx.play("ui"); main.goto("crew", {"id": id}))
	return card


## Special celebration expression (unlocked by daily puzzles).
func _celebration_card() -> Control:
	var data: Dictionary = Game.state.data
	var card := LFStyle.card()
	var h := LFStyle.hbox(16)
	card.add_child(h)
	var special: Array = LFCrew.load_data()["special"]
	if special.is_empty():
		card.visible = false
		return card
	var d: Dictionary = special[0]
	var p := LFCrewPortrait.make("bloop", 110, false)
	p.state = LFCrewAnim.CELEBRATING
	p.expression = ""
	h.add_child(p)
	var tv := LFStyle.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(LFStyle.label(str(d["name"]), 28, LFStyle.TEXT, 800))
	var unlocked := LFCrew.is_unlocked(data, str(d["id"]))
	var pr := LFCrew.progress_for(d.get("unlock", {}), data, Game.state.campaign)
	var sub := LFStyle.label("Starry eyes when the crew celebrates." if unlocked else "%s · %d/%d" % [LFCrew.requirement_text(d.get("unlock", {})), mini(pr.x, pr.y), pr.y], 22, LFStyle.TEXT_MUTED, 400)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(sub)
	h.add_child(tv)
	if unlocked:
		var cb := CheckButton.new()
		cb.button_pressed = str(data["crew"].get("celebration", "")) == str(d["id"])
		cb.focus_mode = LFStyle.focus_mode()
		cb.toggled.connect(func(on):
			LFCrew.set_celebration(data, str(d["id"]) if on else "")
			data["crew"]["seen"][str(d["id"])] = true
			Analytics.track("cosmetic_equipped", {"cosmetic_id": str(d["id"]) if on else "", "character": "crew"})
			Game.request_save())
		h.add_child(cb)
		data["crew"]["seen"][str(d["id"])] = true
	else:
		var ic := Control.new()
		ic.custom_minimum_size = Vector2(56, 56)
		ic.draw.connect(func(): LFIcons.draw_icon(ic, "lock", Rect2(Vector2.ZERO, ic.size), LFStyle.TEXT_MUTED))
		h.add_child(ic)
	p.queue_redraw()
	return card


# ----------------------------------------------------------------------------- detail

func _detail(v: VBoxContainer) -> void:
	var data: Dictionary = Game.state.data
	var def := LFCrew.get_def(_id)
	var stage := LFStyle.card(LFStyle.SECONDARY.lerp(Color.WHITE, 0.75), 28)
	var sv := LFStyle.vbox(8)
	stage.add_child(sv)
	_portrait = LFCrewPortrait.make(_id, 300, _animate)
	_portrait.cosmetic = LFCrew.art_for(data, _id)
	if _animate:
		var states: Array = []
		for s in PREVIEW:
			states.append(s[1])
		_portrait.cycle = states
	sv.add_child(_portrait)
	var chips := HFlowContainer.new()
	chips.alignment = FlowContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	for s in PREVIEW:
		var b := LFStyle.button(s[0], "SecondaryButton", 64)
		b.add_theme_font_size_override("font_size", 22)
		var st: int = s[1]
		b.pressed.connect(func():
			_portrait.cycle = []
			_portrait.play_state(st)
			_portrait.set_animate(_animate)
			Analytics.track("character_animation_played", {"character": _id, "animation": LFCrewAnim.state_name(st), "surface": "collection"}))
		chips.add_child(b)
	sv.add_child(chips)
	v.add_child(stage)
	v.add_child(LFStyle.label("“%s”" % str(def.get("line", "")), 30, LFStyle.TEXT, 800, HORIZONTAL_ALIGNMENT_CENTER))
	for t in [str(def.get("personality", "")), str(def.get("bio", ""))]:
		if t == "":
			continue
		var l := LFStyle.label(t, 24, LFStyle.TEXT_MUTED, 400)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	if not def.get("cosmetics", []).is_empty():
		v.add_child(LFStyle.label("Looks", 34, LFStyle.TEXT, 800))
		var note := LFStyle.label("Looks never cover a package's colour or delivery symbol.", 22, LFStyle.TEXT_MUTED, 400)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(note)
		_looks = LFStyle.vbox(12)
		v.add_child(_looks)
		_fill_looks()
	for c in def.get("cosmetics", []):
		if LFCrew.is_unlocked(data, str(c["id"])):
			data["crew"]["seen"][str(c["id"])] = true
	Game.request_save()


func _fill_looks() -> void:
	for c in _looks.get_children():
		c.queue_free()
	var data: Dictionary = Game.state.data
	var def := LFCrew.get_def(_id)
	var current := LFCrew.equipped(data, _id)
	_looks.add_child(_look_row({"id": "", "name": "Classic", "art": ""}, true, current == "", Vector2i(1, 1)))
	for c in def.get("cosmetics", []):
		var id := str(c["id"])
		var pr := LFCrew.progress_for(c.get("unlock", {}), data, Game.state.campaign)
		_looks.add_child(_look_row(c, LFCrew.is_unlocked(data, id), current == id, pr))


func _look_row(c: Dictionary, unlocked: bool, worn: bool, pr: Vector2i) -> Control:
	var card := LFStyle.card(LFStyle.SURFACE if unlocked else LFStyle.SURFACE_2, 18)
	if worn:
		card.add_theme_stylebox_override("panel", LFStyle.box(LFStyle.SURFACE, 18, true, LFStyle.PRIMARY, 4))
	var h := LFStyle.hbox(16)
	card.add_child(h)
	var p := LFCrewPortrait.make(_id, 104, false)
	p.cosmetic = str(c.get("art", ""))
	p.expression = "happy"
	if not unlocked:
		p.modulate = Color(1, 1, 1, 0.45)
	h.add_child(p)
	var tv := LFStyle.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(LFStyle.label(str(c["name"]), 28, LFStyle.TEXT if unlocked else LFStyle.TEXT_MUTED, 800))
	var sub := "Wearing" if worn else ("Tap to wear" if unlocked else "%s · %d/%d" % [LFCrew.requirement_text(c.get("unlock", {})), mini(pr.x, pr.y), pr.y])
	var sl := LFStyle.label(sub, 22, LFStyle.PRIMARY if worn else LFStyle.TEXT_MUTED, 700)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(sl)
	h.add_child(tv)
	if not unlocked:
		var ic := Control.new()
		ic.custom_minimum_size = Vector2(48, 48)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.draw.connect(func(): LFIcons.draw_icon(ic, "lock", Rect2(Vector2.ZERO, ic.size), LFStyle.TEXT_MUTED))
		h.add_child(ic)
	elif not worn:
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(func(e): if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT: _wear(str(c["id"])))
	return card


func _wear(cosmetic_id: String) -> void:
	var data: Dictionary = Game.state.data
	if not LFCrew.equip(data, _id, cosmetic_id):
		return
	Sfx.play("unlock" if cosmetic_id != "" else "ui")
	Sfx.haptic_pattern("light")
	Analytics.track("cosmetic_equipped", {"cosmetic_id": cosmetic_id, "character": _id})
	Game.request_save()
	_portrait.cosmetic = LFCrew.art_for(data, _id)
	_portrait.cycle = []
	_portrait.play_state(LFCrewAnim.CELEBRATING)
	_fill_looks.call_deferred()
