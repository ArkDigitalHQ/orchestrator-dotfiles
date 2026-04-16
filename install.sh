#!/usr/bin/env bash
set -euo pipefail

# ── Orchestrator Supervisor Installer ────────────────────────────────────────
# Usage (interactive):
#   bash install.sh
# Usage (non-interactive / Codespaces):
#   ANTHROPIC_API_KEY=sk-ant-... bash <(curl -fsSL https://raw.githubusercontent.com/ArkDigitalHQ/orchestrator-dotfiles/main/install.sh)

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
  yellow "Existing install found — updating code only."
  UPDATE_ONLY=true
else
  UPDATE_ONLY=false

  # Helper: prompt interactively if stdin is a terminal, else require env var
  prompt_or_env() {
    local var_name="$1"
    local prompt_text="$2"
    local default_val="${3:-}"
    local current="${!var_name:-}"

    if [ -n "$current" ]; then
      return
    fi

    if [ -t 0 ]; then
      if [ -n "$default_val" ]; then
        read -rp "  $prompt_text [$default_val]: " input
        eval "$var_name=\"${input:-$default_val}\""
      else
        read -rp "  $prompt_text: " input
        eval "$var_name=\"$input\""
      fi
    else
      if [ -n "$default_val" ]; then
        eval "$var_name=\"$default_val\""
      else
        red ""
        red "Non-interactive mode: set $var_name as an environment variable."
        red ""
        red "  $var_name=your-value bash <(curl -fsSL https://raw.githubusercontent.com/ArkDigitalHQ/orchestrator-dotfiles/main/install.sh)"
        red ""
        exit 1
      fi
    fi
  }

  echo ""
  bold "Configuration:"
  echo ""

  ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
  MACHINE_ID="${MACHINE_ID:-${CODESPACE_NAME:-}}"
  MAX_BUDGET_USD="${MAX_BUDGET_USD:-}"
  MAX_TURNS="${MAX_TURNS:-}"

  prompt_or_env ANTHROPIC_API_KEY "ANTHROPIC_API_KEY"
  [ -z "$ANTHROPIC_API_KEY" ] && { red "ANTHROPIC_API_KEY is required."; exit 1; }

  MACHINE_ID_DEFAULT=$(hostname -s 2>/dev/null || echo "machine")
  prompt_or_env MACHINE_ID "MACHINE_ID" "${CODESPACE_NAME:-$MACHINE_ID_DEFAULT}"

  prompt_or_env MAX_BUDGET_USD "MAX_BUDGET_USD" "5"
  prompt_or_env MAX_TURNS "MAX_TURNS" "40"

  CONTROL_PLANE_URL="wss://control-plane-production-89e4.up.railway.app"
  SHARED_SECRET="5c816a1149107258cc44b7cf71b62176f1e9ddf7c144faf95be47bd28a7103b7"
fi

# ── 4. Clone / update repo ────────────────────────────────────────────────────
echo ""
if [ -d "$INSTALL_DIR/repo/.git" ]; then
  yellow "Updating repo..."
  git -C "$INSTALL_DIR/repo" pull --ff-only
else
  yellow "Cloning orchestrator-control..."
  mkdir -p "$INSTALL_DIR"
  # Use GITHUB_TOKEN if available (set automatically in Codespaces)
  CLONE_URL="$REPO"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    CLONE_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/ArkDigitalHQ/orchestrator-control.git"
  fi
  git clone --depth 1 "$CLONE_URL" "$INSTALL_DIR/repo"
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
  mkdir -p "$INSTALL_DIR"
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

# ── 7. Stop any existing nohup-launched supervisor ────────────────────────────
if [ -f "$INSTALL_DIR/supervisor.pid" ]; then
  OLD_PID=$(cat "$INSTALL_DIR/supervisor.pid")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    yellow "Stopping previous supervisor (PID $OLD_PID)..."
    kill "$OLD_PID" 2>/dev/null || true
    sleep 1
  fi
  rm -f "$INSTALL_DIR/supervisor.pid"
fi

# ── 8. Install / start service ────────────────────────────────────────────────
OS="$(uname -s)"

if [ "$OS" = "Darwin" ]; then
  # ── macOS: launchd ──────────────────────────────────────────────────────────
  PLIST_DIR="$HOME/Library/LaunchAgents"
  PLIST="$PLIST_DIR/$SERVICE_NAME.plist"
  mkdir -p "$PLIST_DIR"
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
    printf "    <key>%s</key><string>%s</string>\n" "$k" "$v"
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
  green "✓ launchd service loaded"

elif [ "$OS" = "Linux" ]; then
  # ── Linux: always use nohup (systemd is unavailable/stubbed in Codespaces) ──
  yellow "Starting supervisor with nohup..."
  set -o allexport
  source "$ENV_FILE"
  set +o allexport

  nohup node "$SUPERVISOR_BIN" \
    >> "$INSTALL_DIR/supervisor.log" 2>&1 &
  echo $! > "$INSTALL_DIR/supervisor.pid"
  sleep 2

  SUPERVISOR_PID=$(cat "$INSTALL_DIR/supervisor.pid" 2>/dev/null)
  if [ -n "$SUPERVISOR_PID" ] && kill -0 "$SUPERVISOR_PID" 2>/dev/null; then
    SUPERVISOR_PID=$(cat "$INSTALL_DIR/supervisor.pid" 2>/dev/null || echo "unknown")
    green "✓ Supervisor running (PID $SUPERVISOR_PID)"
  else
    red "Supervisor failed to start. Check logs:"
    tail -20 "$INSTALL_DIR/supervisor.log" || true
    exit 1
  fi
else
  red "Unsupported OS: $OS"
  exit 1
fi

echo ""
green "=== Installation complete! ==="
echo ""
echo "  Machine ID : $(grep MACHINE_ID "$ENV_FILE" | cut -d= -f2)"
echo "  Logs       : tail -f $INSTALL_DIR/supervisor.log"
echo "  Config     : $ENV_FILE"
echo "  Dashboard  : https://orchestrator-dashboard-flostack-ai.vercel.app"
echo ""
