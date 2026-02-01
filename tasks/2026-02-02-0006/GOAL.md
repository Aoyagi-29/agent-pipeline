# GOAL

## Purpose
`./scripts/01_new_task.sh <task-id>` が「生成物（GATE_REPORT / AUDIT / AUDIT_PACK）を作って作業ツリーを汚す」問題をなくす。
タスク雛形作成直後でも `git status --porcelain` が空（クリーン）であることを保証する。

## Scope
- 対象: `scripts/01_new_task.sh`
- 変更: 新規タスク作成時に生成するファイルを最小化する

## Non-goals
- Gate/Audit の仕様変更はしない
- 既存タスクの中身を改変しない

## Done
- `./scripts/01_new_task.sh 2026-02-02-0006` 実行直後に `git status --porcelain` が空である
- 新規タスク作成で生成されるのは **`GOAL.md` と `SPEC.md` のみ**
- `GATE_REPORT.md` / `AUDIT.md` / `AUDIT_PACK.md` は **作られない**
- 既存のディレクトリがある場合のエラー挙動（exit code/メッセージ）は維持

## Constraints
- WSL bash を正本とする
- ネットワークアクセスなし
- 外部依存追加なし
