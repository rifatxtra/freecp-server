#!/usr/bin/env bash
# ============================================================
#  freecp restore-client <domain> [backup-file]
#  If no backup file given, restores from latest
# ============================================================

cmd_restore_client() {
    require_args 1 "restore-client <domain> [backup-file]" "$@"

    local domain="${1,,}"
    local specific_backup="${2:-}"

    source "${FREECP_COMMANDS}/backup/backup_lib.sh"
    backup_check_enabled

    freecp_header "Restore Client: ${domain}"

    local remote_dir="${FREECP_BACKUP_VPS_PATH}/clients/${domain}"

    # ── Find backup to restore ────────────────────────────────
    local backup_file
    if [[ -n "$specific_backup" ]]; then
        backup_file="$specific_backup"
    else
        freecp_step "Finding latest backup..."
        backup_file=$(backup_ssh \
            "ls -t ${remote_dir}/*.tar.gz 2>/dev/null | head -1" 2>/dev/null \
            | xargs basename 2>/dev/null || echo "")

        if [[ -z "$backup_file" ]]; then
            freecp_error "No backups found for '${domain}' on backup VPS"
            echo "  Create one first: freecp backup-client ${domain}"
            exit 1
        fi
    fi

    echo -e "  Restoring: ${CYAN}${backup_file}${NC}"
    echo ""
    echo -e "  ${YELLOW}This will overwrite current client data.${NC}"
    echo ""

    freecp_confirm "Restore '${domain}' from backup?" "n" || { echo "  Cancelled."; exit 0; }
    echo ""

    local tmp_dir
    tmp_dir=$(mktemp -d)

    # ── Pull backup from VPS ──────────────────────────────────
    freecp_step "Downloading backup from backup VPS..."
    rsync -az \
        -e "ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no -p ${FREECP_BACKUP_VPS_PORT:-22}" \
        "${FREECP_BACKUP_VPS_USER:-root}@${FREECP_BACKUP_VPS_HOST}:${remote_dir}/${backup_file}" \
        "${tmp_dir}/" || {
            freecp_error "Failed to download backup"
            rm -rf "$tmp_dir"
            exit 1
        }

    # ── Stop container if running ─────────────────────────────
    freecp_step "Stopping container..."
    supervisor_stop "$domain" 2>/dev/null || true
    docker_stop "$domain"   2>/dev/null || true

    # ── Extract backup ────────────────────────────────────────
    freecp_step "Extracting backup..."
    tar -xzf "${tmp_dir}/${backup_file}" \
        -C "${FREECP_CLIENTS_PATH}/" \
        2>/dev/null || {
            freecp_error "Failed to extract backup"
            rm -rf "$tmp_dir"
            exit 1
        }

    # ── Restore database ──────────────────────────────────────
    local db_sql="${tmp_dir}/database.sql"

    # Also check inside extracted path
    [[ ! -f "$db_sql" ]] && \
        db_sql="${FREECP_CLIENTS_PATH}/${domain}/../database.sql"

    if [[ -f "$db_sql" ]]; then
        freecp_step "Restoring database..."
        local db_name
        db_name=$(state_get "$domain" "credentials" "db_name")

        docker exec -i freecp_mariadb \
            mysql -uroot -p"${FREECP_DB_ROOT_PASSWORD}" \
            "$db_name" \
            < "$db_sql" 2>/dev/null \
            && freecp_ok "Database restored" \
            || freecp_warn "Database restore failed — check manually"
    else
        freecp_warn "No database dump found in backup — skipping DB restore"
    fi

    # ── Restart container ─────────────────────────────────────
    freecp_step "Restarting container..."
    if docker_container_exists "$domain"; then
        docker_start "$domain"
    else
        local plan php uid
        plan=$(state_get "$domain" "config" "plan")
        php=$(state_get "$domain" "config" "php_version")
        uid=$(state_get "$domain" "config" "uid")
        docker_run_client "$domain" "$plan" "$php" "$uid"
    fi

    supervisor_restart "$domain" 2>/dev/null || true

    # ── Restore Nginx vhost ───────────────────────────────────
    freecp_step "Restoring Nginx vhost..."
    nginx_create_vhost "$domain"

    # ── Cleanup ───────────────────────────────────────────────
    rm -rf "$tmp_dir"

    freecp_success_box "Client '${domain}' restored!"
    echo -e "  From: ${backup_file}"
    echo -e "  Site: ${CYAN}https://${domain}${NC}"
    echo ""
}