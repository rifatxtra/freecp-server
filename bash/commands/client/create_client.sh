#!/usr/bin/env bash
# ============================================================
#  freecp create-client <domain> <plan> [php]
# ============================================================

cmd_create_client() {
    require_args 2 "create-client <domain> <plan> [php83]" "$@"

    local domain plan php_version
    domain="${1,,}"
    plan="${2,,}"
    php_version=$(normalize_php "${3:-php83}")

    freecp_header "Creating Client: ${domain}"

    # ── Validate ──────────────────────────────────────────────
    validate_domain   "$domain"      || exit 1
    validate_plan     "$plan"        || exit 1
    validate_php      "$php_version" || exit 1

    if client_exists "$domain"; then
        freecp_error "Client '${domain}' already exists."
        echo "  To change plan: freecp upgrade-client ${domain} <plan>"
        exit 1
    fi

    # ── Show plan summary ─────────────────────────────────────
    echo -e "  Domain:     ${CYAN}${domain}${NC}"
    echo -e "  Plan:       ${CYAN}$(plan_get "$plan" "name") — $(plan_get "$plan" "price") BDT/mo${NC}"
    echo -e "  PHP:        ${CYAN}${php_version}${NC}"
    echo -e "  RAM:        ${CYAN}$(plan_get "$plan" "ram_reservation") reserved / $(plan_get "$plan" "ram_limit") max${NC}"
    echo -e "  CPU:        ${CYAN}$(plan_get "$plan" "cpu_limit") cores${NC}"
    echo -e "  Storage:    ${CYAN}$(plan_get "$plan" "storage_gb") GB${NC}"
    echo -e "  Bandwidth:  ${CYAN}$(plan_get "$plan" "bandwidth_gb") GB/mo${NC}"
    echo ""

    freecp_confirm "Proceed with provisioning?" "y" || exit 0
    echo ""

    # ── Generate credentials ──────────────────────────────────
    local uid db_name db_user db_pass app_key redis_prefix
    uid=$(client_generate_uid "$domain")
    db_name=$(db_generate_name "$domain")
    db_user=$(db_generate_user "$domain")
    db_pass=$(db_generate_password)
    app_key="base64:$(openssl rand -base64 32)"
    redis_prefix="${domain//[.-]/_}:"

    # ── Create directories ────────────────────────────────────
    freecp_step "Creating client directory..."
    client_create_dirs "$domain"

    # ── Save config ───────────────────────────────────────────
    state_write "$domain" "config" \
        "domain=${domain}" \
        "plan=${plan}" \
        "php_version=${php_version}" \
        "uid=${uid}" \
        "gid=${uid}" \
        "created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # ── Save credentials ──────────────────────────────────────
    state_write "$domain" "credentials" \
        "db_name=${db_name}" \
        "db_user=${db_user}" \
        "db_pass=${db_pass}" \
        "app_key=${app_key}" \
        "redis_prefix=${redis_prefix}"

    # ── Set status ────────────────────────────────────────────
    client_set_status "$domain" "active"

    # ── Initialize bandwidth ──────────────────────────────────
    local reset_date
    reset_date=$(date -d "$(date +%Y-%m-01) +1 month" +%Y-%m-%d 2>/dev/null \
              || date -v+1m -v1d +%Y-%m-%d 2>/dev/null \
              || echo "$(date +%Y-%m)-01")

    state_write "$domain" "bandwidth" \
        "used_gb=0" \
        "limit_gb=$(plan_get "$plan" "bandwidth_gb")" \
        "reset_date=${reset_date}" \
        "throttled=0"

    # ── Initialize storage ────────────────────────────────────
    state_write "$domain" "storage" \
        "container_gb=0" \
        "db_gb=0" \
        "limit_gb=$(plan_get "$plan" "storage_gb")"

    # ── Primary domain ────────────────────────────────────────
    client_add_domain "$domain" "$domain"

    # ── Generate .env ─────────────────────────────────────────
    freecp_step "Generating .env..."
    _create_env_file "$domain" "$plan" "$php_version" \
        "$db_name" "$db_user" "$db_pass" "$app_key" "$redis_prefix"

    # ── Docker volume ─────────────────────────────────────────
    freecp_step "Creating Docker volume..."
    docker_create_volume "$domain"

    # ── MariaDB ───────────────────────────────────────────────
    freecp_step "Provisioning database..."
    db_create "$db_name" "$db_user" "$db_pass" \
        "$(plan_get "$plan" "db_max_connections")" \
        "$(plan_get "$plan" "db_max_queries")"
    client_add_database "$domain" "$db_name"

    # ── Docker container ──────────────────────────────────────
    docker_run_client "$domain" "$plan" "$php_version" "$uid" || exit 1

    # ── Nginx vhost ───────────────────────────────────────────
    freecp_step "Configuring Nginx..."
    nginx_create_vhost "$domain"

    # ── Supervisor ────────────────────────────────────────────
    freecp_step "Setting up Supervisor..."
    supervisor_create "$domain" "$plan"

    # ── SSH deploy key ────────────────────────────────────────
    freecp_step "Generating SSH deploy key..."
    local ssh_dir key_path private_key public_key
    ssh_dir="${FREECP_CLIENTS_PATH}/${domain}/ssh"
    key_path="${ssh_dir}/deploy_key"

    ssh-keygen -t ed25519 \
        -C "freecp-deploy-${domain}" \
        -f "$key_path" \
        -N "" > /dev/null 2>&1

    private_key=$(cat "${key_path}")
    public_key=$(cat "${key_path}.pub")

    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
    echo "# freecp-${domain}"  >> /root/.ssh/authorized_keys
    echo "$public_key"         >> /root/.ssh/authorized_keys

    # ── Print summary ─────────────────────────────────────────
    freecp_success_box "Client '${domain}' provisioned!"

    echo -e "  ${BOLD}Domain:${NC}       ${domain}"
    echo -e "  ${BOLD}Plan:${NC}         $(plan_get "$plan" "name")"
    echo -e "  ${BOLD}PHP:${NC}          ${php_version}"
    echo -e "  ${BOLD}Container:${NC}    $(docker_container_name "$domain")"
    echo -e "  ${BOLD}DB Name:${NC}      ${db_name}"
    echo -e "  ${BOLD}DB User:${NC}      ${db_user}"
    echo -e "  ${BOLD}DB Pass:${NC}      ${db_pass}"
    echo -e "  ${BOLD}UID/GID:${NC}      ${uid}"
    echo ""
    freecp_divider
    echo -e "  ${BOLD}SSH Private Key${NC} (add to GitHub Actions → FREECP_SSH_KEY):"
    echo ""
    echo "$private_key"
    echo ""
    freecp_divider
    echo ""
    echo -e "  ${YELLOW}Next steps:${NC}"
    echo -e "  1. Point DNS for ${CYAN}${domain}${NC} to this server's IP"
    echo -e "  2. Once DNS propagates: ${CYAN}freecp provision-ssl ${domain}${NC}"
    echo -e "  3. rsync target: ${CYAN}${FREECP_CLIENTS_PATH}/${domain}/app/${NC}"
    echo ""
}

_create_env_file() {
    local domain="$1" plan="$2" php="$3"
    local db_name="$4" db_user="$5" db_pass="$6"
    local app_key="$7" redis_prefix="$8"
    local env_path="${FREECP_CLIENTS_PATH}/${domain}/.env"

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
}