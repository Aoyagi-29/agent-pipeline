#!/usr/bin/env bash
# Shared model/thinking resolution for agent-pipeline orchestration.
# Source this file; do not execute it directly.
#
# Precedence (highest first):
#   1. Explicit env already set in the shell
#   2. Values from repo .env (loaded by caller)
#   3. Built-in defaults
#
# Defaults:
#   AGENT_BACKEND=pi
#   AGENT_MODEL=openai-codex/gpt-5.5
#   AGENT_THINKING=xhigh
#   CODEX_MODEL=gpt-5.5  (codex CLI fallback / legacy)

agent_model_defaults() {
  local thinking_was_set=0
  local model_was_set=0
  local codex_was_set=0

  if [[ -n "${AGENT_THINKING+x}" && -n "${AGENT_THINKING}" ]]; then
    thinking_was_set=1
  fi
  if [[ -n "${AGENT_THINKING_SET:-}" ]]; then
    thinking_was_set=1
  fi
  if [[ -n "${AGENT_MODEL+x}" && -n "${AGENT_MODEL}" ]]; then
    model_was_set=1
  fi
  if [[ -n "${CODEX_MODEL+x}" && -n "${CODEX_MODEL}" ]]; then
    codex_was_set=1
  fi

  AGENT_BACKEND="${AGENT_BACKEND:-pi}"
  AGENT_PROVIDER="${AGENT_PROVIDER:-openai-codex}"
  AGENT_MODEL="${AGENT_MODEL:-openai-codex/gpt-5.5}"
  AGENT_THINKING="${AGENT_THINKING:-xhigh}"

  # Allow shorthand: AGENT_MODEL=openai-codex/gpt-5.5:xhigh
  if [[ "$AGENT_MODEL" == *:* ]]; then
    local model_part thinking_part
    model_part="${AGENT_MODEL%:*}"
    thinking_part="${AGENT_MODEL##*:}"
    if [[ -n "$model_part" && -n "$thinking_part" ]]; then
      case "$thinking_part" in
        off|minimal|low|medium|high|xhigh)
          AGENT_MODEL="$model_part"
          # Shorthand fills thinking only when AGENT_THINKING was not explicitly set
          if [[ "$thinking_was_set" -eq 0 ]]; then
            AGENT_THINKING="$thinking_part"
          fi
          ;;
      esac
    fi
  fi

  # If model is bare (no provider/), prefix with AGENT_PROVIDER
  if [[ "$AGENT_MODEL" != */* ]]; then
    AGENT_MODEL="${AGENT_PROVIDER}/${AGENT_MODEL}"
  fi

  # Derive provider from model when possible
  if [[ "$AGENT_MODEL" == */* ]]; then
    AGENT_PROVIDER="${AGENT_MODEL%%/*}"
  fi

  # Legacy codex CLI model id (no provider prefix)
  if [[ "$codex_was_set" -eq 0 ]]; then
    if [[ "$AGENT_MODEL" == */* ]]; then
      CODEX_MODEL="${AGENT_MODEL#*/}"
    else
      CODEX_MODEL="$AGENT_MODEL"
    fi
  fi

  export AGENT_BACKEND AGENT_PROVIDER AGENT_MODEL AGENT_THINKING CODEX_MODEL
  # silence unused (kept for callers that set model_was_set intentionally)
  : "${model_was_set}"
}

agent_model_print() {
  agent_model_defaults
  echo "AGENT_BACKEND=${AGENT_BACKEND}"
  echo "AGENT_PROVIDER=${AGENT_PROVIDER}"
  echo "AGENT_MODEL=${AGENT_MODEL}"
  echo "AGENT_THINKING=${AGENT_THINKING}"
  echo "CODEX_MODEL=${CODEX_MODEL}"
}

# Build argv for: pi --model ... --thinking ...
# Usage: eval "$(agent_pi_model_args)"; pi "${PI_MODEL_ARGS[@]}" -p "..."
agent_pi_model_args() {
  agent_model_defaults
  PI_MODEL_ARGS=(--model "$AGENT_MODEL" --thinking "$AGENT_THINKING")
  # Export as a printable declaration for callers that prefer eval
  printf 'PI_MODEL_ARGS=(--model %q --thinking %q)\n' "$AGENT_MODEL" "$AGENT_THINKING"
}

# Resolve which binary to use for implementation.
# Prints: pi | codex | custom
agent_resolve_backend() {
  agent_model_defaults
  case "${AGENT_BACKEND}" in
    pi|PI)
      if command -v pi >/dev/null 2>&1; then
        echo "pi"
        return 0
      fi
      if command -v codex >/dev/null 2>&1; then
        echo "warn: pi not found; falling back to codex CLI" >&2
        echo "codex"
        return 0
      fi
      echo "missing" >&2
      return 1
      ;;
    codex|CODEX|codex-cli)
      echo "codex"
      return 0
      ;;
    *)
      echo "${AGENT_BACKEND}"
      return 0
      ;;
  esac
}
