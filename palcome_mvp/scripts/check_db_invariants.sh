#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# .env 読み込み（あれば）
if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
  set +a
fi

: "${SUPABASE_URL:?missing SUPABASE_URL}"
: "${SUPABASE_SERVICE_ROLE_KEY:?missing SUPABASE_SERVICE_ROLE_KEY}"

PROJECT_REF="$(echo "$SUPABASE_URL" | sed -E 's#^https?://([^./]+)\..*$#\1#')"
REST_URL="https://${PROJECT_REF}.supabase.co/rest/v1/scoring_jobs?select=id&status=eq.succeeded&scoring_result=is.null"

# 件数だけ見たいので、Content-Range を使う（Prefer: count=exact）
HDRS="$(curl -sS -D - -o /dev/null \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Prefer: count=exact" \
  "${REST_URL}" )"

COUNT="$(echo "$HDRS" | awk -F'/' 'tolower($1) ~ /^content-range:/ {gsub("\r","",$2); print $2}' | tail -n 1)"

if [[ -z "${COUNT:-}" ]]; then
  echo "[invariant] cannot determine count (missing Content-Range)" >&2
  exit 1
fi

if [[ "$COUNT" != "0" ]]; then
  echo "[invariant] VIOLATION: succeeded but scoring_result is NULL (count=$COUNT)" >&2
  exit 1
fi

echo "[invariant] OK: succeeded => scoring_result NOT NULL"
