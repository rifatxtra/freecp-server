#!/usr/bin/env bash
# ============================================================
#  freecp read-key <domain>
# ============================================================

cmd_read_key() {
    require_args 1 "read-key <domain>" "$@"

    local domain="${1,,}"
    client_assert_exists "$domain"

    local key_path="${FREECP_CLIENTS_PATH}/${domain}/ssh/deploy_key"

    freecp_header "SSH Deploy Key: ${domain}"

    if [[ ! -f "$key_path" ]]; then
        freecp_error "SSH key not found for '${domain}'"
        echo "  Generate one: freecp regenerate-key ${domain}"
        exit 1
    fi

    # ── Show public key ───────────────────────────────────────
    echo -e "  ${BOLD}Public Key:${NC}"
    cat "${key_path}.pub"
    echo ""

    # ── Show private key ──────────────────────────────────────
    echo -e "  ${BOLD}Private Key${NC} ${YELLOW}(add to GitHub Actions → Settings → Secrets → FREECP_SSH_KEY):${NC}"
    echo ""
    cat "$key_path"
    echo ""

    # ── GitHub Actions usage hint ─────────────────────────────
    freecp_divider
    echo -e "  ${BOLD}GitHub Actions workflow example:${NC}"
    echo ""
    echo -e "  ${GRAY}env:"
    echo -e "    FREECP_SSH_KEY: \${{ secrets.FREECP_SSH_KEY }}"
    echo ""
    echo -e "  steps:"
    echo -e "    - name: Deploy"
    echo -e "      run: |"
    echo -e "        echo \"\$FREECP_SSH_KEY\" > /tmp/deploy_key"
    echo -e "        chmod 600 /tmp/deploy_key"
    echo -e "        rsync -avz -e \"ssh -i /tmp/deploy_key -o StrictHostKeyChecking=no\" \\"
    echo -e "          ./  root@YOUR_VPS_IP:${FREECP_CLIENTS_PATH}/${domain}/app/${NC}"
    echo ""
}