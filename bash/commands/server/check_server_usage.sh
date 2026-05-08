#!/usr/bin/env bash
# freecp check-server-usage

cmd_check_server_usage() {
    freecp_header "FreeCP Server Usage"

    # ── Memory ────────────────────────────────────────────────
    echo -e "  ${BOLD}MEMORY${NC}"
    freecp_divider

    local mem_total mem_avail mem_used mem_pct
    mem_total=$(grep MemTotal     /proc/meminfo | awk '{print $2}')
    mem_avail=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    mem_used=$(( mem_total - mem_avail ))

    local total_gb used_gb avail_gb
    total_gb=$(awk "BEGIN {printf \"%.1f\", $mem_total / 1024 / 1024}")
    used_gb=$(awk  "BEGIN {printf \"%.1f\", $mem_used  / 1024 / 1024}")
    avail_gb=$(awk "BEGIN {printf \"%.1f\", $mem_avail / 1024 / 1024}")
    mem_pct=$(awk  "BEGIN {printf \"%d\",   $mem_used  * 100 / $mem_total}")

    echo -e "  Total:        ${total_gb} GB"
    echo -e "  Used:         ${CYAN}${used_gb} GB${NC} (${mem_pct}%)"
    echo -e "  Available:    ${GREEN}${avail_gb} GB${NC}"
    freecp_progress_bar "$mem_pct"
    echo ""

    # ── CPU ───────────────────────────────────────────────────
    echo -e "  ${BOLD}CPU${NC}"
    freecp_divider

    local load1 load5 load15 vcpus
    read -r load1 load5 load15 _ < /proc/loadavg
    vcpus=$(nproc)

    echo -e "  vCPUs:        ${vcpus}"
    echo -e "  Load (1m):    ${CYAN}${load1}${NC}"
    echo -e "  Load (5m):    ${load5}"
    echo -e "  Load (15m):   ${load15}"
    echo ""

    # ── Disk ──────────────────────────────────────────────────
    echo -e "  ${BOLD}NVMe STORAGE${NC}"
    freecp_divider

    local disk_line disk_total disk_used disk_free disk_pct
    disk_line=$(df -BG / | tail -1)
    disk_total=$(echo "$disk_line" | awk '{print $2}' | tr -d 'G')
    disk_used=$(echo "$disk_line"  | awk '{print $3}' | tr -d 'G')
    disk_free=$(echo "$disk_line"  | awk '{print $4}' | tr -d 'G')
    disk_pct=$(echo "$disk_line"   | awk '{print $5}' | tr -d '%')

    echo -e "  Total:        ${disk_total} GB"
    echo -e "  Used:         ${CYAN}${disk_used} GB${NC} (${disk_pct}%)"
    echo -e "  Free:         ${GREEN}${disk_free} GB${NC}"
    freecp_progress_bar "$disk_pct"
    echo ""

    # ── Shared services ───────────────────────────────────────
    echo -e "  ${BOLD}SHARED SERVICES${NC}"
    freecp_divider

    for svc in freecp_mariadb freecp_redis; do
        if docker ps --format '{{.Names}}' | grep -q "^${svc}$"; then
            local svc_stats
            svc_stats=$(docker stats "$svc" --no-stream \
                --format '{{.CPUPerc}} | RAM: {{.MemUsage}}' 2>/dev/null)
            echo -e "  ${GREEN}●${NC} ${svc}: ${svc_stats}"
        else
            echo -e "  ${RED}●${NC} ${svc}: ${RED}NOT RUNNING${NC}"
        fi
    done
    echo ""

    # ── Client summary ────────────────────────────────────────
    echo -e "  ${BOLD}CLIENT SUMMARY${NC}"
    freecp_divider

    local total=0 active=0 suspended=0 deleted=0 revenue=0

    while IFS= read -r domain; do
        [[ -z "$domain" ]] && continue
        local status plan price
        status=$(client_get_status "$domain")
        plan=$(state_get "$domain" "config" "plan")
        price=$(plan_get "${plan:-lite}" "price")

        (( total++ )) || true
        case "$status" in
            active)
                (( active++ ))   || true
                (( revenue += price )) || true
                ;;
            suspended) (( suspended++ )) || true ;;
            deleted)   (( deleted++ ))   || true ;;
        esac
    done < <(client_list_all 2>/dev/null)

    local server_cost=1350
    local profit=$(( revenue - server_cost ))

    echo -e "  Clients:         ${WHITE}${total}${NC} / 20"
    echo -e "  Active:          ${GREEN}${active}${NC}"
    echo -e "  Suspended:       ${YELLOW}${suspended}${NC}"
    echo -e "  Deleted:         ${RED}${deleted}${NC}"
    echo ""
    echo -e "  Monthly Revenue: ${GREEN}৳${revenue} BDT${NC}"
    echo -e "  Server Cost:     ${RED}৳${server_cost} BDT${NC}"
    echo -e "  Net Profit:      ${GREEN}৳${profit} BDT${NC}"
    echo ""
}