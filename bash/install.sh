#!/usr/bin/env bash
# ============================================================
#  FreeCP — Installer
#  Run on fresh Ubuntu 24.04 LTS
#
#  curl -fsSL https://raw.githubusercontent.com/rifatxtra/freecp-server/main/bash/install.sh | bash
# ============================================================

set -euo pipefail

FREECP_REPO="https://github.com/rifatxtra/freecp-server"
FREECP_PATH="/opt/freecp"
FREECP_BIN="/usr/local/bin/freecp"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()   { echo -e "${CYAN}[FreeCP]${NC} $1"; }
ok()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && error "Run as root: sudo bash install.sh"

echo -e "${BOLD}"
cat << 'BANNER'
    ______               ____________
   / ____/_______  ___  / ____/ __ \
  / /_  / ___/ _ \/ _ \/ /   / /_/ /
 / __/ / /  /  __/  __/ /___/ ____/
/_/   /_/   \___/\___/\____/_/

  Free Open Source Hosting Control Panel
  https://github.com/rifatxtra/freecp-server
BANNER
echo -e "${NC}"

# ── 1. System packages ────────────────────────────────────────
log "Installing system packages..."
apt-get update -qq
apt-get install -y -qq \
    curl wget git unzip \
    ufw fail2ban \
    ca-certificates gnupg lsb-release \
    iproute2 bc openssl
ok "System packages installed"

# ── 2. PHP versions ───────────────────────────────────────────
log "Installing PHP 8.2, 8.3, 8.4..."
add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1
apt-get update -qq

for ver in 8.2 8.3 8.4; do
    apt-get install -y -qq \
        php${ver}-cli php${ver}-fpm php${ver}-common \
        php${ver}-mysql php${ver}-redis php${ver}-curl \
        php${ver}-mbstring php${ver}-xml php${ver}-zip \
        php${ver}-gd php${ver}-bcmath php${ver}-intl \
        php${ver}-opcache php${ver}-imagick 2>/dev/null || true
done
ok "PHP 8.2, 8.3, 8.4 installed"

# ── 3. Docker ─────────────────────────────────────────────────
log "Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -qq
apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

cat > /etc/docker/daemon.json <<'DOCKEREOF'
{
    "log-driver": "json-file",
    "log-opts": { "max-size": "10m", "max-file": "3" },
    "storage-driver": "overlay2",
    "live-restore": true
}
DOCKEREOF

systemctl enable docker > /dev/null 2>&1
systemctl restart docker
ok "Docker installed"

# ── 4. Nginx + Certbot ────────────────────────────────────────
log "Installing Nginx and Certbot..."
apt-get install -y -qq nginx certbot python3-certbot-nginx
systemctl enable nginx > /dev/null 2>&1
ok "Nginx and Certbot installed"

# ── 5. Supervisor ─────────────────────────────────────────────
log "Installing Supervisor..."
apt-get install -y -qq supervisor
systemctl enable supervisor > /dev/null 2>&1
ok "Supervisor installed"

# ── 6. Fail2Ban ───────────────────────────────────────────────
log "Configuring Fail2Ban..."
cat > /etc/fail2ban/jail.local <<'F2B'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
F2B
systemctl restart fail2ban > /dev/null 2>&1
ok "Fail2Ban configured"

# ── 7. UFW ────────────────────────────────────────────────────
log "Configuring firewall..."
ufw default deny incoming  > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1
ufw allow 22/tcp  > /dev/null 2>&1
ufw allow 80/tcp  > /dev/null 2>&1
ufw allow 443/tcp > /dev/null 2>&1
ufw --force enable > /dev/null 2>&1
ok "Firewall configured"

# ── 8. Clone FreeCP ───────────────────────────────────────────
log "Installing FreeCP..."
if [[ -d "$FREECP_PATH" ]]; then
    warn "FreeCP already exists — pulling latest..."
    cd "$FREECP_PATH" && git pull -q
else
    git clone -q "$FREECP_REPO" "$FREECP_PATH"
fi

# Copy bash files to runtime location
cp -r "${FREECP_PATH}/bash/lib"       "${FREECP_PATH}/"
cp -r "${FREECP_PATH}/bash/commands"  "${FREECP_PATH}/"
cp -r "${FREECP_PATH}/bash/templates" "${FREECP_PATH}/"

# Setup config
mkdir -p "${FREECP_PATH}/config"
if [[ ! -f "${FREECP_PATH}/config/freecp.conf" ]]; then
    cp "${FREECP_PATH}/bash/config/freecp.conf.example" \
       "${FREECP_PATH}/config/freecp.conf"
    chmod 600 "${FREECP_PATH}/config/freecp.conf"
fi

# Install global command
cp "${FREECP_PATH}/bash/bin/freecp" "$FREECP_BIN"
chmod +x "$FREECP_BIN"
ok "freecp command installed"

# ── Summary ───────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  FreeCP installed successfully!${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo ""
echo -e "  1. Edit config:"
echo -e "     ${CYAN}nano /opt/freecp/config/freecp.conf${NC}"
echo ""
echo -e "  2. Initialize server:"
echo -e "     ${CYAN}freecp init-server${NC}"
echo ""
echo -e "  3. Setup SMTP:"
echo -e "     ${CYAN}freecp setup-smtp${NC}"
echo ""
echo -e "  4. Create first client:"
echo -e "     ${CYAN}freecp create-client domain.com lite php83${NC}"
echo ""