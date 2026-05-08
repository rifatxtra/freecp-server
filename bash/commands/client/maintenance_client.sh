#!/usr/bin/env bash
# freecp maintenance-client <domain> on|off

cmd_maintenance_client() {
    require_args 2 "maintenance-client <domain> on|off" "$@"

    local domain="${1,,}"
    local mode="${2,,}"

    client_assert_exists "$domain"

    if [[ "$mode" != "on" && "$mode" != "off" ]]; then
        freecp_error "Invalid mode: '${mode}'. Use: on or off"
        exit 1
    fi

    if [[ "$mode" == "on" ]]; then
        if client_is_maintenance "$domain"; then
            freecp_warn "Client '${domain}' is already in maintenance mode."
            exit 0
        fi

        freecp_step "Enabling maintenance mode for ${domain}..."
        client_set_status "$domain" "maintenance"
        nginx_enable_maintenance "$domain"

        freecp_ok "Maintenance mode ON for '${domain}'"
        echo -e "  Visitors will see the maintenance page."
        echo -e "  Disable: ${CYAN}freecp maintenance-client ${domain} off${NC}"

    else
        if ! client_is_maintenance "$domain"; then
            freecp_warn "Client '${domain}' is not in maintenance mode."
            exit 0
        fi

        freecp_step "Disabling maintenance mode for ${domain}..."
        client_set_status "$domain" "active"
        nginx_disable_maintenance "$domain"

        freecp_ok "Maintenance mode OFF — '${domain}' is live."
    fi
    echo ""
}