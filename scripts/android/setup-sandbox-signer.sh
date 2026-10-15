#!/usr/bin/env bash
# ONLY for environments where Google's Android SDK downloads (dl.google.com) are blocked.
# Creates a minimal SDK layout so Godot's non-Gradle Android export can build and sign APKs:
#   build-tools/34.0.0/apksigner -> MiniApkSigner (Google's apksig library, bundled in
#                                   uber-apk-signer 1.3.0 from GitHub releases): v1+v2+v3 signing
#   platform-tools/adb           -> stub (Godot only checks it exists; needed for device deploy)
# On normal machines install the real Android SDK instead (docs/release-android.md).
set -euo pipefail
SDK="${ANDROID_SDK_DIR:-/opt/android-sdk}"
TOOLS="${ANDROID_TOOLS_DIR:-/opt/android-tools}"
mkdir -p "$TOOLS/classes" "$SDK/build-tools/34.0.0" "$SDK/platform-tools"
[ -f "$TOOLS/uber-apk-signer.jar" ] || curl -sSfL -o "$TOOLS/uber-apk-signer.jar" https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar
javac -cp "$TOOLS/uber-apk-signer.jar" -d "$TOOLS/classes" "$(dirname "$0")/MiniApkSigner.java"
cat > "$SDK/build-tools/34.0.0/apksigner" <<EOS
#!/bin/sh
exec java -cp $TOOLS/uber-apk-signer.jar:$TOOLS/classes MiniApkSigner "\$@"
EOS
printf '#!/bin/sh\necho "adb stub: platform-tools not installed" >&2\nexit 1\n' > "$SDK/platform-tools/adb"
chmod +x "$SDK/build-tools/34.0.0/apksigner" "$SDK/platform-tools/adb"
echo "Sandbox Android SDK layout ready at $SDK"
