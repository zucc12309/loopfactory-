# Sharing, friend challenges and replays

## Result card

`apps/game/scripts/ui/share_card.gd` renders a 1080×1350 (4:5) PNG in an off-screen SubViewport.
It shows branding, the date, difficulty, rotations vs par, stars, attempts, and the challenge code
when there is one. **It never shows the solution.** The share sheet previews the card and offers:

* **Copy text:** a short text result with emoji stars, copied to the clipboard.
* **Save image:** writes the PNG to `user://share/` (and to the Pictures folder on desktop),
  then copies the text.

`LFShareCard.native_share(text, png)` is the integration boundary for a native share sheet. It
calls an Engine singleton `LoopFactoryShare` when one is present. **No such plugin ships today**,
so on Android and iOS the image stays in app storage and only the text reaches the clipboard. A
native share sheet needs a small Android plugin (`ACTION_SEND` with a FileProvider URI) and an iOS
plugin (`UIActivityViewController`).

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
| Typing the code in the app | **Works everywhere** (covered by the E2E test). |
| `https://<domain>/c/CODE` landing page | **Works** once `PUBLIC_BASE_URL` points at the deployed API. Shows the challenge, the code, an app link and store links (`PLAY_STORE_URL`, `APP_STORE_URL`). |
| `loopfactory://challenge/CODE` and `--challenge=CODE` | Parsed by `main.launch_challenge_code()`. Works on desktop as a command-line argument. |
| Android App Links / iOS Universal Links opening the app directly | **Not configured.** These need an intent filter in a Gradle-based Android export, `assetlinks.json` and `apple-app-site-association` on the production domain, plus a plugin to read the launch URL. That URL never reaches `OS.get_cmdline_args()` on mobile. Until then the landing page tells players to type the code. |

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
