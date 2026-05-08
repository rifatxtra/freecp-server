#!/usr/bin/env bash
# freecp edit-env <domain>

cmd_edit_env() {
    require_args 1 "edit-env <domain>" "$@"

    local domain="${1,,}"
    client_assert_exists "$domain"

    local env_path="${FREECP_CLIENTS_PATH}/${domain}/.env"

    if [[ ! -f "$env_path" ]]; then
        freecp_error ".env not found for '${domain}'"
        echo "  Create one: freecp create-env ${domain}"
        exit 1
    fi

    # ── Pick editor ───────────────────────────────────────────
    local editor="${EDITOR:-}"

    if [[ -z "$editor" ]]; then
        if command -v nano &>/dev/null; then
            editor="nano"
        elif command -v vim &>/dev/null; then
            editor="vim"
        elif command -v vi &>/dev/null; then
            editor="vi"
        else
            freecp_error "No editor found. Set \$EDITOR or install nano."
            echo "  Alternative: freecp update-env ${domain} KEY VALUE"
            exit 1
        fi
    fi

    # ── Backup before editing ─────────────────────────────────
    cp "$env_path" "${env_path}.bak"

    # ── Open editor ───────────────────────────────────────────
    "$editor" "$env_path"

    # ── Restart on save ───────────────────────────────────────
    if docker_container_running "$domain"; then
        freecp_confirm "Restart container to apply changes?" "y" && {
            freecp_step "Restarting..."
            docker_restart "$domain"
            freecp_ok "Container restarted."
        }
    fi

    echo ""
}