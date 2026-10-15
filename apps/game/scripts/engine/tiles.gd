class_name LFTiles
## Tile rules. Mirrors packages/engine/src/tiles.ts and directions.ts exactly.

const NORTH := 0
const EAST := 1
const SOUTH := 2
const WEST := 3
const DX := [0, 1, 0, -1]
const DY := [-1, 0, 1, 0]
const COLOR_COUNT := 4

const BASE_MASK := {
	"empty": 0, "blocked": 0, "straight": 5, "corner": 3, "tee": 7, "cross": 15, "source": 0, "dest": 15,
}
const PERIOD := {
	"empty": 1, "blocked": 1, "straight": 2, "corner": 4, "tee": 4, "cross": 1, "source": 4, "dest": 1,
}
const TYPES := ["empty", "blocked", "straight", "corner", "tee", "cross", "source", "dest"]


static func bit(d: int) -> int:
	return 1 << d


static func opposite(d: int) -> int:
	return (d + 2) & 3


static func turn_right(d: int) -> int:
	return (d + 1) & 3


static func turn_left(d: int) -> int:
	return (d + 3) & 3


static func rotate_mask(mask: int, times: int) -> int:
	var m := mask & 15
	var t := ((times % 4) + 4) % 4
	for i in t:
		m = ((m << 1) | (m >> 3)) & 15
	return m


static func is_rotatable(tile: Dictionary) -> bool:
	if tile.get("l", false):
		return false
	var t: String = tile["t"]
	return t == "straight" or t == "corner" or t == "tee"


static func input_mask(tile: Dictionary, r: int) -> int:
	if tile["t"] == "source":
		return 0
	return rotate_mask(BASE_MASK[tile["t"]], r)


static func output_mask(tile: Dictionary, r: int) -> int:
	var t: String = tile["t"]
	if t == "source":
		return bit(r & 3)
	if t == "dest":
		return 0
	return rotate_mask(BASE_MASK[t], r)


static func connection_mask(tile: Dictionary, r: int) -> int:
	return input_mask(tile, r) | output_mask(tile, r)


static func rotation_cost(tile: Dictionary, from: int, to: int) -> int:
	var p: int = PERIOD[tile["t"]]
	var best := 4
	var k := 0
	while k < 4:
		var target := (to + k) & 3
		var cw := (((target - from) % 4) + 4) % 4
		var ccw := (4 - cw) % 4
		best = mini(best, mini(cw, ccw))
		k += p
	return best


## [taps, dir] — cheapest way to rotate from `from` to an orientation equivalent to `to`.
static func rotation_plan(tile: Dictionary, from: int, to: int) -> Array:
	var cost := rotation_cost(tile, from, to)
	var k := 0
	var p: int = PERIOD[tile["t"]]
	while k < 4:
		if (((to + k - from) % 4) + 4) % 4 == cost:
			return [cost, 1]
		k += p
	return [cost, -1]


## Normalize a tile parsed from JSON (Godot parses all JSON numbers as floats).
static func normalize_tile(raw: Dictionary) -> Dictionary:
	var tile := {"t": str(raw.get("t", "empty")), "r": int(raw.get("r", 0))}
	if raw.get("l", false):
		tile["l"] = true
	if raw.has("c"):
		tile["c"] = int(raw["c"])
	if raw.has("n"):
		tile["n"] = int(raw["n"])
	return tile


## Normalize a full level dictionary from JSON.
static func normalize_level(raw: Dictionary) -> Dictionary:
	var lvl := raw.duplicate(true)
	lvl["width"] = int(raw["width"])
	lvl["height"] = int(raw["height"])
	lvl["version"] = int(raw.get("version", 1))
	lvl["par"] = int(raw.get("par", 0))
	lvl["difficultyScore"] = int(raw.get("difficultyScore", 0))
	var tiles: Array = []
	for t in raw["tiles"]:
		tiles.append(normalize_tile(t))
	lvl["tiles"] = tiles
	if raw.has("solution") and raw["solution"] is Dictionary:
		var rots: Array = []
		for r in raw["solution"].get("rotations", []):
			rots.append(int(r))
		var moves: Array = []
		for m in raw["solution"].get("moves", []):
			moves.append([int(m[0]), int(m[1])])
		lvl["solution"] = {"rotations": rots, "moves": moves}
	if raw.get("generator") is Dictionary:
		var g: Dictionary = raw["generator"]
		lvl["generator"] = {"version": str(g["version"]), "seed": int(g["seed"]), "tier": str(g["tier"])}
	return lvl


## Structural validation for untrusted boards (saves, network). Returns "" when valid.
static func validate_board(board: Dictionary) -> String:
	var w := int(board.get("width", 0))
	var h := int(board.get("height", 0))
	if w < 2 or h < 2 or w > 12 or h > 12:
		return "bad dimensions"
	var tiles: Array = board.get("tiles", [])
	if tiles.size() != w * h:
		return "tile count mismatch"
	var sources := 0
	var dests := 0
	var src_colors := {}
	var dest_colors := {}
	for tile in tiles:
		if not (tile is Dictionary) or not TYPES.has(tile.get("t", "")):
			return "unknown tile"
		var r := int(tile.get("r", -1))
		if r < 0 or r > 3:
			return "bad rotation"
		if tile["t"] == "source" or tile["t"] == "dest":
			var c := int(tile.get("c", 0))
			if c < 0 or c >= COLOR_COUNT:
				return "bad color"
			if tile["t"] == "source":
				sources += 1
				src_colors[c] = true
			else:
				dests += 1
				dest_colors[c] = true
	if sources == 0 or dests == 0:
		return "missing source or destination"
	for c in src_colors:
		if not dest_colors.has(c):
			return "no destination for color"
	return ""


static func start_rotations(board: Dictionary) -> Array:
	var out: Array = []
	for t in board["tiles"]:
		out.append(int(t["r"]))
	return out


## Apply moves; returns the rotations array or null for an illegal move.
static func apply_moves(board: Dictionary, moves: Array, from: Array) -> Variant:
	var rot := from.duplicate()
	var tiles: Array = board["tiles"]
	for mv in moves:
		var i := int(mv[0])
		var d := int(mv[1])
		if i < 0 or i >= tiles.size() or (d != 1 and d != -1) or not is_rotatable(tiles[i]):
			return null
		rot[i] = (int(rot[i]) + d + 4) & 3
	return rot
