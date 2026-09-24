#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-}"
PORT="${2:-5555}"

if [[ -z "$HOST" ]]; then
  cat <<'HELP'
Usage:
  ./connect-wireless.sh <phone-ip> [connect-port]

Wireless debugging setup (Android 11+):
  1. Phone: Settings -> Developer options -> Wireless debugging -> ON
  2. Tap "Pair device with pairing code" and note IP, pairing port, and 6-digit code
  3. Pair (once per session):
       adb pair <ip>:<pairing-port> <6-digit-code>
  4. Phone: Wireless debugging -> "IP address & port" (connect port, often 5555)
  5. Connect:
       ./connect-wireless.sh <ip> [connect-port]

Example:
  adb pair 192.168.1.50:37123 123456
  ./connect-wireless.sh 192.168.1.50 5555
HELP
  exit 1
fi

adb start-server
echo "Connecting to ${HOST}:${PORT}..."
adb connect "${HOST}:${PORT}"
adb devices -l
