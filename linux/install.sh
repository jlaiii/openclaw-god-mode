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
# Generated by OpenClaw God Mode
# DANGER: Full root access enabled. Use only on isolated systems.

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
    echo "  OpenClaw God Mode — Configuration"
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
        echo "# Updated by OpenClaw God Mode"
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

# ─── Persist OpenClaw service with elevated privileges ───
persist_openclaw_service() {
    log "Setting up OpenClaw systemd service with watchdog..."
    
    local service_file="/etc/systemd/system/openclaw.service"
    local user="${SUDO_USER:-$USER}"
    local home_dir
    home_dir=$(eval echo "~$user")
    
    if [ -f "$service_file" ]; then
        # Check if service is already correct
        if grep -q "User=root" "$service_file" 2>/dev/null; then
            ok "OpenClaw service already configured for root"
        else
            log "Updating OpenClaw service to run as root..."
            sudo sed -i 's/^User=.*/User=root/' "$service_file"
            sudo sed -i 's/^Group=.*/Group=root/' "$service_file"
            sudo systemctl daemon-reload
        fi
    else
        cat << 'SERVICE' | sudo tee "$service_file" >/dev/null
[Unit]
Description=OpenClaw Gateway (God Mode)
After=network.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/root/.openclaw
Environment="HOME=/root"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/usr/bin/openclaw gateway start
ExecStop=/usr/bin/openclaw gateway stop
Restart=always
RestartSec=10
WatchdogSec=30

[Install]
WantedBy=multi-user.target
SERVICE
        
        sudo chmod 644 "$service_file"
        sudo systemctl daemon-reload
        ok "OpenClaw systemd service created (root + watchdog)"
    fi
    
    # Enable service to start on boot
    if systemctl is-enabled openclaw.service &>/dev/null; then
        ok "OpenClaw service already enabled"
    else
        sudo systemctl enable openclaw.service
        ok "OpenClaw service enabled for boot"
    fi
}

# ─── Auto-start OpenClaw if tokens are configured ───
start_openclaw_if_ready() {
    local config_file="$HOME/.openclaw/config/gateway.yaml"
    
    # Check if tokens are set (not still ${VAR} placeholders)
    if grep -q '\${DISCORD_TOKEN}' "$config_file" 2>/dev/null; then
        warn "Discord token not set — skipping auto-start"
        return 0
    fi
    
    log "Starting OpenClaw service..."
    if sudo systemctl start openclaw.service 2>/dev/null; then
        ok "OpenClaw service started"
        sleep 2
        if systemctl is-active openclaw.service &>/dev/null; then
            ok "OpenClaw running and healthy"
        else
            warn "OpenClaw service started but may not be healthy yet"
        fi
    else
        warn "Could not start OpenClaw service. Start manually: sudo systemctl start openclaw"
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
    echo "Service:    systemd openclaw.service (root, watchdog, auto-start)"
    echo ""
    echo "Next steps:"
    echo "  1. Review ~/.openclaw/config/gateway.yaml"
    echo "  2. Check service: sudo systemctl status openclaw"
    echo ""
    echo "Commands:"
    echo "  ollama list                    # List models"
    echo "  ollama pull <model>            # Pull a model"
    echo "  openclaw status                # Check gateway status"
    echo "  openclaw gateway start         # Manual start (if not using systemd)"
    echo "  sudo systemctl start openclaw  # Start via systemd"
    echo "  sudo systemctl stop openclaw   # Stop via systemd"
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
