#!/usr/bin/env bash

##########################################################################
# functions
##########################################################################

function stop_and_remove_container {
  container_id="$(docker ps -aq -f name=$1)"
  if [ ! "$container_id" ]; then
    echo "Container '$1' not found, skipping stop&remove"
    return
  fi

  if [ ! "$(docker ps -aq -f status=exited -f name=$1)" ]; then
    # not exited, stopping
    echo "Stopping container '$1' ($container_id)"
    docker stop "$container_id" -t 0 > /dev/null
  fi

  echo "Removing container '$1' ($container_id)"
  docker rm -f "$container_id" > /dev/null
}

function clone_repo {
  echo "Clonning repository '$1'..."

  if [ -d $1 ]; then
    echo "Directory '$1' already exists, updating..."
    cd $1 || exit
    git pull origin master
    cd ..
    return
  fi

  git clone https://github.com/ferdn4ndo/$1.git
  chown -R "$USER":"$GROUP" "$1"
}

function print_title {
  echo "--------------------------------"
  echo "$1"
  echo "--------------------------------"
}

function prepare_virutal_host {
  # $1 = file
  file=$1
  subdomain=$2
  echo "Preparing virtual host environment config for '${subdomain}.${USERVER_VIRTUAL_HOST}'"

  sed -i -e "s/VIRTUAL_HOST=/VIRTUAL_HOST=${subdomain}.${USERVER_VIRTUAL_HOST}/g" "$file"
  if [ "$USERVER_MODE" == "prod" ]; then
    sed -i -e "s/LETSENCRYPT_HOST=/LETSENCRYPT_HOST=${subdomain}.${USERVER_VIRTUAL_HOST}/g" "$file"
    sed -i -e "s/LETSENCRYPT_EMAIL=/LETSENCRYPT_EMAIL=${USERVER_LETSENCRYPT_EMAIL}/g" "$file"
  fi
}

function start_service {
  # $1 = start a service (ex: userver-web)
  service=$1
  # $2 = if it should be rebuilt instead of restarted
  build=$2

  build_arg=
  action="Restarting"
  if [ "${build}" == 1 ]; then
    build_arg="--build --remove-orphans"
    action="Building"
  fi

  echo "${action} ${service}..."
  cd "${service}" || exit 1
  docker-compose up $build_arg -d
  cd ..
}

function sed_replace_occurences {
  local file="$1" # Save first argument in a variable
  shift # Shift all arguments to the left (original $1 gets lost)
  local strings_arr=("$@") # Rebuild the array with rest of arguments

  for i in "${strings_arr[@]}"
  do
    :
      sed -i -e "$i" "$file"
  done
}

##########################################################################
# docker & docker-compose
##########################################################################

docker info > /dev/null || exit 1

docker-compose --version  || exit 1

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

NETWORK_NAME=nginx-proxy
if [ -z $(docker network ls --filter name=^${NETWORK_NAME}$ --format="{{ .Name }}") ] ; then
  docker network create ${NETWORK_NAME} ;
fi

##########################################################################
# userver-web
##########################################################################

print_title "Deploying userver-web..."

build=
if [ ! -d userver-web ] || [ "$USERVER_FORCE_BUILD" == "true" ]; then
  build=1
  stop_and_remove_container userver-web
  clone_repo userver-web

  envs=(
    "s/SERVER_NAME=/SERVER_NAME=${USERVER_VIRTUAL_HOST} adminer.${USERVER_VIRTUAL_HOST} auth.${USERVER_VIRTUAL_HOST} filemgr.${USERVER_VIRTUAL_HOST} mail.${USERVER_VIRTUAL_HOST} webmail.${USERVER_VIRTUAL_HOST} whoami.${USERVER_VIRTUAL_HOST}/g"
    #"s/AUTO_LETS_ENCRYPT=no/AUTO_LETS_ENCRYPT=no/g"
    #"s/GENERATE_SELF_SIGNED_SSL=no/GENERATE_SELF_SIGNED_SSL=no/g"
    #"s/HTTP2=yes/HTTP2=yes/g"
    #"s/REDIRECT_HTTP_TO_HTTPS=no/REDIRECT_HTTP_TO_HTTPS=no/g"
    #"s/DISABLE_DEFAULT_SERVER=yes/DISABLE_DEFAULT_SERVER=yes/g"
    #"s/ALLOWED_METHODS=GET|POST|PATCH|DELETE|HEAD/ALLOWED_METHODS=GET|POST|PATCH|DELETE|HEAD/g"
    #"s/SERVE_FILES=no/SERVE_FILES=no/g"
  )
  cp userver-web/nginx-firewall/.env.template userver-web/nginx-firewall/.env
  sed_replace_occurences userver-web/nginx-firewall/.env "${envs[@]}"

  envs=(
    "s/DEFAULT_EMAIL=/DEFAULT_EMAIL=${USERVER_LETSENCRYPT_EMAIL}/g"
    "s/NGINX_PROXY_CONTAINER=/NGINX_PROXY_CONTAINER=userver-nginx-proxy/g"
  )
  cp userver-web/letsencrypt/.env.template userver-web/letsencrypt/.env
  sed_replace_occurences userver-web/letsencrypt/.env "${envs[@]}"

  cp userver-web/whoami/.env.template userver-web/whoami/.env
  prepare_virutal_host userver-web/whoami/.env "whoami"
