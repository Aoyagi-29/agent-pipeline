# SPEC

## Scope

`scripts/03_gate.sh` に `--require-clean-tree` オプションを追加する。このオプションが指定された場合、Gate 判定の前に `git status --porcelain` で作業ツリーの状態を検査し、未コミット差分があれば即座に失敗する。既存の `./scripts/03_gate.sh <task-dir>` の挙動は一切変更しない。

対象ファイル: `scripts/03_gate.sh`（既存スクリプトへの機能追加）

## Acceptance Criteria

| # | 条件 | 検証方法 |
|---|---|---|
| AC-1 | `./scripts/03_gate.sh <task-dir>` の既存動作が変わらない | TP-1 |
| AC-2 | `--require-clean-tree` 指定時、`git status --porcelain` の出力が空でなければ stderr にエラーを出し exit 1 | TP-2 |
| AC-3 | `--require-clean-tree` 指定時、作業ツリーがクリーンなら従来の Gate 判定を実行する | TP-3 |
| AC-4 | 引数不正 / パス不在 / git repo 外は exit 2 | TP-4〜TP-8 |
| AC-5 | shebang は `#!/usr/bin/env bash`、先頭で `set -euo pipefail` | コード目視 |
| AC-6 | ネットワークアクセスなし、外部依存追加なし | コード目視 |

## Interfaces

### CLI Synopsis

```
scripts/03_gate.sh [OPTIONS] <task-dir>
```

### Positional Arguments

| 引数 | 必須 | 説明 |
|---|---|---|
| `<task-dir>` | Yes | タスクディレクトリへの相対パスまたは絶対パス |

### Options

| オプション | 説明 |
|---|---|
| （なし） | legacy モード。既存動作を維持 |
| `--require-clean-tree` | Gate 判定前に作業ツリーのクリーン性を検査する |

### 引数制約

- 許容する引数構成は（オプション最大1つ）+ `<task-dir>` の合計2トークンまで。これを超える場合は stderr に `"Error: invalid arguments"` を出力し exit 2。
- 未知のオプション（`--` で始まる未定義フラグ）は stderr に `"Error: unknown option: <flag>"` を出力し exit 2。

### stdout / stderr

| チャネル | 用途 |
|---|---|
| stdout | 正常動作時のログ・進捗出力（既存踏襲） |
| stderr | エラーメッセージのみ |

### `--require-clean-tree` の動作フロー

1. 共通バリデーション（Error Handling 参照）を実行する。
2. `git status --porcelain` を実行する。
3. 出力が空でない場合 → stderr に `"Error: working tree is not clean"` を出力し exit 1。
4. 出力が空の場合 → 従来の Gate 判定ロジックをそのまま実行する。Gate 判定結果の exit code をそのまま返す。

## Error Handling

以下を全モード共通で Gate 判定前に検証する。いずれか失敗で即 exit 2。検証順序はこの番号順。

| # | 条件 | stderr メッセージ | exit |
|---|---|---|---|
| 0 | 引数トークン数が上限（2）を超えている | `"Error: invalid arguments"` | 2 |
| 1 | `<task-dir>` が未指定 | `"Error: <task-dir> is required"` | 2 |
| 2 | `<task-dir>` が存在するディレクトリでない | `"Error: directory not found: <task-dir>"` | 2 |
| 3 | cwd が git リポジトリ内でない（`git rev-parse --show-toplevel` 失敗） | `"Error: not inside a git repository: <cwdの実パス>"` | 2 |

`--require-clean-tree` 固有のエラー:

| 条件 | stderr メッセージ | exit |
|---|---|---|
| `git status --porcelain` の出力が空でない | `"Error: working tree is not clean"` | 1 |

exit 1 と exit 2 の使い分け: 作業ツリーが汚い状態は「Gate 不合格」と同等の扱い（exit 1）。引数やパスの問題は「使い方の誤り」（exit 2）。

## Security/Safety Constraints

