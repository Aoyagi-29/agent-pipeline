#!/usr/bin/env bash
set -euo pipefail

echo "==> ADB device check"
adb start-server >/dev/null 2>&1 || true

if [[ -n "${ADB_SERVER_SOCKET:-}" ]]; then
  echo "ADB server: $ADB_SERVER_SOCKET"
else
  echo "ADB server: local (default tcp:5037)"
fi

DEVICES="$(adb devices -l | tail -n +2 | sed '/^$/d')"
if [[ -z "$DEVICES" ]]; then
  echo
  echo "No devices connected."
  echo
  echo "Setup options:"
  echo "  USB (WSL):  ./scripts/setup-usb-wsl.sh"
  echo "  Wireless:   ./scripts/connect-wireless.sh <phone-ip>"
  echo "  Remote:     ./scripts/adb-bridge-ssh.sh (from WSL with USB phone)"
  exit 1
fi

echo
echo "$DEVICES"
echo
echo "Device check OK."
