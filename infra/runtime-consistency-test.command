#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if ! command -v pwsh >/dev/null 2>&1; then
  echo "PowerShell Core (pwsh) is required to run this test on macOS." >&2
  echo "Install with Homebrew: brew install --cask powershell" >&2
  exit 127
fi
exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/runtime-consistency-test.ps1"
