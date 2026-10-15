// Host-only stand-in for lf_bridge_ios.mm (see lf_bridge.h). Compiled with LF_STUB_BRIDGE for the
// binding tests (scripts/ios/test-native-stub.sh); never part of an iOS build.
#include "lf_bridge.h"

#include <cstdio>
#include <map>

namespace lfnative {

namespace {
LinkCallback g_on_link = nullptr;
ShareCallback g_on_share = nullptr;
std::string g_pending_uri;
std::map<std::string, std::string> g_store;
bool g_sheet_open = false;
} // namespace

bool is_native_ios() {
	return false;
}

void init(LinkCallback on_link, ShareCallback on_share) {
	g_on_link = on_link;
	g_on_share = on_share;
}

void shutdown() {
	g_on_link = nullptr;
	g_on_share = nullptr;
}

int share(const std::string &text, const std::string &abs_path, const std::string &mime, const std::string &title) {
	(void)mime;
	(void)title;
	if (text.empty() && abs_path.empty()) {
		return SHARE_FAILED;
	}
	if (g_sheet_open) {
		return SHARE_FAILED;
	}
	if (!abs_path.empty()) {
		FILE *f = fopen(abs_path.c_str(), "rb");
		if (f == nullptr) {
			return SHARE_INVALID_FILE;
		}
		fclose(f);
	}
	g_sheet_open = true;
	return SHARE_OPENED;
}

std::string consume_launch_uri() {
	std::string out = g_pending_uri;
	g_pending_uri.clear();
	return out;
}

bool keychain_available() {
	return true;
}

bool keychain_set(const std::string &key, const std::string &value) {
	g_store[key] = value;
	return true;
}

bool keychain_get(const std::string &key, std::string &r_value) {
	auto it = g_store.find(key);
	if (it == g_store.end()) {
		return false;
	}
	r_value = it->second;
	return true;
}

bool keychain_delete(const std::string &key) {
	g_store.erase(key);
	return true;
}

int reduce_motion() {
	return -1;
}

void stub_deliver_link(const std::string &uri) {
	if (uri.rfind("https://", 0) != 0) {
		return;
	}
	g_pending_uri = uri;
	if (g_on_link) {
		g_on_link(uri);
	}
}

void stub_finish_share(const std::string &result, const std::string &activity_type) {
	g_sheet_open = false;
	if (g_on_share) {
		g_on_share(result, activity_type);
	}
}

} // namespace lfnative
