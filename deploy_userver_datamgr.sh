#!/usr/bin/env bash

# Common functions
. ./functions.sh --source-only

# Compose-time vars in userver-datamgr/.env (ssl cert basename + bind mount to userver-web/certs).
datamgr_compose_env_upsert() {
    local f="userver-datamgr/.env"
    local key="$1"
    local val="$2"
    [ -f "$f" ] || touch "$f"
    if grep -q "^${key}=" "$f" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$f"
    else
        printf '%s=%s\n' "$key" "$val" >> "$f"
    fi
}

print_title "Deploying userver-datamgr..."

# Skip functionality
if [ "$USERVER_SKIP_DEPLOY_DATAMGR" = "true" ]; then
    echo "Deployment of uServer-DataMgr was skipped due to env 'USERVER_SKIP_DEPLOY_DATAMGR' set to true"
    exit 0
fi

# Upstream postgres/docker-ensure-tls.sh requires TLS (Let's Encrypt in prod or self-signed in dev).
ensure_datamgr_postgres_tls_material() {
    local ssl_dir="userver-datamgr/postgres/ssl"
    [ -d "${ssl_dir}" ] || return 0
    if [ -f "${ssl_dir}/server.crt" ] && [ -f "${ssl_dir}/server.key" ]; then
        return 0
    fi
    if [ "${USERVER_MODE}" = "prod" ] && [ -n "${USERVER_VIRTUAL_HOST:-}" ]; then
        echo "Postgres TLS: using Let's Encrypt certs from userver-web (container waits if ACME is still issuing)."
        return 0
    fi
    if command -v openssl >/dev/null 2>&1; then
        echo "Generating self-signed Postgres TLS for dev (userver-datamgr/postgres/generate-ssl.sh)..."
        ( cd userver-datamgr/postgres && sh ./generate-ssl.sh ) || exit 1
    else
        echo "Missing ${ssl_dir}/server.crt and server.key; install openssl or run userver-datamgr/postgres/generate-ssl.sh manually." >&2
        exit 1
    fi
}

datamgr_compose_down() {
    if [ -f userver-datamgr/docker-compose.yml ]; then
        (
            cd userver-datamgr || exit 0
            if docker compose version >/dev/null 2>&1; then
                docker compose down --remove-orphans
            else
                docker-compose down --remove-orphans
            fi
        ) 2>/dev/null || true
    fi
}

