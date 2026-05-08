#!/usr/bin/env bash
# ============================================================
#  freecp upgrade-client <domain> <plan>
# ============================================================

cmd_upgrade_client() {
    require_args 2 "upgrade-client <domain> <plan>" "$@"

    local domain="${1,,}"
    local new_plan="${2,,}"

    client_assert_exists "$domain"
    validate_plan "$new_plan" || exit 1

    freecp_header "Change Plan: ${domain}"

    local current_plan
    current_plan=$(state_get "$domain" "config" "plan")

    if [[ "$current_plan" == "$new_plan" ]]; then
        freecp_warn "Client '${domain}' is already on the '${new_plan}' plan."
        exit 0
    fi

    # ── Show diff ─────────────────────────────────────────────
    echo -e "  ${BOLD}Current:${NC}  ${current_plan^^} — $(plan_get "$current_plan" "price") BDT/mo"
    echo -e "  ${BOLD}New:${NC}      ${new_plan^^} — $(plan_get "$new_plan" "price") BDT/mo"
    echo ""
    printf "  ${BOLD}%-20s %-15s %-15s${NC}\n" "RESOURCE" "CURRENT" "NEW"
    freecp_divider
    printf "  %-20s %-15s %-15s\n" "RAM (max)"   "$(plan_get "$current_plan" "ram_limit")"  "$(plan_get "$new_plan" "ram_limit")"
    printf "  %-20s %-15s %-15s\n" "CPU"         "$(plan_get "$current_plan" "cpu_limit")"  "$(plan_get "$new_plan" "cpu_limit")"
    printf "  %-20s %-15s %-15s\n" "Bandwidth"   "$(plan_get "$current_plan" "bandwidth_gb")GB" "$(plan_get "$new_plan" "bandwidth_gb")GB"
    printf "  %-20s %-15s %-15s\n" "Queue Workers" "$(plan_get "$current_plan" "queue_workers")" "$(plan_get "$new_plan" "queue_workers")"
    printf "  %-20s %-15s %-15s\n" "Max DBs"     "$(plan_get "$current_plan" "max_databases")"  "$(plan_get "$new_plan" "max_databases")"
    echo ""
    echo -e "  ${YELLOW}Note: Storage is NOT changed. Use 'freecp resize-storage' separately.${NC}"
    echo ""

    freecp_confirm "Apply plan change?" "y" || { echo "  Cancelled."; exit 0; }
    echo ""

    # ── Update Docker resource limits ─────────────────────────
    freecp_step "Updating Docker resource limits..."
    docker_update_limits "$domain" "$new_plan"

    # ── Handle Octane transition ──────────────────────────────
    local current_octane new_octane
    current_octane=$(plan_get "$current_plan" "octane")
    new_octane=$(plan_get "$new_plan" "octane")

    if [[ "$current_octane" != "$new_octane" ]]; then
        freecp_warn "Octane mode changed — container rebuild required."
        freecp_step "Rebuilding container..."

        local uid php_version
        uid=$(state_get "$domain" "config" "uid")
        php_version=$(state_get "$domain" "config" "php_version")

        docker_remove "$domain"
        docker_run_client "$domain" "$new_plan" "$php_version" "$uid" || {
            freecp_error "Rebuild failed"
            exit 1
        }
    fi

    # ── Update Supervisor ─────────────────────────────────────
    freecp_step "Updating Supervisor processes..."
    supervisor_update "$domain" "$new_plan"

    # ── Update bandwidth limit ────────────────────────────────
    freecp_step "Updating bandwidth limit..."
    state_set "$domain" "bandwidth" "limit_gb" "$(plan_get "$new_plan" "bandwidth_gb")"

    # ── Update plan in config ─────────────────────────────────
    state_set "$domain" "config" "plan" "$new_plan"
    state_set "$domain" "config" "upgraded_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    freecp_success_box "Plan changed to '${new_plan^^}'"
    echo -e "  Domain:  ${domain}"
    echo -e "  Plan:    ${new_plan^^} — $(plan_get "$new_plan" "price") BDT/mo"
    echo -e "  RAM:     $(plan_get "$new_plan" "ram_reservation") reserved / $(plan_get "$new_plan" "ram_limit") max"
    echo -e "  CPU:     $(plan_get "$new_plan" "cpu_limit") cores"
    echo ""
}