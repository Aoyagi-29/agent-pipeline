## Codex運用ルール（Build役）

- Codexは「実装・テスト・コミット」まで担当する。
- Codexは `tasks/<id>/SPEC.md` を編集しない（編集したら即FAIL）。
- Codexは `git push` を実行しない（ネットワーク/DNS差異で不安定なため）。
- `git push` は人間が WSL bash（/mnt/c/work/agent-pipeline）から実行する。
- Codexが生成した `tasks/<id>/GATE_REPORT.md` / `AUDIT.md` が未追跡で邪魔なら、push前に人間が削除する（必要なら別タスクで自動化）。

## Cursor Cloud specific instructions

This repo is a bash + Python (stdlib-only) agent-orchestration pipeline. There is no package manager, build system, or automated test suite. Runtime deps are just `bash`, `python3`, `git`, `jq` (all preinstalled). The startup update script runs `git config core.fileMode false` + `chmod +x scripts/*.sh`.

- Exec bits: scripts are tracked as `100644` (non-executable) but invoke each other by path (e.g. `"${SCRIPT_DIR}/03_gate.sh"`), which fails with "Permission denied" on a real Linux filesystem. The developers run on a WSL/Windows mount where exec bits are always effectively on, hiding this. The update script makes them executable; `core.fileMode false` keeps the tree clean so the mode change never shows as a diff — do not commit an exec-bit change.
- Lint/test: `scripts/03_gate.sh <task-dir>` is the closest thing to lint/test. Its Node/Python test+lint sections only fire if `package.json` or `pyproject.toml` exist (they don't here), so the gate effectively validates git cleanliness and reports PASS/FAIL to `GATE_REPORT.md`.
- Run (no API keys needed): `bash scripts/06_smoke.sh <task-dir>`, `bash scripts/03_gate.sh <task-dir>` (legacy gate, keeps `GATE_REPORT.md`), `bash scripts/04_audit_pack.sh <task-dir>`, and `bash scripts/05_run_audit.sh <task-dir>` (gate `--clean` + audit pack; requires a clean committed tree). `bash scripts/01_new_task.sh <id>` scaffolds a task.
- Gotcha: `scripts/00_run_task.sh <task-dir>` (default mode) writes `RUN_SUMMARY.md` itself and then runs the gate in `--clean` mode, so it fails on the resulting untracked summary. Use the individual scripts above (or the `--auto` path) instead of the default `00_run_task.sh` for a clean run.
- Requires secrets/CLIs (not available by default): the `--auto` plan/implement/self-improve flow needs the `claude` and `codex` CLIs plus `ANTHROPIC_API_KEY`/`OPENAI_API_KEY`; `CHANGE_SUMMARY.md` generation needs `USE_CHATGPT_API=1` + `OPENAI_API_KEY`. Without these, the scripts degrade gracefully (skip/warn) rather than crash.
- Generated files: `GATE_REPORT.md`, `AUDIT_PACK.md`, `AUDIT.md`, `BUILD_REPORT.md` are gitignored; `RUN_SUMMARY.md` and `CHANGE_SUMMARY.md` are not, so they can dirty the tree.
