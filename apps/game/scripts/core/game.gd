extends Node
## Autoload "Game": owns LFGameState, autosaves after every meaningful change, and persists on
## interruption (app paused/backgrounded/closed). Screens talk to this node, never to files.

signal state_changed
signal achievements_unlocked(list: Array)
signal cosmetics_unlocked(list: Array)
signal settings_changed

var state: LFGameState
var store := LFSaveStore.new("user://save.json")
var _save_pending := false
var load_source := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var campaign := _load_campaign()
	var ach: Array = _read_json("res://data/achievements.json").get("achievements", [])
	state = LFGameState.new(campaign, ach)
	state.load_from(store.load_data())
	load_source = store.last_load_source
	state.data["stats"]["sessions"] += 1
	save_now()


func _load_campaign() -> Array:
	var raw: Dictionary = _read_json("res://data/levels/curated.json")
	var out: Array = []
	for l in raw.get("levels", []):
		out.append(LFTiles.normalize_level(l))
	return out


static func _read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Coalesce many changes in one frame into a single write.
func request_save() -> void:
	state_changed.emit()
	if _save_pending:
		return
	_save_pending = true
	call_deferred("_flush")


func _flush() -> void:
	_save_pending = false
	save_now()


func save_now() -> void:
	if not store.save(state.data):
		push_warning("Save failed: " + store.last_error)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST:
			save_now()


# Convenience wrappers used by screens -------------------------------------------------

func settings() -> Dictionary:
	return state.data["settings"]


func set_setting(key: String, value: Variant) -> void:
	state.set_setting(key, value)
	settings_changed.emit()
	request_save()


func complete_active() -> Dictionary:
	var res := state.complete_active()
	if not res.is_empty():
		if not res["achievements"].is_empty():
			achievements_unlocked.emit(res["achievements"])
		if not res.get("cosmetics", []).is_empty():
			cosmetics_unlocked.emit(res["cosmetics"])
		request_save()
	return res


## Wipe local data (after account deletion or "reset progress").
func wipe_local() -> void:
	store.wipe()
	state.data = LFGameState.defaults()
	save_now()
	state_changed.emit()
