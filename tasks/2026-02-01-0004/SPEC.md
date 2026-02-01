# SPEC

## 1. Overview

`scripts/03_gate.sh` に `--clean` および `--clean-only` オプションを追加する。既存の引数なしモード（`<task-dir>` のみ）の挙動は一切変更しない。

| モード | コマンド | 動作 |
|---|---|---|
| legacy | `./scripts/03_gate.sh <task-dir>` | gate判定 → GATE_REPORT.md 生成（既存動作そのまま） |
| clean | `./scripts/03_gate.sh --clean <task-dir>` | gate判定 → GATE_REPORT.md 生成 → 生成物を削除 |
| clean-only | `./scripts/03_gate.sh --clean-only <task-dir>` | gate判定を実行せず、生成物だけ削除 |

## 2. Interfaces

### 2.1 CLI Synopsis

```
scripts/03_gate.sh [OPTIONS] <task-dir>
```

### 2.2 Positional Arguments

| 引数 | 必須 | 説明 |
|---|---|---|
| `<task-dir>` | Yes | タスクディレクトリへの相対パスまたは絶対パス |

### 2.3 Options

| オプション | 説明 |
|---|---|
| （なし） | legacy モード。既存動作を維持 |
| `--clean` | gate判定を実行後、生成物を削除 |
| `--clean-only` | gate判定を実行せず、生成物のみ削除 |

- `--clean` と `--clean-only` は排他。同時指定は引数不正（exit 2）。
- オプションは `<task-dir>` より前に置く。順序は `--clean <task-dir>` または `--clean-only <task-dir>` 固定。
- 未知のオプション（`--` で始まる未定義フラグ）は引数不正（exit 2）。

### 2.4 stdin / stdout / stderr

| チャネル | 用途 |
|---|---|
| stdout | 正常動作時のログ・進捗出力（既存踏襲） |
| stderr | エラーメッセージのみ |
| stdin | 使用しない |

## 3. Functional Requirements

### FR-1: legacy モード（後方互換）

既存の `./scripts/03_gate.sh <task-dir>` を呼び出した場合、現行コードと完全に同一の挙動をする。出力内容・exit code・副作用すべて既存のまま。

### FR-2: 共通バリデーション（全モード共通、gate判定より前に実行）

以下をすべてのモードで gate 判定前（clean-only の場合は削除前）に検証する。いずれか失敗で即 exit 2。

0. `--clean` / `--clean-only` を含め、許容する引数構成は（オプション最大1つ）+ `<task-dir>` の合計2トークンまで。これを超える場合は stderr に `"Error: invalid arguments"` を出力し exit 2。
1. `<task-dir>` が指定されていること。未指定なら stderr に `"Error: <task-dir> is required"` を出力。
2. `<task-dir>` がファイルシステム上に存在するディレクトリであること。存在しない／ファイルなら stderr に `"Error: directory not found: <task-dir>"` を出力。
3. スクリプト実行地点（カレントディレクトリ）が git リポジトリ内であること。`git rev-parse --show-toplevel` が失敗したら stderr に `"Error: not inside a git repository: <cwd の実パス>"` を出力。メッセージ末尾の実パスは `$(pwd)` 等で動的に埋める。

### FR-3: `--clean` モード

1. FR-2 のバリデーションを通過する。
2. 既存の gate 判定ロジックを実行する（legacy モードと同一の関数/処理）。
3. gate 判定が正常完了したら、FR-5 の削除処理を実行する。
4. gate 判定が異常終了（exit code ≠ 0）した場合でも、FR-5 の削除処理を実行する。つまり削除は必ず行う。
5. 最終 exit code は gate 判定の exit code をそのまま返す。

### FR-4: `--clean-only` モード

1. FR-2 のバリデーションを通過する。
2. gate 判定は一切実行しない。
3. FR-5 の削除処理を実行する。
4. 削除成功で exit 0。

### FR-5: 削除処理（clean 共通）

