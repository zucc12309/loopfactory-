class_name LFGameState
extends RefCounted
## All persistent player state and the rules that change it. Pure logic (no nodes) so it can be
## unit-tested headless; the Game autoload wraps it with signals, autosave and lifecycle handling.

const DAILY_TIERS := ["expert", "easy", "medium", "medium", "hard", "hard", "expert"]  # Sun..Sat (UTC)
const ENDLESS_SEED_STEP := 7919

var data: Dictionary = {}
var campaign: Array = []  # normalized curated levels
var campaign_index := {}  # id -> index
var achievements_def: Array = []


func _init(p_campaign: Array = [], p_achievements: Array = []) -> void:
	campaign = p_campaign
	for i in campaign.size():
		campaign_index[campaign[i]["id"]] = i
	achievements_def = p_achievements
	data = defaults()


static func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


static func uuid4() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


static func defaults() -> Dictionary:
	return {
		"player": {"localId": uuid4(), "createdAt": now_ms()},
		"settings": {
			"sfx": true, "music": true, "haptics": true, "reducedMotion": false, "colorblind": false,
			"analytics": false, "analyticsAsked": false, "cloudSync": true, "updatedAt": 0,
			"crewCharacters": true, "crewAnimations": true, "mascotDialogue": true,
		},
		"progress": {},
		"active": null,
		"stats": {"campaign": 0, "perfect": 0, "dailies": 0, "endless": 0, "rotations": 0, "hints": 0, "sessions": 0, "challenges": 0},
		"onboarding": {"tutorialStarted": false, "tutorialDone": false},
		"challenges": {"created": {}, "played": {}},
		# Interdimensional Delivery Crew: cosmetic unlocks/equips and dialogue cooldowns (LFCrew).
		"crew": {"equipped": {}, "unlocked": {}, "seen": {}, "dialogue": {}, "celebration": ""},
		"endless": {"count": 0, "seedBase": randi() & 0x7fffffff},
		"daily": {"cache": {}, "results": {}},
		"achievements": {},
		"auth": {"playerId": "", "refreshToken": "", "displayName": ""},
		"syncQueue": [],
		"remoteConfig": {},
		"entitlements": {"noAds": false, "themes": ["classic"]},
		"theme": "classic",
		"analyticsId": uuid4(),
	}


## Merge a loaded save over defaults so new fields appear after updates.
func load_from(saved: Dictionary) -> void:
	var d := defaults()
	for k in saved:
		if d.has(k) and d[k] is Dictionary and saved[k] is Dictionary:
			var merged: Dictionary = d[k].duplicate(true)
			merged.merge(saved[k], true)
			d[k] = merged
		else:
			d[k] = saved[k]
	data = d
	# Defensive: drop an active puzzle that no longer validates (e.g. content update).
	if data["active"] != null and not _active_valid(data["active"]):
		data["active"] = null
	LFCrew.sanitize(data)
	# Cosmetics are derived from progress, so existing players receive what they already earned.
	LFCrew.evaluate_unlocks(data, campaign, now_ms())


func _active_valid(a: Variant) -> bool:
	if not (a is Dictionary) or not a.has("level"):
		return false
	var lvl: Dictionary = LFTiles.normalize_level(a["level"])
	if LFTiles.validate_board(lvl) != "":
		return false
	var rot: Array = a.get("rotations", [])
	if rot.size() != lvl["tiles"].size():
		return false
	# Replaying history from the start must reproduce the saved rotations.
	var replay = LFTiles.apply_moves(lvl, a.get("history", []), LFTiles.start_rotations(lvl))
	if replay == null:
		return false
	for i in rot.size():
		if int(replay[i]) != int(rot[i]):
			return false
	return true


# ---------------------------------------------------------------- active puzzle

func start_level(kind: String, level: Dictionary) -> Dictionary:
	data["active"] = {
		"kind": kind, "levelId": level["id"], "level": level,
		"rotations": LFTiles.start_rotations(level), "history": [], "hints": 0, "runs": 0,
		"hintTile": -1, "hintStep": 0,
		"startedAt": now_ms(), "updatedAt": now_ms(),
	}
	return data["active"]


func active() -> Variant:
	return data["active"]


