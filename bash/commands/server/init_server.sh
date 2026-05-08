#!/usr/bin/env bash
# ============================================================
#  freecp init-server
#  Run once on a fresh Ubuntu 24.04 VPS
# ============================================================

cmd_init_server() {
    freecp_header "FreeCP — Server Initialization"

    freecp_confirm "Initialize this VPS for FreeCP?" "y" || exit 0
    echo ""

    # ── 1. Directories ────────────────────────────────────────
    freecp_step "Creating directories..."
    mkdir -p /opt/freecp/{clients,templates,logs,backups,ssl}
    chmod 700 /opt/freecp/{clients,backups,ssl}
    chmod 755 /opt/freecp/{templates,logs}
    mkdir -p /var/log/freecp
    freecp_ok "Directories ready"

    # ── 2. Swap ───────────────────────────────────────────────
    freecp_step "Configuring swap..."
    if [[ ! -f /swapfile ]]; then
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile  > /dev/null
        swapon /swapfile
        grep -q '/swapfile' /etc/fstab \
            || echo '/swapfile none swap sw 0 0' >> /etc/fstab
        grep -q 'vm.swappiness' /etc/sysctl.conf \
            || echo 'vm.swappiness=10' >> /etc/sysctl.conf
        grep -q 'vm.vfs_cache_pressure' /etc/sysctl.conf \
            || echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf
        sysctl -p -q
        freecp_ok "2GB swap created"
    else
        freecp_warn "Swap already exists — skipping"
    fi

    # ── 3. Kernel tuning ──────────────────────────────────────
    freecp_step "Tuning kernel parameters..."
    local sysctl_params=(
        "net.core.somaxconn=65535"
        "net.ipv4.tcp_max_syn_backlog=65535"
        "net.ipv4.tcp_fin_timeout=30"
        "net.ipv4.tcp_keepalive_time=300"
    )
    for param in "${sysctl_params[@]}"; do
        local key="${param%%=*}"
        grep -q "^${key}" /etc/sysctl.conf \
            || echo "$param" >> /etc/sysctl.conf
    done
    sysctl -p -q
    freecp_ok "Kernel tuned"

    # ── 4. Docker networks ────────────────────────────────────
    freecp_step "Creating Docker networks..."
    docker network inspect freecp_proxy   > /dev/null 2>&1 \
        || docker network create --driver bridge \
               --subnet=172.20.0.0/16 \
               freecp_proxy > /dev/null

    docker network inspect freecp_backend > /dev/null 2>&1 \
        || docker network create --driver bridge \
               --subnet=172.21.0.0/16 \
               --internal \
               freecp_backend > /dev/null

    freecp_ok "Networks: freecp_proxy, freecp_backend"

    # ── 5. MariaDB ────────────────────────────────────────────
    freecp_step "Deploying shared MariaDB (2GB limit)..."

    if docker ps --format '{{.Names}}' | grep -q '^freecp_mariadb$'; then
        freecp_warn "MariaDB already running — skipping"
    else
        local db_root_pass
        db_root_pass=$(grep '^DB_ROOT_PASSWORD=' /opt/freecp/config/freecp.conf 2>/dev/null \
            | cut -d= -f2 || echo "")

        if [[ -z "$db_root_pass" ]]; then
            db_root_pass=$(freecp_ask "Set MariaDB root password")
            echo "DB_ROOT_PASSWORD=${db_root_pass}" >> /opt/freecp/config/freecp.conf
            export FREECP_DB_ROOT_PASSWORD="$db_root_pass"
        fi

        # Copy MariaDB config template
        cp "${FREECP_TEMPLATES_PATH}/docker/mariadb.cnf" \
           /opt/freecp/mariadb.cnf 2>/dev/null || true

        docker run -d \
            --name freecp_mariadb \
            --restart unless-stopped \
            --network freecp_backend \
            --memory=2g \
            --memory-reservation=1g \
            --cpus=1.0 \
            -e MYSQL_ROOT_PASSWORD="$db_root_pass" \
            -e MYSQL_CHARACTER_SET_SERVER=utf8mb4 \
            -e MYSQL_COLLATION_SERVER=utf8mb4_unicode_ci \
            -v freecp_mariadb_data:/var/lib/mysql \
            -v /opt/freecp/mariadb.cnf:/etc/mysql/conf.d/freecp.cnf:ro \
            --log-opt max-size=20m \
            --log-opt max-file=3 \
            mariadb:10.11-jammy > /dev/null

        freecp_step "Waiting for MariaDB..."
        sleep 15
        freecp_ok "MariaDB started"
    fi

    # ── 6. Redis ──────────────────────────────────────────────
    freecp_step "Deploying shared Redis (1GB limit)..."

    if docker ps --format '{{.Names}}' | grep -q '^freecp_redis$'; then
        freecp_warn "Redis already running — skipping"
    else
        docker run -d \
            --name freecp_redis \
            --restart unless-stopped \
            --network freecp_backend \
            --memory=1g \
            --memory-reservation=256m \
            --cpus=0.5 \
            -v freecp_redis_data:/data \
            --log-opt max-size=5m \
            --log-opt max-file=2 \
            redis:7.2-alpine \
            redis-server \
            --maxmemory 900mb \
            --maxmemory-policy allkeys-lru \
            --save "" \
            --appendonly no > /dev/null
        freecp_ok "Redis started"
    fi

    # ── 7. Nginx ──────────────────────────────────────────────
    freecp_step "Configuring Nginx..."
    mkdir -p /etc/nginx/{sites-available,sites-enabled,freecp,ssl}

    # Self-signed default cert
    if [[ ! -f /etc/nginx/ssl/default.crt ]]; then
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout /etc/nginx/ssl/default.key \
            -out    /etc/nginx/ssl/default.crt \
            -subj "/CN=default" > /dev/null 2>&1
    fi

    # Catch-all — unknown domains return 444
    cat > /etc/nginx/sites-available/default <<'NGINX'
server {
    listen 80 default_server;
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate     /etc/nginx/ssl/default.crt;
    ssl_certificate_key /etc/nginx/ssl/default.key;
    return 444;
}
NGINX

    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/default \
           /etc/nginx/sites-enabled/default

    # Copy global Nginx config
    cp "${FREECP_TEMPLATES_PATH}/nginx/global.conf" \
       /etc/nginx/freecp/global.conf

    # Include global config in nginx.conf
    if ! grep -q 'freecp/global.conf' /etc/nginx/nginx.conf; then
        sed -i '/http {/a\    include /etc/nginx/freecp/global.conf;' \
            /etc/nginx/nginx.conf
    fi

    nginx -t > /dev/null 2>&1 && systemctl reload nginx
    freecp_ok "Nginx configured"

    # ── 8. Supervisor ─────────────────────────────────────────
    freecp_step "Configuring Supervisor..."
    systemctl enable supervisor > /dev/null 2>&1
    systemctl start  supervisor > /dev/null 2>&1
    freecp_ok "Supervisor ready"

    # ── 9. Cron jobs ──────────────────────────────────────────
    freecp_step "Installing cron jobs..."
    local cron_tmp
    cron_tmp=$(mktemp)
    crontab -l 2>/dev/null > "$cron_tmp" || true

    local jobs=(
        "0 0 1 * * /usr/local/bin/freecp bandwidth-reset-all >> /var/log/freecp/cron.log 2>&1"
        "0 */6 * * * /usr/local/bin/freecp update-storage >> /var/log/freecp/cron.log 2>&1"
        "0 3 * * * certbot renew --quiet --nginx >> /var/log/freecp/ssl.log 2>&1"
    )

    for job in "${jobs[@]}"; do
        grep -qF "$job" "$cron_tmp" || echo "$job" >> "$cron_tmp"
    done

    crontab "$cron_tmp"
    rm -f "$cron_tmp"
    freecp_ok "Cron jobs installed"

    # ── Summary ───────────────────────────────────────────────
    freecp_success_box "Server initialization complete!"
    echo -e "  ${BOLD}Next steps:${NC}"
    echo ""
    echo -e "  ${CYAN}freecp setup-smtp${NC}"
    echo -e "  ${CYAN}freecp create-client domain.com lite php83${NC}"
    echo ""
}