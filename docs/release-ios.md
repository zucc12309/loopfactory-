# iOS readiness

**Status: prepared, not built.** iOS builds require macOS with Xcode and an Apple Developer
account; neither was available, so **no iOS build has been produced or tested**.

What is ready:
* `export_presets.cfg` → preset `iOS`: bundle id `com.loopfactory.game`, iOS 14+, arm64,
  icons, storyboard background, privacy manifest entries (gameplay content and product
  interaction, not linked to identity, no tracking).
* Engine and UI are platform-neutral (GL Compatibility renderer → Metal via MoltenVK/ANGLE in
  Godot 4.3; touch input via emulated mouse; safe-area margins).
* Backend supports **Sign in with Apple** (`APPLE_BUNDLE_IDS`) and the App Store purchase
  verifier slot (pending credentials).
* Haptics use `Input.vibrate_handheld`, which works on iOS.

Steps on a Mac:
1. Install Xcode (current), Godot 4.3 + export templates.
2. Fill `application/app_store_team_id` and code-signing identities in the iOS preset.
3. Export → Xcode project; open in Xcode, set signing, run on a device.
4. Add Sign in with Apple capability and a StoreKit plugin when enabling linking/purchases
   (App Store rule: an app offering third-party login must also offer Sign in with Apple).
5. TestFlight internal testing with the same checklist as Android.
