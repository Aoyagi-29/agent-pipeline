from datetime import datetime, timezone
from typing import Any, Dict, Optional

import requests


class SupabaseDB:
    def __init__(self, supabase_url: str, service_role_key: str):
        self.base = supabase_url.rstrip("/") + "/rest/v1"
        self.h = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        }

    def claim_one_pending_job(self) -> Optional[Dict[str, Any]]:
        url = f"{self.base}/rpc/claim_scoring_job"
        r = requests.post(url, headers=self.h, json={}, timeout=30)
        r.raise_for_status()
        rows = r.json()
        return rows[0] if rows else None

    def reap_stale_running_jobs(self, running_timeout_seconds: int) -> int:
        url = f"{self.base}/rpc/reap_stale_scoring_jobs"
        payload = {"running_timeout_seconds": running_timeout_seconds}
        r = requests.post(url, headers=self.h, json=payload, timeout=30)
        r.raise_for_status()
        data = r.json()
        if isinstance(data, dict) and "reaped_count" in data:
            return int(data["reaped_count"])
        if isinstance(data, list) and data:
            return int(data[0].get("reaped_count", 0))
        return 0

    def update_job(self, job_id: str, patch: Dict[str, Any]) -> None:
        url = f"{self.base}/scoring_jobs"
        params = {"id": f"eq.{job_id}"}
        def _strip_openai_envelope(v):
            # OpenAI外箱(dict)なら choices[0].message.content へ落とす
            if isinstance(v, dict) and "choices" in v and isinstance(v.get("choices"), list) and v["choices"]:
                c0 = v["choices"][0] or {}
                msg = c0.get("message") or {}
                content = msg.get("content")
                if content is None:
                    content = c0.get("text")
                return _strip_openai_envelope(content)
        
            # JSON文字列なら dict/list に（失敗ならそのまま）
            if isinstance(v, str):
                s = v.strip()
                if (s.startswith("{") and s.endswith("}")) or (s.startswith("[") and s.endswith("]")):
                    try:
                        import json
                        return _strip_openai_envelope(json.loads(s))
                    except Exception:
                        return v
                return v
        
            return v
        
        patch = {k: _strip_openai_envelope(v) for k, v in patch.items()}
        # None を落とす実装がどこかにあっても、ここで収束させる
        # running_at / lease_expires_at は明示的NULLを通す
        patch = {k: v for k, v in patch.items() if (v is not None) or (k in ("running_at","lease_expires_at"))}
        
        import os
        debug = os.getenv("DEBUG_SUPABASE") == "1"
        r = requests.patch(url, headers=self.h, params=params, json=patch, timeout=30)

        # 400/401/403 でも本文を省略しないため、raise_for_status の前に必ず出す
        if debug:
            print("SUPABASE_UPDATE_URL:", f"{url}?id=eq.{job_id}")
            print("SUPABASE_UPDATE_STATUS:", r.status_code)
            print("SUPABASE_UPDATE_TEXT:", r.text)

        r.raise_for_status()

    def set_running(self, job_id: str) -> None:
        self.update_job(
            job_id,
            {
                "status": "running",
                "running_at": datetime.now(timezone.utc).isoformat(),
            },
        )

    def set_done(self, job_id: str) -> None:
        self.update_job(job_id, {"status": "succeeded", "running_at": None, "lease_expires_at": None})

    def set_error(self, job_id: str, code: str, detail: Dict[str, Any]) -> None:
        # NOTE: DB側 status が check constraint で制限されている想定。
        # "error" が許可されない環境があるため "failed" を使う。
        self.update_job(
            job_id,
            {
                "status": "failed",
                "error_code": code,
                "error_detail": detail,
            },
        )
