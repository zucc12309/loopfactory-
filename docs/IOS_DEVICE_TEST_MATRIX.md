# iPhone test matrix

How to build and install: [IOS_BUILD_RUNBOOK.md](IOS_BUILD_RUNBOOK.md). Status and evidence:
[IOS_READINESS.md](IOS_READINESS.md).

## Evidence levels

Every row says exactly which of these it has. Nothing moves to **Sim** or **Device** without a
person running it and recording the build, device and date in the results log at the bottom.

| Code | Meaning |
|---|---|
| **Auto** | Verified by automated tests only (desktop Godot, simulated iOS geometry/events, fakes, or the host-compiled native binding layer). |
| **Sim** | Tested on the iOS Simulator. |
| **Device** | Tested on a physical iPhone. |
| **—** | Not tested. |

**Current state (2026-10-15): no Simulator or iPhone run has happened.** No Mac was available. Every
row is **Auto** or **—**.

## Devices

| Device | Why | iOS | Status |
|---|---|---|---|
| iPhone 15 / 16 (Dynamic Island, 6.1") | Main target; top inset 59 pt | latest public iOS | — |
| iPhone 13 mini or SE (3rd gen) | Small screen; SE has a home button and no inset | an older supported iOS | — |
| iPhone 16 Pro Max (6.9") | Largest, top inset 62 pt | latest | — |
| Oldest supported | Minimum deployment target is iOS **15.0** | iOS 15.x (iPhone 6s or later) | — |
| Simulators | iPhone SE (3rd gen), iPhone 16, iPhone 16 Pro Max | Xcode's current runtime | — |

The four geometries above (pixels and safe-area insets) are simulated in
`tests_ui/ios_ui_tests.gd`. That covers layout maths, not real rendering.

## Test cases

### A. Install, launch, render

| # | Case | Steps | Expect | Auto | Sim | Device |
|---|---|---|---|---|---|---|
| A1 | Install and launch | `scripts/build-ios.sh development simulator` / `device` | Splash then Home, no crash; console shows `Godot Engine v4.5.1` | Export validated (26 checks) | — | — |
| A2 | Renderer | Look at the board, belts and Crew | Same visuals as Android (GL Compatibility → OpenGL ES 3 on iOS) | — | — | — |
| A3 | Icon and name | Home screen | "Loop Factory", opaque icon, no black corners | Icon opaque (export check) | — | — |
| A4 | Launch screen | Cold start | Cream storyboard background, no white flash | Storyboard colour in preset | — | — |
| A5 | Portrait lock | Rotate the phone | Stays portrait | Info.plist portrait-only | — | — |

### B. Layout and input

| # | Case | Expect | Auto | Sim | Device |
|---|---|---|---|---|---|
| B1 | Dynamic Island / notch | No button, field or scroll area under it on any screen | ios_ui_tests: 4 geometries × 8 screens (mutation-checked) | — | — |
| B2 | Home indicator | Bottom controls (Run/Undo, Reset) clear of it; home swipe needs a second swipe (`hide_home_indicator`) | Same suite | — | — |
| B3 | Tap to rotate | Clockwise turn on tap, responsive | beta_ui_tests (desktop pointer events) | — | — |
| B4 | Long-press reverse rotation | Counter-clockwise; ↺ toggle as alternative | beta_ui_tests | — | — |
| B5 | Drag / scroll lists | Levels, Daily and Crew scroll smoothly; no accidental rotations while scrolling | — | — | — |
| B6 | Keyboard | Friends → code field: keyboard opens, field stays visible, Return submits | — | — | — |
| B7 | Profile name field | Keyboard, edit, save | — | — | — |
| B8 | Modals | Consent card, share card and win overlay centred, buttons reachable | UI suites (desktop) | — | — |
| B9 | Text | No clipping or overflow; fonts crisp at 3× | ui_tests on 5 aspect ratios, ios_ui_tests overflow check | — | — |
| B10 | Reduced motion | iOS Settings → Accessibility → Motion → Reduce Motion **before first launch** → game starts with reduced motion; toggling it in the game afterwards wins | ios_ui_tests (fake native value) | — | — |

### C. Gameplay parity (identical rules on both platforms)

| # | Case | Expect | Auto | Sim | Device |
|---|---|---|---|---|---|
| C1 | All 36 curated levels | Solvable, same par, same stars as Android | Engine parity fixtures (TS ↔ GDScript), Godot unit suite | — | — |
| C2 | Hints | Same hints as Android | Godot unit + beta_ui_tests | — | — |
| C3 | Undo / reset | Exact | beta_ui_tests | — | — |
| C4 | Daily challenge | Same date puzzle as Android on the same day | API + E2E | — | — |
| C5 | Crew animations and cosmetics | Play, unlock and equip as on Android | crew_ui_tests | — | — |

### D. Lifecycle, audio, memory

| # | Case | Steps | Expect | Auto | Sim | Device |
|---|---|---|---|---|---|---|
| D1 | Background / resume | Mid-puzzle → home swipe → wait 1 min → reopen | Same board, same moves | Pause saves immediately (ios_ui_tests) | — | — |
| D2 | Killed in background | Background → swipe the app away in the switcher → reopen | Progress kept up to the last move | Same | — | — |
| D3 | Terminate during save | Background immediately after a move | Save intact (`.tmp`/`.bak` recovery) | Save-store corruption tests | — | — |
| D4 | Silent switch | Switch on silent → play | **No sound** (Ambient session), haptics still on if enabled | Project setting only | — | — |
| D5 | Other audio | Music app playing → open game | Your music keeps playing, mixed with game sounds | Project setting only | — | — |
| D6 | Audio interruption | Phone call or Siri mid-game → end it | Game audio resumes; game paused state sane | — | — | — |
| D7 | Memory warning | Simulator: Debug → Simulate Memory Warning | State saved; `memory_warning` diagnostic; no crash | ios_ui_tests | — | — |
| D8 | 30-minute session | Play continuously | No growing memory (Xcode → Debug Navigator), stable frame rate, phone not hot | — | — | — |

### E. Storage, identity, network

| # | Case | Steps | Expect | Auto | Sim | Device |
|---|---|---|---|---|---|---|
| E1 | Progress persists | Clear 3 levels → force-quit → reopen | Progress kept | Save-store tests | — | — |
| E2 | Token in Keychain | `--native` build, go online once, then inspect the save (Xcode → Devices → Download Container) | `save.json` has `refreshTokenStore: "keychain"` and **no** `refreshToken` value | platform_tests + native binding tests (host) | — | — |
| E3 | Reinstall | Delete the app → reinstall | **New guest, progress gone** (this is expected; no account recovery is shipped). Nothing claims otherwise | platform_tests (stale Keychain token deleted) | — | — |
| E4 | Offline play | Airplane mode → play several levels → reconnect | Everything playable offline; queued results sync within ~1 min online | E2E (desktop) | — | — |
| E5 | Wi-Fi ↔ cellular | Switch networks mid-sync | No duplicate scores; sync resumes | Auth/sync suites | — | — |
| E6 | HTTPS API | Staging build against the deployed API | Guest created, daily loads, leaderboard loads | API + E2E (desktop) | — | — |
| E7 | Server errors | Stop the API / return 5xx | Game stays playable; no identity replaced on transient errors | auth_tests | — | — |
| E8 | Delete my data | Settings → Delete | Server deletion, local wipe, Keychain token removed | analytics_tests + platform_tests | — | — |

### F. Native sharing (`--native` builds)

| # | Case | Expect | Auto | Sim | Device |
|---|---|---|---|---|---|
| F1 | Share result image | Win → Share: iOS share sheet with the card image and text | Adapter contract (fake + host binary) | — | — |
| F2 | Messages / Mail / WhatsApp | The recipient app receives the image and/or text. **Record per app**; never assume | — | — | — |
| F3 | Save Image | Share sheet → Save Image → first time asks for **add-only** photo access with our text; image appears in Photos | Purpose string present (export check) | — | — |
| F4 | Cancel | Close the sheet | Back in the game; `share_sheet_closed{result: cancelled}` | Host binding test | — | — |
| F5 | Challenge invite | Create challenge → Send invite | Text with code and https link | — | — | — |
| F6 | Copy fallback | Build without `--native` | "Copy text" / "Copy invite" work; no Share button | beta_ui_tests | — | — |
| F7 | iPad popover | Only if iPad support is ever enabled (currently iPhone-only) | No crash; sheet anchored bottom-centre | — | — | — |
| F8 | Data export | Settings → Export my data | Share sheet with a JSON file → Save to Files works | — | — | — |

### G. Universal Links (paid team + deployed AASA + `--native`)

| # | Case | Expect | Auto | Sim | Device |
|---|---|---|---|---|---|
| G1 | AASA served | `curl -si https://<host>/.well-known/apple-app-site-association` → 200 JSON, no redirect | API tests | — | — |
| G2 | App closed | Tap `https://<host>/c/<CODE>` in Notes → app launches into that challenge | Routing (simulated) | — | — |
| G3 | App backgrounded | Same, app in background → opens challenge on resume | Routing (simulated) | — | — |
| G4 | App in foreground | Tap a link from a notification / Messages while playing → challenge screen | Routing (simulated) | — | — |
| G5 | Same link twice | Reopens, no stacked screens | Routing (simulated) | — | — |
| G6 | Two different links | The latest one is shown | Routing (simulated) + host binding test | — | — |
| G7 | Offline | Link while offline → "You're offline… we saved the code" and reopens next online launch | Routing (simulated) | — | — |
| G8 | Invalid code | "That link isn't a Loop Factory challenge…" | Routing (simulated) | — | — |
| G9 | App not installed | Landing page with the code for manual entry | API landing-page test | — | — |

### H. Privacy and permissions

| # | Case | Expect | Auto | Sim | Device |
|---|---|---|---|---|---|
| H1 | No unexpected prompts | Fresh install, full play-through: **no** camera, microphone, photo-read, tracking or notification prompts. Only add-to-Photos when Save Image is chosen, plus Local Network on development builds pointed at a LAN server | Purpose strings and entitlements checked | — | — |
| H2 | Analytics consent | Nothing sent before opting in; the consent card appears after the first completed puzzle | analytics_tests | — | — |
| H3 | Privacy manifest | `PrivacyInfo.xcprivacy` in the app bundle, tracking false | Export check | — | — |

## Results log

| Date | Build (env, version, build no., commit) | Device / Simulator, iOS | Rows | Result | Tester |
|---|---|---|---|---|---|
| — | — | — | — | No runs yet | — |
