#!/usr/bin/env bash

# Common functions
. ./functions.sh --source-only

# Skip functionality
if [ "$USERVER_SKIP_DEPLOY_MAILER" = "true" ]; then
    echo "Deployment of uServer-Mailer was skipped due to env 'USERVER_SKIP_DEPLOY_MAILER' set to true"
    return 0
fi

print_title "Deploying userver-mailer..."

build=
if [ ! -d userver-mailer ] || [ "$USERVER_FORCE_BUILD" = "true" ]; then
  build=1
  stop_and_remove_container userver-mailer
  clone_repo userver-mailer

  envs=(
    #"s/RCLONE_CONFIG_BACKUP_TYPE=s3/RCLONE_CONFIG_BACKUP_TYPE=s3/g"
    #"s/RCLONE_CONFIG_BACKUP_PROVIDER=aws/RCLONE_CONFIG_BACKUP_PROVIDER=aws/g"
    "s/RCLONE_CONFIG_BACKUP_ACCESS_KEY_ID=<your-key>/RCLONE_CONFIG_BACKUP_ACCESS_KEY_ID=${USERVER_MAIL_BKP_S3_ID}/g"
    "s/RCLONE_CONFIG_BACKUP_SECRET_ACCESS_KEY=<your-access-key>/RCLONE_CONFIG_BACKUP_SECRET_ACCESS_KEY=${USERVER_MAIL_BKP_S3_KEY}/g"
    "s/RCLONE_CONFIG_BACKUP_REGION=<your-region>/RCLONE_CONFIG_BACKUP_REGION=${USERVER_MAIL_BKP_S3_REGION}/g"
    #"s/RCLONE_CONFIG_BACKUP_ACL=bucket-owner-full-control/RCLONE_CONFIG_BACKUP_ACL=bucket-owner-full-control/g"
    #"s/ROTATE_BACKUPS=-hourly=240 --daily=60 --weekly=16 --yearl=always/ROTATE_BACKUPS=-hourly=240 --daily=60 --weekly=16 --yearl=always/g"
    "s~REMOTE_BACKUP_PATH=/<your-bucket>/<subfolder>~REMOTE_BACKUP_PATH=/${USERVER_MAIL_BKP_S3_BUCKET}/${USERVER_MAIL_BKP_S3_PREFIX}~g"
    #"s/BACKUP_INTERVAL=0 * * * */BACKUP_INTERVAL=0 * * * */g"
    #"s/SERVICES_BACKUP_LIST=/SERVICES_BACKUP_LIST=/g"
  )
  cp userver-mailer/backup/.env.template userver-mailer/backup/.env
  sed_replace_occurences userver-mailer/backup/.env "${envs[@]}"

  envs=(
    "s/HOSTNAME=<subdomain>/HOSTNAME=${USERVER_MAIL_HOSTNAME}/g"
    "s/DOMAINNAME=<domain>/DOMAINNAME=${USERVER_VIRTUAL_HOST}/g"
    "s/OVERRIDE_HOSTNAME=<full_host>/OVERRIDE_HOSTNAME=${USERVER_MAIL_HOSTNAME}.${USERVER_VIRTUAL_HOST}/g"
  )
  cp userver-mailer/mail/.env.template userver-mailer/mail/.env
  prepare_virutal_host userver-mailer/mail/.env "${USERVER_MAIL_HOSTNAME}"
  sed_replace_occurences userver-mailer/mail/.env "${envs[@]}"

  docker exec -it userver-postgres sh -c "export PGPASSWORD='${USERVER_DB_PASSWORD}'; psql -U ${USERVER_DB_USER} -c \"create database ${USERVER_WEBMAIL_DB_NAME};\""
  docker exec -it userver-postgres sh -c "export PGPASSWORD='${USERVER_DB_PASSWORD}'; psql -U ${USERVER_DB_USER} -c \"create user ${USERVER_WEBMAIL_DB_USER} with encrypted password '${USERVER_WEBMAIL_DB_PASS}';\""
  docker exec -it userver-postgres sh -c "export PGPASSWORD='${USERVER_DB_PASSWORD}'; psql -U ${USERVER_DB_USER} -c \"grant all privileges on database ${USERVER_WEBMAIL_DB_NAME} to ${USERVER_WEBMAIL_DB_USER};\""

  envs=(
    "s/ROUNDCUBEMAIL_DB_TYPE=/ROUNDCUBEMAIL_DB_TYPE=pgsql/g"
    "s/ROUNDCUBEMAIL_DB_HOST=/ROUNDCUBEMAIL_DB_HOST=userver-postgres/g"
    "s/ROUNDCUBEMAIL_DB_PORT=/ROUNDCUBEMAIL_DB_PORT=5432/g"
    "s/ROUNDCUBEMAIL_DB_USER=/ROUNDCUBEMAIL_DB_USER=${USERVER_WEBMAIL_DB_USER}/g"
    "s/ROUNDCUBEMAIL_DB_NAME=/ROUNDCUBEMAIL_DB_NAME=${USERVER_WEBMAIL_DB_NAME}/g"
    "s/ROUNDCUBEMAIL_DB_PASSWORD=/ROUNDCUBEMAIL_DB_PASSWORD=${USERVER_WEBMAIL_DB_PASS}/g"
  )
  cp userver-mailer/webmail/.env.template userver-mailer/webmail/.env
  prepare_virutal_host userver-mailer/webmail/.env "${USERVER_WEBMAIL_HOSTNAME}"
  sed_replace_occurences userver-mailer/webmail/.env "${envs[@]}"

  docker exec -it userver-postgres sh -c "export PGPASSWORD='${USERVER_DB_PASSWORD}'; psql -U ${USERVER_DB_USER} -c \"create database ${USERVER_POSTFIXADMIN_DB_NAME};\""
  docker exec -it userver-postgres sh -c "export PGPASSWORD='${USERVER_DB_PASSWORD}'; psql -U ${USERVER_DB_USER} -c \"create user ${USERVER_POSTFIXADMIN_DB_USER} with encrypted password '${USERVER_POSTFIXADMIN_DB_PASS}';\""
  docker exec -it userver-postgres sh -c "export PGPASSWORD='${USERVER_DB_PASSWORD}'; psql -U ${USERVER_DB_USER} -c \"grant all privileges on database ${USERVER_POSTFIXADMIN_DB_NAME} to ${USERVER_POSTFIXADMIN_DB_USER};\""

  envs=(
    "s/POSTFIXADMIN_DB_TYPE=pgsql/POSTFIXADMIN_DB_TYPE=${USERVER_POSTFIXADMIN_DB_TYPE}/g"
    "s/POSTFIXADMIN_DB_HOST=db/POSTFIXADMIN_DB_HOST=${USERVER_POSTFIXADMIN_DB_HOST}/g"
    "s/POSTFIXADMIN_DB_NAME=postfixadmin/POSTFIXADMIN_DB_NAME=${USERVER_POSTFIXADMIN_DB_NAME}/g"
    "s/POSTFIXADMIN_DB_USER=postfixadmin/POSTFIXADMIN_DB_USER=${USERVER_POSTFIXADMIN_DB_USER}/g"
    "s/POSTFIXADMIN_DB_PASSWORD=example/POSTFIXADMIN_DB_PASSWORD=${USERVER_POSTFIXADMIN_DB_PASS}/g"
    "s/POSTFIXADMIN_SETUP_PASSWORD=topsecret99/POSTFIXADMIN_SETUP_PASSWORD=${USERVER_POSTFIXADMIN_SETUP_PASS}/g"
    "s/POSTFIXADMIN_SMTP_SERVER=localhost/POSTFIXADMIN_SMTP_SERVER=${USERVER_POSTFIXADMIN_SMTP_HOST}/g"
    "s/POSTFIXADMIN_SMTP_PORT=25/POSTFIXADMIN_SMTP_PORT=${USERVER_POSTFIXADMIN_SMTP_PORT}/g"
  )
  cp userver-mailer/postfixadmin/.env.template userver-mailer/postfixadmin/.env
  prepare_virutal_host userver-mailer/postfixadmin/.env "${USERVER_POSTFIXADMIN_HOSTNAME}"
  sed_replace_occurences userver-mailer/postfixadmin/.env "${envs[@]}"
fi

echo "Cleaning port 25"
fuser -k -TERM -n tcp 25

start_service userver-mailer "$build"
