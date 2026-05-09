#!/usr/bin/env bash
# ============================================================
#  freecp list-backups-server
# ============================================================

cmd_list_backups_server() {
    source "${FREECP_COMMANDS}/backup/backup_lib.sh"
    backup_check_enabled

    freecp_header "Server Backups"

    local remote_dir="${FREECP_BACKUP_VPS_PATH}/server"

    freecp_step "Fetching backup list from ${FREECP_BACKUP_VPS_HOST}..."

    local backup_list
    backup_list=$(backup_ssh \
        "ls -lt ${remote_dir}/freecp_server_*.tar.gz 2>/dev/null \
         | awk '{print \$5, \$6, \$7, \$8, \$9}'" 2>/dev/null || echo "")

    if [[ -z "$backup_list" ]]; then
        freecp_warn "No server backups found."
        echo -e "  Create one: ${CYAN}freecp backup-server${NC}"
        echo ""
        return
    fi

    echo ""
    printf "  ${BOLD}%-15s %-25s %-30s${NC}\n" "SIZE" "DATE" "FILE"
    freecp_divider

    echo "$backup_list" | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local size date_str time_str filename
        size=$(echo "$line"     | awk '{print $1}')
        date_str=$(echo "$line" | awk '{print $2, $3}')
        time_str=$(echo "$line" | awk '{print $4}')
        filename=$(echo "$line" | awk '{print $5}' | xargs basename 2>/dev/null)

        local hr_size
        hr_size=$(awk "BEGIN {
            s=$size
            if (s > 1073741824) printf \"%.1f GB\", s/1073741824
            else if (s > 1048576) printf \"%.1f MB\", s/1048576
            else printf \"%.0f KB\", s/1024
        }")

        printf "  %-15s %-25s %-30s\n" "$hr_size" "${date_str} ${time_str}" "$filename"
    done

    local count
    count=$(echo "$backup_list" | grep -c 'freecp_server_' || echo 0)

    # ── Also show per-client backup count ─────────────────────
    echo ""
    freecp_divider
    echo -e "  ${BOLD}Per-client backups:${NC}"

    while IFS= read -r domain; do
        [[ -z "$domain" ]] && continue
        local client_count
        client_count=$(backup_ssh \
            "ls ${FREECP_BACKUP_VPS_PATH}/clients/${domain}/*.tar.gz 2>/dev/null | wc -l" \
            2>/dev/null | xargs || echo "0")
        printf "  %-35s %s backup(s)\n" "$domain" "$client_count"
    done < <(client_list_all 2>/dev/null)

    echo ""
    echo -e "  Server backups: ${WHITE}${count}${NC} (retaining last 8)"
    echo ""
    echo -e "  Restore: ${CYAN}freecp restore-server [backup-file]${NC}"
    echo ""
}