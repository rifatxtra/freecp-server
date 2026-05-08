#!/usr/bin/env bash
# ============================================================
#  freecp renew-ssl <domain>
# ============================================================

cmd_renew_ssl() {
    require_args 1 "renew-ssl <domain>" "$@"

    local domain="${1,,}"

    freecp_header "Renew SSL: ${domain}"

    # ── Check cert exists ─────────────────────────────────────
    if [[ ! -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        freecp_error "No SSL certificate found for '${domain}'"
        echo "  Provision one first: freecp provision-ssl ${domain}"
        exit 1
    fi

    # ── Show current expiry ───────────────────────────────────
    local expiry
    expiry=$(openssl x509 -enddate -noout \
        -in "/etc/letsencrypt/live/${domain}/fullchain.pem" 2>/dev/null \
        | cut -d= -f2)
    echo -e "  Current expiry: ${YELLOW}${expiry}${NC}"
    echo ""

    freecp_step "Renewing certificate for ${domain}..."

    certbot renew \
        --cert-name "$domain" \
        --nginx \
        --non-interactive \
        2>&1 | while IFS= read -r line; do
            echo "  ${line}"
        done

    echo ""

    local new_expiry
    new_expiry=$(openssl x509 -enddate -noout \
        -in "/etc/letsencrypt/live/${domain}/fullchain.pem" 2>/dev/null \
        | cut -d= -f2)

    if [[ "$new_expiry" != "$expiry" ]]; then
        freecp_ok "Certificate renewed."
        echo -e "  New expiry: ${GREEN}${new_expiry}${NC}"
    else
        freecp_warn "Certificate not renewed — it may not be due yet (renews when <30 days left)."
        echo -e "  Expiry: ${expiry}"
    fi
    echo ""
}