#!/usr/bin/env bash

# Common functions
. ./functions.sh --source-only

print_title "Deploying userver-auth..."

# Skip functionality
if [ "$USERVER_SKIP_DEPLOY_AUTH" = "true" ]; then
    echo "Deployment of uServer-Auth was skipped due to env 'USERVER_SKIP_DEPLOY_AUTH' set to true"
    exit 0
fi

if [ -d userver-auth ] && [ "$USERVER_FORCE_BUILD" != "true" ]; then
    echo "Directory userver-auth exists and env USERVER_FORCE_BUILD is not set to true, skipping build"
    start_service userver-auth 0
    exit 0
fi

stop_and_remove_container userver-auth
clone_repo userver-auth

envs=(
    "s/POSTGRES_HOST=/POSTGRES_HOST=${USERVER_AUTH_DB_HOST}/g"
    "s/POSTGRES_DB=/POSTGRES_DB=${USERVER_AUTH_DB}/g"
    "s/POSTGRES_DB_TEST=/POSTGRES_DB_TEST=${USERVER_AUTH_TEST_DB}/g"
    "s/POSTGRES_USER=/POSTGRES_USER=${USERVER_AUTH_USER}/g"
    "s/POSTGRES_PASS=/POSTGRES_PASS=${USERVER_AUTH_PASS}/g"
    #"s/POSTGRES_PORT=5432/POSTGRES_PORT=5432/g"
    "s/ENV_MODE=prod/ENV_MODE=${USERVER_MODE}/g"
    #"s/FLASK_PORT=5000/FLASK_PORT=5000/g"
    "s/FLASK_SECRET_KEY=/FLASK_SECRET_KEY=${USERVER_AUTH_SECRET_KEY}/g"
    "s/SYSTEM_CREATION_TOKEN=/SYSTEM_CREATION_TOKEN=${USERVER_AUTH_SYSTEM_CREATION_TOKEN}/g"
    #"s/JWT_EXP_DELTA_SECS=3600/JWT_EXP_DELTA_SECS=3600/g"
    "s/POSTGRES_ROOT_USER=/POSTGRES_ROOT_USER=${USERVER_DB_USER}/g"
    "s/POSTGRES_ROOT_PASS=/POSTGRES_ROOT_PASS=${USERVER_DB_PASSWORD}/g"
)
cp userver-auth/.env.template userver-auth/.env
prepare_virutal_host userver-auth/.env "${USERVER_AUTH_HOSTNAME}"
sed_replace_occurences userver-auth/.env "${envs[@]}"

start_service userver-auth 1

echo "Waiting 10s for container startup"
sleep 10s

docker exec -it userver-auth sh -c "./setup.sh"
