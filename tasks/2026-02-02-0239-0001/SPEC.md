# SPEC

## Scope

新規スクリプト `scripts/05_run_audit.sh` を作成する。Gate 判定（＋クリーン）→ AuditPack 生成 → 状態表示を1コマンドで順に実行するラッパーである。内部で `scripts/03_gate.sh --clean` と `scripts/04_audit_pack.sh` を呼び出す。既存スクリプト（03, 04）の仕様・コードは変更しない。

対象ファイル: `scripts/05_run_audit.sh`（新規作成）

## Acceptance Criteria

| # | 条件 | 検証方法 |
|---|---|---|
| AC-1 | `scripts/05_run_audit.sh` が実行可能ファイルとして存在する | TP-1 |
| AC-2 | `./scripts/05_run_audit.sh <task-dir>` の形式で実行できる | TP-2 |
| AC-3 | 内部で (1) `03_gate.sh --clean <task-dir>` → (2) `04_audit_pack.sh <task-dir>` → (3) `git status --porcelain` を順に実行する | TP-2, TP-3 |
| AC-4 | `03_gate.sh` が非0で終了した場合、`04_audit_pack.sh` を実行せず同じ exit code で終了する | TP-4 |
| AC-5 | `04_audit_pack.sh` が非0で終了した場合、`05_run_audit.sh` も非0で終了する | TP-5 |
| AC-6 | 相対パスで動作する（リポジトリルートから実行する前提） | TP-2 |
| AC-7 | `-h` または `--help` で usage と実行例を stdout に表示し exit 0 | TP-6 |
| AC-8 | 既存スクリプト（03, 04）のコードを変更しない | コード目視 |
| AC-9 | 引数不正時は stderr に usage を出し exit 2 | TP-7, TP-8, TP-9 |

## Interfaces

### CLI Synopsis

```
scripts/05_run_audit.sh [-h|--help] <task-dir>
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
| stdout | 各ステップの進捗ログ、子スクリプトの stdout、`git status --porcelain` の出力、`--help` 時の usage |
| stderr | エラーメッセージ、子スクリプトの stderr |

### 実行フロー

正常系の実行順序:

```
1. バリデーション（Error Handling 参照）
2. stdout に "=== Step 1/3: Gate (--clean) ===" を出力
3. ./scripts/03_gate.sh --clean <task-dir> を実行
   - 非0 → exit code をそのまま返して終了（Step 2, 3 は実行しない）
4. stdout に "=== Step 2/3: Audit Pack ===" を出力
5. ./scripts/04_audit_pack.sh <task-dir> を実行
   - 非0 → exit code をそのまま返して終了（Step 3 は実行しない）
6. stdout に "=== Step 3/3: Working Tree Status ===" を出力
7. git status --porcelain を実行し、出力をそのまま stdout に流す
8. exit 0
```

ステップ見出し（`=== Step N/3: ... ===`）の文言は上記を正とする。実装者はこの文字列を使うこと（TP-3 で検証する）。

### 子スクリプトの呼び出しパス

子スクリプトは `05_run_audit.sh` 自身のディレクトリからの相対パスで解決する。具体的には:

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"${SCRIPT_DIR}/03_gate.sh" --clean "$TASK_DIR"
"${SCRIPT_DIR}/04_audit_pack.sh" "$TASK_DIR"
```

これにより、リポジトリルート以外から呼ばれても子スクリプトを正しく見つけられる。

## Error Handling

05 自身のバリデーション（子スクリプト呼び出し前に実行）:

| # | 条件 | stderr メッセージ | exit |
|---|---|---|---|
| 0 | 引数が0個（`-h`/`--help` でもない） | usage を表示 | 2 |
| 1 | 引数が2個以上 | usage を表示 | 2 |
| 2 | 未知のオプション（`-` 始まりで `-h`/`--help` 以外） | usage を表示 | 2 |
| 3 | `<task-dir>` が存在するディレクトリでない | `"Error: directory not found: <task-dir>"` | 2 |
| 4 | cwd が git リポジトリ内でない（`git rev-parse --show-toplevel` 失敗） | `"Error: not inside a git repository: <cwd の実パス>"` | 2 |

子スクリプト実行時のエラー伝播:

| 条件 | 動作 |
|---|---|
| `03_gate.sh --clean` が非0で終了 | `04_audit_pack.sh` を実行しない。stderr に `"Error: gate failed (exit=<N>)"` を出力。05 の exit code = 03 の exit code |
| `04_audit_pack.sh` が非0で終了 | stderr に `"Error: audit_pack failed (exit=<N>)"` を出力。05 の exit code = 04 の exit code |

## Security/Safety Constraints

| # | 制約 |
|---|---|
| 1 | shebang は `#!/usr/bin/env bash` |
| 2 | スクリプト先頭で `set -euo pipefail` |
| 3 | ネットワークアクセス禁止 |
| 4 | 外部依存追加禁止。bash 組み込み + coreutils + git のみ |
| 5 | 既存スクリプト（03, 04）のコード・仕様を変更しない |
| 6 | `05_run_audit.sh` 自身はファイルを生成・削除しない（副作用は子スクリプト経由のみ） |
| 7 | WSL bash を正本とする |

## Test Plan

