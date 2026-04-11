#!/usr/bin/env bash
# Shallow-clone a ferdn4ndo/userver-* service repo under ci/stacks/<name>, or copy bundled stacks.
set -euo pipefail
STACK="${1:?Usage: $0 <stack-repo-name e.g. userver-web>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${REPO_ROOT}/ci/stacks/${STACK}"
mkdir -p "${REPO_ROOT}/ci/stacks"
rm -rf "${DEST}"

# Prefer compose shipped in this repo (Docker Hub stacks). If not committed yet, shallow-clone upstream.
if [ "${STACK}" = "userver-auth" ] || [ "${STACK}" = "userver-filemgr" ]; then
    if [ -f "${REPO_ROOT}/${STACK}/docker-compose.yml" ]; then
        cp -a "${REPO_ROOT}/${STACK}" "${DEST}"
        echo "Copied bundled ${STACK} -> ${DEST}"
        exit 0
    fi
    echo "No bundled ${STACK}/docker-compose.yml in this checkout; cloning upstream..." >&2
fi

git clone --depth 1 "https://github.com/ferdn4ndo/${STACK}.git" "${DEST}"
echo "Cloned ${STACK} -> ${DEST}"
