#!/usr/bin/env bash

echo "-- Stopping all uServer services --"

docker-compose -f userver-filemgr/docker-compose.yml down

docker-compose -f userver-auth/docker-compose.yml down

docker-compose -f userver-mailer/docker-compose.yml down

docker-compose -f userver-datamgr/docker-compose.yml down

docker-compose -f userver-logger/docker-compose.yml down

docker-compose -f userver-web/docker-compose.yml down

echo "-- Done --"
