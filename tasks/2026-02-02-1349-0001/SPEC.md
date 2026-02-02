# SPEC

## Scope

`scripts/03_gate.sh` の `--clean` モードに、Gate 判定実行前の作業ツリークリーンチェックを追加する。`git status --porcelain` が空でない場合は Gate 判定を実行せず即座に失敗させる。`--clean` を指定しない通常実行（legacy モード）にはこのチェックを追加しない。

対象ファイル: `scripts/03_gate.sh`（既存スクリプトへの機能追加）

変更しないもの: legacy モード（`./scripts/03_gate.sh <task-dir>`）の挙動、`--clean-only` モードの挙動（存在する場合）、他スクリプト（04, 05, 00）のコード。

## Acceptance Criteria

| # | 条件 | 検証方法 |
|---|---|---|
| AC-1 | `--clean` 実行時、Gate 判定前に `git status --porcelain` を検査する | TP-1 |
| AC-2 | 出力が空でなければ stderr にエラーメッセージを出力し exit 2 で終了する | TP-1 |
| AC-3 | 出力が空であれば従来どおり Gate 判定 → クリーン削除を実行する | TP-2 |
| AC-4 | legacy モード（`./scripts/03_gate.sh <task-dir>`）ではクリーンチェックを行わない | TP-3 |
| AC-5 | 既存の Test Plan（TP）が壊れない | TP-4 |

## Interfaces

### 変更対象モード

| モード | クリーンチェック | 備考 |
|---|---|---|
| legacy（`<task-dir>` のみ） | **行わない** | 既存動作を維持 |
| `--clean <task-dir>` | **行う** | 本タスクで追加 |
| `--clean-only <task-dir>` | **行わない** | 存在する場合、既存動作を維持 |

### `--clean` モードの実行フロー（変更後）

```
1. 共通バリデーション（引数・パス・git repo チェック）  ← 既存
2. ★ git status --porcelain を実行                     ← 新規追加
   - 出力が空でない → stderr にエラー、exit 2
3. Gate 判定ロジック                                    ← 既存
4. 削除処理（GATE_REPORT.md 等）                        ← 既存
```

ステップ 2 が本タスクの追加箇所。それ以外は既存コードを変更しない。

### stderr メッセージ

作業ツリーが汚れている場合のメッセージ:

```
Error: working tree is not clean (--clean requires a clean working tree)
```

メッセージの後に `git status --porcelain` の出力内容を stderr にそのまま付記する。これにより、何が汚れているか即座に把握できる。

```
Error: working tree is not clean (--clean requires a clean working tree)
 M scripts/03_gate.sh
?? untracked_file.txt
```

## Error Handling

本タスクで追加するエラー条件:

| 条件 | stderr メッセージ | exit |
|---|---|---|
| `--clean` 実行時に `git status --porcelain` の出力が空でない | `"Error: working tree is not clean (--clean requires a clean working tree)"` + 差分内容 | 2 |

exit 2 を使う理由: 作業ツリーが汚れている状態は「実行前提条件の不備」であり、Gate 判定の合否（exit 0/1）とは性質が異なる。引数不正やパス不在と同じカテゴリ（exit 2）に分類する。

既存のエラー条件（引数不正 / パス不在 / git repo 外）には変更を加えない。

## Security/Safety Constraints

| # | 制約 |
|---|---|
| 1 | shebang `#!/usr/bin/env bash` と `set -euo pipefail` を維持 |
| 2 | ネットワークアクセス禁止 |
| 3 | 外部依存追加禁止。bash 組み込み + coreutils + git のみ |
| 4 | legacy モード / `--clean-only` モードのコードパスに変更を加えない |
| 5 | 追加するコードは `--clean` モードの Gate 判定前の1箇所のみ |
| 6 | WSL bash を正本とする |

## Test Plan

テストはリポジトリルートで実行する前提。

### TP-1: --clean で作業ツリーが汚い → exit 2

```bash
TASK_DIR="tasks/2026-02-02-0004"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

# Setup: 作業ツリーを汚す
echo "dirty" > __tp1_dirty_file__
trap 'rm -f __tp1_dirty_file__' EXIT

# Exec
./scripts/03_gate.sh --clean "$TASK_DIR" 2>tp1_stderr.txt
EXIT=$?

# Verify: exit 2
[ "$EXIT" -eq 2 ] || { echo "TP-1: FAIL (expected exit 2, got $EXIT)"; rm -f tp1_stderr.txt; exit 1; }

# Verify: stderr に "not clean" が含まれる
grep -q "not clean" tp1_stderr.txt || { echo "TP-1: FAIL (stderr missing message)"; rm -f tp1_stderr.txt; exit 1; }

# Verify: stderr に汚れファイル名が含まれる
grep -q "__tp1_dirty_file__" tp1_stderr.txt || { echo "TP-1: FAIL (dirty file not listed)"; rm -f tp1_stderr.txt; exit 1; }

rm -f __tp1_dirty_file__ tp1_stderr.txt
trap - EXIT
echo "TP-1: PASS"
```

### TP-2: --clean で作業ツリーがクリーン → Gate 判定実行

```bash
TASK_DIR="tasks/2026-02-02-0004"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

# Precondition: 作業ツリーがクリーン
if [ -n "$(git status --porcelain)" ]; then
  echo "SKIP: working tree is not clean (commit or stash first)"
  exit 0
fi

# Exec
./scripts/03_gate.sh --clean "$TASK_DIR"
EXIT=$?

# Verify: exit 0 or 1（Gate 判定結果）。2 ではない
[ "$EXIT" -eq 0 ] || [ "$EXIT" -eq 1 ] || { echo "TP-2: FAIL (unexpected exit $EXIT)"; exit 1; }

echo "TP-2: PASS (exit=$EXIT)"
```

### TP-3: legacy モードではクリーンチェックしない

```bash
TASK_DIR="tasks/2026-02-02-0004"
[ -d "$TASK_DIR" ] || { echo "SKIP: $TASK_DIR not found"; exit 0; }

# Setup: 作業ツリーを汚す
echo "dirty" > __tp3_dirty_file__
trap 'rm -f __tp3_dirty_file__' EXIT

# Exec: legacy モード（--clean なし）
./scripts/03_gate.sh "$TASK_DIR" 2>tp3_stderr.txt
EXIT=$?

# Verify: exit 2 ではない（legacy はクリーンチェックしない）
[ "$EXIT" -ne 2 ] || { echo "TP-3: FAIL (legacy should not check clean tree)"; rm -f tp3_stderr.txt; exit 1; }

# Verify: stderr に "not clean" が含まれない
grep -q "not clean" tp3_stderr.txt && { echo "TP-3: FAIL (clean check ran in legacy mode)"; rm -f tp3_stderr.txt; exit 1; }

rm -f __tp3_dirty_file__ tp3_stderr.txt
trap - EXIT
echo "TP-3: PASS (exit=$EXIT)"
```

### TP-4: 既存テスト（引数不正系）が壊れていないこと

```bash
PASS=0
FAIL=0

# 引数なし → exit 2
./scripts/03_gate.sh 2>/dev/null; [ $? -eq 2 ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# 存在しないパス → exit 2
./scripts/03_gate.sh /nonexistent 2>/dev/null; [ $? -eq 2 ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# 未知オプション → exit 2
./scripts/03_gate.sh --unknown tasks/2026-02-02-0004 2>/dev/null; [ $? -eq 2 ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

echo "TP-4: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && echo "TP-4: PASS" || echo "TP-4: FAIL"
```