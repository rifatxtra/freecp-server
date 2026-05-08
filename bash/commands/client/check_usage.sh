#!/usr/bin/env bash
# freecp check-usage <domain>

cmd_check_usage() {
    require_args 1 "check-usage <domain>" "$@"
    local domain="${1,,}"
    client_assert_exists "$domain"

    local plan
    plan=$(state_get "$domain" "config" "plan")

    freecp_header "Usage: ${domain}"

    # ── Container ─────────────────────────────────────────────
    echo -e "  ${BOLD}CONTAINER${NC}"
    freecp_divider

    if docker_container_running "$domain"; then
        local stats cpu mem mem_pct net block
        stats=$(docker_stats "$domain")
        cpu=$(echo "$stats"      | cut -d'|' -f1)
        mem=$(echo "$stats"      | cut -d'|' -f2)
        mem_pct=$(echo "$stats"  | cut -d'|' -f3)
        net=$(echo "$stats"      | cut -d'|' -f4)
        block=$(echo "$stats"    | cut -d'|' -f5)
        echo -e "  CPU:          ${CYAN}${cpu}${NC} / $(plan_get "$plan" "cpu_limit") cores"
        echo -e "  Memory:       ${CYAN}${mem}${NC} (${mem_pct})"
        echo -e "  Network I/O:  ${net}"
        echo -e "  Block I/O:    ${block}"
    else
        freecp_warn "Container not running"
    fi
    echo ""

    # ── Storage ───────────────────────────────────────────────
    echo -e "  ${BOLD}STORAGE (DYNAMIC)${NC}"
    freecp_divider

    local c_gb db_gb limit_gb total_gb pct
    c_gb=$(state_get "$domain" "storage" "container_gb"); c_gb="${c_gb:-0}"
    db_gb=$(state_get "$domain" "storage" "db_gb");       db_gb="${db_gb:-0}"
    limit_gb=$(state_get "$domain" "storage" "limit_gb"); limit_gb="${limit_gb:-$(plan_get "$plan" "storage_gb")}"
    total_gb=$(awk "BEGIN {printf \"%.2f\", ${c_gb} + ${db_gb}}")
    pct=$(awk "BEGIN {printf \"%d\", ($limit_gb > 0) ? ($total_gb * 100 / $limit_gb) : 0}")

    echo -e "  Container:    ${CYAN}${c_gb} GB${NC}"
    echo -e "  Database:     ${CYAN}${db_gb} GB${NC}"
    echo -e "  Total:        ${CYAN}${total_gb} GB${NC} / ${limit_gb} GB"
    freecp_progress_bar "$pct"
    echo ""

    # ── Bandwidth ─────────────────────────────────────────────
    echo -e "  ${BOLD}BANDWIDTH${NC}"
    freecp_divider

    local bw_used bw_limit bw_reset throttled bw_pct
    bw_used=$(state_get "$domain" "bandwidth" "used_gb");   bw_used="${bw_used:-0}"
    bw_limit=$(state_get "$domain" "bandwidth" "limit_gb"); bw_limit="${bw_limit:-$(plan_get "$plan" "bandwidth_gb")}"
    bw_reset=$(state_get "$domain" "bandwidth" "reset_date")
    throttled=$(state_get "$domain" "bandwidth" "throttled")
    bw_pct=$(awk "BEGIN {printf \"%d\", ($bw_limit > 0) ? ($bw_used * 100 / $bw_limit) : 0}")

    echo -e "  Used:         ${CYAN}${bw_used} GB${NC} / ${bw_limit} GB"
    echo -e "  Resets:       ${bw_reset}"
    if [[ "${throttled}" == "1" ]]; then
        echo -e "  Throttled:    ${YELLOW}YES — $(plan_get "$plan" "bandwidth_throttle")${NC}"
    else
        echo -e "  Throttled:    ${GREEN}No${NC}"
    fi
    freecp_progress_bar "$bw_pct"
    echo ""

    # ── Redis ─────────────────────────────────────────────────
    echo -e "  ${BOLD}REDIS${NC}"
    freecp_divider

    local redis_prefix key_count
    redis_prefix=$(state_get "$domain" "credentials" "redis_prefix")
    key_count=$(docker exec freecp_redis \
        redis-cli --scan --pattern "${redis_prefix}*" 2>/dev/null | wc -l | xargs)

    echo -e "  Prefix:       ${redis_prefix}"
    echo -e "  Keys:         ${CYAN}${key_count}${NC}"
    echo -e "  Limit:        $(plan_get "$plan" "redis_memory") (optional)"
    echo ""

    # ── Databases ─────────────────────────────────────────────
    echo -e "  ${BOLD}DATABASES${NC}"
    freecp_divider

    local max_db
    max_db=$(plan_get "$plan" "max_databases")
    local db_list=()
    mapfile -t db_list < <(client_get_databases "$domain" 2>/dev/null || true)

    echo -e "  Count:        ${#db_list[@]} / ${max_db}"
    for db in "${db_list[@]}"; do
        local size
        size=$(db_size_mb "$db")
        printf "    · %-32s %s MB\n" "$db" "${size:-0}"
    done
    echo ""

    # ── Supervisor ────────────────────────────────────────────
    echo -e "  ${BOLD}PROCESSES${NC}"
    freecp_divider

    supervisor_status "$domain" | while IFS= read -r line; do
        if echo "$line" | grep -q "RUNNING"; then
            echo -e "  ${GREEN}${line}${NC}"
        elif echo "$line" | grep -qE "STOPPED|FATAL|ERROR"; then
            echo -e "  ${RED}${line}${NC}"
        else
            echo -e "  ${YELLOW}${line}${NC}"
        fi
    done
    echo ""
}