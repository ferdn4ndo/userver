#!/usr/bin/env bash

# Common functions
. ./functions.sh --source-only

print_title "Deploying userver-web..."

# Skip functionality
if [ "$USERVER_SKIP_DEPLOY_WEB" == "true" ]; then
    echo "Deployment of uServer-Web was skipped due to env 'USERVER_SKIP_DEPLOY_WEB' set to true"
    exit 0
fi

build=
if [ ! -d userver-web ] || [ "$USERVER_FORCE_BUILD" == "true" ]; then
    build=1
    stop_and_remove_container userver-web
    clone_repo userver-web

    hosts="${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_DB_ADMINER_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_AUTH_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_FILEMGR_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_MAIL_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_MONITOR_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_POSTFIXADMIN_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_WEBMAIL_HOSTNAME}.${USERVER_VIRTUAL_HOST}"
    hosts="${hosts} ${USERVER_WHOAMI_HOSTNAME}.${USERVER_VIRTUAL_HOST}"

    if [ "$USERVER_MODE" == "prod" ]; then
    envs=(
        "s|^SERVER_NAME=.*|SERVER_NAME=${hosts}|g"
        "s/AUTO_LETS_ENCRYPT=no/AUTO_LETS_ENCRYPT=yes/g"
        #"s/GENERATE_SELF_SIGNED_SSL=no/GENERATE_SELF_SIGNED_SSL=no/g"
        #"s/HTTP2=yes/HTTP2=yes/g"
        #"s/REDIRECT_HTTP_TO_HTTPS=no/REDIRECT_HTTP_TO_HTTPS=no/g"
        #"s/DISABLE_DEFAULT_SERVER=yes/DISABLE_DEFAULT_SERVER=yes/g"
        #"s/ALLOWED_METHODS=GET|POST|PATCH|DELETE|HEAD/ALLOWED_METHODS=GET|POST|PATCH|DELETE|HEAD/g"
        #"s/SERVE_FILES=no/SERVE_FILES=no/g"
    )
    else
    envs=(
        "s|^SERVER_NAME=.*|SERVER_NAME=${hosts}|g"
        #"s/AUTO_LETS_ENCRYPT=no/AUTO_LETS_ENCRYPT=no/g"
        "s/GENERATE_SELF_SIGNED_SSL=no/GENERATE_SELF_SIGNED_SSL=yes/g"
        #"s/HTTP2=yes/HTTP2=yes/g"
        #"s/REDIRECT_HTTP_TO_HTTPS=no/REDIRECT_HTTP_TO_HTTPS=no/g"
        #"s/DISABLE_DEFAULT_SERVER=yes/DISABLE_DEFAULT_SERVER=yes/g"
        #"s/ALLOWED_METHODS=GET|POST|PATCH|DELETE|HEAD/ALLOWED_METHODS=GET|POST|PATCH|DELETE|HEAD/g"
        #"s/SERVE_FILES=no/SERVE_FILES=no/g"
    )
    fi

    # userver-web main no longer ships nginx-firewall (compose only uses nginx-proxy, letsencrypt, monitor, whoami).
    if [ -f userver-web/nginx-firewall/.env.template ]; then
        cp userver-web/nginx-firewall/.env.template userver-web/nginx-firewall/.env
        sed_replace_occurrences userver-web/nginx-firewall/.env "${envs[@]}"
    else
        echo "Skipping nginx-firewall/.env (not present in this userver-web checkout)."
    fi

    cp userver-web/nginx-proxy/.env.template userver-web/nginx-proxy/.env
    sed_replace_occurrences userver-web/nginx-proxy/.env "${envs[@]}"

    envs=(
        "s|^DEFAULT_EMAIL=.*|DEFAULT_EMAIL=${USERVER_LETSENCRYPT_EMAIL}|g"
        "s|^NGINX_PROXY_CONTAINER=.*|NGINX_PROXY_CONTAINER=userver-nginx-proxy|g"
    )
    cp userver-web/letsencrypt/.env.template userver-web/letsencrypt/.env
    sed_replace_occurrences userver-web/letsencrypt/.env "${envs[@]}"

    cp userver-web/monitor/.env.template userver-web/monitor/.env
    prepare_virtual_host userver-web/monitor/.env "${USERVER_MONITOR_HOSTNAME}"

    cp userver-web/whoami/.env.template userver-web/whoami/.env
    prepare_virtual_host userver-web/whoami/.env "${USERVER_WHOAMI_HOSTNAME}"
fi

# acme-companion 2.6+ needs NGINX_DOCKER_GEN_CONTAINER set to the nginx-proxy container when docker-gen is embedded
# in nginxproxy/nginx-proxy (otherwise: "can't get docker-gen container id"). Apply on every run for older .env files.
if [ -f userver-web/letsencrypt/.env ]; then
    if grep -q '^NGINX_DOCKER_GEN_CONTAINER=' userver-web/letsencrypt/.env; then
        sed -i -e 's/^NGINX_DOCKER_GEN_CONTAINER=.*/NGINX_DOCKER_GEN_CONTAINER=userver-nginx-proxy/' userver-web/letsencrypt/.env
    else
        printf '%s\n' '' 'NGINX_DOCKER_GEN_CONTAINER=userver-nginx-proxy' >> userver-web/letsencrypt/.env
    fi
fi

