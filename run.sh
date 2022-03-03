#!/usr/bin/env bash

# Read environment variables
echo "Reading environment variables..."
export $(egrep -v '^#' .env | xargs)
echo "Finished reading environment variables. Startup mode: ${USERVER_MODE}"

# Common functions
. ./functions.sh --source-only

# Check docker & docker-compose
docker --version || exit 1
docker-compose --version  || exit 1

# Check if the network interface is ready
NETWORK_NAME=nginx-proxy
if [ -z $(docker network ls --filter name=^${NETWORK_NAME}$ --format="{{ .Name }}") ] ; then
  docker network create ${NETWORK_NAME};
else
  echo "Network ${NETWORK_NAME} already exists, skipping creation..."
fi

# Deploy uServer-Web
./deploy_userver_web.sh

# Deploy uServer-Logger
./deploy_userver_logger.sh

# Deploy uServer-DataMgr
./deploy_userver_datamgr.sh

# Deploy uServer-Mailer
./deploy_userver_mailer.sh

# Deploy uServer-Auth
./deploy_userver_auth.sh

# Deploy uServer-FileMgr
./deploy_userver_filemgr.sh

echo "Cleaning up environment variables..."
unset $(grep -v '^#' .env | sed -E 's/(.*)=.*/\1/' | xargs)

echo "=========  SETUP FINISHED! ========="
exit 0;
