# SPEC

## Scope

新規スクリプト `scripts/00_run_task.sh` を作成する。タスク1本を「1コマンド」で回すための SSOT エントリポイントであり、内部で `scripts/05_run_audit.sh <task-dir>` を呼び出すラッパーである。既存スクリプト（03, 04, 05）のコード・仕様は変更しない。

対象ファイル: `scripts/00_run_task.sh`（新規作成）

## Acceptance Criteria

| # | 条件 | 検証方法 |
|---|---|---|
| AC-1 | `scripts/00_run_task.sh` が実行可能ファイルとして存在する | TP-1 |
| AC-2 | `./scripts/00_run_task.sh <task-dir>` の形式で実行できる | TP-2 |
| AC-3 | 内部で `./scripts/05_run_audit.sh <task-dir>` を呼び出し、完走させる | TP-2, TP-3 |
| AC-4 | `-h` または `--help` で usage と実行例を stdout に表示し exit 0 | TP-4 |
| AC-5 | 引数不正（なし / 余剰 / 未知オプション）は stderr に usage を出し exit 2 | TP-5, TP-6, TP-7 |
| AC-6 | `<task-dir>` が存在するディレクトリでない場合は stderr にエラーを出し exit 2 | TP-8 |
| AC-7 | `AUDIT_PACK.md` の .gitignore ポリシーを壊さない（00 自身が .gitignore を変更しない） | コード目視 |
| AC-8 | ネットワークアクセスなし。外部依存追加なし | コード目視 |
| AC-9 | 既存スクリプト（03, 04, 05）を変更しない | コード目視 |

## Interfaces

### CLI Synopsis

```
scripts/00_run_task.sh [-h|--help] <task-dir>
```

### Positional Arguments

| 引数 | 必須 | 説明 |
|---|---|---|
| `<task-dir>` | Yes（`-h`/`--help` 以外） | タスクディレクトリへの相対パスまたは絶対パス |

### Options

| オプション | 説明 |
|---|---|
| `-h`, `--help` | usage と実行例を stdout に表示し exit 0 |

### 引数制約

- `-h` / `--help` 単独、または `<task-dir>` 単独の最大1トークンのみ許容する。これを超える場合は stderr に usage を出力し exit 2。
- 未知のオプション（`-` で始まる `-h` / `--help` 以外のフラグ）は stderr に usage を出力し exit 2。

### stdout / stderr

| チャネル | 用途 |
|---|---|
| stdout | 進捗ログ、子スクリプト（05）の stdout、`--help` 時の usage |
| stderr | エラーメッセージ、子スクリプト（05）の stderr |

### 実行フロー

```
1. バリデーション（Error Handling 参照）
2. stdout に "=== 00_run_task: <task-dir> ===" を出力
3. ./scripts/05_run_audit.sh <task-dir> を実行
   - 非0 → 同じ exit code で終了
4. stdout に "=== 00_run_task: done ===" を出力
5. exit 0
```

### 子スクリプトの呼び出しパス

子スクリプトは `00_run_task.sh` 自身のディレクトリからの相対パスで解決する:

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"${SCRIPT_DIR}/05_run_audit.sh" "$TASK_DIR"
```

### usage 表示内容（`-h` / `--help`）

最低限以下を含むこと:

```
Usage: 00_run_task.sh <task-dir>

Run the full task pipeline (Gate → AuditPack → Status).

Example:
  ./scripts/00_run_task.sh tasks/2026-02-02-0337-0001
```

## Error Handling

00 自身のバリデーション（子スクリプト呼び出し前に実行）。検証順序はこの番号順。

| # | 条件 | stderr メッセージ | exit |
|---|---|---|---|
| 0 | 引数が0個（`-h`/`--help` でもない） | usage を表示 | 2 |
| 1 | 引数が2個以上 | usage を表示 | 2 |
| 2 | 未知のオプション（`-` 始まりで `-h`/`--help` 以外） | usage を表示 | 2 |
| 3 | `<task-dir>` が存在するディレクトリでない | `"Error: directory not found: <task-dir>"` | 2 |

子スクリプト実行時のエラー伝播:

| 条件 | 動作 |
|---|---|
| `05_run_audit.sh` が非0で終了 | stderr に `"Error: run_audit failed (exit=<N>)"` を出力。00 の exit code = 05 の exit code |

## Security/Safety Constraints

| # | 制約 |
|---|---|
| 1 | shebang は `#!/usr/bin/env bash` |
| 2 | スクリプト先頭で `set -euo pipefail` |
| 3 | ネットワークアクセス禁止 |
| 4 | 外部依存追加禁止。bash 組み込み + coreutils + git のみ |
| 5 | 既存スクリプト（03, 04, 05）のコード・仕様を変更しない |
| 6 | `00_run_task.sh` 自身はファイルを生成・削除しない（副作用は子スクリプト経由のみ） |
| 7 | `.gitignore` を変更しない（AUDIT_PACK.md の ignore ポリシーを維持） |
| 8 | WSL bash を正本とする |

