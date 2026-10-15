class_name LFRng
extends RefCounted
## xorshift32 PRNG + FNV-1a. Must produce identical streams to packages/engine/src/rng.ts.

const MASK32 := 0xFFFFFFFF
var state: int


static func fnv1a32(text: String) -> int:
	var h := 0x811c9dc5
	for b in text.to_utf8_buffer():
		h = h ^ b
		h = (h * 16777619) & MASK32
	return h


func _init(seed: int) -> void:
	var s := (seed & MASK32) ^ 0x9e3779b9
	if s == 0:
		s = 0x6d2b79f5
	state = s
	for i in 8:
		next_u32()


func next_u32() -> int:
	var x := state
	x = x ^ ((x << 13) & MASK32)
	x = x ^ (x >> 17)
	x = x ^ ((x << 5) & MASK32)
	state = x
	return x


func int_n(n: int) -> int:
	assert(n > 0)
	return next_u32() % n


func range_i(lo: int, hi: int) -> int:
	return lo + int_n(hi - lo + 1)


func chance(pct: int) -> bool:
	return int_n(100) < pct


func shuffle(arr: Array) -> Array:
	var i := arr.size() - 1
	while i > 0:
		var j := int_n(i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
		i -= 1
	return arr


func pick(arr: Array) -> Variant:
	return arr[int_n(arr.size())]
