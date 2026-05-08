#!/usr/bin/env bash
# freecp unsuspend-client <domain>

cmd_unsuspend_client() {
    require_args 1 "unsuspend-client <domain>" "$@"
    local domain="${1,,}"
    client_assert_exists "$domain"

    if ! client_is_suspended "$domain"; then
        freecp_warn "Client '${domain}' is not suspended (status: $(client_get_status "$domain"))."
        exit 0
    fi

    freecp_step "Unsuspending ${domain}..."
    client_set_status "$domain" "active"
    state_set "$domain" "config" "suspended_at" ""
    nginx_disable_suspended "$domain"

    if ! docker_container_running "$domain"; then
        docker_start "$domain"
    fi

    freecp_ok "Client '${domain}' is now active."
    echo -e "  Website: ${CYAN}https://${domain}${NC}"
    echo ""
}