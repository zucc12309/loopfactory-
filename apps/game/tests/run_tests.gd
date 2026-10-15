extends SceneTree
## Headless test runner:  godot --headless --path apps/game -s res://tests/run_tests.gd
## Runs every test_*.gd file in res://tests and exits non-zero on failure.

func _initialize() -> void:
	var files: Array = []
	var dir := DirAccess.open("res://tests")
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	var total := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()
	var assertions := 0
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		var inst = script.new()
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			inst.current = f + "::" + name
			var before: int = inst.failures.size()
			inst.call(name)
			if inst.failures.size() > before:
				failed += 1
				for msg in inst.failures.slice(before, before + 5):
					printerr("FAIL ", msg)
			else:
				print("ok   ", f, "::", name)
		assertions += inst.assertions
	print("\n%d tests, %d assertions, %d failed (%d ms)" % [total, assertions, failed, Time.get_ticks_msec() - t0])
	quit(1 if failed > 0 else 0)
