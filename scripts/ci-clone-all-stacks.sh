#!/usr/bin/env bash
# Clone all orchestrated stacks (for local runs of full validation).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
for s in userver-web userver-logger userver-datamgr userver-eventmgr userver-mailer userver-auth userver-filemgr; do
    "${SCRIPT_DIR}/ci-clone-one-stack.sh" "${s}"
done
