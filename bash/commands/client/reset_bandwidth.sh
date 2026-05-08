#!/usr/bin/env bash
# freecp reset-bandwidth <domain>

cmd_reset_bandwidth() {
    require_args 1 "reset-bandwidth <domain>" "$@"

    local domain="${1,,}"
    client_assert_exists "$domain"

    freecp_header "Reset Bandwidth: ${domain}"

    local bw_used bw_limit throttled
    bw_used=$(state_get "$domain" "bandwidth" "used_gb")
    bw_limit=$(state_get "$domain" "bandwidth" "limit_gb")
    throttled=$(state_get "$domain" "bandwidth" "throttled")

    echo -e "  Current usage: ${CYAN}${bw_used:-0} GB${NC} / ${bw_limit} GB"
    echo ""

    freecp_confirm "Reset bandwidth counter for '${domain}'?" "y" || { echo "  Cancelled."; exit 0; }

    # ── Reset counter ─────────────────────────────────────────
    local next_reset
    next_reset=$(date -d "$(date +%Y-%m-01) +1 month" +%Y-%m-%d 2>/dev/null \
              || date -v+1m -v1d +%Y-%m-%d 2>/dev/null \
              || echo "$(date +%Y-%m)-01")

    state_set "$domain" "bandwidth" "used_gb"    "0"
    state_set "$domain" "bandwidth" "reset_date" "$next_reset"
    state_set "$domain" "bandwidth" "throttled"  "0"

    # ── Remove throttle if active ─────────────────────────────
    if [[ "${throttled}" == "1" ]]; then
        freecp_step "Removing bandwidth throttle..."
        docker_remove_throttle "$domain"
        freecp_ok "Throttle removed"
    fi

    freecp_ok "Bandwidth reset. Next reset: ${next_reset}"
    echo ""
}