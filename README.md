# ⚡ OpenClaw Plug & Play

One-command setup for [OpenClaw](https://github.com/openclaw/openclaw) + [Ollama](https://ollama.com). From zero to running bot in minutes.

[![Linux](https://img.shields.io/badge/Linux-✓-brightgreen?style=flat-square&logo=linux)](./linux)
[![Windows](https://img.shields.io/badge/Windows-✓-blue?style=flat-square&logo=windows)](./windows)
[![Docker](https://img.shields.io/badge/Docker-WIP-yellow?style=flat-square&logo=docker)](./docker)

📖 **[Documentation Site](https://jlaiii.github.io/openclaw-plug-and-play)**

---

## Quick Start

### 🐧 Linux

```bash
git clone https://github.com/jlaiii/openclaw-plug-and-play.git
cd openclaw-plug-and-play/linux
chmod +x install.sh
./install.sh
```

**Supported:** Ubuntu 20.04+, Debian 11+, Fedora 35+, Arch, Manjaro

### 🪟 Windows

```powershell
git clone https://github.com/jlaiii/openclaw-plug-and-play.git
cd openclaw-plug-and-play\windows
.\install.ps1
```

**Requires:** Windows 10/11, PowerShell 5.1+ (Run as Administrator)

---

## What It Does

1. **Detects OS** — Identifies distro/package manager
2. **Installs dependencies** — Node.js 22+, git, curl (if missing)
3. **Installs Ollama** — Official installer, starts service
4. **Pulls default model** — `kimi-k2.6:cloud` with retry logic
5. **Installs OpenClaw** — `npm install -g openclaw`
6. **Configures workspace** — Creates `~/.openclaw/` with defaults
7. **Prompts for tokens** — Discord, Telegram, admin ID + extra whitelist users
8. **Enables both channels** — Discord + Telegram active
9. **Prints setup guide** — Discord intents, invite URL, BotFather steps

---

## Discord Security Model

| Feature | Setting | How It Works |
|---------|---------|--------------|
| **DMs** | ✅ Enabled | Only whitelisted Discord IDs can DM the bot |
| **Groups** | ✅ Enabled | Works in all servers (or whitelisted guild if set) |
| **Whitelist** | Multi-user | You + any extra users you add during setup |
| **Guild lock** | Optional | Restrict to specific server, or leave open |

Add more whitelisted users anytime by editing `~/.openclaw/config/gateway.yaml`:

```yaml
discord:
  allowedUsers: [123456789, 987654321, 555555555]
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
openclaw gateway start
```

### 3. Verify

```bash
openclaw status
ollama list
```

---

## Model Catalog

The installer syncs models from [ollama.com/search?c=cloud](https://ollama.com/search?c=cloud). Switch models by editing `~/.openclaw/config/gateway.yaml`:

```yaml
# Cloud models (no local GPU needed)
model: ollama/kimi-k2.6:cloud
model: ollama/qwen2.5:cloud

# Local models (requires GPU/CPU)
model: ollama/llama3.2
model: ollama/mistral
model: ollama/phi4
```

---

## Roadmap

- [ ] Docker Compose deployment
- [ ] Systemd auto-start service
- [ ] TUI wizard (whiptail/dialog)
- [ ] Auto-update script
- [ ] Backup/restore config
- [ ] Interactive model picker

---

## Contributing

Open an issue or PR: [github.com/jlaiii/openclaw-plug-and-play](https://github.com/jlaiii/openclaw-plug-and-play)

---

Built by [@jlaiii](https://github.com/jlaiii) · Not affiliated with OpenClaw or Ollama
