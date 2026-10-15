class_name LFDialogue
## Data-driven character dialogue (data/crew/dialogue.<locale>.json). Works fully offline.
##
## Each line: id, character, event, text, priority, cooldown (seconds), probability (0..1),
## anim (expression), optional `when` conditions and optional `locale`. Selection is a pure
## function (`pick`) so it can be unit-tested; LFCrew.say() adds settings, flags, persistence and
## analytics.
##
## Localisation: the English file is the source of truth. A translation file
## (dialogue.hi.json, …) only needs {"lines": [{"id", "text"}]}; missing ids fall back to English.
## Translations must be written or reviewed by a fluent speaker; nothing is machine-translated
## (docs/CHARACTER_SYSTEM.md#localisation).

const EVENTS := [
	"FIRST_LAUNCH", "HOME_IDLE", "HOME_TAP", "LEVEL_START", "NEW_WORLD", "NEW_MECHANIC",
	"FIRST_SUCCESS", "SUCCESS", "PERFECT_SCORE", "UNUSUALLY_EFFICIENT", "ALL_TOGETHER", "NEAR_MISS",
	"FAILED_ATTEMPT", "DAILY_CHALLENGE", "CHARACTER_UNLOCK", "COLLECTION",
]

static var _cache := {}


static func locale() -> String:
	var l := OS.get_locale_language()
	return l if l != "" else "en"


## English lines with any translated `text` for `loc` merged in by id.
static func lines(loc := "en", base_path := "res://data/crew/dialogue.en.json") -> Array:
	var key := loc + "|" + base_path
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var base = _read(base_path)
	if base is Dictionary:
		for l in base.get("lines", []):
			if l is Dictionary and l.has("id") and l.has("event") and l.has("text"):
				out.append(l)
	if loc != "en":
		var tr = _read(base_path.replace(".en.json", ".%s.json" % loc))
		if tr is Dictionary:
			var by_id := {}
			for l in tr.get("lines", []):
				if l is Dictionary and l.has("id") and l.has("text"):
					by_id[str(l["id"])] = str(l["text"])
			for i in out.size():
				if by_id.has(str(out[i]["id"])):
					var copy: Dictionary = out[i].duplicate()
					copy["text"] = by_id[str(out[i]["id"])]
					copy["locale"] = loc
					out[i] = copy
	_cache[key] = out
	return out


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _matches(line: Dictionary, ctx: Dictionary) -> bool:
	var when = line.get("when")
	if not (when is Dictionary):
		return true
	for k in when:
		if not ctx.has(k) or str(ctx[k]) != str(when[k]):
			return false
	return true


## Choose a line for `event`, or {} for none.
##  * Only lines whose `when` conditions all match `ctx` and whose cooldown has expired.
##  * The highest priority group wins; `roll` (0..1) must fall under its probability.
##  * Within the group the least recently shown line is preferred, ties broken by `roll`.
static func pick(all: Array, event: String, ctx: Dictionary, seen: Dictionary, now_ms: int, roll: float) -> Dictionary:
	var best_p := -INF
	var group: Array = []
	for l in all:
		if str(l["event"]) != event or not _matches(l, ctx):
			continue
		var last := int(seen.get(str(l["id"]), -1))
		var cd := float(l.get("cooldown", 0))
		if last >= 0 and (cd < 0.0 or now_ms - last < int(cd * 1000.0)):
			continue  # cooldown -1 = show once ever
		var pr := float(l.get("priority", 0))
		if pr > best_p:
			best_p = pr
			group = [l]
		elif pr == best_p:
			group.append(l)
	if group.is_empty():
		return {}
	var prob := 0.0
	for l in group:
		prob = maxf(prob, float(l.get("probability", 1.0)))
	if roll >= prob:
		return {}
	var oldest := INF
	var cands: Array = []
	for l in group:
		var last := float(seen.get(str(l["id"]), -1))
		if last < oldest:
			oldest = last
			cands = [l]
		elif last == oldest:
			cands.append(l)
	return cands[int(roll / maxf(prob, 0.0001) * cands.size()) % cands.size()]


## Replace {name} style placeholders.
static func format(text: String, vars: Dictionary) -> String:
	var out := text
	for k in vars:
		out = out.replace("{%s}" % k, str(vars[k]))
	return out
