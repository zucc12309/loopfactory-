#!/usr/bin/env bash
# Compiles the LoopFactoryIOS GDExtension for the HOST with the stub bridge (no UIKit) and runs
# apps/game/tests_e2e/ios_native_binding_tests.gd against it in a scratch copy of the project.
# Verifies the C++/godot-cpp binding layer and its contract with the GDScript adapter. It does not
# exercise UIKit — see docs/IOS_DEVICE_TEST_MATRIX.md for simulator/device checks.
#
#   GODOT=/path/to/godot-4.5.x scripts/ios/test-native-stub.sh
# Needs: scons (pip install scons), a C++17 compiler, git (godot-cpp is cloned on first run).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NATIVE="$ROOT/ios/loopfactory-native"
GODOT="${GODOT:-godot}"
TAG="godot-4.5-stable"
VER="$("$GODOT" --version | head -1)"
case "$VER" in 4.5.*) ;; *) echo "Godot 4.5.x required (found $VER)" >&2; exit 1;; esac
case "$(uname -s)" in
  Linux) PLATFORM=linux; EXT=so; KEY=linux.debug.x86_64 ;;
  Darwin) PLATFORM=macos; EXT=dylib; KEY=macos.debug ;;
  *) echo "unsupported host" >&2; exit 1 ;;
esac
if [ ! -f "$NATIVE/godot-cpp/SConstruct" ]; then
  git clone --depth 1 --branch "$TAG" https://github.com/godotengine/godot-cpp "$NATIVE/godot-cpp"
fi
(cd "$NATIVE" && scons platform=$PLATFORM target=template_debug -j"$(getconf _NPROCESSORS_ONLN)")
LIB="$(ls -t "$NATIVE"/bin/libloopfactory_native.$PLATFORM.template_debug*.$EXT | head -1)"
# Scratch project (kept for inspection; recreated on every run).
WORK="$NATIVE/build/stub-test"
rm -rf "${WORK:?}"
mkdir -p "$WORK"
cp -r "$ROOT/apps/game/." "$WORK/"
rm -rf "${WORK:?}/.godot" "${WORK:?}/build"
mkdir -p "$WORK/native/stub"
cp "$LIB" "$WORK/native/stub/"
cat >"$WORK/native/stub/loopfactory_native_stub.gdextension" <<EOF
[configuration]
entry_symbol = "loopfactory_native_init"
compatibility_minimum = "4.5"
reloadable = false

[libraries]
$KEY = "res://native/stub/$(basename "$LIB")"
EOF
"$GODOT" --headless --path "$WORK" --import >/dev/null 2>&1 || true
LOG="$WORK/out.log"
timeout 120 "$GODOT" --headless --path "$WORK" -s res://tests_e2e/ios_native_binding_tests.gd 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
if grep -E "SCRIPT ERROR|Parse Error" "$LOG" >/dev/null || ! grep -q "iOS native binding tests: .* 0 failed" "$LOG"; then
  STATUS=1
fi
exit "$STATUS"
