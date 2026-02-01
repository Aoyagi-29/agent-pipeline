# Goal

## Purpose
- 監査（Audit）に必要な情報（SPEC / Gate Report / git diff）を手作業で集めず、1発で揃える。
- Audit→差し戻し判断がブレないよう、監査入力を毎回同じフォーマットに固定する。

## Deliverable
- scripts/04_audit_pack.sh が存在し、実行可能（chmod +x）
- ./scripts/04_audit_pack.sh <task-dir> が <task-dir>/AUDIT_PACK.md を生成する
- AUDIT_PACK.md には少なくとも以下を含む：
  - <task-dir>/SPEC.md の全文
  - Gate Report（scripts/03_gate.sh <task-dir> 実行で生成される <task-dir>/GATE_REPORT.md の内容）
  - git diff --stat の結果
  - git diff の結果
- 引数なし／不正パス／SPEC.md不在は stderr にエラーを出し exit code 2
- 正常時は exit code 0
- 出力は空にならない（最低限テンプレは必ず出る）

## Constraints
- Must:
  - bash正本（#!/usr/bin/env bash + set -euo pipefail）
  - 既存ファイルは壊さない（SPEC.md/GOAL.md は読むだけ）
  - ネットワークアクセスや外部依存を増やさない
- Must not:
  - Claude/Codex/LLM APIの実行（監査パック生成のみ）
  - eval/source の使用
  - tasks配下の既存ファイルへの書き込み（例外：<task-dir>/AUDIT_PACK.md と Gateが生成する <task-dir>/GATE_REPORT.md のみ）
- Out of scope:
  - 複数タスクの一括処理
  - 多言語対応
