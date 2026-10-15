# Offline-first persistence and synchronisation

The game never waits for the network. Everything is saved locally first; the server is a backup,
a way to move between devices and the authority for competitive results.

## Local persistence (`LFSaveStore`, `LFGameState`)

* `user://save.json` holds an envelope `{schema, checksum: sha256(payload), payload}`.
* Writes: temp file → previous file kept as `.bak` → atomic rename. Loads verify the checksum and
  fall back `main → tmp → bak → defaults`; corrupt files are kept as `*.corrupt`. Covered by
  `apps/game/tests/test_save.gd` (truncation, bad checksum, crash between write and rename).
* Autosave after every rotation/undo/reset/hint/completion (coalesced per frame) and on
  pause/background/close notifications.
* The active puzzle stores the level, current rotations and the full move history. On load the
  history is replayed from the start and must reproduce the saved rotations — otherwise the active
  puzzle is discarded rather than trusted. A simulation is never persisted: an interruption during
  a run resumes on the last editable board.
* Schema migrations: `LFSaveStore.migrate()`; new default fields are merged in on load.

## Operation queue

Every change that matters to the server becomes an operation:

```json
{ "opId": "uuid-v4", "type": "level_complete|settings|active_puzzle|daily_submit",
  "payload": {}, "clientTs": 1760000000000, "attempts": 0, "nextAttemptAt": 0 }
```

* Settings and active-puzzle snapshots are **coalesced** (newer replaces the queued older one).
* Failed uploads back off exponentially (2 s × 2ⁿ, max 1 h). The queue is bounded (500).
* The player ID is never client-chosen: the first sync creates a server guest account and the
  client stores its refresh token.

## Sync round (`Net.sync()`)

1. Authenticate (refresh token rotation, or create a guest).
2. Upload due operations (`POST /progress/sync`, ≤100 per call; daily submissions go to
   `POST /challenges/daily/submit`).
3. Server deduplicates by `(player, opId)` — retries return `duplicate` and are never applied twice
   (tested with concurrent identical requests).
4. Server applies each op in its own transaction together with its `sync_operations` row.
5. The response contains a full snapshot which the client merges.

## Conflict-resolution domains

| Domain | Rule |
|---|---|
| Level completions | **Monotonic.** Union of both sides; best rotations = min. Never removed by sync. |
| Verification | A replay-verified completion replaces an unverified one; unverified results are clamped to ≥ par and never ranked. |
| Settings | Last-writer-wins on the client `updatedAt` (stale devices cannot overwrite newer settings). |
| Active puzzle | Last-writer-wins on `updatedAt`; adopted by a client only if it has no active puzzle. |
| Counters (dailies, endless) | max(local, server). Campaign/perfect are recomputed from progress. |
| Achievements | Union. |
| Daily results | Submitted as replays; the server's verified best is authoritative for ranking. |

## Reinstall / new device

Guest data lives only on the device until the player links Google/Apple. After linking, a new
install creates a guest, calls `POST /auth/link` with `onConflict: "switch"`, receives the original
account's tokens and merges its snapshot. (Linking requires the native sign-in plugins — see
`docs/known-limitations.md`.)
