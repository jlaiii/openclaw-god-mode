#!/bin/bash
set -euo pipefail

# OpenClaw Plug & Play — Linux Installer
# Installs: Ollama, OpenClaw, configures bots, pulls models

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$(dirname "$SCRIPT_DIR")/shared"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[*]${NC} $*"; }
ok()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# ─── Detect OS ───
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        err "Cannot detect OS. Need /etc/os-release."
    fi
    log "Detected OS: $OS $VER"
}

# ─── Check Dependencies ───
check_deps() {
    log "Checking dependencies..."
    
    NEED_PACKAGES=()
    
    if ! command -v curl &>/dev/null; then
        NEED_PACKAGES+=(curl)
    fi
    if ! command -v git &>/dev/null; then
        NEED_PACKAGES+=(git)
    fi
    if ! command -v node &>/dev/null || [ "$(node -v | cut -d'v' -f2 | cut -d'.' -f1)" -lt 22 ]; then
        NEED_NODE=1
    fi
    
    if [ ${#NEED_PACKAGES[@]} -gt 0 ] || [ -n "${NEED_NODE:-}" ]; then
        install_packages
    fi
    
    ok "Dependencies ready"
}

# ─── Install System Packages ───
install_packages() {
    log "Installing packages: ${NEED_PACKAGES[*]:-none}, Node.js 22+..."
    
    case $OS in
        ubuntu|debian)
            sudo apt-get update -qq
            sudo apt-get install -y -qq curl git ca-certificates gnupg
            
            if [ -n "${NEED_NODE:-}" ]; then
                curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
                sudo apt-get install -y -qq nodejs
            fi
            ;;
            
        fedora|rhel|centos)
            sudo dnf install -y -q curl git ca-certificates
            
            if [ -n "${NEED_NODE:-}" ]; then
                sudo dnf module reset -y nodejs
                sudo dnf module install -y nodejs:22
            fi
            ;;
            
        arch|manjaro)
            sudo pacman -Sy --noconfirm --quiet curl git ca-certificates
            
            if [ -n "${NEED_NODE:-}" ]; then
                sudo pacman -S --noconfirm --quiet nodejs npm
            fi
            ;;
            
        *)
            err "Unsupported OS: $OS. Supported: ubuntu, debian, fedora, rhel, centos, arch, manjaro"
            ;;
    esac
    
    ok "Packages installed"
}

# ─── Install Ollama ───
install_ollama() {
    if command -v ollama &>/dev/null; then
        ok "Ollama already installed: $(ollama --version)"
        return
    fi
    
    log "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
    
    # Start service
    if systemctl --user is-active ollama &>/dev/null || systemctl is-active ollama &>/dev/null; then
        ok "Ollama service already running"
    else
        log "Starting Ollama service..."
        if systemctl --user start ollama 2>/dev/null || sudo systemctl start ollama 2>/dev/null; then
            ok "Ollama service started"
        else
            warn "Could not start Ollama via systemd. It may need manual start."
        fi
    fi
    
    ok "Ollama installed"
}

# ─── Sync Model Catalog ───
sync_model_catalog() {
    log "Syncing model catalog from ollama.com..."
    
    local catalog_file="$SHARED_DIR/model-catalog.json"
    mkdir -p "$(dirname "$catalog_file")"
    
    # Fetch cloud models from ollama.com
    curl -sL "https://ollama.com/api/tags?c=cloud" > /tmp/ollama-cloud-raw.json 2>/dev/null || true
    
    # Build catalog with metadata
    cat > "$catalog_file" << 'CATALOG'
{
  "updated": "TIMESTAMP",
  "sources": {
    "cloud": "https://ollama.com/search?c=cloud",
    "local": "https://ollama.com/library"
  },
  "models": {
    "recommended": {
      "id": "kimi-k2.6:cloud",
      "name": "Kimi K2.6 (Cloud)",
      "provider": "ollama",
      "tags": ["cloud", "multilingual", "long-context"],
      "description": "Moonshot AI's Kimi K2.6 via Ollama cloud"
    },
    "cloud": [],
    "local": [
      {"id": "llama3.2", "name": "Llama 3.2", "size": "2B-70B", "tags": ["meta", "general"]},
      {"id": "qwen2.5", "name": "Qwen 2.5", "size": "0.5B-72B", "tags": ["alibaba", "multilingual"]},
      {"id": "mistral", "name": "Mistral", "size": "7B", "tags": ["mistral-ai", "general"]},
      {"id": "gemma2", "name": "Gemma 2", "size": "2B-27B", "tags": ["google", "general"]},
      {"id": "phi4", "name": "Phi-4", "size": "14B", "tags": ["microsoft", "reasoning"]}
    ]
  }
}
CATALOG

    # Replace timestamp
    sed -i "s/TIMESTAMP/$(date -u +%Y-%m-%dT%H:%M:%SZ)/" "$catalog_file"
    
    # Try to populate cloud models from API response
    if [ -f /tmp/ollama-cloud-raw.json ] && [ -s /tmp/ollama-cloud-raw.json ]; then
        log "Cloud model data fetched successfully"
    fi
    
    ok "Model catalog saved to shared/model-catalog.json"
}

