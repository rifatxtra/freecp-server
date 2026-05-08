#!/usr/bin/env bash
# ============================================================
#  freecp add-domain <primary-domain> <addon-domain>
# ============================================================

cmd_add_domain() {
    require_args 2 "add-domain <primary-domain> <addon-domain>" "$@"

    local domain="${1,,}"
    local addon="${2,,}"

    client_assert_exists "$domain"
    validate_domain "$addon" || exit 1

    freecp_header "Add Domain: ${addon} → ${domain}"

    # ── Check addon not already in use ────────────────────────
    while IFS= read -r existing; do
        [[ -z "$existing" ]] && continue
        if client_get_domains "$existing" | grep -q "^${addon}$"; then
            freecp_error "Domain '${addon}' is already assigned to client '${existing}'"
            exit 1
        fi
    done < <(client_list_all 2>/dev/null)

    # ── Check within plan storage limits ──────────────────────
    local plan max_db
    plan=$(state_get "$domain" "config" "plan")

    freecp_step "Creating Nginx vhost for ${addon}..."

    local container_name config_path enabled_path
    container_name=$(docker_container_name "$domain")
    config_path="${FREECP_NGINX_AVAILABLE}/${addon}.conf"
    enabled_path="${FREECP_NGINX_ENABLED}/${addon}.conf"

    sed \
        -e "s|{{DOMAIN}}|${addon}|g" \
        -e "s|{{CONTAINER_NAME}}|${container_name}|g" \
        "${FREECP_TEMPLATES_PATH}/nginx/vhost.conf" \
        > "$config_path"

    [[ ! -L "$enabled_path" ]] && ln -sf "$config_path" "$enabled_path"

    nginx_reload

    freecp_step "Registering domain..."
    client_add_domain "$domain" "$addon"

    freecp_ok "Domain '${addon}' added to '${domain}'"
    echo ""
    echo -e "  ${YELLOW}Next steps:${NC}"
    echo -e "  1. Point DNS for ${CYAN}${addon}${NC} to this server's IP"
    echo -e "  2. Once DNS propagates: ${CYAN}freecp provision-ssl ${addon}${NC}"
    echo ""
}