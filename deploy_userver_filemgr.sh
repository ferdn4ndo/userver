#!/usr/bin/env bash

# Common functions
. ./functions.sh --source-only

print_title "Deploying userver-filemgr..."

# Skip functionality
if [ "$USERVER_SKIP_DEPLOY_FILEMGR" = "true" ]; then
    echo "Deployment of uServer-FileMgr was skipped due to env 'USERVER_SKIP_DEPLOY_FILEMGR' set to true"
    exit 0
fi

FM_ROOT="userver-filemgr/filemgr"

export USERVER_FILEMGR_IMAGE_TAG="${USERVER_FILEMGR_IMAGE_TAG:-latest}"

# Defaults keep filemgr aligned with auth: same system name/token as POST /auth/system body, and in-container URL to userver-auth.
_FILEMGR_AUTH_HOST="${USERVER_FILEMGR_AUTH_HOST:-http://userver-auth:5000}"
_FILEMGR_SYS_NAME="${USERVER_FILEMGR_AUTH_SYSTEM_NAME:-${USERVER_AUTH_SYSTEM_NAME:-}}"
_FILEMGR_SYS_TOKEN="${USERVER_FILEMGR_AUTH_SYSTEM_TOKEN:-${USERVER_AUTH_SYSTEM_TOKEN:-}}"

# Refresh auth-related lines from orchestration .env without requiring USERVER_FORCE_BUILD.
sync_filemgr_auth_env_from_orchestration() {
    local ef="${FM_ROOT}/.env"
    [ -f "${ef}" ] || return 0
    sed -i -e "s~^USERVER_AUTH_HOST=.*~USERVER_AUTH_HOST=${_FILEMGR_AUTH_HOST}~" "${ef}"
    sed -i -e "s~^USERVER_AUTH_SYSTEM_NAME=.*~USERVER_AUTH_SYSTEM_NAME=${_FILEMGR_SYS_NAME}~" "${ef}"
    sed -i -e "s~^USERVER_AUTH_SYSTEM_TOKEN=.*~USERVER_AUTH_SYSTEM_TOKEN=${_FILEMGR_SYS_TOKEN}~" "${ef}"
}

filemgr_troubleshooting() {
    echo "" >&2
    echo "userver-filemgr troubleshooting:" >&2
    echo "  docker logs --tail=200 userver-filemgr" >&2
    echo "  cd userver-filemgr && docker compose ps && docker compose logs --tail=80 userver-filemgr" >&2
    echo "  Check ${FM_ROOT}/.env: POSTGRES_* , POSTGRES_ROOT_* , USERVER_AUTH_HOST" >&2
    echo "  If POST /auth/register returns 401 after system 409: USERVER_AUTH_SYSTEM_NAME + USERVER_AUTH_SYSTEM_TOKEN must match the system already stored in auth's DB (or reset auth DB / drop the system)." >&2
}

if [ -f "${FM_ROOT}/.env" ] && [ "$USERVER_FORCE_BUILD" != "true" ]; then
    echo "${FM_ROOT}/.env exists and USERVER_FORCE_BUILD is not true: restarting without full env rewrite (Docker Hub image, compose does not --build)"
    mkdir -p userver-filemgr/logs userver-filemgr/tmp userver-filemgr/local
    sync_filemgr_auth_env_from_orchestration
    start_service userver-filemgr 0 || exit 1
    echo "Waiting for userver-filemgr healthcheck; then checking qcluster stability..."
    wait_for_container_healthy userver-filemgr 90 2 || {
        filemgr_troubleshooting
        exit 1
    }
    wait_for_container_to_exist userver-filemgr-qcluster 120 || exit 1
    wait_for_container_stable userver-filemgr-qcluster 8 5 || {
        echo "userver-filemgr-qcluster failed stability check. Recent logs:" >&2
        docker logs --tail=80 userver-filemgr-qcluster 1>&2 || true
        exit 1
    }
    exit 0
fi

stop_and_remove_container userver-filemgr
stop_and_remove_container userver-filemgr-qcluster

mkdir -p userver-filemgr/logs userver-filemgr/tmp userver-filemgr/local

