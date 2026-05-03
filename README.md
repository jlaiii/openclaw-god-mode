# ⚡ OpenClaw God Mode

One-command setup for [OpenClaw](https://github.com/openclaw/openclaw) + [Ollama](https://ollama.com). From zero to running bot in minutes — with full system-level control.

[![Linux](https://img.shields.io/badge/Linux-✓-brightgreen?style=flat-square&logo=linux)](./linux)
[![Windows](https://img.shields.io/badge/Windows-✓-blue?style=flat-square&logo=windows)](./windows)

📖 **[Configurator](https://jlaiii.github.io/openclaw-god-mode/configure.html)** · **[Model Manager](https://jlaiii.github.io/openclaw-god-mode/models.html)**

---

## Quick Start

### 🐧 Linux

```bash
git clone https://github.com/jlaiii/openclaw-god-mode.git
cd openclaw-god-mode/linux
chmod +x install.sh
./install.sh
```

**Supported:** Ubuntu 20.04+, Debian 11+, Fedora 35+, Arch, Manjaro

### 🪟 Windows

```powershell
git clone https://github.com/jlaiii/openclaw-god-mode.git
cd openclaw-god-mode\windows
.\install.ps1
```

**Requires:** Windows 10/11, PowerShell 5.1+ (Run as Administrator)

### ⚡ Web Configurator

Generate your install command with a GUI: [jlaiii.github.io/openclaw-god-mode/configure.html](https://jlaiii.github.io/openclaw-god-mode/configure.html)

---

## What It Does

1. **Detects OS** — Identifies distro and package manager
2. **Installs dependencies** — Node.js 22+, git, curl (if missing)
3. **Configures NOPASSWD sudo** — Passwordless `sudo` for non-interactive automation
4. **Installs Ollama** — Official installer, starts service
5. **Pulls default model** — `kimi-k2.6:cloud` with retry logic
6. **Installs OpenClaw** — `npm install -g openclaw`
7. **Configures workspace** — Creates `~/.openclaw/` with multi-agent config
8. **Prompts for tokens** — Discord, Telegram, admin ID + extra whitelist users
9. **Enables channels** — Discord + Telegram (configurable per agent)
10. **Sets up systemd service** — User service, auto-starts on boot
11. **Verifies system access** — Tests shell, packages, network, file write
12. **Prints setup guide** — Discord intents, invite URL, BotFather steps

---

## ⚠️ WARNING: This Is NOT For Everyone

This project removes nearly every safety guardrail OpenClaw ships with by default. It is designed for advanced users who want **maximum, unrestricted system control** from their AI agent. If you do not understand the implications below, **do not use this installer**.

### What This Installer Actually Does

OpenClaw's default install is designed to be safe, sandboxed, and limited:
- Runs as a regular user
- Requires device authentication to access the web UI
- Prompts before running dangerous commands
- Has no elevated system privileges

**This installer strips all of that away:**

| Default OpenClaw Safety | What This Script Changes |
|------------------------|--------------------------|
| User-level execution | **User systemd service** with passwordless `sudo` |
| Device auth required | `dangerouslyDisableDeviceAuth: true` — web UI has no login gate |
| Prompts for approval | Passwordless `sudo` (`NOPASSWD: *** — no human in the loop |
| Limited file access | Full read/write access to **entire filesystem** |
| No package installation | Can `apt/dnf/pacman install` anything without asking |
| Network restricted | Unrestricted network access |
| Sandbox model | **Root shell** model — the AI can modify system configs, create users, wipe drives |

### What This Means in Practice

- The AI agent can `sudo rm -rf /` without any prompt
- The AI agent can install malware, backdoors, or modify SSH keys
- The AI agent can read any file on the system including `/etc/shadow`
- Anyone with Discord/Telegram access to the bot (even whitelisted users) can issue destructive commands
- **There is no audit trail or approval step**

### Who Should Use This

- You run OpenClaw on a **dedicated, isolated machine or VM**
- You **fully trust** everyone in the `allowedUsers` whitelist
- You understand that a compromised token or social-engineered prompt = full system compromise
- You have **backups** and a **recovery plan**

### Who Should NOT Use This

- Anyone running OpenClaw on their daily driver / personal machine
- Anyone who does not understand `sudo`, `systemd`, or Linux permissions
- Anyone sharing the bot with people they do not absolutely trust
- Anyone without isolated infrastructure

**Use the official OpenClaw install instead:** https://github.com/openclaw/openclaw

---

| Feature | Description |
|---------|-------------|
| 🚀 **One-Command Setup** | Single script installs everything and configures bots |
| 🔒 **Whitelist Security** | DMs enabled but restricted to whitelisted Discord IDs only |
| 🤖 **Dual Channels** | Discord + Telegram both configurable per agent |
| ☁️ **Cloud & Local Models** | Defaults to `kimi-k2.6:cloud`, 229 models in catalog |
| 🖥️ **Cross-Platform** | Native scripts for Linux and Windows |
| ⚙️ **System-Level Control** | Passwordless `sudo`, systemd user service, full system access |
| 🔄 **Idempotent** | Safe to run multiple times — detects existing installs and skips duplicates |
| 📝 **Multi-User Whitelist** | Add multiple Discord users during install or edit config later |
| 🤖 **Multi-Agent** | Multiple agents with different models + channels via configurator |
| 📦 **Model Manager** | Web UI to fetch, pull, verify, and manage Ollama models |

---

## Discord Security Model

| Feature | Setting | How It Works |
|---------|---------|--------------|
| **DMs** | `allowDMs: true` | ✅ Enabled — only whitelisted Discord IDs can DM |
| **Groups** | `allowGroups: true` | ✅ Enabled — works in all servers (or whitelisted guild) |
| **Whitelist** | Multi-user | You + any extra users added during setup |
| **Guild lock** | Optional | Restrict to specific server, or leave open |
| **Token storage** | `.env` file | Auto-.gitignored, never committed |
| **Device auth** | Disabled | `dangerouslyDisableDeviceAuth: true` for local use |

Add more whitelisted users anytime by editing `~/.openclaw/config/gateway.yaml`:

```yaml
discord:
  allowedUsers: [123456789, 987654321, 555555555]
```

---

## System-Level Setup

The Linux installer configures full non-interactive system control:

- **Passwordless sudo** — Creates `/etc/sudoers.d/99-openclaw-$USER` with `NOPASSWD: ALL`. Checks for duplicates, validates syntax
- **systemd user service** — `openclaw-gateway.service` auto-starts on boot
- **Access verification** — Tests shell execution, package manager, network, file write
- **Idempotent** — Won't duplicate sudoers entries or overwrite existing service configs

Start/stop the service:

```bash
systemctl --user start openclaw-gateway.service   # Start now
systemctl --user stop openclaw-gateway.service    # Stop
systemctl --user enable openclaw-gateway.service  # Enable on boot (already done)
systemctl --user status openclaw-gateway.service  # Check status
```

---

## After Install

### 1. Set Your Tokens

Edit `~/.openclaw/.env` (Linux) or `%USERPROFILE%\.openclaw\.env` (Windows):

```env
DISCORD_TOKEN=your_discord_bot_token
TELEGRAM_TOKEN=your_telegram_bot_token
ADMIN_DISCORD_ID=your_discord_user_id
```

### 2. Start OpenClaw

```bash
# Manual start (foreground)
openclaw gateway run

# Or use systemd (background)
systemctl --user start openclaw-gateway.service
```

### 3. Verify

```bash
openclaw status                    # Gateway status
ollama list                        # Installed models
systemctl --user status openclaw-gateway.service  # Service status
```

---

## Model Catalog

The installer pulls `kimi-k2.6:cloud` by default. The web Model Manager syncs 229 models from [ollama.com/search](https://ollama.com/search). Switch models by editing `~/.openclaw/openclaw.json` or via the Model Manager.

```yaml
# Cloud models (no local GPU needed)
model: ollama/kimi-k2.6:cloud

# Local models (requires GPU/CPU)
model: ollama/llama3.2
model: ollama/mistral
model: ollama/phi4
```

Pull new models: `ollama pull <model>`

---

## Model Manager

A web UI for managing Ollama models:

- **Fetch** available models from GitHub-hosted catalog
- **Connect** to your Ollama instance (configurable host)
- **Pull** models with streaming progress
- **Verify** models after pull via `/api/tags`
- **Select active** models for OpenClaw agents
- **Remove** models from local Ollama

Open it at: [jlaiii.github.io/openclaw-god-mode/models.html](https://jlaiii.github.io/openclaw-god-mode/models.html)

Or run locally after clone:
```bash
cd openclaw-god-mode/docs
python3 -m http.server 8080
# Open http://localhost:8080/models.html
```

---

## Configurator

Generate install commands with a GUI:

- Add multiple agents with different models
- Set fallback models per agent
- Configure Discord + Telegram per agent
- Pick identity presets (default, hacker, devops, custom)
- Set bind mode, guild lock, extra users
- Shareable URL with all settings encoded

Open it at: [jlaiii.github.io/openclaw-god-mode/configure.html](https://jlaiii.github.io/openclaw-god-mode/configure.html)

---

## Roadmap

- [ ] Docker Compose deployment
- [ ] Windows service auto-start
- [ ] TUI wizard (whiptail/dialog)
- [ ] Auto-update script
- [ ] Backup/restore config
- [ ] Interactive model picker

---

## Contributing

Open an issue or PR: [github.com/jlaiii/openclaw-god-mode](https://github.com/jlaiii/openclaw-god-mode)

---

Built by [@jlaiii](https://github.com/jlaiii) · Not affiliated with OpenClaw or Ollama
