#!/usr/bin/env bash
# ============================================================
#  freecp delete-client <domain> [--force]
# ============================================================

cmd_delete_client() {
    require_args 1 "delete-client <domain> [--force]" "$@"

    local domain="${1,,}"
    local force=false
    [[ "${2:-}" == "--force" ]] && force=true

    client_assert_exists "$domain"
    freecp_header "Delete Client: ${domain}"

    if $force; then
        echo -e "  ${RED}${BOLD}PERMANENT DELETE — cannot be undone!${NC}"
        echo ""
        freecp_confirm "Permanently delete '${domain}'?" "n" || { echo "  Cancelled."; exit 0; }

        freecp_step "Stopping container..."
        docker_stop "$domain"
        supervisor_stop "$domain"

        freecp_step "Removing Docker container and volume..."
        docker_remove "$domain"
        docker_remove_volume "$domain"

        freecp_step "Removing Supervisor config..."
        supervisor_remove "$domain"

        freecp_step "Removing Nginx vhost..."
        nginx_remove_vhost "$domain"

        freecp_step "Dropping database..."
        local db_name db_user
        db_name=$(state_get "$domain" "credentials" "db_name")
        db_user=$(state_get "$domain" "credentials" "db_user")
        [[ -n "$db_name" ]] && db_drop "$db_name" "$db_user"

        freecp_step "Removing SSH key..."
        _remove_ssh_key "$domain"

        freecp_step "Removing client files..."
        rm -rf "${FREECP_CLIENTS_PATH}/${domain}"

        freecp_ok "Client '${domain}' permanently deleted."

    else
        echo "  Soft-delete — data kept 2 months, then auto-purged."
        echo ""
        freecp_confirm "Soft-delete '${domain}'?" "y" || { echo "  Cancelled."; exit 0; }

        freecp_step "Stopping container..."
        docker_stop "$domain"
        supervisor_stop "$domain"

        freecp_step "Removing Nginx vhost..."
        nginx_remove_vhost "$domain"

        freecp_step "Marking as deleted..."
        client_set_status "$domain" "deleted"
        state_set "$domain" "config" "deleted_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

        local purge_date
        purge_date=$(date -d '+2 months' +%Y-%m-%d 2>/dev/null \
                  || date -v+2m +%Y-%m-%d 2>/dev/null \
                  || echo "in 2 months")

        state_set "$domain" "config" "purge_after" "$purge_date"

        freecp_ok "Client '${domain}' soft-deleted."
        echo -e "  Data purge scheduled: ${YELLOW}${purge_date}${NC}"
        echo -e "  To restore: ${CYAN}freecp restore-client ${domain}${NC}"
    fi
    echo ""
}

_remove_ssh_key() {
    local domain="$1"
    local auth_keys="/root/.ssh/authorized_keys"
    [[ ! -f "$auth_keys" ]] && return

    local tmp skip=false
    tmp=$(mktemp)

    while IFS= read -r line; do
        if [[ "$line" == "# freecp-${domain}" ]]; then
            skip=true; continue
        fi
        if $skip; then
            skip=false; continue
        fi
        echo "$line" >> "$tmp"
    done < "$auth_keys"

    mv "$tmp" "$auth_keys"
    chmod 600 "$auth_keys"
}