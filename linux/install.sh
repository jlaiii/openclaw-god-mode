#!/bin/bash
set -euo pipefail

# OpenClaw God Mode — Linux Installer
# Installs: Ollama, OpenClaw, configures bots, pulls models
# DANGER: This script grants root-level AI access. Use only on isolated systems.

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
        enable_ollama_service
        return
    fi
    
    log "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
    
    enable_ollama_service
    ok "Ollama installed"
}

# ─── Enable Ollama systemd service for boot ───
enable_ollama_service() {
    log "Enabling Ollama service for auto-start on boot..."
    
    # Check for system-level ollama service (installed via official script as root)
    if [ -f /etc/systemd/system/ollama.service ]; then
        if systemctl is-enabled ollama.service &>/dev/null; then
            ok "System ollama.service already enabled for boot"
        else
            sudo systemctl enable ollama.service
            ok "System ollama.service enabled for boot"
        fi
        
        # Ensure it's running now
        if ! systemctl is-active ollama.service &>/dev/null; then
            sudo systemctl start ollama.service 2>/dev/null || warn "Could not start system ollama.service"
        fi
        return
    fi
    
    # Check for user-level ollama service
    if [ -f "$HOME/.config/systemd/user/ollama.service" ]; then
        if systemctl --user is-enabled ollama.service &>/dev/null; then
            ok "User ollama.service already enabled for boot"
        else
            systemctl --user enable ollama.service
            ok "User ollama.service enabled for boot"
        fi
        
        # Ensure it's running now
        if ! systemctl --user is-active ollama.service &>/dev/null; then
            systemctl --user start ollama.service 2>/dev/null || warn "Could not start user ollama.service"
        fi
        return
    fi
    
    # Fallback: try to find and enable any ollama service
    if systemctl list-unit-files | grep -q "ollama.service"; then
        sudo systemctl enable ollama.service 2>/dev/null || systemctl --user enable ollama.service 2>/dev/null
        ok "Ollama service enabled for boot (fallback)"
    else
        warn "Ollama service file not found — may need manual enable after install"
        warn "Try: sudo systemctl enable ollama  OR  systemctl --user enable ollama"
    fi
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
    sudo npm install -g openclaw
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
# Generated by OpenClaw God Mode
# DANGER: Full root access enabled. Use only on isolated systems.

controlUi:
  dangerouslyDisableDeviceAuth: true

agents:
  - id: main
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
    # ── Expanded integrations (all disabled by default, fill in tokens to enable) ──
    whatsapp:
      # token: ${WHATSAPP_TOKEN}
      enabled: false
    signal:
      # number: ${SIGNAL_NUMBER}
      enabled: false
    imessage:
      enabled: false
    line:
      # token: ${LINE_TOKEN}
      enabled: false
    zalo:
      # token: ${ZALO_TOKEN}
      enabled: false
    wechat:
      # token: ${WECHAT_TOKEN}
      # appId: ${WECHAT_APP_ID}
      enabled: false
    slack:
      # token: ${SLACK_TOKEN}
      enabled: false
    googlechat:
      # token: ${GOOGLECHAT_TOKEN}
      enabled: false
    msteams:
      # token: ${MSTEAMS_TOKEN}
      enabled: false
    mattermost:
      # token: ${MATTERMOST_TOKEN}
      # url: ${MATTERMOST_URL}
      enabled: false
    nextcloud:
      # token: ${NEXTCLOUD_TOKEN}
      # url: ${NEXTCLOUD_URL}
      enabled: false
    irc:
      # server: ${IRC_SERVER}
      # nick: ${IRC_NICK}
      # password: ${IRC_PASS}
      enabled: false
    matrix:
      # token: ${MATRIX_TOKEN}
      # server: ${MATRIX_SERVER}
      enabled: false
    nostr:
      # privateKey: ${NOSTR_KEY}
      enabled: false
    twitch:
      # token: ${TWITCH_TOKEN}
      # channel: ${TWITCH_CHANNEL}
      enabled: false
    ollama:
      host: http://localhost:11434
EOF
        ok "Config template written to ~/.openclaw/config/gateway.yaml"
    fi
    
    # Create openclaw.json with gateway.mode=local (required by OpenClaw)
    # Also supports multi-agent mode with agents.list
    if [ ! -f "$workspace/openclaw.json" ]; then
        # Check if AGENTS_JSON env var is set (from configurator)
        if [ -n "${AGENTS_JSON:-}" ]; then
            # User provided agent config from configurator — parse and build agents.list
            log "Using agent configuration from configurator..."
            
            # Build agents.list JSON using node (already installed)
            local agents_list
            agents_list="$(echo "$AGENTS_JSON" | node -e '
const agents = JSON.parse(require("fs").readFileSync(0, "utf8"));
const blocks = agents.map(a => {
    const fb = a.fb || [];
    const modelLine = fb.length > 0
        ? `"model": { "primary": ${JSON.stringify(a.m)}, "fallbacks": [${fb.map(f => JSON.stringify(f)).join(", ")}] }`
        : `"model": { "primary": ${JSON.stringify(a.m)} }`;
    const channelsStr = (a.c || ["discord"]).map(c => JSON.stringify(c)).join(", ");
    return `    {\n      "id": ${JSON.stringify(a.id)},\n      ${modelLine},\n      "channels": [${channelsStr}]\n    }`;
});
console.log(blocks.join(",\n"));
' 2>/dev/null || echo '    { "id": "main", "model": { "primary": "ollama/kimi-k2.6:cloud" }, "channels": ["discord", "telegram"] }')"

            cat > "$workspace/openclaw.json" << JSON
{
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace",
      "sandbox": { "mode": "off" }
    },
    "list": [
$agents_list
    ]
  },
  "gateway": {
    "mode": "local",
    "auth": { "mode": "token", "token": "auto-generated-on-first-install" },
    "port": 18789,
    "bind": "loopback",
    "controlUi": {
      "dangerouslyDisableDeviceAuth": true,
      "allowInsecureAuth": true
    }
  },
  "meta": {
    "lastTouchedVersion": "2026.5.2",
    "lastTouchedAt": "auto"
  }
}
JSON
            ok "Multi-agent configuration applied from configurator"
        else
            # Default single-agent config
            cat > "$workspace/openclaw.json" << 'JSON'
{
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace",
      "model": { "primary": "ollama/kimi-k2.6:cloud" },
      "sandbox": { "mode": "off" }
    }
  },
  "gateway": {
    "mode": "local",
    "auth": { "mode": "token", "token": "auto-generated-on-first-install" },
    "port": 18789,
    "bind": "loopback",
    "controlUi": {
      "dangerouslyDisableDeviceAuth": true,
      "allowInsecureAuth": true
    }
  },
  "meta": {
    "lastTouchedVersion": "2026.5.2",
    "lastTouchedAt": "auto"
  }
}
JSON
            ok "Gateway mode set to local in ~/.openclaw/openclaw.json"
            ok "Single-agent defaults configured"
        fi
    fi
    
    # Copy default BOOTSTRAP.md to workspace so OpenClaw skips onboarding
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Check if user provided an identity preset via env var
    if [ -n "${IDENTITY_PRESET:-}" ] && [ -f "$script_dir/BOOTSTRAP.md" ]; then
        mkdir -p "$workspace/workspace"
        
        case "$IDENTITY_PRESET" in
            default|hacker|devops|coder)
                # The preset content will be injected by the one-liner
                # For now, use the default BOOTSTRAP.md
                cp "$script_dir/BOOTSTRAP.md" "$workspace/workspace/BOOTSTRAP.md"
                ok "Identity preset '$IDENTITY_PRESET' applied — OpenClaw will use this personality"
                ;;
            custom)
                if [ -n "${CUSTOM_IDENTITY:-}" ]; then
                    echo "$CUSTOM_IDENTITY" > "$workspace/workspace/BOOTSTRAP.md"
                    ok "Custom identity applied — OpenClaw will use your personality"
                else
                    warn "CUSTOM_IDENTITY not set for 'custom' preset — using default"
                    cp "$script_dir/BOOTSTRAP.md" "$workspace/workspace/BOOTSTRAP.md"
                fi
                ;;
            *)
                cp "$script_dir/BOOTSTRAP.md" "$workspace/workspace/BOOTSTRAP.md"
                ok "Default BOOTSTRAP.md copied — OpenClaw will use default identity"
                ;;
        esac
    elif [ -f "$script_dir/BOOTSTRAP.md" ] && [ ! -f "$workspace/workspace/BOOTSTRAP.md" ]; then
        # Only copy default if no BOOTSTRAP.md exists yet
        # This lets OpenClaw ask "who are you?" if user hasn't set identity
        mkdir -p "$workspace/workspace"
        cp "$script_dir/BOOTSTRAP.md" "$workspace/workspace/BOOTSTRAP.md"
        ok "Default BOOTSTRAP.md copied — OpenClaw will use default identity"
        ok "Delete ~/.openclaw/workspace/BOOTSTRAP.md and restart to let OpenClaw ask your identity"
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
# Only asks for tokens that are actually needed based on enabled channels
prompt_config() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  OpenClaw God Mode — Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Detect which channels are enabled from AGENTS_JSON
    local discord_needed=false
    local telegram_needed=false
    if [ -n "${AGENTS_JSON:-}" ]; then
        # Parse channels from agent config using node
        local detected_channels
        detected_channels="$(echo "$AGENTS_JSON" | node -e '
