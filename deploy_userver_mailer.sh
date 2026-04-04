#!/usr/bin/env bash

# Common functions
. ./functions.sh --source-only

ORCH_ROOT="$(cd "$(dirname "$0")" && pwd)"

print_title "Deploying userver-mailer..."

# Skip functionality
if [ "$USERVER_SKIP_DEPLOY_MAILER" = "true" ]; then
    echo "Deployment of uServer-Mailer was skipped due to env 'USERVER_SKIP_DEPLOY_MAILER' set to true"
    exit 0
fi

build=
if [ ! -d userver-mailer ] || [ "$USERVER_FORCE_BUILD" = "true" ]; then
    build=1
    stop_and_remove_container userver-mailer
    clone_repo userver-mailer

    # Fallback if clone predates userver-mailer main (postfixadmin scripts live in that repo now).
    if [ ! -f userver-mailer/postfixadmin/setup.sh ] && [ -f "${ORCH_ROOT}/patches/userver-mailer/postfixadmin/setup.sh" ]; then
        cp "${ORCH_ROOT}/patches/userver-mailer/postfixadmin/custom-entrypoint.sh" \
            "${ORCH_ROOT}/patches/userver-mailer/postfixadmin/setup.sh" \
            userver-mailer/postfixadmin/
        chmod +x userver-mailer/postfixadmin/custom-entrypoint.sh userver-mailer/postfixadmin/setup.sh
    fi

    envs=(
        "s|^ACCESS_KEY=.*|ACCESS_KEY=${USERVER_MAIL_BKP_S3_ID}|g"
        "s|^SECRET_KEY=.*|SECRET_KEY=${USERVER_MAIL_BKP_S3_KEY}|g"
        "s|^S3_PATH=.*|S3_PATH=s3://${USERVER_MAIL_BKP_S3_BUCKET}/${USERVER_MAIL_BKP_S3_PREFIX}|g"
        #"s/CRON_SCHEDULE=\"0 12 * * *\"/CRON_SCHEDULE=\"${USERVER_MAIL_BKP_CRON_SCHEDULE}\"/"
    )
    copy_env_template_if_missing userver-mailer/backup/.env.template userver-mailer/backup/.env
    sed_replace_occurrences userver-mailer/backup/.env "${envs[@]}"

    envs=(
        "s/HOSTNAME=<subdomain>/HOSTNAME=${USERVER_MAIL_HOSTNAME}/g"
        "s/DOMAINNAME=<domain>/DOMAINNAME=${USERVER_VIRTUAL_HOST}/g"
        "s|^OVERRIDE_HOSTNAME=.*|OVERRIDE_HOSTNAME=${USERVER_MAIL_HOSTNAME}.${USERVER_VIRTUAL_HOST}|"
    )
    copy_env_template_if_missing userver-mailer/mail/.env.template userver-mailer/mail/.env
    prepare_virtual_host userver-mailer/mail/.env "${USERVER_MAIL_HOSTNAME}"
    sed_replace_occurrences userver-mailer/mail/.env "${envs[@]}"

    wait_for_postgresql_container userver-postgres 120

    ensure_postgres_database_if_not_exists userver-postgres "${USERVER_WEBMAIL_DB_NAME}"
    ensure_postgres_role_if_not_exists userver-postgres "${USERVER_WEBMAIL_DB_USER}" "${USERVER_WEBMAIL_DB_PASS}"
    docker exec userver-postgres sh -c "export PGPASSWORD='${USERVER_DB_PASSWORD}'; psql -U ${USERVER_DB_USER} -c \"grant all privileges on database ${USERVER_WEBMAIL_DB_NAME} to ${USERVER_WEBMAIL_DB_USER};\""

    envs=(
        "s|^ROUNDCUBEMAIL_DB_TYPE=.*|ROUNDCUBEMAIL_DB_TYPE=pgsql|g"
        "s|^ROUNDCUBEMAIL_DB_HOST=.*|ROUNDCUBEMAIL_DB_HOST=userver-postgres|g"
        "s|^ROUNDCUBEMAIL_DB_PORT=.*|ROUNDCUBEMAIL_DB_PORT=5432|g"
        "s|^ROUNDCUBEMAIL_DEFAULT_HOST=.*|ROUNDCUBEMAIL_DEFAULT_HOST=${USERVER_WEBMAIL_IMAP_HOST}|g"
        "s|^ROUNDCUBEMAIL_DEFAULT_PORT=.*|ROUNDCUBEMAIL_DEFAULT_PORT=${USERVER_WEBMAIL_IMAP_PORT}|g"
        "s|^ROUNDCUBEMAIL_SMTP_SERVER=.*|ROUNDCUBEMAIL_SMTP_SERVER=${USERVER_WEBMAIL_SMTP_HOST}|g"
        "s|^ROUNDCUBEMAIL_SMTP_PORT=.*|ROUNDCUBEMAIL_SMTP_PORT=${USERVER_WEBMAIL_SMTP_PORT}|g"
        "s|^ROUNDCUBEMAIL_DB_USER=.*|ROUNDCUBEMAIL_DB_USER=${USERVER_WEBMAIL_DB_USER}|g"
        "s|^ROUNDCUBEMAIL_DB_NAME=.*|ROUNDCUBEMAIL_DB_NAME=${USERVER_WEBMAIL_DB_NAME}|g"
        "s|^ROUNDCUBEMAIL_DB_PASSWORD=.*|ROUNDCUBEMAIL_DB_PASSWORD=${USERVER_WEBMAIL_DB_PASS}|g"
    )
    copy_env_template_if_missing userver-mailer/webmail/.env.template userver-mailer/webmail/.env
    prepare_virtual_host userver-mailer/webmail/.env "${USERVER_WEBMAIL_HOSTNAME}"
    sed_replace_occurrences userver-mailer/webmail/.env "${envs[@]}"

    ensure_postgres_database_if_not_exists userver-postgres "${USERVER_POSTFIXADMIN_DB_NAME}"
    ensure_postgres_role_if_not_exists userver-postgres "${USERVER_POSTFIXADMIN_DB_USER}" "${USERVER_POSTFIXADMIN_DB_PASS}"
    docker exec userver-postgres sh -c "export PGPASSWORD='${USERVER_DB_PASSWORD}'; psql -U ${USERVER_DB_USER} -c \"grant all privileges on database ${USERVER_POSTFIXADMIN_DB_NAME} to ${USERVER_POSTFIXADMIN_DB_USER};\""

    envs=(
        "s|^POSTFIXADMIN_DB_TYPE=.*|POSTFIXADMIN_DB_TYPE=${USERVER_POSTFIXADMIN_DB_TYPE}|g"
        "s|^POSTFIXADMIN_DB_HOST=.*|POSTFIXADMIN_DB_HOST=${USERVER_POSTFIXADMIN_DB_HOST}|g"
        "s|^POSTFIXADMIN_DB_NAME=.*|POSTFIXADMIN_DB_NAME=${USERVER_POSTFIXADMIN_DB_NAME}|g"
        "s|^POSTFIXADMIN_DB_USER=.*|POSTFIXADMIN_DB_USER=${USERVER_POSTFIXADMIN_DB_USER}|g"
        "s|^POSTFIXADMIN_DB_PASSWORD=.*|POSTFIXADMIN_DB_PASSWORD=${USERVER_POSTFIXADMIN_DB_PASS}|g"
        "s|^POSTFIXADMIN_SETUP_PASSWORD=.*|POSTFIXADMIN_SETUP_PASSWORD=${USERVER_POSTFIXADMIN_SETUP_PASS}|g"
        "s|^POSTFIXADMIN_SMTP_SERVER=.*|POSTFIXADMIN_SMTP_SERVER=${USERVER_POSTFIXADMIN_SMTP_HOST}|g"
        "s|^POSTFIXADMIN_SMTP_PORT=.*|POSTFIXADMIN_SMTP_PORT=${USERVER_POSTFIXADMIN_SMTP_PORT}|g"
    )
    copy_env_template_if_missing userver-mailer/postfixadmin/.env.template userver-mailer/postfixadmin/.env
    prepare_virtual_host userver-mailer/postfixadmin/.env "${USERVER_POSTFIXADMIN_HOSTNAME}"
    sed_replace_occurrences userver-mailer/postfixadmin/.env "${envs[@]}"
fi

echo "Cleaning port 25"
fuser -k -TERM -n tcp 25

if [ -d userver-mailer ]; then
    ensure_mailer_stack_mail_fqdn "${ORCH_ROOT}/userver-mailer"
fi

start_service userver-mailer "$build"
