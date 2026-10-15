extends LFTestCase
## Persistence: atomic writes, checksum verification, fallback and corrupted-file recovery.

const P := "user://test_save.json"


func _store() -> LFSaveStore:
	var s := LFSaveStore.new(P)
	s.wipe()
	for suffix in [".corrupt", ".tmp.corrupt", ".bak.corrupt"]:
		if FileAccess.file_exists(P + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(P + suffix))
	return s


func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_roundtrip_and_backup() -> void:
	var s := _store()
	check(s.save({"a": 1}), "first save")
	check(s.save({"a": 2}), "second save")
	eq(s.load_data(), {"a": 2}, "latest data")
	eq(s.last_load_source, "main")
	check(FileAccess.file_exists(P + ".bak"), "previous version kept as backup")
	check(not FileAccess.file_exists(P + ".tmp"), "temp file renamed away")


func test_missing_file_gives_defaults() -> void:
	var s := _store()
	eq(s.load_data(), {})
	eq(s.last_load_source, "default")


func test_corrupted_main_falls_back_to_backup() -> void:
	var s := _store()
	s.save({"level": 3})
	s.save({"level": 4})
	_write_raw(P, "{\"schema\":1,\"checksum\":\"deadbeef\",\"payload\":\"{\\\"level\\\":99}\"}")
	eq(s.load_data(), {"level": 3}, "backup used when checksum fails")
	eq(s.last_load_source, "bak")
	check(FileAccess.file_exists(P + ".corrupt"), "corrupt file quarantined")


func test_truncated_file_never_crashes() -> void:
	var s := _store()
	s.save({"x": 1})
	_write_raw(P, "{\"schema\":1,\"chec")
	_write_raw(P + ".bak", "garbage")
	eq(s.load_data(), {}, "falls back to defaults")
	eq(s.last_load_source, "default")


func test_interrupted_write_recovers_from_tmp() -> void:
	var s := _store()
	s.save({"v": 1})
	# Simulate a crash after the temp file was written but before the rename.
	var payload := JSON.stringify({"v": 2})
	_write_raw(P + ".tmp", JSON.stringify({"schema": 1, "checksum": payload.sha256_text(), "payload": payload}))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(P))
	eq(s.load_data(), {"v": 2}, "temp file used when main is missing")