| # | 制約 |
|---|---|
| 1 | shebang は `#!/usr/bin/env bash` |
| 2 | スクリプト先頭で `set -euo pipefail` |
| 3 | ネットワークアクセス禁止。curl/wget/nc 等を新規追加しない |
| 4 | 外部依存（apt/brew/pip 等）を新規追加しない。bash 組み込み + coreutils + git のみ |
| 5 | 既存コードの非オプション部分への変更は最小限にとどめる |
| 6 | ファイルの削除・書き込みを新たに追加しない（本タスクのスコープ外） |

## Test Plan

テストはリポジトリルート（`/mnt/c/work/agent-pipeline` 等）で実行する前提。

### TP-1: legacy モード後方互換

```bash
TASK_DIR="tasks/2026-02-02-0005"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

./scripts/03_gate.sh "$TASK_DIR"
EXIT=$?

# exit 0 or 1（2 ではない）
[ "$EXIT" -eq 0 ] || [ "$EXIT" -eq 1 ]
echo "TP-1: PASS (exit=$EXIT)"
```

### TP-2: --require-clean-tree で作業ツリーが汚い → exit 1

```bash
TASK_DIR="tasks/2026-02-02-0005"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

# Setup: 作業ツリーを汚す
echo "dirty" > __tp2_dirty_file__
trap 'rm -f __tp2_dirty_file__' EXIT

# Exec
./scripts/03_gate.sh --require-clean-tree "$TASK_DIR" 2>tp2_stderr.txt
EXIT=$?

# Verify: exit 1
[ "$EXIT" -eq 1 ] || { echo "TP-2: FAIL (expected exit 1, got $EXIT)"; exit 1; }

# Verify: stderr に "not clean" が含まれる
grep -q "not clean" tp2_stderr.txt || { echo "TP-2: FAIL (stderr missing message)"; exit 1; }

# Cleanup
rm -f __tp2_dirty_file__ tp2_stderr.txt
trap - EXIT
echo "TP-2: PASS"
```

### TP-3: --require-clean-tree で作業ツリーがクリーン → Gate 判定実行

```bash
TASK_DIR="tasks/2026-02-02-0005"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

# Precondition: 作業ツリーがクリーンであること
if [ -n "$(git status --porcelain)" ]; then
  echo "SKIP: working tree is not clean (commit or stash first)"
  exit 0
fi

# Exec
./scripts/03_gate.sh --require-clean-tree "$TASK_DIR"
EXIT=$?

# Verify: exit 0 or 1（Gate 判定結果。2 ではない）
[ "$EXIT" -eq 0 ] || [ "$EXIT" -eq 1 ]
echo "TP-3: PASS (exit=$EXIT)"
```

### TP-4: 引数なし → exit 2

```bash
./scripts/03_gate.sh 2>/dev/null
[ $? -eq 2 ] && echo "TP-4: PASS" || echo "TP-4: FAIL"
```

### TP-5: 存在しないディレクトリ → exit 2

```bash
./scripts/03_gate.sh /nonexistent/path 2>/dev/null
[ $? -eq 2 ] && echo "TP-5: PASS" || echo "TP-5: FAIL"
```

### TP-6: 未知オプション → exit 2

```bash
TASK_DIR="tasks/2026-02-02-0005"
[ -d "$TASK_DIR" ] || { echo "SKIP"; exit 0; }

./scripts/03_gate.sh --unknown "$TASK_DIR" 2>/dev/null
[ $? -eq 2 ] && echo "TP-6: PASS" || echo "TP-6: FAIL"
```

### TP-7: 余剰引数 → exit 2

```bash
TASK_DIR="tasks/2026-02-02-0005"
[ -d "$TASK_DIR" ] || { echo "SKIP"; exit 0; }

./scripts/03_gate.sh --require-clean-tree "$TASK_DIR" extra 2>/dev/null
[ $? -eq 2 ] && echo "TP-7: PASS" || echo "TP-7: FAIL"
```

### TP-8: stderr にエラーメッセージが出力されること

```bash
ERR=$(./scripts/03_gate.sh 2>&1 1>/dev/null)
echo "$ERR" | grep -q "Error:" && echo "TP-8: PASS" || echo "TP-8: FAIL"
```
