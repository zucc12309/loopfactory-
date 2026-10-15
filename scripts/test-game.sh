#!/usr/bin/env bash
# Runs the Godot test-suite headless. Fails on test failures AND on any GDScript runtime error
# (Godot keeps running after script errors, so the log is scanned too).
set -uo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/../apps/game"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
LOG=$(mktemp)
"$GODOT" --headless --path . -s res://tests/run_tests.gd 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
if grep -E "SCRIPT ERROR|Parse Error" "$LOG" >/dev/null; then
  echo "::error::GDScript errors detected during tests"
  STATUS=1
fi
# Scene-level UI tests (layout on five aspect ratios, rapid taps, failure/celebration flow). They
# need real font metrics, so they use the GL renderer under a virtual display when available.
if command -v xvfb-run >/dev/null 2>&1; then
  UI_CMD=(xvfb-run -a "$GODOT" --path . --rendering-driver opengl3 -s res://tests_ui/ui_tests.gd)
else
  echo "xvfb-run not found: running UI tests headless (font metrics differ; layout checks are conservative)"
  UI_CMD=("$GODOT" --headless --path . -s res://tests_ui/ui_tests.gd)
fi
timeout 300 "${UI_CMD[@]}" 2>&1 | tee "$LOG"
UI_STATUS=${PIPESTATUS[0]}
if grep -E "SCRIPT ERROR|Parse Error" "$LOG" >/dev/null; then
  echo "::error::GDScript errors detected during UI tests"
  UI_STATUS=1
fi
[ "$UI_STATUS" -ne 0 ] && STATUS=1
rm -f "$LOG"
exit $STATUS
