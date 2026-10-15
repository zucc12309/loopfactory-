// LoopFactoryIOS: Engine singleton exposed to GDScript (apps/game/scripts/platform/ios_adapter.gd).
// Pure godot-cpp C++; everything platform-specific is behind lf_bridge.h.
#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class LoopFactoryIOS : public Object {
	GDCLASS(LoopFactoryIOS, Object);

	static LoopFactoryIOS *singleton;

protected:
	static void _bind_methods();

public:
	// Bumped when the GDScript-facing contract changes (LFIOSAdapter.API_VERSION).
	static const int API_VERSION = 1;

	static LoopFactoryIOS *get_singleton();

	int apiVersion() const;
	bool isNativeIOS() const;

	// Same contract as the Android plugin: true when the share sheet was asked to open.
	bool share(const String &p_text, const String &p_abs_path, const String &p_mime, const String &p_title);
	// 0 opened, 1 unavailable, 2 failed, 3 invalid file (lf_bridge.h ShareResult).
	int shareEx(const String &p_text, const String &p_abs_path, const String &p_mime, const String &p_title);
	String consumeLaunchUri();

	bool isKeychainAvailable();
	bool keychainSet(const String &p_key, const String &p_value);
	String keychainGet(const String &p_key);
	bool keychainDelete(const String &p_key);

	int reduceMotion();

#ifdef LF_STUB_BRIDGE
	void stubDeliverLink(const String &p_uri);
	void stubFinishShare(const String &p_result, const String &p_activity);
#endif

	LoopFactoryIOS();
	~LoopFactoryIOS();
};

} // namespace godot
