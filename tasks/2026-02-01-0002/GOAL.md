# GOAL

## 目的
Gateで「SPECのSSOT不変」を機械的に保証する。
Codexが誤って tasks/<id>/SPEC.md を編集した場合、Gateが即FAILし、差し戻し判断を一意にする。

## 背景
運用の最重要ルールは SPEC.md がSSOTであり、Codexは編集禁止。
人間の注意だけだとSSOT汚染が起きるため、Gateで強制する。

## 成果物（Doneの定義）
- scripts/03_gate.sh が以下を満たす：
  - 引数の tasks/<id> を対象に、Git差分に tasks/<id>/SPEC.md の変更が含まれていたら FAIL（exit non-zero）。
  - （推奨）同様に tasks/<id>/GOAL.md の変更も FAIL（Humanのみ編集のため）。
  - FAIL時は tasks/<id>/GATE_REPORT.md に理由と検知したファイル一覧を出力する。
  - PASS時も「SPEC/GOALが変更されていない」旨をGATE_REPORTに明記する。
- 既存のGate出力（diff/stat等）は壊さない（互換性維持）。
- 最低限の動作確認：
  - SPEC.md を意図的に編集した場合にGateがFAILすること。
  - SPEC.md を触っていない場合にGateがPASSすること。

## 非目標
- 新規外部ツール導入（CI追加など）はしない（必要なら別タスク）。
- 役割分離を崩す変更はしない。
