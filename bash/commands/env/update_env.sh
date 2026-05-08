#!/usr/bin/env bash
# freecp update-env <domain> <KEY> <VALUE>

cmd_update_env() {
    require_args 3 "update-env <domain> <KEY> <VALUE>" "$@"

    local domain="${1,,}"
    local key="$2"
    local value="$3"

    client_assert_exists "$domain"

    local env_path="${FREECP_CLIENTS_PATH}/${domain}/.env"

    if [[ ! -f "$env_path" ]]; then
        freecp_error ".env not found for '${domain}'"
        echo "  Create one: freecp create-env ${domain}"
        exit 1
    fi

    # ── Update or append key ──────────────────────────────────
    if grep -q "^${key}=" "$env_path" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$env_path"
        freecp_ok "Updated: ${key}=${value}"
    else
        echo "${key}=${value}" >> "$env_path"
        freecp_ok "Added: ${key}=${value}"
    fi

    # ── Restart container to apply ────────────────────────────
    if docker_container_running "$domain"; then
        freecp_step "Restarting container to apply changes..."
        docker_restart "$domain"
    fi

    echo ""
}