func active_level() -> Dictionary:
	return LFTiles.normalize_level(data["active"]["level"])


func rotate(index: int, dir: int) -> bool:
	var a = data["active"]
	if a == null:
		return false
	var lvl: Dictionary = a["level"]
	if index < 0 or index >= lvl["tiles"].size() or not LFTiles.is_rotatable(lvl["tiles"][index]) or (dir != 1 and dir != -1):
		return false
	a["rotations"][index] = (int(a["rotations"][index]) + dir + 4) & 3
	a["history"].append([index, dir])
	a["updatedAt"] = now_ms()
	return true


## Returns the undone move [index, dir] or null.
func undo() -> Variant:
	var a = data["active"]
	if a == null or a["history"].is_empty():
		return null
	var mv: Array = a["history"].pop_back()
	a["rotations"][int(mv[0])] = (int(a["rotations"][int(mv[0])]) - int(mv[1]) + 4) & 3
	a["updatedAt"] = now_ms()
	return mv


func reset() -> void:
	var a = data["active"]
	if a == null:
		return
	a["rotations"] = LFTiles.start_rotations(a["level"])
	a["history"] = []
	a["updatedAt"] = now_ms()


func moves_count() -> int:
	return 0 if data["active"] == null else data["active"]["history"].size()


func record_hint() -> void:
	if data["active"] != null:
		data["active"]["hints"] += 1
		data["stats"]["hints"] += 1


## Progressive hints: asking again about the same suggested tile reveals more (1 = area,
## 2 = tile, 3 = tile + rotation). A new suggestion (after the player moved on) starts at 1.
func next_hint_step(tile: int) -> int:
	var a = data["active"]
	if a == null:
		return 0
	if int(a.get("hintTile", -1)) == tile:
		a["hintStep"] = mini(3, int(a.get("hintStep", 0)) + 1)
	else:
		a["hintTile"] = tile
		a["hintStep"] = 1
	record_hint()
	return int(a["hintStep"])


## Count a press of Run (attempts are shown on daily results and challenge comparisons).
func record_run() -> int:
	var a = data["active"]
	if a == null:
		return 0
	a["runs"] = int(a.get("runs", 0)) + 1
	return int(a["runs"])


static func stars_for(moves: int, par: int) -> int:
	if moves <= par:
		return 3
	if moves <= par + 3:
		return 2
	return 1


## Call after the simulation reported success. Verifies the win locally, updates progress, stats and
## achievements, queues a sync operation and clears the active puzzle.
func complete_active() -> Dictionary:
	var a: Dictionary = data["active"]
	var lvl: Dictionary = LFTiles.normalize_level(a["level"])
	var rotations: Array = a["rotations"]
	if not LFSimulation.is_solved(lvl, rotations):
		return {}
	var moves: int = a["history"].size()
	var par: int = lvl["par"]
	var kind: String = a["kind"]
	var key := progress_key(kind, lvl)
	var prev = data["progress"].get(key)
	var first := prev == null
	var best := moves if first else mini(int(prev["best"]), moves)
	var entry := {
		"completed": true, "best": best, "par": par, "stars": stars_for(best, par),
		"completedAt": now_ms() if first else int(prev["completedAt"]), "kind": kind,
	}
	# Keep the best solution as a deterministic replay (moves from the level's start rotations).
	if first or moves < int(prev["best"]) or not prev.has("replay"):
		entry["replay"] = {"v": 1, "levelId": lvl["id"], "contentVersion": lvl["version"], "moves": a["history"].duplicate(true), "rotations": moves}
		if kind != "campaign":
			entry["replay"]["level"] = lvl
	else:
		entry["replay"] = prev["replay"]
	data["progress"][key] = entry
	data["stats"]["rotations"] += moves
	if first or (int(prev["best"]) > par and best <= par):
		if best <= par:
			data["stats"]["perfect"] += 1
	if first:
		match kind:
			"campaign":
				data["stats"]["campaign"] += 1
			"endless":
				data["stats"]["endless"] += 1
			"daily", "offline_daily":
				if kind == "daily":
					data["stats"]["dailies"] += 1
			"challenge":
				data["stats"]["challenges"] += 1
	if kind == "endless":
		data["endless"]["count"] += 1
	var history: Array = a["history"].duplicate(true)
	var op_payload := {
		"kind": kind, "levelId": lvl["id"], "contentVersion": lvl["version"], "moves": history,
		"rotations": moves, "hints": a["hints"], "completedAt": now_ms(),
	}
	if kind == "endless" and lvl.get("generator") is Dictionary:
		op_payload["generator"] = lvl["generator"]
	if kind == "daily":
		var date: String = str(a.get("date", lvl.get("date", "")))
		var prev_d: Dictionary = data["daily"]["results"].get(date, {})
		data["daily"]["results"][date] = {
			"rotations": mini(moves, int(prev_d.get("rotations", moves))), "submitted": false,
			"attempts": int(prev_d.get("attempts", 0)) + int(a.get("runs", 1)), "solves": int(prev_d.get("solves", 0)) + 1,
		}
		enqueue("daily_submit", {"date": date, "moves": history, "submissionId": uuid4()})
	elif kind != "offline_daily" and kind != "challenge":
		enqueue("level_complete", op_payload)
	var unlocked := evaluate_achievements()
	var cosmetics := LFCrew.evaluate_unlocks(data, campaign, now_ms())
	data["active"] = null
	return {"moves": moves, "par": par, "best": best, "stars": stars_for(moves, par), "first": first,
		"newBest": not first and moves < int(prev["best"]), "achievements": unlocked, "cosmetics": cosmetics, "kind": kind, "levelId": lvl["id"],
		"hints": int(a["hints"]), "runs": int(a.get("runs", 1)), "history": history, "level": lvl}


