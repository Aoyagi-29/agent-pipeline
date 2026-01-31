# AGENTS SSOT (must follow)

## Core pipeline
GOAL.md (human) -> SPEC.md (claude, spec only, format fixed) -> implementation (codex) -> GATE_REPORT.md (scripts) -> AUDIT.md (auditor) -> redo or next task

## Non-negotiables
- SPEC.md is the ONLY spec source of truth for implementation.
- Claude must NOT implement code. Claude outputs ONLY SPEC.md.
- Codex must NOT change SPEC.md. Codex changes code only.
- If gate fails, do not merge. Fix by looping.

## SPEC.md fixed headings (DO NOT CHANGE)
1. Scope
2. Acceptance Criteria
3. Interfaces
4. Error Handling
5. Security/Safety Constraints
6. Test Plan

## Output discipline
- Every change must be explained by an Acceptance Criteria item.
- Keep diffs minimal. Avoid drive-by refactors.
