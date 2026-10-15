extends LFTestCase
## Upgrade features: experiments, progressive hints, attempts, replays, worlds, analytics taxonomy.

var campaign: Array = []
var ach: Array = []


func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/curated.json"))
	for l in data["levels"]:
		campaign.append(LFTiles.normalize_level(l))
	ach = JSON.parse_string(FileAccess.get_file_as_string("res://data/achievements.json"))["achievements"]


func _state() -> LFGameState:
	return LFGameState.new(campaign, ach)


func _solve(st: LFGameState) -> void:
	for mv in st.active_level()["solution"]["moves"]:
		st.rotate(int(mv[0]), int(mv[1]))


# ------------------------------------------------------------------ experiments

func test_experiments_default_to_control_without_remote_config() -> void:
	var data := LFGameState.defaults()
	for key in LFFlags.EXPERIMENTS:
		eq(LFFlags.resolve(data, key), LFFlags.EXPERIMENTS[key][0], key)
	eq(LFFlags.active_assignments(data), {})
	data["remoteConfig"] = {"experiments": {"celebration_ms": {"enabled": false, "weights": [0, 100]}}}
	eq(LFFlags.resolve(data, "celebration_ms"), 1200, "disabled experiment stays control")


func test_experiment_bucketing_is_stable_and_weighted() -> void:
	var counts := {1200: 0, 800: 0}
	for i in 2000:
		var data := {"analyticsId": "player-%d" % i, "remoteConfig": {"experiments": {"celebration_ms": {"enabled": true, "weights": [50, 50]}}}}
		var v = LFFlags.resolve(data, "celebration_ms")
		eq(LFFlags.resolve(data, "celebration_ms"), v, "stable")
		counts[v] += 1
	check(counts[1200] > 850 and counts[800] > 850, "roughly 50/50 split: %s" % counts)
	var all_b := {"analyticsId": "x", "remoteConfig": {"experiments": {"tutorial_flow": {"enabled": true, "weights": [0, 100]}}}}
	eq(LFFlags.resolve(all_b, "tutorial_flow"), "tips_only")
	var forced := {"analyticsId": "x", "remoteConfig": {"experiments": {"daily_entry": {"force": "banner"}}}}
	eq(LFFlags.resolve(forced, "daily_entry"), "banner")
	eq(LFFlags.active_assignments(forced), {"daily_entry": "banner"})
	var bogus := {"analyticsId": "x", "remoteConfig": {"experiments": {"daily_entry": {"force": "nope"}}}}
	eq(LFFlags.resolve(bogus, "daily_entry"), "card", "unknown forced variant falls back to control")


func test_gentle_ramp_stays_longer_in_each_tier() -> void:
	eq(LFGameState.endless_tier(6), "medium")
	eq(LFGameState.endless_tier(6, "gentle"), "easy")
	eq(LFGameState.endless_tier(20, "gentle"), "medium")
	eq(LFGameState.endless_tier(60, "gentle"), "expert")


# ------------------------------------------------------------------ hints & attempts

func test_progressive_hints_escalate_per_suggestion() -> void:
	var st := _state()
	st.start_level("campaign", campaign[5])
	eq(st.next_hint_step(7), 1)
	eq(st.next_hint_step(7), 2)
	eq(st.next_hint_step(7), 3)
	eq(st.next_hint_step(7), 3, "caps at 3")
	eq(st.next_hint_step(9), 1, "a new suggested tile restarts at step 1")
	eq(st.active()["hints"], 5, "each step counts as a hint")


func test_hint_is_always_a_move_toward_a_verified_solution() -> void:
	# Follow the hint system from the start until solved: every suggestion must be legal and the
	# total must equal par (hints come from the optimal solution).
	for idx in [0, 4, 5, 12, 20, 26]:
		var lvl: Dictionary = campaign[idx]
		var rots := LFTiles.start_rotations(lvl)
		var used := 0
		for guard in 60:
			var h = LFSolver.hint(lvl, rots)
			if h == null:
				break
			check(LFTiles.is_rotatable(lvl["tiles"][h["tile"]]), "hint targets a rotatable tile")
			rots[h["tile"]] = (int(rots[h["tile"]]) + int(h["dir"]) + 4) & 3
			used += 1
		check(LFSimulation.is_solved(lvl, rots), "following hints solves %s" % lvl["id"])
		eq(used, int(lvl["par"]), "hints reach par on %s" % lvl["id"])


func test_runs_are_counted_into_daily_attempts() -> void:
	var st := _state()
	var lvl = LFGameState.offline_daily_level("2026-10-14")
	lvl["date"] = "2026-10-14"
	st.start_level("daily", lvl)
	st.active()["date"] = "2026-10-14"
	st.record_run()
	st.record_run()
	_solve(st)
	st.record_run()
	var res := st.complete_active()
	eq(res["runs"], 3)
	eq(st.data["daily"]["results"]["2026-10-14"]["attempts"], 3)
	st.start_level("daily", lvl)
	st.active()["date"] = "2026-10-14"
	_solve(st)
	st.record_run()
	st.complete_active()
	eq(st.data["daily"]["results"]["2026-10-14"]["attempts"], 4, "attempts accumulate across solves")


