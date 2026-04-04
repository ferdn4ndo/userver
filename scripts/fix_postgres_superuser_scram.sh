#!/usr/bin/env bash
# Set a valid SCRAM password for the configured superuser role when logs show:
#   FATAL: ... does not have a valid SCRAM secret.
# Typical after PG major upgrades or a damaged auth catalog. Uses a local Unix
# socket inside the container (default image pg_hba usually trusts "local").
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINER="${POSTGRES_CONTAINER_NAME:-userver-postgres}"

# shellcheck disable=SC2046
export $(grep -E -v '^#' "${ROOT}/.env" | xargs)

ROLE="${USERVER_DB_USER:?Set USERVER_DB_USER in ${ROOT}/.env (Postgres superuser role name, same as userver-datamgr postgres/.env POSTGRES_USER).}"
PASS="${USERVER_DB_PASSWORD:?Set USERVER_DB_PASSWORD in ${ROOT}/.env (must match datamgr POSTGRES_PASSWORD).}"

sql_escape_literal() {
    printf '%s' "${1//\'/\'\'}"
}
PASS_ESC="$(sql_escape_literal "${PASS}")"
SQL="ALTER USER \"${ROLE}\" WITH PASSWORD '${PASS_ESC}';"

echo "Altering role '${ROLE}' password in ${CONTAINER} (SCRAM) to match USERVER_DB_PASSWORD from .env..."

if docker exec "${CONTAINER}" psql -U "${ROLE}" -d postgres -v ON_ERROR_STOP=1 -c "${SQL}"; then
    echo "OK: role '${ROLE}' now has a SCRAM password."
    echo "If mailer roles (webmail, postfix) still fail with the same SCRAM message, re-run ./deploy_userver_mailer.sh with USERVER_FORCE_BUILD=true or ALTER those users while connected as superuser."
else
    echo "Failed. Is ${CONTAINER} running? If the superuser role name differs from USERVER_DB_USER, fix .env or run ALTER USER manually." >&2
    exit 1
fi
