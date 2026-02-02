#!/usr/bin/env bash
set -euo pipefail

if ! repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "Error: not inside a git repository" >&2
  exit 2
fi

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"

echo "SMOKE_OK"
echo "repo_root=$repo_root"
echo "branch=$branch"
