import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    supabase_url: str
    supabase_service_role_key: str
    openai_api_key: str
    openai_base_url: str
    openai_model: str
    running_timeout_seconds: int

    @staticmethod
    def from_env() -> "Settings":
        supabase_url = os.environ.get("SUPABASE_URL", "").strip()
        supabase_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
        openai_key = os.environ.get("OPENAI_API_KEY", "").strip()
        base_url = os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1").strip()
        model = os.environ.get("OPENAI_MODEL", "gpt-4.1-mini").strip()
        running_timeout_seconds = int(os.environ.get("RUNNING_TIMEOUT_SECONDS", "3600"))

        if not supabase_url or not supabase_key:
            raise RuntimeError("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY")
        if not openai_key:
            raise RuntimeError("Missing OPENAI_API_KEY")

        return Settings(
            supabase_url=supabase_url,
            supabase_service_role_key=supabase_key,
            openai_api_key=openai_key,
            openai_base_url=base_url,
            openai_model=model,
            running_timeout_seconds=running_timeout_seconds,
        )
