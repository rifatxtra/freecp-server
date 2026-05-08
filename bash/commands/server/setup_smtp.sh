#!/usr/bin/env bash
# ============================================================
#  freecp setup-smtp
# ============================================================

cmd_setup_smtp() {
    freecp_header "FreeCP — SMTP Configuration"
    echo "  Configure SMTP for system emails and client alerts."
    echo ""

    local host port user pass encryption from_email from_name

    host=$(freecp_ask       "SMTP Host"                   "${FREECP_SMTP_HOST:-}")
    port=$(freecp_ask       "SMTP Port"                   "${FREECP_SMTP_PORT:-465}")
    user=$(freecp_ask       "SMTP Username"               "${FREECP_SMTP_USER:-}")
    pass=$(freecp_ask_secret "SMTP Password")
    encryption=$(freecp_ask "Encryption (ssl/tls/none)"   "${FREECP_SMTP_ENCRYPTION:-ssl}")
    from_email=$(freecp_ask "From Email"                  "${FREECP_SMTP_FROM:-noreply@rifatxtra.com}")
    from_name=$(freecp_ask  "From Name"                   "${FREECP_SMTP_FROM_NAME:-FreeCP}")

    echo ""
    freecp_step "Testing SMTP connection to ${host}:${port}..."

    if timeout 5 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
        freecp_ok "Connection successful"
    else
        freecp_warn "Connection test failed — saving config anyway"
    fi

    local config_file="/opt/freecp/config/freecp.conf"

    _smtp_set() {
        local key="$1" val="$2"
        if grep -q "^${key}=" "$config_file" 2>/dev/null; then
            sed -i "s|^${key}=.*|${key}=${val}|" "$config_file"
        else
            echo "${key}=${val}" >> "$config_file"
        fi
    }

    _smtp_set "SMTP_HOST"      "$host"
    _smtp_set "SMTP_PORT"      "$port"
    _smtp_set "SMTP_USER"      "$user"
    _smtp_set "SMTP_PASSWORD"  "$pass"
    _smtp_set "SMTP_ENCRYPTION" "$encryption"
    _smtp_set "SMTP_FROM"      "$from_email"
    _smtp_set "SMTP_FROM_NAME" "$from_name"

    freecp_ok "SMTP configuration saved."
    echo -e "  From: ${CYAN}${from_email}${NC}"
    echo ""
}