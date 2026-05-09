#!/usr/bin/env bash
# ============================================================
#  freecp regenerate-key <domain>
# ============================================================

cmd_regenerate_key() {
    require_args 1 "regenerate-key <domain>" "$@"

    local domain="${1,,}"
    client_assert_exists "$domain"

    freecp_header "Regenerate SSH Key: ${domain}"

    echo -e "  ${YELLOW}This will invalidate the current deploy key.${NC}"
    echo -e "  ${YELLOW}You must update the key in GitHub Actions secrets after.${NC}"
    echo ""

    freecp_confirm "Regenerate SSH deploy key for '${domain}'?" "y" || { echo "  Cancelled."; exit 0; }

    local ssh_dir="${FREECP_CLIENTS_PATH}/${domain}/ssh"
    local key_path="${ssh_dir}/deploy_key"
    local auth_keys="/root/.ssh/authorized_keys"

    # ── Remove old key from authorized_keys ───────────────────
    freecp_step "Removing old key from authorized_keys..."
    if [[ -f "$auth_keys" && -f "${key_path}.pub" ]]; then
        local old_pub
        old_pub=$(cat "${key_path}.pub")
        # Remove matching line
        grep -v -F "$old_pub" "$auth_keys" > "${auth_keys}.tmp" 2>/dev/null \
            && mv "${auth_keys}.tmp" "$auth_keys" \
            || true
        chmod 600 "$auth_keys"
    fi

    # ── Remove old comment line ───────────────────────────────
    if [[ -f "$auth_keys" ]]; then
        sed -i "/^# freecp-${domain}$/d" "$auth_keys"
    fi

    # ── Remove old key files ──────────────────────────────────
    rm -f "$key_path" "${key_path}.pub"

    # ── Generate new key pair ─────────────────────────────────
    freecp_step "Generating new ED25519 key pair..."
    mkdir -p "$ssh_dir" && chmod 700 "$ssh_dir"

    ssh-keygen -t ed25519 \
        -C "freecp-deploy-${domain}" \
        -f "$key_path" \
        -N "" > /dev/null 2>&1

    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"

    # ── Register new public key ───────────────────────────────
    freecp_step "Registering new public key..."
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    touch "$auth_keys" && chmod 600 "$auth_keys"

    echo "# freecp-${domain}"   >> "$auth_keys"
    cat "${key_path}.pub"       >> "$auth_keys"

    # ── Print new private key ─────────────────────────────────
    freecp_success_box "SSH key regenerated for '${domain}'"
    echo -e "  ${BOLD}New Private Key${NC} ${YELLOW}(update GitHub Actions secret FREECP_SSH_KEY):${NC}"
    echo ""
    cat "$key_path"
    echo ""
    freecp_divider
    echo -e "  ${RED}Important: Update this key in GitHub Actions secrets now.${NC}"
    echo -e "  ${RED}Deployments will fail until the secret is updated.${NC}"
    echo ""
}