envs=(
    "s~^USERVER_AUTH_HOST=.*~USERVER_AUTH_HOST=${_FILEMGR_AUTH_HOST}~g"
    "s~^USERVER_AUTH_SYSTEM_NAME=.*~USERVER_AUTH_SYSTEM_NAME=${_FILEMGR_SYS_NAME}~g"
    "s~^USERVER_AUTH_SYSTEM_TOKEN=.*~USERVER_AUTH_SYSTEM_TOKEN=${_FILEMGR_SYS_TOKEN}~g"
    "s|^USERVER_AUTH_USER=.*|USERVER_AUTH_USER=${USERVER_FILEMGR_AUTH_USER}|g"
    "s|^USERVER_AUTH_PASSWORD=.*|USERVER_AUTH_PASSWORD=${USERVER_FILEMGR_AUTH_PASSWORD}|g"

    "s|^DJANGO_SECRET_KEY=.*|DJANGO_SECRET_KEY=${USERVER_FILEMGR_DJANGO_SECRET_KEY}|g"

    "s|^POSTGRES_HOST=.*|POSTGRES_HOST=${USERVER_FILEMGR_DB_HOST}|g"
    "s|^POSTGRES_DB=.*|POSTGRES_DB=${USERVER_FILEMGR_DB_NAME}|g"
    "s|^POSTGRES_USER=.*|POSTGRES_USER=${USERVER_FILEMGR_DB_USER}|g"
    "s|^POSTGRES_PASS=.*|POSTGRES_PASS=${USERVER_FILEMGR_DB_PASS}|g"

    "s|^TEST_AWS_S3_REGION=.*|TEST_AWS_S3_REGION=${USERVER_FILMGR_S3_TEST_REGION}|g"
    "s|^TEST_AWS_S3_BUCKET=.*|TEST_AWS_S3_BUCKET=${USERVER_FILMGR_S3_TEST_BUCKET}|g"
    "s|^TEST_AWS_S3_ID=.*|TEST_AWS_S3_ID=${USERVER_FILMGR_S3_TEST_ID}|g"
    "s|^TEST_AWS_S3_KEY=.*|TEST_AWS_S3_KEY=${USERVER_FILMGR_S3_TEST_KEY}|g"
    "s|^TEST_AWS_S3_ROOT_FOLDER=.*|TEST_AWS_S3_ROOT_FOLDER=${USERVER_FILMGR_S3_TEST_PREFIX}|g"

    "s/^ENV_MODE=.*/ENV_MODE=${USERVER_MODE}/g"

    "s|^POSTGRES_ROOT_USER=.*|POSTGRES_ROOT_USER=${USERVER_DB_USER}|g"
    "s|^POSTGRES_ROOT_PASS=.*|POSTGRES_ROOT_PASS=${USERVER_DB_PASSWORD}|g"
    "s|^USERVER_AUTH_SYSTEM_CREATION_TOKEN=.*|USERVER_AUTH_SYSTEM_CREATION_TOKEN=${USERVER_AUTH_SYSTEM_CREATION_TOKEN}|g"
)
cp "${FM_ROOT}/.env.template" "${FM_ROOT}/.env"
prepare_virtual_host "${FM_ROOT}/.env" "${USERVER_FILEMGR_HOSTNAME}"
sed_replace_occurrences "${FM_ROOT}/.env" "${envs[@]}"

# Docker Hub: ferdn4ndo/userver-filemgr (tag from USERVER_FILEMGR_IMAGE_TAG or compose default latest).
compose_pull_stack userver-filemgr || exit 1
start_service userver-filemgr 0 || {
    echo "userver-filemgr: docker compose up failed." >&2
    exit 1
}

echo "userver-filemgr: setup.sh then gunicorn; waiting for healthcheck (qcluster starts after web is healthy)."
wait_for_container_healthy userver-filemgr 90 2 || {
    filemgr_troubleshooting
    exit 1
}
wait_for_container_to_exist userver-filemgr-qcluster 120 || exit 1
wait_for_container_stable userver-filemgr-qcluster 8 5 || {
    echo "userver-filemgr-qcluster failed stability check. Recent logs:" >&2
    docker logs --tail=80 userver-filemgr-qcluster 1>&2 || true
    exit 1
}
