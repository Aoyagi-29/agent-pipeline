import traceback
from datetime import datetime, timezone
from typing import Any, Dict

from .db_supabase import SupabaseDB
from .config import Settings
from .llm_client import OpenAIClient
from .schemas import SCORE_RESULT_SCHEMA, NORMALIZED_SCHEMA
from .prompts import (
    score_system_prompt, score_constraints_text, rakuten_url_prompt,
    ingredient_extract_prompt, normalize_prompt
)
from .score import finalize_and_validate


def run_one_job(db: SupabaseDB, s: Settings, job: Dict[str, Any]) -> None:
    job_id = job["id"]
    db.set_running(job_id)

    llm = OpenAIClient(s.openai_api_key, s.openai_base_url, s.openai_model)

    try:
        patch: Dict[str, Any] = {
            "last_run_at": datetime.now(timezone.utc).isoformat(),
        }
        db.update_job(job_id, patch)
        # 1) rakuten_url
        if not job.get("rakuten_url"):
            sys = "You are a helpful assistant. Output JSON only."
            usr = rakuten_url_prompt(job["brand_name"], job["product_name"])
            r = llm.json_call(sys, usr)
            db.update_job(job_id, {"rakuten_url": r.get("rakuten_url"), "error_detail": None, "error_code": None})
            job["rakuten_url"] = r.get("rakuten_url")

        # 2) ingredients_raw
        if not job.get("ingredients_raw"):
            sys = "You extract cosmetics ingredient lists. Output JSON only."
            usr = ingredient_extract_prompt(job["brand_name"], job["product_name"], job.get("rakuten_url"))
            r = llm.json_call(sys, usr)
            db.update_job(job_id, {"ingredients_raw": r, "error_detail": None, "error_code": None})
            job["ingredients_raw"] = r

        # 3) ingredients_normalized
        if not job.get("ingredients_normalized"):
            sys = "You normalize cosmetics ingredients. Output JSON only."
            ingr = (job["ingredients_raw"] or {}).get("ingredients_list_jp") or []
            usr = normalize_prompt(ingr)
            r = llm.json_call(sys, usr)
            db.update_job(job_id, {"ingredients_normalized": r, "error_detail": None, "error_code": None})
            job["ingredients_normalized"] = r

        # 4) scoring_result (with auto-repair retry up to 2)
        if not job.get("scoring_result"):
            sys = score_system_prompt()
            normalized = job["ingredients_normalized"]
            import json

            input_json = json.dumps(normalized, ensure_ascii=False)
            user = f"Normalized ingredients JSON:\n{input_json}\nReturn score_result JSON."
            last_err = None
            for attempt in range(1, 3):  # 1..2
                try:
                    out = llm.json_call(sys, user)
                    out2 = finalize_and_validate(out, SCORE_RESULT_SCHEMA)
                    db.update_job(job_id, {"scoring_result": out2, "error_detail": None, "error_code": None})
                    job["scoring_result"] = out2
                    last_err = None
                    break
                except Exception as e:
                    last_err = e
                    # auto-repair: tell model the validation error + allowed keys
                    user = (
                        "Your previous JSON was invalid.\n"
                        f"Error detail: {str(e)}\n"
                        f"Original input JSON:\n{input_json}\n"
                        f"{score_constraints_text()}\n"
                        "Fix and re-output JSON ONLY."
                    )
            if last_err is not None:
                raise last_err

        db.set_done(job_id)

    except Exception as e:
        db.set_error(job_id, "JOB_FAILED", {
            "message": str(e),
            "traceback": traceback.format_exc(),
        })
        return
