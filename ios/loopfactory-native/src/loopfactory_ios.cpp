#include "loopfactory_ios.h"

#include "lf_bridge.h"

#include <string>

using namespace godot;

LoopFactoryIOS *LoopFactoryIOS::singleton = nullptr;

static std::string to_std(const String &p_s) {
	CharString cs = p_s.utf8();
	return std::string(cs.get_data(), cs.length());
}

static String from_std(const std::string &p_s) {
	return String::utf8(p_s.c_str(), (int64_t)p_s.size());
}

// Bridge callbacks arrive on the main thread, possibly while Godot is mid-frame: signals are
// emitted deferred so GDScript handlers run at a safe point.
static void on_link(const std::string &p_uri) {
	if (LoopFactoryIOS::get_singleton() != nullptr) {
		LoopFactoryIOS::get_singleton()->call_deferred("emit_signal", "launch_uri_received", from_std(p_uri));
	}
}

static void on_share(const std::string &p_result, const std::string &p_activity) {
	if (LoopFactoryIOS::get_singleton() != nullptr) {
		LoopFactoryIOS::get_singleton()->call_deferred("emit_signal", "share_finished", from_std(p_result), from_std(p_activity));
	}
}

LoopFactoryIOS *LoopFactoryIOS::get_singleton() {
	return singleton;
}

LoopFactoryIOS::LoopFactoryIOS() {
	singleton = this;
	lfnative::init(on_link, on_share);
}

LoopFactoryIOS::~LoopFactoryIOS() {
	lfnative::shutdown();
	if (singleton == this) {
		singleton = nullptr;
	}
}

void LoopFactoryIOS::_bind_methods() {
	ClassDB::bind_method(D_METHOD("apiVersion"), &LoopFactoryIOS::apiVersion);
	ClassDB::bind_method(D_METHOD("isNativeIOS"), &LoopFactoryIOS::isNativeIOS);
	ClassDB::bind_method(D_METHOD("share", "text", "abs_path", "mime", "title"), &LoopFactoryIOS::share);
	ClassDB::bind_method(D_METHOD("shareEx", "text", "abs_path", "mime", "title"), &LoopFactoryIOS::shareEx);
	ClassDB::bind_method(D_METHOD("consumeLaunchUri"), &LoopFactoryIOS::consumeLaunchUri);
	ClassDB::bind_method(D_METHOD("isKeychainAvailable"), &LoopFactoryIOS::isKeychainAvailable);
	ClassDB::bind_method(D_METHOD("keychainSet", "key", "value"), &LoopFactoryIOS::keychainSet);
	ClassDB::bind_method(D_METHOD("keychainGet", "key"), &LoopFactoryIOS::keychainGet);
	ClassDB::bind_method(D_METHOD("keychainDelete", "key"), &LoopFactoryIOS::keychainDelete);
	ClassDB::bind_method(D_METHOD("reduceMotion"), &LoopFactoryIOS::reduceMotion);
#ifdef LF_STUB_BRIDGE
	ClassDB::bind_method(D_METHOD("stubDeliverLink", "uri"), &LoopFactoryIOS::stubDeliverLink);
	ClassDB::bind_method(D_METHOD("stubFinishShare", "result", "activity"), &LoopFactoryIOS::stubFinishShare);
#endif
	ADD_SIGNAL(MethodInfo("launch_uri_received", PropertyInfo(Variant::STRING, "uri")));
	ADD_SIGNAL(MethodInfo("share_finished", PropertyInfo(Variant::STRING, "result"), PropertyInfo(Variant::STRING, "activity_type")));
}

int LoopFactoryIOS::apiVersion() const {
	return API_VERSION;
}

bool LoopFactoryIOS::isNativeIOS() const {
	return lfnative::is_native_ios();
}

bool LoopFactoryIOS::share(const String &p_text, const String &p_abs_path, const String &p_mime, const String &p_title) {
	return shareEx(p_text, p_abs_path, p_mime, p_title) == lfnative::SHARE_OPENED;
}

int LoopFactoryIOS::shareEx(const String &p_text, const String &p_abs_path, const String &p_mime, const String &p_title) {
	return lfnative::share(to_std(p_text), to_std(p_abs_path), to_std(p_mime), to_std(p_title));
}

String LoopFactoryIOS::consumeLaunchUri() {
	return from_std(lfnative::consume_launch_uri());
}

bool LoopFactoryIOS::isKeychainAvailable() {
	return lfnative::keychain_available();
}

bool LoopFactoryIOS::keychainSet(const String &p_key, const String &p_value) {
	return !p_key.is_empty() && lfnative::keychain_set(to_std(p_key), to_std(p_value));
}

String LoopFactoryIOS::keychainGet(const String &p_key) {
	std::string v;
	if (p_key.is_empty() || !lfnative::keychain_get(to_std(p_key), v)) {
		return String();
	}
	return from_std(v);
}

bool LoopFactoryIOS::keychainDelete(const String &p_key) {
	return !p_key.is_empty() && lfnative::keychain_delete(to_std(p_key));
}

int LoopFactoryIOS::reduceMotion() {
	return lfnative::reduce_motion();
}

#ifdef LF_STUB_BRIDGE
void LoopFactoryIOS::stubDeliverLink(const String &p_uri) {
	lfnative::stub_deliver_link(to_std(p_uri));
}

void LoopFactoryIOS::stubFinishShare(const String &p_result, const String &p_activity) {
	lfnative::stub_finish_share(to_std(p_result), to_std(p_activity));
}
#endif
