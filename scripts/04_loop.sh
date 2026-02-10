#!/usr/bin/env bash
set -euo pipefail

TASK_DIR="${1:-}"
if [[ -z "$TASK_DIR" ]]; then
  echo "usage: scripts/04_loop.sh tasks/<id>" >&2
  exit 2
fi

echo "[0] Task: $TASK_DIR"
echo ""

echo "[1] You (goal): edit $TASK_DIR/GOAL.md"
echo "    - write purpose / deliverable / constraints"
echo ""

echo "[2] Codex + Claude (plan): generate EXECPLAN.md"
echo "    - input:  $TASK_DIR/GOAL.md (+ SELF_CONTEXT if needed)"
echo "    - output: update $TASK_DIR/EXECPLAN.md"
echo ""

echo "[2b] Claude (spec only): generate SPEC.md"
echo "    - input:  $TASK_DIR/GOAL.md"
echo "    - output: overwrite $TASK_DIR/SPEC.md"
echo "    - MUST keep fixed headings from AGENTS.md"
echo ""

echo "[3] CodexCLI (implement): implement based on SPEC.md"
echo "    - MUST NOT edit SPEC.md"
echo "    - commit changes"
echo ""

echo "[4] Gate: run scripts/03_gate.sh"
./scripts/03_gate.sh "$TASK_DIR" || true

echo ""
echo "[Next]"
echo "- If Gate FAIL: fix with Codex and re-run: ./scripts/03_gate.sh $TASK_DIR"
