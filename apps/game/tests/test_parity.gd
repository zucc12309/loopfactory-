extends LFTestCase
## Cross-language parity: the GDScript engine must match the canonical TypeScript engine exactly.

var fx: Dictionary
var levels := {}


func _init() -> void:
	fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/parity.json"))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/curated.json"))
	for raw in data["levels"]:
		var lvl := LFTiles.normalize_level(raw)
		levels[lvl["id"]] = lvl


static func digest(res: Dictionary) -> String:
	var parts: PackedStringArray = []
	for f in res["frames"]:
		var ps: PackedStringArray = []
		for p in f["packages"]:
			var s := "%d@%d/%d/%s" % [p["id"], p["cell"], p["dir"], p["state"].substr(0, 1)]
			if p.has("toX"):
				s += ">%d,%d" % [p["toX"], p["toY"]]
			ps.append(s)
		parts.append("%d:%d:%s" % [f["tick"], f["delivered"], ",".join(ps)])
	return ";".join(parts)


func _ints(a: Array) -> Array:
	return a.map(func(v): return int(v))


func test_rng_streams() -> void:
	for case in fx["rng"]:
		var r := LFRng.new(int(case["seed"]))
		var vals: Array = []
		for i in 12:
			vals.append(r.next_u32())
		var ints: Array = []
		for i in 12:
			ints.append(r.int_n(7))
		eq(vals, case["values"], "rng values seed %d" % case["seed"])
		eq(ints, case["ints"], "rng ints seed %d" % case["seed"])


func test_fnv() -> void:
	for case in fx["fnv"]:
		eq(LFRng.fnv1a32(case["text"]), case["hash"], "fnv '%s'" % case["text"])


func test_simulation_parity() -> void:
	for case in fx["sims"]:
		var lvl: Dictionary = levels[case["level"]]
		var res := LFSimulation.simulate(lvl, _ints(case["rotations"]))
		var exp: Dictionary = case["result"]
		var label: String = case["level"]
		eq(res["success"], exp["success"], label + " success")
		eq(res["reason"], exp["reason"], label + " reason")
		eq(res["ticks"], exp["ticks"], label + " ticks")
		eq(res["delivered"], exp["delivered"], label + " delivered")
		eq(res["failurePackage"], exp["failurePackage"], label + " failurePackage")
		eq(res["failureCell"], exp["failureCell"], label + " failureCell")
		eq(digest(res), exp["digest"], label + " frames")


func test_solver_parity() -> void:
	for case in fx["solves"]:
		var lvl: Dictionary = levels[case["level"]]
		var res := LFSolver.solve(lvl, LFTiles.start_rotations(lvl), 200000, 20)
		var label: String = case["level"]
		eq(res["status"], case["status"], label + " status")
		eq(res["optimal"], case["optimal"], label + " optimal")
		eq(res["minCost"], case["minCost"], label + " minCost")
		eq(res["rotations"], case["rotations"], label + " rotations")
		eq(res["moves"], case["moves"], label + " moves")
		eq(res["routeOrder"], case["routeOrder"], label + " routeOrder")
		eq(res["nodes"], case["nodes"], label + " nodes")
		eq(res["solutionCount"], case["solutionCount"], label + " solutionCount")


func test_hint_parity() -> void:
	for case in fx["hints"]:
		var lvl: Dictionary = levels[case["level"]]
		eq(LFSolver.hint(lvl, _ints(case["rotations"])), case["hint"], case["level"] + " hint")


func test_generator_parity() -> void:
	for case in fx["generated"]:
		var lvl = LFGenerator.generate_level(int(case["seed"]), case["tier"])
		var label := "%s/%d" % [case["tier"], case["seed"]]
		if case["level"] == null:
			eq(lvl, null, label)
			continue
		check(lvl != null, label + " produced no level")
		if lvl == null:
			continue
		var exp: Dictionary = case["level"]
		for key in ["id", "name", "difficulty", "difficultyScore", "width", "height", "tiles", "generator", "par", "solution", "solutionCount", "solutionCountCapped"]:
			eq(lvl[key], exp[key], label + " " + key)


## Negative paths (audit G4): every failure reason, queueing, conflicting arrivals and timeouts.
func test_negative_simulation_parity() -> void:
	var reasons := {}
	for kind in fx["negative"]["sims"]:
		var cases: Array = fx["negative"]["sims"][kind]
		check(cases.size() > 0, "fixture present for " + kind)
		for i in cases.size():
			var case: Dictionary = cases[i]
			var b := LFTiles.normalize_level(case["board"])
			var res := LFSimulation.simulate(b, _ints(case["rotations"]), true, int(case.get("maxTicks", -1)))
			var exp: Dictionary = case["result"]
			var label := "%s[%d]" % [kind, i]
			eq(res["success"], exp["success"], label + " success")
			eq(res["reason"], exp["reason"], label + " reason")
			eq(res["ticks"], exp["ticks"], label + " ticks")
			eq(res["delivered"], exp["delivered"], label + " delivered")
			eq(res["failurePackage"], exp["failurePackage"], label + " failurePackage")
			eq(res["failureCell"], exp["failureCell"], label + " failureCell")
			eq(digest(res), exp["digest"], label + " frames")
			reasons[str(exp["reason"])] = true
	for r in ["wrong_destination", "deadlock", "loop", "timeout", "off_board", "disconnected"]:
		check(reasons.has(r), "covers failure reason " + r)


## Solver status semantics (feasible vs proven optimal, exhausted, unsolvable, already solved) and the
## matching hint outcome must agree across engines.
func test_solver_outcome_parity() -> void:
	var names := []
	for case in fx["outcomes"]:
		var b := LFTiles.normalize_level(case["board"])
		var res := LFSolver.solve(b, _ints(case["start"]), int(case["maxNodes"]))
		var exp: Dictionary = case["solve"]
		var label: String = case["name"]
		names.append(label)
		eq(res["status"], exp["status"], label + " status")
		eq(res["optimal"], exp["optimal"], label + " optimal")
		eq(res["minCost"], exp["minCost"], label + " minCost")
		eq(res["rotations"], exp["rotations"], label + " rotations")
		eq(res["nodes"], exp["nodes"], label + " nodes")
		eq(LFSolver.hint_outcome(b, _ints(case["start"]), int(case["maxNodes"])), case["hint"], label + " hint outcome")
	eq(names, ["feasible_unproven", "proven_optimal", "budget_exhausted", "unsolvable", "already_solved"], "outcome cases")


## Invalid move input is rejected identically (TS applyMoves throws <-> GD apply_moves returns null).
func test_invalid_move_parity() -> void:
	for case in fx["moves"]:
		var lvl: Dictionary = levels[case["level"]]
		var rot = LFTiles.apply_moves(lvl, case["moves"], LFTiles.start_rotations(lvl))
		eq(rot != null, case["legal"], str(case["name"]) + " legality")
		if rot != null:
			eq(LFSimulation.is_solved(lvl, rot), case["verdict"]["valid"], str(case["name"]) + " verdict")