# ─── Pull Default Model ───
pull_default_model() {
    log "Pulling default model: kimi-k2.6:cloud"
    
    if ollama list 2>/dev/null | grep -q "kimi-k2.6"; then
        ok "Model kimi-k2.6 already available"
        return
    fi
    
    # Wait for ollama to be ready
    local retries=30
    while ! ollama list &>/dev/null && [ $retries -gt 0 ]; do
        sleep 1
        ((retries--))
    done
    
    if ollama pull kimi-k2.6:cloud 2>/dev/null; then
        ok "Model kimi-k2.6:cloud pulled"
    else
        warn "Could not pull kimi-k2.6:cloud. You may need to pull manually later."
        warn "Run: ollama pull kimi-k2.6:cloud"
    fi
}

# ─── Install OpenClaw ───
install_openclaw() {
    if command -v openclaw &>/dev/null; then
        ok "OpenClaw already installed: $(openclaw --version 2>/dev/null || echo 'unknown')"
        return
    fi
    
    log "Installing OpenClaw..."
    npm install -g openclaw
    ok "OpenClaw installed"
}

# ─── Configure OpenClaw ───
configure_openclaw() {
    log "Configuring OpenClaw..."
    
    local workspace="$HOME/.openclaw"
    mkdir -p "$workspace"
    
    # Write initial config if not exists
    local config_dir="$workspace/config"
    mkdir -p "$config_dir"
    
    if [ ! -f "$config_dir/gateway.yaml" ]; then
        cat > "$config_dir/gateway.yaml" << 'EOF'
# OpenClaw Gateway Configuration
# Generated by OpenClaw Plug & Play

controlUi:
  dangerouslyDisableDeviceAuth: true

agents:
  - id: main
    name: NanoBot
    model: ollama/kimi-k2.6:cloud
    channels:
      - discord
      - telegram
    discord:
      token: ${DISCORD_TOKEN}
      guilds: []
      allowDMs: true
      allowGroups: true
      allowedUsers: [${ADMIN_DISCORD_ID}]
    telegram:
      token: ${TELEGRAM_TOKEN}
    ollama:
      host: http://localhost:11434
EOF
        ok "Config template written to ~/.openclaw/config/gateway.yaml"
    fi
    
    # Write .env template
    cat > "$workspace/.env" << 'EOF'
# OpenClaw Environment Variables
# Set your tokens here or export them before running

# DISCORD_TOKEN=your_discord_bot_token_here
# TELEGRAM_TOKEN=your_telegram_bot_token_here
# ADMIN_DISCORD_ID=your_discord_user_id
EOF
    
    ok "OpenClaw workspace ready at ~/.openclaw"
}

