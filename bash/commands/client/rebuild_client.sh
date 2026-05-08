#!/usr/bin/env bash
# freecp rebuild-client <domain>

cmd_rebuild_client() {
    require_args 1 "rebuild-client <domain>" "$@"

    local domain="${1,,}"
    client_assert_exists "$domain"

    freecp_header "Rebuild: ${domain}"

    local plan php_version uid
    plan=$(state_get "$domain" "config" "plan")
    php_version=$(state_get "$domain" "config" "php_version")
    uid=$(state_get "$domain" "config" "uid")

    echo -e "  Plan:  ${plan^^}"
    echo -e "  PHP:   ${php_version}"
    echo ""
    echo -e "  ${YELLOW}Container will be stopped briefly during rebuild.${NC}"
    echo ""

    freecp_confirm "Rebuild container for '${domain}'?" "y" || { echo "  Cancelled."; exit 0; }

    freecp_step "Stopping container..."
    supervisor_stop "$domain"
    docker_stop "$domain"
    docker_remove "$domain"

    freecp_step "Rebuilding image..."
    docker_run_client "$domain" "$plan" "$php_version" "$uid" || {
        freecp_error "Rebuild failed — check Docker logs"
        exit 1
    }

    freecp_step "Restarting Supervisor..."
    supervisor_restart "$domain"

    freecp_ok "Client '${domain}' rebuilt successfully."
    echo ""
}