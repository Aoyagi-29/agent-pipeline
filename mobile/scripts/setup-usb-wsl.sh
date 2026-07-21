#!/usr/bin/env bash
set -euo pipefail

# WSL-specific USB passthrough helper for Android phones.
# Requires: usbipd-win on Windows host (https://learn.microsoft.com/windows/wsl/connect-usb)

if ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "This script is intended for WSL2. On native Linux, plug in USB directly."
fi

echo "==> WSL USB setup for Android (usbipd-win)"
echo
echo "On Windows PowerShell (Admin):"
echo "  winget install dorssel.usbipd-win"
echo "  usbipd list"
echo "  usbipd bind --busid <BUSID>"
echo "  usbipd attach --wsl --busid <BUSID>"
echo
echo "Then in WSL:"
echo "  sudo apt-get install -y android-tools-adb"
echo "  adb devices"
echo
echo "If the device appears, run:"
echo "  ./scripts/check-device.sh"

if command -v adb >/dev/null 2>&1; then
  echo
  echo "Current adb devices:"
  adb devices -l || true
fi
