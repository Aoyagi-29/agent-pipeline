# PalCome MVP Worker (Python minimal)

## Setup
1) Python 3.11+ recommended
2) Install deps:
   pip install -r requirements.txt

3) Set env vars (example):
- SUPABASE_URL="https://xxxx.supabase.co"
- SUPABASE_SERVICE_ROLE_KEY="xxxxx"
- OPENAI_API_KEY="xxxxx"
- OPENAI_BASE_URL="https://api.openai.com/v1" (optional)
- OPENAI_MODEL="gpt-4.1-mini" (optional)
- RUNNING_TIMEOUT_SECONDS="3600" (optional, for reaping stale running jobs)

## Run once
python worker.py --once

## Run loop
python worker.py --loop --interval 30

## Behavior
- Claims one job atomically via Supabase RPC from scoring_jobs where status='pending'
- Fills in:
  - rakuten_url (LLM stub)
  - ingredients_raw (LLM stub)
  - ingredients_normalized (LLM stub)
  - scoring_result (LLM with schema + canonical origin validation, auto-retry up to 2)
- Updates status to done or error
- Reaps stale running jobs by resetting them (RPC)

## Required Supabase RPCs (example names)
- claim_scoring_job (atomic claim)
- reap_stale_scoring_jobs (return running jobs older than the provided timeout)
