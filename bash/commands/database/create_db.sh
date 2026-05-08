#!/usr/bin/env bash
# ============================================================
#  freecp create-db <domain> <dbname>
# ============================================================

cmd_create_db() {
    require_args 2 "create-db <domain> <dbname>" "$@"

    local domain="${1,,}"
    local dbname="${2,,}"

    client_assert_exists "$domain"

    freecp_header "Create Database: ${dbname}"

    # ── Sanitize db name ──────────────────────────────────────
    # Only allow alphanumeric and underscores
    if [[ ! "$dbname" =~ ^[a-zA-Z0-9_]+$ ]]; then
        freecp_error "Invalid database name: '${dbname}'"
        echo "  Only letters, numbers and underscores allowed."
        exit 1
    fi

    # ── Check plan DB limit ───────────────────────────────────
    local plan max_db current_count
    plan=$(state_get "$domain" "config" "plan")
    max_db=$(plan_get "$plan" "max_databases")
    current_count=$(client_get_databases "$domain" | wc -l | xargs)

    if [[ "$current_count" -ge "$max_db" ]]; then
        freecp_error "Database limit reached: ${current_count} / ${max_db} (${plan} plan)"
        echo "  Upgrade plan to add more databases: freecp upgrade-client ${domain} <plan>"
        exit 1
    fi

    # ── Check db doesn't already exist ───────────────────────
    if db_exists "$dbname"; then
        freecp_error "Database '${dbname}' already exists."
        exit 1
    fi

    # ── Check not already registered to another client ────────
    while IFS= read -r existing; do
        [[ -z "$existing" ]] && continue
        if client_get_databases "$existing" | grep -q "^${dbname}$"; then
            freecp_error "Database '${dbname}' is already registered to client '${existing}'"
            exit 1
        fi
    done < <(client_list_all 2>/dev/null)

    # ── Generate credentials ──────────────────────────────────
    local db_user db_pass
    db_user="u_${dbname:0:28}"
    db_pass=$(db_generate_password)

    local max_conn max_queries
    max_conn=$(plan_get "$plan" "db_max_connections")
    max_queries=$(plan_get "$plan" "db_max_queries")

    freecp_step "Creating database '${dbname}'..."
    db_create "$dbname" "$db_user" "$db_pass" "$max_conn" "$max_queries"

    freecp_step "Registering database..."
    client_add_database "$domain" "$dbname"

    # ── Update .env if needed ────────────────────────────────
    # Don't overwrite primary DB — just inform
    freecp_success_box "Database '${dbname}' created!"

    echo -e "  ${BOLD}Database:${NC}  ${dbname}"
    echo -e "  ${BOLD}User:${NC}      ${db_user}"
    echo -e "  ${BOLD}Password:${NC}  ${db_pass}"
    echo -e "  ${BOLD}Host:${NC}      freecp_mariadb"
    echo -e "  ${BOLD}Port:${NC}      3306"
    echo ""
    echo -e "  ${YELLOW}Add to your .env:${NC}"
    echo -e "  ${CYAN}freecp update-env ${domain} DB2_DATABASE ${dbname}${NC}"
    echo -e "  ${CYAN}freecp update-env ${domain} DB2_USERNAME ${db_user}${NC}"
    echo -e "  ${CYAN}freecp update-env ${domain} DB2_PASSWORD ${db_pass}${NC}"
    echo ""
    echo -e "  Count: ${current_count+1} / ${max_db}"
    echo ""
}