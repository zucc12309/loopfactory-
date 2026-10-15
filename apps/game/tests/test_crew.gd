extends LFTestCase
## Interdimensional Delivery Crew: roster identity, cosmetics and unlocks, persistence and old-save
## compatibility, presentation switches, the animation state machine, dialogue and moments.
## Rendering checks (symbols never covered, compact boards, board flows) are in tests_ui/.

const BODIES := ["bloop", "zip", "glitch", "mochi", "naps", "rix"]
const ARTS := ["crown", "goggles", "cape", "headphones", "helmet", "glasses", "pixel_shades", "alien_antenna",
	"holo", "sleep_cap", "backpack", "pajamas", "naps_detective", "naps_lab", "naps_gold", "starry_eyes"]

var campaign: Array = []
var ach: Array = []


func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/curated.json"))
	for l in data["levels"]:
		campaign.append(LFTiles.normalize_level(l))
	ach = JSON.parse_string(FileAccess.get_file_as_string("res://data/achievements.json"))["achievements"]


func _state() -> LFGameState:
	return LFGameState.new(campaign, ach)


func _complete(st: LFGameState, idx: int, perfect := true) -> void:
	st.start_level("campaign", campaign[idx])
	for mv in campaign[idx]["solution"]["moves"]:
		st.rotate(int(mv[0]), int(mv[1]))
	if not perfect:
		for i in campaign[idx]["tiles"].size():
			if LFTiles.is_rotatable(campaign[idx]["tiles"][i]):
				for k in LFTiles.PERIOD[campaign[idx]["tiles"][i]["t"]]:
					st.rotate(i, 1)
				break
	st.complete_active()


# ------------------------------------------------------------------ roster & identity

func test_every_package_colour_has_exactly_one_character() -> void:
	var data := LFCrew.load_data(LFCrew.DATA_PATH, true)
	eq(data["source"], "file", "roster comes from data/crew/characters.json")
	var ids := {}
	for c in LFCrew.roster():
		check(not ids.has(c["id"]), "unique id %s" % c["id"])
		ids[c["id"]] = true
		check(LFCrew.body_of(c) in BODIES, "%s has a drawable body" % c["id"])
		for k in ["name", "role", "personality", "bio", "line"]:
			check(str(c.get(k, "")) != "", "%s has %s" % [c["id"], k])
	for cidx in 4:
		var c := LFCrew.for_color(cidx)
		eq(int(c["color"]), cidx, "character for colour %d" % cidx)
		eq(c["kind"], "package")
	eq([LFCrew.for_color(0)["id"], LFCrew.for_color(1)["id"], LFCrew.for_color(2)["id"], LFCrew.for_color(3)["id"]], ["bloop", "zip", "glitch", "mochi"])
	check(ids.has("naps") and ids.has("rix"), "mascot and engineer present")


func test_missing_or_broken_data_falls_back() -> void:
	var fb := LFCrew.load_data("res://data/crew/does-not-exist.json")
	eq(fb["source"], "fallback")
	eq(fb["characters"].size(), 5)
	var unknown := LFCrew.get_def("nobody")
	eq(LFCrew.body_of(unknown), "generic", "unknown character draws as a generic package")
	# A generic body still animates with a valid pose.
	for s in 8:
		var p := LFCrewAnim.pose("generic", s, 0.2, 1.0, 3)
		check(p.has("eyes") and p.has("mouth"), "generic pose %d" % s)


# ------------------------------------------------------------------ cosmetics config

