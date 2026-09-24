#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Installing Android platform-tools (adb)..."
if command -v adb >/dev/null 2>&1; then
  adb version
else
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y android-tools-adb android-tools-fastboot
  else
    echo "ERROR: adb not found and apt-get unavailable. Install Android platform-tools manually."
    exit 1
  fi
fi

echo "==> Building MCP server..."
cd "$ROOT/mcp-server"
npm install
npm run build

echo
echo "Done. Next steps:"
echo "  1. Connect your phone (see mobile/README.md)"
echo "  2. Enable the MCP server in Cursor (see mobile/README.md)"
echo "  3. Ask the agent to run mobile_list_devices"
