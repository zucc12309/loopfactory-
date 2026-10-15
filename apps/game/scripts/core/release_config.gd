class_name LFReleaseConfig
extends RefCounted
## Client configuration (res://config/client.json) loading and validation (audit R1).
## The same rules are enforced at build time by scripts/client-config.ts (the build fails) and at
## runtime here (a staging build shows a visible warning; tests cover both with shared cases in
## config/validation-cases.json).
##
## Release environments (staging, production) must have:
##  * an https:// apiBaseUrl that is not loopback/private/".example"/placeholder,
##  * real https:// privacyPolicyUrl and supportUrl,
##  * a positive build number, no test-only switches, and no secret-looking fields.
## Development may use http://127.0.0.1 / localhost.

const ENVIRONMENTS := ["development", "staging", "production"]
const REQUIRED_URLS := ["apiBaseUrl", "privacyPolicyUrl", "supportUrl"]
const TEST_ONLY_KEYS := ["devAuth", "devPurchases", "testMode", "fakeServer"]
const SECRET_HINTS := ["secret", "password", "privatekey", "private_key", "serviceaccount", "jwt"]


static func load_client(path := "res://config/client.json") -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Returns a list of human-readable problems ([] = valid for its environment).
static func validate(cfg: Dictionary) -> Array:
	var errs: Array = []
	var env := str(cfg.get("environment", ""))
	if not ENVIRONMENTS.has(env):
		errs.append("environment must be one of %s (got '%s')" % [ENVIRONMENTS, env])
		return errs
	var release := env != "development"
	for key in REQUIRED_URLS:
		var u := str(cfg.get(key, ""))
		if u == "":
			if release:
				errs.append("%s is required for %s builds" % [key, env])
			continue
		var why := url_problem(u, release)
		if why != "":
			errs.append("%s: %s (%s)" % [key, why, u])
	var links: Dictionary = cfg.get("appLinks", {})
	var host := str(links.get("host", ""))
	if host != "":
		var hp := url_problem("https://" + host, release)
		if hp != "":
			errs.append("appLinks.host: %s" % hp)
	if release:
		if int(cfg.get("build", 0)) <= 0:
			errs.append("build must be a positive integer for %s builds" % env)
		for k in TEST_ONLY_KEYS:
			if bool(cfg.get(k, false)):
				errs.append("test-only switch '%s' is on" % k)
	_scan_secrets(cfg, "", errs)
	return errs


## Why a URL is unacceptable, or "".
static func url_problem(u: String, release: bool) -> String:
	var lower := u.strip_edges().to_lower()
	var scheme_end := lower.find("://")
	if scheme_end < 0:
		return "not an absolute URL"
	var scheme := lower.substr(0, scheme_end)
	var rest := lower.substr(scheme_end + 3)
	var host := rest.split("/")[0].split("?")[0]
	if host.contains("@"):
		return "credentials in URL"
	host = host.split(":")[0] if not host.begins_with("[") else host
	if host == "":
		return "missing host"
	var loopback := host == "localhost" or host.begins_with("127.") or host == "[::1]" or host == "0.0.0.0" or host.ends_with(".localhost")
	var private := host.begins_with("10.") or host.begins_with("192.168.") or _is_172_private(host) or host.ends_with(".local") or host.ends_with(".internal")
	if not release:
		return "" if scheme == "http" or scheme == "https" else "unsupported scheme"
	if scheme != "https":
		return "must use https"
	if loopback:
		return "loopback host"
	if private:
		return "private/development host"
	if host.ends_with(".example") or host.contains(".example.") or host == "example.com" or host.ends_with(".example.com") or host.ends_with(".test") or host.ends_with(".invalid"):
		return "placeholder domain"
	if lower.contains("your-domain") or lower.contains("change-me") or lower.contains("placeholder"):
		return "placeholder value"
	if not host.contains("."):
		return "not a public host name"
	return ""


static func _is_172_private(host: String) -> bool:
	if not host.begins_with("172."):
		return false
	var parts := host.split(".")
	return parts.size() > 1 and parts[1].is_valid_int() and int(parts[1]) >= 16 and int(parts[1]) <= 31


static func _scan_secrets(v: Variant, path: String, errs: Array) -> void:
	if v is Dictionary:
		for k in v:
			var key := str(k).to_lower().replace("-", "").replace("_", "")
			for h in SECRET_HINTS:
				if key.contains(h.replace("_", "")) and str(v[k]) != "":
					errs.append("secret-looking field '%s%s' must not ship in the client" % [path, k])
			_scan_secrets(v[k], path + str(k) + ".", errs)