const agents = JSON.parse(require("fs").readFileSync(0, "utf8"));
const allCh = new Set(agents.flatMap(a => a.c || []));
console.log(Array.from(allCh).join(" "));
' 2>/dev/null || echo "")"
        if echo "$detected_channels" | grep -qw "discord"; then
            discord_needed=true
        fi
        if echo "$detected_channels" | grep -qw "telegram"; then
            telegram_needed=true
        fi
    fi
    
    # Check if running non-interactively (no TTY)
    local non_interactive=false
    if ! tty -s 2>/dev/null || [ ! -t 0 ]; then
        non_interactive=true
    fi
    
    # Check for environment variables first
    discord_token="${DISCORD_TOKEN:-}"
    telegram_token="${TELEGRAM_TOKEN:-}"
    admin_id="${ADMIN_DISCORD_ID:-}"
    guild_id="${DISCORD_GUILD_ID:-}"
    local extra_users="${DISCORD_EXTRA_USERS:-}"
    
    # Only warn about missing Discord token if Discord is actually needed
    if [ "$non_interactive" = true ] && [ "$discord_needed" = true ] && [ -z "$discord_token" ]; then
        warn "Non-interactive mode: Discord token required but DISCORD_TOKEN not set."
        warn "Continuing with placeholder. You MUST edit ~/.openclaw/config/gateway.yaml manually."
        discord_token="YOUR_DISCORD_BOT_TOKEN"
        admin_id="${admin_id:-YOUR_ADMIN_ID}"
        guild_id="${guild_id:-}"
    fi
    
    # Only prompt if interactive
    if [ "$non_interactive" = true ]; then
        ok "Non-interactive mode — skipping prompts. Using env vars or defaults."
        [ -z "$discord_token" ] && discord_token=""
        [ -z "$admin_id" ] && admin_id=""
    else
        if [ "$discord_needed" = true ] && [ -z "$discord_token" ]; then
            read -rp "Discord Bot Token: " discord_token
        elif [ "$discord_needed" = true ]; then
            ok "Discord token provided via DISCORD_TOKEN environment variable"
        fi
        
        if [ "$telegram_needed" = true ] && [ -z "$telegram_token" ]; then
            read -rp "Telegram Bot Token: " telegram_token
        elif [ "$telegram_needed" = true ]; then
            ok "Telegram token provided via TELEGRAM_TOKEN environment variable"
        fi
        
        if [ "$discord_needed" = true ] && [ -z "$admin_id" ]; then
            read -rp "Your Discord User ID (admin/owner): " admin_id
        elif [ "$discord_needed" = true ]; then
            ok "Admin ID provided via ADMIN_DISCORD_ID environment variable"
        fi
    fi
    
    # Build whitelist array
    local whitelist=()
    [ -n "$admin_id" ] && whitelist+=("$admin_id")
    
    # Add extra users from env var (comma-separated)
    if [ -n "$extra_users" ]; then
        IFS=',' read -ra extra_arr <<< "$extra_users"
        for eid in "${extra_arr[@]}"; do
            eid=$(echo "$eid" | tr -d ' ')
            [ -n "$eid" ] && whitelist+=("$eid")
        done
        ok "Added ${#extra_arr[@]} extra user(s) from DISCORD_EXTRA_USERS"
    fi
    
    # Allow adding more users (only if interactive)
    if [ "$non_interactive" = false ]; then
        echo ""
        echo "Add more Discord users to DM whitelist (leave blank when done):"
        while true; do
            read -rp "  Discord User ID to whitelist: " extra_id
            [ -z "$extra_id" ] && break
            whitelist+=("$extra_id")
        done
    fi
    
    if [ "$non_interactive" = true ] && [ -z "$guild_id" ]; then
        ok "Non-interactive mode — guild ID left empty (any server allowed)"
    elif [ -z "$guild_id" ] && [ "$discord_needed" = true ]; then
        read -rp "Discord Guild ID to whitelist (leave blank for any server): " guild_id
    elif [ -n "$guild_id" ]; then
        ok "Guild ID provided via DISCORD_GUILD_ID environment variable"
    fi
    
    # Write to .env — only include vars that are actually set
    local env_file="$HOME/.openclaw/.env"
    {
        echo "# Updated by OpenClaw God Mode"
        [ -n "$discord_token" ] && echo "DISCORD_TOKEN=$discord_token"
        [ -n "$telegram_token" ] && echo "TELEGRAM_TOKEN=$telegram_token"
        [ -n "$admin_id" ] && echo "ADMIN_DISCORD_ID=$admin_id"
        [ -n "$guild_id" ] && echo "DISCORD_GUILD_ID=$guild_id"
        # Expanded integrations
        [ -n "${WHATSAPP_TOKEN:-}" ] && echo "WHATSAPP_TOKEN=$WHATSAPP_TOKEN"
        [ -n "${SIGNAL_NUMBER:-}" ] && echo "SIGNAL_NUMBER=$SIGNAL_NUMBER"
        [ -n "${LINE_TOKEN:-}" ] && echo "LINE_TOKEN=$LINE_TOKEN"
        [ -n "${ZALO_TOKEN:-}" ] && echo "ZALO_TOKEN=$ZALO_TOKEN"
        [ -n "${WECHAT_TOKEN:-}" ] && echo "WECHAT_TOKEN=$WECHAT_TOKEN"
        [ -n "${WECHAT_APP_ID:-}" ] && echo "WECHAT_APP_ID=$WECHAT_APP_ID"
        [ -n "${SLACK_TOKEN:-}" ] && echo "SLACK_TOKEN=$SLACK_TOKEN"
        [ -n "${GOOGLECHAT_TOKEN:-}" ] && echo "GOOGLECHAT_TOKEN=$GOOGLECHAT_TOKEN"
        [ -n "${MSTEAMS_TOKEN:-}" ] && echo "MSTEAMS_TOKEN=$MSTEAMS_TOKEN"
        [ -n "${MATTERMOST_TOKEN:-}" ] && echo "MATTERMOST_TOKEN=$MATTERMOST_TOKEN"
        [ -n "${MATTERMOST_URL:-}" ] && echo "MATTERMOST_URL=$MATTERMOST_URL"
        [ -n "${NEXTCLOUD_TOKEN:-}" ] && echo "NEXTCLOUD_TOKEN=$NEXTCLOUD_TOKEN"
        [ -n "${NEXTCLOUD_URL:-}" ] && echo "NEXTCLOUD_URL=$NEXTCLOUD_URL"
        [ -n "${IRC_SERVER:-}" ] && echo "IRC_SERVER=$IRC_SERVER"
        [ -n "${IRC_NICK:-}" ] && echo "IRC_NICK=$IRC_NICK"
        [ -n "${IRC_PASS:-}" ] && echo "IRC_PASS=$IRC_PASS"
        [ -n "${MATRIX_TOKEN:-}" ] && echo "MATRIX_TOKEN=$MATRIX_TOKEN"
        [ -n "${MATRIX_SERVER:-}" ] && echo "MATRIX_SERVER=$MATRIX_SERVER"
        [ -n "${NOSTR_KEY:-}" ] && echo "NOSTR_KEY=$NOSTR_KEY"
        [ -n "${TWITCH_TOKEN:-}" ] && echo "TWITCH_TOKEN=$TWITCH_TOKEN"
        [ -n "${TWITCH_CHANNEL:-}" ] && echo "TWITCH_CHANNEL=$TWITCH_CHANNEL"
    } > "$env_file"
    
    # Update config with values
    local config_file="$HOME/.openclaw/config/gateway.yaml"
    
    # Only inject Discord config if discord is needed
    if [ "$discord_needed" = true ] && [ -n "$discord_token" ]; then
        sed -i "s|\${DISCORD_TOKEN}|$discord_token|" "$config_file"
    fi
    if [ "$telegram_needed" = true ] && [ -n "$telegram_token" ]; then
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
    if [ "$discord_needed" = true ]; then
        echo ""
        echo "  Whitelisted users for DMs: ${whitelist[*]:-(none)}"
        echo "  Guild restriction: ${guild_id:-(any server)}"
        echo "  Groups: enabled for all servers"
        echo ""
    fi
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

