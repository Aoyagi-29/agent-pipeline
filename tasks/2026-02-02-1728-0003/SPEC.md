対象：
- scripts/06_smoke.sh を新規追加

仕様：
- bash（/usr/bin/env bash）
- set -euo pipefail
- git 管理下（repo 内）であることを確認する
  - git rev-parse --show-toplevel が成功すること
- 標準出力へ次を順に出す
  - "SMOKE_OK"
  - "repo_root=<path>"
  - "branch=<name>"
- 正常終了は exit 0
- repo 外の場合は stderr に理由を出して exit 2

テスト：
- scripts/06_smoke.sh を実行して "SMOKE_OK" が出る
