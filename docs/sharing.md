# Sharing, friend challenges and replays

## Result card

`apps/game/scripts/ui/share_card.gd` renders a 1080×1350 (4:5) PNG in an off-screen SubViewport.
It shows branding, the date, difficulty, rotations vs par, stars, attempts, and the challenge code
when there is one. **It never shows the solution.** The share sheet previews the card and offers:

* **Share** (only when the native share plugin is in the build): opens the system chooser with
  the image and text — see "Native share sheet" below.
* **Copy text:** a short text result with emoji stars, copied to the clipboard.
* **Save image** (desktop only): writes the PNG to the Pictures folder and shows that path.

On phones without a native module there is no "Save image": the PNG would only land in private app
storage, which the player can't open. On iOS the LoopFactoryIOS extension provides the
`UIActivityViewController` share sheet, which itself offers Save Image (add-only photo access,
purpose string in the iOS preset).

All of this goes through `LFPlatform` (`apps/game/scripts/platform/`), so screens never know
whether they run on Android, iOS or desktop. `scripts/check-platform-refs.py` (CI) fails the build
if shared code reaches around it.

## Friend challenges

```
Player A solves a puzzle ─▶ "Challenge" ─▶ POST /challenges/friend {level ref, moves}
        server re-simulates A's moves ─▶ code ABCD2345 + link <PUBLIC_BASE_URL>/c/ABCD2345
Player B opens the link (landing page) or types the code (Home ▸ Friend code)
        GET /challenges/friend/:code ─▶ puzzle (no solution, no A's moves) + score to beat
B solves (hints off) ─▶ POST /challenges/friend/:code/attempts {moves}
        server re-simulates ─▶ win / tie / lose; best attempt per player kept
GET /challenges/friend/:code/results ─▶ head-to-head table for everyone who played the code
```

* **No account needed to accept:** the client silently uses a guest identity. No sign-up screen
  stands between the link and the puzzle.
* **Server-validated:** the server rebuilds the puzzle from a reference: a campaign id, an
  official daily date, or generator parameters (`seed`, `tier`, `version`, rejected if the
  generator version differs). It never trusts a client-sent board, and every score is
  re-simulated.
* **Codes:** 8 characters from an unambiguous alphabet (no 0/O/1/I/L), so they can be read aloud
  and typed. Generated with `crypto.randomInt`, unique, and valid for 30 days.
* **Privacy:** challenges and attempts are included in the data export and deleted with the
  account (FK cascade). The landing page has no scripts, no trackers and `noindex`.
* **Offline:** creating or opening a challenge needs a connection. The client says so and every
  other mode keeps working. When an attempt can't be verified, the client shows the comparison as
  *unverified*.

### Deep links: what is and isn't configured

| Path | Status |
|---|---|
| Typing the code in the app (Friends) | **Works everywhere** (E2E). Codes are validated (8 characters, unambiguous alphabet) before any request; invalid, expired and offline cases each get their own message; a code entered offline is kept and reopened at the next launch. |
| `https://<domain>/c/CODE` landing page | **Works** once `PUBLIC_BASE_URL` points at the deployed API. Shows the challenge, the code for manual entry, an "Open in the app" link and store links. It says plainly that installing from the store does not carry the link along. |
| `/.well-known/assetlinks.json` | Served by the API once `ANDROID_CERT_SHA256` (and `ANDROID_PACKAGE_NAME`) are set; 404 otherwise. Tested. |
| Android App Links + `loopfactory://challenge/CODE` opening the installed app | **Implemented in source, not built or device-tested.** The intent filters (with `autoVerify`) and `consumeLaunchUri()` live in `android/share-plugin`, which needs the Android SDK + Gradle export. Until that plugin ships, phones type the code. |
| Deferred deep link (install, then open the same puzzle) | **Not possible with App Links alone.** The landing page shows the code; manual entry is the supported path. |
| `--challenge=CODE` launch argument | Works on desktop. |
| `/.well-known/apple-app-site-association` (+ `/apple-app-site-association`) | Served by the API as `application/json` once `IOS_APP_IDS` (`<TEAM_ID>.<bundle id>`) is set; 404 otherwise; placeholder team IDs are refused at startup. Tested. |
| iOS Universal Links opening the installed app | **Implemented in source, not built or device-tested.** The `LoopFactoryIOS` extension registers with Godot 4.5's app delegate (`GDTApplicationDelegate +addService:`) and receives `continueUserActivity`. The entitlement `applinks:<LF_APP_LINK_HOST>` is added by `scripts/build-ios.sh`. Needs a paid Apple team, the deployed AASA file and a real device ([IOS_BUILD_RUNBOOK.md](IOS_BUILD_RUNBOOK.md) §5). |
| Links while the app is running (both platforms) | `main.gd` routes a link delivered while the game runs: the iOS signal, plus a check on every resume (covers Android App Links reaching a running activity). Same link → reopened, not stacked; consecutive links → latest wins; invalid → plain message; offline → code kept. Simulated in `tests_ui/ios_ui_tests.gd`. |

### Native share sheet

`LFShare` (scripts/core/share.gd) uses the `LoopFactoryShare` Android plugin when present: the image
is copied to the app cache, exposed through a FileProvider `content://` URI with a temporary
read-permission grant, and handed to the system chooser with the text. Behaviour per target app
(WhatsApp, Instagram, …) depends on what each accepts and has **not** been verified on a device.
Without the plugin (this build): phones offer **Copy text** only — the image is never "saved" into
private app storage and presented as if the player could open it; desktop saves to Pictures.
Analytics record only what is observable (see [analytics.md](analytics.md)).

## Replays

Each completion stores the best solution as a deterministic replay in local progress:
`progress[key].replay = {v, levelId, contentVersion, moves, rotations[, level]}`. Generated
puzzles embed their level. A new replay replaces the stored one only when it is strictly better.
The Replay screen:

1. Starts from the level's start rotations.
2. Applies each rotation with a highlight, 0.32 s apart.
3. Runs the real simulation and plays the celebration.

If content changed and the replay no longer solves the level, the screen says so.

**Clean view** hides all controls, leaving a portrait frame with only the board and a caption.
This is suitable for screen recording (OS recorder). **The game does not export video itself.**
That would need a platform recording API, which has not been implemented or tested. Automatic
zoom on key moments is also not implemented.
