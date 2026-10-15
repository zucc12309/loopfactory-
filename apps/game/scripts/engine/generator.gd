class_name LFGenerator
extends RefCounted
## Procedural puzzle generator. Mirror of packages/engine/src/generator.ts — identical output for the
## same (seed, tier, GENERATOR_VERSION). Every random call happens in the same order as the TS version.

const GENERATOR_VERSION := "gen-1"
const MAX_ATTEMPTS := 60
const DIFFICULTIES := ["beginner", "easy", "medium", "hard", "expert"]

const TIERS := {
	"beginner": {"width": 4, "height": 4, "paths": 1, "packagesMin": 1, "packagesMax": 1, "pathMin": 3, "pathMax": 5, "decoyPct": 35, "blockedPct": 10, "teePct": 0, "allowCross": false, "lockedPct": 0, "minRotations": 2, "maxRotations": 5, "solverBudget": 20000},
	"easy": {"width": 5, "height": 5, "paths": 1, "packagesMin": 1, "packagesMax": 2, "pathMin": 5, "pathMax": 9, "decoyPct": 55, "blockedPct": 10, "teePct": 0, "allowCross": false, "lockedPct": 10, "minRotations": 4, "maxRotations": 9, "solverBudget": 40000},
	"medium": {"width": 5, "height": 6, "paths": 2, "packagesMin": 1, "packagesMax": 2, "pathMin": 3, "pathMax": 7, "decoyPct": 60, "blockedPct": 8, "teePct": 15, "allowCross": false, "lockedPct": 10, "minRotations": 6, "maxRotations": 14, "solverBudget": 60000},
	"hard": {"width": 6, "height": 6, "paths": 2, "packagesMin": 2, "packagesMax": 2, "pathMin": 5, "pathMax": 9, "decoyPct": 65, "blockedPct": 8, "teePct": 20, "allowCross": true, "lockedPct": 15, "minRotations": 8, "maxRotations": 18, "solverBudget": 80000},
	"expert": {"width": 6, "height": 7, "paths": 3, "packagesMin": 1, "packagesMax": 3, "pathMin": 4, "pathMax": 9, "decoyPct": 70, "blockedPct": 6, "teePct": 25, "allowCross": true, "lockedPct": 15, "minRotations": 10, "maxRotations": 24, "solverBudget": 120000},
}

var rng: LFRng
var cfg: Dictionary
var w: int
var h: int
var grid: Array

# route-building state
var _owner: int
var _path: Array
var _in_path: Dictionary
var _budget: int
var _target: int
var _dest_cell: int


static func corner_rotation(a: int, b: int) -> int:
	var mask := LFTiles.bit(a) | LFTiles.bit(b)
	for r in 4:
		if LFTiles.rotate_mask(3, r) == mask:
			return r
	return 0


static func difficulty_score(tiles: Array, par: int, paths: int) -> int:
	var rotatable := 0
	var crosses := 0
	var tees := 0
	var packages := 0
	for t in tiles:
		if LFTiles.is_rotatable(t):
			rotatable += 1
		if t["t"] == "cross":
			crosses += 1
		if t["t"] == "tee":
			tees += 1
		if t["t"] == "source":
			packages += int(t.get("n", 1))
	return par * 10 + rotatable * 3 + paths * 15 + packages * 4 + crosses * 5 + tees * 4


## Generate a verified level or null. Deterministic per (seed, tier).
static func generate_level(seed: int, tier: String, id := "", name := "") -> Variant:
	var g := LFGenerator.new()
	return g._generate(seed & 0xFFFFFFFF, tier, id, name)


static func generate_level_from(seed: int, tier: String, id := "", name := "", max_seeds := 50) -> Variant:
	for k in max_seeds:
		var lvl = generate_level((seed + k) & 0xFFFFFFFF, tier, id, name)
		if lvl != null:
			return lvl
	return null


