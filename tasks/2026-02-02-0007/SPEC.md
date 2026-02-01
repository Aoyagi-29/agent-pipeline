# SPEC

## Scope

新規スクリプト `scripts/04_audit_pack.sh` を作成する。指定されたタスクディレクトリ内の証跡（GOAL.md / SPEC.md / GATE_REPORT.md / 未コミット差分）を収集し、`AUDIT_PACK.md` として1ファイルに結合出力する。監査の合否判定は行わない。コミット範囲指定（`HEAD~n..HEAD`）は対象外。

対象ファイル: `scripts/04_audit_pack.sh`（新規作成）

## Acceptance Criteria

| # | 条件 | 検証方法 |
|---|---|---|
| AC-1 | `scripts/04_audit_pack.sh` が実行可能ファイルとして存在する | TP-1 |
| AC-2 | `<task-dir>` に `GOAL.md` と `SPEC.md` が両方存在する場合のみ正常動作する | TP-2, TP-6 |
| AC-3 | 成功時 `<task-dir>/AUDIT_PACK.md` を生成する | TP-2 |
| AC-4 | `AUDIT_PACK.md` に必須6セクションが順序どおり含まれる | TP-3 |
| AC-5 | `GATE_REPORT.md` が存在しない場合は `MISSING: GATE_REPORT.md` と明記される | TP-4 |
| AC-6 | 実行後に作業ツリーに増えるファイルは `AUDIT_PACK.md` のみ | TP-5 |
| AC-7 | `--help` で usage を表示し exit 0 | TP-7 |
| AC-8 | 引数不正時は stderr に usage を出し exit 2 | TP-8, TP-9 |

## Interfaces

### CLI Synopsis

```
scripts/04_audit_pack.sh [--help] <task-dir>
```

### Positional Arguments

| 引数 | 必須 | 説明 |
|---|---|---|
| `<task-dir>` | Yes（`--help` 以外） | タスクディレクトリへの相対パスまたは絶対パス |

### Options

| オプション | 説明 |
|---|---|
| `--help` | usage を stdout に表示し exit 0。他の引数と併用不可 |

### 引数制約

- `--help` 単独、または `<task-dir>` 単独の最大1トークンのみ許容する。これを超える場合（余剰引数）は stderr に usage を出力し exit 2。
- 未知のオプション（`--` で始まる `--help` 以外のフラグ）は stderr に usage を出力し exit 2。

### stdout / stderr

| チャネル | 用途 |
|---|---|
| stdout | `--help` 時の usage 表示。正常動作時の進捗ログ |
| stderr | エラーメッセージおよび異常時の usage 表示 |

### 生成物

成功時に `<task-dir>/AUDIT_PACK.md` を生成する。それ以外のファイルは一切生成しない。既存の `AUDIT_PACK.md` がある場合は上書きする。

### AUDIT_PACK.md のフォーマット

以下の6セクションをこの順序で出力する。各セクションは Markdown 見出し（`#` または `##`）で区切る。

| # | セクション | 内容 |
|---|---|---|
| 1 | タイトル | `# AUDIT_PACK: <task-id>` + 生成時刻（ISO 8601 形式、例: `2026-02-02T12:34:56+09:00`）。`<task-id>` は `<task-dir>` のベースネーム |
| 2 | GOAL.md | `## GOAL.md` 見出し + `<task-dir>/GOAL.md` の全文 |
| 3 | SPEC.md | `## SPEC.md` 見出し + `<task-dir>/SPEC.md` の全文 |
| 4 | GATE_REPORT.md | `## GATE_REPORT.md` 見出し + `<task-dir>/GATE_REPORT.md` の全文。ファイルが存在しない場合は `MISSING: GATE_REPORT.md` と記載 |
| 5 | git diff --stat | `## git diff --stat` 見出し + `git diff --stat HEAD` の出力をコードブロックで囲む。出力が空の場合は `(no uncommitted changes)` と記載 |
| 6 | git diff | `## git diff` 見出し + `git diff HEAD` の出力をコードブロックで囲む。出力が空の場合は `(no uncommitted changes)` と記載 |

## Error Handling

検証順序はこの番号順。いずれか失敗で即座に該当 exit code で終了する。

