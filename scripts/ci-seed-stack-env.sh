#!/usr/bin/env bash
# Copy every **/.env.template under STACK_ROOT to sibling .env (Compose env_file paths).
# userver-eventmgr: append a CI MQTT user so Mosquitto pwfile bootstrap succeeds.
set -euo pipefail
STACK_ROOT="${1:?Usage: $0 <path-to-cloned-stack>}"
if [ ! -d "${STACK_ROOT}" ]; then
    echo "Not a directory: ${STACK_ROOT}" >&2
    exit 1
fi

while IFS= read -r -d '' tmpl; do
    target="${tmpl%.template}"
    cp "${tmpl}" "${target}"
done < <(find "${STACK_ROOT}" -name '.env.template' -print0)

if [ "$(basename "${STACK_ROOT}")" = "userver-eventmgr" ]; then
    # Not named *.env.template — must copy explicitly (entrypoint builds pwfile from this file).
    su_tmpl="${STACK_ROOT}/mosquitto/config/setup-users.env.template"
    su="${STACK_ROOT}/mosquitto/config/setup-users.env"
    if [ -f "${su_tmpl}" ]; then
        cp "${su_tmpl}" "${su}"
        printf '%s\n' 'ci-mqtt=github-actions-ci' >> "${su}"
    fi
    # Mosquitto runs as non-root; bind mounts must allow log/pwfile writes. Fresh clones and CI
    # checkouts often produce root-owned or mode-restricted dirs after a previous Docker run.
    mkdir -p \
        "${STACK_ROOT}/mosquitto/log" \
        "${STACK_ROOT}/mosquitto/data" \
        "${STACK_ROOT}/rabbitmq/data"
    chmod -R a+rwx \
        "${STACK_ROOT}/mosquitto/log" \
        "${STACK_ROOT}/mosquitto/data" \
        "${STACK_ROOT}/mosquitto/config" \
        "${STACK_ROOT}/rabbitmq/data" \
        "${STACK_ROOT}/rabbitmq/conf.d" 2>/dev/null || true
fi

# No root .env.template — compose still substitutes MAIL_FQDN for the mail container hostname.
if [ "$(basename "${STACK_ROOT}")" = "userver-mailer" ]; then
    root_env="${STACK_ROOT}/.env"
    if [ -f "$root_env" ] && grep -q '^MAIL_FQDN=' "$root_env" 2>/dev/null; then
        sed -i 's|^MAIL_FQDN=.*|MAIL_FQDN=mail.ci.example.invalid|' "$root_env"
    else
        printf '%s\n' 'MAIL_FQDN=mail.ci.example.invalid' >> "$root_env"
    fi
fi