fi

start_service userver-web "$build"

##########################################################################
# userver-datamgr
##########################################################################

print_title "Deploying userver-datamgr..."

build=
if [ ! -d userver-datamgr ] || [ "$USERVER_FORCE_BUILD" == "true" ]; then
  build=1
  stop_and_remove_container userver-datamgr
  clone_repo userver-datamgr

  envs=(
    "s/BASIC_AUTH_USER=/BASIC_AUTH_USER=${USERVER_ADMINER_BASIC_AUTH_USER}/g"
    "s/BASIC_AUTH_PWD=/BASIC_AUTH_PWD=${USERVER_ADMINER_BASIC_AUTH_USER}/g"
  )
  cp userver-datamgr/adminer/.env.template userver-datamgr/adminer/.env
  sed_replace_occurences userver-datamgr/adminer/.env "${envs[@]}"
  prepare_virutal_host userver-datamgr/adminer/.env "adminer"

  envs=(
    "s/POSTGRES_DATABASE=<db>/POSTGRES_DATABASE=/g"
    "s/POSTGRES_HOST=<host>/POSTGRES_HOST=userver-postgres/g"
    #"s/POSTGRES_PORT=5432/POSTGRES_PORT=5432/g"
    "s/POSTGRES_USER=<user>/POSTGRES_USER=postgres/g"
    "s/POSTGRES_PASSWORD=<password>/POSTGRES_PASSWORD=${USERVER_DB_PASSWORD}/g"
    #"s/POSTGRES_EXTRA_OPTS=/POSTGRES_EXTRA_OPTS=/g"
    "s/SCHEDULE=@every 6h/SCHEDULE=@every ${USERVER_DB_BKP_FREQUENCY}/g"
    "s/ENCRYPTION_PASSWORD=<password>/ENCRYPTION_PASSWORD=${USERVER_DB_BKP_ENCRYPTION_PASSWORD}/g"
    #"s/DELETE_OLDER_THAN=/DELETE_OLDER_THAN=/g"
    #"s/TEMP_PATH=\/temp/TEMP_PATH=\/temp/g"
    #"s/XZ_COMPRESSION_LEVEL=6/XZ_COMPRESSION_LEVEL=6/g"
    "s/BACKUP_PREFIX=/BACKUP_PREFIX=postgres-dump-all/g"
    #"s/RUN_AT_STARTUP=1/RUN_AT_STARTUP=1/g"
    #"s/STARTUP_BKP_DELAY_SECS=5/STARTUP_BKP_DELAY_SECS=5/g"
    "s/S3_REGION=<region>/S3_REGION=${USERVER_DB_BKP_S3_REGION}/g"
    "s/S3_BUCKET=<bucket>/S3_BUCKET=${USERVER_DB_BKP_S3_BUCKET}/g"
    "s/S3_ACCESS_KEY_ID=<key_id>/S3_ACCESS_KEY_ID=${USERVER_DB_BKP_S3_ID}/g"
    "s/S3_SECRET_ACCESS_KEY=<access_key>/S3_SECRET_ACCESS_KEY=${USERVER_DB_BKP_S3_KEY}/g"
    "s~S3_PREFIX=~S3_PREFIX=${USERVER_DB_BKP_S3_PREFIX}~g"
    #"s/S3_ENDPOINT=/S3_ENDPOINT=/g"
    #"s/S3_S3V4=no/S3_S3V4=no/g"
  )
  cp userver-datamgr/backup/.env.template userver-datamgr/backup/.env
  sed_replace_occurences userver-datamgr/backup/.env "${envs[@]}"

  envs=(
    "s/POSTGRES_PASSWORD=/POSTGRES_PASSWORD=${USERVER_DB_PASSWORD}/g"
    #"s/PGDATA=/var/lib/postgresql/data/pgdata/PGDATA=/var/lib/postgresql/data/pgdata/g"
  )
  cp userver-datamgr/postgres/.env.template userver-datamgr/postgres/.env
  sed_replace_occurences userver-datamgr/postgres/.env "${envs[@]}"