func test_cosmetics_are_valid_and_achievable() -> void:
	var seen := {}
	var all: Dictionary = LFCrew.load_data()["cosmetics"]
	check(all.size() >= 16, "15 looks + 1 expression")
	for id in all:
		var d: Dictionary = all[id]
		check(not seen.has(id), "unique cosmetic %s" % id)
		seen[id] = true
		check(str(d.get("slot", "")) in LFCrew.SLOTS, "%s slot" % id)
		check(str(d.get("art", "")) in ARTS, "%s has painter art" % id)
		var u: Dictionary = d.get("unlock", {})
		check(str(u.get("type", "")) in LFCrew.UNLOCK_TYPES, "%s unlock type" % id)
		check(LFCrew.requirement_text(u) != "Keep playing", "%s has requirement copy" % id)
		match str(u["type"]):
			"campaign":
				check(int(u["count"]) <= campaign.size(), "%s reachable in campaign" % id)
			"stars":
				check(int(u["count"]) <= campaign.size() * 3, "%s reachable stars" % id)
			"world":
				var found := false
				for w in LFWorlds.WORLDS:
					found = found or w["id"] == u["world"]
				check(found, "%s world exists" % id)
	# Each package character has 3 looks, Captain Naps 3, Dr. Rix none.
	for cid in ["bloop", "zip", "glitch", "mochi", "naps"]:
		eq(LFCrew.get_def(cid)["cosmetics"].size(), 3, cid)


func test_unlocks_follow_real_progress() -> void:
	var st := _state()
	eq(st.data["crew"]["unlocked"], {}, "a new player starts with no looks")
	for i in 5:
		_complete(st, i)
	check(LFCrew.is_unlocked(st.data, "mochi_cap"), "5 puzzles unlock Mochi's sleep cap")
	check(not LFCrew.is_unlocked(st.data, "bloop_crown"), "crown needs 10")
	for i in range(5, 9):
		_complete(st, i)
	check(LFCrew.is_unlocked(st.data, "naps_detective"), "finishing Little Workshop unlocks the detective hat")
	_complete(st, 9)
	check(LFCrew.is_unlocked(st.data, "bloop_crown"), "10 puzzles unlock Bloop's crown")
	check(LFCrew.is_unlocked(st.data, "glitch_shades"), "30 stars unlock Glitch's shades")
	eq(LFCrew.total_stars(st.data, campaign), 30)
	check(LFCrew.is_unlocked(st.data, "zip_glasses"), "10 perfect solves unlock Zip's glasses")
	eq(LFCrew.unseen_count(st.data), 5, "new looks are marked unseen")


func test_completion_reports_new_cosmetics() -> void:
	var st := _state()
	for i in 4:
		_complete(st, i)
	st.start_level("campaign", campaign[4])
	for mv in campaign[4]["solution"]["moves"]:
		st.rotate(int(mv[0]), int(mv[1]))
	var res := st.complete_active()
	eq(res["cosmetics"].size(), 1)
	eq(res["cosmetics"][0]["id"], "mochi_cap")


func test_daily_any_counts_official_and_practice_dailies() -> void:
	var st := _state()
	var u := {"type": "daily_any", "count": 3}
	eq(LFCrew.progress_for(u, st.data, campaign), Vector2i(0, 3))
	st.data["progress"]["daily:daily-2026-10-01"] = {"best": 5, "par": 5, "stars": 3}
	st.data["progress"]["offline_daily:offline-2026-10-02"] = {"best": 5, "par": 5, "stars": 3}
	st.data["progress"]["endless:gen-1"] = {"best": 5, "par": 5, "stars": 3}
	eq(LFCrew.progress_for(u, st.data, campaign), Vector2i(2, 3))


# ------------------------------------------------------------------ persistence & compatibility

