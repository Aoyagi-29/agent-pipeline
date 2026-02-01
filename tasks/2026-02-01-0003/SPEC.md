# SPEC

## 1. Overview

### 1.1 Purpose
監査（Audit）に必要な材料（SPEC / Gate Report / git diff）を手作業で集めず、1コマンドで **監査入力（Audit Pack）を毎回同じ型**で生成できるようにする。

### 1.2 Deliverable
- `scripts/04_audit_pack.sh` を追加する（実行可能）
- `./scripts/04_audit_pack.sh <task-dir>` 実行で `<task-dir>/AUDIT_PACK.md` を生成する
- 生成物は空にならない（最低限のテンプレ＋必須セクションは必ず出る）

### 1.3 In Scope
- 単一タスクディレクトリ `<task-dir>` を対象に、監査パック（Markdown）を生成する
- Gate 実行（`scripts/03_gate.sh <task-dir>`）を呼び出し、生成された `GATE_REPORT.md` を監査パックへ埋め込む
- git diff（stat + full diff）を監査パックへ埋め込む

### 1.4 Out of Scope
- 複数タスク一括処理
- 外部API/LLM 実行
- ネットワークアクセス追加
- 多言語対応

## 2. Interfaces

### 2.1 Command
`./scripts/04_audit_pack.sh <task-dir>`

- `<task-dir>` は `tasks/2026-02-01-0003` のようなタスクディレクトリパス
- 相対/絶対パスどちらも受け付ける

### 2.2 Output Files (writes allowed)
- `<task-dir>/AUDIT_PACK.md`（本スクリプトが生成/上書き）
- `<task-dir>/GATE_REPORT.md`（Gateスクリプトが生成/上書き。監査パック生成の副作用として許容）

### 2.3 Read-only Files
- `<task-dir>/SPEC.md`（必須）
- `<task-dir>/GOAL.md`（存在する場合は読んでもよいが必須ではない）
- git repo の状態（`git diff` 等）

## 3. Functional Requirements

### 3.1 Argument Validation
以下は **stderr に1行以上のエラー**を出し、`exit 2` で終了する。

- 引数が無い / 引数が2個以上
- `<task-dir>` が存在しない / ディレクトリでない
- `<task-dir>/SPEC.md` が存在しない / 読めない
- スクリプト実行地点が git リポジトリ外（`git rev-parse --show-toplevel` が失敗）

※ `set -euo pipefail` を使いつつ、上記バリデーションは意図的にメッセージ付きで終了すること。

### 3.2 Gate Execution and Capture
- `scripts/03_gate.sh <task-dir>` を実行する
- 実行後、`<task-dir>/GATE_REPORT.md` が存在することを前提に、その内容を `AUDIT_PACK.md` に埋め込む
- Gate が FAIL しても **監査パック生成自体は継続**してよい（監査に必要なため）。  
  ただし Gate 実行が「コマンドとして実行不能」など致命的な場合は `exit 2` で落としてよい。

期待挙動（推奨）：
- `scripts/03_gate.sh` の終了コードを記録して `AUDIT_PACK.md` に明示
- Gate FAIL の場合でも `AUDIT_PACK.md` を生成し、スクリプト自体の終了コードは `0` を維持してよい  
  （監査入力の生成が主目的のため）
- ただし `GATE_REPORT.md` が生成されなかった場合は `exit 2`

※最終判断は実装者に委ねるが、少なくとも「Gate失敗で監査パックが出ない」は避ける。

### 3.3 Git Diff Capture
`AUDIT_PACK.md` に以下を含める。

- `git diff --stat`
- `git diff`

diff の基準は以下とする：
- `git diff` は **作業ツリー vs HEAD**（未ステージ差分）を対象
- 追加で、可能なら `git diff --cached --stat` と `git diff --cached`（ステージ差分）も含める  
  （監査時に差分取りこぼしを防ぐため）

※ ただし GOAL の必須要件は「--stat と diff を含む」なので、最低限 `git diff --stat` と `git diff` は必須。

### 3.4 Output Content Structure (AUDIT_PACK.md)
`AUDIT_PACK.md` は Markdown とし、最低限以下の順序でセクションを持つ。

1) Header（生成日時、対象タスク、git commit情報など）
2) SPEC全文
3) Gate結果（Gate exit code と `GATE_REPORT.md` 本文）
4) git diff --stat
5) git diff（full）
6) （任意）git diff --cached --stat / git diff --cached

各セクションは **見出し + コードブロック** で囲う。

#### Required headings (exact strings)
監査入力の型を固定するため、以下の見出し文字列を **そのまま**使う。

- `## AUDIT PACK`
- `## SPEC (SSOT)`
- `## GATE REPORT`
- `## GIT DIFF --STAT`
- `## GIT DIFF`
- `## GIT DIFF --CACHED --STAT`（任意）
- `## GIT DIFF --CACHED`（任意）

### 3.5 Non-empty Guarantee
- `AUDIT_PACK.md` は 1KB 未満でもよいが、空ファイルは禁止
- バリデーションを通過したら、最低でも header + 見出し群を出力する

## 4. Non-Functional Requirements

### 4.1 Shell
- shebang: `#!/usr/bin/env bash`
- strict mode: `set -euo pipefail`

### 4.2 Safety / Constraints
- ネットワークアクセスしない
- 外部依存を追加しない（bash + git + coreutils 程度で完結）
- `SPEC.md` / `GOAL.md` を編集しない（読み取りのみ）
- `tasks/` 配下で書き込み可能なのは `<task-dir>/AUDIT_PACK.md` と Gateが生成する `<task-dir>/GATE_REPORT.md` のみ

### 4.3 Portability
- WSL2 Ubuntu bash を正本とする
- 可能な限り GNU coreutils 前提でよい（mac互換は不要）

## 5. Exit Codes

- `0`: 監査パック生成に成功（Gate FAIL を含む場合でも、監査パックが生成されれば 0 でよい）
- `2`: 引数不正 / パス不在 / SPEC.md不在 / git repo外 / 生成不能などのエラー

## 6. Test Plan

### 6.1 Happy Path
1. 任意のタスクdir（例：`tasks/2026-02-01-0003`）に `SPEC.md` がある状態で実行
2. `<task-dir>/AUDIT_PACK.md` が生成される
3. `AUDIT_PACK.md` に Required headings が全て含まれる
4. `SPEC (SSOT)` に `SPEC.md` の全文が含まれる
5. `GATE REPORT` に `GATE_REPORT.md` の内容が含まれる
6. `GIT DIFF --STAT` と `GIT DIFF` が含まれる

### 6.2 Error Cases (exit 2)
- 引数なし
- task-dir が存在しない
- task-dir がディレクトリでない
- SPEC.md が無い
- git repo外で実行（`git rev-parse` が失敗する場所）

### 6.3 Side Effects
- `SPEC.md` / `GOAL.md` に変更が入らないこと
- 書き込みが `AUDIT_PACK.md` と `GATE_REPORT.md` 以外に発生しないこと

## 7. Notes
- Gate FAIL でも監査パックを出すことが監査効率の観点で望ましい
- ただし「Gate実行不能」「GATE_REPORT.md 不生成」など、監査パックの要となる情報が欠ける場合は exit 2 とする
