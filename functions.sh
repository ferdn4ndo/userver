#!/usr/bin/env bash

if [ "${1}" != "--source-only" ]; then
    echo "This script is intended to be used only as an import for common functions (using the --source-only argument)"
    exit 1
fi

function stop_and_remove_container {
    container_name=$1
    # Docker's name= filter matches substrings; resolve by exact .Names match.
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

# Bundled stacks (userver-auth, userver-filemgr) ship compose + .env.template in the orchestration repo.
# If the directory is missing or incomplete (old clone, tarball without subdirs), fetch from GitHub raw.
# USERVER_ORCHESTRATION_GITHUB_REPO (default ferdn4ndo/userver), USERVER_BUNDLED_STACK_REF (default main).
function ensure_bundled_stack_from_repo {
    local dir="${1:?stack directory e.g. userver-auth}"
    shift
    if [ "$#" -eq 0 ]; then
        echo "ensure_bundled_stack_from_repo: no file names passed." >&2
        return 1
    fi
    local ref="${USERVER_BUNDLED_STACK_REF:-main}"
    local repo="${USERVER_ORCHESTRATION_GITHUB_REPO:-ferdn4ndo/userver}"
    local base="https://raw.githubusercontent.com/${repo}/${ref}/${dir}"
    local need_fetch=0
    local f
    for f in "$@"; do
        if [ ! -f "${dir}/${f}" ]; then
            need_fetch=1
            break
        fi
    done
    if [ "${need_fetch}" = 0 ]; then
        return 0
    fi

    echo "Bundled files missing under ${dir}/; fetching from ${base}/" >&2
    echo "  (override repo/branch: USERVER_ORCHESTRATION_GITHUB_REPO, USERVER_BUNDLED_STACK_REF; or git pull this repo)." >&2
    mkdir -p "${dir}"

    _bundled_fetch() {
        local url="$1"
        local out="$2"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL "${url}" -o "${out}"
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O "${out}" "${url}"
        else
            echo "Install curl or wget, or copy ${dir}/ from a full orchestration checkout." >&2
            return 1
        fi
    }

    for f in "$@"; do
        echo "  -> ${dir}/${f}" >&2
        _bundled_fetch "${base}/${f}" "${dir}/${f}" || return 1
    done
    return 0
}

# Inspect + healthcheck log + container logs (for deploy scripts and CI when a container is unhealthy / crashing).
# Optional $2: log tail (default 200).
function docker_print_container_diagnostics {
    local cname="${1:?container name}"
    local log_tail="${2:-200}"
    echo "" >&2
    echo "========== docker diagnostics: ${cname} ==========" >&2
    if ! docker inspect "${cname}" >/dev/null 2>&1; then
        echo "No container named '${cname}'. Recent docker ps -a (name / status / image):" >&2
        docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null | head -50 >&2 || true
        echo "========== end diagnostics ==========" >&2
        return 0
    fi
    docker inspect --format 'Image={{.Config.Image}}
Status={{.State.Status}} ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}}
StartedAt={{.State.StartedAt}} FinishedAt={{.State.FinishedAt}}
Error={{.State.Error}}' "${cname}" 2>/dev/null | sed 's/^/  /' >&2 || true
    local hstat fstreak
    hstat="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}(no healthcheck in image){{end}}' "${cname}" 2>/dev/null || echo '?')"
    fstreak="$(docker inspect --format '{{if .State.Health}}{{.State.Health.FailingStreak}}{{else}}n/a{{end}}' "${cname}" 2>/dev/null || echo '?')"
    echo "  Health.Status=${hstat}  FailingStreak=${fstreak}" >&2
    local log_count
    log_count="$(docker inspect --format '{{if .State.Health}}{{len .State.Health.Log}}{{else}}0{{end}}' "${cname}" 2>/dev/null || echo 0)"
    if [ -n "${log_count}" ] && [ "${log_count}" -gt 0 ] 2>/dev/null; then
        echo "  --- Healthcheck log (command output from last checks) ---" >&2
        docker inspect --format '{{range .State.Health.Log}}--- exit={{.ExitCode}} start={{.Start}} ---{{println}}{{.Output}}{{end}}' "${cname}" 2>/dev/null | tail -n 80 | sed 's/^/  /' >&2 || true
    fi
    echo "  --- docker logs (last ${log_tail} lines) ---" >&2
    docker logs --tail="${log_tail}" "${cname}" 2>&1 | sed 's/^/  /' >&2 || true
    echo "========== end diagnostics ==========" >&2
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
    docker_print_container_diagnostics "${cname}" 180
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
    local vhost="${subdomain}.${USERVER_VIRTUAL_HOST}"
    echo "Preparing virtual host environment config for '${vhost}'"

    # Replace whole lines: prefix-only s/KEY=/ would match KEY=existing and append on re-run.
    sed -i -e "s|^VIRTUAL_HOST=.*|VIRTUAL_HOST=${vhost}|" "$file"
    if [ "$USERVER_MODE" == "prod" ]; then
        sed -i -e "s|^LETSENCRYPT_HOST=.*|LETSENCRYPT_HOST=${vhost}|" "$file"
        sed -i -e "s|^LETSENCRYPT_EMAIL=.*|LETSENCRYPT_EMAIL=${USERVER_LETSENCRYPT_EMAIL}|" "$file"
    fi
}

