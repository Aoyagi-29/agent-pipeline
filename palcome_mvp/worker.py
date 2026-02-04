import json

def unwrap_openai_content(x):
    """
    OpenAIのレスポンス(dict)をDB保存可能な形へ収束させる。
    - chat.completionsの外側（id/choices/created/...）を捨てる
    - choices[0].message.content を優先
    - content がJSON文字列なら dict/list にパース
    """
    if x is None:
        return None

    # すでにdict/listならそのまま（ただしOpenAI外箱なら剥がす）
    if isinstance(x, dict):
        if "choices" in x and isinstance(x.get("choices"), list) and x["choices"]:
            choice0 = x["choices"][0] or {}
            msg = choice0.get("message") or {}
            content = msg.get("content")
            # content が無い型もあるのでフォールバック
            if content is None:
                content = choice0.get("text")
            return unwrap_openai_content(content)
        return x

    if isinstance(x, list):
        return x

    # 文字列なら、JSONっぽければパース、無理なら文字列のまま
    if isinstance(x, str):
        s = x.strip()
        if (s.startswith("{") and s.endswith("}")) or (s.startswith("[") and s.endswith("]")):
            try:
                return json.loads(s)
            except Exception:
                return x
        return x

    # その他の型は文字列化
    return str(x)

# PalCome MVP worker.py (instrumented)
import argparse
import time
import traceback

from palcome.config import Settings
from palcome.db_supabase import SupabaseDB
from palcome.pipeline import run_one_job


def persist_failure(db: SupabaseDB, job, err: str):
    if not job or job.get("id") is None:
        print("[persist_failure] FATAL: job is None (cannot persist last_error)")
        print("[persist_failure] err:\n", err)
        return

    job_id = job.get("id")
    attempts_prev = job.get("attempts") or 0

    payload = {
        "status": "failed",
        "error_code": "JOB_FAILED",
        "last_error": err[:4000],
        "attempts": attempts_prev + 1,
        "running_at": None,
        "lease_expires_at": None,
    }

    try:
        print(f"[persist_failure] updating job id={job_id} attempts {attempts_prev} -> {attempts_prev + 1}")
        print(f"[persist_failure] last_error.len={len(err)} (truncated to {len(payload['last_error'])})")
        res = db.update_job(job_id, payload)
        print(f"[persist_failure] update_job result: {res!r}")
    except Exception:
        print("[persist_failure] FATAL: failed to persist last_error")
        print("[persist_failure] traceback:\n", traceback.format_exc())
        print("[persist_failure] original err:\n", err)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true", help="Run a single job then exit")
    ap.add_argument("--loop", action="store_true", help="Run forever")
    ap.add_argument("--interval", type=int, default=30, help="Loop sleep seconds")
    args = ap.parse_args()

    s = Settings.from_env()
    db = SupabaseDB(s.supabase_url, s.supabase_service_role_key)

    def tick() -> bool:
        print("[tick] start")
        job = None
        try:
            db.reap_stale_running_jobs(s.running_timeout_seconds)

            job = db.claim_one_pending_job()
            print(f"[tick] claimed job: {None if not job else job.get('id')}")

            if not job:
                print("[tick] no pending job")
                return False

            run_one_job(db, s, job)
            print("[tick] run_one_job done")
            return True

        except Exception:
            err = traceback.format_exc()
            print("[tick] caught exception; calling persist_failure")
            persist_failure(db, job, err)
            print("[tick] persist_failure returned")
            print("FATAL:", err)
            return False

    if args.once:
        tick()
        return

    if args.loop:
        while True:
            did = tick()
            if not did:
                time.sleep(args.interval)
        return

    ap.print_help()


if __name__ == "__main__":
    main()
