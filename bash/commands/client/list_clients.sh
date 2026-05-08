#!/usr/bin/env bash
# freecp list-clients [--status=active|suspended|deleted|maintenance]

cmd_list_clients() {
    local filter_status=""
    for arg in "$@"; do
        [[ "$arg" == --status=* ]] && filter_status="${arg#--status=}"
    done

    freecp_header "FreeCP Clients"

    local domains=()
    mapfile -t domains < <(client_list_all 2>/dev/null || true)

    if [[ ${#domains[@]} -eq 0 ]]; then
        echo "  No clients found."
        echo -e "  Create one: ${CYAN}freecp create-client domain.com lite php83${NC}"
        echo ""
        return
    fi

    # Header
    printf "  ${BOLD}%-32s %-12s %-10s %-7s %-14s %-14s %-12s${NC}\n" \
        "DOMAIN" "STATUS" "PLAN" "PHP" "BANDWIDTH" "STORAGE" "CREATED"
    freecp_divider

    local total=0 active_count=0

    for domain in "${domains[@]}"; do
        local status plan php bw_used bw_limit c_gb db_gb st_limit st_used created color

        status=$(client_get_status "$domain")
        [[ -n "$filter_status" && "$status" != "$filter_status" ]] && continue

        plan=$(state_get "$domain" "config" "plan")
        php=$(state_get "$domain" "config" "php_version")
        bw_used=$(state_get "$domain" "bandwidth" "used_gb")
        bw_limit=$(state_get "$domain" "bandwidth" "limit_gb")
        c_gb=$(state_get "$domain" "storage" "container_gb")
        db_gb=$(state_get "$domain" "storage" "db_gb")
        st_limit=$(state_get "$domain" "storage" "limit_gb")
        created=$(state_get "$domain" "config" "created_at" | cut -c1-10)

        st_used=$(awk "BEGIN {printf \"%.1f\", ${c_gb:-0} + ${db_gb:-0}}")

        case "$status" in
            active)      color=$GREEN ;;
            suspended)   color=$YELLOW ;;
            deleted)     color=$RED ;;
            maintenance) color=$CYAN ;;
            *)           color=$NC ;;
        esac

        printf "  %-32s ${color}%-12s${NC} %-10s %-7s %-14s %-14s %-12s\n" \
            "$domain" \
            "${status^^}" \
            "${plan^^}" \
            "${php:-?}" \
            "${bw_used:-0}/${bw_limit:-0}GB" \
            "${st_used}/${st_limit:-0}GB" \
            "${created:-unknown}"

        (( total++ ))
        [[ "$status" == "active" ]] && (( active_count++ )) || true
    done

    echo ""
    echo -e "  Total: ${WHITE}${total}${NC} | Active: ${GREEN}${active_count}${NC} | Max: ${WHITE}20${NC}"
    echo ""
}