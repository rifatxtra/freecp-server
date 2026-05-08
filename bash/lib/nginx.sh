#!/usr/bin/env bash
# ============================================================
#  FreeCP — Nginx Helpers
# ============================================================

nginx_create_vhost() {
    local domain="$1"
    local container_name
    container_name=$(docker_container_name "$domain")

    local config_path="${FREECP_NGINX_AVAILABLE}/${domain}.conf"
    local enabled_path="${FREECP_NGINX_ENABLED}/${domain}.conf"

    mkdir -p "${FREECP_CLIENTS_PATH}/${domain}/logs"

    sed \
        -e "s|{{DOMAIN}}|${domain}|g" \
        -e "s|{{CONTAINER_NAME}}|${container_name}|g" \
        "${FREECP_TEMPLATES_PATH}/nginx/vhost.conf" \
        > "$config_path"

    [[ ! -L "$enabled_path" ]] && ln -sf "$config_path" "$enabled_path"
    nginx_reload
}

nginx_remove_vhost() {
    local domain="$1"
    rm -f "${FREECP_NGINX_ENABLED}/${domain}.conf"
    rm -f "${FREECP_NGINX_AVAILABLE}/${domain}.conf"
    nginx_reload
}

nginx_enable_suspended() {
    local domain="$1"
    local pages_path="${FREECP_CLIENTS_PATH}/${domain}/pages"
    local log_path="${FREECP_CLIENTS_PATH}/${domain}/logs"
    local config_path="${FREECP_NGINX_AVAILABLE}/${domain}.conf"

    # Ensure suspended page exists
    if [[ ! -f "${pages_path}/suspended.html" ]]; then
        mkdir -p "$pages_path"
        sed "s|{{DOMAIN}}|${domain}|g" \
            "${FREECP_TEMPLATES_PATH}/pages/suspended.html" \
            > "${pages_path}/suspended.html"
    fi

    cat > "$config_path" <<NGINX
# FreeCP — Suspended: ${domain}
server {
    listen 80;
    listen [::]:80;
    server_name ${domain} www.${domain};

    root ${pages_path};

    access_log ${log_path}/access.log;
    error_log  ${log_path}/error.log warn;

    location / { return 503; }

    error_page 503 /suspended.html;
    location = /suspended.html { internal; }
}
NGINX

    nginx_reload
}

nginx_disable_suspended() { nginx_create_vhost "$1"; }

nginx_enable_maintenance() {
    local domain="$1"
    local container_name pages_path log_path config_path
    container_name=$(docker_container_name "$domain")
    pages_path="${FREECP_CLIENTS_PATH}/${domain}/pages"
    log_path="${FREECP_CLIENTS_PATH}/${domain}/logs"
    config_path="${FREECP_NGINX_AVAILABLE}/${domain}.conf"

    if [[ ! -f "${pages_path}/maintenance.html" ]]; then
        mkdir -p "$pages_path"
        sed "s|{{DOMAIN}}|${domain}|g" \
            "${FREECP_TEMPLATES_PATH}/pages/maintenance.html" \
            > "${pages_path}/maintenance.html"
    fi

    cat > "$config_path" <<NGINX
# FreeCP — Maintenance: ${domain}
server {
    listen 80;
    listen [::]:80;
    server_name ${domain} www.${domain};

    root ${pages_path};

    access_log ${log_path}/access.log;
    error_log  ${log_path}/error.log warn;

    location / { try_files \$uri /maintenance.html =503; }
    error_page 503 /maintenance.html;

    location = /health {
        proxy_pass http://${container_name}:80/health;
    }
}
NGINX

    nginx_reload
}

nginx_disable_maintenance() { nginx_create_vhost "$1"; }

nginx_provision_ssl() {
    local domain="$1"
    local email="${FREECP_SMTP_FROM:-admin@example.com}"

    certbot --nginx \
        -d "$domain" \
        -d "www.${domain}" \
        --email "$email" \
        --agree-tos \
        --non-interactive \
        --redirect
}

nginx_renew_ssl() {
    certbot renew --cert-name "$1" --nginx --non-interactive
}

nginx_test()   { nginx -t > /dev/null 2>&1; }

nginx_reload() {
    if nginx_test; then
        systemctl reload nginx > /dev/null
    else
        freecp_error "Nginx config test failed — check: nginx -t"
        return 1
    fi
}