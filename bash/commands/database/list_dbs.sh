#!/usr/bin/env bash
# ============================================================
#  freecp list-dbs <domain>
# ============================================================

cmd_list_dbs() {
    require_args 1 "list-dbs <domain>" "$@"

    local domain="${1,,}"
    client_assert_exists "$domain"

    freecp_header "Databases: ${domain}"

    local plan max_db primary_db
    plan=$(state_get "$domain" "config" "plan")
    max_db=$(plan_get "$plan" "max_databases")
    primary_db=$(state_get "$domain" "credentials" "db_name")

    local databases=()
    mapfile -t databases < <(client_get_databases "$domain" 2>/dev/null || true)

    if [[ ${#databases[@]} -eq 0 ]]; then
        freecp_warn "No databases found."
        echo ""
        return
    fi

    printf "  ${BOLD}%-35s %-12s %-10s${NC}\n" "DATABASE" "SIZE" "TYPE"
    freecp_divider

    local total_size=0

    for db in "${databases[@]}"; do
        [[ -z "$db" ]] && continue

        local size type
        size=$(db_size_mb "$db")
        size="${size:-0}"

        [[ "$db" == "$primary_db" ]] \
            && type="${CYAN}Primary${NC}" \
            || type="Additional"

        # Add to total
        total_size=$(awk "BEGIN {printf \"%.2f\", ${total_size} + ${size}}")

        printf "  %-35s %-12s %-10b\n" "$db" "${size} MB" "$type"
    done

    freecp_divider
    echo ""
    echo -e "  Total: ${#databases[@]} / ${max_db} databases | ${CYAN}${total_size} MB${NC} used"
    echo ""
    echo -e "  Add:    ${CYAN}freecp create-db ${domain} <dbname>${NC}"
    echo -e "  Remove: ${CYAN}freecp delete-db ${domain} <dbname>${NC}"
    echo ""
}