func test_old_saves_load_and_receive_earned_looks() -> void:
	# A save from before the crew existed: no "crew" key, no crew settings.
	var old := LFGameState.defaults()
	old.erase("crew")
	for k in ["crewCharacters", "crewAnimations", "mascotDialogue"]:
		old["settings"].erase(k)
	for i in 10:
		old["progress"][campaign[i]["id"]] = {"completed": true, "best": campaign[i]["par"], "par": campaign[i]["par"], "stars": 3, "completedAt": 1, "kind": "campaign"}
	old["stats"]["campaign"] = 10
	var before: Dictionary = old["progress"].duplicate(true)
	var st := _state()
	st.load_from(JSON.parse_string(JSON.stringify(old)))
	eq(st.data["progress"], before, "progress untouched")
	check(st.data["crew"] is Dictionary, "crew data created")
	eq(st.data["settings"]["crewCharacters"], true, "new settings default on")
	for id in ["mochi_cap", "naps_detective", "bloop_crown", "glitch_shades"]:
		check(LFCrew.is_unlocked(st.data, id), "retroactive unlock %s" % id)
	check(not LFCrew.is_unlocked(st.data, "zip_headphones"), "20-puzzle look still locked")


func test_equip_rules_and_save_round_trip() -> void:
	var st := _state()
	for i in 10:
		_complete(st, i)
	check(not LFCrew.equip(st.data, "zip", "zip_headphones"), "locked look can't be worn")
	check(not LFCrew.equip(st.data, "zip", "bloop_crown"), "another character's look can't be worn")
	check(LFCrew.equip(st.data, "bloop", "bloop_crown"), "unlocked look can be worn")
	eq(LFCrew.art_for(st.data, "bloop"), "crown")
	check(not LFCrew.set_celebration(st.data, "starry_eyes"), "locked expression can't be chosen")
	var store := LFSaveStore.new("user://test-crew-save.json")
	check(store.save(st.data), "saved")
	var st2 := _state()
	st2.load_from(store.load_data())
	eq(LFCrew.equipped(st2.data, "bloop"), "bloop_crown", "equipped look restored")
	eq(st2.data["crew"]["unlocked"].keys().size(), st.data["crew"]["unlocked"].keys().size(), "unlocks restored")
	check(LFCrew.equip(st2.data, "bloop", ""), "remove look")
	eq(LFCrew.art_for(st2.data, "bloop"), "")
	store.wipe()
	# Content updates: references to looks that no longer exist are dropped on load.
	var bogus := st.data.duplicate(true)
	bogus["crew"]["equipped"]["zip"] = "zip_jetpack_v9"
	bogus["crew"]["celebration"] = "nope"
	var st3 := _state()
	st3.load_from(bogus)
	eq(LFCrew.equipped(st3.data, "zip"), "")
	eq(st3.data["crew"]["celebration"], "")


# ------------------------------------------------------------------ presentation switches

func test_presentation_flags_variants_and_settings() -> void:
	var data := LFGameState.defaults()
	var p := LFCrew.presentation(data)
	eq(p["variant"], "hybrid", "hybrid is the shipped default")
	for k in ["characters", "animations", "dialogue", "collection"]:
		check(p[k], "%s on by default" % k)
	check(not p["scifi"], "sci-fi backdrop only in the full variant")
	for flag in LFFlags.FLAGS:
		var d := LFGameState.defaults()
		d["remoteConfig"] = {"flags": {flag: false}}
		var q := LFCrew.presentation(d)
		match flag:
			"characters_enabled":
				check(not q["characters"] and not q["animations"] and not q["dialogue"] and not q["collection"], "kill switch removes everything")
			"character_animations_enabled":
				check(q["characters"] and not q["animations"], flag)
			"mascot_dialogue_enabled":
				check(q["characters"] and not q["dialogue"], flag)
			"character_collection_enabled":
				check(q["characters"] and not q["collection"], flag)
	var mini := LFGameState.defaults()
	mini["remoteConfig"] = {"experiments": {"presentation": {"force": "minimal"}}}
	check(not LFCrew.presentation(mini)["characters"], "variant A is the pre-crew look")
	var full := LFGameState.defaults()
	full["remoteConfig"] = {"experiments": {"presentation": {"force": "full"}}}
	check(LFCrew.presentation(full)["scifi"], "variant C adds the sci-fi treatment")
	full["remoteConfig"]["flags"] = {"sci_fi_theme_enabled": false}
	check(not LFCrew.presentation(full)["scifi"], "sci-fi flag off")
	var rm := LFGameState.defaults()
	rm["settings"]["reducedMotion"] = true
	check(LFCrew.presentation(rm)["characters"] and not LFCrew.presentation(rm)["animations"], "reduced motion stops character animation")
	var off := LFGameState.defaults()
	off["settings"]["crewAnimations"] = false
	check(not LFCrew.presentation(off)["animations"], "player can turn character animations off")


