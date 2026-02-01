# GOAL

scripts/03_gate.sh に「作業ツリーがクリーンでない場合はFAILする」モードを追加する。

## Background

Gate実行により生成物（GATE_REPORT.md等）が残ったり、未コミット差分がある状態で混乱する事故が起きやすい。
Gate自身が「クリーンな状態でのみ判定できる」ことを機械的に保証したい。

## Requirements

- 対象: scripts/03_gate.sh
- 後方互換:
  - `./scripts/03_gate.sh <task-dir>` の従来挙動は維持する
- 新規オプション:
  - `./scripts/03_gate.sh --require-clean-tree <task-dir>`
    - Gate判定の前に `git status --porcelain` を確認する
    - 出力が空でない場合は stderr にエラーを出し exit 1
    - 出力が空の場合のみ従来のGate判定を実行する
- 例外運用は入れない（最初は厳格にする）
- 引数不正 / パス不在 / git repo外は stderr にエラー、exit 2
- bash: `#!/usr/bin/env bash` と `set -euo pipefail`
- 外部依存追加禁止、ネットワーク禁止

## Done

- `--require-clean-tree` が実装され、クリーンでない場合に exit 1 で止まる
- 後方互換の動作が壊れていない
- `./scripts/03_gate.sh --require-clean-tree tasks/2026-02-02-0005` を含む簡単な動作確認手順を SPEC に書ける状態
