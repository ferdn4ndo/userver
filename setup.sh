#!/bin/bash

SUDO=''
if (( $EUID != 0 )); then
    SUDO='sudo'
fi

##########################################################################
# functions
##########################################################################

function stop_and_remove_container {
  echo "Stopping and removing container '$1'..."
  docker stop "$1" || true
  docker rm "$1" || true
}

function clone_repo {
  echo "Clonning repository '$1'..."

  SUDO=''
  if (( $EUID != 0 )); then
      SUDO='sudo'
  fi

  $SUDO rm -rf $1
  git clone https://github.com/ferdn4ndo/$1.git
  $SUDO chown -R "$USER":"$GROUP" $1
}

function print_title {
  echo "--------------------------------"
  echo "$1"
  echo "--------------------------------"
}

##########################################################################
# docker-compose
##########################################################################

# To update the steps, check https://docs.docker.com/compose/install/
if [ ! -f /usr/local/bin/docker-compose ]; then
    echo "Installing docker-compose"
    $SUDO curl -L "https://github.com/docker/compose/releases/download/1.26.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    $SUDO chmod +x /usr/local/bin/docker-compose
fi
command -v docker-compose >/dev/null 2>&1 || { echo >&2 "Error during docker-compose installation. Aborting..."; exit 1; }
echo "Succesfully checked docker-compose!"

##########################################################################
# .env
##########################################################################

echo "Setting up environment variables..."
# Export the vars in .env into your shell:
set -o allexport
source .env
set +o allexport

##########################################################################
# network interface
##########################################################################

$SUDO service docker start

docker network create nginx-proxy || true

##########################################################################
# userver-web
##########################################################################

print_title "Deploying userver-web..."
stop_and_remove_container userver-web
clone_repo userver-web
cd userver-web || exit 1

cp chronos/.env.template chronos/.env
sed -i -e "s/VIRTUAL_HOST=/VIRTUAL_HOST=chronos.${USERVER_VIRTUAL_HOST}/g" chronos/.env
sed -i -e "s/LETSENCRYPT_HOST=/LETSENCRYPT_HOST=chronos.${USERVER_VIRTUAL_HOST}/g" chronos/.env
sed -i -e "s/LETSENCRYPT_EMAIL=/LETSENCRYPT_EMAIL=chronos.${USERVER_VIRTUAL_HOST}/g" chronos/.env
sed -i -e "s/BASIC_AUTH_USER=/BASIC_AUTH_USER=${USERVER_CHRONOS_BASIC_AUTH_USER}/g" chronos/.env
sed -i -e "s/BASIC_AUTH_PWD=/BASIC_AUTH_PWD=${USERVER_CHRONOS_BASIC_AUTH_PWD}/g" chronos/.env

cp letsencrypt/.env.template letsencrypt/.env
sed -i -e "s/DEFAULT_EMAIL=/DEFAULT_EMAIL=${USERVER_LETSENCRYPT_EMAIL}/g" letsencrypt/.env
sed -i -e "s/NGINX_PROXY_CONTAINER=/NGINX_PROXY_CONTAINER=userver-nginx-proxy/g" letsencrypt/.env

cp monitor/.env.template monitor/.env
sed -i -e "s/VIRTUAL_HOST=/VIRTUAL_HOST=monitor.${USERVER_VIRTUAL_HOST}/g" monitor/.env
sed -i -e "s/LETSENCRYPT_HOST=/LETSENCRYPT_HOST=monitor.${USERVER_VIRTUAL_HOST}/g" monitor/.env
sed -i -e "s/LETSENCRYPT_EMAIL=/LETSENCRYPT_EMAIL=${USERVER_LETSENCRYPT_EMAIL}/g" monitor/.env

docker-compose up --build -d
cd ..

##########################################################################
# userver-datamgr
##########################################################################

print_title "Deploying userver-datamgr..."
stop_and_remove_container userver-datamgr
clone_repo userver-datamgr
cd userver-datamgr || exit 1

cp adminer/.env.template adminer/.env

sed -i -e "s/VIRTUAL_HOST=/VIRTUAL_HOST=adminer.${USERVER_VIRTUAL_HOST}/g" adminer/.env
sed -i -e "s/LETSENCRYPT_HOST=/LETSENCRYPT_HOST=adminer.${USERVER_VIRTUAL_HOST}/g" adminer/.env
sed -i -e "s/LETSENCRYPT_EMAIL=/LETSENCRYPT_EMAIL=${USERVER_LETSENCRYPT_EMAIL}/g" adminer/.env

cp backup/.env.template backup/.env

sed -i -e "s/POSTGRES_DATABASE=<db>/POSTGRES_DATABASE=/g" backup/.env
sed -i -e "s/POSTGRES_HOST=<host>/POSTGRES_HOST=userver-postgres/g" backup/.env
#sed -i -e "s/POSTGRES_PORT=5432/POSTGRES_PORT=5432/g" backup/.env
sed -i -e "s/POSTGRES_USER=<user>/POSTGRES_USER=postgres/g" backup/.env
sed -i -e "s/POSTGRES_PASSWORD=<password>/POSTGRES_PASSWORD=${USERVER_DB_PASSWORD}/g" backup/.env
#sed -i -e "s/POSTGRES_EXTRA_OPTS=/POSTGRES_EXTRA_OPTS=/g" backup/.env

