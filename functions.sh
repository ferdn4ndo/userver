#!/usr/bin/env bash

if [ "${1}" != "--source-only" ]; then
    echo "This script is intended to be used only as an import for common functions (using the --source-only argument)"
    exit 1
fi

function stop_and_remove_container {
    container_name=$1
    container_id="$(docker ps -aq -f name="${container_name}")"
    if [ ! "$container_id" ]; then
        echo "Container '$1' not found, skipping stop&remove"
        return
    fi

    if [ ! "$(docker ps -aq -f status=exited -f name="${container_name}")" ]; then
        # not exited, stopping
        echo "Stopping container '${container_name}' ($container_id)"
        docker stop "$container_id" -t 0 > /dev/null
    fi

    echo "Removing container '${container_name}' ($container_id)"
    docker rm -f "$container_id" > /dev/null
}

function clone_repo {
    repo_name="$1"
    echo "Cloning repository '${repo_name}'..."

    if [ -d "${repo_name}" ]; then
        cd "${repo_name}" || exit
        main_branch_name=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
        echo "Directory '${repo_name}' already exists, updating from branch '${main_branch_name}'..."
        git pull origin "${main_branch_name}" --no-rebase
        cd ..
        return
    fi

    git clone https://github.com/ferdn4ndo/"${repo_name}".git
    chown -R "$USER":"$GROUP" "${repo_name}"
}

function print_title {
    echo "--------------------------------"
    echo "$1"
    echo "--------------------------------"
}

function prepare_virtual_host {
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

function sed_replace_occurrences {
    local file="$1" # Save first argument in a variable
    shift # Shift all arguments to the left (original $1 gets lost)
    local strings_arr=("$@") # Rebuild the array with rest of arguments

    for i in "${strings_arr[@]}"; do
    :
        sed -i -e "$i" "$file" || echo "Failed to replace string ${i}"
    done
}

function remove_service_images_and_volumes {
    # $1 = the folder name of the service to remove the images
    service_folder=$1

    echo "Removing images and volumes of the service ${service_folder}"
    (cd "$service_folder" || exit; docker-compose rm -fsv)
}