# userver-mailer: MAIL_FQDN (compose hostname) and OVERRIDE_HOSTNAME (DMS TLS paths) must match the mail FQDN.
function ensure_mailer_stack_mail_fqdn {
    local mailer_root="${1:?}"
    local fqdn="${USERVER_MAIL_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
    local mail_env="${mailer_root}/mail/.env"
    if [ -f "$mail_env" ]; then
        sed -i "s|^OVERRIDE_HOSTNAME=.*|OVERRIDE_HOSTNAME=${fqdn}|" "$mail_env"
    fi
    local ef="${mailer_root}/.env"
    if [ -f "$ef" ] && grep -q '^MAIL_FQDN=' "$ef" 2>/dev/null; then
        sed -i "s|^MAIL_FQDN=.*|MAIL_FQDN=${fqdn}|" "$ef"
    else
        printf '%s\n' "MAIL_FQDN=${fqdn}" >> "$ef"
    fi
}

# Pull service images from the registry (no build). Honors USERVER_COMPOSE_PULL (default: pull).
# Optional $2: compose file name (default docker-compose.yml). Use a single explicit file to avoid
# merging docker-compose.override.yml (e.g. old dev bind-mounts over /app or /code).
function compose_pull_stack {
    local service_dir="${1:?service directory}"
    local compose_file="${2:-docker-compose.yml}"
    case "${USERVER_COMPOSE_PULL:-true}" in
        1 | true | yes) ;;
        *) return 0 ;;
    esac
    echo "Pulling images for ${service_dir}..."
    (
        cd "${service_dir}" || exit 1
        if docker compose version >/dev/null 2>&1; then
            docker compose -f "${compose_file}" pull
        else
            docker-compose -f "${compose_file}" pull
        fi
    ) || return 1
}

function start_service {
    # $1 = start a service (ex: userver-web)
    service=$1
    # $2 = if it should be rebuilt instead of restarted
    build=$2
    # $3 = optional extra args for "docker compose up" (e.g. --force-recreate so entrypoint/setup.sh runs again)
    compose_extra="${3-}"
    # $4 = optional compose file (e.g. docker-compose.yml) — when set, only this file is used (no override merge)
    compose_file="${4-}"

    build_arg=
    action="Restarting"
    if [ "${build}" == 1 ]; then
        build_arg="--build --remove-orphans"
        action="Building"
    fi

    echo "${action} ${service}..."
    cd "${service}" || exit 1
    local _compose_rc=0
    local _compose_file_args=()
    if [ -n "${compose_file}" ]; then
        _compose_file_args=( -f "${compose_file}" )
    fi
    if docker compose version >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        docker compose "${_compose_file_args[@]}" up ${build_arg} ${compose_extra} -d || _compose_rc=$?
    else
        # shellcheck disable=SC2086
        docker-compose "${_compose_file_args[@]}" up ${build_arg} ${compose_extra} -d || _compose_rc=$?
    fi
    cd .. || return 1
    return "${_compose_rc}"
}

# After compose up: optional warmup, then ensure running and RestartCount stable (not crash-looping).
# Args: container_name, warmup_seconds (default 20; use 0 to skip), settle_seconds between samples (default 5).
function wait_for_container_stable {
    local cname="${1:?container name}"
    local warmup_sec="${2:-20}"
    local settle_sec="${3:-5}"

    if [ "${warmup_sec}" != "0" ]; then
        echo "Waiting ${warmup_sec}s for ${cname} (startup)..."
        sleep "${warmup_sec}"
    fi

    local state
    state="$(docker inspect --format='{{.State.Status}}' "${cname}" 2>/dev/null || true)"
    if [ -z "${state}" ]; then
        echo "Container '${cname}' not found after wait." >&2
        docker_print_container_diagnostics "${cname}" 120
        return 1
    fi
    if [ "${state}" = "restarting" ]; then
        echo "Container '${cname}' is restarting (crash loop)." >&2
        docker_print_container_diagnostics "${cname}" 200
        return 1
    fi
    if [ "${state}" != "running" ]; then
        echo "Container '${cname}' state is '${state}' (expected running)." >&2
        docker_print_container_diagnostics "${cname}" 200
        return 1
    fi

    local c1 c2
    c1="$(docker inspect --format='{{.RestartCount}}' "${cname}" 2>/dev/null)"
    sleep "${settle_sec}"
    state="$(docker inspect --format='{{.State.Status}}' "${cname}" 2>/dev/null || true)"
    if [ "${state}" != "running" ]; then
        echo "Container '${cname}' left running state (now '${state:-missing}')." >&2
        docker_print_container_diagnostics "${cname}" 200
        return 1
    fi
    c2="$(docker inspect --format='{{.RestartCount}}' "${cname}" 2>/dev/null)"
    if [ "${c1}" != "${c2}" ]; then
        echo "Container '${cname}' restart count changed (${c1} -> ${c2}); likely crash loop." >&2
        docker_print_container_diagnostics "${cname}" 200
        return 1
    fi

    echo "${cname}: stable (running, RestartCount=${c2})."
    return 0
}

