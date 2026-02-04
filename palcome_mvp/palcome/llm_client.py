import time
import random
from typing import Any, Optional

import requests


class OpenAIAPIError(RuntimeError):
    def __init__(self, status_code: int, err_type: str, message: str, raw: Optional[str] = None):
        super().__init__(message)
        self.status_code = status_code
        self.err_type = err_type
        self.message = message
        self.raw = raw


def _safe_parse_openai_error(resp: requests.Response) -> OpenAIAPIError:
    """
    OpenAI互換のエラーフォーマットをできるだけ安全に読む。
    期待外でも job 側に渡せるように OpenAIAPIError に畳む。
    """
    status = resp.status_code
    raw = resp.text
    try:
        j = resp.json()
        # 互換: {"error": {"type": "...", "message": "..."}}
        if isinstance(j, dict) and isinstance(j.get("error"), dict):
            et = str(j["error"].get("type") or "api_error")
            msg = str(j["error"].get("message") or raw)
            return OpenAIAPIError(status, et, msg, raw=raw)
        # 互換: {"message": "..."}
        if isinstance(j, dict) and "message" in j:
            return OpenAIAPIError(status, "api_error", str(j.get("message")), raw=raw)
    except Exception:
        pass
    return OpenAIAPIError(status, "api_error", raw, raw=raw)


def _unwrap_openai_payload(data: Any) -> Any:
    """
    OpenAI互換レスポンスの外箱（id/choices/created...）を剥がし、
    choices[0].message.content を優先して返す。

    response_format=json_object の場合、content が JSON文字列になりやすいので、
    JSONっぽければ dict/list に寄せる。
    """
    # dict で choices を持つなら中身へ
    if isinstance(data, dict) and isinstance(data.get("choices"), list) and data["choices"]:
        c0 = data["choices"][0] or {}
        msg = c0.get("message") or {}
        content = msg.get("content")
        if content is None:
            # 旧形式互換
            content = c0.get("text")

        # content が JSON 文字列ならパース
        if isinstance(content, str):
            t = content.strip()
            if (t.startswith("{") and t.endswith("}")) or (t.startswith("[") and t.endswith("]")):
                try:
                    import json
                    return json.loads(t)
                except Exception:
                    return content
            return content

        # すでに dict/list ならそのまま
        if isinstance(content, (dict, list)):
            return content

        # 解析不能なら外箱を返すより content を返す
        if content is not None:
            return content

    # それ以外はそのまま
    return data


class LLMClient:
    def __init__(self, api_key: str, base_url: str, model: str):
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.model = model

    def _call_with_retry_429(self, fn, max_sleep: float = 30.0, base_sleep: float = 1.0, max_retries: int = 8):
        last_exc = None

        for i in range(max_retries):
            try:
                return fn()
            except OpenAIAPIError as api_err:
                last_exc = api_err
                # 429(rate_limit) は Retry-After 優先 + exponential backoff
                if api_err.status_code != 429:
                    raise

                retry_after = None
                # raw textの方ではなくレスポンスヘッダから読むため、呼び出し元でセットして投げる想定はしない
                # ここでは一般的な backoff のみ
                sleep = min(max_sleep, base_sleep * (2 ** i))
                sleep = sleep + random.uniform(0, 0.3 * sleep)
                time.sleep(sleep)

        if last_exc is not None:
            raise last_exc
        raise RuntimeError("rate limit: exceeded retries")

    def json_call(self, system: str, user: str) -> Any:
        def _do():
            r = requests.post(
                f"{self.base_url}/chat/completions",
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": self.model,
                    "messages": [
                        {"role": "system", "content": system},
                        {"role": "user", "content": user},
                    ],
                    "response_format": {"type": "json_object"},
                },
                timeout=60,
            )

            try:
                r.raise_for_status()
            except requests.HTTPError:
                api_err = _safe_parse_openai_error(r)
                # quota は粘るほど job が汚れるので確定失敗として上げる
                if api_err.err_type == "insufficient_quota":
                    raise api_err
                # 429 以外もここで投げて job 側に理由を渡す
                raise api_err

            try:
                data = r.json()
            except Exception:
                # ここに落ちるときは、JSONとして不正な応答。job 側で観測できる形にする
                return {"raw_text": r.text}

            return _unwrap_openai_payload(data)

        return self._call_with_retry_429(_do)


# Backward-compatible alias (pipeline expects this name)
OpenAIClient = LLMClient
