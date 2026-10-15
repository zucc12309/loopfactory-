class_name LFCrew
## The Interdimensional Delivery Crew: roster data, cosmetic unlocks, presentation switches and
## the glue between the dialogue engine, analytics and the board.
##
## Adding a character is configuration first: an entry in data/crew/characters.json (id, name,
## colour index, personality, style body id, cosmetics) plus, for a brand-new body shape, a few
## draw branches in LFCrewPainter / LFCrewAnim. Unknown body ids fall back to a generic
## personality and the plain package body, so a missing asset never breaks the board.
## See docs/CHARACTER_SYSTEM.md.

const DATA_PATH := "res://data/crew/characters.json"
const SLOTS := ["head", "eyes", "back", "skin", "suit", "expression"]
const UNLOCK_TYPES := ["campaign", "stars", "world", "perfect", "daily_any", "endless", "challenges", "all_campaign"]

## Used when the data file is missing or unreadable (and as the shape reference for tests).
const FALLBACK := [
	{"id": "bloop", "name": "Bloop", "kind": "package", "color": 0, "style": {"body": "bloop"}, "cosmetics": []},
	{"id": "zip", "name": "Zip", "kind": "package", "color": 1, "style": {"body": "zip", "size": 0.92}, "cosmetics": []},
	{"id": "glitch", "name": "Glitch", "kind": "package", "color": 2, "style": {"body": "glitch", "radius": 0.24}, "cosmetics": []},
	{"id": "mochi", "name": "Mochi", "kind": "package", "color": 3, "style": {"body": "mochi", "radius": 0.42}, "cosmetics": []},
	{"id": "naps", "name": "Captain Naps", "kind": "mascot", "color": -1, "style": {"body": "naps"}, "cosmetics": []},
]

static var _data := {}
static var _exposed := {}


static func load_data(path := DATA_PATH, force := false) -> Dictionary:
	if not _data.is_empty() and not force and path == DATA_PATH:
		return _data
	var chars: Array = []
	var special: Array = []
	var source := "file"
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if parsed is Dictionary and parsed.get("characters") is Array:
		for c in parsed["characters"]:
			if c is Dictionary and c.has("id"):
				chars.append(c)
		if parsed.get("special") is Array:
			special = parsed["special"]
	if chars.is_empty():
		chars = FALLBACK.duplicate(true)
		source = "fallback"
	var by_id := {}
	var cos := {}
	for c in chars:
		by_id[str(c["id"])] = c
		for k in c.get("cosmetics", []):
			var d: Dictionary = k.duplicate()
			d["character"] = str(c["id"])
			cos[str(d["id"])] = d
	for k in special:
		var d: Dictionary = k.duplicate()
		d["character"] = ""
		cos[str(d["id"])] = d
	var out := {"characters": chars, "by_id": by_id, "cosmetics": cos, "special": special, "source": source}
	if path == DATA_PATH:
		_data = out
	return out


static func roster() -> Array:
	return load_data()["characters"]


static func get_def(id: String) -> Dictionary:
	var d = load_data()["by_id"].get(id)
	if d is Dictionary:
		return d
	return {"id": id, "name": id.capitalize(), "kind": "package", "color": 0, "style": {"body": "generic"}, "cosmetics": []}


## The package character for colour index `cidx` (0..3). Colour identity is fixed: the character
## always uses LFStyle.PACKAGE[cidx] and LFStyle.SYMBOLS[cidx].
static func for_color(cidx: int) -> Dictionary:
	for c in roster():
		if str(c.get("kind", "")) == "package" and int(c.get("color", -1)) == cidx:
			return c
	return {"id": "package_%d" % cidx, "name": LFStyle.PACKAGE_NAMES[clampi(cidx, 0, 3)].capitalize(), "kind": "package", "color": cidx, "style": {"body": "generic"}, "cosmetics": []}


static func body_of(def: Dictionary) -> String:
	return str(def.get("style", {}).get("body", def.get("id", "generic")))


static func cosmetic(id: String) -> Dictionary:
	return load_data()["cosmetics"].get(id, {})


# ------------------------------------------------------------------------- presentation

## Resolved switches for this player: remote feature flags, the `presentation` experiment
## (hybrid = shipped default, minimal = pre-crew look, full = hybrid + sci-fi backdrop) and the
## player's own settings. Every crew feature reads this, so each can be switched off remotely.
static func presentation(data: Dictionary) -> Dictionary:
	var s: Dictionary = data.get("settings", {})
	var variant := str(LFFlags.resolve(data, "presentation"))
	var chars := LFFlags.flag(data, "characters_enabled") and variant != "minimal" and bool(s.get("crewCharacters", true))
	return {
		"variant": variant,
		"characters": chars,
		"animations": chars and LFFlags.flag(data, "character_animations_enabled") and bool(s.get("crewAnimations", true)) and not bool(s.get("reducedMotion", false)),
		"dialogue": chars and LFFlags.flag(data, "mascot_dialogue_enabled") and bool(s.get("mascotDialogue", true)),
		"collection": chars and LFFlags.flag(data, "character_collection_enabled"),
		"scifi": chars and variant == "full" and LFFlags.flag(data, "sci_fi_theme_enabled"),
	}


