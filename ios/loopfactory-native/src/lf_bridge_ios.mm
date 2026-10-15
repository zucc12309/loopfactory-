// iOS implementation of lf_bridge.h (UIKit + Security). Compiled with -fobjc-arc.
//
// STATUS: written against the Godot 4.5.1 iOS template (GDTApplicationDelegate +addService:,
// verified by inspecting libgodot.ios.release.xcframework); NOT yet compiled or run on a device —
// see docs/IOS_READINESS.md. Nothing here depends on Godot headers.
//
// Universal Links. Godot 4.5's app delegate (GDTApplicationDelegate) forwards UIApplicationDelegate
// calls, including application:continueUserActivity:restorationHandler:, to registered "services".
// LFLinkService is registered:
//   * from +load, as soon as UIApplicationDidFinishLaunchingNotification is posted (before iOS
//     delivers a cold-start user activity), and also reads the activity from the launch options;
//   * again (idempotently) when the extension initialises, in case the library was loaded late.
// The class is looked up by name at runtime, so a Godot version without it only disables links.
//
// Share sheet. UIActivityViewController presented on the main thread from the top-most view
// controller, anchored to the bottom centre for iPad popovers. Files are copied into
// tmp/lf-share/ (copies older than an hour are pruned at the next share) so the receiving app reads a
// stable file even after the game rewrites its own copy.
//
// Keychain. kSecClassGenericPassword, service "<bundle id>.auth", accessible after first unlock,
// this device only (not migrated to other devices / backups).

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

#include "lf_bridge.h"

namespace {
lfnative::LinkCallback g_on_link = nullptr;
lfnative::ShareCallback g_on_share = nullptr;
std::string g_pending_uri;
int g_keychain_ok = -1; // -1 not probed yet
} // namespace

static void lf_store_link(NSURL *url) {
	if (url == nil || ![[url.scheme lowercaseString] isEqualToString:@"https"]) {
		return;
	}
	const char *c = url.absoluteString.UTF8String;
	std::string s = c ? c : "";
	if (s.empty()) {
		return;
	}
	g_pending_uri = s; // latest link wins; the game consumes it once
	if (g_on_link) {
		g_on_link(s);
	}
}

@interface LFLinkService : NSObject <UIApplicationDelegate>
@end

@implementation LFLinkService
- (BOOL)application:(UIApplication *)application
		continueUserActivity:(NSUserActivity *)userActivity
		  restorationHandler:(void (^)(NSArray<id<UIUserActivityRestoring>> *_Nullable))restorationHandler {
	if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] && userActivity.webpageURL != nil) {
		lf_store_link(userActivity.webpageURL);
		return YES;
	}
	return NO;
}
@end

static LFLinkService *g_link_service = nil;

static void lf_register_link_service(void) {
	if (g_link_service != nil) {
		return;
	}
	Class cls = NSClassFromString(@"GDTApplicationDelegate");
	SEL sel = NSSelectorFromString(@"addService:");
	if (cls == Nil || ![cls respondsToSelector:sel]) {
		NSLog(@"[LoopFactoryIOS] GDTApplicationDelegate +addService: not found; Universal Links are disabled in this build");
		return;
	}
	g_link_service = [LFLinkService new];
	((void (*)(id, SEL, id))objc_msgSend)(cls, sel, g_link_service);
}

@interface LFLinkBootstrap : NSObject
@end

@implementation LFLinkBootstrap
+ (void)load {
	[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
													  object:nil
													   queue:nil
												  usingBlock:^(NSNotification *note) {
													  lf_register_link_service();
													  NSDictionary *d = note.userInfo[UIApplicationLaunchOptionsUserActivityDictionaryKey];
													  id activity = [d isKindOfClass:[NSDictionary class]] ? d[@"UIApplicationLaunchOptionsUserActivityKey"] : nil;
													  if ([activity isKindOfClass:[NSUserActivity class]] &&
															  [((NSUserActivity *)activity).activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
														  lf_store_link(((NSUserActivity *)activity).webpageURL);
													  }
												  }];
}
@end

static UIViewController *lf_top_view_controller(void) {
	UIWindow *window = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) {
			continue;
		}
		for (UIWindow *w in ((UIWindowScene *)scene).windows) {
			if (w.isKeyWindow) {
				window = w;
				break;
			}
		}
	}
	id<UIApplicationDelegate> delegate = UIApplication.sharedApplication.delegate;
	if (window == nil && [delegate respondsToSelector:@selector(window)]) {
		window = delegate.window;
	}
	UIViewController *vc = window.rootViewController;
	while (vc.presentedViewController != nil && !vc.presentedViewController.isBeingDismissed) {
		vc = vc.presentedViewController;
	}
	return vc;
}

static NSString *lf_share_dir(void) {
	NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"lf-share"];
	NSFileManager *fm = NSFileManager.defaultManager;
	[fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-3600];
	for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
		NSString *p = [dir stringByAppendingPathComponent:name];
		NSDate *m = [[fm attributesOfItemAtPath:p error:nil] fileModificationDate];
		if (m != nil && [m compare:cutoff] == NSOrderedAscending) {
			[fm removeItemAtPath:p error:nil];
		}
	}
	return dir;
}

