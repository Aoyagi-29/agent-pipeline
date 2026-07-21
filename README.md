# Agent Pipeline (GOAL → SPEC固定 → 実装 → Gate → 監査 → 差し戻し)

このリポジトリは、AI駆動開発を **役割分離**で安全に回すための運用パイプラインです。  
**実行正本は WSL2 Ubuntu + bash**。Windows PowerShellは補助用途です。

## 役割分離（本質）
Human（目的だけ） → Pi/Codex（対話入口） → Claude（ExecPlan生成） → Pi(openai-codex)（実装） → Gate → 差し戻し or 完了

## Pi + Codex セットアップ
実装のデフォルトは **Pi harness + ChatGPT Codex サブスク**（モデル: `openai-codex/gpt-5.5`, thinking: `xhigh`）。

```bash
# 1) Pi インストール + プロジェクト設定 (.pi/settings.json, .env.example)
./scripts/09_setup_pi.sh

# 2) ChatGPT Plus/Pro で Codex ログイン（対話）
pi
# その中で: /login → ChatGPT Plus/Pro (Codex)

# 3) 確認
./scripts/09_setup_pi.sh --check
```

モデル選定はオーケストレーション側で調整する（`.env` または環境変数）:

| 変数 | デフォルト | 意味 |
|------|------------|------|
| `AGENT_BACKEND` | `pi` | `pi` または `codex`（CLI） |
| `AGENT_MODEL` | `openai-codex/gpt-5.5` | プロバイダ/モデル（`:thinking` 短縮可） |
| `AGENT_THINKING` | `xhigh` | `off\|minimal\|low\|medium\|high\|xhigh` |
| `CODEX_MODEL` | `gpt-5.5` | `AGENT_BACKEND=codex` 時の CLI モデル ID |

例:
```bash
# デフォルト（GPT-5.5 xhigh）で auto
./scripts/00_run_task.sh --auto tasks/<id>

# 思考レベルだけ下げる
AGENT_THINKING=high ./scripts/00_run_task.sh --auto tasks/<id>

# モデルを明示
AGENT_MODEL=openai-codex/gpt-5.4 AGENT_THINKING=medium ./scripts/00_run_task.sh --auto tasks/<id>

# 旧 codex CLI にフォールバック
AGENT_BACKEND=codex CODEX_MODEL=gpt-5.5 ./scripts/00_run_task.sh --auto tasks/<id>
```

## SSOT（唯一の正）
- Plan/Decision/Progress のSSOT = `tasks/<task-id>/EXECPLAN.md`
- 実装は SPEC.md に従う（CodexがSPECを編集したら即FAIL）
- Gate結果 = `tasks/<task-id>/GATE_REPORT.md`
- 監査結果 = `tasks/<task-id>/AUDIT.md`

## クイックスタート（WSL bash）
```bash
cd /mnt/c/work/agent-pipeline
ls -la tasks
ls -la scripts
```

## Self Improve
```bash
# 改善タスクだけ作る
./scripts/07_self_improve.sh

# 改善タスクを作ってそのまま auto 実行
./scripts/07_self_improve.sh --run-auto
```

## Claude Planning Context
`--auto` 実行時は `scripts/02_build_self_context.sh` が `tasks/<id>/SELF_CONTEXT.md` を生成し、
`GOAL.md` と合わせて Claude に渡して `SPEC.md` を作成します。
デフォルトは **Claude CLI を優先**し、CLI が無い場合は API を使います。
`CLAUDE_PLAN_MODE=cli|api` で強制切り替えできます。
API費用を使わない場合は `CLAUDE_NO_API=1` を設定し、Claude CLIのみで実行します。
このモードでは `CLAUDE_API_KEY` / `ANTHROPIC_API_KEY` が設定されていると失敗します。
実装（Pi / Codex）はデフォルトで `OPENAI_API_KEY` を無視し、ChatGPT サブスク認証（`pi /login` または `codex login`）を使います。API キーが必要な場合のみ `CODEX_ALLOW_API_KEY=1` を設定します。

## Change Summary (ChatGPT API)
監査用の `CHANGE_SUMMARY.md` 生成は ChatGPT API を使いますが、デフォルトで無効化されています。
有効化する場合は `USE_CHATGPT_API=1` を設定してください。

## Auto Loop
複数回の再実行・再Planを自動化する場合は `scripts/08_auto_loop.sh` を使います。
デフォルトは「実務で止まりにくい」上限に設定されています。

```bash
./scripts/08_auto_loop.sh tasks/<id>
```

上書き可能な環境変数:
- `MAX_BUILD_LOOPS` (default: 3)
- `MAX_REPLANS` (default: 2)
- `MAX_TOTAL_RUNS` (default: 6)
- `MAX_ENV_RETRIES` (default: 2)
- `MAX_DIFF_FILES` (default: 50)
- `CLAUDE_PLAN_TIMEOUT` (default: 120)
- `CLAUDE_PLAN_MAX_CONTEXT_CHARS` (default: 4000, `0`でSELF_CONTEXTを無効化)

`--auto` の実行順:
1. Plan (`SELF_CONTEXT.md` 生成 + Claudeで `SPEC.md`)
2. Implement (`scripts/05_codex_implement.sh` — default Pi / GPT-5.5 xhigh)
3. Build/Run (`scripts/06_build_run_codex.sh`)
4. Gate + AuditPack
