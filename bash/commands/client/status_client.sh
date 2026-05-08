#!/usr/bin/env bash
# freecp status-client <domain>

cmd_status_client() {
    require_args 1 "status-client <domain>" "$@"
    local domain="${1,,}"
    client_assert_exists "$domain"

    local status plan php uid created email price color
    status=$(client_get_status "$domain")
    plan=$(state_get "$domain" "config" "plan")
    php=$(state_get "$domain" "config" "php_version")
    uid=$(state_get "$domain" "config" "uid")
    created=$(state_get "$domain" "config" "created_at")
    email=$(client_get_email "$domain")
    price=$(plan_get "${plan:-lite}" "price")

    case "$status" in
        active)      color=$GREEN ;;
        suspended)   color=$YELLOW ;;
        deleted)     color=$RED ;;
        maintenance) color=$CYAN ;;
        *)           color=$NC ;;
    esac

    freecp_header "Status: ${domain}"

    echo -e "  ${BOLD}Status:${NC}       ${color}${status^^}${NC}"
    echo -e "  ${BOLD}Plan:${NC}         ${plan^^} — ${price} BDT/mo"
    echo -e "  ${BOLD}PHP:${NC}          ${php}"
    echo -e "  ${BOLD}Created:${NC}      ${created:0:16}"
    echo -e "  ${BOLD}UID/GID:${NC}      ${uid}"
    echo ""

    # Container
    local container_name
    container_name=$(docker_container_name "$domain")

    if docker_container_running "$domain"; then
        local stats cpu mem net
        stats=$(docker_stats "$domain")
        cpu=$(echo "$stats" | cut -d'|' -f1)
        mem=$(echo "$stats" | cut -d'|' -f2)
        net=$(echo "$stats" | cut -d'|' -f4)
        echo -e "  ${BOLD}Container:${NC}    ${container_name} ${GREEN}[RUNNING]${NC}"
        echo -e "  ${BOLD}CPU:${NC}          ${cpu}"
        echo -e "  ${BOLD}Memory:${NC}       ${mem}"
        echo -e "  ${BOLD}Network I/O:${NC}  ${net}"
    else
        echo -e "  ${BOLD}Container:${NC}    ${container_name} ${RED}[STOPPED]${NC}"
    fi

    echo ""

    # Domains
    echo -e "  ${BOLD}Domains:${NC}"
    while IFS= read -r d; do
        echo "    · $d"
    done < <(client_get_domains "$domain")
    echo ""

    # Databases
    local db_count max_db primary_db
    db_count=$(client_get_databases "$domain" | wc -l | xargs)
    max_db=$(plan_get "${plan:-lite}" "max_databases")
    primary_db=$(state_get "$domain" "credentials" "db_name")
    echo -e "  ${BOLD}Databases:${NC}    ${db_count} / ${max_db}"
    echo -e "  ${BOLD}Primary DB:${NC}   ${primary_db}"
    echo ""
    echo -e "  ${BOLD}Alert Email:${NC}  ${email:-${YELLOW}not set${NC}}"
    echo ""
    echo -e "  Run ${CYAN}freecp check-usage ${domain}${NC} for full resource details."
    echo ""
}