sed -i -e "s/SCHEDULE=@every 6h/SCHEDULE=@every ${USERVER_DB_BKP_FREQUENCY}/g" backup/.env
sed -i -e "s/ENCRYPTION_PASSWORD=<password>/ENCRYPTION_PASSWORD=${USERVER_DB_BKP_ENCRYPTION_PASSWORD}/g" backup/.env
#sed -i -e "s/DELETE_OLDER_THAN=/DELETE_OLDER_THAN=/g" backup/.env
#sed -i -e "s/TEMP_PATH=\/temp/TEMP_PATH=\/temp/g" backup/.env
#sed -i -e "s/XZ_COMPRESSION_LEVEL=6/XZ_COMPRESSION_LEVEL=6/g" backup/.

sed -i -e "s/BACKUP_PREFIX=/BACKUP_PREFIX=postgres-dump-all/g" backup/.env
#sed -i -e "s/RUN_AT_STARTUP=1/RUN_AT_STARTUP=1/g" backup/.env
#sed -i -e "s/STARTUP_BKP_DELAY_SECS=5/STARTUP_BKP_DELAY_SECS=5/g" backup/.env

sed -i -e "s/S3_REGION=<region>/S3_REGION=${USERVER_S3_REGION}/g" backup/.env
sed -i -e "s/S3_BUCKET=<bucket>/S3_BUCKET=${USERVER_S3_BUCKET}/g" backup/.env
sed -i -e "s/S3_ACCESS_KEY_ID=<key_id>/S3_ACCESS_KEY_ID=${USERVER_S3_ACCESS_KEY_ID}/g" backup/.env
sed -i -e "s/S3_SECRET_ACCESS_KEY=<access_key>/S3_SECRET_ACCESS_KEY=${USERVER_S3_SECRET_ACCESS_KEY}/g" backup/.env
sed -i -e "s~S3_PREFIX=~S3_PREFIX=${USERVER_S3_PREFIX_BKP_DB}~g" backup/.env
#sed -i -e "s/S3_ENDPOINT=/S3_ENDPOINT=/g" backup/.env
#sed -i -e "s/S3_S3V4=no/S3_S3V4=no/g" backup/.env

cp postgres/.env.template postgres/.env

sed -i -e "s/POSTGRES_PASSWORD=/POSTGRES_PASSWORD=${USERVER_DB_PASSWORD}/g" postgres/.env
#sed -i -e "s/PGDATA=/var/lib/postgresql/data/pgdata/PGDATA=/var/lib/postgresql/data/pgdata/g" postgres/.env

docker-compose up --build -d
cd ..

##########################################################################
# userver-mailer
##########################################################################

print_title "Deploying userver-mailer..."
stop_and_remove_container userver-mailer
clone_repo userver-mailer
cd userver-mailer || exit 1

cp backup/.env.template backup/.env

#sed -i -e "s/RCLONE_CONFIG_BACKUP_TYPE=s3/RCLONE_CONFIG_BACKUP_TYPE=s3/g" backup/.env
#sed -i -e "s/RCLONE_CONFIG_BACKUP_PROVIDER=aws/RCLONE_CONFIG_BACKUP_PROVIDER=aws/g" backup/.env
sed -i -e "s/RCLONE_CONFIG_BACKUP_ACCESS_KEY_ID=<your-key>/RCLONE_CONFIG_BACKUP_ACCESS_KEY_ID=${USERVER_S3_ACCESS_KEY_ID}/g" backup/.env
sed -i -e "s/RCLONE_CONFIG_BACKUP_SECRET_ACCESS_KEY=<your-access-key>/RCLONE_CONFIG_BACKUP_SECRET_ACCESS_KEY=${USERVER_S3_SECRET_ACCESS_KEY}/g" backup/.env
sed -i -e "s/RCLONE_CONFIG_BACKUP_REGION=<your-region>/RCLONE_CONFIG_BACKUP_REGION=${USERVER_S3_REGION}/g" backup/.env
#sed -i -e "s/RCLONE_CONFIG_BACKUP_ACL=bucket-owner-full-control/RCLONE_CONFIG_BACKUP_ACL=bucket-owner-full-control/g" backup/.env
#sed -i -e "s/ROTATE_BACKUPS=-hourly=240 --daily=60 --weekly=16 --yearl=always/ROTATE_BACKUPS=-hourly=240 --daily=60 --weekly=16 --yearl=always/g" backup/.env
sed -i -e "s~REMOTE_BACKUP_PATH=/<your-bucket>/<subfolder>~REMOTE_BACKUP_PATH=/${USERVER_S3_BUCKET}/${USERVER_S3_PREFIX_BKP_MAIL}~g" backup/.env
#sed -i -e "s/BACKUP_INTERVAL=0 * * * */BACKUP_INTERVAL=0 * * * */g" backup/.env
#sed -i -e "s/SERVICES_BACKUP_LIST=/SERVICES_BACKUP_LIST=/g" backup/.env

