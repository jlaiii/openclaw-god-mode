#!/bin/bash
set -euo pipefail

# OpenClaw God Mode — One-Click Deploy Script
# Usage: export DISCORD_TOKEN='...' ADMIN_DISCORD_ID='...' && curl -fsSL .../deploy.sh | bash

REPO="https://github.com/jlaiii/openclaw-god-mode.git"
TMP_DIR="/tmp/openclaw-god-mode-$$"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[*]${NC} $*"; }
ok()  { echo -e "${GREEN}[✓]${NC} $*"; }

log "OpenClaw God Mode — One-Click Deploy"

# Check required env vars
if [ -z "${DISCORD_TOKEN:-}" ]; then
    echo "ERROR: DISCORD_TOKEN is not set."
    echo "Set it before running this script:"
    echo "  export DISCORD_TOKEN='your_token'"
    exit 1
fi

if [ -z "${ADMIN_DISCORD_ID:-}" ]; then
    echo "ERROR: ADMIN_DISCORD_ID is not set."
    echo "Set it before running this script:"
    echo "  export ADMIN_DISCORD_ID='your_user_id'"
    exit 1
fi

log "Cloning repository..."
git clone --depth 1 "$REPO" "$TMP_DIR"

log "Running installer..."
cd "$TMP_DIR/linux"
chmod +x install.sh
./install.sh

# Cleanup
rm -rf "$TMP_DIR"

ok "Deploy complete! Your bot should be running."
ok "Check status: systemctl --user status openclaw-gateway.service"
