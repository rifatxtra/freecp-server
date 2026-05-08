#!/usr/bin/env bash
# freecp list-php

cmd_list_php() {
    freecp_header "Available PHP Versions"

    local versions=("8.2" "8.3" "8.4")
    local default="8.3"

    for version in "${versions[@]}"; do
        local info
        info=$(php${version} --version 2>/dev/null | head -1 || true)

        if [[ -n "$info" ]]; then
            local tag=""
            [[ "$version" == "$default" ]] && tag=" ${YELLOW}(default)${NC}"
            echo -e "  PHP ${version}  ${GREEN}✓ installed${NC}${tag}"
            echo -e "    ${GRAY}${info}${NC}"
        else
            echo -e "  PHP ${version}  ${RED}✗ not installed${NC}"
        fi
        echo ""
    done

    echo -e "  Create: ${CYAN}freecp create-client domain.com lite php83${NC}"
    echo -e "  Switch: ${CYAN}freecp switch-php domain.com php82${NC}"
    echo ""
}