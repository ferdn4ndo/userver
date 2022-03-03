#!/usr/bin/env bash

# Common functions
. ./functions.sh --source-only

print_title "Deploying userver-logger..."

# Skip functionality
if [ "$USERVER_SKIP_DEPLOY_LOGGER" = "true" ]; then
    echo "Deployment of uServer-Logger was skipped due to env var 'USERVER_SKIP_DEPLOY_LOGGER' set to true"
    exit 0
fi

build=
if [ ! -d userver-logger ] || [ "$USERVER_FORCE_BUILD" = "true" ]; then
    build=1
    stop_and_remove_container userver-logger
    clone_repo userver-logger

    # userver-container-monitor
    envs=(
        "s/LOOP_WAIT_INTERVAL=5s/LOOP_WAIT_INTERVAL=${USERVER_LOGGER_MONITOR_LOOP_WAIT_INTERVAL}/g"
        "s/MAX_LOG_LINES=10000/MAX_LOG_LINES=${USERVER_LOGGER_MONITOR_MAX_LOG_LINES}/g"
        "s/EXCLUDED_CONTAINER_NAMES=userver-loki;userver-grafana;userver-promtail;userver-container-monitor/EXCLUDED_CONTAINER_NAMES=${USERVER_LOGGER_MONITOR_EXCLUDED_CONTAINER_NAMES}/g"
        "s/LOG_FILES_PREFIX=container_monitor_/LOG_FILES_PREFIX=${USERVER_LOGGER_MONITOR_LOG_FILES_PREFIX}/g"
        "s~DATA_FOLDER=/opt/monitor/data~DATA_FOLDER=${USERVER_LOGGER_MONITOR_DATA_FOLDER}~g"
        "s~LOGS_FOLDER=/opt/monitor/logs~LOGS_FOLDER=${USERVER_LOGGER_MONITOR_LOGS_FOLDER}~g"
        "s/PREVIOUS_CONTAINERS_LIST_FILENAME=last_containers_list.txt/PREVIOUS_CONTAINERS_LIST_FILENAME=${USERVER_LOGGER_MONITOR_PREVIOUS_CONTAINERS_LIST_FILENAME}/g"
        "s/CURRENT_CONTAINERS_LIST_FILENAME=last_containers_list.txt/CURRENT_CONTAINERS_LIST_FILENAME=${USERVER_LOGGER_MONITOR_CURRENT_CONTAINERS_LIST_FILENAME}/g"
        "s/PREVIOUS_TIMESTAMP_FILENAME=last_timestamp.txt/PREVIOUS_TIMESTAMP_FILENAME=${USERVER_LOGGER_MONITOR_PREVIOUS_TIMESTAMP_FILENAME}/g"
        "s/MONITOR_LOG_FILENAME=userver-container-monitor.log/MONITOR_LOG_FILENAME=${USERVER_LOGGER_MONITOR_LOG_FILENAME}/g"
        "s/COPY_NGINX_LOGS=1/COPY_NGINX_LOGS=${USERVER_LOGGER_COPY_NGINX_LOGS}/g"
        "s/NGINX_CONTAINER_NAME=userver-nginx-proxy/NGINX_CONTAINER_NAME=${USERVER_LOGGER_NGINX_CONTAINER_NAME}/g"
        "s~NGINX_CONTAINER_LOGS_FOLDER=/var/log/nginx~NGINX_CONTAINER_LOGS_FOLDER=${USERVER_LOGGER_NGINX_CONTAINER_LOGS_FOLDER}~g"
    )
    cp userver-logger/container_monitor/.env.template userver-logger/container_monitor/.env
    sed_replace_occurrences userver-logger/container_monitor/.env "${envs[@]}"

    # userver-grafana
    envs=(
        "s/GF_SECURITY_ADMIN_USER=/GF_SECURITY_ADMIN_USER=${USERVER_LOGGER_GRAFANA_ADMIN_USER}/g"
        "s/GF_SECURITY_ADMIN_PASSWORD=/GF_SECURITY_ADMIN_PASSWORD=${USERVER_LOGGER_GRAFANA_ADMIN_PASSWORD}/g"
    )
    cp userver-logger/grafana/.env.template userver-logger/grafana/.env
    prepare_virtual_host userver-logger/grafana/.env "${USERVER_LOGGER_GRAFANA_HOSTNAME}"
    sed_replace_occurrences userver-logger/grafana/.env "${envs[@]}"

    # userver-loki
    envs=(
        "s~ACTIVE_INDEX_FOLDER=/tmp/loki/boltdb-shipper-active~ACTIVE_INDEX_FOLDER=${USERVER_LOGGER_LOKI_ACTIVE_INDEX_FOLDER}~g"
        "s~INDEX_FOLDER=/opt/loki/index~INDEX_FOLDER=${USERVER_LOGGER_LOKI_INDEX_FOLDER}~g"
        "s/INDEX_PERIOD=24h/INDEX_PERIOD=${USERVER_LOGGER_LOKI_INDEX_PERIOD}/g"
        "s~CHUNKS_FOLDER=/opt/loki/chunks~CHUNKS_FOLDER=${USERVER_LOGGER_LOKI_CHUNKS_FOLDER}~g"
        "s/CHUNK_PERIOD=24h/CHUNK_PERIOD=${USERVER_LOGGER_LOKI_CHUNK_PERIOD}/g"
        "s~CACHE_FOLDER=/tmp/loki/boltdb-shipper-cache~CACHE_FOLDER=${USERVER_LOGGER_LOKI_CACHE_FOLDER}~g"
        "s/CACHE_TTL=24h/CACHE_TTL=${USERVER_LOGGER_LOKI_CACHE_TTL}/g"
        "s~COMPACTOR_FOLDER=/loki/boltdb-shipper-compactor~COMPACTOR_FOLDER=${USERVER_LOGGER_LOKI_COMPACTOR_FOLDER}~g"
        "s~WAL_FOLDER=/loki/wal~WAL_FOLDER=${USERVER_LOGGER_LOKI_WAL_FOLDER}~g"
        "s/RETENTION_PERIOD=744h/RETENTION_PERIOD=${USERVER_LOGGER_LOKI_RETENTION_PERIOD}/g"
    )
    cp userver-logger/loki/.env.template userver-logger/loki/.env
    sed_replace_occurrences userver-logger/loki/.env "${envs[@]}"

    # userver-promtail
    envs=(
        "s~LOKI_CLIENT_URL=http://userver-loki:3100/loki/api/v1/push~LOKI_CLIENT_URL=${USERVER_LOGGER_PROMTAIL_LOKI_CLIENT_URL}~g"
        "s~LOG_FILES_SELECTOR=/logs/*.log~LOG_FILES_SELECTOR=${USERVER_LOGGER_PROMTAIL_LOG_FILES_SELECTOR}~g"
        "s~POSITIONS_FILEPATH=/tmp/positions.yaml~POSITIONS_FILEPATH=${USERVER_LOGGER_PROMTAIL_POSITIONS_FILEPATH}~g"
        "s/HTTP_LISTEN_PORT=9080/HTTP_LISTEN_PORT=${USERVER_LOGGER_PROMTAIL_HTTP_LISTEN_PORT}/g"
        "s/GRPC_LISTEN_PORT=0/GRPC_LISTEN_PORT=${USERVER_LOGGER_PROMTAIL_GRPC_LISTEN_PORT}/g"
    )
    cp userver-logger/promtail/.env.template userver-logger/promtail/.env
    sed_replace_occurrences userver-logger/promtail/.env "${envs[@]}"
fi

start_service userver-logger "$build"
