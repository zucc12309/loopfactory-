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
	var had_save := FileAccess.file_exists(store.path) or FileAccess.file_exists(store.path + ".bak")
	state.load_from(store.load_data())
	load_source = store.last_load_source
	state.data["stats"]["sessions"] += 1
	save_now()
	if load_source == "tmp" or load_source == "bak" or (load_source == "default" and had_save):
		# A damaged main save was recovered from a backup (or nothing usable was left).
		LFDiagnostics.record.call_deferred("save_recovered", load_source == "default", {"source": load_source})


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
		LFDiagnostics.record("save_failed", false, {"error": store.last_error})


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


## Wipe local data (after account deletion or "reset progress"): the save and its backups,
## quarantined corrupt copies, the analytics queue, diagnostics, exported data and share images.
## Ordinary saves never touch the backups; only this explicit deletion removes them.
func wipe_local() -> void:
	store.wipe(true)
	Analytics.clear()
	LFDiagnostics.clear()
	for f in ["user://loop-factory-export.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	_remove_dir("user://share")
	state.data = LFGameState.defaults()
	save_now()
	state_changed.emit()


static func _remove_dir(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir_path))


## Every local file holding player data (for tests and the deletion audit).
func residual_files() -> Array:
	var out: Array = []
	for f in [store.path, store.path + ".tmp", store.path + ".bak", store.path + ".corrupt", store.path + ".tmp.corrupt", store.path + ".bak.corrupt", Analytics.queue_path, LFDiagnostics.path, "user://loop-factory-export.json"]:
		if FileAccess.file_exists(f):
			out.append(f)
	var d := DirAccess.open("user://share")
	if d != null:
		for f in d.get_files():
			out.append("user://share/" + f)
	return out
