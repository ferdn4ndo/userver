#!/usr/bin/env bash
# Legacy entrypoint: clone + seed userver-eventmgr only (smoke tests / local experiments).
# Full stack compose validation runs via .github/workflows/test_compose.yml (matrix).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"${REPO_ROOT}/scripts/ci-clone-one-stack.sh" userver-eventmgr
"${REPO_ROOT}/scripts/ci-seed-stack-env.sh" "${REPO_ROOT}/ci/stacks/userver-eventmgr"
