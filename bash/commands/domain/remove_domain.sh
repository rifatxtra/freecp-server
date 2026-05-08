#!/usr/bin/env bash
# ============================================================
#  freecp remove-domain <primary-domain> <addon-domain>
# ============================================================

cmd_remove_domain() {
    require_args 2 "remove-domain <primary-domain> <addon-domain>" "$@"

    local domain="${1,,}"
    local addon="${2,,}"

    client_assert_exists "$domain"

    freecp_header "Remove Domain: ${addon}"

    # ── Cannot remove primary domain ──────────────────────────
    if [[ "$addon" == "$domain" ]]; then
        freecp_error "Cannot remove the primary domain '${domain}'."
        echo "  To delete the client entirely: freecp delete-client ${domain}"
        exit 1
    fi

    # ── Check domain belongs to this client ───────────────────
    if ! client_get_domains "$domain" | grep -q "^${addon}$"; then
        freecp_error "Domain '${addon}' is not registered under '${domain}'"
        exit 1
    fi

    freecp_confirm "Remove domain '${addon}' from '${domain}'?" "y" || { echo "  Cancelled."; exit 0; }

    freecp_step "Removing Nginx vhost..."
    nginx_remove_vhost "$addon"

    freecp_step "Unregistering domain..."
    client_remove_domain "$domain" "$addon"

    freecp_ok "Domain '${addon}' removed."
    echo ""
}