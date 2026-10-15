class_name LFWorlds
## Campaign worlds: a name, a mechanic focus and a board palette each. Palettes only tint the
## board plate, belts and backdrop — package and dock colours never change, so every theme stays
## equally readable (all belt/plate pairs keep the same luminance contrast as the classic theme).

const WORLDS := [
	{
		"id": "workshop", "name": "Little Workshop", "focus": "Turning belts, corners and pins",
		"first": "c01", "bg": Color("#F7F5F0"), "plate": Color("#EDE6DA"), "belt": Color("#C9CEE8"),
		"rail": Color("#AEB5DA"), "motif": "bolts",
	},
	{
		"id": "candy", "name": "Candy Factory", "focus": "Longer routes and planning",
		"first": "c10", "bg": Color("#FBF3F3"), "plate": Color("#F3E2E6"), "belt": Color("#E5C9D6"),
		"rail": Color("#CFA9BC"), "motif": "sprinkles",
	},
	{
		"id": "parcel", "name": "Parcel Station", "focus": "Two routes at once",
		"first": "c20", "bg": Color("#F2F6F6"), "plate": Color("#E1EBEC"), "belt": Color("#BFD5DB"),
		"rail": Color("#9DBAC2"), "motif": "stripes",
	},
	{
		"id": "neon", "name": "Neon Circuit", "focus": "Busy junctions and right of way",
		"first": "x26", "bg": Color("#F3F2FA"), "plate": Color("#E4E1F4"), "belt": Color("#C8C2EE"),
		"rail": Color("#A79FDF"), "motif": "traces",
	},
	{
		"id": "space", "name": "Space Logistics", "focus": "Three colours, full factory",
		"first": "x31", "bg": Color("#F1F3F8"), "plate": Color("#E0E5EF"), "belt": Color("#BCC6DC"),
		"rail": Color("#98A6C6"), "motif": "stars",
	},
]


## World index for a campaign position, given the ordered campaign list.
static func index_for(campaign: Array, campaign_index: int) -> int:
	var w := 0
	for i in mini(campaign_index + 1, campaign.size()):
		for k in WORLDS.size():
			if campaign[i]["id"] == WORLDS[k]["first"]:
				w = k
	return w


## [start, end) campaign indices for world `w`.
static func range_for(campaign: Array, w: int) -> Vector2i:
	var start := -1
	var end := campaign.size()
	for i in campaign.size():
		var id: String = campaign[i]["id"]
		if id == WORLDS[w]["first"]:
			start = i
		elif w + 1 < WORLDS.size() and id == WORLDS[w + 1]["first"]:
			end = i
	return Vector2i(maxi(start, 0), end)


static func palette(w: int) -> Dictionary:
	return WORLDS[clampi(w, 0, WORLDS.size() - 1)]


## Palette for non-campaign modes (endless / daily / challenges) chosen from the level id so a
## given puzzle always looks the same for everyone.
static func palette_for_level(level: Dictionary) -> Dictionary:
	var h := LFRng.fnv1a32(str(level.get("id", "")))
	return WORLDS[h % WORLDS.size()]
