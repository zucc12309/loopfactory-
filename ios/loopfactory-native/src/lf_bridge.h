// Loop Factory native bridge: the platform half of the LoopFactoryIOS GDExtension.
//
// lf_bridge_ios.mm implements it with UIKit / Security (the iOS build). lf_bridge_stub.cpp is a
// host-only stand-in (Linux/macOS desktop) used ONLY to compile and test the Godot binding layer:
// it never ships, reports isNativeIOS() == false, and keeps "keychain" values in memory.
//
// All functions are called on the main thread (Godot's main thread is the UIKit main thread on iOS).
#pragma once

#include <string>

namespace lfnative {

enum ShareResult {
	SHARE_OPENED = 0, // the share sheet was asked to present (nothing about recipients)
	SHARE_UNAVAILABLE = 1, // no native share sheet in this build
	SHARE_FAILED = 2, // no view controller, a sheet already open, copy failed...
	SHARE_INVALID_FILE = 3, // the file is missing, unreadable, a directory, or not a decodable image
};

typedef void (*LinkCallback)(const std::string &uri);
typedef void (*ShareCallback)(const std::string &result, const std::string &activity_type);

bool is_native_ios();
void init(LinkCallback on_link, ShareCallback on_share);
void shutdown();

int share(const std::string &text, const std::string &abs_path, const std::string &mime, const std::string &title);
// The most recent https link delivered to the app (Universal Link), returned once; "" when none.
std::string consume_launch_uri();

bool keychain_available();
bool keychain_set(const std::string &key, const std::string &value);
bool keychain_get(const std::string &key, std::string &r_value);
bool keychain_delete(const std::string &key);

// UIAccessibilityIsReduceMotionEnabled(): 1 / 0, or -1 when unknown.
int reduce_motion();

#ifdef LF_STUB_BRIDGE
// Host test hooks: simulate what UIKit does on a device.
void stub_deliver_link(const std::string &uri);
void stub_finish_share(const std::string &result, const std::string &activity_type);
#endif

} // namespace lfnative
