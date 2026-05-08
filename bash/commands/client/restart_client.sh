#!/usr/bin/env bash
# freecp restart-client <domain>

cmd_restart_client() {
    require_args 1 "restart-client <domain>" "$@"

    local domain="${1,,}"
    client_assert_exists "$domain"

    freecp_header "Restart: ${domain}"

    freecp_step "Restarting Docker container..."
    docker_restart "$domain"

    freecp_step "Restarting Supervisor processes..."
    supervisor_restart "$domain"

    freecp_ok "Client '${domain}' restarted."
    echo ""
}