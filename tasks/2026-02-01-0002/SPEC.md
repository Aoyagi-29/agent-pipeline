● SPEC

  Scope

  やること

  - scripts/03_gate.sh を拡張し、SSOT
  保護チェックを追加
  - Git 差分に tasks/<id>/SPEC.md
  の変更が含まれていたら FAIL
  - Git 差分に tasks/<id>/GOAL.md
  の変更が含まれていたら FAIL
  - FAIL 時は tasks/<id>/GATE_REPORT.md
  に理由と検知ファイル一覧を出力
  - PASS 時は GATE_REPORT.md に「SPEC/GOAL
  未変更」を明記
  - 既存の Gate 出力（diff/stat 等）との互換性維持

  やらないこと

  - 新規外部ツール・CI の導入
  - 役割分離を崩す変更
  - SPEC.md / GOAL.md 以外のファイルへの編集制限

  Acceptance Criteria

  - AC-1: scripts/03_gate.sh <task-dir> 実行時、Git
   差分に <task-dir>/SPEC.md の変更があれば exit
  code が非ゼロ
  - AC-2: scripts/03_gate.sh <task-dir> 実行時、Git
   差分に <task-dir>/GOAL.md の変更があれば exit
  code が非ゼロ
  - AC-3: FAIL 時、<task-dir>/GATE_REPORT.md
  に以下が出力される
    - FAIL の理由（SSOT 違反）
    - 検知した禁止ファイルの一覧
  - AC-4: PASS 時、<task-dir>/GATE_REPORT.md
  に「SPEC.md および GOAL.md
  は変更されていない」旨が明記される
  - AC-5: 既存の Gate 出力（diff 表示、stat
  情報等）が引き続き出力される（後方互換）
  - AC-6: SPEC.md を意図的に編集 → Gate が FAIL
  する
  - AC-7: SPEC.md / GOAL.md を触らない変更 → Gate
  が PASS する

  Interfaces

  CLI

  Usage: 03_gate.sh <task-dir>

  Arguments:
    task-dir    タスクディレクトリのパス（例:
  tasks/2026-01-31-0001）

  Exit codes:
    0   PASS（SSOT 違反なし）
    1   FAIL（SSOT 違反検出）
    2   引数エラー / パス不在

  入力
  項目: $1
  形式: ディレクトリパス
  備考: 対象タスクディレクトリ
  ────────────────────────────────────────
  項目: Git 差分
  形式: git diff --name-only 等
  備考: HEAD との比較（未コミット変更）
  出力
  出力先: stdout
  内容: 既存の Gate 出力（diff/stat 等）+ SSOT
    チェック結果
  ────────────────────────────────────────
  出力先: <task-dir>/GATE_REPORT.md
  内容:
  チェック結果詳細（PASS/FAIL、理由、検知ファイル
  GATE_REPORT.md フォーマット（FAIL 時）

  # Gate Report

  ## Result: FAIL

  ## SSOT Violation
  以下の禁止ファイルが変更されています:
  - tasks/<id>/SPEC.md
  - tasks/<id>/GOAL.md

  ## Action Required
  SPEC.md / GOAL.md の変更を取り消してください。

  GATE_REPORT.md フォーマット（PASS 時）

  # Gate Report

  ## Result: PASS

  ## SSOT Check
  SPEC.md および GOAL.md は変更されていません。

  Error Handling
  条件: 引数なし
  動作: stderr に Usage 出力
  exit code: 2
  ────────────────────────────────────────
  条件: 指定ディレクトリが存在しない
  動作: stderr にエラー出力
  exit code: 2
  ────────────────────────────────────────
  条件: Git リポジトリ外で実行
  動作: stderr にエラー出力
  exit code: 2
  ────────────────────────────────────────
  条件: SPEC.md / GOAL.md に変更検出
  動作: GATE_REPORT.md に詳細出力、FAIL
  exit code: 1
  Security/Safety Constraints

  禁止事項

  - SPEC.md / GOAL.md への書き込み（読み取り専用）
  - eval / source の使用
  - ネットワークアクセス
  - 既存 Gate 出力の削除・改変

  必須事項

  - shebang: #!/usr/bin/env bash
  - set -euo pipefail をスクリプト冒頭で宣言
  - Git コマンドの戻り値を適切にハンドリング
  - GATE_REPORT.md のみ書き込み可（それ以外は
  read-only）

  Test Plan
  #: T-1
  テスト内容: SPEC.md を編集後、Gate 実行
  期待結果: exit 1、GATE_REPORT.md に SPEC.md
  が記載
  ────────────────────────────────────────
  #: T-2
  テスト内容: GOAL.md を編集後、Gate 実行
  期待結果: exit 1、GATE_REPORT.md に GOAL.md
  が記載
  ────────────────────────────────────────
  #: T-3
  テスト内容: SPEC.md と GOAL.md 両方を編集後、Gate
   実行
  期待結果: exit 1、両ファイルが記載
  ────────────────────────────────────────
  #: T-4
  テスト内容: SPEC.md / GOAL.md
    以外のファイルのみ編集後、Gate 実行
  期待結果: exit 0、GATE_REPORT.md に「未変更」明
  ────────────────────────────────────────
  #: T-5
  テスト内容: 変更なしで Gate 実行
  期待結果: exit 0
  ────────────────────────────────────────
  #: T-6
  テスト内容: 既存 Gate
    出力（diff/stat）が表示されることを確認
  期待結果: 従来通り出力される
  ────────────────────────────────────────
  #: T-7
  テスト内容: 引数なしで実行
  期待結果: exit 2、Usage 出力
  ────────────────────────────────────────
  #: T-8
  テスト内容: 存在しないディレクトリを指定
  期待結果: exit 2、エラー出力

