class_name LFCrewMoments
## Shareable "moments" detected from a real simulation result — never invented. They pick the
## Captain Naps reaction and the share card's featured character.
##  * perfect             – solved in par rotations
##  * unusually_efficient – perfect on a big puzzle (par >= 8)
##  * all_together        – every package (2+) delivered on the same tick
##  * near_miss           – a package had to wait while another occupied the cell it faced

const PRIORITY := ["unusually_efficient", "all_together", "near_miss", "perfect"]
const EVENT := {
	"unusually_efficient": "UNUSUALLY_EFFICIENT", "all_together": "ALL_TOGETHER",
	"near_miss": "NEAR_MISS", "perfect": "PERFECT_SCORE",
}


static func detect(result: Dictionary, level: Dictionary, moves: int) -> Array:
	var out: Array = []
	if not bool(result.get("success", false)):
		return out
	var par := int(level.get("par", 0))
	if moves <= par:
		out.append("perfect")
		if par >= 8:
			out.append("unusually_efficient")
	var frames: Array = result.get("frames", [])
	var total := int(result.get("total", 0))
	if total >= 2:
		for f in frames:
			var n := 0
			for p in f["packages"]:
				if p["state"] == "delivered":
					n += 1
			if n == total:
				out.append("all_together")
				break
	var w := int(level.get("width", 1))
	var h := int(level.get("height", 1))
	for f in frames:
		var occupied := {}
		for p in f["packages"]:
			if p["state"] != "delivered" and p["state"] != "crashed":
				occupied[int(p["cell"])] = int(p["id"])
		var found := false
		for p in f["packages"]:
			if p["state"] != "waiting":
				continue
			var d := int(p["dir"])
			var x: int = int(p["cell"]) % w + LFTiles.DX[d]
			var y: int = int(p["cell"]) / w + LFTiles.DY[d]
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var other = occupied.get(y * w + x)
			if other != null and int(other) != int(p["id"]):
				found = true
				break
		if found:
			out.append("near_miss")
			break
	return out


## The highest-ranked moment, or "" if none.
static func headline(moments: Array) -> String:
	for m in PRIORITY:
		if m in moments:
			return m
	return ""
