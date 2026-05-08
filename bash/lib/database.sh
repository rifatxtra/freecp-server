#!/usr/bin/env bash
# ============================================================
#  FreeCP — Database Helpers (Shared MariaDB)
# ============================================================

_db_root_pass() { echo "${FREECP_DB_ROOT_PASSWORD:-}"; }

db_exec() {
    docker exec freecp_mariadb \
        mysql -uroot -p"$(_db_root_pass)" \
        -e "$1" 2>/dev/null
}

db_exec_silent() {
    docker exec freecp_mariadb \
        mysql -uroot -p"$(_db_root_pass)" \
        -sN -e "$1" 2>/dev/null
}

db_create() {
    local db_name="$1" db_user="$2" db_pass="$3"
    local max_conn="$4" max_queries="$5"

    db_exec "
        CREATE DATABASE IF NOT EXISTS \`${db_name}\`
            CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS '${db_user}'@'%' IDENTIFIED BY '${db_pass}';
        GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'%';
        ALTER USER '${db_user}'@'%'
            WITH MAX_CONNECTIONS_PER_HOUR ${max_conn}
                 MAX_QUERIES_PER_HOUR ${max_queries}
                 MAX_USER_CONNECTIONS ${max_conn};
        FLUSH PRIVILEGES;
    "
}

db_drop() {
    db_exec "
        DROP DATABASE IF EXISTS \`$1\`;
        DROP USER IF EXISTS '$2'@'%';
        FLUSH PRIVILEGES;
    "
}

db_size_mb() {
    db_exec_silent "
        SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
        FROM information_schema.tables
        WHERE table_schema = '$1';
    " | tail -1
}

db_exists() {
    local result
    result=$(db_exec_silent "SHOW DATABASES LIKE '$1';" | grep -c "$1" 2>/dev/null || echo 0)
    [[ "$result" -gt 0 ]]
}

db_generate_name()     { echo "fcp_${1//[.-]/_}"; }
db_generate_user()     { local u="u_${1//[.-]/_}"; echo "${u:0:32}"; }
db_generate_password() { openssl rand -hex 16; }