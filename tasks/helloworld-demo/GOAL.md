# Goal

## Purpose
- Verify the agent-pipeline runs end-to-end in the Cursor Cloud dev environment.

## Deliverable
- A task that passes Gate and produces AUDIT_PACK.md via scripts/00_run_task.sh.

## Constraints
- Must: run without external API keys (default Gate + AuditPack mode).
- Must not: modify SPEC.md during implementation.
- Out of scope: the Claude/Codex --auto pipeline (requires API keys/CLIs).
