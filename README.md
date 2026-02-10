# Agent Pipeline (GOAL → SPEC固定 → 実装 → Gate → 監査 → 差し戻し)

このリポジトリは、AI駆動開発を **役割分離**で安全に回すための運用パイプラインです。  
**実行正本は WSL2 Ubuntu + bash**。Windows PowerShellは補助用途です。

## 役割分離（本質）
Human（目的だけ） → ClaudeCLI（仕様固定） → CodexCLI（実装） → ChatGPT（監査/ゲート判定） → 差し戻し or 完了

## SSOT（唯一の正）
- 仕様のSSOT = `tasks/<task-id>/SPEC.md`
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
Codex 実装はデフォルトで `OPENAI_API_KEY` を無視します。必要なら `CODEX_ALLOW_API_KEY=1` を設定します。

`--auto` の実行順:
1. Plan (`SELF_CONTEXT.md` 生成 + Claudeで `SPEC.md`)
2. Implement (`scripts/05_codex_implement.sh`)
3. Build/Run (`scripts/06_build_run_codex.sh`)
4. Gate + AuditPack
