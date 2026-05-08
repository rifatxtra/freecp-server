#!/usr/bin/env bash
# freecp set-client-email <domain> <email>

cmd_set_client_email() {
    require_args 2 "set-client-email <domain> <email>" "$@"

    local domain="${1,,}"
    local email="$2"

    client_assert_exists "$domain"
    validate_email "$email" || exit 1

    state_write_raw "$domain" "email" "$email"

    freecp_ok "Alert email set for '${domain}': ${email}"
    echo -e "  System alerts will be sent to: ${CYAN}${email}${NC}"
    echo ""
}