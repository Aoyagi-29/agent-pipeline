## Codex運用ルール（Build役）

- 実装バックエンドのデフォルトは **Pi harness**（`AGENT_BACKEND=pi`）。ChatGPT Plus/Pro の Codex プロバイダを使う。
- デフォルトモデルは **GPT-5.5 / thinking=xhigh**（`AGENT_MODEL=openai-codex/gpt-5.5`, `AGENT_THINKING=xhigh`）。オーケストレーション側の `.env` / 環境変数で上書きする。
- Codex（Pi / codex CLI）は「実装・テスト・コミット」まで担当する。
- Codexは `tasks/<id>/SPEC.md` を編集しない（編集したら即FAIL）。
- Codexは `git push` を実行しない（ネットワーク/DNS差異で不安定なため）。
- `git push` は人間が WSL bash（/mnt/c/work/agent-pipeline）から実行する。
- Codexが生成した `tasks/<id>/GATE_REPORT.md` / `AUDIT.md` が未追跡で邪魔なら、push前に人間が削除する（必要なら別タスクで自動化）。
