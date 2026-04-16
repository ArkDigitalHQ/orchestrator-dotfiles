#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="com.orchestrator.supervisor"
INSTALL_DIR="$HOME/.orchestrator"
OS="$(uname -s)"

echo "Stopping and removing Orchestrator Supervisor..."

if [ "$OS" = "Darwin" ]; then
  PLIST="$HOME/Library/LaunchAgents/$SERVICE_NAME.plist"
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "✓ launchd service removed"
elif [ "$OS" = "Linux" ]; then
  sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  sudo rm -f "/etc/systemd/system/$SERVICE_NAME.service"
  sudo systemctl daemon-reload
  echo "✓ systemd service removed"
fi

rm -rf "$INSTALL_DIR"
echo "✓ Install directory removed"
echo ""
echo "Orchestrator Supervisor uninstalled."
