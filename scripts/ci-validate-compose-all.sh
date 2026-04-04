#!/usr/bin/env bash
# Clone every stack, seed env templates, run `docker compose config` (same coverage as CI matrix).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
"${SCRIPT_DIR}/ci-clone-all-stacks.sh"
for s in userver-web userver-logger userver-datamgr userver-eventmgr userver-mailer userver-auth userver-filemgr; do
    echo "=== compose config: ${s} ==="
    "${SCRIPT_DIR}/ci-seed-stack-env.sh" "${REPO_ROOT}/ci/stacks/${s}"
    (cd "${REPO_ROOT}/ci/stacks/${s}" && docker compose -f docker-compose.yml config --quiet)
done
echo "All stacks: OK"
