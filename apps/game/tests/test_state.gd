extends LFTestCase
## Game state rules: rotation/undo/reset, completion, resume, sync queue and merge semantics.

var campaign: Array = []
var ach: Array = []


func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/curated.json"))
	for l in data["levels"]:
		campaign.append(LFTiles.normalize_level(l))
	ach = JSON.parse_string(FileAccess.get_file_as_string("res://data/achievements.json"))["achievements"]


func _state() -> LFGameState:
	return LFGameState.new(campaign, ach)


func _solve_active(st: LFGameState) -> void:
	for mv in st.active_level()["solution"]["moves"]:
		st.rotate(int(mv[0]), int(mv[1]))


func test_rotate_undo_reset() -> void:
	var st := _state()
	var lvl: Dictionary = campaign[2]
	st.start_level("campaign", lvl)
	var start := LFTiles.start_rotations(lvl)
	var idx := -1
	for i in lvl["tiles"].size():
		if LFTiles.is_rotatable(lvl["tiles"][i]):
			idx = i
			break
	check(st.rotate(idx, 1), "rotatable tile rotates")
	check(st.rotate(idx, 1), "again")
	eq(st.active()["rotations"][idx], (start[idx] + 2) % 4)
	eq(st.moves_count(), 2)
	eq(st.undo(), [idx, 1])
	eq(st.active()["rotations"][idx], (start[idx] + 1) % 4)
	st.rotate(idx, -1)
	eq(st.active()["rotations"][idx], start[idx], "ccw undoes cw")
	st.reset()
	eq(st.active()["rotations"], start)
	eq(st.moves_count(), 0)
	eq(st.undo(), null, "nothing to undo after reset")


func test_locked_and_fixed_tiles_reject_rotation() -> void:
	var st := _state()
	var lvl: Dictionary = campaign[3]  # "Pinned" has locked belts
	st.start_level("campaign", lvl)
	for i in lvl["tiles"].size():
		var t: Dictionary = lvl["tiles"][i]
		if not LFTiles.is_rotatable(t):
			check(not st.rotate(i, 1), "tile %d (%s) must not rotate" % [i, t["t"]])
	eq(st.moves_count(), 0)
	check(not st.rotate(-1, 1), "out of range")
	check(not st.rotate(9999, 1), "out of range")


func test_complete_requires_real_solution() -> void:
	var st := _state()
	st.start_level("campaign", campaign[0])
	eq(st.complete_active(), {}, "unsolved board cannot complete")
	check(st.active() != null, "puzzle still active")
	_solve_active(st)
	var res := st.complete_active()
	eq(res["moves"], campaign[0]["par"])
	eq(res["stars"], 3)
	check(res["first"], "first completion")
	eq(st.active(), null, "active cleared")
	check(st.campaign_completed(0), "progress recorded")
	eq(st.data["stats"]["campaign"], 1)
	eq(st.data["stats"]["perfect"], 1)
	var ids: Array = res["achievements"].map(func(a): return a["id"])
	check(ids.has("first_delivery") and ids.has("efficient"), "achievements unlocked: %s" % [ids])
	var q: Array = st.data["syncQueue"]
	eq(q.size(), 1)
	eq(q[0]["type"], "level_complete")
	eq(q[0]["payload"]["moves"], campaign[0]["solution"]["moves"], "replay queued for server verification")


func test_best_score_is_monotonic() -> void:
	var st := _state()
	var lvl: Dictionary = campaign[1]
	st.start_level("campaign", lvl)
	var extra := -1
	for i in lvl["tiles"].size():
		if LFTiles.is_rotatable(lvl["tiles"][i]):
			extra = i
	st.rotate(extra, 1)
	st.rotate(extra, -1)
	_solve_active(st)
	var first := st.complete_active()
	eq(first["moves"], lvl["par"] + 2)
	st.start_level("campaign", lvl)
	_solve_active(st)
	var second := st.complete_active()
	check(second["newBest"], "improved")
	eq(st.data["progress"][lvl["id"]]["best"], lvl["par"])
	st.start_level("campaign", lvl)
	st.rotate(extra, 1)
	st.rotate(extra, -1)
	_solve_active(st)
	st.complete_active()
	eq(st.data["progress"][lvl["id"]]["best"], lvl["par"], "worse run never overwrites best")
	eq(st.data["stats"]["campaign"], 1, "replays don't double count")


func test_resume_after_restart() -> void:
	var st := _state()
	st.start_level("campaign", campaign[4])
	st.rotate(int(campaign[4]["solution"]["moves"][0][0]), 1)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(st.data))  # through JSON like the real save
	var st2 := _state()
	st2.load_from(saved)
	check(st2.active() != null, "active puzzle restored")
	eq(st2.active()["rotations"], st.active()["rotations"])
	eq(st2.moves_count(), 1)
	eq(st2.undo() != null, true, "undo history restored")


func test_tampered_active_puzzle_is_dropped() -> void:
	var st := _state()
	st.start_level("campaign", campaign[4])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(st.data))
	saved["active"]["rotations"][0] = 3  # inconsistent with (empty) history
	var st2 := _state()
	st2.load_from(saved)
	eq(st2.active(), null, "inconsistent active state discarded instead of crashing")