# ─── Non-interactive sudo NOPASSWD setup ───
setup_nopasswd_sudo() {
    local user="${SUDO_USER:-$USER}"
    local sudoers_file="/etc/sudoers.d/99-openclaw-$user"
    
    if [ -f "$sudoers_file" ]; then
        ok "NOPASSWD sudo already configured for $user"
        return 0
    fi
    
    log "Configuring passwordless sudo for OpenClaw user: $user"
    
    # Check if user already has NOPASSWD anywhere in sudoers
    if sudo grep -qE "^$user\s+.*NOPASSWD" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
        ok "NOPASSWD sudo already exists for $user"
        return 0
    fi
    
    # Create dedicated sudoers file
    echo "$user ALL=(ALL) NOPASSWD: ALL" | sudo tee "$sudoers_file" >/dev/null
    sudo chmod 440 "$sudoers_file"
    sudo visudo -c || err "sudoers syntax check failed"
    
    ok "NOPASSWD sudo configured: $sudoers_file"
}

# ─── Persist OpenClaw service ───
persist_openclaw_service() {
    log "Setting up OpenClaw systemd service..."
    
    # Use openclaw's built-in installer (creates proper user service)
    openclaw gateway install --force 2>&1 | grep -E "Installed|already|Reinstall|No gateway token" || true
    
    # Enable for boot
    if systemctl --user is-enabled openclaw-gateway.service &>/dev/null; then
        ok "OpenClaw user service enabled for boot"
    else
        systemctl --user enable openclaw-gateway.service
        ok "OpenClaw user service enabled for boot"
    fi
}

