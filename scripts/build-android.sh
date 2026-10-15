#!/usr/bin/env bash
# Builds Android APKs with Godot's non-Gradle exporter.
#   scripts/build-android.sh debug     -> apps/game/build/loopfactory-debug.apk
#   scripts/build-android.sh release   -> apps/game/build/loopfactory-release.apk
# Prerequisites (docs/release-android.md): Godot 4.3 + export templates, Android SDK with
# build-tools (apksigner) and platform-tools, JDK 17+, editor settings pointing at the SDK.
# Release signing: GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD (never commit keys).
set -euo pipefail
MODE="${1:-debug}"
cd "$(dirname "$0")/../apps/game"
mkdir -p build
"${GODOT:-godot}" --headless --path . --import >/dev/null 2>&1 || true
if [ "$MODE" = "release" ]; then
  : "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?set the upload keystore path}"
  "${GODOT:-godot}" --headless --path . --export-release "Android" build/loopfactory-release.apk
else
  "${GODOT:-godot}" --headless --path . --export-debug "Android" build/loopfactory-debug.apk
fi
ls -la build/
