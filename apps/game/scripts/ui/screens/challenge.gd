extends LFScreen
## Friend challenges: enter (or deep-link) a code, see who you're up against, play the same puzzle.
## No account step — the game silently uses a guest identity for the server-verified attempt.
## Args: {code} to open one directly.

var _input: LineEdit
var _result: VBoxContainer


func setup(args: Dictionary) -> void:
	var sm: Vector2 = main.safe_margins()
	var root := LFStyle.vbox(22)
	var m := LFStyle.margin(root, 32, 32 + int(sm.x), 32, 32 + int(sm.y))
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	root.add_child(header("Friend challenge"))
	var intro := LFStyle.label("Got a code from a friend? Play the exact same puzzle and try to use fewer rotations.", 24, LFStyle.TEXT_MUTED, 400)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(intro)
	var row := LFStyle.hbox(14)
	_input = LineEdit.new()
	_input.placeholder_text = "Challenge code"
	_input.custom_minimum_size = Vector2(0, 96)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_font_size_override("font_size", 34)
	_input.max_length = 16
	_input.text_submitted.connect(func(_t): _open())
	row.add_child(_input)
	var go := LFStyle.button("Open", "", 96)
	go.custom_minimum_size.x = 170
	go.pressed.connect(_open)
	row.add_child(go)
	root.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_result = LFStyle.vbox(16)
	_result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_result)
	_render_history()
	if str(args.get("code", "")) != "":
		_input.text = str(args["code"])
		_open.call_deferred()


func _render_history() -> void:
	var ch: Dictionary = Game.state.data["challenges"]
	if ch["created"].is_empty() and ch["played"].is_empty():
		return
	_result.add_child(LFStyle.label("Your challenges", 30, LFStyle.TEXT, 800))
	for code in ch["created"]:
		_result.add_child(_line("Sent · %s" % code, "%d rotations" % int(ch["created"][code]["rotations"])))
	for code in ch["played"]:
		var p: Dictionary = ch["played"][code]
		_result.add_child(_line("Played · %s" % code, "%d · %s" % [int(p["rotations"]), str(p.get("outcome", "")).capitalize()]))


func _line(a: String, b: String) -> Control:
	var card := LFStyle.card(LFStyle.SURFACE, 14)
	var h := LFStyle.hbox(12)
	card.add_child(h)
	var l := LFStyle.label(a, 24, LFStyle.TEXT, 700)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(LFStyle.label(b, 24, LFStyle.TEXT_MUTED, 700))
	return card


## Copy for each lookup failure (never blames the player).
const ERRORS := {
	"invalid": "That isn't a challenge code. Codes have 8 letters and numbers, like K7MPQ2XR.",
	"not_found": "This challenge has expired or doesn't exist. Ask your friend for a new code.",
	"offline": "You're offline. We saved the code and will open it next time you start the game online. Your other puzzles still work offline.",
	"error": "Something went wrong looking up that code. Please try again in a moment.",
}


func _open() -> void:
	var raw := _input.text
	if raw.strip_edges().is_empty():
		return
	var code := LFShare.parse_challenge(raw)
	for c in _result.get_children():
		c.queue_free()
	if code == "":
		_show_error(ERRORS["invalid"])
		return
	_result.add_child(LFStyle.label("Looking up %s…" % code, 26, LFStyle.TEXT_MUTED, 400))
	Analytics.track("challenge_link_opened", {"source": "code_entry"})
	var res: Dictionary = await Net.get_challenge_result(code) if Net.enabled() else {"status": "offline", "body": null}
	if not is_inside_tree():
		return
	for c in _result.get_children():
		c.queue_free()
	var chs: Dictionary = Game.state.data["challenges"]
	if res["status"] != "ok":
		if res["status"] == "offline":
			chs["pending"] = code  # opened again at the next launch
		elif str(chs.get("pending", "")) == code:
			chs.erase("pending")
		Game.request_save()
		_show_error(ERRORS.get(res["status"], ERRORS["error"]))
		return
	chs.erase("pending")
	Game.request_save()
	var ch: Dictionary = res["body"]
	Analytics.track("challenge_loaded", {"attempts": int(ch.get("attempts", 0))})
	var card := LFStyle.card()
	var v := LFStyle.vbox(12)
	card.add_child(LFStyle.margin(v, 8, 8, 8, 8))
	v.add_child(LFStyle.label("%s challenged you" % str(ch["creatorName"]), 34, LFStyle.TEXT, 800))
	var lvl: Dictionary = ch["level"]
	v.add_child(LFStyle.label("%s · %s · par %d" % [lvl["name"], str(lvl.get("difficulty", "")).capitalize(), lvl["par"]], 24, LFStyle.TEXT_MUTED, 700))
	var goal := LFStyle.label("Beat %d rotations. %d player%s tried so far." % [int(ch["creatorRotations"]), int(ch.get("attempts", 0)), "" if int(ch.get("attempts", 0)) == 1 else "s"], 26, LFStyle.TEXT, 700)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(goal)
	var play := LFStyle.button("Play challenge", "", 104)
	play.name = "PlayChallenge"
	play.pressed.connect(func():
		var info := {"code": str(ch["code"]), "creatorName": str(ch["creatorName"]), "creatorRotations": int(ch["creatorRotations"])}
		main.goto("play", {"kind": "challenge", "level": lvl, "challenge": info}))
	v.add_child(play)
	_result.add_child(card)


func _show_error(text: String) -> void:
	for c in _result.get_children():
		c.queue_free()
	var l := LFStyle.label(text, 24, LFStyle.ERROR.darkened(0.25), 700)
	l.name = "ChallengeMessage"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.add_child(l)
