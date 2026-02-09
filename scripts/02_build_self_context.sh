#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/02_build_self_context.sh <task-dir>"
  echo ""
  echo "Build tasks/<id>/SELF_CONTEXT.md from TARGET_REPO files and recent reports."
}

if [[ $# -ne 1 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage >&2
  exit 2
fi

TASK_DIR="$1"
if [[ ! -d "$TASK_DIR" ]]; then
  echo "Error: directory not found: $TASK_DIR" >&2
  exit 2
fi

TARGET_REPO_FILE="$TASK_DIR/TARGET_REPO"
if [[ ! -f "$TARGET_REPO_FILE" ]]; then
  echo "Error: TARGET_REPO not found in $TASK_DIR" >&2
  exit 2
fi

TARGET_REPO="$(head -n 1 "$TARGET_REPO_FILE" | tr -d '\r' | xargs)"
if [[ -z "$TARGET_REPO" ]]; then
  echo "Error: TARGET_REPO is empty" >&2
  exit 2
fi
if [[ ! -d "$TARGET_REPO" ]]; then
  echo "Error: TARGET_REPO directory not found: $TARGET_REPO" >&2
  exit 2
fi

SELF_CONTEXT_PATH="$TASK_DIR/SELF_CONTEXT.md"
MAX_FILES="${SELF_CONTEXT_MAX_FILES:-8}"
MAX_LINES="${SELF_CONTEXT_MAX_LINES:-120}"
MAX_REPORTS="${SELF_CONTEXT_MAX_REPORTS:-4}"
MAX_REPORT_LINES="${SELF_CONTEXT_MAX_REPORT_LINES:-80}"

if ! [[ "$MAX_FILES" =~ ^[0-9]+$ ]] || [[ "$MAX_FILES" -le 0 ]]; then
  echo "Error: SELF_CONTEXT_MAX_FILES must be a positive integer" >&2
  exit 2
fi
if ! [[ "$MAX_LINES" =~ ^[0-9]+$ ]] || [[ "$MAX_LINES" -le 0 ]]; then
  echo "Error: SELF_CONTEXT_MAX_LINES must be a positive integer" >&2
  exit 2
fi
if ! [[ "$MAX_REPORTS" =~ ^[0-9]+$ ]] || [[ "$MAX_REPORTS" -le 0 ]]; then
  echo "Error: SELF_CONTEXT_MAX_REPORTS must be a positive integer" >&2
  exit 2
fi
if ! [[ "$MAX_REPORT_LINES" =~ ^[0-9]+$ ]] || [[ "$MAX_REPORT_LINES" -le 0 ]]; then
  echo "Error: SELF_CONTEXT_MAX_REPORT_LINES must be a positive integer" >&2
  exit 2
fi

rel_path() {
  local p="$1"
  case "$p" in
    "$TARGET_REPO"/*) printf '%s\n' "${p#"$TARGET_REPO"/}" ;;
    *) printf '%s\n' "$p" ;;
  esac
}

append_file_snippet() {
  local file="$1"
  local max_lines="$2"
  local rel
  local line_count
  rel="$(rel_path "$file")"
  line_count="$(wc -l < "$file" | tr -d ' ')"
  {
    echo "### $rel"
    echo '```'
    sed -n "1,${max_lines}p" "$file"
    if [[ "$line_count" -gt "$max_lines" ]]; then
      echo ""
      echo "... (truncated: ${max_lines}/${line_count} lines)"
    fi
    echo '```'
    echo
  } >> "$SELF_CONTEXT_PATH"
}

{
  echo "# SELF_CONTEXT"
  echo
  echo "- generated_at: $(date -Iseconds 2>/dev/null || date)"
  echo "- task_dir: $TASK_DIR"
  echo "- target_repo: $TARGET_REPO"
  echo
  echo "## Objective"
  echo "Use this context to identify improvements needed for the pipeline and produce SPEC.md."
  echo
  echo "## Repository Snapshot"
  (
    cd "$TARGET_REPO"
    echo "- git_branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    echo "- git_head: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "- dirty: $(if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then echo yes; else echo no; fi)"
  )
  echo
  echo "## Key Files"
} > "$SELF_CONTEXT_PATH"

file_count=0
if [[ -d "$TARGET_REPO/scripts" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    append_file_snippet "$f" "$MAX_LINES"
    file_count=$((file_count + 1))
  done < <(find "$TARGET_REPO/scripts" -mindepth 1 -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" \) | sort | head -n "$MAX_FILES")
fi

if [[ "$file_count" -eq 0 ]]; then
  for f in "$TARGET_REPO/README.md" "$TARGET_REPO/AGENTS.md" "$TARGET_REPO/pyproject.toml" "$TARGET_REPO/package.json"; do
    if [[ -f "$f" ]]; then
      append_file_snippet "$f" "$MAX_LINES"
      file_count=$((file_count + 1))
    fi
    if [[ "$file_count" -ge "$MAX_FILES" ]]; then
      break
    fi
  done
fi

if [[ "$file_count" -eq 0 ]]; then
  {
    echo "(no key files found under scripts/ and fallback files)"
    echo
  } >> "$SELF_CONTEXT_PATH"
fi

{
  echo "## Recent Reports"
} >> "$SELF_CONTEXT_PATH"

report_count=0
if [[ -d "$TARGET_REPO/tasks" ]]; then
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    for report in "$d/BUILD_REPORT.md" "$d/GATE_REPORT.md" "$d/AUDIT_PACK.md"; do
      if [[ -f "$report" ]]; then
        append_file_snippet "$report" "$MAX_REPORT_LINES"
        report_count=$((report_count + 1))
      fi
      if [[ "$report_count" -ge "$MAX_REPORTS" ]]; then
        break 2
      fi
    done
  done < <(find "$TARGET_REPO/tasks" -mindepth 1 -maxdepth 1 -type d | sort -r)
fi

if [[ "$report_count" -eq 0 ]]; then
  {
    echo "(no recent reports found)"
    echo
  } >> "$SELF_CONTEXT_PATH"
fi

echo "Wrote: $SELF_CONTEXT_PATH"
