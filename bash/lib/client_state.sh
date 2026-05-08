#!/usr/bin/env bash
# ============================================================
#  FreeCP — Client State Manager
#
#  /opt/freecp/clients/{domain}/
#    config        plan, php_version, uid, gid, created_at
#    credentials   db_name, db_user, db_pass, app_key, redis_prefix
#    status        active | suspended | deleted | maintenance
#    bandwidth     used_gb, limit_gb, reset_date, throttled
#    storage       container_gb, db_gb, limit_gb
#    email         client alert email (single line)
#    domains       one domain per line
#    databases     one db name per line
# ============================================================

# ── Path helpers ─────────────────────────────────────────────
client_path()   { echo "${FREECP_CLIENTS_PATH}/$1"; }
client_file()   { echo "${FREECP_CLIENTS_PATH}/$1/$2"; }
client_exists() { [[ -d "${FREECP_CLIENTS_PATH}/$1" ]]; }

client_assert_exists() {
    if ! client_exists "$1"; then
        freecp_error "Client '$1' not found."
        exit 1
    fi
}

# ── Create directory structure ────────────────────────────────
client_create_dirs() {
    local base="${FREECP_CLIENTS_PATH}/$1"
    mkdir -p "${base}"/{app,logs,pages,nginx,supervisor,ssh}
    chmod 700 "$base"
    chmod 755 "${base}/app" "${base}/logs" "${base}/pages"
    chmod 700 "${base}/ssh"
}

# ── Key=value read/write ──────────────────────────────────────
state_get() {
    local domain="$1" file="$2" key="$3"
    local filepath
    filepath=$(client_file "$domain" "$file")
    [[ ! -f "$filepath" ]] && echo "" && return
    grep "^${key}=" "$filepath" 2>/dev/null | head -1 | cut -d'=' -f2- | xargs
}

state_set() {
    local domain="$1" file="$2" key="$3" value="$4"
    local filepath
    filepath=$(client_file "$domain" "$file")
    touch "$filepath"
    if grep -q "^${key}=" "$filepath" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$filepath"
    else
        echo "${key}=${value}" >> "$filepath"
    fi
    chmod 600 "$filepath"
}

state_write() {
    # state_write <domain> <file> "key=val" "key=val" ...
    local domain="$1" file="$2"
    local filepath
    filepath=$(client_file "$domain" "$file")
    shift 2
    printf '%s\n' "$@" > "$filepath"
    chmod 600 "$filepath"
}

state_read_raw() {
    local filepath
    filepath=$(client_file "$1" "$2")
    [[ -f "$filepath" ]] && cat "$filepath" | xargs || echo ""
}

state_write_raw() {
    local filepath
    filepath=$(client_file "$1" "$2")
    echo "$3" > "$filepath"
    chmod 600 "$filepath"
}

# ── Status ───────────────────────────────────────────────────
client_get_status()   { state_read_raw "$1" "status"; }
client_set_status()   { state_write_raw "$1" "status" "$2"; }
client_is_active()      { [[ "$(client_get_status "$1")" == "active" ]]; }
client_is_suspended()   { [[ "$(client_get_status "$1")" == "suspended" ]]; }
client_is_deleted()     { [[ "$(client_get_status "$1")" == "deleted" ]]; }
client_is_maintenance() { [[ "$(client_get_status "$1")" == "maintenance" ]]; }

# ── Shortcuts ────────────────────────────────────────────────
client_get_plan()  { state_get "$1" "config" "plan"; }
client_get_php()   { state_get "$1" "config" "php_version"; }
client_get_uid()   { state_get "$1" "config" "uid"; }
client_get_email() { state_read_raw "$1" "email"; }

# ── Domains list ─────────────────────────────────────────────
client_get_domains() {
    local filepath
    filepath=$(client_file "$1" "domains")
    [[ -f "$filepath" ]] && grep -v '^[[:space:]]*$' "$filepath" || true
}

client_add_domain() {
    local filepath
    filepath=$(client_file "$1" "domains")
    touch "$filepath"
    grep -q "^$2$" "$filepath" 2>/dev/null || echo "$2" >> "$filepath"
}

client_remove_domain() {
    local filepath
    filepath=$(client_file "$1" "domains")
    [[ -f "$filepath" ]] && sed -i "/^$2$/d" "$filepath"
}

# ── Databases list ───────────────────────────────────────────
client_get_databases() {
    local filepath
    filepath=$(client_file "$1" "databases")
    [[ -f "$filepath" ]] && grep -v '^[[:space:]]*$' "$filepath" || true
}

client_add_database() {
    local filepath
    filepath=$(client_file "$1" "databases")
    touch "$filepath"
    echo "$2" >> "$filepath"
}

client_remove_database() {
    local filepath
    filepath=$(client_file "$1" "databases")
    [[ -f "$filepath" ]] && sed -i "/^$2$/d" "$filepath"
}

# ── List all clients ──────────────────────────────────────────
client_list_all() {
    [[ ! -d "$FREECP_CLIENTS_PATH" ]] && return
    for dir in "${FREECP_CLIENTS_PATH}"/*/; do
        [[ -d "$dir" ]] && basename "$dir"
    done
}

# ── Generate unique UID from domain ──────────────────────────
client_generate_uid() {
    local hash
    hash=$(echo "$1" | cksum | cut -d' ' -f1)
    echo $(( 2000 + (hash % 58000) ))
}