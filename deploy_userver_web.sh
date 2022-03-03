#!/usr/bin/env bash

# Common functions
. ./functions.sh --source-only

print_title "Deploying userver-web..."

# Skip functionality
if [ "$USERVER_SKIP_DEPLOY_WEB" == "true" ]; then
    echo "Deployment of uServer-Web was skipped due to env 'USERVER_SKIP_DEPLOY_WEB' set to true"
    exit 0
fi

build=
if [ ! -d userver-web ] || [ "$USERVER_FORCE_BUILD" == "true" ]; then
    build=1
    stop_and_remove_container userver-web
    clone_repo userver-web

    hosts="${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_DB_ADMINER_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_AUTH_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_FILEMGR_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_MAIL_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_MONITOR_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_POSTFIXADMIN_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_WEBMAIL_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_WHOAMI_HOSTNAME}.${USERVER_VIRTUAL_HOST}"

    if [ "$USERVER_MODE" == "prod" ]; then
    envs=(
        "s/SERVER_NAME=/SERVER_NAME=${hosts}/g"
        "s/AUTO_LETS_ENCRYPT=no/AUTO_LETS_ENCRYPT=yes/g"
        #"s/GENERATE_SELF_SIGNED_SSL=no/GENERATE_SELF_SIGNED_SSL=no/g"
        #"s/HTTP2=yes/HTTP2=yes/g"
        #"s/REDIRECT_HTTP_TO_HTTPS=no/REDIRECT_HTTP_TO_HTTPS=no/g"
        #"s/DISABLE_DEFAULT_SERVER=yes/DISABLE_DEFAULT_SERVER=yes/g"
        #"s/ALLOWED_METHODS=GET|POST|PATCH|DELETE|HEAD/ALLOWED_METHODS=GET|POST|PATCH|DELETE|HEAD/g"
        #"s/SERVE_FILES=no/SERVE_FILES=no/g"
    )
    else
    envs=(
        "s/SERVER_NAME=/SERVER_NAME=${hosts}/g"
        #"s/AUTO_LETS_ENCRYPT=no/AUTO_LETS_ENCRYPT=no/g"
        "s/GENERATE_SELF_SIGNED_SSL=no/GENERATE_SELF_SIGNED_SSL=yes/g"
        #"s/HTTP2=yes/HTTP2=yes/g"
        #"s/REDIRECT_HTTP_TO_HTTPS=no/REDIRECT_HTTP_TO_HTTPS=no/g"
        #"s/DISABLE_DEFAULT_SERVER=yes/DISABLE_DEFAULT_SERVER=yes/g"
        #"s/ALLOWED_METHODS=GET|POST|PATCH|DELETE|HEAD/ALLOWED_METHODS=GET|POST|PATCH|DELETE|HEAD/g"
        #"s/SERVE_FILES=no/SERVE_FILES=no/g"
    )
    fi

    cp userver-web/nginx-firewall/.env.template userver-web/nginx-firewall/.env
    sed_replace_occurrences userver-web/nginx-firewall/.env "${envs[@]}"

    envs=(
        "s/HTTPS_METHOD=redirect/HTTPS_METHOD=redirect/g"
    )
    cp userver-web/nginx-proxy/.env.template userver-web/nginx-proxy/.env
    sed_replace_occurrences userver-web/nginx-proxy/.env "${envs[@]}"

    envs=(
        "s/DEFAULT_EMAIL=/DEFAULT_EMAIL=${USERVER_LETSENCRYPT_EMAIL}/g"
        "s/NGINX_PROXY_CONTAINER=/NGINX_PROXY_CONTAINER=userver-nginx-proxy/g"
    )
    cp userver-web/letsencrypt/.env.template userver-web/letsencrypt/.env
    sed_replace_occurrences userver-web/letsencrypt/.env "${envs[@]}"

    cp userver-web/monitor/.env.template userver-web/monitor/.env
    prepare_virtual_host userver-web/monitor/.env "${USERVER_MONITOR_HOSTNAME}"

    cp userver-web/whoami/.env.template userver-web/whoami/.env
    prepare_virtual_host userver-web/whoami/.env "${USERVER_WHOAMI_HOSTNAME}"
fi

start_service userver-web "$build"
