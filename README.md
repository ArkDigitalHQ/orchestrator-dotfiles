# orchestrator-dotfiles

Install scripts for the Orchestrator Supervisor — the agent that runs on any machine you want to control from the dashboard.

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/ArkDigitalHQ/orchestrator-dotfiles/main/install.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/ArkDigitalHQ/orchestrator-dotfiles.git
cd orchestrator-dotfiles
./install.sh
```

## What it does

1. Checks Node.js 22+ is installed
2. Prompts for your `ANTHROPIC_API_KEY` and a machine name
3. Clones and builds `orchestrator-control/packages/supervisor`
4. Installs a background service (launchd on macOS, systemd on Linux)
5. The supervisor connects to the control plane and appears in the dashboard

## Update

Re-run `install.sh` on a machine that already has the supervisor — it pulls the latest code and rebuilds without touching your `.env`.

## Uninstall

```bash
./uninstall.sh
```

## Requirements

- Node.js 22+
- macOS or Linux
- An Anthropic API key

## Dashboard

https://orchestrator-dashboard-flostack-ai.vercel.app