# ------------------------------------------------------------------ animation state machine

func test_poses_are_deterministic_and_complete() -> void:
	for body in ["bloop", "zip", "glitch", "mochi", "generic"]:
		for s in 8:
			for t in [0.0, 0.37, 1.9, 12.5]:
				var a := LFCrewAnim.pose(body, s, t * 0.5, t, 7, {"dir": Vector2(1, 0)})
				var b := LFCrewAnim.pose(body, s, t * 0.5, t, 7, {"dir": Vector2(1, 0)})
				eq(a, b, "%s %s deterministic" % [body, LFCrewAnim.state_name(s)])
				for k in LFCrewAnim.base():
					check(a.has(k), "%s has %s" % [body, k])
				check(is_finite(float(a["dy"])) and is_finite(float(a["rot"])), "finite pose")
				check(absf(float(a["dy"])) <= 0.45, "%s %s hop stays small (%f)" % [body, LFCrewAnim.state_name(s), a["dy"]])
	eq(LFCrewAnim.state_from_name("celebrating"), LFCrewAnim.CELEBRATING)


func test_reduced_motion_freezes_every_pose() -> void:
	for body in ["bloop", "zip", "glitch", "mochi"]:
		for s in 8:
			var first := LFCrewAnim.pose(body, s, 0.0, 0.0, 1, {"motion": false, "dir": Vector2(0, 1)})
			for t in [0.05, 0.21, 0.6, 3.3, 9.7]:
				var p := LFCrewAnim.pose(body, s, t, t, 1, {"motion": false, "dir": Vector2(0, 1)})
				eq([p["dx"], p["dy"], p["sx"], p["sy"], p["rot"], p["ghost"], p["foot"]], [0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0], "%s %s static" % [body, LFCrewAnim.state_name(s)])
				if s != LFCrewAnim.SELECTED and s != LFCrewAnim.FAILED and s != LFCrewAnim.DELIVERED and s != LFCrewAnim.SURPRISED:
					eq([p["eyes"], p["mouth"]], [first["eyes"], first["mouth"]], "%s %s expression doesn't flicker" % [body, LFCrewAnim.state_name(s)])


func test_animation_never_touches_the_simulation() -> void:
	for idx in [5, 6, 20, 25, 31, 35]:
		var lvl: Dictionary = campaign[idx]
		var rots = LFTiles.apply_moves(lvl, lvl["solution"]["moves"], LFTiles.start_rotations(lvl))
		var a := LFSimulation.simulate(lvl, rots)
		var snapshot := JSON.stringify(a)
		# Drive every character through every frame the way the board does.
		for f in a["frames"]:
			for p in f["packages"]:
				for s in 8:
					LFCrewAnim.pose(LFCrew.body_of(LFCrew.for_color(int(p["color"]))), s, 0.1, 0.2, int(p["id"]), {"dir": Vector2(1, 0)})
		LFCrewMoments.detect(a, lvl, lvl["par"])
		eq(JSON.stringify(a), snapshot, "%s frames untouched" % lvl["id"])
		eq(JSON.stringify(LFSimulation.simulate(lvl, rots)), snapshot, "%s re-simulates identically" % lvl["id"])
		check(a["success"], "%s solves" % lvl["id"])


