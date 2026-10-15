# Performance

Everything below was measured in this repository's cloud development container on 2026-10-15.
That is a shared x86-64 VM with Godot 4.3, the GL Compatibility renderer and Mesa llvmpipe
(software rendering) under Xvfb. **These are not phone measurements.** They only compare code
paths against each other on the same machine.

## Board rendering (CPU work per frame)

Benchmark: `xvfb-run godot --path apps/game --rendering-driver opengl3 -s res://tests_ui/bench_board.gd`.
It measures the board's own `_process` plus all of its draw-command recording, over 120 frames
of a running simulation.

| Board | Before (single immediate-mode `_draw`) | After (per-tile canvas items + signatures) |
|---|---|---|
| c06, 4×4 | p50 2.05 ms · p95 3.49 ms | p50 0.71 ms · p95 1.32 ms |
| c34, 6×7 (largest) | p50 5.26 ms · p95 7.69 ms | p50 1.30 ms · p95 2.31 ms |

What changed (see [game-feel.md](game-feel.md#rendering-architecture-performance)):

* Each tile is a separate CanvasItem whose draw commands are retained by the engine.
* Rotation, press, pop and intro animations are transforms.
* A tile re-records its draw commands only when its appearance signature changes.
* Animated colours and radii are quantised so the `StyleBoxFlat` cache stops churning. In
  steady state the cache adds about 6 new boxes per 120 frames on the largest board.

## Characters (Interdimensional Delivery Crew)

Same benchmark, characters on vs off (classic boxes), two runs each, after the pooled
character-node optimisation:

| Board | Classic: running · idle (p50) | Characters: running · idle (p50) | Characters p95 running |
|---|---|---|---|
| c06, 4×4 | 0.64–0.78 ms · 0.26–0.28 ms | 0.63–0.66 ms · 0.40–0.41 ms | 1.36–1.44 ms |
| c34, 6×7 | 1.28–1.34 ms · 0.52–0.59 ms | 1.05–1.16 ms · 0.79 ms | 2.15–2.17 ms |

How it got there: the first version drew every character every frame in GDScript (c34 running
p50 2.4 ms, p95 up to 4.6 ms; profiled at ≈ 85 µs per character). Characters are now pooled canvas
items moved by transforms and re-recorded only when the face changes, and bodies use cached native
style boxes. While running, characters are slightly cheaper than the classic boxes (which are
redrawn every frame); while idle they cost ≈ 0.25 ms more because the waiting characters in sources
blink and glance (a source re-records only when its face changes).

## Other measurements

* **Rapid input:** 40 taps and undos in one frame converge to the model within 0.4 s, with every
  rotation animation finished (UI test).
* **Startup:** music synthesis runs on a worker thread, so the first frame never waits for audio
  generation. The short sound effects (under 2 s of audio in total) are synthesised on the main
  thread at startup. Startup time itself was not measured separately.
* **Idle:** `low_processor_mode` is on. When nothing animates, no tile re-records commands.
* **Generator:** generating 1,000 small puzzles and running every validity, replay and
  duplicate check takes about 1 s in Node (`packages/engine/test/generator-scale.test.ts`).

## Not measured (needs devices)

* Frame rate on a mid-range Android phone, GPU fill rate, battery drain over a long session.
* Memory over a long session, and recovery after low-memory process death. Save and resume is
  covered by unit tests, but the OS lifecycle on a device isn't.
* Touch latency and haptic feel.

The release checklist in [release-android.md](release-android.md) and
[known-limitations.md](known-limitations.md) lists these as pending device QA.