| # | 条件 | stderr メッセージ | exit |
|---|---|---|---|
| 0 | 引数が0個（`--help` でもない） | usage を表示 | 2 |
| 1 | 引数が2個以上 | usage を表示 | 2 |
| 2 | 未知のオプション（`--` 始まりで `--help` 以外） | usage を表示 | 2 |
| 3 | `<task-dir>` が存在するディレクトリでない | `"Error: directory not found: <task-dir>"` | 2 |
| 4 | cwd が git リポジトリ内でない（`git rev-parse --show-toplevel` 失敗） | `"Error: not inside a git repository: <cwd の実パス>"` | 2 |
| 5 | `<task-dir>/GOAL.md` が存在しない | `"Error: GOAL.md not found in <task-dir>"` | 1 |
| 6 | `<task-dir>/SPEC.md` が存在しない | `"Error: SPEC.md not found in <task-dir>"` | 1 |

exit code の使い分け: 引数・パス・環境の問題は exit 2（使い方の誤り）。必須ファイル欠損は exit 1（実行条件未達）。

## Security/Safety Constraints

| # | 制約 |
|---|---|
| 1 | shebang は `#!/usr/bin/env bash` |
| 2 | スクリプト先頭で `set -euo pipefail` |
| 3 | ネットワークアクセス禁止。curl/wget/nc 等を使用しない |
| 4 | 外部依存追加禁止。bash 組み込み + coreutils + git + date のみ |
| 5 | `AUDIT_PACK.md` 以外のファイルを生成・変更・削除しない |
| 6 | `git diff` は `HEAD` との未コミット差分のみ。リモート通信を伴うコマンドを使用しない |
| 7 | WSL bash を正本とする |

## Test Plan

テストはリポジトリルートで実行する前提。

### TP-1: スクリプトが存在し実行可能である

```bash
[ -x ./scripts/04_audit_pack.sh ] && echo "TP-1: PASS" || echo "TP-1: FAIL"
```

### TP-2: 正常実行で AUDIT_PACK.md が生成される

```bash
TASK_DIR="tasks/2026-02-02-0007"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }
[ -f "$TASK_DIR/GOAL.md" ] || { echo "SKIP: GOAL.md missing"; exit 0; }
[ -f "$TASK_DIR/SPEC.md" ] || { echo "SKIP: SPEC.md missing"; exit 0; }

# Cleanup prior run
rm -f "$TASK_DIR/AUDIT_PACK.md"

# Exec
./scripts/04_audit_pack.sh "$TASK_DIR"
EXIT=$?

[ "$EXIT" -eq 0 ] || { echo "TP-2: FAIL (exit=$EXIT)"; exit 1; }
[ -f "$TASK_DIR/AUDIT_PACK.md" ] || { echo "TP-2: FAIL (AUDIT_PACK.md not created)"; exit 1; }

echo "TP-2: PASS"
```

### TP-3: AUDIT_PACK.md に必須6セクションが順序どおり含まれる

```bash
TASK_DIR="tasks/2026-02-02-0007"
PACK="$TASK_DIR/AUDIT_PACK.md"
[ -f "$PACK" ] || { echo "SKIP: run TP-2 first"; exit 0; }

# Verify: 各セクション見出しが存在し、出現順序が正しい
LINE_TITLE=$(grep -n "^# AUDIT_PACK:" "$PACK" | head -1 | cut -d: -f1)
LINE_GOAL=$(grep -n "^## GOAL.md" "$PACK" | head -1 | cut -d: -f1)
LINE_SPEC=$(grep -n "^## SPEC.md" "$PACK" | head -1 | cut -d: -f1)
LINE_GATE=$(grep -n "^## GATE_REPORT.md" "$PACK" | head -1 | cut -d: -f1)
LINE_STAT=$(grep -n "^## git diff --stat" "$PACK" | head -1 | cut -d: -f1)
LINE_DIFF=$(grep -n "^## git diff$" "$PACK" | head -1 | cut -d: -f1)

# All must exist
for VAR in LINE_TITLE LINE_GOAL LINE_SPEC LINE_GATE LINE_STAT LINE_DIFF; do
  [ -n "${!VAR}" ] || { echo "TP-3: FAIL ($VAR missing)"; exit 1; }
done

# Order must be ascending
[ "$LINE_TITLE" -lt "$LINE_GOAL" ] && \
[ "$LINE_GOAL" -lt "$LINE_SPEC" ] && \
[ "$LINE_SPEC" -lt "$LINE_GATE" ] && \
[ "$LINE_GATE" -lt "$LINE_STAT" ] && \
[ "$LINE_STAT" -lt "$LINE_DIFF" ] || { echo "TP-3: FAIL (wrong order)"; exit 1; }

echo "TP-3: PASS"
```

