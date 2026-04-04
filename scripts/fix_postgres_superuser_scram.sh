#!/usr/bin/env bash
# Set a valid SCRAM password for role "postgres" when logs show:
#   FATAL: ... User "postgres" does not have a valid SCRAM secret.
# Typical after PG major upgrades or a damaged auth catalog. Uses Unix-socket
# peer auth as the container's "postgres" OS user (no TCP password needed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINER="${POSTGRES_CONTAINER_NAME:-userver-postgres}"

# shellcheck disable=SC2046
export $(grep -E -v '^#' "${ROOT}/.env" | xargs)

PASS="${USERVER_DB_PASSWORD:?Set USERVER_DB_PASSWORD in ${ROOT}/.env (must match what apps use as POSTGRES_ROOT_PASS / datamgr POSTGRES_PASSWORD).}"

echo "Altering role postgres password in ${CONTAINER} (SCRAM) to match USERVER_DB_PASSWORD from .env..."
SQL="$(USERVER_DB_PASSWORD="${PASS}" python3 -c "import os; p = os.environ['USERVER_DB_PASSWORD'].replace(\"'\", \"''\"); print(f\"ALTER USER postgres WITH PASSWORD '{p}';\")")"

if docker exec -u postgres "${CONTAINER}" psql -d postgres -v ON_ERROR_STOP=1 -c "${SQL}"; then
    echo "OK: postgres superuser now has a SCRAM password."
    echo "If mailer roles (webmail, postfix) still fail with the same SCRAM message, re-run ./deploy_userver_mailer.sh with USERVER_FORCE_BUILD=true or ALTER those users while connected as postgres."
else
    echo "Failed. Is ${CONTAINER} running? Try: docker ps -a --filter name=${CONTAINER}" >&2
    exit 1
fi