cp mail/.env.template mail/.env

sed -i -e "s/VIRTUAL_HOST=/VIRTUAL_HOST=mail.${USERVER_VIRTUAL_HOST}/g" mail/.env
sed -i -e "s/LETSENCRYPT_HOST=/LETSENCRYPT_HOST=mail.${USERVER_VIRTUAL_HOST}/g" mail/.env
sed -i -e "s/LETSENCRYPT_EMAIL=/LETSENCRYPT_EMAIL=${USERVER_LETSENCRYPT_EMAIL}/g" mail/.env

sed -i -e "s/HOSTNAME=/HOSTNAME=mail/g" mail/.env
sed -i -e "s/DOMAINNAME=/DOMAINNAME=${USERVER_VIRTUAL_HOST}/g" mail/.env

cp webmail/.env.template webmail/.env

sed -i -e "s/VIRTUAL_HOST=/VIRTUAL_HOST=mail.${USERVER_VIRTUAL_HOST}/g" webmail/.env
sed -i -e "s/LETSENCRYPT_HOST=/LETSENCRYPT_HOST=mail.${USERVER_VIRTUAL_HOST}/g" webmail/.env
sed -i -e "s/LETSENCRYPT_EMAIL=/LETSENCRYPT_EMAIL=${USERVER_LETSENCRYPT_EMAIL}/g" webmail/.env
#sed -i -e "s/UID=991/UID=991/g" webmail/.env
#sed -i -e "s/GID=991/GID=991/g" webmail/.env
#sed -i -e "s/UPLOAD_MAX_SIZE=25M/UPLOAD_MAX_SIZE=25M/g" webmail/.env
#sed -i -e "s/LOG_TO_STDOUT=false/LOG_TO_STDOUT=false/g" webmail/.env
#sed -i -e "s/MEMORY_LIMIT=128M/MEMORY_LIMIT=128M/g" webmail/.env

echo "Clearing port 25"
$SUDO fuser -k -TERM -n tcp 25

docker-compose up --build -d
cd ..

##########################################################################
# userver-auth
##########################################################################

print_title "Deploying userver-auth..."
stop_and_remove_container userver-auth
clone_repo userver-auth
cd userver-auth || exit 1

cp .env.template .env

sed -i -e "s/VIRTUAL_HOST=/VIRTUAL_HOST=auth.${USERVER_VIRTUAL_HOST}/g" .env
sed -i -e "s/LETSENCRYPT_HOST=/LETSENCRYPT_HOST=auth.${USERVER_VIRTUAL_HOST}/g" .env
sed -i -e "s/LETSENCRYPT_EMAIL=/LETSENCRYPT_EMAIL=${USERVER_LETSENCRYPT_EMAIL}/g" .env

sed -i -e "s/POSTGRES_HOST=/POSTGRES_HOST=userver-postgres/g" .env
sed -i -e "s/POSTGRES_DB=/POSTGRES_DB=${USERVER_AUTH_DB}/g" .env
sed -i -e "s/POSTGRES_DB_TEST=/POSTGRES_DB_TEST=${USERVER_AUTH_TEST_DB}/g" .env
sed -i -e "s/POSTGRES_USER=/POSTGRES_USER=${USERVER_AUTH_USER}/g" .env
sed -i -e "s/POSTGRES_PASS=/POSTGRES_PASS=${USERVER_AUTH_PASS}/g" .env
#sed -i -e "s/POSTGRES_PORT=5432/POSTGRES_PORT=5432/g" .env

#sed -i -e "s/ENV_MODE=prod/ENV_MODE=prod/g" .env
#sed -i -e "s/FLASK_PORT=5000/FLASK_PORT=5000/g" .env

sed -i -e "s/FLASK_SECRET_KEY=/FLASK_SECRET_KEY=${USERVER_AUTH_SECRET_KEY}/g" .env
sed -i -e "s/SYSTEM_CREATION_TOKEN=/SYSTEM_CREATION_TOKEN=${USERVER_AUTH_SYSTEM_CREATION_TOKEN}/g" .env
#sed -i -e "s/JWT_EXP_DELTA_SECS=3600/JWT_EXP_DELTA_SECS=3600/g" .env

sed -i -e "s/POSTGRES_ROOT_USER=/POSTGRES_ROOT_USER=postgres/g" .env
sed -i -e "s/POSTGRES_ROOT_PASS=/POSTGRES_ROOT_PASS=${USERVER_DB_PASSWORD}/g" .env

docker-compose up --build -d

echo "Waiting 15s for container startup"
sleep 15s

docker exec -it userver-auth sh -c "./setup.sh"

##########################################################################
# .env
##########################################################################

echo "Cleaning up environment variables..."
# Export the vars in .env into your shell:
unset $(grep -v '^#' .env | sed -E 's/(.*)=.*/\1/' | xargs)

echo "=========  SETUP FINISHED! ========="

exit 0;
