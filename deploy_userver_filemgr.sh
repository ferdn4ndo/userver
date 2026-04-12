#!/usr/bin/env bash

# Common functions
. ./functions.sh --source-only

# Registry image uses /app/main; a leftover docker-compose.override.yml bind-mount can shadow binaries.
sanitize_userver_filemgr_env_file() {
    local ef="userver-filemgr/.env"
    [ -f "${ef}" ] || return 0
    sed -i '/^MIGRATE_BIN=/d;/^APP_BIN=/d' "${ef}"
}

print_title "Deploying userver-filemgr..."

# Skip functionality
if [ "$USERVER_SKIP_DEPLOY_FILEMGR" = "true" ]; then
    echo "Deployment of uServer-FileMgr was skipped due to env 'USERVER_SKIP_DEPLOY_FILEMGR' set to true"
    exit 0
fi

ensure_bundled_stack_from_repo userver-filemgr docker-compose.yml .env.template || exit 1

FM_ROOT="userver-filemgr"

export USERVER_FILEMGR_IMAGE_TAG="${USERVER_FILEMGR_IMAGE_TAG:-latest}"

# Upstream Go service uses ENV_MODE=development|prod (see userver-filemgr .env.template).
if [ -z "${USERVER_FILEMGR_ENV_MODE}" ]; then
    if [ "${USERVER_MODE:-dev}" = "prod" ]; then
        USERVER_FILEMGR_ENV_MODE=prod
    else
        USERVER_FILEMGR_ENV_MODE=development
    fi
fi

# Defaults keep filemgr aligned with auth: same system name/token as POST /auth/system body, and in-container URL to userver-auth.
_FILEMGR_AUTH_HOST="${USERVER_FILEMGR_AUTH_HOST:-http://userver-auth:5000}"
_FILEMGR_SYS_NAME="${USERVER_FILEMGR_AUTH_SYSTEM_NAME:-${USERVER_AUTH_SYSTEM_NAME:-}}"
_FILEMGR_SYS_TOKEN="${USERVER_FILEMGR_AUTH_SYSTEM_TOKEN:-${USERVER_AUTH_SYSTEM_TOKEN:-}}"
_FM_DB_TEST="${USERVER_FILEMGR_DB_TEST:-userver_filemgr_test}"
_LOCAL_ROOT="${USERVER_FILEMGR_TEST_STORAGE_ROOT:-/storages/local}"
_LOCAL_ROOT="${_LOCAL_ROOT%/}"

# Refresh orchestration-driven lines without requiring USERVER_FORCE_BUILD.
sync_filemgr_env_from_orchestration() {
    local ef="${FM_ROOT}/.env"
    [ -f "${ef}" ] || return 0
    sed -i -e "s~^USERVER_AUTH_HOST=.*~USERVER_AUTH_HOST=${_FILEMGR_AUTH_HOST}~" "${ef}"
    sed -i -e "s~^FILEMGR_BOOTSTRAP_SYSTEM_NAME=.*~FILEMGR_BOOTSTRAP_SYSTEM_NAME=${_FILEMGR_SYS_NAME}~" "${ef}"
    sed -i -e "s~^FILEMGR_SYSTEM_TOKEN=.*~FILEMGR_SYSTEM_TOKEN=${_FILEMGR_SYS_TOKEN}~" "${ef}"
    sed -i -e "s~^SYSTEM_CREATION_TOKEN=.*~SYSTEM_CREATION_TOKEN=${USERVER_AUTH_SYSTEM_CREATION_TOKEN}~" "${ef}"
    sed -i "s|^ENV_MODE=.*|ENV_MODE=${USERVER_FILEMGR_ENV_MODE}|" "${ef}"
}

filemgr_troubleshooting() {
    echo "" >&2
    echo "userver-filemgr troubleshooting:" >&2
    echo "  docker logs --tail=200 userver-filemgr" >&2
    echo "  cd userver-filemgr && docker compose ps && docker compose logs --tail=80 userver-filemgr" >&2
    echo "  Check ${FM_ROOT}/.env: POSTGRES_* , POSTGRES_ROOT_* , USERVER_AUTH_HOST , SYSTEM_CREATION_TOKEN" >&2
    echo "  If bootstrap fails: SYSTEM_CREATION_TOKEN must match userver-auth; FILEMGR_BOOTSTRAP_SYSTEM_NAME + FILEMGR_SYSTEM_TOKEN must match the system in auth after first run." >&2
}

