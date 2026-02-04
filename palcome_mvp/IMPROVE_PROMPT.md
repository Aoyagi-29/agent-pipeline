# PalCome MVP Worker - Improve Loop Prompt (SSOT)

目的：
palcome_mvp の worker を「動いてエラーの出ないもの」へ収束させる。
ここでの “エラーの出ない” は、想定前提（env未設定・外部I/O失敗）を含めて「説明的に失敗し、状態が破綻しない」も含む。

固定ルール：
- 仕様（GOAL/SPEC）を勝手に変えない
- 変更は palcome_mvp/ 配下のみ
- 1周回1論点……小さく直す
- 毎周回、観測/合意/相違/期限 を DECISION_LOG.md に追記する

観測（毎周回）：
1) python -m compileall palcome_mvp
2) python palcome_mvp/worker.py --once
   - env未設定なら「必要キー列挙 + exit」でよい（stacktrace垂れ流しは避ける）
   - 外部I/O失敗なら、job側へ error を必ず反映（可能な範囲で）

優先して潰す論点（上から）：
- python-dotenv を実際に読み込む導線（.env）
- 例外分類と error_code 粒度（SUPABASE_RPC_FAILED / OPENAI_CALL_FAILED / VALIDATION_FAILED など）
- tick() の FATAL 経路を “観測しやすいログ” へ寄せる（必要なら構造化）
- 最低限のバックオフ/再試行の境界（暴走しない範囲）

出力（毎周回）：
- 変更差分
- DECISION_LOG.md 追記
- 失敗なら再周回、成功なら次の論点へ