## Replay of the best solution for a progress key, or null.
func replay_for(key: String) -> Variant:
	var p = data["progress"].get(key)
	if p == null or not (p.get("replay") is Dictionary):
		return null
	return p["replay"]


static func progress_key(kind: String, lvl: Dictionary) -> String:
	if kind == "campaign":
		return lvl["id"]
	return "%s:%s" % [kind, lvl["id"]]


# ---------------------------------------------------------------- campaign

func campaign_completed(i: int) -> bool:
	return data["progress"].has(campaign[i]["id"])


func completed_count() -> int:
	var n := 0
	for i in campaign.size():
		if campaign_completed(i):
			n += 1
	return n


## Levels unlock progressively but generously: the next three unsolved levels are always open.
func is_unlocked(i: int) -> bool:
	var open := 0
	for j in i:
		if not campaign_completed(j):
			open += 1
	return open < 3


func next_campaign_index() -> int:
	for i in campaign.size():
		if not campaign_completed(i):
			return i
	return campaign.size() - 1


# ---------------------------------------------------------------- endless & daily

## `ramp` is the difficulty_ramp experiment: "gentle" stays 1.5× longer in each tier.
static func endless_tier(count: int, ramp := "standard") -> String:
	var k := 1.5 if ramp == "gentle" else 1.0
	if count < 5 * k:
		return "easy"
	if count < 15 * k:
		return "medium"
	if count < 35 * k:
		return "hard"
	return "expert"


func endless_level() -> Variant:
	var n: int = data["endless"]["count"]
	var seed: int = (int(data["endless"]["seedBase"]) + n * ENDLESS_SEED_STEP) & 0x7fffffff
	var tier := endless_tier(n, str(LFFlags.resolve(data, "difficulty_ramp")))
	return LFGenerator.generate_level_from(seed, tier, "", "Endless #%d" % (n + 1))