func _generate(seed: int, tier: String, id: String, name: String) -> Variant:
	cfg = TIERS[tier]
	w = cfg["width"]
	h = cfg["height"]
	rng = LFRng.new(seed)
	for attempt in MAX_ATTEMPTS:
		var built = _try_generate()
		if built == null:
			continue
		var tiles: Array = built["tiles"]
		var board := {"width": w, "height": h, "tiles": tiles}
		var start := LFTiles.start_rotations(board)
		if not LFSimulation.is_solved(board, built["solved"]):
			continue
		if LFSimulation.is_solved(board, start):
			continue
		var res := LFSolver.solve(board, start, cfg["solverBudget"], 20)
		if res["status"] != "solved":
			continue
		if res["minCost"] < cfg["minRotations"] or res["minCost"] > cfg["maxRotations"]:
			continue
		var level_name := name if name != "" else "%s #%d" % [tier.capitalize(), seed]
		return {
			"id": id if id != "" else "%s-%d" % [tier, seed],
			"name": level_name,
			"version": 1,
			"difficulty": tier,
			"difficultyScore": difficulty_score(tiles, res["minCost"], cfg["paths"]),
			"width": w,
			"height": h,
			"tiles": tiles,
			"generator": {"version": GENERATOR_VERSION, "seed": seed, "tier": tier},
			"par": res["minCost"],
			"solution": {"rotations": res["rotations"], "moves": res["moves"]},
			"solutionCount": res["solutionCount"],
			"solutionCountCapped": res["solutionCountCapped"],
		}
	return null


func _cell(t: String, r: int, l: bool, c: int, n: int, owner: int) -> Dictionary:
	return {"t": t, "r": r, "l": l, "c": c, "n": n, "owner": owner}


func _free(i: int) -> bool:
	return grid[i]["t"] == "empty" and grid[i]["owner"] < 0


func _step_to(cell: int, d: int) -> int:
	var x: int = (cell % w) + LFTiles.DX[d]
	var y: int = (cell / w) + LFTiles.DY[d]
	if x < 0 or y < 0 or x >= w or y >= h:
		return -1
	return y * w + x


func _crossable(cell: int, d: int) -> bool:
	if not cfg["allowCross"]:
		return false
	var c: Dictionary = grid[cell]
	if c["owner"] < 0 or c["owner"] == _owner or c["t"] != "straight" or c["l"]:
		return false
	var vertical: bool = c["r"] % 2 == 0
	return d % 2 == 1 if vertical else d % 2 == 0


func _dfs(cell: int, dir: int) -> bool:
	_budget -= 1
	if _budget <= 0:
		return false
	if _path.size() >= _target:
		for d in rng.shuffle([0, 1, 2, 3]):
			if d == LFTiles.opposite(dir):
				continue
			var n := _step_to(cell, d)
			if n >= 0 and _free(n) and not _in_path.has(n):
				_path[_path.size() - 1]["outDir"] = d
				_dest_cell = n
				return true
		return false
	var last: Dictionary = _path[_path.size() - 1]
	var forced_straight: bool = grid[cell]["owner"] >= 0 and grid[cell]["owner"] != _owner
	var options: Array
	if forced_straight:
		options = [dir]
	else:
		options = rng.shuffle([0, 1, 2, 3]).filter(func(d): return d != LFTiles.opposite(dir))
	for d in options:
		var n := _step_to(cell, d)
		if n < 0 or _in_path.has(n):
			continue
		if not _free(n) and not _crossable(n, d):
			continue
		last["outDir"] = d
		_path.append({"cell": n, "inDir": d, "outDir": d})
		_in_path[n] = true
		if _dfs(n, d):
			return true
		_path.pop_back()
		_in_path.erase(n)
		if _budget <= 0:
			return false
	return false