func test_load_merges_new_default_fields() -> void:
	var st := _state()
	st.load_from({"settings": {"sfx": false}, "progress": {"c01": {"completed": true, "best": 1, "par": 1, "stars": 3, "completedAt": 1}}})
	eq(st.data["settings"]["sfx"], false)
	eq(st.data["settings"]["haptics"], true, "missing keys default")
	check(st.data.has("syncQueue"), "new sections present")


func test_sync_queue_coalesces_and_backs_off() -> void:
	var st := _state()
	st.set_setting("sfx", false)
	st.set_setting("haptics", false)
	var settings_ops: Array = st.data["syncQueue"].filter(func(o): return o["type"] == "settings")
	eq(settings_ops.size(), 1, "settings snapshots coalesce")
	eq(settings_ops[0]["payload"]["settings"]["haptics"], false, "latest snapshot kept")
	var op_id: String = settings_ops[0]["opId"]
	st.retry_later([op_id], 1000)
	eq(st.due_ops(1000).size(), 0, "not due during backoff")
	eq(st.due_ops(1000 + 3600001).size(), 1, "due after backoff")
	st.ack_ops([op_id])
	eq(st.data["syncQueue"].size(), 0)


func test_merge_remote_rules() -> void:
	var st := _state()
	st.data["progress"]["c01"] = {"completed": true, "best": 3, "par": 1, "stars": 2, "completedAt": 5, "kind": "campaign"}
	st.data["settings"]["updatedAt"] = 100
	st.data["settings"]["sfx"] = true
	st.merge_remote({
		"progress": [
			{"levelId": "c01", "kind": "campaign", "bestRotations": 1, "par": 1, "completedAt": 9},
			{"levelId": "c02", "kind": "campaign", "bestRotations": 4, "par": 2, "completedAt": 9},
		],
		"settings": {"sfx": false, "updatedAt": 50},
		"stats": {"dailies": 3, "endless": 7},
		"achievements": ["regular"],
	})
	eq(st.data["progress"]["c01"]["best"], 1, "best = min")
	check(st.data["progress"].has("c02"), "remote completion added (union)")
	eq(st.data["settings"]["sfx"], true, "older remote settings ignored")
	eq(st.data["stats"]["campaign"], 2)
	eq(st.data["stats"]["dailies"], 3)
	eq(st.data["endless"]["count"], 7)
	check(st.data["achievements"].has("regular"), "achievements union")
	st.merge_remote({"settings": {"sfx": false, "updatedAt": 200}})
	eq(st.data["settings"]["sfx"], false, "newer remote settings win")
	# Remote never removes local completions.
	st.merge_remote({"progress": []})
	check(st.data["progress"].has("c01"), "completions are monotonic")


func test_unlocking_is_generous() -> void:
	var st := _state()
	check(st.is_unlocked(0) and st.is_unlocked(2), "first three open")
	check(not st.is_unlocked(3), "fourth locked initially")
	st.data["progress"]["c01"] = {"completed": true, "best": 1, "par": 1}
	check(st.is_unlocked(3), "solving one opens another")


func test_endless_is_deterministic_and_ramps() -> void:
	var st := _state()
	st.data["endless"]["seedBase"] = 1234
	var a = st.endless_level()
	var b = st.endless_level()
	check(a != null, "endless level generated")
	eq(a["tiles"], b["tiles"], "same counter -> same puzzle (resume-safe)")
	eq(LFGameState.endless_tier(0), "easy")
	eq(LFGameState.endless_tier(40), "expert")


func test_daily_offline_practice_is_labelled_and_reproducible() -> void:
	var a = LFGameState.offline_daily_level("2026-10-15")
	var b = LFGameState.offline_daily_level("2026-10-15")
	check(a != null, "practice level")
	eq(a["tiles"], b["tiles"], "same date same practice puzzle")
	check(str(a["id"]).begins_with("offline-"), "never uses an official id")
	check(str(a["name"]).begins_with("Practice"), "clearly labelled")
	eq(LFGameState.daily_tier("2026-10-15"), "hard", "Thursday tier")


func test_offline_practice_never_queues_ranked_submission() -> void:
	var st := _state()
	var lvl = LFGameState.offline_daily_level("2026-10-15")
	st.start_level("offline_daily", lvl)
	_solve_active(st)
	st.complete_active()
	eq(st.data["syncQueue"].filter(func(o): return o["type"] == "daily_submit").size(), 0)


func test_daily_completion_queues_replay_submission() -> void:
	var st := _state()
	var lvl: Dictionary = campaign[10].duplicate(true)
	lvl["id"] = "daily-2026-10-15"
	lvl["date"] = "2026-10-15"
	st.start_level("daily", lvl)
	st.active()["date"] = "2026-10-15"
	_solve_active(st)
	st.complete_active()
	var subs: Array = st.data["syncQueue"].filter(func(o): return o["type"] == "daily_submit")
	eq(subs.size(), 1)
	eq(subs[0]["payload"]["date"], "2026-10-15")
	eq(subs[0]["payload"]["moves"].size(), lvl["par"])
	eq(st.data["stats"]["dailies"], 1)
