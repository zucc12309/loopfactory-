class_name LFFlags
## Feature flags and A/B experiments with deterministic, privacy-safe bucketing.
##
## * Every experiment has a control (first variant) that ships as the default experience.
## * An experiment only runs when remote config lists it under `experiments.<key>` with
##   `"enabled": true` — so a build with no server, or an offline first launch, always gets control.
## * Bucketing hashes the random analytics id with the experiment key (FNV-1a), so a player keeps the
##   same variant across sessions and different experiments are independent. No device id is used.
## * `"force": "<variant>"` rolls a variant out to everyone (or rolls back to control).
## Remote config example (docs/experiments.md):
##   {"experiments": {"celebration_ms": {"enabled": true, "weights": [50, 50]}}}

const EXPERIMENTS := {
	# Interactive coach for levels 1–5 vs. text tips only.
	"tutorial_flow": ["coach", "tips_only"],
	# Win celebration length before the result card (milliseconds).
	"celebration_ms": [1200, 800],
	# Where "Challenge a friend" sits on the win card.
	"challenge_button": ["secondary_row", "beside_next"],
	# Daily challenge entry on Home: a card in the row, or a banner above Continue.
	"daily_entry": ["card", "banner"],
	# Endless difficulty ramp: standard thresholds or 1.5× more puzzles per tier.
	"difficulty_ramp": ["standard", "gentle"],
}


static func bucket(analytics_id: String, key: String) -> int:
	return LFRng.fnv1a32(analytics_id + ":" + key) % 100


## Pure resolution so it can be unit-tested: `data` is the save dictionary.
static func resolve(data: Dictionary, key: String) -> Variant:
	var variants: Array = EXPERIMENTS.get(key, [null])
	var exps = data.get("remoteConfig", {}).get("experiments", {})
	var cfg = exps.get(key) if exps is Dictionary else null
	if not (cfg is Dictionary):
		return variants[0]
	if cfg.has("force"):
		for v in variants:
			if str(v) == str(cfg["force"]):
				return v
		return variants[0]
	if not bool(cfg.get("enabled", false)):
		return variants[0]
	var weights: Array = cfg.get("weights", [])
	if weights.size() != variants.size():
		weights = []
		for v in variants:
			weights.append(100.0 / variants.size())
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return variants[0]
	var b := float(bucket(str(data.get("analyticsId", "")), key)) / 100.0 * total
	var acc := 0.0
	for i in variants.size():
		acc += maxf(0.0, float(weights[i]))
		if b < acc:
			return variants[i]
	return variants[-1]


static func get_variant(key: String) -> Variant:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game") if tree else null
	if game == null or game.get("state") == null:
		return EXPERIMENTS.get(key, [null])[0]
	return resolve(game.state.data, key)


## {key: variant} for every experiment that is actually running — attached to analytics events so
## results can be split by variant.
static func active_assignments(data: Dictionary) -> Dictionary:
	var out := {}
	var exps = data.get("remoteConfig", {}).get("experiments", {})
	if not (exps is Dictionary):
		return out
	for key in EXPERIMENTS:
		var cfg = exps.get(key)
		if cfg is Dictionary and (bool(cfg.get("enabled", false)) or cfg.has("force")):
			out[key] = str(resolve(data, key))
	return out
