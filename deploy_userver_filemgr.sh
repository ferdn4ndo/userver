#!/usr/bin/env bash

# Common functions
. ./functions.sh --source-only

# Skip functionality
if [ "$USERVER_SKIP_DEPLOY_FILEMGR" == "true" ]; then
    echo "Deployment of uServer-FileMgr was skipped due to env 'USERVER_SKIP_DEPLOY_FILEMGR' set to true"
    return 0
fi

print_title "Deploying userver-filemgr..."

if [ -d userver-filemgr ] && [ "$USERVER_FORCE_BUILD" != "true" ]; then
    echo "Directory userver-filemgr exists and env USERVER_FORCE_BUILD is not set to true, skipping build"
    start_service userver-filemgr 0
    exit 0
fi

stop_and_remove_container userver-filemgr
clone_repo userver-filemgr

envs=(
    "s/USERVER_AUTH_HOST=/USERVER_AUTH_HOST=userver-auth:5000/g"
    "s/USERVER_AUTH_SYSTEM_NAME=/USERVER_AUTH_SYSTEM_NAME=${USERVER_FILEMGR_AUTH_SYSTEM_NAME}/g"
    "s/USERVER_AUTH_SYSTEM_TOKEN=/USERVER_AUTH_SYSTEM_TOKEN=${USERVER_FILEMGR_AUTH_SYSTEM_TOKEN}/g"
    "s/USERVER_AUTH_USER=/USERVER_AUTH_USER=${USERVER_FILEMGR_AUTH_USER}/g"
    "s/USERVER_AUTH_PASSWORD=/USERVER_AUTH_PASSWORD=${USERVER_FILEMGR_AUTH_PASSWORD}/g"

    "s/DJANGO_SECRET_KEY=/DJANGO_SECRET_KEY=${USERVER_FILEMGR_DJANGO_SECRET_KEY}/g"

    "s/POSTGRES_HOST=/POSTGRES_HOST=${USERVER_FILEMGR_DB_HOST}/g"
    "s/POSTGRES_DB=/POSTGRES_DB=${USERVER_FILEMGR_DB_NAME}/g"
    "s/POSTGRES_USER=/POSTGRES_USER=${USERVER_FILEMGR_DB_USER}/g"
    "s/POSTGRES_PASS=/POSTGRES_PASS=${USERVER_FILEMGR_DB_PASS}/g"
    #"s/POSTGRES_PORT=5432/POSTGRES_PORT=5432/g"
    #"s~LOCAL_TEST_STORAGE_ROOT=/storages/local/~LOCAL_TEST_STORAGE_ROOT=/storages/local/~g"

    "s/TEST_AWS_S3_REGION=/TEST_AWS_S3_REGION=${USERVER_FILMGR_S3_TEST_REGION}/g"
    "s/TEST_AWS_S3_BUCKET=/TEST_AWS_S3_BUCKET=${USERVER_FILMGR_S3_TEST_BUCKET}/g"
    "s/TEST_AWS_S3_ID=/TEST_AWS_S3_ID=${USERVER_FILMGR_S3_TEST_ID}/g"
    "s/TEST_AWS_S3_KEY=/TEST_AWS_S3_KEY=${USERVER_FILMGR_S3_TEST_KEY}/g"
    "s~TEST_AWS_S3_ROOT_FOLDER=~TEST_AWS_S3_ROOT_FOLDER=${USERVER_FILMGR_S3_TEST_PREFIX}~g"

    "s/ENV_MODE=prod/ENV_MODE=${USERVER_MODE}/g"
    #"s/DOWNLOAD_EXP_BYTES_SECS_RATIO=4.25/DOWNLOAD_EXP_BYTES_SECS_RATIO=4.25/g"
    #"s/GUVICORN_WORKERS=3/GUVICORN_WORKERS=3/g"

    "s/POSTGRES_ROOT_USER=/POSTGRES_ROOT_USER=${USERVER_DB_USER}/g"
    "s/POSTGRES_ROOT_PASS=/POSTGRES_ROOT_PASS=${USERVER_DB_PASSWORD}/g"
    "s/USERVER_AUTH_SYSTEM_CREATION_TOKEN=/USERVER_AUTH_SYSTEM_CREATION_TOKEN=${USERVER_AUTH_SYSTEM_CREATION_TOKEN}/g"
)
cp userver-filemgr/.env.template userver-filemgr/.env
prepare_virutal_host userver-filemgr/.env "filemgr"
sed_replace_occurences userver-filemgr/.env "${envs[@]}"

start_service userver-filemgr 1

echo "Waiting 10s for container startup"
sleep 10s

docker exec -it userver-filemgr sh -c "./setup.sh"
