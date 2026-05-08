#!/usr/bin/env bash
# ============================================================
#  FreeCP — Config Loader + Plan Definitions
# ============================================================

# ── Default paths ─────────────────────────────────────────────
FREECP_CLIENTS_PATH="/opt/freecp/clients"
FREECP_TEMPLATES_PATH="/opt/freecp/templates"
FREECP_LOGS_PATH="/opt/freecp/logs"
FREECP_BACKUPS_PATH="/opt/freecp/backups"
FREECP_NGINX_AVAILABLE="/etc/nginx/sites-available"
FREECP_NGINX_ENABLED="/etc/nginx/sites-enabled"
FREECP_SUPERVISOR_CONF="/etc/supervisor/conf.d"

# ── Load freecp.conf ──────────────────────────────────────────
freecp_load_config() {
    local config_file="${FREECP_PATH}/config/freecp.conf"

    if [[ ! -f "$config_file" ]]; then
        # On first run (init-server not yet run), skip silently
        return
    fi

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${key// }" ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        export "FREECP_${key}"="$value"
    done < "$config_file"
}

# ── Plan data ─────────────────────────────────────────────────
# Usage: plan_get <plan> <key>
plan_get() {
    local plan="$1"
    local key="$2"

    case "${plan}:${key}" in
        # ── Lite ──────────────────────────────────────────────
        lite:name)                echo "Lite" ;;
        lite:price)               echo "250" ;;
        lite:ram_reservation)     echo "128m" ;;
        lite:ram_limit)           echo "512m" ;;
        lite:cpu_limit)           echo "0.25" ;;
        lite:storage_gb)          echo "8" ;;
        lite:bandwidth_gb)        echo "100" ;;
        lite:bandwidth_throttle)  echo "1mbit" ;;
        lite:peak_users)          echo "20" ;;
        lite:fpm_workers)         echo "5" ;;
        lite:octane)              echo "false" ;;
        lite:octane_workers)      echo "0" ;;
        lite:queue_workers)       echo "1" ;;
        lite:max_databases)       echo "2" ;;
        lite:db_max_connections)  echo "10" ;;
        lite:db_max_queries)      echo "10000" ;;
        lite:pids_limit)          echo "50" ;;
        lite:redis_memory)        echo "32m" ;;
        lite:swap_grace_gb)       echo "0.5" ;;

        # ── Standard ──────────────────────────────────────────
        standard:name)                echo "Standard" ;;
        standard:price)               echo "550" ;;
        standard:ram_reservation)     echo "256m" ;;
        standard:ram_limit)           echo "1g" ;;
        standard:cpu_limit)           echo "0.50" ;;
        standard:storage_gb)          echo "15" ;;
        standard:bandwidth_gb)        echo "250" ;;
        standard:bandwidth_throttle)  echo "2mbit" ;;
        standard:peak_users)          echo "60" ;;
        standard:fpm_workers)         echo "10" ;;
        standard:octane)              echo "false" ;;
        standard:octane_workers)      echo "0" ;;
        standard:queue_workers)       echo "2" ;;
        standard:max_databases)       echo "5" ;;
        standard:db_max_connections)  echo "20" ;;
        standard:db_max_queries)      echo "25000" ;;
        standard:pids_limit)          echo "100" ;;
        standard:redis_memory)        echo "64m" ;;
        standard:swap_grace_gb)       echo "0.5" ;;

        # ── Plus ──────────────────────────────────────────────
        plus:name)                echo "Plus" ;;
        plus:price)               echo "950" ;;
        plus:ram_reservation)     echo "512m" ;;
        plus:ram_limit)           echo "2g" ;;
        plus:cpu_limit)           echo "1.00" ;;
        plus:storage_gb)          echo "30" ;;
        plus:bandwidth_gb)        echo "500" ;;
        plus:bandwidth_throttle)  echo "5mbit" ;;
        plus:peak_users)          echo "150" ;;
        plus:fpm_workers)         echo "20" ;;
        plus:octane)              echo "false" ;;
        plus:octane_workers)      echo "0" ;;
        plus:queue_workers)       echo "4" ;;
        plus:max_databases)       echo "10" ;;
        plus:db_max_connections)  echo "40" ;;
        plus:db_max_queries)      echo "60000" ;;
        plus:pids_limit)          echo "200" ;;
        plus:redis_memory)        echo "128m" ;;
        plus:swap_grace_gb)       echo "1" ;;

        # ── Ultra ─────────────────────────────────────────────
        ultra:name)                echo "Ultra" ;;
        ultra:price)               echo "1850" ;;
        ultra:ram_reservation)     echo "1g" ;;
        ultra:ram_limit)           echo "4g" ;;
        ultra:cpu_limit)           echo "2.00" ;;
        ultra:storage_gb)          echo "50" ;;
        ultra:bandwidth_gb)        echo "1024" ;;
        ultra:bandwidth_throttle)  echo "10mbit" ;;
        ultra:peak_users)          echo "400+" ;;
        ultra:fpm_workers)         echo "0" ;;
        ultra:octane)              echo "true" ;;
        ultra:octane_workers)      echo "4" ;;
        ultra:queue_workers)       echo "8" ;;
        ultra:max_databases)       echo "20" ;;
        ultra:db_max_connections)  echo "80" ;;
        ultra:db_max_queries)      echo "150000" ;;
        ultra:pids_limit)          echo "400" ;;
        ultra:redis_memory)        echo "256m" ;;
        ultra:swap_grace_gb)       echo "1" ;;

        *) echo "" ;;
    esac
}

# ── Validation helpers ────────────────────────────────────────
plan_valid() {
    case "$1" in
        lite|standard|plus|ultra) return 0 ;;
        *) return 1 ;;
    esac
}

php_valid() {
    local v
    v=$(normalize_php "$1")
    case "$v" in
        8.2|8.3|8.4) return 0 ;;
        *) return 1 ;;
    esac
}

normalize_php() {
    local v="${1,,}"
    v="${v//php/}"
    # Convert 83 → 8.3
    if [[ ${#v} -eq 2 && "$v" =~ ^[0-9]{2}$ ]]; then
        v="${v:0:1}.${v:1:1}"
    fi
    echo "$v"
}