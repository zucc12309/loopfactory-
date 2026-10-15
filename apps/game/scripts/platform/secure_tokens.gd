class_name LFSecureTokens
extends RefCounted
## Keeps the refresh token out of the save file where the platform offers keychain-class storage
## (iOS Keychain through the LoopFactoryIOS extension). Everywhere else (Android, desktop, an iOS
## build without the extension) nothing changes: the token stays in user://save.json as before.
##
## In memory the token always lives at state.data.auth.refreshToken, so Net and the tests are
## unaware of where it is persisted.
##
## Rules:
##  * Write order: Keychain first, read back and compared, THEN the save file without the token
##    (auth.refreshTokenStore = "keychain"). If the Keychain write fails the token stays in the file
##    (an identity is never dropped to gain secrecy).
##  * Migration: a save that still holds a plaintext token (older build, or the fallback above) is
##    moved into the Keychain on the next save. Nothing is deleted before the copy is verified.
##  * Fresh install (no save file at all): any Keychain token left by an earlier install is deleted,
##    so reinstalling behaves like Android — a new guest. Progress is NOT restorable after reinstall
##    unless an account was linked (account linking is not shipped; docs/IOS_READINESS.md).

const KEY := "refresh_token"
const MARKER := "refreshTokenStore"

static var _written := ""
## Last problem seen ("", "write_failed", "token_missing", "secure_store_unavailable").
static var last_problem := ""


static func enabled() -> bool:
	return LFPlatform.supports_secure_storage()


## The dictionary to write to disk: `data` itself when secure storage is off or failed, otherwise a
## shallow copy whose auth has no refresh token.
static func for_disk(data: Dictionary) -> Dictionary:
	if not enabled() or not (data.get("auth") is Dictionary):
		return data
	var auth: Dictionary = data["auth"]
	var tok := str(auth.get("refreshToken", ""))
	if tok != _written:
		if tok == "":
			LFPlatform.secure_delete(KEY)
			_written = ""
		elif LFPlatform.secure_set(KEY, tok) and LFPlatform.secure_get(KEY) == tok:
			_written = tok
		else:
			last_problem = "write_failed"
			return data
	var out := data.duplicate()
	var a2: Dictionary = auth.duplicate()
	a2.erase("refreshToken")
	a2[MARKER] = "keychain"
	out["auth"] = a2
	return out


## Call right after the save file is loaded into `data`.
static func after_load(data: Dictionary, fresh_install: bool) -> void:
	var auth: Dictionary = data["auth"]
	var marker := str(auth.get(MARKER, ""))
	auth.erase(MARKER)
	_written = ""
	if not enabled():
		if marker == "keychain":
			# Saved by a build with the extension, loaded by one without: the token is unreachable.
			last_problem = "secure_store_unavailable"
		return
	if fresh_install:
		LFPlatform.secure_delete(KEY)
		return
	if marker == "keychain":
		var tok := LFPlatform.secure_get(KEY)
		if tok != "":
			auth["refreshToken"] = tok
			_written = tok
		else:
			last_problem = "token_missing"


## Explicit local deletion.
static func wipe() -> void:
	if enabled():
		LFPlatform.secure_delete(KEY)
	_written = ""
