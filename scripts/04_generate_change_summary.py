#!/usr/bin/env python3
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.error
import urllib.request


DEFAULT_MODEL = "gpt-5-nano"
DEFAULT_ENDPOINT = "https://api.openai.com/v1"
MAX_DIFF_CHARS = 8000
MAX_DIFFSTAT_CHARS = 2000
MAX_OUTPUT_TOKENS = 200


def fail(msg: str) -> None:
    print(f"Error: {msg}", file=sys.stderr)
    raise SystemExit(2)


def load_env_file(env_path: pathlib.Path) -> None:
    if not env_path.is_file():
        return
    try:
        content = env_path.read_text(encoding="utf-8")
    except OSError as exc:
        print("Failed to source .env file; check syntax", file=sys.stderr)
        raise SystemExit(2) from exc
    try:
        for raw_line in content.splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[len("export ") :].lstrip()
            if "=" not in line:
                raise ValueError("missing '='")
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip()
            if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", key):
                raise ValueError("invalid key")
            if value and value[0] in {"'", '"'} and value[-1:] == value[:1]:
                value = value[1:-1]
            if not os.getenv(key):
                os.environ[key] = value
    except Exception as exc:
        print("Failed to source .env file; check syntax", file=sys.stderr)
        raise SystemExit(2) from exc


def run_git(cmd: list[str]) -> str:
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return ""
    return out.decode("utf-8", errors="replace")


def get_repo_root() -> pathlib.Path:
    root = run_git(["git", "rev-parse", "--show-toplevel"]).strip()
    if not root:
        fail("not inside a git repository")
    return pathlib.Path(root)


def resolve_api_key(task_dir: pathlib.Path, root_dir: pathlib.Path) -> str:
    load_env_file(task_dir / ".env")
    load_env_file(root_dir / ".env")
    value = os.getenv("OPENAI_API_KEY", "").strip()
    if value:
        return value
    fail("OPENAI_API_KEY not set")
    return ""


def is_chatgpt_api_enabled() -> bool:
    raw = os.getenv("USE_CHATGPT_API", "").strip().lower()
    return raw in {"1", "true", "yes", "on"}


def truncate(text: str, limit: int) -> tuple[str, bool]:
    if len(text) <= limit:
        return text, False
    return text[:limit], True


def build_prompt(diff_stat: str, diff_body: str, stat_trunc: bool, diff_trunc: bool) -> str:
    header = (
        "あなたは変更点の要約者です。以下のgit diff情報から、変更点を日本語の文章で3-5文で要約してください。"
        "箇条書きは禁止。機密情報やAPIキーの値は絶対に書かない。"
    )
    parts = [header, "", "git diff --stat:", diff_stat or "(no changes)"]
    if stat_trunc:
        parts.append("(diff stat truncated)")
    parts += ["", "git diff (truncated):", diff_body or "(no changes)"]
    if diff_trunc:
        parts.append("(diff truncated)")
    return "\n".join(parts)


def call_openai(prompt: str, api_key: str, endpoint: str, model: str) -> str:
    body = {
        "model": model,
        "input": prompt,
        "max_output_tokens": MAX_OUTPUT_TOKENS,
        "text": {"verbosity": "low"},
    }
    req = urllib.request.Request(
        f"{endpoint.rstrip('/')}/responses",
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={
            "content-type": "application/json",
            "authorization": f"Bearer {api_key}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            raw = res.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        fail(f"OpenAI API call failed: HTTP {exc.code}: {detail[:400]}")
    except urllib.error.URLError as exc:
        fail(f"OpenAI API call failed: {exc.reason}")
    except Exception as exc:
        fail(f"OpenAI API call failed: {exc}")

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"invalid API response JSON: {exc}")

    outputs = payload.get("output")
    if not isinstance(outputs, list):
        fail("OpenAI API returned no output")
    chunks: list[str] = []
    for item in outputs:
        if not isinstance(item, dict):
            continue
        if item.get("type") != "message":
            continue
        for part in item.get("content", []):
            if isinstance(part, dict) and part.get("type") == "output_text":
                text = part.get("text")
                if isinstance(text, str):
                    chunks.append(text)
    out = "\n".join(chunks).strip()
    if not out:
        fail("OpenAI API returned empty summary")
    return out


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: scripts/04_generate_change_summary.py <task-dir>", file=sys.stderr)
        return 2
    task_dir = pathlib.Path(sys.argv[1])
    if not task_dir.is_dir():
        fail(f"directory not found: {task_dir}")

    if not is_chatgpt_api_enabled():
        print("CHANGE_SUMMARY skipped: USE_CHATGPT_API is disabled. Set USE_CHATGPT_API=1 to enable.")
        return 0

    repo_root = get_repo_root()
    api_key = resolve_api_key(task_dir=task_dir, root_dir=repo_root)

    diff_stat = run_git(["git", "diff", "--stat", "HEAD"]).strip()
    diff_body = run_git(["git", "diff", "HEAD"]).strip()
    diff_stat, stat_trunc = truncate(diff_stat, MAX_DIFFSTAT_CHARS)
    diff_body, diff_trunc = truncate(diff_body, MAX_DIFF_CHARS)

    prompt = build_prompt(diff_stat, diff_body, stat_trunc, diff_trunc)
    endpoint = os.getenv("OPENAI_BASE_URL", DEFAULT_ENDPOINT)
    model = os.getenv("CHANGE_SUMMARY_MODEL", DEFAULT_MODEL)
    summary = call_openai(prompt=prompt, api_key=api_key, endpoint=endpoint, model=model)
    print(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
