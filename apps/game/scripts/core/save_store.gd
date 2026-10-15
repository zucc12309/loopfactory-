class_name LFSaveStore
extends RefCounted
## Crash-safe JSON persistence.
##  - Envelope: {"schema": N, "checksum": sha256(payload), "payload": "<json string>"}
##  - Writes go to <file>.tmp first, the previous good file is kept as <file>.bak, then the temp file
##    is renamed into place. Rename is atomic on Android/iOS/Linux filesystems.
##  - Loading verifies the checksum and falls back main → tmp → bak. Corrupt files are preserved as
##    <file>.corrupt for diagnosis and never crash the game.
##  - Schema migrations run on load (see migrate()).

const SCHEMA := 1

var path: String
var last_load_source := ""  # "main", "tmp", "bak", "default"
var last_error := ""


func _init(p_path: String = "user://save.json") -> void:
	path = p_path


func save(data: Dictionary) -> bool:
	var payload := JSON.stringify(data)
	var envelope := JSON.stringify({"schema": SCHEMA, "checksum": payload.sha256_text(), "payload": payload})
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "open tmp failed: %s" % error_string(FileAccess.get_open_error())
		return false
	f.store_string(envelope)
	f.flush()
	f.close()
	var abs_main := ProjectSettings.globalize_path(path)
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	var abs_bak := ProjectSettings.globalize_path(path + ".bak")
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(abs_bak)
		DirAccess.rename_absolute(abs_main, abs_bak)
	var err := DirAccess.rename_absolute(abs_tmp, abs_main)
	if err != OK:
		last_error = "rename failed: %s" % error_string(err)
		return false
	return true


## Returns the stored dictionary, or {} when nothing valid exists.
func load_data() -> Dictionary:
	for candidate in [[path, "main"], [path + ".tmp", "tmp"], [path + ".bak", "bak"]]:
		var p: String = candidate[0]
		if not FileAccess.file_exists(p):
			continue
		var data = _read(p)
		if data is Dictionary:
			last_load_source = candidate[1]
			return data
		_quarantine(p)
	last_load_source = "default"
	return {}


## Remove the save. `everything` also removes quarantined .corrupt copies (explicit deletion only).
func wipe(everything := false) -> void:
	var suffixes := ["", ".tmp", ".bak"]
	if everything:
		suffixes += [".corrupt", ".tmp.corrupt", ".bak.corrupt"]
	for suffix in suffixes:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _read(p: String) -> Variant:
	var text := FileAccess.get_file_as_string(p)
	if text.is_empty():
		last_error = "empty file " + p
		return null
	var env = JSON.parse_string(text)
	if not (env is Dictionary) or not env.has("payload") or not env.has("checksum"):
		last_error = "malformed envelope " + p
		return null
	var payload: String = str(env["payload"])
	if payload.sha256_text() != str(env["checksum"]):
		last_error = "checksum mismatch " + p
		return null
	var data = JSON.parse_string(payload)
	if not (data is Dictionary):
		last_error = "malformed payload " + p
		return null
	return migrate(int(env.get("schema", 0)), data)


func _quarantine(p: String) -> void:
	var dst := p + ".corrupt"
	if FileAccess.file_exists(dst):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dst))
	DirAccess.copy_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(dst))


## Upgrade older save schemas in place. Add a branch per schema bump.
static func migrate(from_schema: int, data: Dictionary) -> Dictionary:
	var d := data
	if from_schema < 1:
		# Pre-release saves had no envelope schema; nothing structural changed.
		pass
	return d
