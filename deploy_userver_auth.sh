#!/usr/bin/env bash

# Common functions
. ./functions.sh --source-only

# Registry image uses /app/main; dev paths or a leftover docker-compose.override.yml bind-mount make it non-executable.
sanitize_userver_auth_env_file() {
    local ef="userver-auth/.env"
    [ -f "${ef}" ] || return 0
    sed -i '/^MIGRATE_BIN=/d;/^APP_BIN=/d' "${ef}"
}

print_title "Deploying userver-auth..."

export USERVER_AUTH_IMAGE_TAG="${USERVER_AUTH_IMAGE_TAG:-latest}"

# Skip functionality
if [ "$USERVER_SKIP_DEPLOY_AUTH" = "true" ]; then
    echo "Deployment of uServer-Auth was skipped due to env 'USERVER_SKIP_DEPLOY_AUTH' set to true"
    exit 0
fi

if [ -f userver-auth/.env ] && [ "$USERVER_FORCE_BUILD" != "true" ]; then
    echo "userver-auth/.env exists and USERVER_FORCE_BUILD is not true: restarting without env rewrite (Docker Hub image, compose does not --build)"
    sanitize_userver_auth_env_file
    if [ -f userver-auth/docker-compose.override.yml ]; then
        echo "Warning: userver-auth/docker-compose.override.yml exists — it may bind-mount over /app and break the Hub image. Use only docker-compose.yml for registry deploy (rename/remove the override)." >&2
    fi
    start_service userver-auth 0 "" docker-compose.yml || exit 1
    wait_for_container_stable userver-auth 20 5 || exit 1
    exit 0
fi

stop_and_remove_container userver-auth

envs=(
    "s|^POSTGRES_HOST=.*|POSTGRES_HOST=${USERVER_AUTH_DB_HOST}|g"
    "s|^POSTGRES_DB=.*|POSTGRES_DB=${USERVER_AUTH_DB}|g"
    "s|^POSTGRES_DB_TEST=.*|POSTGRES_DB_TEST=${USERVER_AUTH_TEST_DB}|g"
    "s|^POSTGRES_USER=.*|POSTGRES_USER=${USERVER_AUTH_USER}|g"
    "s|^POSTGRES_PASS=.*|POSTGRES_PASS=${USERVER_AUTH_PASS}|g"
    #"s/POSTGRES_PORT=5432/POSTGRES_PORT=5432/g"
    "s|^ENV_MODE=.*|ENV_MODE=${USERVER_MODE}|g"
    #"s/APP_PORT=5000/APP_PORT=5000/g"
    "s|^APP_SECRET_KEY=.*|APP_SECRET_KEY=${USERVER_AUTH_SECRET_KEY}|g"
    "s|^SYSTEM_CREATION_TOKEN=.*|SYSTEM_CREATION_TOKEN=${USERVER_AUTH_SYSTEM_CREATION_TOKEN}|g"
    #"s/JWT_EXP_DELTA_SECS=3600/JWT_EXP_DELTA_SECS=3600/g"
    "s|^POSTGRES_ROOT_USER=.*|POSTGRES_ROOT_USER=${USERVER_DB_USER}|g"
    "s|^POSTGRES_ROOT_PASS=.*|POSTGRES_ROOT_PASS=${USERVER_DB_PASSWORD}|g"
)
cp userver-auth/.env.template userver-auth/.env
prepare_virtual_host userver-auth/.env "${USERVER_AUTH_HOSTNAME}"
sed_replace_occurrences userver-auth/.env "${envs[@]}"
sanitize_userver_auth_env_file

if [ -f userver-auth/docker-compose.override.yml ]; then
    echo "Warning: userver-auth/docker-compose.override.yml exists — it may bind-mount over /app and break the Hub image. Use only docker-compose.yml for registry deploy (rename/remove the override)." >&2
fi

# Docker Hub: ferdn4ndo/userver-auth (explicit -f avoids merging override). Tag: USERVER_AUTH_IMAGE_TAG.
compose_pull_stack userver-auth docker-compose.yml || exit 1
start_service userver-auth 0 "" docker-compose.yml || exit 1

echo "userver-auth: entrypoint runs setup.sh (DB + migrations) then the Go API."
wait_for_container_stable userver-auth 20 5 || exit 1