# ─── Prompt for Tokens and Whitelist ───
prompt_config() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  OpenClaw Plug & Play — Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    read -rp "Discord Bot Token: " discord_token
    read -rp "Telegram Bot Token (leave blank to skip): " telegram_token
    read -rp "Your Discord User ID (admin/owner): " admin_id
    
    # Build whitelist array
    local whitelist=()
    [ -n "$admin_id" ] && whitelist+=("$admin_id")
    
    # Allow adding more users
    echo ""
    echo "Add more Discord users to DM whitelist (leave blank when done):"
    while true; do
        read -rp "  Discord User ID to whitelist: " extra_id
        [ -z "$extra_id" ] && break
        whitelist+=("$extra_id")
    done
    
    read -rp "Discord Guild ID to whitelist (leave blank for any server): " guild_id
    
    # Write to .env
    local env_file="$HOME/.openclaw/.env"
    {
        echo "# Updated by OpenClaw Plug & Play"
        [ -n "$discord_token" ] && echo "DISCORD_TOKEN=$discord_token"
        [ -n "$telegram_token" ] && echo "TELEGRAM_TOKEN=$telegram_token"
        [ -n "$admin_id" ] && echo "ADMIN_DISCORD_ID=$admin_id"
        [ -n "$guild_id" ] && echo "DISCORD_GUILD_ID=$guild_id"
    } > "$env_file"
    
    # Update config with values
    local config_file="$HOME/.openclaw/config/gateway.yaml"
    
    if [ -n "$discord_token" ]; then
        sed -i "s|\${DISCORD_TOKEN}|$discord_token|" "$config_file"
    fi
    if [ -n "$telegram_token" ]; then
        sed -i "s|\${TELEGRAM_TOKEN}|$telegram_token|" "$config_file"
    fi
    if [ ${#whitelist[@]} -gt 0 ]; then
        local whitelist_str=$(printf ",%s" "${whitelist[@]}")
        whitelist_str="${whitelist_str:1}"  # remove leading comma
        sed -i "s|allowedUsers: \[\${ADMIN_DISCORD_ID}\]|allowedUsers: [$whitelist_str]|" "$config_file"
        sed -i "s|\${ADMIN_DISCORD_ID}|$admin_id|" "$config_file"
    fi
    if [ -n "$guild_id" ]; then
        sed -i "s|guilds: \[\]|guilds: [$guild_id]|" "$config_file"
    fi
    
    ok "Configuration saved!"
    
    # Show whitelist summary
    echo ""
    echo "  Whitelisted users for DMs: ${whitelist[*]:-(none)}"
    echo "  Guild restriction: ${guild_id:-(any server)}"
    echo "  Groups: enabled for all servers"
    echo ""
}

# ─── Print Discord Setup Helper ───
discord_helper() {
    local perms="274877910080"  # Send Messages, Read, Embed, Reactions, etc.
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Discord Bot Setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Go to: https://discord.com/developers/applications"
    echo "2. Create New Application → Bot"
    echo "3. Enable these Privileged Gateway Intents:"
    echo "   ✓ MESSAGE CONTENT INTENT"
    echo "   ✓ SERVER MEMBERS INTENT"
    echo "   ✓ PRESENCE INTENT"
    echo "4. Copy your Bot Token (reset if needed)"
    echo "5. Get Application ID from General Information"
    echo ""
    echo "Invite URL (replace YOUR_CLIENT_ID):"
    echo "https://discord.com/oauth2/authorize?client_id=YOUR_CLIENT_ID&permissions=$perms&integration_type=0&scope=bot+applications.commands"
    echo ""
    echo "Discord Settings (configured):"
    echo "   • DMs:        ENABLED — whitelisted users only"
    echo "   • Groups:     ENABLED — all servers (or whitelisted guild)"
    echo "   • Admin:      Your Discord ID + any extra users you added"
    echo "   • Guild:      Any server, or restricted to whitelisted guild"
    echo ""
    echo "To add more whitelisted users later, edit:"
    echo "   ~/.openclaw/config/gateway.yaml"
    echo "   Change: allowedUsers: [id1, id2, id3]"
    echo ""
}

# ─── Print Telegram Setup Helper ───
telegram_helper() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Telegram Bot Setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Message @BotFather on Telegram"
    echo "2. Send /newbot and follow prompts"
    echo "3. Copy the HTTP API token"
    echo "4. Token saved to ~/.openclaw/.env"
    echo ""
}

# ─── Print Final Status ───
print_status() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  OpenClaw Plug & Play — Setup Complete"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Ollama:     $(ollama --version 2>/dev/null || echo 'check manually')"
    echo "OpenClaw:   $(openclaw --version 2>/dev/null || echo 'check manually')"
    echo "Workspace:  ~/.openclaw"
    echo "Config:     ~/.openclaw/config/gateway.yaml"
    echo "Env file:   ~/.openclaw/.env"
    echo ""
    echo "Channels:   Discord + Telegram (both enabled)"
    echo "Discord:    DMs ON (whitelisted users only), Groups ON"
    echo ""
    echo "Next steps:"
    echo "  1. Review ~/.openclaw/config/gateway.yaml"
    echo "  2. Start OpenClaw: openclaw gateway start"
    echo ""
    echo "Commands:"
    echo "  ollama list              # List models"
    echo "  ollama pull <model>      # Pull a model"
    echo "  openclaw status          # Check status"
    echo "  openclaw gateway start   # Start the gateway"
    echo ""
}

# ─── Main ───
main() {
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║   OpenClaw Plug & Play — Linux Setup   ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    
    detect_os
    check_deps
    install_ollama
    sync_model_catalog
    pull_default_model
    install_openclaw
    configure_openclaw
    prompt_config
    discord_helper
    telegram_helper
    print_status
}

# Run
main "$@"