以下のファイルを `rm -f` で削除する。存在しなくてもエラーにしない。

| # | 対象パス |
|---|---|
| 1 | `<task-dir>/GATE_REPORT.md` |
| 2 | `<task-dir>/AUDIT_PACK.md` |
| 3 | `<task-dir>/AUDIT.md` |

- 上記 3 ファイル以外は絶対に削除しない。
- ワイルドカード・glob・`rm -rf` は使用禁止。
- 各ファイル削除時、stdout に `"Removed: <path>"` を出力する（ファイルが存在しなかった場合は出力しない）。

## 4. Non-Functional Requirements

| # | 要件 |
|---|---|
| NFR-1 | shebang は `#!/usr/bin/env bash` |
| NFR-2 | スクリプト先頭で `set -euo pipefail` |
| NFR-3 | ネットワークアクセス禁止。curl/wget/nc 等を新規追加しない |
| NFR-4 | 外部依存（apt/brew/pip 等）を新規追加しない。bash 組み込み + coreutils + git のみ |
| NFR-5 | 既存コードの非オプション部分への変更は最小限にとどめ、差分レビューしやすい構造にする |
| NFR-6 | ShellCheck（`shellcheck -e SC1091` 許容）で warning 0 を目標とする |

## 5. Exit Codes

| Code | 意味 |
|---|---|
| 0 | 正常終了（legacy: gate PASS / clean-only: 削除完了） |
| 1 | gate 判定 FAIL（legacy / --clean で gate が不合格の場合。既存挙動踏襲） |
| 2 | 引数不正 / 余剰引数 / パス不在 / git repo 外 / 排他オプション同時指定 / 未知オプション |

`--clean` モードでの最終 exit code は gate 判定結果に従う（PASS→0, FAIL→1）。削除処理自体が exit code を変えることはない（`rm -f` は失敗しない前提）。

## 6. Test Plan

すべてのテストは `bash` で手動実行可能であること。テスト用の一時ディレクトリを作成・削除して副作用を残さない。

### TP-1: legacy モード後方互換

```bash
# Setup: 実タスクdirを使用（SPEC.md 等が存在する前提）
TASK_DIR="tasks/2026-02-01-0004"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

# Exec
./scripts/03_gate.sh "$TASK_DIR"
LEGACY_EXIT=$?

# Verify: 終了コードが 0 または 1 であること（2 ではない）
[ "$LEGACY_EXIT" -eq 0 ] || [ "$LEGACY_EXIT" -eq 1 ]
```

### TP-2: --clean モード（gate → 削除）

```bash
TASK_DIR="tasks/2026-02-01-0004"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

# Exec
./scripts/03_gate.sh --clean "$TASK_DIR"
CLEAN_EXIT=$?

# Verify: exit code は 0 or 1（gate 結果による）
[ "$CLEAN_EXIT" -eq 0 ] || [ "$CLEAN_EXIT" -eq 1 ]

# Verify: 生成物が削除されていること
[ ! -f "$TASK_DIR/GATE_REPORT.md" ]
[ ! -f "$TASK_DIR/AUDIT_PACK.md" ]
[ ! -f "$TASK_DIR/AUDIT.md" ]
```

### TP-3: --clean-only モード（gate 未実行、削除のみ）

```bash
TASK_DIR="tasks/2026-02-01-0004"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

# Setup: ダミー生成物を配置
echo "dummy" > "$TASK_DIR/GATE_REPORT.md"
echo "dummy" > "$TASK_DIR/AUDIT_PACK.md"
echo "dummy" > "$TASK_DIR/AUDIT.md"

# Exec
./scripts/03_gate.sh --clean-only "$TASK_DIR"
CLEAN_ONLY_EXIT=$?

# Verify: exit 0
[ "$CLEAN_ONLY_EXIT" -eq 0 ]

# Verify: 3 ファイルとも削除されていること
[ ! -f "$TASK_DIR/GATE_REPORT.md" ]
[ ! -f "$TASK_DIR/AUDIT_PACK.md" ]
[ ! -f "$TASK_DIR/AUDIT.md" ]
```

