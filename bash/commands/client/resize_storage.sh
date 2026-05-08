#!/usr/bin/env bash
# ============================================================
#  freecp resize-storage <domain> <size>
#  Example: freecp resize-storage example.com 20gb
# ============================================================

cmd_resize_storage() {
    require_args 2 "resize-storage <domain> <size>  (e.g. 20gb)" "$@"

    local domain="${1,,}"
    local size_input="${2,,}"

    client_assert_exists "$domain"

    # ── Parse size ────────────────────────────────────────────
    local new_size_gb
    new_size_gb=$(echo "$size_input" | tr -d 'gb ' | grep -E '^[0-9]+$' || echo "")

    if [[ -z "$new_size_gb" || "$new_size_gb" -lt 1 ]]; then
        freecp_error "Invalid size: '${size_input}'. Example: 20gb or 20"
        exit 1
    fi

    freecp_header "Resize Storage: ${domain}"

    local current_limit
    current_limit=$(state_get "$domain" "storage" "limit_gb")

    echo -e "  Current limit: ${CYAN}${current_limit} GB${NC}"
    echo -e "  New limit:     ${CYAN}${new_size_gb} GB${NC}"
    echo ""

    if [[ "$new_size_gb" -lt "$current_limit" ]]; then
        # Check current usage before shrinking
        local c_gb db_gb total_used
        c_gb=$(state_get "$domain" "storage" "container_gb"); c_gb="${c_gb:-0}"
        db_gb=$(state_get "$domain" "storage" "db_gb");       db_gb="${db_gb:-0}"
        total_used=$(awk "BEGIN {printf \"%d\", ${c_gb} + ${db_gb} + 0.5}")

        if [[ "$total_used" -gt "$new_size_gb" ]]; then
            freecp_error "Cannot shrink to ${new_size_gb}GB — current usage is ~${total_used}GB"
            echo "  Free up space first or set a larger limit."
            exit 1
        fi

        freecp_warn "Shrinking storage from ${current_limit}GB to ${new_size_gb}GB"
    fi

    freecp_confirm "Resize storage to ${new_size_gb}GB?" "y" || { echo "  Cancelled."; exit 0; }

    # ── Apply XFS quota ───────────────────────────────────────
    freecp_step "Applying storage quota..."

    local volume_mount
    volume_mount=$(docker volume inspect "$(docker_volume_name "$domain")" \
        --format '{{.Mountpoint}}' 2>/dev/null || echo "")

    if [[ -n "$volume_mount" && -d "$volume_mount" ]]; then
        local quota_bytes=$(( new_size_gb * 1024 * 1024 * 1024 ))
        # XFS project quota
        xfs_quota -x -c "limit bhard=${quota_bytes} ${volume_mount}" / 2>/dev/null || \
            freecp_warn "XFS quota not applied — ensure filesystem is XFS with pquota"
    fi

    # ── Update state ──────────────────────────────────────────
    freecp_step "Updating storage config..."
    state_set "$domain" "storage" "limit_gb" "$new_size_gb"

    # ── Restart container to pick up changes ──────────────────
    freecp_step "Restarting container..."
    docker_restart "$domain"

    freecp_ok "Storage resized to ${new_size_gb}GB"
    echo ""
}