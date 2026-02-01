# GOAL (task 2026-02-02-0007)

## Objective
監査（Audit）に必要な証跡を、手作業で集めずに 1 コマンドで揃える。
`scripts/04_audit_pack.sh <task-dir>` を追加し、監査パック（AUDIT_PACK.md）を生成できるようにする。

## Done / Acceptance Criteria
- `scripts/04_audit_pack.sh tasks/<id>` が存在する。
- 引数 `<task-dir>` が存在し、かつ `GOAL.md` と `SPEC.md` が存在する場合にのみ動作する（どれか欠けたら exit!=0）。
- 成功時、`<task-dir>/AUDIT_PACK.md` を生成する。
- `AUDIT_PACK.md` には最低限以下を含む（順序固定）:
  1) タイトル（task id / 生成時刻）
  2) `GOAL.md` 全文
  3) `SPEC.md` 全文
  4) （存在すれば）`GATE_REPORT.md` 全文、無ければ「MISSING: GATE_REPORT.md」と明記
  5) `git diff --stat`（対象はHEAD、未コミット差分のみ）
  6) `git diff`（同上、未コミット差分のみ）
- 実行後に作業ツリーが汚れるのは `AUDIT_PACK.md` のみ（それ以外の新規生成物を作らない）。
- `--help` で usage を表示し exit=0。
- 引数が無い/多い場合は usage を stderr に出して exit=2。

## Out of scope
- コミット範囲指定や履歴diff（`HEAD~n..HEAD`）対応は今回やらない。
- 監査の合否判定そのものは行わない（パック生成のみ）。
