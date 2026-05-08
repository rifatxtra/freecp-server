#!/usr/bin/env bash
# freecp set-suspend-page <domain> <path-to-html>

cmd_set_suspend_page() {
    require_args 2 "set-suspend-page <domain> <path-to-html>" "$@"

    local domain="${1,,}"
    local html_file="$2"

    client_assert_exists "$domain"

    if [[ ! -f "$html_file" ]]; then
        freecp_error "File not found: ${html_file}"
        exit 1
    fi

    local pages_path="${FREECP_CLIENTS_PATH}/${domain}/pages"
    mkdir -p "$pages_path"

    cp "$html_file" "${pages_path}/suspended.html"
    chmod 644 "${pages_path}/suspended.html"

    # If currently suspended, reload Nginx to pick up new page
    if client_is_suspended "$domain"; then
        nginx_reload
        freecp_ok "Suspended page updated and reloaded for '${domain}'"
    else
        freecp_ok "Suspended page updated for '${domain}'"
        echo -e "  Applies when: ${CYAN}freecp suspend-client ${domain}${NC}"
    fi
    echo ""
}