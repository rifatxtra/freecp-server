#!/usr/bin/env bash
# freecp flush-redis <domain>

cmd_flush_redis() {
    require_args 1 "flush-redis <domain>" "$@"

    local domain="${1,,}"
    client_assert_exists "$domain"

    freecp_header "Flush Redis: ${domain}"

    local redis_prefix
    redis_prefix=$(state_get "$domain" "credentials" "redis_prefix")

    if [[ -z "$redis_prefix" ]]; then
        freecp_error "Redis prefix not found for '${domain}'"
        exit 1
    fi

    # ── Count keys first ──────────────────────────────────────
    local key_count
    key_count=$(docker exec freecp_redis \
        redis-cli --scan --pattern "${redis_prefix}*" 2>/dev/null | wc -l | xargs)

    echo -e "  Prefix:  ${CYAN}${redis_prefix}${NC}"
    echo -e "  Keys:    ${CYAN}${key_count}${NC}"
    echo ""

    if [[ "$key_count" -eq 0 ]]; then
        freecp_warn "No keys found with prefix '${redis_prefix}' — nothing to flush."
        exit 0
    fi

    freecp_confirm "Flush ${key_count} Redis keys for '${domain}'?" "y" || { echo "  Cancelled."; exit 0; }

    # ── Delete all keys with client prefix ────────────────────
    freecp_step "Flushing Redis keys..."

    local deleted
    deleted=$(docker exec freecp_redis \
        redis-cli --scan --pattern "${redis_prefix}*" 2>/dev/null \
        | xargs -r docker exec freecp_redis redis-cli del 2>/dev/null \
        | tail -1 || echo "0")

    freecp_ok "Flushed ${deleted:-0} Redis keys for '${domain}'"
    echo ""
}