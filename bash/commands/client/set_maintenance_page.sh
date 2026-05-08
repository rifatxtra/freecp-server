#!/usr/bin/env bash
# freecp set-maintenance-page <domain> <path-to-html>

cmd_set_maintenance_page() {
    require_args 2 "set-maintenance-page <domain> <path-to-html>" "$@"

    local domain="${1,,}"
    local html_file="$2"

    client_assert_exists "$domain"

    if [[ ! -f "$html_file" ]]; then
        freecp_error "File not found: ${html_file}"
        exit 1
    fi

    local pages_path="${FREECP_CLIENTS_PATH}/${domain}/pages"
    mkdir -p "$pages_path"

    cp "$html_file" "${pages_path}/maintenance.html"
    chmod 644 "${pages_path}/maintenance.html"

    freecp_ok "Maintenance page updated for '${domain}'"
    echo -e "  Source: ${html_file}"
    echo -e "  Enable: ${CYAN}freecp maintenance-client ${domain} on${NC}"
    echo ""
}