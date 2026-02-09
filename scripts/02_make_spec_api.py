#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request


DEFAULT_MODEL = "claude-3-5-sonnet-latest"
DEFAULT_ENDPOINT = "https://api.anthropic.com/v1/messages"
PROMPT_HEADER = """あなたは仕様策定者です。GOAL.md を読み取り、実装者向けの SPEC.md を作成してください。

出力ルール:
- 実装は禁止
- 出力は SPEC.md の本文のみ（前後の説明・コードブロック外の文章は禁止）
- 見出しはこの順序で固定: Scope / Acceptance Criteria / Interfaces / Error Handling / Security/Safety Constraints / Test Plan
- 各見出しには具体的かつ検証可能な内容を書く
- 余計な説明や挨拶は書かない
"""


def fail(msg: str) -> None:
    print(f"Error: {msg}", file=sys.stderr)
    raise SystemExit(2)


def read_goal(task_dir: pathlib.Path) -> str:
    goal = task_dir / "GOAL.md"
    if not goal.is_file():
        fail(f"GOAL.md not found in {task_dir}")
    try:
        return goal.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"failed to read GOAL.md: {exc}")
    return ""


def unwrap_spec_text(payload: dict) -> str:
    content = payload.get("content")
    if not isinstance(content, list):
        return ""
    chunks = []
    for part in content:
        if isinstance(part, dict) and part.get("type") == "text":
            text = part.get("text")
            if isinstance(text, str):
                chunks.append(text)
    out = "\n".join(chunks).strip()
    if out.startswith("```"):
        lines = out.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        out = "\n".join(lines).strip()
    return out


def call_claude(goal_text: str, model: str, endpoint: str, timeout: int) -> str:
    mock_spec = os.getenv("CLAUDE_API_MOCK_SPEC", "").strip()
    mock_spec_path = os.getenv("CLAUDE_API_MOCK_SPEC_PATH", "").strip()
    if mock_spec:
        return mock_spec
    if mock_spec_path:
        p = pathlib.Path(mock_spec_path)
        try:
            return p.read_text(encoding="utf-8")
        except OSError as exc:
            fail(f"failed to read CLAUDE_API_MOCK_SPEC_PATH: {exc}")

    api_key = (
        os.getenv("CLAUDE_API_KEY", "").strip()
        or os.getenv("ANTHROPIC_API_KEY", "").strip()
    )
    if not api_key:
        fail("CLAUDE_API_KEY or ANTHROPIC_API_KEY is required")

    body = {
        "model": model,
        "max_tokens": 3000,
        "messages": [
            {
                "role": "user",
                "content": (
                    f"{PROMPT_HEADER}\n\nGOAL.md:\n```\n{goal_text}\n```"
                ),
            }
        ],
    }
    req = urllib.request.Request(
        endpoint,
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={
            "content-type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            raw = res.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        fail(f"Claude API HTTP {exc.code}: {detail[:400]}")
    except urllib.error.URLError as exc:
        fail(f"Claude API connection failed: {exc.reason}")
    except Exception as exc:
        fail(f"Claude API call failed: {exc}")

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"invalid API response JSON: {exc}")

    text = unwrap_spec_text(payload)
    if not text.strip():
        fail("Claude API returned empty SPEC")
    return text


def write_spec(task_dir: pathlib.Path, spec_text: str) -> None:
    spec = task_dir / "SPEC.md"
    tmp = task_dir / ".SPEC.md.tmp"
    try:
        tmp.write_text(spec_text.rstrip() + "\n", encoding="utf-8")
        tmp.replace(spec)
    except OSError as exc:
        fail(f"failed to write SPEC.md: {exc}")


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="02_make_spec_api.py",
        description="Generate tasks/<id>/SPEC.md from GOAL.md via Claude API.",
    )
    parser.add_argument("task_dir")
    parser.add_argument(
        "--timeout",
        type=int,
        default=120,
        help="HTTP timeout seconds (default: 120)",
    )
    args = parser.parse_args()

    task_dir = pathlib.Path(args.task_dir)
    if not task_dir.is_dir():
        fail(f"directory not found: {task_dir}")

    model = os.getenv("CLAUDE_MODEL", DEFAULT_MODEL).strip() or DEFAULT_MODEL
    endpoint = os.getenv("CLAUDE_API_ENDPOINT", DEFAULT_ENDPOINT).strip() or DEFAULT_ENDPOINT

    goal_text = read_goal(task_dir)
    spec_text = call_claude(goal_text=goal_text, model=model, endpoint=endpoint, timeout=args.timeout)
    write_spec(task_dir=task_dir, spec_text=spec_text)
    print(f"Wrote: {task_dir / 'SPEC.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
