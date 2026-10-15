# iOS build runbook

How to go from this repository to Loop Factory running on the iOS Simulator and on your iPhone.
Background, status and evidence: [IOS_READINESS.md](IOS_READINESS.md). What to test once it runs:
[IOS_DEVICE_TEST_MATRIX.md](IOS_DEVICE_TEST_MATRIX.md).

> Godot's iOS export produces an **Xcode project**, not an `.ipa`. Compiling, signing and
> installing happen in Xcode (or `xcodebuild`), so **a Mac with Xcode is required**. On Linux the
> script can export and validate the Xcode project only; every later step exits with code 2
> (`BLOCKED`).

## 1. One-time setup on the Mac

| What | Version | Notes |
|---|---|---|
| macOS + Xcode | Xcode 16.4 or newer | Godot 4.5.1's iOS libraries were built with the iOS 18.5 SDK. Open Xcode once and accept the licence; install an iOS Simulator runtime (Xcode → Settings → Components). App Store uploads have their own minimum Xcode/SDK, so check Apple's current requirement before submitting. |
| Godot | **4.5.1-stable** (macOS) | <https://godotengine.org/download/archive/4.5.1-stable/>. Put it at `/Applications/Godot.app`, or point `GODOT` at the binary. |
| Godot export templates | 4.5.1 | In Godot: Editor → Manage Export Templates → Download. The script looks for `ios.zip` in `~/Library/Application Support/Godot/export_templates/4.5.1.stable/`. |
| Node.js | 22 | `npm ci` at the repository root (the build validates the client config with `tsx`). |
| Python 3 | any recent | Used by the export checks. |
| SCons | 4.x | Only for the native module: `pipx install scons` (or `pip3 install scons`). |
| Apple ID | free or paid | Free (Personal Team): simulator plus your own iPhone, with apps expiring after 7 days and **no Universal Links** (Associated Domains needs the paid programme). Paid (Apple Developer Program): everything, including TestFlight. |

```bash
git clone https://github.com/zucc12309/loopfactory- && cd loopfactory-
git checkout claude/ios-readiness
npm ci
export GODOT=/Applications/Godot.app/Contents/MacOS/Godot
"$GODOT" --version        # 4.5.1.stable.official...
```

Your **Team ID**: Xcode → Settings → Accounts → select the team (or developer.apple.com →
Membership). It is 10 characters, for example `AB12CD34EF`. Keep it in your shell, never in git:

```bash
export LF_IOS_TEAM_ID=AB12CD34EF
```

## 2. Simulator (fastest first run)

```bash
# Local API in another terminal (optional; the game plays fully offline):
docker compose up --build                                        # http://127.0.0.1:8080

scripts/build-ios.sh development simulator --native
```

