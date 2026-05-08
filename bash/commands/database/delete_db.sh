#!/usr/bin/env bash
# ============================================================
#  freecp delete-db <domain> <dbname>
# ============================================================

cmd_delete_db() {
    require_args 2 "delete-db <domain> <dbname>" "$@"

    local domain="${1,,}"
    local dbname="${2,,}"

    client_assert_exists "$domain"

    freecp_header "Delete Database: ${dbname}"

    # ── Prevent deleting primary DB ───────────────────────────
    local primary_db
    primary_db=$(state_get "$domain" "credentials" "db_name")

    if [[ "$dbname" == "$primary_db" ]]; then
        freecp_error "Cannot delete the primary database '${dbname}'."
        echo "  The primary database is deleted automatically when the client is deleted."
        exit 1
    fi

    # ── Check db belongs to this client ──────────────────────
    if ! client_get_databases "$domain" | grep -q "^${dbname}$"; then
        freecp_error "Database '${dbname}' is not registered under '${domain}'"
        exit 1
    fi

    # ── Show size warning ─────────────────────────────────────
    local size
    size=$(db_size_mb "$dbname")
    echo -e "  Database: ${CYAN}${dbname}${NC}"
    echo -e "  Size:     ${size:-0} MB"
    echo ""
    echo -e "  ${RED}All data will be permanently deleted.${NC}"
    echo ""

    freecp_confirm "Delete database '${dbname}'?" "n" || { echo "  Cancelled."; exit 0; }

    # ── Drop database and user ────────────────────────────────
    local db_user="u_${dbname:0:28}"

    freecp_step "Dropping database..."
    db_drop "$dbname" "$db_user"

    freecp_step "Unregistering database..."
    client_remove_database "$domain" "$dbname"

    freecp_ok "Database '${dbname}' deleted."
    echo ""
}