### TP-4: GATE_REPORT.md が存在しない場合に MISSING と記載される

```bash
TASK_DIR="tasks/2026-02-02-0007"
[ -d "$TASK_DIR" ] || { echo "SKIP"; exit 0; }

# Setup: GATE_REPORT.md を一時的に退避
BACKUP=""
if [ -f "$TASK_DIR/GATE_REPORT.md" ]; then
  BACKUP=$(mktemp)
  mv "$TASK_DIR/GATE_REPORT.md" "$BACKUP"
fi

rm -f "$TASK_DIR/AUDIT_PACK.md"
./scripts/04_audit_pack.sh "$TASK_DIR"

# Verify
grep -q "MISSING: GATE_REPORT.md" "$TASK_DIR/AUDIT_PACK.md" || { echo "TP-4: FAIL (MISSING not found)"; }

# Restore
if [ -n "$BACKUP" ]; then
  mv "$BACKUP" "$TASK_DIR/GATE_REPORT.md"
fi
rm -f "$TASK_DIR/AUDIT_PACK.md"

echo "TP-4: PASS"
```

### TP-5: 実行後に増えるファイルは AUDIT_PACK.md のみ

```bash
TASK_DIR="tasks/2026-02-02-0007"
[ -d "$TASK_DIR" ] || { echo "SKIP"; exit 0; }

rm -f "$TASK_DIR/AUDIT_PACK.md"

# Snapshot before
BEFORE=$(git status --porcelain)

# Exec
./scripts/04_audit_pack.sh "$TASK_DIR"

# Snapshot after
AFTER=$(git status --porcelain)

# Diff should only show AUDIT_PACK.md
DIFF=$(diff <(echo "$BEFORE") <(echo "$AFTER") || true)
LINES=$(echo "$DIFF" | grep "^>" | grep -v "AUDIT_PACK.md" || true)

[ -z "$LINES" ] || { echo "TP-5: FAIL (unexpected files: $LINES)"; rm -f "$TASK_DIR/AUDIT_PACK.md"; exit 1; }

rm -f "$TASK_DIR/AUDIT_PACK.md"
echo "TP-5: PASS"
```

### TP-6: GOAL.md または SPEC.md が無い → exit 1

```bash
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

# Case A: GOAL.md のみ（SPEC.md なし）
echo "# GOAL" > "$TEST_DIR/GOAL.md"
./scripts/04_audit_pack.sh "$TEST_DIR" 2>/dev/null
[ $? -eq 1 ] || { echo "TP-6a: FAIL"; exit 1; }
echo "TP-6a: PASS"

# Case B: SPEC.md のみ（GOAL.md なし）
rm "$TEST_DIR/GOAL.md"
echo "# SPEC" > "$TEST_DIR/SPEC.md"
./scripts/04_audit_pack.sh "$TEST_DIR" 2>/dev/null
[ $? -eq 1 ] || { echo "TP-6b: FAIL"; exit 1; }
echo "TP-6b: PASS"
```

### TP-7: --help → usage 表示、exit 0

```bash
./scripts/04_audit_pack.sh --help >/dev/null 2>&1
[ $? -eq 0 ] && echo "TP-7: PASS" || echo "TP-7: FAIL"
```

### TP-8: 引数なし → exit 2

```bash
./scripts/04_audit_pack.sh 2>/dev/null
[ $? -eq 2 ] && echo "TP-8: PASS" || echo "TP-8: FAIL"
```

### TP-9: 余剰引数 → exit 2

```bash
TASK_DIR="tasks/2026-02-02-0007"
[ -d "$TASK_DIR" ] || { echo "SKIP"; exit 0; }

./scripts/04_audit_pack.sh "$TASK_DIR" extra 2>/dev/null
[ $? -eq 2 ] && echo "TP-9: PASS" || echo "TP-9: FAIL"
```

### TP-10: 存在しないディレクトリ → exit 2

```bash
./scripts/04_audit_pack.sh /nonexistent/path 2>/dev/null
[ $? -eq 2 ] && echo "TP-10: PASS" || echo "TP-10: FAIL"
```
