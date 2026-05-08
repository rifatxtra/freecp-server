#!/usr/bin/env bash
# freecp logs-client <domain> [type] [--lines=50] [--follow]

cmd_logs_client() {
    require_args 1 "logs-client <domain> [error|access|queue|scheduler|fpm|octane|all] [--lines=50] [--follow]" "$@"

    local domain="${1,,}"
    local type="${2:-error}"
    local lines=50
    local follow=false

    client_assert_exists "$domain"

    for arg in "$@"; do
        [[ "$arg" == --lines=* ]] && lines="${arg#--lines=}"
        [[ "$arg" == --follow  ]] && follow=true
    done

    local log_dir="${FREECP_CLIENTS_PATH}/${domain}/logs"

    declare -A log_files=(
        [error]="${log_dir}/error.log"
        [access]="${log_dir}/access.log"
        [queue]="${log_dir}/queue.log"
        [scheduler]="${log_dir}/scheduler.log"
        [fpm]="${log_dir}/fpm.log"
        [octane]="${log_dir}/octane.log"
    )

    if [[ "$type" == "all" ]]; then
        for name in error access queue scheduler fpm octane; do
            local file="${log_files[$name]}"
            [[ -f "$file" ]] || continue
            echo ""
            echo -e "${CYAN}── ${name}.log ──────────────────────${NC}"
            tail -n "$lines" "$file"
        done
        return
    fi

    if [[ -z "${log_files[$type]+isset}" ]]; then
        freecp_error "Unknown log type: ${type}"
        echo "  Valid: error, access, queue, scheduler, fpm, octane, all"
        exit 1
    fi

    local file="${log_files[$type]}"

    if [[ ! -f "$file" ]]; then
        freecp_warn "Log file not found: ${file}"
        return
    fi

    echo ""
    echo -e "${CYAN}  ${domain} — ${type}.log${NC}"
    freecp_divider

    if $follow; then
        tail -f -n "$lines" "$file"
    else
        tail -n "$lines" "$file" | while IFS= read -r line; do
            if echo "$line" | grep -qiE "error|fatal|exception"; then
                echo -e "${RED}${line}${NC}"
            elif echo "$line" | grep -qi "warn"; then
                echo -e "${YELLOW}${line}${NC}"
            else
                echo "$line"
            fi
        done
    fi
    echo ""
}