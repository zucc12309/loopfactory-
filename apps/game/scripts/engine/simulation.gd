class_name LFSimulation
## Deterministic conveyor simulation. Line-for-line mirror of packages/engine/src/simulation.ts —
## see that file and docs/gameplay-rules.md for the rules. Parity is enforced by tests/test_parity.gd.


static func exit_direction(tile: Dictionary, r: int, dir: int) -> int:
	var out := LFTiles.output_mask(tile, r) & ~LFTiles.bit(LFTiles.opposite(dir))
	if out & LFTiles.bit(dir):
		return dir
	var right := LFTiles.turn_right(dir)
	if out & LFTiles.bit(right):
		return right
	var left := LFTiles.turn_left(dir)
	if out & LFTiles.bit(left):
		return left
	return -1


static func total_packages(board: Dictionary) -> int:
	var total := 0
	for t in board["tiles"]:
		if t["t"] == "source":
			total += int(t.get("n", 1))
	return total


static func is_solved(board: Dictionary, rotations: Array) -> bool:
	return simulate(board, rotations, false)["success"]


## Returns {success, reason, ticks, delivered, total, failurePackage, failureCell, frames}.
## Each frame: {tick, delivered, packages: [{id, color, cell, dir, state, toX?, toY?}]}.
static func simulate(board: Dictionary, rotations: Array, record_frames := true, max_ticks := -1) -> Dictionary:
	var sim := _Sim.new(board, rotations, record_frames, max_ticks)
	return sim.run()