static func _game() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Game") if tree else null


static func current() -> Dictionary:
	var g := _game()
	if g == null or g.get("state") == null:
		return presentation({})
	return presentation(g.state.data)


## Board wiring shared by play, replay and previews.
static func configure_board(board: Node, data: Dictionary, palette: Dictionary) -> void:
	var p := presentation(data)
	board.crew_on = p["characters"]
	board.crew_motion = p["animations"]
	var arts := {}
	for cidx in 4:
		var def := for_color(cidx)
		arts[cidx] = art_for(data, str(def["id"]))
	board.crew_art = arts
	var ctx: Dictionary = palette.get("crew", {}).duplicate()
	ctx["starry"] = str(data.get("crew", {}).get("celebration", "")) == "starry_eyes"
	board.crew_ctx = ctx


# ------------------------------------------------------------------------- cosmetics

static func _crew(data: Dictionary) -> Dictionary:
	if not (data.get("crew") is Dictionary):
		data["crew"] = {}
	var c: Dictionary = data["crew"]
	for k in ["equipped", "unlocked", "seen", "dialogue"]:
		if not (c.get(k) is Dictionary):
			c[k] = {}
	if not c.has("celebration"):
		c["celebration"] = ""
	return c


static func total_stars(data: Dictionary, campaign: Array) -> int:
	var n := 0
	for lvl in campaign:
		var p = data.get("progress", {}).get(lvl["id"])
		if p is Dictionary:
			n += int(p.get("stars", 0))
	return n


static func world_done(data: Dictionary, campaign: Array, world_id: String) -> Vector2i:
	for w in LFWorlds.WORLDS.size():
		if LFWorlds.WORLDS[w]["id"] == world_id:
			var r := LFWorlds.range_for(campaign, w)
			var done := 0
			for i in range(r.x, r.y):
				if data.get("progress", {}).has(campaign[i]["id"]):
					done += 1
			return Vector2i(done, r.y - r.x)
	return Vector2i(0, 1)


## [current, target] progress toward an unlock requirement.
static func progress_for(unlock: Dictionary, data: Dictionary, campaign: Array) -> Vector2i:
	var stats: Dictionary = data.get("stats", {})
	var count := int(unlock.get("count", 1))
	match str(unlock.get("type", "")):
		"campaign":
			var done := 0
			for lvl in campaign:
				if data.get("progress", {}).has(lvl["id"]):
					done += 1
			return Vector2i(done, count)
		"stars":
			return Vector2i(total_stars(data, campaign), count)
		"world":
			return world_done(data, campaign, str(unlock.get("world", "")))
		"all_campaign":
			var done := 0
			for lvl in campaign:
				if data.get("progress", {}).has(lvl["id"]):
					done += 1
			return Vector2i(done, campaign.size())
		"perfect":
			return Vector2i(int(stats.get("perfect", 0)), count)
		"endless":
			return Vector2i(int(stats.get("endless", 0)), count)
		"challenges":
			return Vector2i(int(stats.get("challenges", 0)), count)
		"daily_any":
			var n := 0
			for key in data.get("progress", {}):
				if str(key).begins_with("daily:") or str(key).begins_with("offline_daily:"):
					n += 1
			return Vector2i(n, count)
	return Vector2i(0, 1)


static func requirement_text(unlock: Dictionary) -> String:
	var n := int(unlock.get("count", 1))
	match str(unlock.get("type", "")):
		"campaign":
			return "Solve %d campaign puzzles" % n
		"stars":
			return "Earn %d stars" % n
		"world":
			for w in LFWorlds.WORLDS:
				if w["id"] == str(unlock.get("world", "")):
					return "Finish %s" % w["name"]
			return "Finish a world"
		"all_campaign":
			return "Solve every campaign puzzle"
		"perfect":
			return "Solve %d puzzles in par" % n
		"endless":
			return "Solve %d endless puzzles" % n
		"challenges":
			return "Play %d friend challenges" % n
		"daily_any":
			return "Solve %d daily puzzles (official or practice)" % n
	return "Keep playing"


static func is_unlocked(data: Dictionary, cosmetic_id: String) -> bool:
	return data.get("crew", {}).get("unlocked", {}).has(cosmetic_id)


## Unlock every cosmetic whose requirement is now met. Returns the newly unlocked definitions.
## Requirements are derived from progress and stats, so existing players get what they already
## earned and a synced device re-derives the same unlocks.
static func evaluate_unlocks(data: Dictionary, campaign: Array, now_ms := 0) -> Array:
	var crew := _crew(data)
	var out: Array = []
	for id in load_data()["cosmetics"]:
		if crew["unlocked"].has(id):
			continue
		var d: Dictionary = load_data()["cosmetics"][id]
		var pr := progress_for(d.get("unlock", {}), data, campaign)
		if pr.x >= pr.y:
			crew["unlocked"][id] = now_ms
			out.append(d)
	return out


