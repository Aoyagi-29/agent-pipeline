#!/usr/bin/env bash
set -euo pipefail

# Run on WSL when the phone is connected via USB.
# Starts adb in TCP mode so a remote machine (Cloud Agent) can reach it via SSH tunnel.

LISTEN_PORT="${ADB_BRIDGE_PORT:-5037}"
LISTEN_HOST="${ADB_BRIDGE_HOST:-0.0.0.0}"

echo "==> USB device check (WSL)"
adb kill-server 2>/dev/null || true
adb start-server
adb devices -l

if ! adb devices | tail -n +2 | grep -qv '^$'; then
  echo "ERROR: No USB device detected. Plug in the phone and enable USB debugging."
  exit 1
fi

echo
echo "==> Starting ADB server on ${LISTEN_HOST}:${LISTEN_PORT} (all interfaces)"
echo "    Remote side: export ADB_SERVER_SOCKET=tcp:<this-machine-ip>:${LISTEN_PORT}"
echo "    Or SSH tunnel: ssh -L 5037:127.0.0.1:5037 user@this-machine"
echo
echo "Press Ctrl+C to stop."

exec adb -a -P "${LISTEN_PORT}" nodaemon server