func test_daily_results_identical_with_and_without_characters() -> void:
	var lvl: Dictionary = campaign[20].duplicate(true)
	lvl["id"] = "daily-2026-10-15"
	var out := []
	for variant in ["hybrid", "minimal"]:
		var st := _state()
		st.data["remoteConfig"] = {"experiments": {"presentation": {"force": variant}}}
		st.start_level("daily", lvl)
		st.active()["date"] = "2026-10-15"
		st.record_run()
		for mv in lvl["solution"]["moves"]:
			st.rotate(int(mv[0]), int(mv[1]))
		var res := st.complete_active()
		out.append([res["moves"], res["stars"], res["par"], st.data["daily"]["results"]["2026-10-15"]["rotations"], st.data["syncQueue"][-1]["payload"]["moves"]])
	eq(out[0], out[1], "presentation variant never changes daily scoring or submissions")


# ------------------------------------------------------------------ dialogue

func test_dialogue_lines_are_short_and_well_formed() -> void:
	var all := LFDialogue.lines("en")
	check(all.size() >= 30, "dialogue loaded")
	var ids := {}
	for l in all:
		check(not ids.has(l["id"]), "unique line %s" % l["id"])
		ids[l["id"]] = true
		check(str(l["event"]) in LFDialogue.EVENTS, "%s known event" % l["id"])
		check(str(l["text"]).length() <= 90, "%s is short (%d chars)" % [l["id"], str(l["text"]).length()])
		check(LFCrew.load_data()["by_id"].has(str(l["character"])), "%s speaker exists" % l["id"])
		check(float(l.get("probability", 1)) > 0.0 and float(l.get("probability", 1)) <= 1.0, "%s probability" % l["id"])
	for ev in ["FIRST_LAUNCH", "NEW_WORLD", "NEW_MECHANIC", "FIRST_SUCCESS", "PERFECT_SCORE", "FAILED_ATTEMPT", "DAILY_CHALLENGE", "CHARACTER_UNLOCK"]:
		var any := false
		for l in all:
			any = any or l["event"] == ev
		check(any, "lines exist for %s" % ev)


func test_dialogue_selection_rules() -> void:
	var lines := [
		{"id": "a", "event": "E", "text": "low", "priority": 1, "cooldown": 60, "probability": 1.0, "character": "naps"},
		{"id": "b", "event": "E", "text": "high", "priority": 5, "cooldown": -1, "probability": 1.0, "character": "naps"},
		{"id": "c", "event": "E", "when": {"world": "neon"}, "text": "neon", "priority": 9, "cooldown": 0, "probability": 1.0, "character": "naps"},
		{"id": "d", "event": "R", "text": "rare", "priority": 1, "cooldown": 0, "probability": 0.25, "character": "naps"},
	]
	eq(LFDialogue.pick(lines, "E", {}, {}, 1000, 0.0)["id"], "b", "highest priority")
	eq(LFDialogue.pick(lines, "E", {"world": "neon"}, {}, 1000, 0.0)["id"], "c", "conditions")
	eq(LFDialogue.pick(lines, "E", {}, {"b": 5}, 999999, 0.0)["id"], "a", "show-once line not repeated")
	eq(LFDialogue.pick(lines, "E", {}, {"b": 5, "a": 1000}, 30000, 0.0), {}, "cooldown respected")
	eq(LFDialogue.pick(lines, "E", {}, {"b": 5, "a": 1000}, 70000, 0.0)["id"], "a", "cooldown expires")
	eq(LFDialogue.pick(lines, "R", {}, {}, 0, 0.5), {}, "probability gate")
	eq(LFDialogue.pick(lines, "R", {}, {}, 0, 0.1)["id"], "d")
	eq(LFDialogue.pick(lines, "NOPE", {}, {}, 0, 0.0), {})
	eq(LFDialogue.format("{done} of {total}", {"done": 3, "total": 36}), "3 of 36")


