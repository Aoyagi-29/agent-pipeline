● SPEC

  Scope

  やること

  - scripts/02_make_spec_prompt.sh を新規作成
  - 引数で指定されたタスクディレクトリから GOAL.md
  を読み込む
  - Claude 用 SPEC 生成プロンプトを stdout へ出力
  - 引数バリデーション（未指定・ディレクトリ不在・G
  OAL.md 不在）

  やらないこと

  - Claude / Codex / LLM API の呼び出し
  - SPEC.md への自動書き込み
  - 複数タスクの一括処理
  - 多言語対応
  - ネットワークアクセス

  Acceptance Criteria

  - AC-1: scripts/02_make_spec_prompt.sh
  が存在し、実行権限が付与されている
  - AC-2: ./scripts/02_make_spec_prompt.sh
  tasks/2026-01-31-0001 実行時、stdout
  にプロンプト全文が出力される
  - AC-3: 出力に以下が含まれる
    - ロール指示（「仕様策定者」等）
    - 「実装は禁止」の文言
    - 固定見出し順の指示（Scope / Acceptance
  Criteria / Interfaces / Error Handling /
  Security/Safety Constraints / Test Plan）
    - GOAL.md の内容（コードブロックで囲む）
  - AC-4: 引数なしで実行 → stderr
  にエラー出力、exit code 2
  - AC-5: 存在しないディレクトリを指定 → stderr
  にエラー出力、exit code 2
  - AC-6: GOAL.md が存在しないディレクトリを指定 →
  stderr にエラー出力、exit code 2
  - AC-7: 正常終了時の exit code は 0
  - AC-8: 正常時の stdout 出力は 1
  行以上（空にならない）

  Interfaces

  CLI

  Usage: 02_make_spec_prompt.sh <task-dir>

  Arguments:
    task-dir    タスクディレクトリのパス（例:
  tasks/2026-01-31-0001）

  Exit codes:
    0   成功
    2   引数エラー / パス不在 / GOAL.md 不在

  入力
  項目: $1
  形式: ディレクトリパス
  備考: 末尾スラッシュ有無どちらも許容
  ────────────────────────────────────────
  項目: <task-dir>/GOAL.md
  形式: Markdown
  備考: UTF-8、読み取り専用
  出力（stdout）

  あなたは仕様策定者です。…（ルール説明）…

  GOAL.md:
  \`\`\`
  （GOAL.md の内容）
  \`\`\`

  Error Handling
  条件: 引数が 0 個
  stderr 出力: Usage: 02_make_spec_prompt.sh
    <task-dir>
  exit code: 2
  ────────────────────────────────────────
  条件: $1 がディレクトリとして存在しない
  stderr 出力: Error: directory not found: <path>
  exit code: 2
  ────────────────────────────────────────
  条件: <task-dir>/GOAL.md が存在しない
  stderr 出力: Error: GOAL.md not found in <path>
  exit code: 2
  Security/Safety Constraints

  禁止事項

  - eval / source の使用
  - ネットワークアクセス（curl / wget 等）
  - Claude / Codex / LLM API の呼び出し
  - 既存ファイルへの書き込み・変更・削除
  -
  未検証の変数展開（コマンドインジェクション対策）

  必須事項

  - shebang: #!/usr/bin/env bash
  - set -euo pipefail をスクリプト冒頭で宣言
  - パス引数は存在チェック後に使用

  Test Plan
  #: T-1
  テスト内容: test -x
  scripts/02_make_spec_prompt.sh
  期待結果: 成功（実行権限あり）
  ────────────────────────────────────────
  #: T-2
  テスト内容:
  有効なタスクディレクトリを指定して実行
  期待結果: exit 0、stdout に GOAL.md
    内容を含むプロンプト出力
  ────────────────────────────────────────
  #: T-3
  テスト内容: 出力を grep で検証:
    「実装は禁止」「Scope」「Acceptance
    Criteria」
  期待結果: すべてマッチ
  ────────────────────────────────────────
  #: T-4
  テスト内容: 引数なしで実行
  期待結果: exit 2、stderr に Usage 出力
  ────────────────────────────────────────
  #: T-5
  テスト内容: 存在しないディレクトリを指定
  期待結果: exit 2、stderr にエラー
  ────────────────────────────────────────
  #: T-6
  テスト内容: GOAL.md がないディレクトリを指定
  期待結果: exit 2、stderr にエラー
  ────────────────────────────────────────
  #: T-7
  テスト内容: [ -n
  "$(./scripts/02_make_spec_prompt.sh
    <valid>)" ]
  期待結果: 成功（出力が空でない）
