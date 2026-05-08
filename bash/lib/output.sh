#!/usr/bin/env bash
# ============================================================
#  FreeCP — Output Helpers
# ============================================================

freecp_header() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  ${BOLD}${WHITE}$1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo ""
}

freecp_success_box() {
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ${BOLD}✓ $1${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo ""
}

freecp_step()    { echo -e "${CYAN}[→]${NC} $1"; }
freecp_ok()      { echo -e "${GREEN}[✓]${NC} $1"; }
freecp_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
freecp_error()   { echo -e "${RED}[✗]${NC} $1"; }
freecp_divider() { echo -e "${GRAY}────────────────────────────────────────────────${NC}"; }

freecp_progress_bar() {
    local percent="${1:-0}"
    local label="${2:-}"
    local filled=$(( percent / 5 ))
    local empty=$(( 20 - filled ))
    local color=$GREEN

    (( percent > 75 )) && color=$YELLOW
    (( percent > 90 )) && color=$RED

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty;  i++)); do bar+="░"; done

    echo -e "  ${color}[${bar}]${NC} ${percent}% ${label}"
}

freecp_confirm() {
    local message="${1:-Are you sure?}"
    local default="${2:-n}"
    local response

    if [[ "$default" == "y" ]]; then
        read -rp "  ${message} [Y/n]: " response
        response="${response:-y}"
    else
        read -rp "  ${message} [y/N]: " response
        response="${response:-n}"
    fi

    [[ "${response,,}" == "y" ]]
}

freecp_ask() {
    local prompt="$1"
    local default="${2:-}"
    local result

    if [[ -n "$default" ]]; then
        read -rp "  ${prompt} [${default}]: " result
        echo "${result:-$default}"
    else
        read -rp "  ${prompt}: " result
        echo "$result"
    fi
}

freecp_ask_secret() {
    local prompt="$1"
    local result
    read -rsp "  ${prompt}: " result
    echo ""
    echo "$result"
}