# ─── Auto-start OpenClaw if tokens are configured ───
start_openclaw_if_ready() {
    # Check if tokens are set (not still ${VAR} placeholders)
    if grep -q '\${DISCORD_TOKEN}' "$HOME/.openclaw/config/gateway.yaml" 2>/dev/null; then
        warn "Discord token not set — skipping auto-start"
        warn "Set your token in ~/.openclaw/.env then run: systemctl --user start openclaw-gateway.service"
        return 0
    fi
    
    log "Starting OpenClaw service..."
    if systemctl --user start openclaw-gateway.service 2>/dev/null; then
        ok "OpenClaw service started"
        sleep 2
        if systemctl --user is-active openclaw-gateway.service &>/dev/null; then
            ok "OpenClaw running and healthy"
        else
            warn "OpenClaw service started but may not be healthy yet"
        fi
    else
        warn "Could not start OpenClaw service. Start manually: systemctl --user start openclaw-gateway.service"
    fi
}

# ─── Verify system execution capability ───
verify_system_access() {
    log "Verifying system execution capabilities..."
    
    # Test shell execution
    if ! bash -c "true" 2>/dev/null; then
        err "Shell execution test failed"
    fi
    
    # Test sudo without password
    if ! sudo -n true 2>/dev/null; then
        warn "sudo without password not working yet — may need re-login"
    else
        ok "Passwordless sudo verified"
    fi
    
    # Test package manager access
    case $OS in
        ubuntu|debian) sudo -n apt-get update -qq &>/dev/null && ok "apt access verified" || warn "apt access failed" ;;
        fedora|rhel|centos) sudo -n dnf repoquery &>/dev/null && ok "dnf access verified" || warn "dnf access failed" ;;
        arch|manjaro) sudo -n pacman -Sy &>/dev/null && ok "pacman access verified" || warn "pacman access failed" ;;
    esac
    
    # Test network
    if curl -s --max-time 5 https://github.com &>/dev/null; then
        ok "Network access verified"
    else
        warn "Network check failed"
    fi
    
    # Test file write to system path
    if sudo -n touch /usr/local/.openclaw_test 2>/dev/null && sudo -n rm /usr/local/.openclaw_test 2>/dev/null; then
        ok "System file write access verified"
    else
        warn "System file write test failed"
    fi
}