namespace lfnative {

bool is_native_ios() {
	return true;
}

void init(LinkCallback on_link, ShareCallback on_share) {
	g_on_link = on_link;
	g_on_share = on_share;
	lf_register_link_service();
}

void shutdown() {
	g_on_link = nullptr;
	g_on_share = nullptr;
}

int share(const std::string &text, const std::string &abs_path, const std::string &mime, const std::string &title) {
	(void)title; // iOS share sheets have no title; the text carries the message.
	NSFileManager *fm = NSFileManager.defaultManager;
	NSMutableArray *items = [NSMutableArray array];
	if (!abs_path.empty()) {
		NSString *path = [NSString stringWithUTF8String:abs_path.c_str()];
		BOOL is_dir = NO;
		if (path == nil || ![fm fileExistsAtPath:path isDirectory:&is_dir] || is_dir || ![fm isReadableFileAtPath:path]) {
			return SHARE_INVALID_FILE;
		}
		NSString *dst = [lf_share_dir() stringByAppendingPathComponent:path.lastPathComponent];
		[fm removeItemAtPath:dst error:nil];
		if (![fm copyItemAtPath:path toPath:dst error:nil]) {
			return SHARE_FAILED;
		}
		if (mime.rfind("image/", 0) == 0 && [UIImage imageWithContentsOfFile:dst] == nil) {
			[fm removeItemAtPath:dst error:nil];
			return SHARE_INVALID_FILE;
		}
		[items addObject:[NSURL fileURLWithPath:dst]];
	}
	if (!text.empty()) {
		NSString *t = [NSString stringWithUTF8String:text.c_str()];
		if (t != nil) {
			[items addObject:t];
		}
	}
	if (items.count == 0) {
		return SHARE_FAILED;
	}
	UIViewController *top = lf_top_view_controller();
	if (top == nil || [top isKindOfClass:[UIActivityViewController class]]) {
		return SHARE_FAILED; // no window yet, or a sheet is already showing
	}
	UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
	avc.completionWithItemsHandler = ^(UIActivityType activity_type, BOOL completed, NSArray *returned_items, NSError *error) {
		// "completed" = the chosen activity said it finished. It does NOT mean anyone received it.
		std::string result = error != nil ? "failed" : (completed ? "completed" : "cancelled");
		std::string activity = activity_type != nil ? std::string(activity_type.UTF8String) : std::string();
		if (g_on_share) {
			g_on_share(result, activity);
		}
	};
	UIPopoverPresentationController *pop = avc.popoverPresentationController;
	if (pop != nil) {
		CGRect b = top.view.bounds;
		pop.sourceView = top.view;
		pop.sourceRect = CGRectMake(CGRectGetMidX(b), CGRectGetMaxY(b) - 1.0, 1.0, 1.0);
		pop.permittedArrowDirections = 0;
	}
	void (^present)(void) = ^{
		[top presentViewController:avc animated:YES completion:nil];
	};
	if (NSThread.isMainThread) {
		present();
	} else {
		dispatch_async(dispatch_get_main_queue(), present);
	}
	return SHARE_OPENED;
}

std::string consume_launch_uri() {
	std::string out = g_pending_uri;
	g_pending_uri.clear();
	return out;
}

static NSMutableDictionary *lf_keychain_query(const std::string &key) {
	NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"com.loopfactory.game";
	return [@{
		(__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService : [bundle stringByAppendingString:@".auth"],
		(__bridge id)kSecAttrAccount : [NSString stringWithUTF8String:key.c_str()] ?: @"",
	} mutableCopy];
}

bool keychain_set(const std::string &key, const std::string &value) {
	NSData *data = [NSData dataWithBytes:value.data() length:value.size()];
	NSMutableDictionary *query = lf_keychain_query(key);
	NSDictionary *attrs = @{
		(__bridge id)kSecValueData : data,
		(__bridge id)kSecAttrAccessible : (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
	};
	OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attrs);
	if (st == errSecItemNotFound) {
		[query addEntriesFromDictionary:attrs];
		st = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
	}
	return st == errSecSuccess;
}

bool keychain_get(const std::string &key, std::string &r_value) {
	NSMutableDictionary *query = lf_keychain_query(key);
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
	CFTypeRef result = NULL;
	OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (st != errSecSuccess || result == NULL) {
		return false;
	}
	NSData *data = (__bridge_transfer NSData *)result;
	r_value.assign((const char *)data.bytes, data.length);
	return true;
}

bool keychain_delete(const std::string &key) {
	OSStatus st = SecItemDelete((__bridge CFDictionaryRef)lf_keychain_query(key));
	return st == errSecSuccess || st == errSecItemNotFound;
}

// Probed once with a throwaway item: the Keychain can be unavailable (e.g. a simulator or an
// unsigned build without a keychain access group), and the game must then keep using the file.
bool keychain_available() {
	if (g_keychain_ok < 0) {
		std::string v;
		g_keychain_ok = (keychain_set("__probe", "1") && keychain_get("__probe", v) && v == "1") ? 1 : 0;
		keychain_delete("__probe");
	}
	return g_keychain_ok == 1;
}

int reduce_motion() {
	return UIAccessibilityIsReduceMotionEnabled() ? 1 : 0;
}

} // namespace lfnative
