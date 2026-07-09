#!/usr/bin/env bash
set -euo pipefail

REMOTE_USER="${1:-}"
REMOTE_HOST="${2:-}"
LOCAL_PORT="${ADB_LOCAL_PORT:-5037}"
REMOTE_PORT="${ADB_REMOTE_PORT:-5037}"

if [[ -z "$REMOTE_USER" || -z "$REMOTE_HOST" ]]; then
  cat <<'HELP'
Usage:
  ./adb-bridge-ssh.sh <remote-user> <remote-host>

Creates an SSH reverse tunnel so a remote machine (e.g. Cloud Agent) can use
your local ADB server where the phone is connected via USB.

Prerequisites (WSL):
  1. Phone connected via USB, USB debugging enabled
  2. ./adb-bridge-usb.sh running in another terminal (or local adb server)
  3. SSH access from WSL to the remote host

This script forwards remote port 5037 -> local adb server.

On the remote machine:
  export ADB_SERVER_SOCKET=tcp:127.0.0.1:5037
  adb devices

Example:
  ./adb-bridge-ssh.sh ubuntu cloud-agent-host.example.com
HELP
  exit 1
fi

echo "Opening reverse tunnel: ${REMOTE_HOST}:${REMOTE_PORT} -> localhost:${LOCAL_PORT}"
echo "Keep this terminal open while using mobile tools remotely."
ssh -N -R "${REMOTE_PORT}:127.0.0.1:${LOCAL_PORT}" "${REMOTE_USER}@${REMOTE_HOST}"