func test_translations_fall_back_to_english_by_id() -> void:
	var dir := "user://crew-l10n"
	DirAccess.make_dir_recursive_absolute(dir)
	var en := {"lines": [{"id": "x", "event": "E", "text": "Hello", "character": "naps"}, {"id": "y", "event": "E", "text": "Bye", "character": "naps"}]}
	var hi := {"lines": [{"id": "x", "text": "नमस्ते"}]}
	var f := FileAccess.open(dir + "/dialogue.en.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(en))
	f.close()
	f = FileAccess.open(dir + "/dialogue.hi.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(hi))
	f.close()
	var out := LFDialogue.lines("hi", dir + "/dialogue.en.json")
	eq(out[0]["text"], "नमस्ते", "translated line")
	eq(out[0]["locale"], "hi")
	eq(out[1]["text"], "Bye", "untranslated line falls back to English")
	eq(LFDialogue.lines("ta", dir + "/dialogue.en.json")[0]["text"], "Hello", "missing language falls back to English")
	DirAccess.remove_absolute(dir + "/dialogue.en.json")
	DirAccess.remove_absolute(dir + "/dialogue.hi.json")


# ------------------------------------------------------------------ moments & introductions

func test_moments_come_from_real_results() -> void:
	var lvl: Dictionary = campaign[35]
	var rots = LFTiles.apply_moves(lvl, lvl["solution"]["moves"], LFTiles.start_rotations(lvl))
	var res := LFSimulation.simulate(lvl, rots)
	var m := LFCrewMoments.detect(res, lvl, int(lvl["par"]))
	check("perfect" in m and "unusually_efficient" in m, "par on a par-17 board: %s" % [m])
	check(not ("perfect" in LFCrewMoments.detect(res, lvl, int(lvl["par"]) + 2)), "over par is not perfect")
	eq(LFCrewMoments.detect({"success": false, "frames": []}, lvl, 1), [], "failures have no moments")
	# Constructed frames: two packages delivered on the same tick; one waits facing another.
	var level := {"width": 3, "height": 1, "par": 2}
	var together := {"success": true, "total": 2, "frames": [
		{"packages": [{"id": 0, "color": 0, "cell": 0, "dir": 1, "state": "waiting"}, {"id": 1, "color": 1, "cell": 1, "dir": 1, "state": "moved"}]},
		{"packages": [{"id": 0, "color": 0, "cell": 2, "dir": 1, "state": "delivered"}, {"id": 1, "color": 1, "cell": 2, "dir": 1, "state": "delivered"}]},
	]}
	var mm := LFCrewMoments.detect(together, level, 3)
	check("all_together" in mm and "near_miss" in mm and not ("perfect" in mm), "constructed moments %s" % [mm])
	eq(LFCrewMoments.headline(mm), "all_together")


func test_dr_rix_and_world_introductions_match_content() -> void:
	var idx := {}
	for i in campaign.size():
		idx[campaign[i]["id"]] = i
	eq(LFCrew.mechanic_intro(campaign, idx["c07"]), "crossing")
	eq(LFCrew.mechanic_intro(campaign, idx["c08"]), "junction")
	eq(LFCrew.mechanic_intro(campaign, idx["x31"]), "three_colours")
	eq(LFCrew.mechanic_intro(campaign, idx["c27"]), "", "later crossings aren't re-introduced")
	eq(LFCrew.world_intro(campaign, idx["c10"]), "candy")
	eq(LFCrew.world_intro(campaign, idx["x26"]), "neon")
	eq(LFCrew.world_intro(campaign, 0), "", "the first world needs no introduction")
	# Every introduction has a line to say.
	var all := LFDialogue.lines("en")
	for m in ["crossing", "junction", "three_colours"]:
		check(not LFDialogue.pick(all, "NEW_MECHANIC", {"mechanic": m}, {}, 0, 0.0).is_empty(), "Dr. Rix line for %s" % m)
	for w in range(1, LFWorlds.WORLDS.size()):
		check(not LFDialogue.pick(all, "NEW_WORLD", {"world": LFWorlds.WORLDS[w]["id"]}, {}, 0, 0.0).is_empty(), "world line for %s" % LFWorlds.WORLDS[w]["id"])
