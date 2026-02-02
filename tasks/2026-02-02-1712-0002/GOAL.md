目的：scripts/04_audit_pack.sh <task-dir> を追加し、監査に必要な証跡を1ファイルへ収束させる

Done：
- <task-dir>/AUDIT_PACK.md を生成する
- AUDIT_PACK.md の順序を固定する
  1) SPEC.md 全文
  2) GATE_REPORT.md 全文（無ければ「missing」と明記）
  3) git diff --stat（範囲を明記）
  4) git diff（同一範囲）
- 生成物はGit追跡しない（.gitignore へ追加）