static func daily_tier(date: String) -> String:
	var parts := date.split("-")
	var unix := Time.get_unix_time_from_datetime_dict({"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]), "hour": 0, "minute": 0, "second": 0})
	var weekday: int = Time.get_datetime_dict_from_unix_time(unix)["weekday"]
	return DAILY_TIERS[weekday]


static func utc_date() -> String:
	return Time.get_date_string_from_system(true)


## A clearly-labelled practice puzzle for days when the official daily cannot be downloaded.
static func offline_daily_level(date: String) -> Variant:
	var seed := LFRng.fnv1a32("offline-daily-" + date)
	var lvl = LFGenerator.generate_level_from(seed, daily_tier(date), "offline-" + date, "Practice · " + date)
	return lvl


# ---------------------------------------------------------------- achievements

func evaluate_achievements() -> Array:
	var unlocked: Array = []
	for a in achievements_def:
		if data["achievements"].has(a["id"]):
			continue
		if int(data["stats"].get(a["metric"], 0)) >= int(a["threshold"]):
			data["achievements"][a["id"]] = now_ms()
			unlocked.append(a)
	return unlocked


# ---------------------------------------------------------------- settings

func set_setting(key: String, value: Variant) -> void:
	data["settings"][key] = value
	data["settings"]["updatedAt"] = now_ms()
	enqueue("settings", {"settings": data["settings"].duplicate(), "updatedAt": data["settings"]["updatedAt"]})


# ---------------------------------------------------------------- sync queue

const COALESCED := ["settings", "active_puzzle"]


func enqueue(type: String, payload: Dictionary) -> Dictionary:
	var q: Array = data["syncQueue"]
	if type in COALESCED:
		for i in range(q.size() - 1, -1, -1):
			if q[i]["type"] == type:
				q.remove_at(i)
	var op := {"opId": uuid4(), "type": type, "payload": payload, "clientTs": now_ms(), "attempts": 0, "nextAttemptAt": 0}
	q.append(op)
	# Bound the queue: settings/active snapshots are coalesced, completions are tiny.
	while q.size() > 500:
		q.remove_at(0)
	return op


func ack_ops(op_ids: Array) -> void:
	var ids := {}
	for id in op_ids:
		ids[id] = true
	data["syncQueue"] = data["syncQueue"].filter(func(op): return not ids.has(op["opId"]))


func retry_later(op_ids: Array, now: int) -> void:
	for op in data["syncQueue"]:
		if op["opId"] in op_ids:
			op["attempts"] += 1
			op["nextAttemptAt"] = now + mini(3600000, 2000 * int(pow(2, mini(op["attempts"], 11))))


func due_ops(now: int, limit := 50) -> Array:
	var out: Array = []
	for op in data["syncQueue"]:
		if int(op["nextAttemptAt"]) <= now:
			out.append(op)
			if out.size() >= limit:
				break
	return out


## Merge the server snapshot. Rules (docs/sync.md):
##  - completions are monotonic: union of both sides, best = min
##  - settings: last-writer-wins by updatedAt
##  - counters (dailies/endless): max of both sides; campaign/perfect recomputed from progress
##  - achievements: union
func merge_remote(snap: Dictionary) -> void:
	for entry in snap.get("progress", []):
		var key: String = progress_key(str(entry["kind"]), {"id": str(entry["levelId"])})
		var local = data["progress"].get(key)
		var remote_best := int(entry["bestRotations"])
		var par := int(entry.get("par", remote_best))
		if local == null:
			data["progress"][key] = {"completed": true, "best": remote_best, "par": par, "stars": stars_for(remote_best, par), "completedAt": int(entry.get("completedAt", now_ms())), "kind": str(entry["kind"])}
		elif remote_best < int(local["best"]):
			local["best"] = remote_best
			local["stars"] = stars_for(remote_best, int(local.get("par", par)))
	var rs = snap.get("settings")
	if rs is Dictionary and int(rs.get("updatedAt", 0)) > int(data["settings"].get("updatedAt", 0)):
		for k in rs:
			if data["settings"].has(k):
				data["settings"][k] = rs[k]
	var stats: Dictionary = snap.get("stats", {})
	for k in ["dailies", "endless"]:
		data["stats"][k] = maxi(int(data["stats"][k]), int(stats.get(k, 0)))
	data["endless"]["count"] = maxi(int(data["endless"]["count"]), int(stats.get("endless", 0)))
	var campaign_n := 0
	var perfect_n := 0
	for key in data["progress"]:
		var p: Dictionary = data["progress"][key]
		if campaign_index.has(key):
			campaign_n += 1
		if int(p["best"]) <= int(p.get("par", 0)):
			perfect_n += 1
	data["stats"]["campaign"] = campaign_n
	data["stats"]["perfect"] = maxi(perfect_n, int(data["stats"]["perfect"]))
	for id in snap.get("achievements", []):
		if not data["achievements"].has(id):
			data["achievements"][id] = now_ms()
	evaluate_achievements()
	LFCrew.evaluate_unlocks(data, campaign, now_ms())