static func equipped(data: Dictionary, char_id: String) -> String:
	return str(data.get("crew", {}).get("equipped", {}).get(char_id, ""))


## Cosmetic art key a character currently wears ("" for none).
static func art_for(data: Dictionary, char_id: String) -> String:
	var id := equipped(data, char_id)
	if id == "" or not is_unlocked(data, id):
		return ""
	return str(cosmetic(id).get("art", ""))


## Equip `cosmetic_id` on `char_id` ("" removes). Only unlocked cosmetics that belong to that
## character can be worn.
static func equip(data: Dictionary, char_id: String, cosmetic_id: String) -> bool:
	var crew := _crew(data)
	if cosmetic_id == "":
		crew["equipped"].erase(char_id)
		return true
	var d := cosmetic(cosmetic_id)
	if d.is_empty() or str(d.get("character", "")) != char_id or not is_unlocked(data, cosmetic_id):
		return false
	crew["equipped"][char_id] = cosmetic_id
	return true


static func set_celebration(data: Dictionary, special_id: String) -> bool:
	var crew := _crew(data)
	if special_id != "" and (not is_unlocked(data, special_id) or cosmetic(special_id).get("slot", "") != "expression"):
		return false
	crew["celebration"] = special_id
	return true


## Drop anything a save refers to that no longer exists (content updates, edited files).
static func sanitize(data: Dictionary) -> void:
	var crew := _crew(data)
	for char_id in crew["equipped"].keys():
		var id := str(crew["equipped"][char_id])
		var d := cosmetic(id)
		if d.is_empty() or str(d.get("character", "")) != str(char_id):
			crew["equipped"].erase(char_id)
	if crew["celebration"] != "" and cosmetic(str(crew["celebration"])).is_empty():
		crew["celebration"] = ""


static func unseen_count(data: Dictionary) -> int:
	var crew := _crew(data)
	var n := 0
	for id in crew["unlocked"]:
		if not crew["seen"].has(id):
			n += 1
	return n


# ------------------------------------------------------------------------- dialogue

## Pick and record a line for `event`. Returns {} when dialogue is off or nothing qualifies.
## Never blocks: callers show the result in a banner, bubble or card, never a modal.
static func say(event: String, ctx := {}, vars := {}, force := false) -> Dictionary:
	var g := _game()
	if g == null or g.get("state") == null:
		return {}
	var data: Dictionary = g.state.data
	if not presentation(data)["dialogue"]:
		return {}
	var crew := _crew(data)
	var roll := 0.0 if force else randf()
	var line := LFDialogue.pick(LFDialogue.lines(LFDialogue.locale()), event, ctx, crew["dialogue"], LFGameState.now_ms(), roll)
	if line.is_empty():
		return {}
	crew["dialogue"][str(line["id"])] = LFGameState.now_ms()
	var out := line.duplicate()
	out["text"] = LFDialogue.format(str(line["text"]), vars)
	out["speaker"] = str(get_def(str(line["character"])).get("name", ""))
	var analytics := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Analytics")
	if analytics != null:
		analytics.track("character_dialogue_shown", {"character": str(line["character"]), "event": event, "line_id": str(line["id"])})
	return out


## character_exposed once per session per surface (keeps the event cheap and meaningful).
static func expose(surface: String, props := {}) -> void:
	if _exposed.has(surface):
		return
	_exposed[surface] = true
	var analytics := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Analytics")
	if analytics != null:
		var p := props.duplicate()
		p["surface"] = surface
		p["variant"] = str(current()["variant"])
		analytics.track("character_exposed", p)


# ------------------------------------------------------------------------- introductions

## Mechanics Dr. Rix introduces (existing rules only — no new mechanics are added for theme).
static func mechanics_of(level: Dictionary) -> Array:
	var out: Array = []
	var colours := {}
	var cross := false
	var tee := false
	for t in level.get("tiles", []):
		match str(t["t"]):
			"cross":
				cross = true
			"tee":
				tee = true
			"source":
				colours[int(t.get("c", 0))] = true
	if cross:
		out.append("crossing")
	if tee:
		out.append("junction")
	if colours.size() >= 3:
		out.append("three_colours")
	return out


## The mechanic first seen at campaign position `index`, or "".
static func mechanic_intro(campaign: Array, index: int) -> String:
	if index < 0 or index >= campaign.size():
		return ""
	for m in mechanics_of(campaign[index]):
		var first := -1
		for i in campaign.size():
			if m in mechanics_of(campaign[i]):
				first = i
				break
		if first == index:
			return m
	return ""


## World id when `index` opens a new world (after the first), else "".
static func world_intro(campaign: Array, index: int) -> String:
	if index <= 0 or index >= campaign.size():
		return ""
	for w in range(1, LFWorlds.WORLDS.size()):
		if campaign[index]["id"] == LFWorlds.WORLDS[w]["first"]:
			return LFWorlds.WORLDS[w]["id"]
	return ""
