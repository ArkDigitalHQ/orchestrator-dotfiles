# orchestrator-dotfiles

Install scripts for the Orchestrator Supervisor — runs a Claude agent on any machine and connects it to the dashboard.

## Install in a Codespace (or any Linux machine)

```bash
ANTHROPIC_API_KEY=sk-ant-... bash <(curl -fsSL https://raw.githubusercontent.com/ArkDigitalHQ/orchestrator-dotfiles/main/install.sh)
```

> **Note:** Use `bash <(curl ...)` — not `curl ... | bash`. The parentheses form is required because the script reads interactive input.

The script will prompt for a machine name and budget limits (press Enter to accept defaults), then:

1. Clone and build the supervisor from [orchestrator-control](https://github.com/ArkDigitalHQ/orchestrator-control)
2. Write credentials to `~/.orchestrator/.env`
3. Start the supervisor in the background

Your machine appears in the dashboard within a few seconds.

## Dashboard

**https://orchestrator-dashboard-flostack-ai.vercel.app**

## Check logs

```bash
tail -f ~/.orchestrator/supervisor.log
```

## Update

Re-run the same install command — it pulls the latest code and restarts without touching your `.env`.

## Stop

```bash
kill $(cat ~/.orchestrator/supervisor.pid)
```

## Uninstall

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ArkDigitalHQ/orchestrator-dotfiles/main/uninstall.sh)
```

## Requirements

- Node.js 22+
- An Anthropic API key
