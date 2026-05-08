#!/usr/bin/env bash
# freecp suspend-client <domain>

cmd_suspend_client() {
    require_args 1 "suspend-client <domain>" "$@"
    local domain="${1,,}"
    client_assert_exists "$domain"

    if client_is_suspended "$domain"; then
        freecp_warn "Client '${domain}' is already suspended."
        exit 0
    fi

    freecp_step "Suspending ${domain}..."
    client_set_status "$domain" "suspended"
    state_set "$domain" "config" "suspended_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    nginx_enable_suspended "$domain"

    freecp_ok "Client '${domain}' suspended."
    echo -e "  Visitors will see the suspended page."
    echo -e "  To restore: ${CYAN}freecp unsuspend-client ${domain}${NC}"
    echo ""
}