if [ -f "${FM_ROOT}/.env" ] && [ "$USERVER_FORCE_BUILD" != "true" ]; then
    echo "${FM_ROOT}/.env exists and USERVER_FORCE_BUILD is not true: restarting without full env rewrite (Docker Hub image, compose does not --build)"
    mkdir -p userver-filemgr/local
    sanitize_userver_filemgr_env_file
    sync_filemgr_env_from_orchestration
    if [ -f userver-filemgr/docker-compose.override.yml ]; then
        echo "Warning: userver-filemgr/docker-compose.override.yml exists — it may bind-mount source over the image tree. For Docker Hub, use only docker-compose.yml (rename/remove the override)." >&2
    fi
    start_service userver-filemgr 0 "" docker-compose.yml || exit 1
    echo "Waiting 20s for userver-filemgr (startup)..."
    wait_for_container_stable userver-filemgr 20 5 || exit 1
    exit 0
fi

stop_and_remove_container userver-filemgr

mkdir -p userver-filemgr/local

envs=(
    "s~^USERVER_AUTH_HOST=.*~USERVER_AUTH_HOST=${_FILEMGR_AUTH_HOST}~g"
    "s~^FILEMGR_BOOTSTRAP_SYSTEM_NAME=.*~FILEMGR_BOOTSTRAP_SYSTEM_NAME=${_FILEMGR_SYS_NAME}~g"
    "s~^FILEMGR_SYSTEM_TOKEN=.*~FILEMGR_SYSTEM_TOKEN=${_FILEMGR_SYS_TOKEN}~g"
    "s|^FILEMGR_BOOTSTRAP_ADMIN_USERNAME=.*|FILEMGR_BOOTSTRAP_ADMIN_USERNAME=${USERVER_FILEMGR_AUTH_USER}|g"
    "s|^FILEMGR_BOOTSTRAP_ADMIN_PASSWORD=.*|FILEMGR_BOOTSTRAP_ADMIN_PASSWORD=${USERVER_FILEMGR_AUTH_PASSWORD}|g"

    "s|^POSTGRES_HOST=.*|POSTGRES_HOST=${USERVER_FILEMGR_DB_HOST}|g"
    "s|^POSTGRES_DB=.*|POSTGRES_DB=${USERVER_FILEMGR_DB_NAME}|g"
    "s|^POSTGRES_DB_TEST=.*|POSTGRES_DB_TEST=${_FM_DB_TEST}|g"
    "s|^POSTGRES_USER=.*|POSTGRES_USER=${USERVER_FILEMGR_DB_USER}|g"
    "s|^POSTGRES_PASS=.*|POSTGRES_PASS=${USERVER_FILEMGR_DB_PASS}|g"

    "s|^LOCAL_STORAGE_ROOT=.*|LOCAL_STORAGE_ROOT=${_LOCAL_ROOT}|g"

    "s|^ENV_MODE=.*|ENV_MODE=${USERVER_FILEMGR_ENV_MODE}|g"

    "s|^POSTGRES_ROOT_USER=.*|POSTGRES_ROOT_USER=${USERVER_DB_USER}|g"
    "s|^POSTGRES_ROOT_PASS=.*|POSTGRES_ROOT_PASS=${USERVER_DB_PASSWORD}|g"
    "s|^SYSTEM_CREATION_TOKEN=.*|SYSTEM_CREATION_TOKEN=${USERVER_AUTH_SYSTEM_CREATION_TOKEN}|g"
)
cp "${FM_ROOT}/.env.template" "${FM_ROOT}/.env"
prepare_virtual_host "${FM_ROOT}/.env" "${USERVER_FILEMGR_HOSTNAME}"
sed_replace_occurrences "${FM_ROOT}/.env" "${envs[@]}"
sanitize_userver_filemgr_env_file

if [ -f userver-filemgr/docker-compose.override.yml ]; then
    echo "Warning: userver-filemgr/docker-compose.override.yml exists — it may bind-mount source over the image tree. For Docker Hub, use only docker-compose.yml (rename/remove the override)." >&2
fi

# Docker Hub: ferdn4ndo/userver-filemgr (explicit -f avoids merging override).
compose_pull_stack userver-filemgr docker-compose.yml || exit 1
start_service userver-filemgr 0 "" docker-compose.yml || {
    echo "userver-filemgr: docker compose up failed." >&2
    exit 1
}

echo "userver-filemgr: entrypoint runs setup.sh (DB + migrations + bootstrap) then the Go API."
wait_for_container_stable userver-filemgr 20 5 || {
    filemgr_troubleshooting
    exit 1
}
