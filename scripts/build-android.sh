#!/usr/bin/env bash
# Android builds (docs/release-android.md). Every artifact carries a VALIDATED client config, and the
# config packaged inside the artifact is re-read and compared after export.
#
#   scripts/build-android.sh debug                 -> apps/game/build/loopfactory-debug.apk
#       development config (loopback API allowed), debug keystore from editor settings.
#   scripts/build-android.sh release <staging|production>
#                                                  -> apps/game/build/loopfactory-<env>.apk
#   scripts/build-android.sh aab <staging|production>
#                                                  -> apps/game/build/loopfactory-<env>.aab (Gradle build)
#
# Release/AAB need: LF_BUILD (version code, increases every upload), LF_VERSION_NAME (optional),
# the LF_* public URLs (see scripts/client-config.ts), and the upload key via
# GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD (never committed).
# Toolchain: Godot 4.5.1 + matching export templates (Play: 16 KB pages, target API 36 via Gradle),
# Android SDK (platform 36, build-tools 35+), JDK 17. Godot 4.3 templates are NOT Play-compliant.
set -euo pipefail
MODE="${1:-debug}"
ENV_NAME="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAME="$ROOT/apps/game"
GODOT="${GODOT:-godot}"
CFG="$GAME/config/client.json"
PRESETS="$GAME/export_presets.cfg"
mkdir -p "$GAME/build"

die() { echo "build-android: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing $1 ($2)"; }
need node "Node 22"
need unzip "unzip"

GODOT_VER="$("$GODOT" --version 2>/dev/null | head -1 || true)"
echo "Godot: ${GODOT_VER:-not found}"
[ -n "$GODOT_VER" ] || die "Godot not found (set GODOT=/path/to/godot)"

# Restore the committed development config and presets whatever happens.
cp "$CFG" "$CFG.orig"
cp "$PRESETS" "$PRESETS.orig"
cleanup() { mv -f "$CFG.orig" "$CFG"; mv -f "$PRESETS.orig" "$PRESETS"; }
trap cleanup EXIT

set_preset() { # set_preset <preset name> <key> <value>  (only within that preset's options block)
  python3 - "$PRESETS" "$1" "$2" "$3" <<'EOF'
import re, sys
path, preset, key, value = sys.argv[1:]
text = open(path).read()
blocks = re.split(r'(?m)^(?=\[preset\.\d+(?:\.options)?\]$)', text)
idx = None
for b in blocks:
    m = re.match(r'\[preset\.(\d+)\]\n', b)
    if m and re.search(r'(?m)^name="%s"$' % re.escape(preset), b):
        idx = m.group(1)
if idx is None:
    sys.exit("no preset " + preset)
out = []
for b in blocks:
    if b.startswith('[preset.%s.options]' % idx):
        if re.search(r'(?m)^%s=' % re.escape(key), b):
            b = re.sub(r'(?m)^%s=.*$' % re.escape(key), '%s=%s' % (key, value), b)
        else:
            b = b.rstrip('\n') + '\n%s=%s\n\n' % (key, value)
    out.append(b)
new = ''.join(out)
if not re.search(r'(?m)^%s=%s$' % (re.escape(key), re.escape(value)), new):
    sys.exit('set_preset: %s was not applied to preset %s' % (key, preset))
open(path, 'w').write(new)
EOF
}

case "$MODE" in
  debug)
    PRESET="Android"
    OUT="$GAME/build/loopfactory-debug.apk"
    node "$ROOT/node_modules/.bin/tsx" "$ROOT/scripts/client-config.ts" write "${ENV_NAME:-development}"
    ;;
  release|aab)
    case "$ENV_NAME" in staging|production) ;; *) die "usage: $0 $MODE <staging|production>";; esac
    : "${LF_BUILD:?set LF_BUILD (version code; must increase for every Play upload)}"
    : "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?set the upload keystore path (never commit it)}"
    : "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:?set the upload key alias}"
    : "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:?set the upload key password}"
    [ -f "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" ] || die "keystore not found: $GODOT_ANDROID_KEYSTORE_RELEASE_PATH"
    case "$GODOT_VER" in 4.3.*) die "Godot 4.3 templates are not Play-compliant (4 KB native libs, target API 34). Use Godot 4.5.1.";; esac
    # Fails (writing nothing) on loopback/placeholder/insecure/missing values.
    node "$ROOT/node_modules/.bin/tsx" "$ROOT/scripts/client-config.ts" write "$ENV_NAME"
    if [ "$MODE" = "aab" ]; then
      PRESET="Android AAB"
      OUT="$GAME/build/loopfactory-$ENV_NAME.aab"
      [ -d "$GAME/android/build" ] || die "Gradle build template missing: open the project in Godot 4.5.1 and use Project > Install Android Build Template (or unzip android_source.zip into apps/game/android/build)"
      [ -n "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ] || die "set ANDROID_HOME to an SDK with platforms;android-36 and build-tools;35+"
      SDK="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
      [ -d "$SDK/platforms/android-36" ] || die "Android SDK platform 36 missing: sdkmanager 'platforms;android-36' 'build-tools;35.0.0'"
    else
      PRESET="Android"
      OUT="$GAME/build/loopfactory-$ENV_NAME.apk"
    fi
    set_preset "$PRESET" "version/code" "$LF_BUILD"
    [ -n "${LF_VERSION_NAME:-}" ] && set_preset "$PRESET" "version/name" "\"$LF_VERSION_NAME\""
    ;;
  *) die "usage: $0 debug | release <env> | aab <env>";;
esac

"$GODOT" --headless --path "$GAME" --import >/dev/null 2>&1 || true
if [ "$MODE" = "debug" ]; then
  "$GODOT" --headless --path "$GAME" --export-debug "$PRESET" "$OUT"
else
  "$GODOT" --headless --path "$GAME" --export-release "$PRESET" "$OUT"
fi
[ -f "$OUT" ] || die "export produced no artifact ($OUT)"

# The config INSIDE the artifact must be the validated one we just wrote.
node "$ROOT/node_modules/.bin/tsx" "$ROOT/scripts/client-config.ts" inspect "$OUT" "$CFG" || { rm -f "$OUT"; die "packaged config check failed; artifact removed"; }
python3 "$ROOT/scripts/android/check-artifact.py" "$OUT" || { [ "$MODE" = "debug" ] || { rm -f "$OUT"; die "artifact check failed; artifact removed"; }; }
ls -la "$OUT"
sha256sum "$OUT"
