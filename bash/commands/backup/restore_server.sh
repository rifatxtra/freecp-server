#!/usr/bin/env bash
# ============================================================
#  freecp restore-server [backup-file]
#  Restores full server from backup on a fresh VPS
# ============================================================

cmd_restore_server() {
    local specific_backup="${1:-}"

    source "${FREECP_COMMANDS}/backup/backup_lib.sh"
    backup_check_enabled

    freecp_header "Restore Server"

    local remote_dir="${FREECP_BACKUP_VPS_PATH}/server"

    # ── Find backup ───────────────────────────────────────────
    local backup_file
    if [[ -n "$specific_backup" ]]; then
        backup_file="$specific_backup"
    else
        freecp_step "Finding latest server backup..."
        backup_file=$(backup_ssh \
            "ls -t ${remote_dir}/freecp_server_*.tar.gz 2>/dev/null | head -1" \
            2>/dev/null | xargs basename 2>/dev/null || echo "")

        if [[ -z "$backup_file" ]]; then
            freecp_error "No server backups found on backup VPS"
            echo "  Create one first: freecp backup-server"
            exit 1
        fi
    fi

    echo -e "  Restoring: ${CYAN}${backup_file}${NC}"
    echo ""
    echo -e "  ${RED}${BOLD}WARNING: This will overwrite all existing client data!${NC}"
    echo ""

    freecp_confirm "Restore full server from backup?" "n" || { echo "  Cancelled."; exit 0; }
    echo ""

    local tmp_dir
    tmp_dir=$(mktemp -d)

    # ── Download backup ───────────────────────────────────────
    freecp_step "Downloading server backup..."
    rsync -az \
        -e "ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no -p ${FREECP_BACKUP_VPS_PORT:-22}" \
        "${FREECP_BACKUP_VPS_USER:-root}@${FREECP_BACKUP_VPS_HOST}:${remote_dir}/${backup_file}" \
        "${tmp_dir}/" || {
            freecp_error "Failed to download backup"
            rm -rf "$tmp_dir"
            exit 1
        }

    # ── Extract ───────────────────────────────────────────────
    freecp_step "Extracting backup..."
    tar -xzf "${tmp_dir}/${backup_file}" -C "$tmp_dir" 2>/dev/null

    local work_dir="${tmp_dir}/freecp_backup"

    # ── Show manifest ─────────────────────────────────────────
    if [[ -f "${work_dir}/manifest.txt" ]]; then
        echo ""
        echo -e "  ${BOLD}Backup Info:${NC}"
        while IFS= read -r line; do
            echo "  $line"
        done < "${work_dir}/manifest.txt"
        echo ""
    fi

    freecp_confirm "Proceed with restore?" "y" || {
        rm -rf "$tmp_dir"
        echo "  Cancelled."
        exit 0
    }
    echo ""

    # ── Restore FreeCP config ─────────────────────────────────
    freecp_step "Restoring FreeCP config..."
    mkdir -p /opt/freecp/config
    cp "${work_dir}/config/freecp.conf" \
       /opt/freecp/config/freecp.conf 2>/dev/null && \
       chmod 600 /opt/freecp/config/freecp.conf || \
       freecp_warn "Config restore failed"

    # Reload config
    freecp_load_config

    # ── Restore client state files ────────────────────────────
    freecp_step "Restoring client state files..."
    mkdir -p "${FREECP_CLIENTS_PATH}"
    cp -r "${work_dir}/clients/." \
          "${FREECP_CLIENTS_PATH}/" 2>/dev/null || \
          freecp_warn "Client files restore failed"

    # ── Restore databases ─────────────────────────────────────
    freecp_step "Restoring databases..."
    for sql_file in "${work_dir}/databases"/*.sql; do
        [[ -f "$sql_file" ]] || continue
        local db_name
        db_name=$(basename "$sql_file" .sql)

        # Recreate DB and user
        local domain
        domain=$(grep -rl "db_name=${db_name}" "${FREECP_CLIENTS_PATH}" 2>/dev/null \
            | head -1 | xargs dirname 2>/dev/null | xargs basename 2>/dev/null || echo "")

        if [[ -n "$domain" ]]; then
            local db_user db_pass max_conn max_queries plan
            db_user=$(state_get "$domain" "credentials" "db_user")
            db_pass=$(state_get "$domain" "credentials" "db_pass")
            plan=$(state_get "$domain" "config" "plan")
            max_conn=$(plan_get "${plan:-lite}" "db_max_connections")
            max_queries=$(plan_get "${plan:-lite}" "db_max_queries")

            db_create "$db_name" "$db_user" "$db_pass" "$max_conn" "$max_queries" 2>/dev/null

            docker exec -i freecp_mariadb \
                mysql -uroot -p"${FREECP_DB_ROOT_PASSWORD}" \
                "$db_name" \
                < "$sql_file" 2>/dev/null \
                && echo -e "    ${GREEN}✓${NC} ${db_name}" \
                || echo -e "    ${YELLOW}!${NC} ${db_name} (import failed)"
        fi
    done

    # ── Restore Nginx vhosts ──────────────────────────────────
    freecp_step "Restoring Nginx vhosts..."
    cp "${work_dir}/nginx/"*.conf \
       "${FREECP_NGINX_AVAILABLE}/" 2>/dev/null || true

    # Re-enable all vhosts
    for conf in "${FREECP_NGINX_AVAILABLE}"/[^default]*.conf; do
        [[ -f "$conf" ]] || continue
        local vhost_name
        vhost_name=$(basename "$conf")
        [[ ! -L "${FREECP_NGINX_ENABLED}/${vhost_name}" ]] && \
            ln -sf "$conf" "${FREECP_NGINX_ENABLED}/${vhost_name}"
    done
    nginx_reload

    # ── Restore Supervisor configs ────────────────────────────
    freecp_step "Restoring Supervisor configs..."
    cp "${work_dir}/supervisor/"*.conf \
       "${FREECP_SUPERVISOR_CONF}/" 2>/dev/null || true
    supervisor_reload

    # ── Rebuild and restart all containers ────────────────────
    freecp_step "Rebuilding client containers..."
    local restored=0 failed=0

    while IFS= read -r domain; do
        [[ -z "$domain" ]] && continue
        local plan php uid
        plan=$(state_get "$domain" "config" "plan")
        php=$(state_get "$domain" "config" "php_version")
        uid=$(state_get "$domain" "config" "uid")

        freecp_step "  → ${domain} (${plan}, PHP ${php})"

        docker_run_client "$domain" "$plan" "$php" "$uid" > /dev/null 2>&1 \
            && (( restored++ )) \
            || { (( failed++ )); freecp_warn "    Failed to start ${domain}"; }

    done < <(client_list_all 2>/dev/null)

    # ── Cleanup ───────────────────────────────────────────────
    rm -rf "$tmp_dir"

    freecp_success_box "Server restore complete!"
    echo -e "  Backup:   ${backup_file}"
    echo -e "  Restored: ${GREEN}${restored}${NC} clients"
    [[ "$failed" -gt 0 ]] && \
        echo -e "  Failed:   ${RED}${failed}${NC} clients — check manually"
    echo ""
    echo -e "  ${YELLOW}Note: SSL certificates are not restored.${NC}"
    echo -e "  Re-provision SSL: ${CYAN}freecp provision-ssl <domain>${NC}"
    echo ""
}