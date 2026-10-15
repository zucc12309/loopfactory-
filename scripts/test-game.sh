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
rm -f "$LOG"
exit $STATUS
