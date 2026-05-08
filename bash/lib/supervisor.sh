#!/usr/bin/env bash
# ============================================================
#  FreeCP — Supervisor Helpers
# ============================================================

supervisor_create() {
    local domain="$1" plan="$2"
    local container_name queue_workers octane_workers is_octane template config_path

    container_name=$(docker_container_name "$domain")
    queue_workers=$(plan_get "$plan" "queue_workers")
    octane_workers=$(plan_get "$plan" "octane_workers")
    is_octane=$(plan_get "$plan" "octane")
    config_path="${FREECP_SUPERVISOR_CONF}/${container_name}.conf"

    if [[ "$is_octane" == "true" ]]; then
        template="${FREECP_TEMPLATES_PATH}/supervisor/client-octane.conf"
    else
        template="${FREECP_TEMPLATES_PATH}/supervisor/client.conf"
    fi

    sed \
        -e "s|{{DOMAIN}}|${domain}|g" \
        -e "s|{{CONTAINER_NAME}}|${container_name}|g" \
        -e "s|{{QUEUE_WORKERS}}|${queue_workers}|g" \
        -e "s|{{OCTANE_WORKERS}}|${octane_workers}|g" \
        "$template" > "$config_path"

    chmod 644 "$config_path"
    supervisor_reload
}

supervisor_remove() {
    local container_name config_path
    container_name=$(docker_container_name "$1")
    config_path="${FREECP_SUPERVISOR_CONF}/${container_name}.conf"
    supervisor_stop "$1"
    [[ -f "$config_path" ]] && rm -f "$config_path"
    supervisor_reload
}

supervisor_start()   { supervisorctl start   "$(docker_container_name "$1"):*" > /dev/null 2>&1 || true; }
supervisor_stop()    { supervisorctl stop    "$(docker_container_name "$1"):*" > /dev/null 2>&1 || true; }
supervisor_restart() { supervisorctl restart "$(docker_container_name "$1"):*" > /dev/null 2>&1 || true; }

supervisor_status() {
    supervisorctl status "$(docker_container_name "$1"):*" 2>/dev/null || true
}

supervisor_reload() {
    supervisorctl reread > /dev/null 2>&1 || true
    supervisorctl update > /dev/null 2>&1 || true
}

supervisor_update() {
    supervisor_stop "$1"
    supervisor_remove "$1"
    supervisor_create "$1" "$2"
}