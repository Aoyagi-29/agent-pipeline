# SPEC

## Scope

`scripts/01_new_task.sh` を修正し、新規タスク作成時に生成するファイルを `GOAL.md` と `SPEC.md` のみに限定する。現状生成されている `GATE_REPORT.md` / `AUDIT.md` / `AUDIT_PACK.md` は作成しない。これにより、タスク作成直後の `git status --porcelain` が空（作業ツリーがクリーン）であることを保証する。

対象ファイル: `scripts/01_new_task.sh`

変更しないもの: Gate / Audit の仕様、既存タスクディレクトリの中身。

## Acceptance Criteria

| # | 条件 | 検証方法 |
|---|---|---|
| AC-1 | `./scripts/01_new_task.sh <task-id>` 実行後、`tasks/<task-id>/` に `GOAL.md` が存在する | TP-1 |
| AC-2 | `./scripts/01_new_task.sh <task-id>` 実行後、`tasks/<task-id>/` に `SPEC.md` が存在する | TP-1 |
| AC-3 | `./scripts/01_new_task.sh <task-id>` 実行後、`GATE_REPORT.md` / `AUDIT.md` / `AUDIT_PACK.md` が存在しない | TP-1 |
| AC-4 | タスク作成後に `git add` + `git commit` し、直後の `git status --porcelain` が空である | TP-2 |
| AC-5 | 既存ディレクトリを指定した場合のエラー挙動（exit code・メッセージ）が従来と同一 | TP-3 |
| AC-6 | 生成される `GOAL.md` / `SPEC.md` の中身が雛形として妥当（空ファイルでない） | TP-4 |

## Interfaces

### CLI Synopsis

```
scripts/01_new_task.sh <task-id>
```

### Positional Arguments

| 引数 | 必須 | 説明 |
|---|---|---|
| `<task-id>` | Yes | タスクID（例: `2026-02-02-0006`）。`tasks/<task-id>/` ディレクトリが作成される |

### 生成物（変更後）

| ファイル | 生成する | 備考 |
|---|---|---|
| `tasks/<task-id>/GOAL.md` | Yes | 雛形。既存と同等の内容 |
| `tasks/<task-id>/SPEC.md` | Yes | 雛形。既存と同等の内容 |
| `tasks/<task-id>/GATE_REPORT.md` | **No（削除）** | 生成コードを除去する |
| `tasks/<task-id>/AUDIT.md` | **No（削除）** | 生成コードを除去する |
| `tasks/<task-id>/AUDIT_PACK.md` | **No（削除）** | 生成コードを除去する |

### stdout / stderr

| チャネル | 用途 |
|---|---|
| stdout | 作成完了メッセージ（既存踏襲） |
| stderr | エラーメッセージのみ |

## Error Handling

既存のエラー挙動を維持する。変更は行わない。

| 条件 | 期待動作 | exit |
|---|---|---|
| `<task-id>` 未指定 | stderr にエラーメッセージ | 既存の exit code を維持 |
| `tasks/<task-id>/` が既に存在する | stderr にエラーメッセージ | 既存の exit code を維持 |
| cwd が git リポジトリ外 | stderr にエラーメッセージ | 既存の exit code を維持 |

実装者への注意: 既存スクリプトのエラーハンドリング部分は変更しない。変更するのは「生成物の作成」部分のみ。

## Security/Safety Constraints

| # | 制約 |
|---|---|
| 1 | shebang は `#!/usr/bin/env bash` |
| 2 | スクリプト先頭で `set -euo pipefail` |
| 3 | ネットワークアクセス禁止 |
| 4 | 外部依存追加禁止。bash 組み込み + coreutils + git のみ |
| 5 | 既存タスクディレクトリの中身を改変しない |
| 6 | エラーハンドリングのコードパスは変更しない |
| 7 | WSL bash を正本とする |

## Test Plan

テストはリポジトリルートで実行する前提。テスト用タスクIDには衝突しない値を使う。

### TP-1: 生成物が GOAL.md と SPEC.md のみであること