class _Sim:
	var width: int
	var height: int
	var tiles: Array
	var rot: Array
	var record: bool
	var total: int
	var max_ticks: int
	var remaining: Array = []
	var packages: Array = []  # [{id, color, cell, dir, source}] kept in id order
	var next_id := 0
	var delivered := 0
	var frames: Array = []
	var seen := {}

	func _init(board: Dictionary, rotations: Array, record_frames: bool, mt: int) -> void:
		width = board["width"]
		height = board["height"]
		tiles = board["tiles"]
		rot = rotations
		record = record_frames
		total = LFSimulation.total_packages(board)
		max_ticks = mt if mt > 0 else 4 * width * height * maxi(1, total) + 50
		for t in tiles:
			remaining.append(int(t.get("n", 1)) if t["t"] == "source" else 0)

	func occupied(cell: int) -> bool:
		for p in packages:
			if p["cell"] == cell:
				return true
		return false

	func spawn(states: Dictionary) -> bool:
		var spawned := false
		for i in tiles.size():
			var t: Dictionary = tiles[i]
			if t["t"] != "source" or remaining[i] <= 0 or occupied(i):
				continue
			var pkg := {"id": next_id, "color": int(t.get("c", 0)), "cell": i, "dir": int(rot[i]) & 3, "source": i}
			next_id += 1
			packages.append(pkg)
			remaining[i] -= 1
			states[pkg["id"]] = "spawned"
			spawned = true
		return spawned

	func snapshot(tick: int, states: Dictionary, extra: Array = []) -> void:
		if not record:
			return
		var list: Array = []
		for p in packages:
			list.append({"id": p["id"], "color": p["color"], "cell": p["cell"], "dir": p["dir"], "state": states.get(p["id"], "moved")})
		list.append_array(extra)
		list.sort_custom(func(a, b): return a["id"] < b["id"])
		frames.append({"tick": tick, "packages": list, "delivered": delivered})

	func finish(success: bool, reason: Variant, tick: int, pkg: Variant = null, cell: Variant = null) -> Dictionary:
		return {
			"success": success, "reason": reason, "ticks": tick, "delivered": delivered, "total": total,
			"failurePackage": pkg, "failureCell": cell, "frames": frames,
		}

	func crash(tick: int, pkg: Dictionary, reason: String, cell: Variant, nx: int, ny: int) -> Dictionary:
		var states := {}
		for p in packages:
			states[p["id"]] = "waiting"
		var kept: Array = []
		for p in packages:
			if p["id"] != pkg["id"]:
				kept.append(p)
		packages = kept
		snapshot(tick, states, [{"id": pkg["id"], "color": pkg["color"], "cell": pkg["cell"], "dir": pkg["dir"], "state": "crashed", "toX": nx, "toY": ny}])
		return finish(false, reason, tick, pkg["id"], cell)

	func run() -> Dictionary:
		var states0 := {}
		spawn(states0)
		snapshot(0, states0)
		for tick in range(1, max_ticks + 1):
			# 1. Intents
			var intents: Array = []
			for pkg in packages:
				var x: int = pkg["cell"] % width
				var y: int = pkg["cell"] / width
				var d: int = pkg["dir"]
				var nx: int = x + LFTiles.DX[d]
				var ny: int = y + LFTiles.DY[d]
				if nx < 0 or ny < 0 or nx >= width or ny >= height:
					return crash(tick, pkg, "off_board", null, nx, ny)
				var target := ny * width + nx
				var tile: Dictionary = tiles[target]
				var r: int = rot[target]
				if not (LFTiles.input_mask(tile, r) & LFTiles.bit(LFTiles.opposite(d))):
					return crash(tick, pkg, "disconnected", target, nx, ny)
				if tile["t"] == "dest":
					if int(tile.get("c", 0)) != pkg["color"]:
						return crash(tick, pkg, "wrong_destination", target, nx, ny)
					intents.append({"pkg": pkg, "target": target, "newDir": d, "deliver": true})
					continue
				var ex := LFSimulation.exit_direction(tile, r, d)
				if ex < 0:
					return crash(tick, pkg, "disconnected", target, nx, ny)
				intents.append({"pkg": pkg, "target": target, "newDir": ex, "deliver": false})

			# 3. Conflict resolution (fixed point)
			var accepted := {}
			for it in intents:
				accepted[it["pkg"]["id"]] = it
			var by_cell := {}
			for p in packages:
				by_cell[p["cell"]] = p
			var changed := true
			while changed:
				changed = false
				var claims := {}
				for it in accepted.values():
					if it["deliver"]:
						continue
					var prev = claims.get(it["target"])
					if prev == null or it["pkg"]["id"] < prev:
						claims[it["target"]] = it["pkg"]["id"]
				for it in accepted.values().duplicate():
					if it["deliver"]:
						continue
					var pid: int = it["pkg"]["id"]
					if claims.get(it["target"]) != pid:
						accepted.erase(pid)
						changed = true
						continue
					var occupant = by_cell.get(it["target"])
					if occupant != null and occupant["id"] != pid:
						var occ_intent = accepted.get(occupant["id"])
						if occ_intent == null:
							accepted.erase(pid)
							changed = true
						elif not occ_intent["deliver"] and occ_intent["target"] == it["pkg"]["cell"]:
							accepted.erase(pid)
							accepted.erase(occupant["id"])
							changed = true

			# 4. Apply
			var states := {}
			var delivered_now: Array = []
			var survivors: Array = []
			for p in packages:
				var it = accepted.get(p["id"])
				if it == null:
					states[p["id"]] = "waiting"
					survivors.append(p)
				elif it["deliver"]:
					delivered += 1
					delivered_now.append({"id": p["id"], "color": p["color"], "cell": it["target"], "dir": p["dir"], "state": "delivered"})
				else:
					p["cell"] = it["target"]
					p["dir"] = it["newDir"]
					states[p["id"]] = "moved"
					survivors.append(p)
			packages = survivors
			var moved := accepted.size() > 0

			# 5. Spawn
			var spawned := spawn(states)
			snapshot(tick, states, delivered_now)

			# 6. Evaluate
			if delivered == total:
				return finish(true, null, tick)
			if not moved and not spawned:
				var stuck = packages[0] if packages.size() > 0 else null
				return finish(false, "deadlock", tick, stuck["id"] if stuck else null, stuck["cell"] if stuck else null)
			var parts: PackedStringArray = []
			for p in packages:
				parts.append("%d:%d:%d" % [p["id"], p["cell"], p["dir"]])
			var key := "|".join(parts) + "#" + ",".join(remaining.map(func(v): return str(v)))
			if seen.has(key):
				var looping = packages[0] if packages.size() > 0 else null
				return finish(false, "loop", tick, looping["id"] if looping else null, looping["cell"] if looping else null)
			seen[key] = true
		return finish(false, "timeout", max_ticks)