### TP-4: --clean-only で対象ファイルが存在しない場合

```bash
TASK_DIR="tasks/2026-02-01-0004"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

# Setup: 対象ファイルが無い状態を保証
rm -f "$TASK_DIR/GATE_REPORT.md" "$TASK_DIR/AUDIT_PACK.md" "$TASK_DIR/AUDIT.md"

# Exec
./scripts/03_gate.sh --clean-only "$TASK_DIR"
EXIT=$?

# Verify: exit 0（エラーにならない）
[ "$EXIT" -eq 0 ]
```

### TP-5: 引数なし → exit 2

```bash
./scripts/03_gate.sh 2>/dev/null
[ $? -eq 2 ]
```

### TP-6: 存在しないディレクトリ → exit 2

```bash
./scripts/03_gate.sh /nonexistent/path 2>/dev/null
[ $? -eq 2 ]
```

### TP-7: git repo 外（cwdがgit外）→ exit 2

```bash
TASK_DIR=$(mktemp -d)
mkdir -p "$TASK_DIR"

# cwd を git repo 外に移して実行
SCRIPT_ABS="$(cd "$(dirname ./scripts/03_gate.sh)" && pwd)/03_gate.sh"
(cd "$TASK_DIR" && bash "$SCRIPT_ABS" "$TASK_DIR" 2>/dev/null)
EXIT=$?
[ "$EXIT" -eq 2 ]

rm -rf "$TASK_DIR"
```

### TP-8: --clean と --clean-only 同時指定 → exit 2

```bash
TASK_DIR="tasks/2026-02-01-0004"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

./scripts/03_gate.sh --clean --clean-only "$TASK_DIR" 2>/dev/null
[ $? -eq 2 ]
```

### TP-9: 未知オプション → exit 2

```bash
TASK_DIR="tasks/2026-02-01-0004"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

./scripts/03_gate.sh --unknown "$TASK_DIR" 2>/dev/null
[ $? -eq 2 ]
```

### TP-10: --clean-only が対象外ファイルを削除しないこと

```bash
TASK_DIR="tasks/2026-02-01-0004"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

# Setup: 対象外ファイルが存在することを確認（SPEC.md は常にある前提）
[ -f "$TASK_DIR/SPEC.md" ] || { echo "FAIL: SPEC.md missing before test"; exit 1; }

# 対象ファイルを配置
echo "dummy" > "$TASK_DIR/GATE_REPORT.md"

# Exec
./scripts/03_gate.sh --clean-only "$TASK_DIR"

# Verify: 対象外は残っている
[ -f "$TASK_DIR/SPEC.md" ]

# Verify: 対象は削除されている
[ ! -f "$TASK_DIR/GATE_REPORT.md" ]
```

### TP-11: stderr にエラーメッセージが出力されること

```bash
ERR=$(./scripts/03_gate.sh 2>&1 1>/dev/null)
echo "$ERR" | grep -q "Error:"
```

### TP-12: 余剰引数 → exit 2

```bash
TASK_DIR="tasks/2026-02-01-0004"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

./scripts/03_gate.sh --clean "$TASK_DIR" extra_arg 2>/dev/null
[ $? -eq 2 ]
```

## 7. Notes

- 既存の `03_gate.sh` が gate 判定で生成するファイルが FR-5 の 3 ファイル以外にある場合、将来的に削除対象の追加が必要になる可能性がある。その場合は SPEC を改訂する。
- `--clean` モードで gate 判定が異常終了しても削除を行う設計理由: CI パイプラインで「判定結果に関わらずクリーンな状態に戻す」ユースケースを想定。
- SPEC.md は SSOT（Single Source of Truth）。実装者はこの文書に記載のない動作を追加しない。
