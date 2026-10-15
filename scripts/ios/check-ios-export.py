#!/usr/bin/env python3
"""Validate a Godot iOS Xcode-project export (scripts/build-ios.sh, docs/IOS_BUILD_RUNBOOK.md).

Runs anywhere (no Xcode needed). Checks what can silently go wrong between the preset and Xcode:
  * the PCK: packaged client config byte-identical to the validated one; no tests/editor files;
    no loopback/placeholder API in staging/production;
  * Info.plist: display name, portrait only, no arbitrary loads, local networking only in
    development, required purpose strings present and non-empty, PrivacyInfo.xcprivacy present;
  * project.pbxproj: bundle id, team, deployment target, version/build, iPhone family;
  * entitlements: associated domains exactly as configured (or none);
  * app icon: 1024 px, opaque (App Store rejects alpha);
  * the native module xcframework when --native was requested.

Usage: check-ios-export.py --dir build/ios/<env> --name LoopFactory --config <client.json>
         --env <env> --bundle-id <id> --team <TEAMID> --version <x.y.z> --build <n>
         [--associated-domain <host>] [--native] [--min-ios 15.0]
Exit 1 when a check fails.
"""
import argparse
import json
import os
import plistlib
import re
import struct
import sys

LOOPBACK = re.compile(r"(127\.\d+\.\d+\.\d+|localhost|0\.0\.0\.0|\[::1\])")


def read_pck(path):
    """Godot 4.4+ pack format 3 (also accepts 2). Returns {path: bytes}."""
    d = open(path, "rb").read()
    magic, fmt = struct.unpack_from("<4sI", d, 0)
    if magic != b"GDPC" or fmt not in (2, 3):
        raise ValueError(f"not a Godot pack (magic {magic!r}, format {fmt})")
    flags = struct.unpack_from("<I", d, 20)[0]
    file_base = struct.unpack_from("<Q", d, 24)[0]
    if fmt == 3:
        p = struct.unpack_from("<Q", d, 32)[0]
    else:
        p = 24 + 8 + 16 * 4
    if flags & 1:
        raise ValueError("encrypted pack directory is not supported by this check")
    count = struct.unpack_from("<I", d, p)[0]
    p += 4
    files = {}
    for _ in range(count):
        n = struct.unpack_from("<I", d, p)[0]
        p += 4
        name = d[p : p + n].rstrip(b"\0").decode()
        p += n
        off, size = struct.unpack_from("<QQ", d, p)
        p += 16 + 16
        p += 4  # flags
        base = file_base if fmt == 3 else 0
        files[name.removeprefix("res://")] = d[base + off : base + off + size]
    return files


