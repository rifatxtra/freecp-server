#!/usr/bin/env bash
# ============================================================
#  freecp backup-server
#  Full server backup — all clients + config + DBs
#  Enables single-command restore on a fresh VPS
# ============================================================

cmd_backup_server() {
    source "${FREECP_COMMANDS}/backup/backup_lib.sh"
    backup_check_enabled

    freecp_header "Full Server Backup"

    local timestamp backup_name tmp_dir
    timestamp=$(backup_timestamp)
    backup_name="freecp_server_${timestamp}.tar.gz"
    tmp_dir=$(mktemp -d)
    local work_dir="${tmp_dir}/freecp_backup"
    mkdir -p "${work_dir}"/{clients,databases,config,nginx,supervisor}

    echo -e "  Backup ID: ${CYAN}${timestamp}${NC}"
    echo -e "  Target:    ${CYAN}${FREECP_BACKUP_VPS_HOST}${NC}"
    echo ""

    # ── 1. Dump all databases ─────────────────────────────────
    freecp_step "Dumping all client databases..."

    local domains=()
    mapfile -t domains < <(client_list_all 2>/dev/null || true)

    for domain in "${domains[@]}"; do
        [[ -z "$domain" ]] && continue
        local db_name
        db_name=$(state_get "$domain" "credentials" "db_name")
        [[ -z "$db_name" ]] && continue

        docker exec freecp_mariadb \
            mysqldump \
            -uroot -p"${FREECP_DB_ROOT_PASSWORD}" \
            --single-transaction \
            --routines \
            --triggers \
            "$db_name" \
            > "${work_dir}/databases/${db_name}.sql" 2>/dev/null \
            && echo -e "    ${GREEN}✓${NC} ${db_name}" \
            || echo -e "    ${YELLOW}!${NC} ${db_name} (failed)"
    done

    # ── 2. Copy all client state files ────────────────────────
    freecp_step "Archiving client state files..."
    cp -r "${FREECP_CLIENTS_PATH}/." "${work_dir}/clients/" 2>/dev/null || true

    # ── 3. Copy FreeCP config ─────────────────────────────────
    freecp_step "Saving FreeCP configuration..."
    cp /opt/freecp/config/freecp.conf \
       "${work_dir}/config/freecp.conf" 2>/dev/null || true

    # ── 4. Copy Nginx vhosts ──────────────────────────────────
    freecp_step "Saving Nginx vhosts..."
    cp "${FREECP_NGINX_AVAILABLE}"/*.conf \
       "${work_dir}/nginx/" 2>/dev/null || true

    # ── 5. Copy Supervisor configs ────────────────────────────
    freecp_step "Saving Supervisor configs..."
    cp "${FREECP_SUPERVISOR_CONF}"/freecp_client_*.conf \
       "${work_dir}/supervisor/" 2>/dev/null || true

    # ── 6. Save server metadata ───────────────────────────────
    cat > "${work_dir}/manifest.txt" <<MANIFEST
FreeCP Server Backup
Timestamp:  ${timestamp}
Hostname:   $(hostname)
Server IP:  $(curl -s -4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
Clients:    ${#domains[@]}
FreeCP:     v${FREECP_VERSION:-1.0.0}
Created at: $(date -u)
MANIFEST

    # ── 7. Create archive ─────────────────────────────────────
    freecp_step "Creating archive..."
    tar -czf "${tmp_dir}/${backup_name}" \
        -C "$tmp_dir" \
        "freecp_backup" \
        2>/dev/null

    local backup_size
    backup_size=$(du -sh "${tmp_dir}/${backup_name}" | cut -f1)

    # ── 8. Push to backup VPS ─────────────────────────────────
    freecp_step "Pushing to backup VPS (${backup_size})..."

    local remote_dir="${FREECP_BACKUP_VPS_PATH}/server"
    backup_ssh "mkdir -p ${remote_dir}" 2>/dev/null

    backup_rsync \
        "${tmp_dir}/${backup_name}" \
        "${remote_dir}/${backup_name}"

    # ── 9. Prune old server backups (keep last 8) ─────────────
    freecp_step "Pruning old server backups..."
    backup_prune "${remote_dir}" 8

    # ── 10. Also backup each client individually ──────────────
    freecp_step "Backing up individual clients..."
    for domain in "${domains[@]}"; do
        [[ -z "$domain" ]] && continue
        freecp_step "  → ${domain}"
        # Re-source to run backup inline
        local status
        status=$(client_get_status "$domain")
        local client_backup="${domain}_${timestamp}.tar.gz"
        local client_tmp
        client_tmp=$(mktemp -d)

        cp -r "${FREECP_CLIENTS_PATH}/${domain}" \
              "${client_tmp}/${domain}" 2>/dev/null || true

        [[ -f "${work_dir}/databases/$(state_get "$domain" "credentials" "db_name").sql" ]] && \
            cp "${work_dir}/databases/$(state_get "$domain" "credentials" "db_name").sql" \
               "${client_tmp}/database.sql" 2>/dev/null || true

        tar -czf "${client_tmp}/${client_backup}" \
            -C "$client_tmp" \
            "$domain" \
            2>/dev/null

        local client_remote="${FREECP_BACKUP_VPS_PATH}/clients/${domain}"
        backup_ssh "mkdir -p ${client_remote}" 2>/dev/null

        backup_rsync \
            "${client_tmp}/${client_backup}" \
            "${client_remote}/${client_backup}" \
            2>/dev/null || true

        backup_prune_client "$domain" "$status"
        rm -rf "$client_tmp"
    done

    # ── Cleanup ───────────────────────────────────────────────
    rm -rf "$tmp_dir"

    freecp_success_box "Server backup complete!"
    echo -e "  File:    ${backup_name}"
    echo -e "  Size:    ${backup_size}"
    echo -e "  Clients: ${#domains[@]}"
    echo -e "  Remote:  ${CYAN}${FREECP_BACKUP_VPS_HOST}:${remote_dir}/${NC}"
    echo ""
    echo -e "  To restore on a fresh VPS: ${CYAN}freecp restore-server${NC}"
    echo ""
}