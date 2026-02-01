# GOAL (task 2026-02-02-0239-0001)

## Objective
Gate → AuditPack → Clean を「1コマンド」で実行できるようにし、運用手順を固定する。
（目的：人間の手順ブレ削減、監査の再現性向上、作業ツリー汚染の防止）

## Background
現状は以下を手動で順に実行している：
- ./scripts/03_gate.sh --clean <task-dir>
- ./scripts/04_audit_pack.sh <task-dir>
- （必要に応じて）後片付け / 状態確認

これを 1コマンド化し、標準手順として定義する。

## Done Criteria (Acceptance)
AC-1. 新しいスクリプト `scripts/05_run_audit.sh` を追加する（名前はこの通り）。
AC-2. 実行形式は次のいずれかを満たす：
  - `./scripts/05_run_audit.sh <task-dir>`
  - もしくは `./scripts/05_run_audit.sh --task <task-dir>`
  ※どちらか一つに統一してよい（SPECで固定する）。
AC-3. `05_run_audit.sh` は内部で次を順に実行する：
  1) `./scripts/03_gate.sh --clean <task-dir>`
  2) `./scripts/04_audit_pack.sh <task-dir>`
  3) 実行後に `git status --porcelain` を表示する（証跡用）
AC-4. `03_gate.sh` が非0で終了した場合：
  - `04_audit_pack.sh` は実行しない
  - `05_run_audit.sh` も同じ終了コードで終了する
AC-5. `04_audit_pack.sh` が非0で終了した場合：
  - `05_run_audit.sh` も非0で終了する
AC-6. `05_run_audit.sh` は「貼る場所：WSL bash / repo直下」を前提に壊れない（相対パスで動く）。
AC-7. ヘルプ表示（`-h` または `--help`）を実装し、使い方と例を表示する。
AC-8. 副作用（生成物）は既存方針を壊さない：
  - `AUDIT_PACK.md` は引き続き `.gitignore` 管理（コミット不要）
  - `--clean` 実行により、必要なら生成物が消えることは許容（ログに出る）
AC-9. 既存スクリプト（03,04）の仕様SSOTを変更しない（必要なら 05 側で吸収する）。

## Non-goals
- 監査の合否判定（PASS/FAIL）を自動化しない
- 03/04 の大規模改修はしない（05でラップする）

## Notes
- SPECのSSOTは tasks/2026-02-02-0239-0001/SPEC.md
- CodexはSPEC.md編集禁止（触ったらFAIL思想）