def png_info(path):
    with open(path, "rb") as f:
        head = f.read(33)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    w, h, depth, color = struct.unpack(">IIBB", head[16:26])
    return w, h, color  # color type 2 = RGB (opaque), 6 = RGBA


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--name", default="LoopFactory")
    ap.add_argument("--config", required=True)
    ap.add_argument("--env", required=True)
    ap.add_argument("--bundle-id", required=True)
    ap.add_argument("--team", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--build", required=True)
    ap.add_argument("--associated-domain", default="")
    ap.add_argument("--native", action="store_true")
    ap.add_argument("--min-ios", default="15.0")
    a = ap.parse_args()
    problems = []
    ok = []
    d, name = a.dir, a.name

    def need(cond, good, bad):
        (ok if cond else problems).append(good if cond else bad)

    # --- PCK ---------------------------------------------------------------------------------
    pck = os.path.join(d, f"{name}.pck")
    try:
        files = read_pck(pck)
        packaged = files.get("config/client.json")
        expected = open(a.config, "rb").read()
        need(packaged == expected, "PCK: client config identical to the validated config", "PCK: packaged config/client.json differs from the validated config (or is missing)")
        leaked = [f for f in files if f.startswith(("tests/", "tests_ui/", "tests_e2e/", "addons/"))]
        need(not leaked, f"PCK: {len(files)} files, no tests/editor files", f"PCK: test/editor files packaged: {leaked[:3]}")
        if packaged is not None and a.env != "development":
            cfg = json.loads(packaged)
            need(not LOOPBACK.search(cfg.get("apiBaseUrl", "")) and str(cfg.get("apiBaseUrl", "")).startswith("https://"), "PCK: release API is https and not loopback", f"PCK: release API not allowed: {cfg.get('apiBaseUrl')}")
    except (OSError, ValueError) as e:
        problems.append(f"PCK: {e}")

    # --- Info.plist --------------------------------------------------------------------------
    plist_path = os.path.join(d, name, f"{name}-Info.plist")
    try:
        with open(plist_path, "rb") as f:
            info = plistlib.load(f)
        orient = info.get("UISupportedInterfaceOrientations", [])
        need(orient == ["UIInterfaceOrientationPortrait"], "Info.plist: portrait only", f"Info.plist: orientations {orient}")
        ats = info.get("NSAppTransportSecurity", {})
        need(not ats.get("NSAllowsArbitraryLoads", False), "Info.plist: no NSAllowsArbitraryLoads", "Info.plist: NSAllowsArbitraryLoads must never be set")
        local = bool(ats.get("NSAllowsLocalNetworking", False))
        need(local == (a.env == "development"), f"Info.plist: local networking {'allowed (development)' if local else 'off'}", "Info.plist: NSAllowsLocalNetworking only belongs in development builds")
        for key in ("NSPhotoLibraryAddUsageDescription", "NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryUsageDescription"):
            need(str(info.get(key, "")).strip() != "", f"Info.plist: {key} set", f"Info.plist: {key} missing or empty")
        need(info.get("ITSAppUsesNonExemptEncryption") is False, "Info.plist: exempt encryption (HTTPS only)", "Info.plist: ITSAppUsesNonExemptEncryption should be false")
        need(info.get("UILaunchStoryboardName") is not None, "Info.plist: launch storyboard", "Info.plist: no launch storyboard")
        need("arm64" in info.get("UIRequiredDeviceCapabilities", []), "Info.plist: requires arm64", "Info.plist: UIRequiredDeviceCapabilities lacks arm64")
    except (OSError, plistlib.InvalidFileException) as e:
        problems.append(f"Info.plist: {e}")
    need(os.path.isfile(os.path.join(d, "PrivacyInfo.xcprivacy")), "PrivacyInfo.xcprivacy present", "PrivacyInfo.xcprivacy missing")

    # --- project.pbxproj ---------------------------------------------------------------------
    pbx_path = os.path.join(d, f"{name}.xcodeproj", "project.pbxproj")
    try:
        pbx = open(pbx_path, encoding="utf-8").read()

        def setting(key):
            return sorted(set(m.strip('"') for m in re.findall(rf"\b{key} = ([^;]+);", pbx)))

        need(setting("PRODUCT_BUNDLE_IDENTIFIER") == [a.bundle_id], f"pbxproj: bundle id {a.bundle_id}", f"pbxproj: bundle id {setting('PRODUCT_BUNDLE_IDENTIFIER')}")
        need(setting("DEVELOPMENT_TEAM") == [a.team], "pbxproj: team set from the environment", f"pbxproj: team {setting('DEVELOPMENT_TEAM')}")
        need(setting("IPHONEOS_DEPLOYMENT_TARGET") == [a.min_ios], f"pbxproj: deployment target {a.min_ios}", f"pbxproj: deployment target {setting('IPHONEOS_DEPLOYMENT_TARGET')}")
        need(setting("MARKETING_VERSION") == [a.version], f"pbxproj: version {a.version}", f"pbxproj: version {setting('MARKETING_VERSION')}")
        need(setting("CURRENT_PROJECT_VERSION") == [a.build], f"pbxproj: build {a.build}", f"pbxproj: build {setting('CURRENT_PROJECT_VERSION')}")
        need(setting("TARGETED_DEVICE_FAMILY") == ["1"], "pbxproj: iPhone family", f"pbxproj: device family {setting('TARGETED_DEVICE_FAMILY')}")
        need(setting("INFOPLIST_KEY_CFBundleDisplayName") == ["Loop Factory"], "pbxproj: display name 'Loop Factory'", f"pbxproj: display name {setting('INFOPLIST_KEY_CFBundleDisplayName')}")
        if a.native:
            need("LoopFactoryNative" in pbx, "pbxproj: LoopFactoryNative framework referenced", "pbxproj: native module requested but not referenced")
        else:
            need("LoopFactoryNative" not in pbx, "pbxproj: no native module (fallback build)", "pbxproj: native module referenced in a non-native build")
    except OSError as e:
        problems.append(f"pbxproj: {e}")

    # --- entitlements ------------------------------------------------------------------------
    ent_path = os.path.join(d, name, f"{name}.entitlements")
    try:
        with open(ent_path, "rb") as f:
            ent = plistlib.load(f)
        domains = ent.get("com.apple.developer.associated-domains", [])
        want = [f"applinks:{a.associated_domain}"] if a.associated_domain else []
        need(domains == want, f"entitlements: associated domains {want or 'none'}", f"entitlements: associated domains {domains}, expected {want}")
        need("aps-environment" not in ent, "entitlements: no push notifications", "entitlements: unexpected aps-environment")
    except (OSError, plistlib.InvalidFileException) as e:
        problems.append(f"entitlements: {e}")

    # --- icon --------------------------------------------------------------------------------
    icon_dir = os.path.join(d, name, "Images.xcassets", "AppIcon.appiconset")
    icons = [os.path.join(icon_dir, f) for f in (os.listdir(icon_dir) if os.path.isdir(icon_dir) else []) if f.endswith(".png")]
    big = [p for p in icons if (png_info(p) or (0, 0, 0))[0] == 1024]
    need(bool(big), "icon: 1024 px app icon present", "icon: no 1024 px app icon in AppIcon.appiconset")
    need(all((png_info(p) or (0, 0, 6))[2] == 2 for p in big), "icon: opaque (no alpha)", "icon: 1024 px icon has an alpha channel (App Store rejects it)")

    # --- native module -----------------------------------------------------------------------
    native_dirs = [r for r, ds, _ in os.walk(d) for x in ds if x == "LoopFactoryNative.xcframework"]
    if a.native:
        need(bool(native_dirs), "native: LoopFactoryNative.xcframework copied into the project", "native: LoopFactoryNative.xcframework missing from the export")

    for line in ok:
        print("ok   " + line)
    for line in problems:
        print("FAIL " + line)
    print("iOS export check:", "FAILED" if problems else f"passed ({len(ok)} checks)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
