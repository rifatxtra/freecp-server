#!/usr/bin/env bash
# ============================================================
#  freecp list-domains <domain>
# ============================================================

cmd_list_domains() {
    require_args 1 "list-domains <domain>" "$@"

    local domain="${1,,}"
    client_assert_exists "$domain"

    freecp_header "Domains: ${domain}"

    local domains=()
    mapfile -t domains < <(client_get_domains "$domain" 2>/dev/null || true)

    if [[ ${#domains[@]} -eq 0 ]]; then
        freecp_warn "No domains registered."
        return
    fi

    printf "  ${BOLD}%-40s %-10s %-10s${NC}\n" "DOMAIN" "SSL" "TYPE"
    freecp_divider

    for d in "${domains[@]}"; do
        [[ -z "$d" ]] && continue

        # Check SSL
        local ssl_status="No"
        if [[ -f "/etc/letsencrypt/live/${d}/fullchain.pem" ]]; then
            # Check expiry
            local expiry
            expiry=$(openssl x509 -enddate -noout \
                -in "/etc/letsencrypt/live/${d}/fullchain.pem" 2>/dev/null \
                | cut -d= -f2)
            ssl_status="${GREEN}Yes${NC} (${expiry})"
        else
            ssl_status="${YELLOW}No${NC}"
        fi

        # Primary or addon
        local type
        [[ "$d" == "$domain" ]] && type="${CYAN}Primary${NC}" || type="Addon"

        printf "  %-40s %-20b %-10b\n" "$d" "$ssl_status" "$type"
    done

    echo ""
    echo -e "  Total: ${#domains[@]} domain(s)"
    echo -e "  Add:   ${CYAN}freecp add-domain ${domain} addon.com${NC}"
    echo -e "  SSL:   ${CYAN}freecp provision-ssl ${domain}${NC}"
    echo ""
}