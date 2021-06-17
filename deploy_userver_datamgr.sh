#!/usr/bin/env bash

# Common functions
. ./functions.sh --source-only

print_title "Deploying userver-datamgr..."

# Skip functionality
if [ "$USERVER_SKIP_DEPLOY_DATAMGR" = "true" ]; then
    echo "Deployment of uServer-DataMgr was skipped due to env 'USERVER_SKIP_DEPLOY_DATAMGR' set to true"
    exit 0
fi

build=
if [ ! -d userver-datamgr ] || [ "$USERVER_FORCE_BUILD" = "true" ]; then
    build=1
    stop_and_remove_container userver-datamgr
    clone_repo userver-datamgr

    envs=(
        "s/BASIC_AUTH_USER=/BASIC_AUTH_USER=${USERVER_DB_ADMINER_BASIC_AUTH_USER}/g"
        "s/BASIC_AUTH_PWD=/BASIC_AUTH_PWD=${USERVER_DB_ADMINER_BASIC_AUTH_PWD}/g"
    )
    cp userver-datamgr/adminer/.env.template userver-datamgr/adminer/.env
    sed_replace_occurences userver-datamgr/adminer/.env "${envs[@]}"
    prepare_virutal_host userver-datamgr/adminer/.env "${USERVER_DB_ADMINER_HOSTNAME}"

    envs=(
        "s/POSTGRES_DATABASE=<db>/POSTGRES_DATABASE=/g"
        "s/POSTGRES_HOST=<host>/POSTGRES_HOST=userver-postgres/g"
        #"s/POSTGRES_PORT=5432/POSTGRES_PORT=5432/g"
        "s/POSTGRES_USER=<user>/POSTGRES_USER=postgres/g"
        "s/POSTGRES_PASSWORD=<password>/POSTGRES_PASSWORD=${USERVER_DB_PASSWORD}/g"
        #"s/POSTGRES_EXTRA_OPTS=/POSTGRES_EXTRA_OPTS=/g"
        "s/SCHEDULE=@every 6h/SCHEDULE=@every ${USERVER_DB_BKP_FREQUENCY}/g"
        "s/ENCRYPTION_PASSWORD=<password>/ENCRYPTION_PASSWORD=${USERVER_DB_BKP_ENCRYPTION_PASSWORD}/g"
        #"s/DELETE_OLDER_THAN=/DELETE_OLDER_THAN=/g"
        #"s~TEMP_PATH=/temp~TEMP_PATH=/temp~g"
        #"s~LOGS_PATH=/logs~LOGS_PATH=/logs~g"
        #"s/XZ_COMPRESSION_LEVEL=6/XZ_COMPRESSION_LEVEL=6/g"
        "s/BACKUP_PREFIX=/BACKUP_PREFIX=postgres-dump-all/g"
        #"s/RUN_AT_STARTUP=1/RUN_AT_STARTUP=1/g"
        #"s/STARTUP_BKP_DELAY_SECS=5/STARTUP_BKP_DELAY_SECS=5/g"
        "s/S3_REGION=<region>/S3_REGION=${USERVER_DB_BKP_S3_REGION}/g"
        "s/S3_BUCKET=<bucket>/S3_BUCKET=${USERVER_DB_BKP_S3_BUCKET}/g"
        "s/S3_ACCESS_KEY_ID=<key_id>/S3_ACCESS_KEY_ID=${USERVER_DB_BKP_S3_ID}/g"
        "s/S3_SECRET_ACCESS_KEY=<access_key>/S3_SECRET_ACCESS_KEY=${USERVER_DB_BKP_S3_KEY}/g"
        "s~S3_PREFIX=~S3_PREFIX=${USERVER_DB_BKP_S3_PREFIX}~g"
        #"s/S3_ENDPOINT=/S3_ENDPOINT=/g"
        #"s/S3_S3V4=no/S3_S3V4=no/g"
    )
    cp userver-datamgr/backup/.env.template userver-datamgr/backup/.env
    sed_replace_occurences userver-datamgr/backup/.env "${envs[@]}"

    envs=(
      "s/POSTGRES_PASSWORD=/POSTGRES_PASSWORD=${USERVER_DB_PASSWORD}/g"
      #"s/PGDATA=/var/lib/postgresql/data/pgdata/PGDATA=/var/lib/postgresql/data/pgdata/g"
    )
    cp userver-datamgr/postgres/.env.template userver-datamgr/postgres/.env
    sed_replace_occurences userver-datamgr/postgres/.env "${envs[@]}"
fi

start_service userver-datamgr "$build"

echo "Waiting 10 secs for datamgr startup..."
sleep 10

# ToDo: check if postgres is healthy by performing a simple query
