#!/usr/bin/env bash
# Shallow-clone a single ferdn4ndo/userver-* service repo under ci/stacks/<name>.
set -euo pipefail
STACK="${1:?Usage: $0 <stack-repo-name e.g. userver-web>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${REPO_ROOT}/ci/stacks/${STACK}"
mkdir -p "${REPO_ROOT}/ci/stacks"
rm -rf "${DEST}"
git clone --depth 1 "https://github.com/ferdn4ndo/${STACK}.git" "${DEST}"
echo "Cloned ${STACK} -> ${DEST}"
