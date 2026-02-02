入力：引数で <task-dir> を1つ受け取る（例：tasks/2026-02-02-1349-0001）
出力：<task-dir>/AUDIT_PACK.md

失敗：
- 引数なし、またはディレクトリでない → stderrに使い方を出して exit 2
- <task-dir>/SPEC.md が無い → stderrに理由を出して exit 2

AUDIT_PACK.md の内容（順序固定）：
- 見出しに task-dir と生成時刻（任意でよいが固定形式にする）

## SPEC → SPEC.md をそのまま埋め込み
## GATE_REPORT → GATE_REPORT.md があれば埋め込み、なければ missing
## DIFF_STAT → git diff --stat を埋め込み
## DIFF → git diff を埋め込み

diff の範囲：HEAD~1..HEAD を固定（最短で収束させるため）
取得は repo 直下で実行する前提
生成物は Git 追跡しない（.gitignore に追加）