func _build_route(owner: int) -> Variant:
	_owner = owner
	var free_cells: Array = []
	for i in grid.size():
		if _free(i):
			free_cells.append(i)
	if free_cells.size() < cfg["pathMin"] + 2:
		return null
	var source: int = rng.pick(free_cells)
	_target = rng.range_i(cfg["pathMin"], cfg["pathMax"])
	var sx := source % w
	var sy := source / w
	var dirs := rng.shuffle([0, 1, 2, 3])
	_budget = 3000
	_path = []
	_in_path = {source: true}
	_dest_cell = -1
	for d in dirs:
		var nx: int = sx + LFTiles.DX[d]
		var ny: int = sy + LFTiles.DY[d]
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			continue
		var first := ny * w + nx
		if not _free(first):
			continue
		_path = [{"cell": first, "inDir": d, "outDir": d}]
		_in_path = {source: true, first: true}
		if _dfs(first, d):
			return {"source": source, "srcDir": d, "steps": _path.duplicate(), "dest": _dest_cell}
		if _budget <= 0:
			break
	return null


func _try_generate() -> Variant:
	grid = []
	for i in w * h:
		grid.append(_cell("empty", 0, false, 0, 1, -1))
	for k in cfg["paths"]:
		var route = _build_route(k)
		if route == null:
			return null
		var n := rng.range_i(cfg["packagesMin"], cfg["packagesMax"])
		grid[route["source"]] = _cell("source", route["srcDir"], true, k, n, k)
		grid[route["dest"]] = _cell("dest", 0, true, k, 1, k)
		for step in route["steps"]:
			var cell: int = step["cell"]
			var existing: Dictionary = grid[cell]
			if existing["owner"] >= 0 and existing["owner"] != k:
				grid[cell] = _cell("cross", 0, false, 0, 1, k)
				continue
			var in_dir: int = step["inDir"]
			var out_dir: int = step["outDir"]
			if in_dir == out_dir:
				grid[cell] = _cell("straight", 0 if in_dir % 2 == 0 else 1, false, 0, 1, k)
			else:
				grid[cell] = _cell("corner", corner_rotation(LFTiles.opposite(in_dir), out_dir), false, 0, 1, k)
			if cfg["teePct"] > 0 and rng.chance(cfg["teePct"]):
				var tee := {"t": "tee", "r": 0}
				var opts: Array = []
				for r in 4:
					if not (LFTiles.rotate_mask(7, r) & LFTiles.bit(LFTiles.opposite(in_dir))):
						continue
					if LFSimulation.exit_direction(tee, r, in_dir) == out_dir:
						opts.append(r)
				if opts.size() > 0:
					grid[cell] = _cell("tee", rng.pick(opts), false, 0, 1, k)

	var decoy_types: Array = ["straight", "corner", "corner", "tee"] if cfg["teePct"] > 0 else ["straight", "corner", "corner"]
	for i in grid.size():
		if grid[i]["owner"] >= 0:
			continue
		if rng.chance(cfg["blockedPct"]):
			grid[i] = _cell("blocked", 0, false, 0, 1, -1)
		elif rng.chance(cfg["decoyPct"]):
			var t: String = rng.pick(decoy_types)
			grid[i] = _cell(t, rng.int_n(4), false, 0, 1, -1)

	if cfg["lockedPct"] > 0:
		for i in grid.size():
			var c: Dictionary = grid[i]
			if c["owner"] >= 0 and (c["t"] == "straight" or c["t"] == "corner" or c["t"] == "tee") and rng.chance(cfg["lockedPct"]):
				c["l"] = true

	var solved: Array = []
	var tiles: Array = []
	for c in grid:
		solved.append(c["r"])
		var t := {"t": c["t"], "r": c["r"]}
		if c["l"] and (c["t"] == "straight" or c["t"] == "corner" or c["t"] == "tee"):
			t["l"] = true
		if c["t"] == "source" or c["t"] == "dest":
			t["c"] = c["c"]
		if c["t"] == "source" and c["n"] != 1:
			t["n"] = c["n"]
		tiles.append(t)
	for t in tiles:
		if LFTiles.is_rotatable(t):
			t["r"] = rng.int_n(4)
	return {"tiles": tiles, "solved": solved}
