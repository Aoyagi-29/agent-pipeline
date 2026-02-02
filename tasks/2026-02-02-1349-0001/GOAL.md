# GOAL

Gate実行時に、作業ツリーがクリーンでない場合（未追跡/未コミット変更あり）に即FAILさせる。

## DONE

- `./scripts/03_gate.sh --clean <task-dir>` 実行時に、実行前チェックとして
  - `git status --porcelain` が空でないなら終了コード2で終了する
  - stderr に明確なエラーメッセージを出す
- 既存のGate機能（TP等）を壊さない
- `--clean` が無い通常実行ではこのチェックを行わない（互換性維持）
