#!/usr/bin/env bash
# ============================================================
#  freecp provision-ssl <domain>
# ============================================================

cmd_provision_ssl() {
    require_args 1 "provision-ssl <domain>" "$@"

    local domain="${1,,}"

    freecp_header "Provision SSL: ${domain}"

    # ── Check Nginx vhost exists ──────────────────────────────
    if [[ ! -f "${FREECP_NGINX_AVAILABLE}/${domain}.conf" ]]; then
        freecp_error "No Nginx vhost found for '${domain}'"
        echo "  Make sure the domain is registered:"
        echo "  freecp create-client / freecp add-domain"
        exit 1
    fi

    # ── Check DNS resolves to this server ─────────────────────
    freecp_step "Checking DNS resolution for ${domain}..."

    local server_ip resolved_ip
    server_ip=$(curl -s -4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    resolved_ip=$(dig +short "$domain" 2>/dev/null | tail -1)

    if [[ -z "$resolved_ip" ]]; then
        freecp_warn "DNS for '${domain}' does not resolve yet."
        freecp_warn "Point your DNS A record to: ${server_ip}"
        echo ""
        freecp_confirm "Try SSL provisioning anyway?" "n" || exit 0
    elif [[ "$resolved_ip" != "$server_ip" ]]; then
        freecp_warn "DNS resolves to ${resolved_ip} but this server is ${server_ip}"
        freecp_warn "SSL will fail until DNS is updated."
        echo ""
        freecp_confirm "Try SSL provisioning anyway?" "n" || exit 0
    else
        freecp_ok "DNS resolves correctly → ${resolved_ip}"
    fi

    # ── Run certbot ───────────────────────────────────────────
    freecp_step "Requesting Let's Encrypt certificate..."
    echo ""

    local email="${FREECP_SMTP_FROM:-admin@example.com}"

    certbot --nginx \
        -d "$domain" \
        -d "www.${domain}" \
        --email "$email" \
        --agree-tos \
        --non-interactive \
        --redirect \
        2>&1 | while IFS= read -r line; do
            echo "  ${line}"
        done

    # ── Verify cert ───────────────────────────────────────────
    echo ""
    if [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        local expiry
        expiry=$(openssl x509 -enddate -noout \
            -in "/etc/letsencrypt/live/${domain}/fullchain.pem" 2>/dev/null \
            | cut -d= -f2)

        freecp_success_box "SSL provisioned for ${domain}"
        echo -e "  Certificate valid until: ${GREEN}${expiry}${NC}"
        echo -e "  HTTPS:  ${CYAN}https://${domain}${NC}"
        echo ""
        echo -e "  Auto-renewal is handled by daily cron."
        echo -e "  Manual renew: ${CYAN}freecp renew-ssl ${domain}${NC}"
    else
        freecp_error "SSL provisioning may have failed — check output above."
        echo "  You can retry: freecp provision-ssl ${domain}"
    fi
    echo ""
}