build=
if [ ! -d userver-datamgr ] || [ "$USERVER_FORCE_BUILD" = "true" ]; then
    build=1
    datamgr_compose_down
    clone_repo userver-datamgr

    envs=(
        "s|^BASIC_AUTH_USER=.*|BASIC_AUTH_USER=${USERVER_DB_ADMINER_BASIC_AUTH_USER}|g"
        "s|^BASIC_AUTH_PWD=.*|BASIC_AUTH_PWD=${USERVER_DB_ADMINER_BASIC_AUTH_PWD}|g"
    )
    cp userver-datamgr/adminer/.env.template userver-datamgr/adminer/.env
    sed_replace_occurrences userver-datamgr/adminer/.env "${envs[@]}"
    prepare_virtual_host userver-datamgr/adminer/.env "${USERVER_DB_ADMINER_HOSTNAME}"

    envs=(
        "s/POSTGRES_DATABASE=<db>/POSTGRES_DATABASE=/g"
        "s/POSTGRES_HOST=<host>/POSTGRES_HOST=userver-postgres/g"
        #"s/POSTGRES_PORT=5432/POSTGRES_PORT=5432/g"
        "s/POSTGRES_USER=<user>/POSTGRES_USER=${USERVER_DB_USER}/g"
        "s/POSTGRES_PASSWORD=<password>/POSTGRES_PASSWORD=${USERVER_DB_PASSWORD}/g"
        #"s/POSTGRES_EXTRA_OPTS=/POSTGRES_EXTRA_OPTS=/g"
        "s/SCHEDULE=@every 6h/SCHEDULE=@every ${USERVER_DB_BKP_FREQUENCY}/g"
        "s/ENCRYPTION_PASSWORD=<password>/ENCRYPTION_PASSWORD=${USERVER_DB_BKP_ENCRYPTION_PASSWORD}/g"
        #"s/DELETE_OLDER_THAN=/DELETE_OLDER_THAN=/g"
        #"s~TEMP_PATH=/temp~TEMP_PATH=/temp~g"
        #"s~LOGS_PATH=/logs~LOGS_PATH=/logs~g"
        #"s/XZ_COMPRESSION_LEVEL=6/XZ_COMPRESSION_LEVEL=6/g"
        "s|^BACKUP_PREFIX=.*|BACKUP_PREFIX=postgres-dump-all|g"
        #"s/RUN_AT_STARTUP=1/RUN_AT_STARTUP=1/g"
        #"s/STARTUP_BKP_DELAY_SECS=5/STARTUP_BKP_DELAY_SECS=5/g"
        "s/S3_REGION=<region>/S3_REGION=${USERVER_DB_BKP_S3_REGION}/g"
        "s/S3_BUCKET=<bucket>/S3_BUCKET=${USERVER_DB_BKP_S3_BUCKET}/g"
        "s/S3_ACCESS_KEY_ID=<key_id>/S3_ACCESS_KEY_ID=${USERVER_DB_BKP_S3_ID}/g"
        "s~S3_SECRET_ACCESS_KEY=<access_key>~S3_SECRET_ACCESS_KEY=${USERVER_DB_BKP_S3_KEY}~g"
        "s|^S3_PREFIX=.*|S3_PREFIX=${USERVER_DB_BKP_S3_PREFIX}|g"
        #"s/S3_ENDPOINT=/S3_ENDPOINT=/g"
        #"s/S3_S3V4=no/S3_S3V4=no/g"
    )
    cp userver-datamgr/backup/.env.template userver-datamgr/backup/.env
    sed_replace_occurrences userver-datamgr/backup/.env "${envs[@]}"

    envs=(
      "s~^POSTGRES_USER=.*~POSTGRES_USER=${USERVER_DB_USER}~g"
      "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${USERVER_DB_PASSWORD}|g"
      #"s/PGDATA=/var/lib/postgresql/data/pgdata/PGDATA=/var/lib/postgresql/data/pgdata/g"
    )
    cp userver-datamgr/postgres/.env.template userver-datamgr/postgres/.env
    sed_replace_occurrences userver-datamgr/postgres/.env "${envs[@]}"
fi

# nginx-proxy defaults to upstream port 80; Adminer listens on 8080 → ERR_EMPTY_RESPONSE / bad gateway without this.
_adminer_env="userver-datamgr/adminer/.env"
if [ -f "${_adminer_env}" ]; then
    if grep -q '^VIRTUAL_PORT=' "${_adminer_env}"; then
        sed -i -e 's/^VIRTUAL_PORT=.*/VIRTUAL_PORT=8080/' "${_adminer_env}"
    else
        printf '\n# nginx-proxy: backend port (Adminer image uses 8080, not 80).\nVIRTUAL_PORT=8080\n' >> "${_adminer_env}"
    fi
fi

# Postgres TLS: HTTP-01 helper (whoami) + acme-companion (userver-web) issues certs; Postgres reads same files.
if [ -d userver-datamgr ]; then
    ensure_datamgr_postgres_tls_material
    cp userver-datamgr/postgres/certs-helper.env.template userver-datamgr/postgres/certs-helper.env
    prepare_virtual_host userver-datamgr/postgres/certs-helper.env "${USERVER_DB_POSTGRES_TLS_HOSTNAME:-postgres}"
fi

if [ "${USERVER_MODE}" = "prod" ] && [ -n "${USERVER_VIRTUAL_HOST:-}" ]; then
    datamgr_compose_env_upsert POSTGRES_SSL_CERT_BASENAME "${USERVER_DB_POSTGRES_TLS_HOSTNAME:-postgres}.${USERVER_VIRTUAL_HOST}"
    datamgr_compose_env_upsert USERVER_WEB_CERTS_DIR "../userver-web/certs"
else
    datamgr_compose_env_upsert POSTGRES_SSL_CERT_BASENAME ""
    datamgr_compose_env_upsert USERVER_WEB_CERTS_DIR "./postgres/.nginx-certs-stub"
fi

start_service userver-datamgr "$build" || exit 1
wait_for_containers_stable 10 userver-postgres userver-postgres-acme userver-redis userver-adminer userver-databackup || exit 1
