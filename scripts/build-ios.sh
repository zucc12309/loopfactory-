#!/usr/bin/env bash
# iOS builds (docs/IOS_BUILD_RUNBOOK.md). Godot's iOS export produces an XCODE PROJECT, never a
# signed .ipa: compiling, signing and archiving are done here with Xcode tooling (macOS only).
#
#   scripts/build-ios.sh <development|staging|production> [mode] [options]
#
# Modes (default: export):
#   export      Validate config, export the Xcode project, check it. Works on Linux and macOS.
#   simulator   export + xcodebuild for the iOS Simulator (unsigned).               macOS + Xcode
#   device      export + xcodebuild for a physical iPhone (automatic signing).      macOS + Xcode
#   archive     export + xcodebuild archive + export an .ipa (development method).  macOS + Xcode
# Options:
#   --native    Build the LoopFactoryIOS GDExtension (share sheet, Universal Links, Keychain)
#               and link it in. macOS + Xcode. Without it the app uses the safe fallbacks.
#   --release   Godot release template (default: debug for development, release otherwise).
#
# Environment (never committed):
#   LF_IOS_TEAM_ID       Apple Developer Team ID (10 chars). Required for device/archive. For
#                        export/simulator without it, an obviously fake unsigned value is used.
#   LF_IOS_BUNDLE_ID     default com.loopfactory.game
#   LF_IOS_PROFILE       provisioning profile specifier (optional; automatic signing otherwise)
#   LF_BUILD             build number (CFBundleVersion); default 1 for development, required otherwise
#   LF_VERSION_NAME      default 0.1.0
#   LF_API_BASE_URL, LF_PRIVACY_POLICY_URL, LF_SUPPORT_URL, LF_APP_LINK_HOST, LF_POSTHOG_KEY
#                        client config (scripts/client-config.ts). LF_APP_LINK_HOST also becomes the
#                        applinks: associated domain.
#   GODOT                Godot 4.5.x binary (default: godot). GODOT_CPP: godot-cpp checkout.
#   LF_IOS_SIM_DEVICE    simulator name for `simulator` (default: first available iPhone)
#
# Outputs: build/ios/<env>/LoopFactory.xcodeproj (+ .pck, frameworks), logs in build/ios/<env>/logs/.
# Exit codes: 0 ok, 1 failure, 2 BLOCKED (the requested step needs macOS/Xcode).
set -euo pipefail
ENV_NAME="${1:-}"
shift || true
MODE="export"
NATIVE=0
RELEASE=""
for arg in "$@"; do
  case "$arg" in
    export|simulator|device|archive) MODE="$arg" ;;
    --native) NATIVE=1 ;;
    --release) RELEASE=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done
case "$ENV_NAME" in development|staging|production) ;; *) echo "usage: $0 <development|staging|production> [export|simulator|device|archive] [--native] [--release]" >&2; exit 1 ;; esac
[ -z "$RELEASE" ] && { [ "$ENV_NAME" = "development" ] && RELEASE=0 || RELEASE=1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAME="$ROOT/apps/game"
NATIVE_SRC="$ROOT/ios/loopfactory-native"
GODOT="${GODOT:-godot}"
CFG="$GAME/config/client.json"
PRESETS="$GAME/export_presets.cfg"
OUT_DIR="$GAME/build/ios/$ENV_NAME"
LOGS="$OUT_DIR/logs"
NAME="LoopFactory"
BUNDLE_ID="${LF_IOS_BUNDLE_ID:-com.loopfactory.game}"
VERSION_NAME="${LF_VERSION_NAME:-0.1.0}"
MIN_IOS="15.0"
UNSIGNED_TEAM="UNSIGNED00"
GODOT_CPP_TAG="godot-4.5-stable"

die() { echo "build-ios: $*" >&2; exit 1; }
blocked() { echo "build-ios: BLOCKED — $*" >&2; exit 2; }
step() { echo; echo "== $*"; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing $1 ($2)"; }

# ---------------------------------------------------------------- 1. prerequisites
step "Prerequisites"
need node "Node 22"
need python3 "Python 3"
GODOT_VER="$("$GODOT" --version 2>/dev/null | head -1 || true)"
echo "Godot: ${GODOT_VER:-not found}"
[ -n "$GODOT_VER" ] || die "Godot not found (set GODOT=/path/to/Godot 4.5.1)"
case "$GODOT_VER" in 4.5.*) ;; *) die "Godot 4.5.x required for the iOS target (found $GODOT_VER); the project's iOS templates and native module are built for 4.5";; esac
TPL_VER="$(echo "$GODOT_VER" | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?)\.([a-z]+).*/\1.\3/')"
TPL_DIRS=("$HOME/.local/share/godot/export_templates/$TPL_VER" "$HOME/Library/Application Support/Godot/export_templates/$TPL_VER")
TPL=""
for t in "${TPL_DIRS[@]}"; do [ -f "$t/ios.zip" ] && TPL="$t/ios.zip"; done
[ -n "$TPL" ] || die "iOS export template missing: install the $TPL_VER export templates (Editor > Manage Export Templates) so that ios.zip exists in one of: ${TPL_DIRS[*]}"
echo "iOS template: $TPL"
ON_MAC=0
XCODE=""
if [ "$(uname -s)" = "Darwin" ] && command -v xcodebuild >/dev/null 2>&1; then
  XCODE="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' || true)"
  if [ -n "$XCODE" ]; then
    ON_MAC=1
    echo "Xcode: $XCODE"
    echo "iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo unknown)"
  fi
