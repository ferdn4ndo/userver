#!/usr/bin/env bash

if [ "${1}" != "--source-only" ]; then
    echo "This script is intended to be used only as an import for common functions (using the --source-only argument)"
    exit 1
fi

function stop_and_remove_container {
    container_name=$1
    # Docker's name= filter matches substrings, so "userver-filemgr" also matches
    # "userver-filemgr-qcluster". Resolve by exact .Names match.
    container_id=""
    local line cid cname
    while IFS= read -r line; do
        cid="${line%% *}"
        cname="${line#* }"
        cname="${cname#/}"
        if [ "${cname}" = "${container_name}" ]; then
            container_id="${cid}"
            break
        fi
    done < <(docker ps -a --format '{{.ID}} {{.Names}}')

    if [ -z "${container_id}" ]; then
        echo "Container '$1' not found, skipping stop&remove"
        return
    fi

    if [ "$(docker inspect -f '{{.State.Running}}' "${container_id}" 2>/dev/null)" = "true" ]; then
        echo "Stopping container '${container_name}' (${container_id})"
        docker stop "${container_id}" -t 0 > /dev/null
    fi

    echo "Removing container '${container_name}' (${container_id})"
    docker rm -f "${container_id}" > /dev/null
}

function clone_repo {
    repo_name="$1"
    echo "Cloning repository '${repo_name}'..."

    _owner="${USER}:$(id -gn)"

    if [ -d "${repo_name}" ]; then
        (
            cd "${repo_name}" || exit 1
            # Docker bind mounts can leave root-owned files; optional sudo chown before git writes.
            case "${USERVER_REPO_SUDO_CHOWN:-}" in
                1 | true | yes)
                    sudo chown -R "$(id -un):$(id -gn)" .
                    ;;
                *)
                    chown -R "$(id -un):$(id -gn)" . 2>/dev/null || true
                    ;;
            esac
            # --prune drops stale origin/master when upstream renamed default to main.
            git fetch origin --prune
            # Re-point origin/HEAD to the remote's real default (fixes old clones).
            git remote set-head origin -a 2>/dev/null || true

            main_branch_name="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
            if [ -z "${main_branch_name}" ] || ! git show-ref --verify --quiet "refs/remotes/origin/${main_branch_name}"; then
                main_branch_name=
            fi
            if [ -z "${main_branch_name}" ]; then
                if git show-ref --verify --quiet refs/remotes/origin/main; then
                    main_branch_name=main
                elif git show-ref --verify --quiet refs/remotes/origin/master; then
                    main_branch_name=master
                else
                    echo "Could not determine default branch for '${repo_name}' (no origin/HEAD, main, or master)." >&2
                    exit 1
                fi
            fi
            echo "Directory '${repo_name}' already exists, updating from branch '${main_branch_name}'..."
            case "${USERVER_REPO_GIT_RESET_HARD:-}" in
                1 | true | yes)
                    git checkout -f "${main_branch_name}" 2>/dev/null || git checkout -B "${main_branch_name}" -f "origin/${main_branch_name}"
                    git reset --hard "origin/${main_branch_name}"
                    ;;
                *)
                    git checkout "${main_branch_name}" 2>/dev/null || git checkout -B "${main_branch_name}" "origin/${main_branch_name}"
                    git pull origin "${main_branch_name}" --no-rebase
                    ;;
            esac
            # Old clones may still track deleted origin/master; align upstream with the branch we pull.
            git branch --set-upstream-to="origin/${main_branch_name}" "${main_branch_name}" 2>/dev/null || true
        ) || exit 1
        chown -R "${_owner}" "${repo_name}" 2>/dev/null || true
        return
    fi

    git clone https://github.com/ferdn4ndo/"${repo_name}".git
    chown -R "${_owner}" "${repo_name}" 2>/dev/null || true
}

function print_title {
    echo "--------------------------------"
    echo "$1"
    echo "--------------------------------"
}

# Used before docker exec into Postgres from deploy scripts (e.g. mailer after datamgr).
# Uses POSTGRES_USER inside the container (same as the DB image init), not USERVER_DB_USER —
# those often differ and pg_isready -U wrong_user never succeeds (looks like a hang for up to max seconds).
function wait_for_postgresql_container {
    local cname="${1:-userver-postgres}"
    local max="${2:-90}"
    local i=0
    echo "Waiting for '${cname}' (pg_isready, up to ${max}s)..."
    while [ "${i}" -lt "${max}" ]; do
        if docker exec "${cname}" sh -c 'pg_isready -q -U "${POSTGRES_USER:-postgres}"' >/dev/null 2>&1; then
            echo "PostgreSQL in '${cname}' is ready."
            return 0
        fi
        docker start "${cname}" >/dev/null 2>&1 || true
        if [ $((i % 15)) -eq 0 ] && [ "${i}" -gt 0 ]; then
            echo "  ... still waiting (${i}s / ${max}s); check: docker logs ${cname}"
        fi
        sleep 1
        i=$((i + 1))
    done
    echo "Postgres container '${cname}' not ready after ${max}s (pg_isready)." >&2
    return 1
}

# Idempotent mailer helpers (PostgreSQL 12+; avoids CREATE DATABASE name IF NOT EXISTS, which is invalid syntax).
function ensure_postgres_database_if_not_exists {
    local cname="$1"
    local db="$2"
    local exists
    exists="$(docker exec "${cname}" sh -c "export PGPASSWORD='${USERVER_DB_PASSWORD}'; psql -U \"${USERVER_DB_USER}\" -qtAc \"SELECT 1 FROM pg_database WHERE datname='${db}'\"")"
    if [ "${exists}" != "1" ]; then
        docker exec "${cname}" sh -c "export PGPASSWORD='${USERVER_DB_PASSWORD}'; psql -U \"${USERVER_DB_USER}\" -v ON_ERROR_STOP=1 -c \"CREATE DATABASE ${db};\""
    fi
}

function ensure_postgres_role_if_not_exists {
    local cname="$1"
    local role="$2"
    local pass="$3"
    local exists
    local pass_esc
    pass_esc="${pass//\'/\'\'}"
    exists="$(docker exec "${cname}" sh -c "export PGPASSWORD='${USERVER_DB_PASSWORD}'; psql -U \"${USERVER_DB_USER}\" -qtAc \"SELECT 1 FROM pg_roles WHERE rolname='${role}'\"")"
    if [ "${exists}" != "1" ]; then
        docker exec "${cname}" sh -c "export PGPASSWORD='${USERVER_DB_PASSWORD}'; psql -U \"${USERVER_DB_USER}\" -v ON_ERROR_STOP=1 -c \"CREATE USER ${role} WITH ENCRYPTED PASSWORD '${pass_esc}';\""
    fi
}

# Copy .env.template → .env only when .env is absent so manual fixes survive ./run.sh (FORCE_BUILD re-ran cp before).
function copy_env_template_if_missing {
    local tmpl="$1"
    local dest="$2"
    if [ ! -f "${dest}" ]; then
        cp "${tmpl}" "${dest}"
    fi
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
    if docker compose version >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        docker compose up ${build_arg} -d
    else
        # shellcheck disable=SC2086
        docker-compose up ${build_arg} -d
    fi
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
    if [ ! -d "$service_folder" ]; then
        echo "Directory '${service_folder}' not present, skipping"
        return
    fi
    (
        cd "$service_folder" || exit 1
        if docker compose version >/dev/null 2>&1; then
            docker compose rm -fsv
        else
            docker-compose rm -fsv
        fi
    )
}
