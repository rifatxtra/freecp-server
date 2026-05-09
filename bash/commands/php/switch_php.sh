#!/usr/bin/env bash
# ============================================================
#  freecp switch-php <domain> <version>
#  Example: freecp switch-php example.com php82
# ============================================================

cmd_switch_php() {
    require_args 2 "switch-php <domain> <version>" "$@"

    local domain="${1,,}"
    local php_version
    php_version=$(normalize_php "$2")

    client_assert_exists "$domain"
    validate_php "$php_version" || exit 1

    freecp_header "Switch PHP: ${domain}"

    local current_php plan uid
    current_php=$(state_get "$domain" "config" "php_version")
    plan=$(state_get "$domain" "config" "plan")
    uid=$(state_get "$domain" "config" "uid")

    if [[ "$current_php" == "$php_version" ]]; then
        freecp_warn "Client '${domain}' is already running PHP ${php_version}."
        exit 0
    fi

    # ── Verify PHP version is installed on host ───────────────
    if ! command -v "php${php_version}" &>/dev/null; then
        freecp_error "PHP ${php_version} is not installed on this server."
        echo "  Available versions: freecp list-php"
        exit 1
    fi

    echo -e "  Current: ${CYAN}PHP ${current_php}${NC}"
    echo -e "  New:     ${CYAN}PHP ${php_version}${NC}"
    echo ""
    echo -e "  ${YELLOW}Container will be rebuilt — brief downtime expected.${NC}"
    echo ""

    freecp_confirm "Switch to PHP ${php_version}?" "y" || { echo "  Cancelled."; exit 0; }
    echo ""

    # ── Stop Supervisor ───────────────────────────────────────
    freecp_step "Stopping Supervisor processes..."
    supervisor_stop "$domain"

    # ── Remove old container and image ───────────────────────
    freecp_step "Removing old container..."
    docker_stop "$domain"
    docker_remove "$domain"
    docker rmi "freecp/${domain}:latest" > /dev/null 2>&1 || true

    # ── Save new PHP version ──────────────────────────────────
    state_set "$domain" "config" "php_version" "$php_version"

    # ── Rebuild with new PHP ──────────────────────────────────
    docker_run_client "$domain" "$plan" "$php_version" "$uid" || {
        freecp_error "Rebuild failed — rolling back to PHP ${current_php}..."
        state_set "$domain" "config" "php_version" "$current_php"
        docker_run_client "$domain" "$plan" "$current_php" "$uid" || true
        exit 1
    }

    # ── Restart Supervisor ────────────────────────────────────
    freecp_step "Restarting Supervisor processes..."
    supervisor_restart "$domain"

    freecp_success_box "PHP switched to ${php_version}"
    echo -e "  Domain: ${domain}"
    echo -e "  PHP:    ${CYAN}${php_version}${NC}"
    echo ""
}