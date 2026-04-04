#!/usr/bin/env bash

echo "-- Stopping all uServer services --"

dc_down() {
    local compose_file="$1"
    if [ ! -f "${compose_file}" ]; then
        return 0
    fi
    if docker compose version >/dev/null 2>&1; then
        docker compose -f "${compose_file}" down
    else
        docker-compose -f "${compose_file}" down
    fi
}

dc_down userver-filemgr/docker-compose.yml
dc_down userver-auth/docker-compose.yml
dc_down userver-mailer/docker-compose.yml
dc_down userver-eventmgr/docker-compose.yml
dc_down userver-datamgr/docker-compose.yml
dc_down userver-logger/docker-compose.yml
dc_down userver-web/docker-compose.yml

echo "-- Done --"
