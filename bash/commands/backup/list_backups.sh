#!/usr/bin/env bash
# ============================================================
#  freecp list-backups <domain>
# ============================================================

cmd_list_backups() {
    require_args 1 "list-backups <domain>" "$@"

    local domain="${1,,}"
    client_assert_exists "$domain"

    source "${FREECP_COMMANDS}/backup/backup_lib.sh"
    backup_check_enabled

    freecp_header "Backups: ${domain}"

    local remote_dir="${FREECP_BACKUP_VPS_PATH}/clients/${domain}"

    freecp_step "Fetching backup list from ${FREECP_BACKUP_VPS_HOST}..."

    local backup_list
    backup_list=$(backup_ssh \
        "ls -lt ${remote_dir}/*.tar.gz 2>/dev/null \
         | awk '{print \$5, \$6, \$7, \$8, \$9}'" 2>/dev/null || echo "")

    if [[ -z "$backup_list" ]]; then
        freecp_warn "No backups found for '${domain}'"
        echo -e "  Create one: ${CYAN}freecp backup-client ${domain}${NC}"
        echo ""
        return
    fi

    echo ""
    printf "  ${BOLD}%-15s %-25s %-20s${NC}\n" "SIZE" "DATE" "FILE"
    freecp_divider

    echo "$backup_list" | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local size date_str time_str filename
        size=$(echo "$line"     | awk '{print $1}')
        date_str=$(echo "$line" | awk '{print $2, $3}')
        time_str=$(echo "$line" | awk '{print $4}')
        filename=$(echo "$line" | awk '{print $5}' | xargs basename 2>/dev/null)

        # Human-readable size
        local hr_size
        hr_size=$(awk "BEGIN {
            s=$size
            if (s > 1073741824) printf \"%.1f GB\", s/1073741824
            else if (s > 1048576) printf \"%.1f MB\", s/1048576
            else printf \"%.0f KB\", s/1024
        }")

        printf "  %-15s %-25s %-20s\n" "$hr_size" "${date_str} ${time_str}" "$filename"
    done

    local count
    count=$(echo "$backup_list" | grep -c '.tar.gz' || echo 0)

    echo ""
    echo -e "  Total: ${WHITE}${count}${NC} backup(s)"
    echo ""
    echo -e "  Restore latest: ${CYAN}freecp restore-client ${domain}${NC}"
    echo -e "  Restore specific: ${CYAN}freecp restore-client ${domain} <filename>${NC}"
    echo ""
}