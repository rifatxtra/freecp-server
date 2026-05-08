#!/usr/bin/env bash
# ============================================================
#  FreeCP — Validation Helpers
# ============================================================

validate_domain() {
    if [[ ! "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        freecp_error "Invalid domain: $1"
        return 1
    fi
}

validate_plan() {
    if ! plan_valid "$1"; then
        freecp_error "Invalid plan: $1"
        echo "  Valid plans: lite, standard, plus, ultra"
        return 1
    fi
}

validate_php() {
    if ! php_valid "$1"; then
        freecp_error "Invalid PHP version: $1"
        echo "  Valid: php82, php83, php84"
        return 1
    fi
}

validate_email() {
    if [[ ! "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        freecp_error "Invalid email: $1"
        return 1
    fi
}

require_args() {
    local count="$1"
    local usage="$2"
    shift 2
    if [[ $# -lt $count ]]; then
        freecp_error "Missing arguments."
        echo "  Usage: freecp ${usage}"
        echo ""
        exit 1
    fi
}