# Poll until healthcheck=healthy, or fail fast on exited/dead/unhealthy.
# Args: container_name, max_attempts (default 90), delay_seconds (default 2).
function wait_for_container_healthy {
    local cname="${1:?container name}"
    local attempts="${2:-90}"
    local delay="${3:-2}"

    local i state exitcode health
    for i in $(seq 1 "${attempts}"); do
        state="$(docker inspect --format='{{.State.Status}}' "${cname}" 2>/dev/null || true)"
        if [ -z "${state}" ]; then
            echo "wait_for_container_healthy: '${cname}' not found yet (${i}/${attempts})." >&2
            sleep "${delay}"
            continue
        fi

        case "${state}" in
            exited|dead)
                exitcode="$(docker inspect --format='{{.State.ExitCode}}' "${cname}" 2>/dev/null || echo "?")"
                echo "Container '${cname}' ${state} (ExitCode=${exitcode}) before healthcheck passed." >&2
                docker_print_container_diagnostics "${cname}" 200
                return 1
                ;;
            restarting)
                if [ "${i}" -ge 25 ]; then
                    echo "Container '${cname}' still restarting after ~$((i * delay))s; giving up." >&2
                    docker_print_container_diagnostics "${cname}" 200
                    return 1
                fi
                if [ "$((i % 10))" -eq 1 ]; then
                    echo "Container '${cname}' is restarting (${i}/${attempts}); snippet:" >&2
                    docker_print_container_diagnostics "${cname}" 80
                fi
                ;;
        esac

        if [ "${state}" = "running" ]; then
            health="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${cname}" 2>/dev/null || echo none)"
            case "${health}" in
                healthy)
                    echo "${cname}: healthcheck reports healthy."
                    return 0
                    ;;
                unhealthy)
                    echo "Container '${cname}' is running but healthcheck=unhealthy." >&2
                    docker_print_container_diagnostics "${cname}" 250
                    return 1
                    ;;
            esac
            if [ "$((i % 15))" -eq 0 ] || [ "${i}" -eq 1 ]; then
                echo "  ... waiting for healthy (${i}/${attempts}) status=${state} health=${health}" >&2
            fi
        fi

        sleep "${delay}"
    done

    echo "Timeout: '${cname}' did not become healthy within $((attempts * delay))s." >&2
    state="$(docker inspect --format='{{.State.Status}}' "${cname}" 2>/dev/null || true)"
    health="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "${cname}" 2>/dev/null || true)"
    echo "Last observed: Status=${state:-?} Health=${health:-?}" >&2
    docker_print_container_diagnostics "${cname}" 250
    return 1
}

# Poll until docker knows about the container (e.g. depends_on after another service is healthy).
function wait_for_container_to_exist {
    local cname="${1:?container name}"
    local max_sec="${2:-120}"
    local i=0
    echo "Waiting up to ${max_sec}s for container '${cname}' to exist..."
    while [ "${i}" -lt "${max_sec}" ]; do
        if docker inspect "${cname}" >/dev/null 2>&1; then
            return 0
        fi
        if [ "$((i % 20))" -eq 0 ] && [ "${i}" -gt 0 ]; then
            echo "  ... still no container '${cname}' (${i}s / ${max_sec}s)" >&2
        fi
        sleep 1
        i=$((i + 1))
    done
    echo "Container '${cname}' did not appear within ${max_sec}s." >&2
    echo "docker ps -a (names containing partial match):" >&2
    docker ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -F "${cname}" >&2 || docker ps -a --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null | head -25 >&2 || true
    return 1
}

# One shared warmup, then wait_for_container_stable(..., 0, settle) for each name (typical after a stack compose up).
function wait_for_containers_stable {
    local shared="${1:-10}"
    shift
    if [ "$#" -eq 0 ]; then
        echo "wait_for_containers_stable: no container names passed." >&2
        return 1
    fi
    if [ -n "${shared}" ] && [ "${shared}" != "0" ]; then
        echo "Waiting ${shared}s before stability checks for: $*"
        sleep "${shared}"
    fi
    local c settle="${USERVER_STACK_STABLE_SETTLE_SEC:-5}"
    for c in "$@"; do
        wait_for_container_stable "${c}" 0 "${settle}" || return 1
    done
    return 0
}

# Each sed script should replace a full line for KEY=value rows (e.g. s|^KEY=.*|KEY=val|),
# not s/KEY=/KEY=val/ — the latter re-matches on re-run and appends to the value.
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