テストはリポジトリルートで実行する前提。

### TP-1: スクリプトが存在し実行可能である

```bash
[ -x ./scripts/05_run_audit.sh ] && echo "TP-1: PASS" || echo "TP-1: FAIL"
```

### TP-2: 正常実行（Gate → AuditPack → Status）

```bash
TASK_DIR="tasks/2026-02-02-0239-0001"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

./scripts/05_run_audit.sh "$TASK_DIR"
EXIT=$?

# exit 0 or 1（Gate結果による）。2 ではない
[ "$EXIT" -eq 0 ] || [ "$EXIT" -eq 1 ]
echo "TP-2: DONE (exit=$EXIT)"
```

### TP-3: ステップ見出しが stdout に出力される

```bash
TASK_DIR="tasks/2026-02-02-0239-0001"
[ -d "$TASK_DIR" ] || { echo "SKIP"; exit 0; }

OUTPUT=$(./scripts/05_run_audit.sh "$TASK_DIR" 2>/dev/null || true)

echo "$OUTPUT" | grep -q "=== Step 1/3: Gate (--clean) ===" || { echo "TP-3: FAIL (Step 1 missing)"; exit 1; }
echo "$OUTPUT" | grep -q "=== Step 2/3: Audit Pack ===" || { echo "TP-3: FAIL (Step 2 missing)"; exit 1; }
echo "$OUTPUT" | grep -q "=== Step 3/3: Working Tree Status ===" || { echo "TP-3: FAIL (Step 3 missing)"; exit 1; }

echo "TP-3: PASS"
```

### TP-4: 03_gate.sh が失敗 → 04_audit_pack.sh は実行されない

```bash
TASK_DIR=$(mktemp -d)
# GOAL.md/SPEC.md なしの空ディレクトリ → 03_gate.sh が失敗するはず
trap "rm -rf $TASK_DIR" EXIT

./scripts/05_run_audit.sh "$TASK_DIR" 2>tp4_stderr.txt
EXIT=$?

# 非0であること
[ "$EXIT" -ne 0 ] || { echo "TP-4: FAIL (expected non-zero)"; exit 1; }

# "Step 2/3: Audit Pack" が出力されていないこと（= 04 は呼ばれていない）
OUTPUT=$(./scripts/05_run_audit.sh "$TASK_DIR" 2>/dev/null || true)
echo "$OUTPUT" | grep -q "Step 2/3" && { echo "TP-4: FAIL (Step 2 ran despite gate failure)"; exit 1; }

rm -f tp4_stderr.txt
echo "TP-4: PASS"
```

### TP-5: 04_audit_pack.sh が失敗 → 05 も非0で終了

```bash
TASK_DIR="tasks/2026-02-02-0239-0001"
[ -d "$TASK_DIR" ] || { echo "SKIP"; exit 0; }

# Setup: GOAL.md を一時退避して 04 を失敗させる
BACKUP=""
if [ -f "$TASK_DIR/GOAL.md" ]; then
  BACKUP=$(mktemp)
  cp "$TASK_DIR/GOAL.md" "$BACKUP"
  rm "$TASK_DIR/GOAL.md"
fi

./scripts/05_run_audit.sh "$TASK_DIR" 2>/dev/null
EXIT=$?

# Restore
if [ -n "$BACKUP" ]; then
  mv "$BACKUP" "$TASK_DIR/GOAL.md"
fi

[ "$EXIT" -ne 0 ] || { echo "TP-5: FAIL (expected non-zero)"; exit 1; }
echo "TP-5: PASS"
```

### TP-6: -h / --help → usage 表示、exit 0

```bash
./scripts/05_run_audit.sh --help >/dev/null 2>&1
[ $? -eq 0 ] || { echo "TP-6a: FAIL"; exit 1; }

./scripts/05_run_audit.sh -h >/dev/null 2>&1
[ $? -eq 0 ] || { echo "TP-6b: FAIL"; exit 1; }

# usage に実行例が含まれること
./scripts/05_run_audit.sh --help | grep -q "05_run_audit.sh" || { echo "TP-6c: FAIL (no usage text)"; exit 1; }

echo "TP-6: PASS"
```

### TP-7: 引数なし → exit 2

```bash
./scripts/05_run_audit.sh 2>/dev/null
[ $? -eq 2 ] && echo "TP-7: PASS" || echo "TP-7: FAIL"
```

### TP-8: 余剰引数 → exit 2

```bash
TASK_DIR="tasks/2026-02-02-0239-0001"
[ -d "$TASK_DIR" ] || { echo "SKIP"; exit 0; }

./scripts/05_run_audit.sh "$TASK_DIR" extra 2>/dev/null
[ $? -eq 2 ] && echo "TP-8: PASS" || echo "TP-8: FAIL"
```

### TP-9: 未知オプション → exit 2

```bash
./scripts/05_run_audit.sh --unknown 2>/dev/null
[ $? -eq 2 ] && echo "TP-9: PASS" || echo "TP-9: FAIL"
```

### TP-10: 存在しないディレクトリ → exit 2

```bash
./scripts/05_run_audit.sh /nonexistent/path 2>/dev/null
[ $? -eq 2 ] && echo "TP-10: PASS" || echo "TP-10: FAIL"
```
