class_name LFSolver
extends RefCounted
## Bounded path-constrained backtracking solver. Mirror of packages/engine/src/solver.ts.

var board: Dictionary
var tiles: Array
var start: Array
var rot: Array
var assigned: Array
var sources: Array = []
var nodes := 0
var max_nodes := 200000
var exceeded := false
var best_cost := 1 << 40
var best: Variant = null
var best_order: Array = []
var order: Array = []
var count_mode := false
var count_cap := 0
var count := 0
var seen_solutions := {}


func _init(b: Dictionary, start_rot: Array, p_max_nodes: int, p_count_mode: bool, p_count_cap: int) -> void:
	board = b
	tiles = b["tiles"]
	start = start_rot
	rot = start_rot.duplicate()
	assigned = []
	assigned.resize(tiles.size())
	assigned.fill(false)
	for i in tiles.size():
		if tiles[i]["t"] == "source":
			sources.append(i)
	max_nodes = p_max_nodes
	count_mode = p_count_mode
	count_cap = p_count_cap


## Returns {status, minCost, rotations, moves, routeOrder, nodes, solutionCount, solutionCountCapped}.
static func solve(b: Dictionary, start_rot: Array, max_nodes := 200000, count_cap := 0) -> Dictionary:
	var s := LFSolver.new(b, start_rot, max_nodes, false, 0)
	s._solve_source(0)
	var solution_count := 0
	var capped := false
	var total_nodes := s.nodes
	if s.best != null and count_cap > 0:
		var c := LFSolver.new(b, start_rot, max_nodes, true, count_cap)
		c._solve_source(0)
		solution_count = c.count
		capped = c.count >= c.count_cap or c.exceeded
		total_nodes += c.nodes
	if s.best != null:
		return {
			"status": "solved", "minCost": s.best_cost, "rotations": s.best,
			"moves": moves_between(b, start_rot, s.best), "routeOrder": s.best_order,
			"nodes": total_nodes, "solutionCount": solution_count, "solutionCountCapped": capped,
		}
	return {
		"status": "budget_exceeded" if s.exceeded else "unsolvable", "minCost": -1, "rotations": null,
		"moves": [], "routeOrder": [], "nodes": total_nodes, "solutionCount": 0, "solutionCountCapped": false,
	}


static func moves_between(b: Dictionary, from: Array, to: Array) -> Array:
	var moves: Array = []
	var ts: Array = b["tiles"]
	for i in ts.size():
		if not LFTiles.is_rotatable(ts[i]):
			continue
		var plan := LFTiles.rotation_plan(ts[i], int(from[i]), int(to[i]))
		for n in plan[0]:
			moves.append([i, plan[1]])
	return moves


## Hint: {tile, dir, taps, targetRotation} or null.
static func hint(b: Dictionary, current: Array, max_nodes := 100000) -> Variant:
	var res := solve(b, current, max_nodes)
	if res["status"] != "solved" or res["minCost"] == 0:
		return null
	var target: Array = res["rotations"]
	var ord: Array = res["routeOrder"].duplicate()
	for i in b["tiles"].size():
		ord.append(i)
	for i in ord:
		var tile: Dictionary = b["tiles"][i]
		if not LFTiles.is_rotatable(tile):
			continue
		var plan := LFTiles.rotation_plan(tile, int(current[i]), int(target[i]))
		if plan[0] == 0:
			continue
		return {"tile": i, "dir": plan[1], "taps": plan[0], "targetRotation": target[i]}
	return null


func _orientations_for(tile: Dictionary, st: int) -> Array:
	var p: int = LFTiles.PERIOD[tile["t"]]
	var opts: Array = []
	for k in p:
		var r := (st + k) & 3
		opts.append([LFTiles.rotation_cost(tile, st, r), r])
	opts.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return opts.map(func(o): return o[1])


func _cost_of() -> int:
	var c := 0
	for i in rot.size():
		if assigned[i]:
			c += LFTiles.rotation_cost(tiles[i], start[i], rot[i])
	return c


func _on_candidate() -> void:
	var sim := LFSimulation.simulate(board, rot, false)
	if not sim["success"]:
		return
	if count_mode:
		var parts: PackedStringArray = []
		for i in rot.size():
			parts.append(str(int(rot[i]) % int(LFTiles.PERIOD[tiles[i]["t"]])))
		var key := "".join(parts)
		if not seen_solutions.has(key):
			seen_solutions[key] = true
			count += 1
		return
	var cost := _cost_of()
	if cost < best_cost:
		best_cost = cost
		best = rot.duplicate()
		best_order = order.duplicate()


func _done() -> bool:
	if exceeded:
		return true
	if count_mode:
		return count >= count_cap
	return best_cost == 0


func _solve_source(si: int) -> void:
	if _done():
		return
	if si >= sources.size():
		_on_candidate()
		return
	var src: int = sources[si]
	_trace(si, src, int(rot[src]) & 3, {})


func _trace(si: int, cell: int, dir: int, visited: Dictionary) -> void:
	if _done():
		return
	nodes += 1
	if nodes > max_nodes:
		exceeded = true
		return
	if not count_mode and _cost_of() >= best_cost:
		return
	var w: int = board["width"]
	var h: int = board["height"]
	var x: int = (cell % w) + LFTiles.DX[dir]
	var y: int = (cell / w) + LFTiles.DY[dir]
	if x < 0 or y < 0 or x >= w or y >= h:
		return
	var nxt := y * w + x
	var tile: Dictionary = tiles[nxt]
	var entry := LFTiles.opposite(dir)
	if LFTiles.is_rotatable(tile) and not assigned[nxt]:
		var st: int = start[nxt]
		assigned[nxt] = true
		for r in _orientations_for(tile, st):
			if not (LFTiles.input_mask(tile, r) & LFTiles.bit(entry)):
				continue
			rot[nxt] = r
			_follow(si, nxt, tile, dir, entry, visited)
			if _done():
				break
		rot[nxt] = st
		assigned[nxt] = false
	else:
		_follow(si, nxt, tile, dir, entry, visited)


func _follow(si: int, nxt: int, tile: Dictionary, dir: int, entry: int, visited: Dictionary) -> void:
	var r: int = rot[nxt]
	if not (LFTiles.input_mask(tile, r) & LFTiles.bit(entry)):
		return
	if tile["t"] == "dest":
		var src_tile: Dictionary = tiles[sources[si]]
		if int(tile.get("c", 0)) == int(src_tile.get("c", 0)):
			_solve_source(si + 1)
		return
	var ex := LFSimulation.exit_direction(tile, r, dir)
	if ex < 0:
		return
	var key := nxt * 4 + ex
	if visited.has(key):
		return
	visited[key] = true
	order.append(nxt)
	_trace(si, nxt, ex, visited)
	order.pop_back()
	visited.erase(key)