fi

start_service userver-datamgr "$build"

##########################################################################
# userver-mailer
##########################################################################

print_title "Deploying userver-mailer..."

build=
if [ ! -d userver-mailer ] || [ "$USERVER_FORCE_BUILD" == "true" ]; then
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
    "s/HOSTNAME=/HOSTNAME=mail/g"
    "s/DOMAINNAME=/DOMAINNAME=${USERVER_VIRTUAL_HOST}/g"
  )
  cp userver-mailer/mail/.env.template userver-mailer/mail/.env
  prepare_virutal_host userver-mailer/mail/.env "mail"
  sed_replace_occurences userver-mailer/mail/.env "${envs[@]}"

  envs=(
    #"s/UID=991/UID=991/g"
    #"s/GID=991/GID=991/g"
    "s/UPLOAD_MAX_SIZE=25M/UPLOAD_MAX_SIZE=50M/g"
    #"s/LOG_TO_STDOUT=false/LOG_TO_STDOUT=false/g"
    #"s/MEMORY_LIMIT=128M/MEMORY_LIMIT=128M/g"
  )
  cp userver-mailer/webmail/.env.template userver-mailer/webmail/.env
  prepare_virutal_host userver-mailer/webmail/.env "webmail"
  sed_replace_occurences userver-mailer/webmail/.env "${envs[@]}"
fi

echo "Cleaning port 25"
fuser -k -TERM -n tcp 25

start_service userver-mailer "$build"

##########################################################################
# userver-auth
##########################################################################

print_title "Deploying userver-auth..."

if [ ! -d userver-auth ] || [ "$USERVER_FORCE_BUILD" == "true" ]; then
  stop_and_remove_container userver-auth
  clone_repo userver-auth

  envs=(
    "s/POSTGRES_HOST=/POSTGRES_HOST=userver-postgres/g"
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
    "s/POSTGRES_ROOT_USER=/POSTGRES_ROOT_USER=postgres/g"
    "s/POSTGRES_ROOT_PASS=/POSTGRES_ROOT_PASS=${USERVER_DB_PASSWORD}/g"
  )
  cp userver-auth/.env.template userver-auth/.env
  prepare_virutal_host userver-auth/.env "auth"
  sed_replace_occurences userver-auth/.env "${envs[@]}"

  start_service userver-auth 1

  echo "Waiting 10s for container startup"
  sleep 10s

  docker exec -it userver-auth sh -c "./setup.sh"
else
  start_service userver-auth 0
fi

##########################################################################
# userver-filemgr
##########################################################################

print_title "Deploying userver-filemgr..."

if [ ! -d userver-filemgr ] || [ "$USERVER_FORCE_BUILD" == "true" ]; then
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

    "s/POSTGRES_ROOT_USER=/POSTGRES_ROOT_USER=postgres/g"
    "s/POSTGRES_ROOT_PASS=/POSTGRES_ROOT_PASS=${USERVER_DB_PASSWORD}/g"
    "s/USERVER_AUTH_SYSTEM_CREATION_TOKEN=/USERVER_AUTH_SYSTEM_CREATION_TOKEN=${USERVER_AUTH_SYSTEM_CREATION_TOKEN}/g"
  )
  cp userver-filemgr/.env.template userver-filemgr/.env
  prepare_virutal_host userver-filemgr/.env "auth"
  sed_replace_occurences userver-filemgr/.env "${envs[@]}"

  start_service userver-filemgr 1

  echo "Waiting 10s for container startup"
  sleep 10s

  docker exec -it userver-filemgr sh -c "./setup.sh"
else
  start_service userver-filemgr 0
fi

##########################################################################
# .env
##########################################################################

echo "Cleaning up environment variables..."
# Export the vars in .env into your shell:
unset $(grep -v '^#' .env | sed -E 's/(.*)=.*/\1/' | xargs)

echo "=========  SETUP FINISHED! ========="

exit 0;
