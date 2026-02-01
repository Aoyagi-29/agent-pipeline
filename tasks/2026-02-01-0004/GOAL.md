# Goal

## Purpose
- Gate実行で毎回生成されるログ/監査生成物（例: GATE_REPORT.md, AUDIT_PACK.md）を、手でrmしなくてもクリーン化できるようにする。
- 「Gate→確認→クリーン→次工程」の運用をワンコマンドで事故なく回せるようにする。

## Deliverable
- scripts/03_gate.sh に clean 機能が追加される。
- 追加されたインターフェースは以下を満たす：
  - ./scripts/03_gate.sh <task-dir> は従来通り動作（後方互換）
  - ./scripts/03_gate.sh --clean <task-dir> は Gate判定を実行し、その後に生成物を削除して作業ツリーをクリーンに戻す
  - ./scripts/03_gate.sh --clean-only <task-dir> は Gateを実行せず、生成物だけ削除する（任意だが推奨）
- clean対象（最低限）：
  - <task-dir>/GATE_REPORT.md
  - <task-dir>/AUDIT_PACK.md
  - <task-dir>/AUDIT.md（存在する場合）
- 削除は rm -f で安全に行い、対象以外は絶対に消さない
- 引数不正 / パス不在 / git repo外は stderr にエラーを出して exit 2
- 正常時は exit 0（GateがFAILでもレポート生成ができていれば従来通りの挙動）

## Constraints
- Must:
  - bash正本（#!/usr/bin/env bash + set -euo pipefail）
  - 既存インターフェースの後方互換を守る
  - tasks/<id>/GOAL.md と SPEC.md は編集禁止（Gate内のSSOT保護思想は維持）
- Must not:
  - 外部依存追加、ネットワークアクセス
  - tasks配下の対象外ファイル削除
