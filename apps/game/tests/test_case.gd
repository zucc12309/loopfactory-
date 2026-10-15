class_name LFTestCase
extends RefCounted
## Minimal assertion helpers for the headless test runner (tests/run_tests.gd).

var failures: Array = []
var current := ""
var assertions := 0


func check(cond: bool, msg: String) -> void:
	assertions += 1
	if not cond:
		failures.append("%s: %s" % [current, msg])


func eq(actual: Variant, expected: Variant, msg := "") -> void:
	assertions += 1
	if not _deep_eq(actual, expected):
		failures.append("%s: %s expected %s got %s" % [current, msg, _short(expected), _short(actual)])


func _short(v: Variant) -> String:
	var s := str(v)
	return s if s.length() < 300 else s.substr(0, 300) + "…"


## Deep equality that treats JSON floats and ints as equal when numerically equal.
func _deep_eq(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _deep_eq(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _deep_eq(a[k], b[k]):
				return false
		return true
	if a == null or b == null:
		return a == null and b == null
	if typeof(a) != typeof(b):
		if (a is String or a is StringName) and (b is String or b is StringName):
			return str(a) == str(b)
		return false
	return a == b