```bash
TEST_ID="9999-99-99-tp01"
TASK_DIR="tasks/$TEST_ID"

# Precondition
[ ! -d "$TASK_DIR" ] || { echo "FAIL: $TASK_DIR already exists"; exit 1; }

# Exec
./scripts/01_new_task.sh "$TEST_ID"
EXIT=$?

# Verify: exit 0
[ "$EXIT" -eq 0 ] || { echo "TP-1: FAIL (exit=$EXIT)"; rm -rf "$TASK_DIR"; exit 1; }

# Verify: GOAL.md と SPEC.md が存在する
[ -f "$TASK_DIR/GOAL.md" ] || { echo "TP-1: FAIL (GOAL.md missing)"; rm -rf "$TASK_DIR"; exit 1; }
[ -f "$TASK_DIR/SPEC.md" ] || { echo "TP-1: FAIL (SPEC.md missing)"; rm -rf "$TASK_DIR"; exit 1; }

# Verify: GATE_REPORT.md / AUDIT.md / AUDIT_PACK.md が存在しない
[ ! -f "$TASK_DIR/GATE_REPORT.md" ] || { echo "TP-1: FAIL (GATE_REPORT.md exists)"; rm -rf "$TASK_DIR"; exit 1; }
[ ! -f "$TASK_DIR/AUDIT.md" ] || { echo "TP-1: FAIL (AUDIT.md exists)"; rm -rf "$TASK_DIR"; exit 1; }
[ ! -f "$TASK_DIR/AUDIT_PACK.md" ] || { echo "TP-1: FAIL (AUDIT_PACK.md exists)"; rm -rf "$TASK_DIR"; exit 1; }

# Cleanup
rm -rf "$TASK_DIR"
echo "TP-1: PASS"
```

### TP-2: タスク作成 → commit 後に git status がクリーン

```bash
TEST_ID="9999-99-99-tp02"
TASK_DIR="tasks/$TEST_ID"

# Precondition: 作業ツリーがクリーン
if [ -n "$(git status --porcelain)" ]; then
  echo "SKIP: working tree is not clean"
  exit 0
fi

# Exec
./scripts/01_new_task.sh "$TEST_ID"

# Add & commit
git add "$TASK_DIR"
git commit -m "test: TP-2 temp task $TEST_ID"

# Verify: git status --porcelain が空
STATUS=$(git status --porcelain)
if [ -n "$STATUS" ]; then
  echo "TP-2: FAIL (working tree not clean after commit)"
  echo "$STATUS"
  git revert --no-edit HEAD
  exit 1
fi

# Cleanup: コミットを巻き戻す
git revert --no-edit HEAD >/dev/null 2>&1
rm -rf "$TASK_DIR"
git add -A && git commit -m "test: TP-2 cleanup" >/dev/null 2>&1

echo "TP-2: PASS"
```

### TP-3: 既存ディレクトリを指定 → エラー（既存挙動維持）

```bash
TEST_ID="9999-99-99-tp03"
TASK_DIR="tasks/$TEST_ID"

# Setup: ディレクトリを先に作る
mkdir -p "$TASK_DIR"

# Exec
./scripts/01_new_task.sh "$TEST_ID" 2>tp3_stderr.txt
EXIT=$?

# Verify: exit 0 以外（既存のエラー挙動）
[ "$EXIT" -ne 0 ] || { echo "TP-3: FAIL (expected error, got exit 0)"; rm -rf "$TASK_DIR" tp3_stderr.txt; exit 1; }

# Verify: stderr にメッセージがある
[ -s tp3_stderr.txt ] || { echo "TP-3: FAIL (no stderr output)"; rm -rf "$TASK_DIR" tp3_stderr.txt; exit 1; }

# Cleanup
rm -rf "$TASK_DIR" tp3_stderr.txt
echo "TP-3: PASS"
```

### TP-4: 生成される雛形が空ファイルでない

```bash
TEST_ID="9999-99-99-tp04"
TASK_DIR="tasks/$TEST_ID"

# Exec
./scripts/01_new_task.sh "$TEST_ID"

# Verify: GOAL.md が1バイト以上
[ -s "$TASK_DIR/GOAL.md" ] || { echo "TP-4: FAIL (GOAL.md is empty)"; rm -rf "$TASK_DIR"; exit 1; }

# Verify: SPEC.md が1バイト以上
[ -s "$TASK_DIR/SPEC.md" ] || { echo "TP-4: FAIL (SPEC.md is empty)"; rm -rf "$TASK_DIR"; exit 1; }

# Cleanup
rm -rf "$TASK_DIR"
echo "TP-4: PASS"
```

### TP-5: task-id 未指定 → エラー

```bash
./scripts/01_new_task.sh 2>/dev/null
[ $? -ne 0 ] && echo "TP-5: PASS" || echo "TP-5: FAIL"
```
