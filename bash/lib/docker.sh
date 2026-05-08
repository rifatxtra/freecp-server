#!/usr/bin/env bash
# ============================================================
#  FreeCP — Docker Helpers
# ============================================================

docker_container_name() {
    local safe="${1//[.-]/_}"
    echo "freecp_client_${safe}"
}

docker_volume_name() {
    local safe="${1//[.-]/_}"
    echo "freecp_vol_${safe}"
}

docker_container_exists() {
    docker ps -a --format '{{.Names}}' 2>/dev/null \
        | grep -q "^$(docker_container_name "$1")$"
}

docker_container_running() {
    docker ps --format '{{.Names}}' 2>/dev/null \
        | grep -q "^$(docker_container_name "$1")$"
}

docker_start()   { docker start   "$(docker_container_name "$1")" > /dev/null; }
docker_stop()    { docker stop    "$(docker_container_name "$1")" > /dev/null 2>&1 || true; }
docker_restart() { docker restart "$(docker_container_name "$1")" > /dev/null; }

docker_remove() {
    local name
    name=$(docker_container_name "$1")
    docker stop "$name"   > /dev/null 2>&1 || true
    docker rm -f "$name"  > /dev/null 2>&1 || true
}

docker_create_volume() { docker volume create "$(docker_volume_name "$1")" > /dev/null; }
docker_remove_volume() { docker volume rm "$(docker_volume_name "$1")"     > /dev/null 2>&1 || true; }

docker_exec() {
    local domain="$1"; shift
    docker exec "$(docker_container_name "$domain")" "$@"
}

docker_stats() {
    local name
    name=$(docker_container_name "$1")
    docker stats "$name" --no-stream \
        --format '{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}|{{.BlockIO}}' \
        2>/dev/null || echo "0%|0B/0B|0%|0B/0B|0B/0B"
}

# ── Calculate memory-swap (RAM + swap grace) ──────────────────
docker_calc_swap() {
    local ram_limit="$1"
    local swap_grace_gb="$2"
    local ram_mb swap_mb total_mb

    if [[ "$ram_limit" == *g ]]; then
        ram_mb=$(( ${ram_limit//g/} * 1024 ))
    else
        ram_mb=${ram_limit//m/}
    fi

    # swap_grace_gb may be decimal (0.5), use awk
    swap_mb=$(awk "BEGIN {printf \"%d\", $swap_grace_gb * 1024}")
    total_mb=$(( ram_mb + swap_mb ))

    if (( total_mb >= 1024 )); then
        awk "BEGIN {printf \"%.1fg\", $total_mb / 1024}"
    else
        echo "${total_mb}m"
    fi
}

# ── Update resource limits (plan upgrade/downgrade) ───────────
docker_update_limits() {
    local domain="$1" plan="$2"
    local name
    name=$(docker_container_name "$domain")

    local ram_limit ram_res cpu pids swap_grace swap_total
    ram_limit=$(plan_get "$plan" "ram_limit")
    ram_res=$(plan_get "$plan" "ram_reservation")
    cpu=$(plan_get "$plan" "cpu_limit")
    pids=$(plan_get "$plan" "pids_limit")
    swap_grace=$(plan_get "$plan" "swap_grace_gb")
    swap_total=$(docker_calc_swap "$ram_limit" "$swap_grace")

    docker update \
        --memory="$ram_limit" \
        --memory-reservation="$ram_res" \
        --memory-swap="$swap_total" \
        --cpus="$cpu" \
        --pids-limit="$pids" \
        "$name" > /dev/null
}

# ── Apply bandwidth throttle via tc ──────────────────────────
docker_apply_throttle() {
    local domain="$1" rate="$2"
    local name pid
    name=$(docker_container_name "$domain")
    pid=$(docker inspect --format '{{.State.Pid}}' "$name" 2>/dev/null)
    [[ -z "$pid" || "$pid" == "0" ]] && return 1
    nsenter -t "$pid" -n -- tc qdisc del dev eth0 root 2>/dev/null || true
    nsenter -t "$pid" -n -- tc qdisc add dev eth0 root tbf \
        rate "$rate" burst 32kbit latency 400ms
}

docker_remove_throttle() {
    local name pid
    name=$(docker_container_name "$1")
    pid=$(docker inspect --format '{{.State.Pid}}' "$name" 2>/dev/null)
    [[ -z "$pid" || "$pid" == "0" ]] && return 0
    nsenter -t "$pid" -n -- tc qdisc del dev eth0 root 2>/dev/null || true
}

# ── Build and run client container ───────────────────────────
docker_run_client() {
    local domain="$1" plan="$2" php_version="$3" uid="$4"

    local name volume client_path templates_path
    name=$(docker_container_name "$domain")
    volume=$(docker_volume_name "$domain")
    client_path="${FREECP_CLIENTS_PATH}/${domain}"
    templates_path="${FREECP_TEMPLATES_PATH}"

    local ram_limit ram_res cpu pids swap_grace swap_total is_octane dockerfile
    ram_limit=$(plan_get "$plan" "ram_limit")
    ram_res=$(plan_get "$plan" "ram_reservation")
    cpu=$(plan_get "$plan" "cpu_limit")
    pids=$(plan_get "$plan" "pids_limit")
    swap_grace=$(plan_get "$plan" "swap_grace_gb")
    swap_total=$(docker_calc_swap "$ram_limit" "$swap_grace")
    is_octane=$(plan_get "$plan" "octane")

    [[ "$is_octane" == "true" ]] && dockerfile="Dockerfile.octane" || dockerfile="Dockerfile"

    # Build image
    freecp_step "Building Docker image (PHP ${php_version})..."
    docker build \
        --file "${templates_path}/docker/${dockerfile}" \
        --build-arg PHP_VERSION="$php_version" \
        --build-arg CLIENT_ID="${domain//[.-]/_}" \
        --build-arg CLIENT_UID="$uid" \
        --build-arg CLIENT_GID="$uid" \
        --tag "freecp/${domain}:latest" \
        "${templates_path}/docker" \
        > /dev/null 2>&1 || {
            freecp_error "Docker build failed"
            return 1
        }

    # Run container
    freecp_step "Starting container..."
    docker run -d \
        --name "$name" \
        --restart unless-stopped \
        --memory="$ram_limit" \
        --memory-reservation="$ram_res" \
        --memory-swap="$swap_total" \
        --cpus="$cpu" \
        --pids-limit="$pids" \
        --security-opt no-new-privileges:true \
        --cap-drop ALL \
        --cap-add NET_BIND_SERVICE \
        --cap-add CHOWN \
        --cap-add SETUID \
        --cap-add SETGID \
        --cap-add DAC_OVERRIDE \
        --user "${uid}:${uid}" \
        -v "${volume}:/var/www/app/storage" \
        -v "${client_path}/app:/var/www/app:ro" \
        -v "${client_path}/.env:/var/www/app/.env:ro" \
        --env-file "${client_path}/.env" \
        --log-driver json-file \
        --log-opt max-size=10m \
        --log-opt max-file=2 \
        --tmpfs /tmp:size=64m,noexec,nosuid \
        --label "freecp.domain=${domain}" \
        --label "freecp.plan=${plan}" \
        --label "freecp.php=${php_version}" \
        "freecp/${domain}:latest" \
        > /dev/null

    # Connect to networks
    docker network connect freecp_proxy   "$name" > /dev/null 2>&1 || true
    docker network connect freecp_backend "$name" > /dev/null 2>&1 || true
}