# ─── Migrate workspace to root if running as root ───
migrate_workspace_if_root() {
    if [ "$EUID" -ne 0 ]; then
        return 0
    fi
    
    local target_home="/root/.openclaw"
    local source_home=""
    
    # Find original user's home if available
    if [ -n "${SUDO_USER:-}" ]; then
        source_home=$(eval echo "~$SUDO_USER")/.openclaw
    fi
    
    if [ -d "$source_home" ] && [ ! -d "$target_home" ]; then
        log "Migrating workspace from $SUDO_USER to root..."
        cp -r "$source_home" "$target_home"
        chown -R root:root "$target_home"
        ok "Workspace migrated to $target_home"
    elif [ ! -d "$target_home" ]; then
        mkdir -p "$target_home"
        chown -R root:root "$target_home"
    fi
}

# ─── Print Final Status ───
print_status() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  OpenClaw God Mode — Setup Complete"
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
    echo "System:     Passwordless sudo configured"
    echo "Service:    systemd user service (auto-start, auto-restart)"
    echo ""
    echo "Next steps:"
    echo "  1. Review ~/.openclaw/config/gateway.yaml"
    echo "  2. Check service: systemctl --user status openclaw-gateway.service"
    echo ""
    echo "Commands:"
    echo "  ollama list                            # List models"
    echo "  ollama pull <model>                    # Pull a model"
    echo "  openclaw status                        # Check gateway status"
    echo "  openclaw gateway run                   # Manual foreground start"
    echo "  systemctl --user start openclaw-gateway.service   # Start via systemd"
    echo "  systemctl --user stop openclaw-gateway.service    # Stop via systemd"
    echo ""
    echo "⚠️  IMPORTANT: Log out and back in for NOPASSWD sudo to take full effect."
    echo "   Or run: exec sudo -i"
    echo ""
}

# ─── Main ───
main() {
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║   OpenClaw God Mode — Linux Setup   ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    
    detect_os
    check_deps
    
    # Privilege setup (idempotent)
    setup_nopasswd_sudo
    
    install_ollama
    pull_default_model
    install_openclaw
    configure_openclaw
    prompt_config
    
    # System-level setup
    migrate_workspace_if_root
    persist_openclaw_service
    verify_system_access
    start_openclaw_if_ready
    
    discord_helper
    telegram_helper
    print_status
}

# Run
main "$@"