This:
1. checks Godot 4.5.x, the iOS template, Xcode and the iOS SDK;
2. writes and validates `config/client.json` for `development` (API `http://127.0.0.1:8080`,
   which the Simulator reaches as the Mac's localhost);
3. `--native`: clones godot-cpp `godot-4.5-stable`, compiles the LoopFactoryIOS extension for the
   device and the simulator (debug and release), wraps each in `LoopFactoryNative.framework`, and
   creates `LoopFactoryNative.xcframework`;
4. sets the preset (team, bundle id, version, build) for this run only, then exports
   `apps/game/build/ios/development/LoopFactory.xcodeproj`;
5. validates the export with `scripts/ios/check-ios-export.py`;
6. runs `xcodebuild` for the Simulator (unsigned), installs the app on the first available
   iPhone simulator and launches it.

Choose a simulator with `LF_IOS_SIM_DEVICE="iPhone 16"`. Logs are in
`apps/game/build/ios/development/logs/`. To see the game's output:

```bash
xcrun simctl spawn booted log stream --predicate 'process == "LoopFactory"'
```

Without `--native` the app still runs fully. Sharing falls back to "Copy text", links to manual
code entry, and the token stays in the save file. Use it to tell game problems apart from
native-module problems.

## 3. Your iPhone

1. **Enable Developer Mode** (iOS 16+): connect the phone, open the project once in Xcode (below)
   so the device is registered, then on the phone go to Settings → Privacy & Security → Developer
   Mode → On, and restart.
2. Build:
   ```bash
   scripts/build-ios.sh development device --native
   ```
   This uses automatic signing with `LF_IOS_TEAM_ID` (`-allowProvisioningUpdates` creates the
   development profile).
3. Install, either way:
   * **Xcode:** `open apps/game/build/ios/development/LoopFactory.xcodeproj`, select your iPhone
     as the run destination, then Product → Run (⌘R). This is the easiest route and shows the
     console.
   * **Command line:**
     ```bash
     xcrun devicectl list devices
     xcrun devicectl device install app --device <UDID> \
       apps/game/build/ios/development/DerivedData/Build/Products/Debug-iphoneos/LoopFactory.app
     ```
4. With a free Apple ID, the first launch says "Untrusted Developer". Go to Settings → General →
   VPN & Device Management → your Apple ID → Trust.

**The API from a phone:** `127.0.0.1` is the phone itself. Either:
* use your deployed HTTPS API, e.g.
  `LF_API_BASE_URL=https://loopfactory-api.onrender.com scripts/build-ios.sh development device --native`;
  or
* use the Mac on the same Wi-Fi: `LF_API_BASE_URL=http://<your-mac-name>.local:8080`.
  Development builds include `NSAllowsLocalNetworking` and a Local Network prompt text; iOS asks
  for Local Network permission on first use. Staging and production builds contain neither.

## 4. Staging / production builds (paid programme)

```bash
export LF_BUILD=12                       # CFBundleVersion, must increase for every upload
export LF_VERSION_NAME=0.1.0
export LF_API_BASE_URL=https://api.<your-domain>
export LF_PRIVACY_POLICY_URL=https://<your-domain>/privacy
export LF_SUPPORT_URL=https://<your-domain>/support
export LF_APP_LINK_HOST=<host serving /c/ links>   # optional; enables Universal Links
scripts/build-ios.sh staging archive --native
```

The client-config step **refuses** loopback, private, placeholder and non-HTTPS URLs, and writes
nothing when it does. The export check verifies that the packaged config is that validated file
byte for byte, that there is no local-networking exception, and that the associated domain is
exactly `applinks:$LF_APP_LINK_HOST`. `archive` produces an `.xcarchive` and a
development-signed `.ipa` in `build/ios/staging/ipa/`. For TestFlight, open the archive in Xcode
Organizer → Distribute App → App Store Connect.

## 5. Universal Links (paid programme)

1. **API:** set `IOS_APP_IDS=<TEAM_ID>.com.loopfactory.game` (comma-separate several) and
   `PUBLIC_BASE_URL=https://<host>`. Placeholder or malformed IDs stop the API at startup.
   Check:
   ```bash
   curl -si https://<host>/.well-known/apple-app-site-association
   # HTTP/2 200, content-type: application/json, no redirect:
   # {"applinks":{"details":[{"appIDs":["AB12CD34EF.com.loopfactory.game"],"components":[{"/":"/c/*",...}]}]}}
   ```
   Apple fetches it through its CDN. A day or so after deploying, check
   `curl -s https://app-site-association.cdn-apple.com/a/v1/<host>`.
2. **App:** build with `LF_APP_LINK_HOST=<host>` and `--native`. The entitlement
   `com.apple.developer.associated-domains = applinks:<host>` is added, and automatic signing
   enables the Associated Domains capability on the App ID.
3. **Test on the device:** send yourself `https://<host>/c/<CODE>` in Notes or Messages and tap
   it. Typing it into Safari's address bar does **not** open apps. Long-press shows "Open in Loop
   Factory" when the association works. To bypass the CDN while testing, turn on Settings →
   Developer → Associated Domains Development, and temporarily build with the entitlement value
   `applinks:<host>?mode=developer`.
4. If it doesn't open: check the device log for `swcd` messages, the exact Team ID and bundle id,
   that HTTPS has no redirect, and that the app was installed **after** the file was reachable.

## 6. Troubleshooting

| Symptom | Fix |
|---|---|
| `Godot 4.5.x required` | Set `GODOT` to the 4.5.1 binary. The 4.3 editor's iOS template is not the target. |
| `iOS export template missing` | Install the 4.5.1 templates (section 1). |
| `App Store Team ID not specified` | Set `LF_IOS_TEAM_ID`. Export-only runs without it use `UNSIGNED00`, which can't be installed. |
| `client config ... not releasable` | Staging/production need real HTTPS URLs (section 4). |
| Signing: "No profiles for 'com.loopfactory.game'" | A free team cannot always register a bundle id someone else used. Set `LF_IOS_BUNDLE_ID=com.<you>.loopfactory`. The id is not hard-coded anywhere else. |
| Native build: `scons: command not found` | `pipx install scons`. |
| App starts but "Share" is missing | Built without `--native`, or the extension failed to load. Look for `LoopFactoryIOS` in the device log. The game falls back on purpose. |
| Universal Link opens Safari | See section 5, step 4. The game still accepts the code by hand under Friends. |
| `xcodebuild` scheme not found | Open the `.xcodeproj` in Xcode once; the scheme is `LoopFactory` (shared). |

## 7. Files the build touches

The committed `apps/game/config/client.json` and `apps/game/export_presets.cfg` are restored
when the script exits, whatever happens. `apps/game/native/ios/` (the installed extension) exists
only during a `--native` export and is removed afterwards, so desktop and Android builds never
reference it. Build outputs live under `apps/game/build/ios/<env>/` and
`ios/loopfactory-native/{bin,build}`, all git-ignored.
