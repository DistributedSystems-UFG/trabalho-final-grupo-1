#!/usr/bin/env sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if command -v pwsh >/dev/null 2>&1; then
  exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/runtime-consistency-test.ps1"
fi
if command -v powershell >/dev/null 2>&1; then
  exec powershell -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/runtime-consistency-test.ps1"
fi
echo "PowerShell Core (pwsh) is required to run this test on Linux/WSL." >&2
echo "Install: https://learn.microsoft.com/powershell/scripting/install/installing-powershell" >&2
exit 127