# Compose bind mounts need a host filesystem path. Values like unix:///run/user/... break parsing (too many colons).
_sock="${USERVER_DOCKER_HOST_SOCK:-/var/run/docker.sock}"
case "${_sock}" in
    unix://*) _sock="${_sock#unix://}" ;;
    unix:/*) _sock="${_sock#unix:}" ;;
esac
_sock="$(printf '%s' "${_sock}" | tr -s '/')"

# docker-compose.yml uses ${NGINX_HTTP_PORT:-80} from a .env file in userver-web/ (not nginx-proxy/.env).
# Without this file, the proxy always binds host :80 — URLs like :8880 never hit it.
if [ -d userver-web ]; then
    _ngx_http="${USERVER_NGINX_HTTP_PORT:-80}"
    _ngx_https="${USERVER_NGINX_HTTPS_PORT:-443}"
    _ngx_dh="${USERVER_NGINX_PROXY_DOCKER_HOST:-unix:///var/run/docker.sock}"
    {
        echo "NGINX_HTTP_PORT=${_ngx_http}"
        echo "NGINX_HTTPS_PORT=${_ngx_https}"
        echo "DOCKER_HOST_SOCK=${_sock}"
        echo "NGINX_PROXY_DOCKER_HOST=${_ngx_dh}"
    } > userver-web/.env
fi

# Rootless Docker: connect() to a bind-mounted docker.sock from inside a container often returns EACCES even with
# correct group_add (user-namespace). Use USERVER_NGINX_PROXY_DOCKER_HOST=tcp://host.docker.internal:2375 (or similar)
# after exposing the API on loopback per Docker rootless docs.
if [ -d userver-web ] && docker info 2>/dev/null | grep -qiF rootless; then
    case "${USERVER_NGINX_PROXY_DOCKER_HOST:-}" in
        tcp://*) ;;
        *)
            echo "Note: Docker is rootless. If nginx-proxy logs still show docker.sock permission denied, set" >&2
            echo "  USERVER_NGINX_PROXY_DOCKER_HOST=tcp://host.docker.internal:<port>" >&2
            echo "in .env and expose the Docker API on 127.0.0.1 (see .env.template)." >&2
            ;;
    esac
fi

# docker.sock is often root:docker mode 660; docker-gen needs that GID inside the container. Not used when DOCKER_HOST
# is tcp://. (docker-gen still watches the entire daemon — all compose projects — not only userver-web.)
_socket_gid_override="userver-web/docker-compose.override.yml"
case "${USERVER_NGINX_PROXY_SKIP_DOCKER_GROUP_ADD:-}" in
    1 | true | yes)
        rm -f "${_socket_gid_override}"
        ;;
    *)
        case "${USERVER_NGINX_PROXY_DOCKER_HOST:-}" in
            tcp://*)
                rm -f "${_socket_gid_override}"
                printf 'Skipping %s (DOCKER_HOST is TCP).\n' "${_socket_gid_override}"
                ;;
            *)
                _dgid=
                if [ -S "${_sock}" ]; then
                    # GID visible inside a container (Docker Desktop maps socket to nobody:65534; host stat shows docker).
                    _dgid="$(docker run --rm -v "${_sock}:/tmp/sock:rw" busybox stat -c '%g' /tmp/sock 2>/dev/null | tr -d ' \n')"
                    if [ -z "${_dgid}" ]; then
                        if stat -c '%g' "${_sock}" >/dev/null 2>&1; then
                            _dgid="$(stat -c '%g' "${_sock}")"
                        else
                            _dgid="$(stat -f '%g' "${_sock}" 2>/dev/null || true)"
                        fi
                    fi
                fi
                case "${_dgid}" in
                    *[!0-9]*) _dgid= ;;
                esac
                if [ -n "${_dgid}" ]; then
                    printf 'Writing %s (group_add GID %s for docker socket %s).\n' "${_socket_gid_override}" "${_dgid}" "${_sock}"
                    cat > "${_socket_gid_override}" <<EOF
# Generated by deploy_userver_web.sh — docker API socket group for nginx-proxy / acme / monitor.
# group_add entries must be YAML strings (quoted); Compose v2.18 rejects bare integers here.
services:
  userver-nginx-proxy:
    group_add:
      - "${_dgid}"
  userver-letsencrypt:
    group_add:
      - "${_dgid}"
  userver-monitor:
    group_add:
      - "${_dgid}"
EOF
                else
                    rm -f "${_socket_gid_override}"
                    echo "Warning: no Docker socket at ${_sock} (or could not stat GID); nginx-proxy may fail. Set USERVER_DOCKER_HOST_SOCK (host path, not unix://) or USERVER_NGINX_PROXY_DOCKER_HOST=tcp://..." >&2
                fi
                ;;
        esac
        ;;
esac

# HTTPS_METHOD=redirect makes nginx send Location: https://vhost/ (port 443). With NGINX_HTTP_PORT=8880 and no listener
# on 443, the browser follows to an empty/wrong port → ERR_EMPTY_RESPONSE. Use noredirect for local dev.
if [ -f userver-web/nginx-proxy/.env ]; then
    if [ "$USERVER_MODE" = "prod" ]; then
        sed -i -e 's/^HTTPS_METHOD=.*/HTTPS_METHOD=redirect/' userver-web/nginx-proxy/.env
    else
        sed -i -e 's/^HTTPS_METHOD=.*/HTTPS_METHOD=noredirect/' userver-web/nginx-proxy/.env
    fi
fi

start_service userver-web "$build" || exit 1

# Docker Compose v5+ sometimes sends SIGTERM to a long-running service during multi-container converge (nginx error.log
# shows workers getting signal 15 from PID 1 right after a successful reload). A short pause and a second `up -d`
# (no build) brings any mistakenly stopped containers back to the desired state.
(
    cd userver-web || exit 0
    sleep 3
    if docker compose version >/dev/null 2>&1; then
        docker compose up -d --no-build
    else
        docker-compose up -d
    fi
) || true

wait_for_containers_stable 12 userver-nginx-proxy userver-letsencrypt userver-monitor userver-whoami || exit 1
