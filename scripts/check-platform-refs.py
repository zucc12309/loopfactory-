#!/usr/bin/env python3
"""Shared GDScript must not depend on a specific platform (docs/IOS_READINESS.md).

Everything that differs between Android, iOS and desktop lives in apps/game/scripts/platform/
(LFPlatform and its adapters). This check fails CI when shared code reaches around it:
native singletons, Java/JS bridges, platform-name feature checks, branching on OS.get_name(),
direct haptics or OS.shell_open. OS.get_name() as a reported VALUE (analytics, diagnostics, the
guest-account platform field) is allowed; OS.has_feature("mobile") is platform-neutral and allowed.

Usage: check-platform-refs.py [game_dir]   (default apps/game). --selftest runs the rule cases.
"""
import os
import re
import sys

RULES = [
    (re.compile(r"Engine\.(has|get)_singleton\s*\("), "native singleton lookup (use LFPlatform)"),
    (re.compile(r"\b(JavaClassWrapper|JavaScriptBridge|AndroidRuntime)\b"), "platform bridge (use an adapter)"),
    (re.compile(r"has_feature\(\s*\"(android|ios|web|macos|windows|linux|linuxbsd|visionos)\"", re.I), "platform-name feature check"),
    (re.compile(r"OS\.get_name\(\)\s*(==|!=|in\b|\.to_lower\(\)\s*(==|!=))"), "branching on OS.get_name()"),
    (re.compile(r"match\s+OS\.get_name\(\)"), "branching on OS.get_name()"),
    (re.compile(r"\"(LoopFactoryShare|LoopFactoryIOS)\""), "native module name (adapters only)"),
    (re.compile(r"Input\.vibrate_handheld\s*\("), "direct haptics (use LFPlatform.vibrate)"),
    (re.compile(r"OS\.shell_open\s*\("), "direct OS.shell_open (use LFPlatform.open_external_url)"),
]
ALLOWED_DIRS = ("scripts/platform/", "addons/", "tests/", "tests_e2e/", "tests_ui/")


def violations(text):
    out = []
    for n, line in enumerate(text.splitlines(), 1):
        code = line.split("#", 1)[0]
        for rx, why in RULES:
            if rx.search(code):
                out.append((n, why, line.strip()))
    return out


def selftest():
    bad = [
        'if Engine.has_singleton("X"):', 'var j = JavaClassWrapper.wrap("a")', 'if OS.has_feature("ios"):',
        'if OS.get_name() == "Android":', 'match OS.get_name():', 'const P := "LoopFactoryIOS"',
        "Input.vibrate_handheld(10)", "OS.shell_open(url)", 'if OS.get_name().to_lower() != "ios":',
    ]
    good = [
        'var p := {"platform": OS.get_name()}', 'if OS.has_feature("mobile"):', "# Engine.has_singleton(x) in a comment",
        "LFPlatform.vibrate(12)", 'LFPlatform.open_external_url("https://a.b")',
    ]
    fails = [b for b in bad if not violations(b)] + [g for g in good if violations(g)]
    for f in fails:
        print("selftest FAIL:", f)
    print(f"platform-refs selftest: {len(bad) + len(good)} cases, {len(fails)} failed")
    return 1 if fails else 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    game = argv[1] if len(argv) > 1 else "apps/game"
    found = 0
    scanned = 0
    for dirpath, _, files in os.walk(game):
        rel_dir = os.path.relpath(dirpath, game).replace(os.sep, "/") + "/"
        if rel_dir.startswith((".godot/", "build/", "native/")) or rel_dir.startswith(ALLOWED_DIRS):
            continue
        for f in files:
            if not f.endswith(".gd"):
                continue
            scanned += 1
            path = os.path.join(dirpath, f)
            for n, why, line in violations(open(path, encoding="utf-8").read()):
                found += 1
                print(f"{os.path.relpath(path, game)}:{n}: {why}: {line}")
    print(f"platform-refs: {scanned} shared scripts scanned, {found} platform-specific reference(s)")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
