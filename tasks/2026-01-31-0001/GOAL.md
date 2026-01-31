# Goal

## Purpose
- Claudeに貼る「SPEC生成プロンプト」を自動生成するスクリプト（scripts/02_make_spec_prompt.sh）を追加し、指定taskのGOAL.mdを読み込んでプロンプト全文をstdoutに出せるようにする

## Deliverable
- scripts/02_make_spec_prompt.sh が存在し、実行可能（chmod +x）
- ./scripts/02_make_spec_prompt.sh tasks/2026-01-31-0001 が「Claudeに貼れるプロンプト全文」をstdoutに出力する
- 引数なし／不正パス／GOAL.md不在は stderr にエラーを出し exit code 2
- 正常時は exit code 0
- 出力は空にならない（最低限テンプレは必ず出る）

## Constraints
- Must:
  - bash正本（#!/usr/bin/env bash + set -euo pipefail）
  - 既存ファイルは壊さない（GOAL.md は読むだけ）
  - 出力は人間がそのままClaudeに貼れる形式
- Must not:
  - Claude/Codex/LLM APIの実行（このスクリプトは「プロンプト生成のみ」）
  - ネットワークアクセスや外部依存を増やす
  - eval/sourceの使用
  - 既存ファイルへの書き込み（read-only）
- Out of scope:
  - Claude出力を自動でSPEC.mdに書き込む
  - 複数タスクの一括処理
  - 多言語対応
