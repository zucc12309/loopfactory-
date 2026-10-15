extends LFTestCase
## Every script in the project must parse and compile (catches errors in UI code that unit tests
## don't import).


func _collect(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	for d in dir.get_directories():
		_collect(dir_path.path_join(d), out)
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))


func test_all_scripts_compile() -> void:
	var files: Array = []
	_collect("res://scripts", files)
	check(files.size() > 15, "expected to find project scripts")
	for f in files:
		var s: Script = load(f)
		check(s != null and s.can_instantiate(), "%s failed to compile" % f)
