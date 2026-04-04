#!/usr/bin/env bash
# Fetch and fast-forward each userver-* service repo under this directory (gitignored clones).
# Run from the uServer root after ./run.sh has cloned services, or whenever you want latest upstream.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

shopt -s nullglob
for repo in userver-*/; do
    [ -d "${repo}/.git" ] || continue
    name="${repo%/}"
    echo "Updating ${name}..."
    git -C "${name}" fetch origin
    br="$(git -C "${name}" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
    if [ -z "${br}" ]; then
        if git -C "${name}" show-ref --verify --quiet refs/remotes/origin/main; then
            br=main
        elif git -C "${name}" show-ref --verify --quiet refs/remotes/origin/master; then
            br=master
        else
            echo "  skip: could not determine default branch" >&2
            continue
        fi
    fi
    git -C "${name}" checkout "${br}"
    git -C "${name}" pull --ff-only origin "${br}" || git -C "${name}" pull origin "${br}" --no-rebase
done
echo "Done."
