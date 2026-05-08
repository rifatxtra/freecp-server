#!/usr/bin/env bash
# freecp create-env <domain>

cmd_create_env() {
    require_args 1 "create-env <domain>" "$@"

    local domain="${1,,}"
    client_assert_exists "$domain"

    local env_path="${FREECP_CLIENTS_PATH}/${domain}/.env"

    freecp_header "Create .env: ${domain}"

    if [[ -f "$env_path" ]]; then
        freecp_warn ".env already exists for '${domain}'"
        freecp_confirm "Overwrite existing .env?" "n" || { echo "  Cancelled."; exit 0; }
        cp "$env_path" "${env_path}.bak.$(date +%Y%m%d%H%M%S)"
        freecp_ok "Existing .env backed up"
    fi

    # ── Rebuild from stored credentials ──────────────────────
    local plan php_version db_name db_user db_pass app_key redis_prefix
    plan=$(state_get "$domain" "config" "plan")
    php_version=$(state_get "$domain" "config" "php_version")
    db_name=$(state_get "$domain" "credentials" "db_name")
    db_user=$(state_get "$domain" "credentials" "db_user")
    db_pass=$(state_get "$domain" "credentials" "db_pass")
    app_key=$(state_get "$domain" "credentials" "app_key")
    redis_prefix=$(state_get "$domain" "credentials" "redis_prefix")

    cat > "$env_path" <<ENV
APP_NAME="${domain}"
APP_ENV=production
APP_KEY=${app_key}
APP_DEBUG=false
APP_URL=https://${domain}

LOG_CHANNEL=stderr
LOG_LEVEL=error

DB_CONNECTION=mysql
DB_HOST=freecp_mariadb
DB_PORT=3306
DB_DATABASE=${db_name}
DB_USERNAME=${db_user}
DB_PASSWORD=${db_pass}

CACHE_DRIVER=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis

REDIS_HOST=freecp_redis
REDIS_PASSWORD=null
REDIS_PORT=6379
REDIS_PREFIX=${redis_prefix}
REDIS_MAX_MEMORY=$(plan_get "$plan" "redis_memory")

MAIL_MAILER=smtp
MAIL_HOST=
MAIL_PORT=587
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS="noreply@${domain}"
MAIL_FROM_NAME="${domain}"

OCTANE_SERVER=frankenphp
OCTANE_WORKERS=$(plan_get "$plan" "octane_workers")
ENV

    chmod 600 "$env_path"

    freecp_ok ".env created for '${domain}'"
    echo -e "  Path: ${CYAN}${env_path}${NC}"
    echo -e "  Edit: ${CYAN}freecp edit-env ${domain}${NC}"
    echo ""
}