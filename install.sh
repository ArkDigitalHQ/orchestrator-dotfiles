#!/usr/bin/env bash
set -euo pipefail

# ── Orchestrator Supervisor Installer ────────────────────────────────────────
# Installs the supervisor as a background service on macOS (launchd) or
# Linux (systemd). Run as your normal user — sudo only used when needed.

REPO="https://github.com/ArkDigitalHQ/orchestrator-control.git"
INSTALL_DIR="$HOME/.orchestrator"
SERVICE_NAME="com.orchestrator.supervisor"
NODE_MIN=22

red()    { echo -e "\033[0;31m$*\033[0m"; }
green()  { echo -e "\033[0;32m$*\033[0m"; }
yellow() { echo -e "\033[0;33m$*\033[0m"; }
bold()   { echo -e "\033[1m$*\033[0m"; }

bold "=== Orchestrator Supervisor Installer ==="
echo ""

# ── 1. Check Node.js ──────────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  red "Node.js not found. Install Node.js $NODE_MIN+ from https://nodejs.org and re-run."
  exit 1
fi

NODE_VER=$(node -e "process.stdout.write(process.versions.node.split('.')[0])")
if [ "$NODE_VER" -lt "$NODE_MIN" ]; then
  red "Node.js $NODE_MIN+ required (found $NODE_VER). Please upgrade."
  exit 1
fi
green "✓ Node.js $NODE_VER"

# ── 2. Check pnpm ────────────────────────────────────────────────────────────
if ! command -v pnpm &>/dev/null; then
  yellow "Installing pnpm..."
  npm install -g pnpm@9
fi
green "✓ pnpm $(pnpm --version)"

# ── 3. Collect env vars ───────────────────────────────────────────────────────
ENV_FILE="$INSTALL_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  yellow "Existing install found at $INSTALL_DIR — updating code only."
  UPDATE_ONLY=true
else
  UPDATE_ONLY=false
  echo ""
  bold "Enter your configuration:"
  echo ""

  read -rp "  ANTHROPIC_API_KEY: " ANTHROPIC_API_KEY </dev/tty
  [ -z "$ANTHROPIC_API_KEY" ] && { red "ANTHROPIC_API_KEY is required"; exit 1; }

  MACHINE_ID_DEFAULT=$(hostname -s)
  read -rp "  MACHINE_ID [$MACHINE_ID_DEFAULT]: " MACHINE_ID </dev/tty
  MACHINE_ID="${MACHINE_ID:-$MACHINE_ID_DEFAULT}"

  CONTROL_PLANE_URL="wss://control-plane-production-89e4.up.railway.app"
  SHARED_SECRET="5c816a1149107258cc44b7cf71b62176f1e9ddf7c144faf95be47bd28a7103b7"

  read -rp "  MAX_BUDGET_USD [5]: " MAX_BUDGET_USD </dev/tty
  MAX_BUDGET_USD="${MAX_BUDGET_USD:-5}"

  read -rp "  MAX_TURNS [40]: " MAX_TURNS </dev/tty
  MAX_TURNS="${MAX_TURNS:-40}"
fi

# ── 4. Clone / update repo ────────────────────────────────────────────────────
echo ""
if [ -d "$INSTALL_DIR/repo" ]; then
  yellow "Updating repo..."
  git -C "$INSTALL_DIR/repo" pull --ff-only
else
  yellow "Cloning orchestrator-control..."
  mkdir -p "$INSTALL_DIR"
  git clone --depth 1 "$REPO" "$INSTALL_DIR/repo"
fi
green "✓ Repo ready"

# ── 5. Build supervisor ───────────────────────────────────────────────────────
yellow "Installing dependencies and building..."
cd "$INSTALL_DIR/repo"
pnpm install --frozen-lockfile
pnpm --filter @orchestrator/shared build
pnpm --filter @orchestrator/supervisor build
green "✓ Build complete"

# ── 6. Write .env ─────────────────────────────────────────────────────────────
if [ "$UPDATE_ONLY" = false ]; then
  cat > "$ENV_FILE" << ENV
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
MACHINE_ID=$MACHINE_ID
CONTROL_PLANE_URL=$CONTROL_PLANE_URL
SHARED_SECRET=$SHARED_SECRET
MAX_BUDGET_USD=$MAX_BUDGET_USD
MAX_TURNS=$MAX_TURNS
PERMISSION_TIMEOUT_MS=600000
ENV
  chmod 600 "$ENV_FILE"
  green "✓ Config written to $ENV_FILE"
fi

SUPERVISOR_BIN="$INSTALL_DIR/repo/packages/supervisor/dist/index.js"

# ── 7. Install service ────────────────────────────────────────────────────────
OS="$(uname -s)"

if [ "$OS" = "Darwin" ]; then
  PLIST_DIR="$HOME/Library/LaunchAgents"
  PLIST="$PLIST_DIR/$SERVICE_NAME.plist"
  mkdir -p "$PLIST_DIR"

  # Stop existing if running
  launchctl unload "$PLIST" 2>/dev/null || true

  cat > "$PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$SERVICE_NAME</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(which node)</string>
    <string>$SUPERVISOR_BIN</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
$(while IFS='=' read -r k v; do
    [[ "$k" =~ ^#|^$ ]] && continue
    echo "    <key>$k</key><string>$v</string>"
  done < "$ENV_FILE")
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$INSTALL_DIR/supervisor.log</string>
  <key>StandardErrorPath</key>
  <string>$INSTALL_DIR/supervisor.err</string>
</dict>
</plist>
PLIST

  launchctl load "$PLIST"
  green "✓ launchd service loaded: $SERVICE_NAME"

elif [ "$OS" = "Linux" ]; then
  SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
  ENV_ARGS=$(while IFS='=' read -r k v; do
    [[ "$k" =~ ^#|^$ ]] && continue
    echo "Environment=\"$k=$v\""
  done < "$ENV_FILE")

  sudo tee "$SERVICE_FILE" > /dev/null << UNIT
[Unit]
Description=Orchestrator Supervisor
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=$(which node) $SUPERVISOR_BIN
$ENV_ARGS
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

  sudo systemctl daemon-reload
  sudo systemctl enable "$SERVICE_NAME"
  sudo systemctl restart "$SERVICE_NAME"
  green "✓ systemd service enabled: $SERVICE_NAME"

else
  red "Unsupported OS: $OS"
  exit 1
fi

echo ""
green "=== Installation complete! ==="
echo ""
echo "  Machine ID : $( [ "$UPDATE_ONLY" = false ] && echo "$MACHINE_ID" || grep MACHINE_ID "$ENV_FILE" | cut -d= -f2)"
echo "  Logs       : $INSTALL_DIR/supervisor.log"
echo "  Config     : $ENV_FILE"
echo ""
echo "  Dashboard  : https://orchestrator-dashboard-flostack-ai.vercel.app"
echo ""