# ------------------------------------------------------------------ replays

func test_best_solution_is_stored_as_a_verifiable_replay() -> void:
	var st := _state()
	var lvl: Dictionary = campaign[5]
	st.start_level("campaign", lvl)
	var first: Array = lvl["solution"]["moves"][0]
	st.rotate(int(first[0]), 1)
	st.rotate(int(first[0]), -1)
	_solve(st)
	st.complete_active()
	var rp = st.replay_for(lvl["id"])
	check(rp != null, "replay stored")
	eq(rp["moves"].size(), int(lvl["par"]) + 2)
	var rots = LFTiles.apply_moves(lvl, rp["moves"], LFTiles.start_rotations(lvl))
	check(LFSimulation.is_solved(lvl, rots), "replay re-solves the level")
	# A worse solve keeps the better replay; a better one replaces it.
	st.start_level("campaign", lvl)
	for k in 4:
		st.rotate(int(first[0]), 1)
	_solve(st)
	st.complete_active()
	eq(st.replay_for(lvl["id"])["moves"].size(), int(lvl["par"]) + 2, "worse solve keeps best replay")
	st.start_level("campaign", lvl)
	_solve(st)
	st.complete_active()
	eq(st.replay_for(lvl["id"])["moves"].size(), int(lvl["par"]), "better solve replaces replay")


func test_generated_replays_carry_their_level() -> void:
	var st := _state()
	var lvl = st.endless_level()
	st.start_level("endless", lvl)
	_solve(st)
	st.complete_active()
	var rp = st.replay_for(LFGameState.progress_key("endless", lvl))
	check(rp != null and rp.has("level"), "endless replay embeds the generated level")


func test_challenge_completion_never_queues_ranked_ops() -> void:
	var st := _state()
	st.start_level("challenge", campaign[5])
	_solve(st)
	var before: int = st.data["syncQueue"].size()
	var res := st.complete_active()
	check(not res.is_empty(), "completes")
	eq(st.data["syncQueue"].size(), before, "challenge results go through the challenge endpoint only")
	eq(st.data["stats"]["challenges"], 1)


# ------------------------------------------------------------------ content & worlds

func test_every_campaign_level_belongs_to_a_world_in_order() -> void:
	var seen := -1
	for i in campaign.size():
		var w := LFWorlds.index_for(campaign, i)
		check(w >= seen, "world index never decreases (%s)" % campaign[i]["id"])
		seen = w
	eq(seen, LFWorlds.WORLDS.size() - 1, "last level is in the last world")
	var covered := 0
	for w in LFWorlds.WORLDS.size():
		var r := LFWorlds.range_for(campaign, w)
		check(r.y > r.x, "world %d has levels" % w)
		covered += r.y - r.x
	eq(covered, campaign.size(), "worlds partition the campaign")
	for k in LFWorlds.WORLDS.size():
		var pal: Dictionary = LFWorlds.WORLDS[k]
		# Belt vs plate contrast keeps boards readable in every theme.
		var d := absf(pal["belt"].get_luminance() - pal["plate"].get_luminance())
		check(d > 0.05, "%s belt/plate luminance gap %.3f" % [pal["id"], d])


func test_transition_levels_teach_one_idea() -> void:
	var idx: Dictionary = {}
	for i in campaign.size():
		idx[campaign[i]["id"]] = i
	check(idx["x26"] < idx["c26"], "Right of Way comes before Interchange")
	check(idx["x31"] < idx["c31"], "Third Shift comes before Tri-Color")
	# x26 must actually make a package wait (the mechanic its tip teaches).
	var lvl: Dictionary = campaign[idx["x26"]]
	var res := LFSimulation.simulate(lvl, lvl["solution"]["rotations"])
	var waited := false
	for f in res["frames"]:
		for p in f["packages"]:
			if p["state"] == "waiting":
				waited = true
	check(res["success"] and waited, "x26 solution demonstrates waiting")


# ------------------------------------------------------------------ analytics

func test_every_tracked_event_is_in_the_taxonomy() -> void:
	var consts: Dictionary = load("res://scripts/core/analytics.gd").get_script_constant_map()
	var events: Array = consts["EVENTS"]
	var re := RegEx.create_from_string("Analytics\\.track\\(\"([a-z_]+)\"")
	var found := 0
	for dir in ["res://scripts/core", "res://scripts/ui", "res://scripts/ui/screens"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var src := FileAccess.get_file_as_string(dir.path_join(f))
			for m in re.search_all(src):
				found += 1
				check(events.has(m.get_string(1)), "event %s (%s) is declared" % [m.get_string(1), f])
	check(found >= 15, "scanned the tracking calls (%d)" % found)
	for e in ["first_launch", "tutorial_start", "tutorial_complete", "level_start", "level_complete", "level_fail", "level_retry", "hint_used", "daily_challenge_entry", "daily_challenge_completed", "share_completed", "challenge_link_opened", "challenge_completed", "session_end", "app_background", "app_resume"]:
		check(events.has(e), "required event %s" % e)