## Test Plan

テストはリポジトリルートで実行する前提。

### TP-1: スクリプトが存在し実行可能である

```bash
[ -x ./scripts/00_run_task.sh ] && echo "TP-1: PASS" || echo "TP-1: FAIL"
```

### TP-2: 正常実行（05_run_audit.sh が呼ばれる）

```bash
TASK_DIR="tasks/2026-02-02-0337-0001"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

./scripts/00_run_task.sh "$TASK_DIR"
EXIT=$?

# exit 0 or 1（Gate結果による）。2 ではない
[ "$EXIT" -eq 0 ] || [ "$EXIT" -eq 1 ]
echo "TP-2: DONE (exit=$EXIT)"
```

### TP-3: 05_run_audit.sh のステップ見出しが出力に含まれる

```bash
TASK_DIR="tasks/2026-02-02-0337-0001"
[ -d "$TASK_DIR" ] || { echo "SKIP"; exit 0; }

OUTPUT=$(./scripts/00_run_task.sh "$TASK_DIR" 2>/dev/null || true)

# 05_run_audit.sh のステップ見出しが透過される
echo "$OUTPUT" | grep -q "Step 1/3" || { echo "TP-3: FAIL (05 step headers missing)"; exit 1; }

# 00 自身の見出し
echo "$OUTPUT" | grep -q "00_run_task:" || { echo "TP-3: FAIL (00 header missing)"; exit 1; }

echo "TP-3: PASS"
```

### TP-4: -h / --help → usage 表示、exit 0

```bash
./scripts/00_run_task.sh --help >/dev/null 2>&1
[ $? -eq 0 ] || { echo "TP-4a: FAIL"; exit 1; }

./scripts/00_run_task.sh -h >/dev/null 2>&1
[ $? -eq 0 ] || { echo "TP-4b: FAIL"; exit 1; }

# usage にスクリプト名と Example が含まれること
./scripts/00_run_task.sh --help | grep -q "00_run_task.sh" || { echo "TP-4c: FAIL"; exit 1; }
./scripts/00_run_task.sh --help | grep -qi "example" || { echo "TP-4d: FAIL"; exit 1; }

echo "TP-4: PASS"
```

### TP-5: 引数なし → exit 2

```bash
./scripts/00_run_task.sh 2>/dev/null
[ $? -eq 2 ] && echo "TP-5: PASS" || echo "TP-5: FAIL"
```

### TP-6: 余剰引数 → exit 2

```bash
TASK_DIR="tasks/2026-02-02-0337-0001"
[ -d "$TASK_DIR" ] || { echo "SKIP"; exit 0; }

./scripts/00_run_task.sh "$TASK_DIR" extra 2>/dev/null
[ $? -eq 2 ] && echo "TP-6: PASS" || echo "TP-6: FAIL"
```

### TP-7: 未知オプション → exit 2

```bash
./scripts/00_run_task.sh --unknown 2>/dev/null
[ $? -eq 2 ] && echo "TP-7: PASS" || echo "TP-7: FAIL"
```

### TP-8: 存在しないディレクトリ → exit 2

```bash
./scripts/00_run_task.sh /nonexistent/path 2>/dev/null
[ $? -eq 2 ] && echo "TP-8: PASS" || echo "TP-8: FAIL"
```

### TP-9: 05_run_audit.sh が失敗 → 00 も非0で終了

```bash
TASK_DIR=$(mktemp -d)
trap "rm -rf $TASK_DIR" EXIT

# 空ディレクトリ → 05 内部の 03_gate.sh が失敗するはず
./scripts/00_run_task.sh "$TASK_DIR" 2>/dev/null
EXIT=$?

[ "$EXIT" -ne 0 ] || { echo "TP-9: FAIL (expected non-zero)"; exit 1; }
echo "TP-9: PASS"
```