fi
[ "$ON_MAC" = 1 ] || echo "Xcode: not available (export and checks only; compile/install steps are BLOCKED here)"
if [ "$MODE" != "export" ] && [ "$ON_MAC" != 1 ]; then blocked "'$MODE' needs macOS with Xcode"; fi
if [ "$NATIVE" = 1 ] && [ "$ON_MAC" != 1 ]; then blocked "--native compiles Objective-C++ against the iOS SDK and needs macOS with Xcode"; fi

TEAM="${LF_IOS_TEAM_ID:-}"
if [ -z "$TEAM" ]; then
  [ "$MODE" = "device" ] || [ "$MODE" = "archive" ] && die "set LF_IOS_TEAM_ID (Apple Developer → Membership) for signed builds"
  TEAM="$UNSIGNED_TEAM"
  echo "Team: none set — using '$UNSIGNED_TEAM' for an UNSIGNED export (not installable on a device)"
else
  [[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || die "LF_IOS_TEAM_ID must be the 10-character Team ID"
  [ "$TEAM" != "$UNSIGNED_TEAM" ] || die "LF_IOS_TEAM_ID is the unsigned placeholder"
fi
if [ "$ENV_NAME" != "development" ]; then
  : "${LF_BUILD:?set LF_BUILD (CFBundleVersion; must increase for every TestFlight/App Store upload)}"
fi
BUILD="${LF_BUILD:-1}"
[[ "$BUILD" =~ ^[0-9]+$ ]] || die "LF_BUILD must be a positive integer"
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || die "LF_IOS_BUNDLE_ID is not a valid bundle identifier"

mkdir -p "$LOGS"
# Restore the committed config/presets and remove the temporary native install whatever happens.
cp "$CFG" "$CFG.orig"
cp "$PRESETS" "$PRESETS.orig"
cleanup() {
  mv -f "$CFG.orig" "$CFG"
  mv -f "$PRESETS.orig" "$PRESETS"
  if [ -d "$GAME/native/ios" ]; then
    rm -rf "$GAME/native/ios"
    rmdir "$GAME/native" 2>/dev/null || true
    "$GODOT" --headless --path "$GAME" --import >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

set_preset() { # set_preset <preset name> <key> <value>
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
            b = re.sub(r'(?m)^%s=.*$' % re.escape(key), lambda _: '%s=%s' % (key, value), b)
        else:
            b = b.rstrip('\n') + '\n%s=%s\n\n' % (key, value)
    out.append(b)
new = ''.join(out)
if not re.search(r'(?m)^%s=%s$' % (re.escape(key), re.escape(value)), new):
    sys.exit('set_preset: %s was not applied to preset %s' % (key, preset))
open(path, 'w').write(new)
EOF
}
gd_str() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }

# ---------------------------------------------------------------- 2. client configuration
step "Client configuration ($ENV_NAME)"
# Fails (writing nothing) on loopback/placeholder/insecure/missing values for staging/production.
if ! LF_BUILD="$BUILD" node "$ROOT/node_modules/.bin/tsx" "$ROOT/scripts/client-config.ts" write "$ENV_NAME" >"$LOGS/config.log" 2>&1; then
  cat "$LOGS/config.log" >&2
  die "client config invalid (see $LOGS/config.log)"
fi
cat "$LOGS/config.log"
cp "$CFG" "$OUT_DIR/client.json.expected"
LINK_HOST="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("appLinks",{}).get("host",""))' "$CFG")"
echo "Universal Links domain: ${LINK_HOST:-none (manual code entry only)}"
if [ -n "$LINK_HOST" ] && [ "$ENV_NAME" != "development" ]; then
  [[ "$LINK_HOST" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]] || die "LF_APP_LINK_HOST must be a bare host name (got $LINK_HOST)"
fi

# ---------------------------------------------------------------- 3. native module (optional)
if [ "$NATIVE" = 1 ]; then
  step "Native module (LoopFactoryIOS GDExtension)"
  need scons "pip install scons"
  CPP="${GODOT_CPP:-$NATIVE_SRC/godot-cpp}"
  if [ ! -f "$CPP/SConstruct" ]; then
    git clone --depth 1 --branch "$GODOT_CPP_TAG" https://github.com/godotengine/godot-cpp "$CPP" >"$LOGS/godot-cpp-clone.log" 2>&1 || die "could not clone godot-cpp ($GODOT_CPP_TAG)"
  fi
  [ "$CPP" = "$NATIVE_SRC/godot-cpp" ] || ln -sfn "$CPP" "$NATIVE_SRC/godot-cpp"
  NB="$NATIVE_SRC/build"
  for TARGET in template_debug template_release; do
    CFGNAME=${TARGET#template_}
    (cd "$NATIVE_SRC" && scons platform=ios arch=arm64 target=$TARGET ios_min_version=$MIN_IOS -j"$(sysctl -n hw.ncpu)") >"$LOGS/native-$CFGNAME-device.log" 2>&1 || die "native device build failed ($LOGS/native-$CFGNAME-device.log)"
    (cd "$NATIVE_SRC" && scons platform=ios ios_simulator=yes arch=universal target=$TARGET ios_min_version=$MIN_IOS -j"$(sysctl -n hw.ncpu)") >"$LOGS/native-$CFGNAME-sim.log" 2>&1 || die "native simulator build failed ($LOGS/native-$CFGNAME-sim.log)"
    DEV_LIB="$(ls -t "$NATIVE_SRC"/bin/libloopfactory_native.ios.$TARGET*.dylib | grep -v simulator | head -1)"
    SIM_LIB="$(ls -t "$NATIVE_SRC"/bin/libloopfactory_native.ios.$TARGET*simulator*.dylib | head -1)"
    rm -rf "$NB/$CFGNAME"
    for KIND in device simulator; do
      FW="$NB/$CFGNAME/$KIND/LoopFactoryNative.framework"
      mkdir -p "$FW"
      [ "$KIND" = device ] && cp "$DEV_LIB" "$FW/LoopFactoryNative" || cp "$SIM_LIB" "$FW/LoopFactoryNative"
      install_name_tool -id @rpath/LoopFactoryNative.framework/LoopFactoryNative "$FW/LoopFactoryNative"
      PLAT=$([ "$KIND" = device ] && echo iPhoneOS || echo iPhoneSimulator)
      cat >"$FW/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LoopFactoryNative</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID.native</string>
<key>CFBundleName</key><string>LoopFactoryNative</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>$VERSION_NAME</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>CFBundleSupportedPlatforms</key><array><string>$PLAT</string></array>
<key>MinimumOSVersion</key><string>$MIN_IOS</string>
</dict></plist>
PLIST
    done
    mkdir -p "$GAME/native/ios/bin/$CFGNAME"
    xcodebuild -create-xcframework -framework "$NB/$CFGNAME/device/LoopFactoryNative.framework" -framework "$NB/$CFGNAME/simulator/LoopFactoryNative.framework" \
      -output "$GAME/native/ios/bin/$CFGNAME/LoopFactoryNative.xcframework" >"$LOGS/native-$CFGNAME-xcframework.log" 2>&1 || die "xcframework creation failed"
  done
  cp "$NATIVE_SRC/loopfactory_native.gdextension" "$GAME/native/ios/loopfactory_native.gdextension"
  echo "native module installed for this export: apps/game/native/ios/"
fi

# ---------------------------------------------------------------- 4. export preset (temporary)
step "Export preset"
PLIST_EXTRA='<key>NSPhotoLibraryAddUsageDescription</key><string>Lets you save Loop Factory result cards to your photo library when you choose Save Image in the share sheet.</string>'
if [ "$ENV_NAME" = "development" ]; then
  # Development builds talk to a local API over plain HTTP; never allowed in staging/production.
  PLIST_EXTRA="$PLIST_EXTRA<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>"
  PLIST_EXTRA="$PLIST_EXTRA<key>NSLocalNetworkUsageDescription</key><string>Development build: connects to the Loop Factory test server on your local network.</string>"
fi
ENTITLEMENTS=""
[ -n "$LINK_HOST" ] && ENTITLEMENTS="<key>com.apple.developer.associated-domains</key><array><string>applinks:$LINK_HOST</string></array>"
set_preset "iOS" "application/app_store_team_id" "\"$TEAM\""
set_preset "iOS" "application/bundle_identifier" "\"$BUNDLE_ID\""
set_preset "iOS" "application/short_version" "\"$VERSION_NAME\""
set_preset "iOS" "application/version" "\"$BUILD\""
set_preset "iOS" "application/min_ios_version" "\"$MIN_IOS\""
set_preset "iOS" "application/export_project_only" "true"
set_preset "iOS" "application/additional_plist_content" "$(gd_str "$PLIST_EXTRA")"
set_preset "iOS" "entitlements/additional" "$(gd_str "$ENTITLEMENTS")"
if [ -n "${LF_IOS_PROFILE:-}" ]; then
  set_preset "iOS" "application/provisioning_profile_specifier_debug" "$(gd_str "$LF_IOS_PROFILE")"
  set_preset "iOS" "application/provisioning_profile_specifier_release" "$(gd_str "$LF_IOS_PROFILE")"
fi
echo "bundle $BUNDLE_ID · version $VERSION_NAME ($BUILD) · iOS $MIN_IOS+ · team $TEAM · $([ "$RELEASE" = 1 ] && echo release || echo debug) template · native $([ "$NATIVE" = 1 ] && echo yes || echo no)"

# ---------------------------------------------------------------- 5. export Xcode project
step "Godot export"
rm -rf "$OUT_DIR/$NAME" "$OUT_DIR/$NAME.xcodeproj" "$OUT_DIR/$NAME.pck" "$OUT_DIR"/*.xcframework
"$GODOT" --headless --path "$GAME" --import >"$LOGS/import.log" 2>&1 || true
EXPORT_FLAG=$([ "$RELEASE" = 1 ] && echo --export-release || echo --export-debug)
"$GODOT" --headless --path "$GAME" "$EXPORT_FLAG" "iOS" "$OUT_DIR/$NAME.xcodeproj" >"$LOGS/godot-export.log" 2>&1 || true
grep -E "ERROR|WARNING" "$LOGS/godot-export.log" | grep -v "can only be built on macOS" || true
[ -f "$OUT_DIR/$NAME.xcodeproj/project.pbxproj" ] || die "Godot produced no Xcode project (see $LOGS/godot-export.log)"
grep -q "ERROR: Project export for preset" "$LOGS/godot-export.log" && die "Godot export failed (see $LOGS/godot-export.log)"

# ---------------------------------------------------------------- 6. validate generated project
step "Validate export"
NATIVE_FLAG=$([ "$NATIVE" = 1 ] && echo --native || true)
CHECK_OK=1
python3 "$ROOT/scripts/ios/check-ios-export.py" --dir "$OUT_DIR" --name "$NAME" --config "$OUT_DIR/client.json.expected" \
  --env "$ENV_NAME" --bundle-id "$BUNDLE_ID" --team "$TEAM" --version "$VERSION_NAME" --build "$BUILD" \
  --associated-domain "$LINK_HOST" --min-ios "$MIN_IOS" $NATIVE_FLAG >"$LOGS/check.log" 2>&1 || CHECK_OK=0
cat "$LOGS/check.log"
[ "$CHECK_OK" = 1 ] || die "export check failed (see $LOGS/check.log)"

# ---------------------------------------------------------------- 7. compile (macOS)
PROJ="$OUT_DIR/$NAME.xcodeproj"
SCHEME="$NAME"
XCCONF=$([ "$RELEASE" = 1 ] && echo Release || echo Debug)
case "$MODE" in
  export)
    echo
    echo "Xcode project: $PROJ"
    [ "$ON_MAC" = 1 ] && echo "Next: scripts/build-ios.sh $ENV_NAME simulator   (or open the project in Xcode)" \
      || echo "Compilation: BLOCKED here (no macOS/Xcode). Copy the repo to a Mac and run: scripts/build-ios.sh $ENV_NAME simulator"
    ;;
  simulator)
    step "xcodebuild (iOS Simulator, unsigned)"
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration "$XCCONF" -sdk iphonesimulator \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath "$OUT_DIR/DerivedData" \
      CODE_SIGNING_ALLOWED=NO build >"$LOGS/xcodebuild-simulator.log" 2>&1 || die "simulator build failed (see $LOGS/xcodebuild-simulator.log)"
    APP="$(find "$OUT_DIR/DerivedData/Build/Products" -maxdepth 2 -name "$NAME.app" -path "*iphonesimulator*" | head -1)"
    [ -n "$APP" ] || die "no .app produced"
    echo "App: $APP"
    SIM="${LF_IOS_SIM_DEVICE:-$(xcrun simctl list devices available | grep -E '^[[:space:]]+iPhone' | head -1 | sed -E 's/^[[:space:]]+(.*) \([0-9A-F-]+\).*/\1/')}"
    if [ -n "$SIM" ]; then
      echo "Installing on simulator: $SIM"
      xcrun simctl boot "$SIM" 2>/dev/null || true
      xcrun simctl install "$SIM" "$APP" && xcrun simctl launch "$SIM" "$BUNDLE_ID" | tee "$LOGS/simulator-launch.log" || die "simulator install/launch failed"
      echo "Launched. Logs: xcrun simctl spawn \"$SIM\" log stream --predicate 'process == \"$NAME\"'"
    fi
    ;;
  device)
    step "xcodebuild (iPhone, automatic signing)"
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration "$XCCONF" -sdk iphoneos \
      -destination 'generic/platform=iOS' -derivedDataPath "$OUT_DIR/DerivedData" -allowProvisioningUpdates \
      DEVELOPMENT_TEAM="$TEAM" build >"$LOGS/xcodebuild-device.log" 2>&1 || die "device build failed (see $LOGS/xcodebuild-device.log)"
    APP="$(find "$OUT_DIR/DerivedData/Build/Products" -maxdepth 2 -name "$NAME.app" -path "*iphoneos*" | head -1)"
    echo "App: $APP"
    echo "Install: xcrun devicectl device install app --device <UDID> \"$APP\"   (list: xcrun devicectl list devices)"
    ;;
  archive)
    step "xcodebuild archive + export (.ipa, development method)"
    ARCHIVE="$OUT_DIR/$NAME.xcarchive"
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
      -archivePath "$ARCHIVE" -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" archive >"$LOGS/xcodebuild-archive.log" 2>&1 || die "archive failed (see $LOGS/xcodebuild-archive.log)"
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT_DIR/ipa" -exportOptionsPlist "$OUT_DIR/$NAME/export_options.plist" \
      -allowProvisioningUpdates >"$LOGS/xcodebuild-export.log" 2>&1 || die "ipa export failed (see $LOGS/xcodebuild-export.log)"
    ls -la "$OUT_DIR/ipa"
    ;;
esac
echo
echo "Logs: $LOGS"
