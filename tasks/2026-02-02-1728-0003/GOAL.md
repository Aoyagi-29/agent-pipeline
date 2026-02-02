目的：パイプラインの入口（00_run_task）で、軽い開発が最後まで回ることを観測する

Done：
- scripts/06_smoke.sh を追加する
- scripts/06_smoke.sh は repo 内で実行されたことを観測し、"SMOKE_OK" を出して exit 0
- ./scripts/00_run_task.sh <task-dir> が exit=0 で完走する
- <task-dir>/AUDIT_PACK.md が生成される（追跡されない）
