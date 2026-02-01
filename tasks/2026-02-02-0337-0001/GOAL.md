# GOAL (task 2026-02-02-0337-0001)

## Objective
MVP入口（One-command entry）のSSOTを確定する。
`scripts/00_run_task.sh <task-dir>` を追加し、タスク1本を「1コマンド」で回せるようにする。

## Background
現状は人間が複数コマンドを順に実行しており、手順ブレが発生しうる。
すでに `scripts/05_run_audit.sh` は Gate(--clean)→AuditPack→status を実行できるが、
プロジェクトとしての「入口（SSOT）」が未確定。

## Done Criteria (Acceptance)
AC-1. 新規スクリプト `scripts/00_run_task.sh` を追加する（このファイル名で固定）。
AC-2. `./scripts/00_run_task.sh <task-dir>` の形式で実行できる。
AC-3. `00_run_task.sh` は内部で `./scripts/05_run_audit.sh <task-dir>` を呼び出し、完走させる。
AC-4. `-h/--help` で usage と実行例を stdout に表示して exit 0。
AC-5. 引数不正（引数なし、余剰、未知オプション）は stderr に usage を出し exit 2。
AC-6. `<task-dir>` が存在するディレクトリでない場合は stderr に明示エラーを出し exit 2。
AC-7. `AUDIT_PACK.md` は引き続き **git管理しない（ignoreのまま）**。ポリシーを壊さない。
AC-8. `00_run_task.sh` 自身はネットワークアクセスしない。外部依存追加なし（bash + coreutils + git）。
AC-9. 既存 `scripts/03_gate.sh` / `scripts/04_audit_pack.sh` / `scripts/05_run_audit.sh` を変更しない。

## Non-goals
- GOAL→SPEC生成、差し戻しテンプレ生成などを00に統合しない（今回は入口固定のみ）。
- 監査の合否判定を自動化しない。

## Notes
- 仕様SSOTは `tasks/2026-02-02-0337-0001/SPEC.md`
- CodexはSPEC.md編集禁止（触ったらFAIL思想）
