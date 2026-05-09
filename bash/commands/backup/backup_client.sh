#!/usr/bin/env bash
# ============================================================
#  freecp backup-client <domain>
# ============================================================

cmd_backup_client() {
    require_args 1 "backup-client <domain>" "$@"

    local domain="${1,,}"
    client_assert_exists "$domain"

    source "${FREECP_COMMANDS}/backup/backup_lib.sh"
    backup_check_enabled

    freecp_header "Backup Client: ${domain}"

    local status plan
    status=$(client_get_status "$domain")
    plan=$(state_get "$domain" "config" "plan")

    local timestamp backup_name tmp_dir
    timestamp=$(backup_timestamp)
    backup_name="${domain}_${timestamp}.tar.gz"
    tmp_dir=$(mktemp -d)

    freecp_step "Creating backup archive..."

    # ── Dump database ─────────────────────────────────────────
    local db_name db_user db_pass
    db_name=$(state_get "$domain" "credentials" "db_name")

    freecp_step "Dumping database '${db_name}'..."
    docker exec freecp_mariadb \
        mysqldump \
        -uroot -p"${FREECP_DB_ROOT_PASSWORD}" \
        --single-transaction \
        --routines \
        --triggers \
        "$db_name" \
        > "${tmp_dir}/database.sql" 2>/dev/null || {
            freecp_warn "Database dump failed — continuing without DB backup"
        }

    # ── Copy client files ─────────────────────────────────────
    freecp_step "Archiving client files..."
    local client_path="${FREECP_CLIENTS_PATH}/${domain}"

    tar -czf "${tmp_dir}/${backup_name}" \
        --exclude="${client_path}/app/vendor" \
        --exclude="${client_path}/app/node_modules" \
        --exclude="${client_path}/logs/*.log" \
        -C "$(dirname "$client_path")" \
        "$(basename "$client_path")" \
        "${tmp_dir}/database.sql" \
        2>/dev/null

    local backup_size
    backup_size=$(du -sh "${tmp_dir}/${backup_name}" | cut -f1)

    # ── Push to backup VPS ────────────────────────────────────
    freecp_step "Pushing to backup VPS (${backup_size})..."

    local remote_dir="${FREECP_BACKUP_VPS_PATH}/clients/${domain}"
    backup_ssh "mkdir -p ${remote_dir}" 2>/dev/null

    backup_rsync \
        "${tmp_dir}/${backup_name}" \
        "${remote_dir}/${backup_name}"

    # ── Prune old backups ─────────────────────────────────────
    freecp_step "Pruning old backups..."
    backup_prune_client "$domain" "$status"

    # ── Cleanup ───────────────────────────────────────────────
    rm -rf "$tmp_dir"

    freecp_ok "Backup complete: ${backup_name} (${backup_size})"
    echo -e "  Remote: ${CYAN}${FREECP_BACKUP_VPS_HOST}:${remote_dir}/${backup_name}${NC}"
    echo ""
}