#!/usr/bin/env bash
# ============================================================
#  freecp setup-backup <vps-ip>
# ============================================================

cmd_setup_backup() {
    require_args 1 "setup-backup <vps-ip>" "$@"

    local backup_ip="$1"

    freecp_header "Setup Backup VPS"

    echo -e "  Backup VPS IP: ${CYAN}${backup_ip}${NC}"
    echo ""

    local backup_user backup_port backup_path
    backup_user=$(freecp_ask "SSH User"    "root")
    backup_port=$(freecp_ask "SSH Port"    "22")
    backup_path=$(freecp_ask "Remote Path" "/backups/freecp")
    echo ""

    # ── Test SSH connection ───────────────────────────────────
    freecp_step "Testing SSH connection to ${backup_ip}..."

    if ssh -o ConnectTimeout=10 \
           -o StrictHostKeyChecking=no \
           -p "$backup_port" \
           "${backup_user}@${backup_ip}" \
           "echo ok" > /dev/null 2>&1; then
        freecp_ok "SSH connection successful"
    else
        freecp_warn "SSH connection failed — check IP, port and SSH access"
        freecp_confirm "Save config anyway?" "n" || exit 0
    fi

    # ── Create remote directory ───────────────────────────────
    freecp_step "Creating remote backup directories..."
    ssh -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -p "$backup_port" \
        "${backup_user}@${backup_ip}" \
        "mkdir -p ${backup_path}/{clients,server} && chmod 700 ${backup_path}" \
        2>/dev/null \
        || freecp_warn "Could not create remote dirs — create manually on backup VPS"

    # ── Save to config ────────────────────────────────────────
    local config="/opt/freecp/config/freecp.conf"

    _bset() {
        local k="$1" v="$2"
        grep -q "^${k}=" "$config" 2>/dev/null \
            && sed -i "s|^${k}=.*|${k}=${v}|" "$config" \
            || echo "${k}=${v}" >> "$config"
    }

    _bset "BACKUP_ENABLED"  "true"
    _bset "BACKUP_VPS_HOST" "$backup_ip"
    _bset "BACKUP_VPS_USER" "$backup_user"
    _bset "BACKUP_VPS_PORT" "$backup_port"
    _bset "BACKUP_VPS_PATH" "$backup_path"

    export FREECP_BACKUP_ENABLED="true"
    export FREECP_BACKUP_VPS_HOST="$backup_ip"
    export FREECP_BACKUP_VPS_USER="$backup_user"
    export FREECP_BACKUP_VPS_PORT="$backup_port"
    export FREECP_BACKUP_VPS_PATH="$backup_path"

    freecp_success_box "Backup VPS configured!"
    echo -e "  Host: ${CYAN}${backup_ip}${NC}"
    echo -e "  Path: ${CYAN}${backup_path}${NC}"
    echo ""
    echo -e "  Test: ${CYAN}freecp backup-server${NC}"
    echo ""
}