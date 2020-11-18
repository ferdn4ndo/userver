#!/usr/bin/env bash

if [ "${1}" != "--source-only" ]; then
    echo "This script is intended to be used only as an import for common functions (using the --source-only argument)"
    exit 1
fi

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

