#!/usr/bin/env bash

# Common functions
. ./functions.sh --source-only

print_title "Deploying userver-eventmgr..."

if [ "$USERVER_SKIP_DEPLOY_EVENTMGR" = "true" ]; then
    echo "Deployment of uServer-EventMgr was skipped due to env 'USERVER_SKIP_DEPLOY_EVENTMGR' set to true"
    exit 0
fi

if [ -d userver-eventmgr ] && [ "$USERVER_FORCE_BUILD" != "true" ]; then
    echo "Directory userver-eventmgr exists and env USERVER_FORCE_BUILD is not set to true, skipping build"
    start_service userver-eventmgr 0 || exit 1
    wait_for_containers_stable 8 userver-mosquitto userver-rabbitmq || exit 1
    exit 0
fi

stop_and_remove_container userver-mosquitto
stop_and_remove_container userver-rabbitmq
clone_repo userver-eventmgr

MQTT_FULL="${USERVER_EVENTMGR_MQTT_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
if [ -n "${USERVER_EVENTMGR_MQTT_WSS_HOST:-}" ]; then
    MQTT_FULL="${USERVER_EVENTMGR_MQTT_WSS_HOST}"
fi
RABBIT_FULL="${USERVER_EVENTMGR_RABBIT_HOSTNAME}.${USERVER_VIRTUAL_HOST}"

cp userver-eventmgr/mosquitto/.env.template userver-eventmgr/mosquitto/.env
cp userver-eventmgr/rabbitmq/.env.template userver-eventmgr/rabbitmq/.env
cp userver-eventmgr/mosquitto/config/setup-users.env.template userver-eventmgr/mosquitto/config/setup-users.env

# Replace example hostnames from upstream templates with this stack's virtual host.
sed -i -e "s|\"mqtt.sd40.lan\"|\"${MQTT_FULL}\"|g" userver-eventmgr/mosquitto/.env
sed -i -e "s|\"rabbitmq.sd40.lan\"|\"${RABBIT_FULL}\"|g" userver-eventmgr/rabbitmq/.env

# acme-companion issues certs for LETSENCRYPT_HOST; it must match the hostname key in VIRTUAL_HOST_MULTIPORTS.
sed -i -e "s|^LETSENCRYPT_HOST=.*|LETSENCRYPT_HOST=${MQTT_FULL}|" userver-eventmgr/mosquitto/.env
if [ -n "${USERVER_LETSENCRYPT_EMAIL:-}" ]; then
    sed -i -e "s|^LETSENCRYPT_EMAIL=.*|LETSENCRYPT_EMAIL=${USERVER_LETSENCRYPT_EMAIL}|" userver-eventmgr/mosquitto/.env
fi

sed -i -e "s/^DEPLOYMENT_ID=.*/DEPLOYMENT_ID=${USERVER_EVENTMGR_DEPLOYMENT_ID}/" userver-eventmgr/rabbitmq/.env
sed -i -e "s/^RABBITMQ_DEFAULT_USER=.*/RABBITMQ_DEFAULT_USER=${USERVER_EVENTMGR_RABBITMQ_USER}/" userver-eventmgr/rabbitmq/.env
sed -i -e "s/^RABBITMQ_DEFAULT_PASS=.*/RABBITMQ_DEFAULT_PASS=${USERVER_EVENTMGR_RABBITMQ_PASS}/" userver-eventmgr/rabbitmq/.env

if [ -n "${USERVER_EVENTMGR_MQTT_USER}" ] && [ -n "${USERVER_EVENTMGR_MQTT_PASS}" ]; then
    printf '%s\n' "${USERVER_EVENTMGR_MQTT_USER}=${USERVER_EVENTMGR_MQTT_PASS}" >> userver-eventmgr/mosquitto/config/setup-users.env
else
    echo "USERVER_EVENTMGR_MQTT_USER or USERVER_EVENTMGR_MQTT_PASS empty; appending local dev MQTT user (change for production)"
    printf '%s\n' "localdev=localdev" >> userver-eventmgr/mosquitto/config/setup-users.env
fi

# Writable bind mounts for Mosquitto (log + pwfile) and RabbitMQ data (avoid root-only dirs from prior runs).
mkdir -p \
    userver-eventmgr/mosquitto/log \
    userver-eventmgr/mosquitto/data \
    userver-eventmgr/rabbitmq/data
chmod -R a+rwx \
    userver-eventmgr/mosquitto/log \
    userver-eventmgr/mosquitto/data \
    userver-eventmgr/mosquitto/config \
    userver-eventmgr/rabbitmq/data \
    userver-eventmgr/rabbitmq/conf.d 2>/dev/null || true

start_service userver-eventmgr 1 || exit 1
wait_for_containers_stable 8 userver-mosquitto userver-rabbitmq || exit 1
