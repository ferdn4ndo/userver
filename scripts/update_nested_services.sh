#!/usr/bin/env bash
# Fetch and fast-forward each userver-* service repo under this directory (gitignored clones).
# Run from the uServer root after ./run.sh has cloned services, or whenever you want latest upstream.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: update_nested_services.sh [--chown] [--reset-hard] [--help]

  --chown       Fix ownership on each repo (chown, then sudo chown if needed) before git
                writes. Use when Docker bind mounts left root-owned files (Permission denied
                on checkout/pull).
  --reset-hard  After fetch, force the working tree to match origin/<branch> (discards local
                commits and uncommitted changes).

Environment (optional): USERVER_NESTED_CHOWN=1|true, USERVER_NESTED_RESET_HARD=1|true
EOF
}

# Use a prefixed name so a random exported RESET_HARD in the environment cannot affect behavior.
UPDATE_NESTED_CHOWN=0
UPDATE_NESTED_RESET_HARD=0
for arg in "$@"; do
    case "$arg" in
        --chown) UPDATE_NESTED_CHOWN=1 ;;
        --reset-hard) UPDATE_NESTED_RESET_HARD=1 ;;
        -h | --help) usage; exit 0 ;;
        *)
            echo "Unknown option: ${arg}" >&2
            usage
            exit 1
            ;;
    esac
done
case "${USERVER_NESTED_CHOWN:-}" in 1 | true | yes) UPDATE_NESTED_CHOWN=1 ;; esac
case "${USERVER_NESTED_RESET_HARD:-}" in 1 | true | yes) UPDATE_NESTED_RESET_HARD=1 ;; esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

nested_chown_repo() {
    local d="$1"
    [ "${UPDATE_NESTED_CHOWN}" = 1 ] || return 0
    echo "  chown -> $(id -un):$(id -gn)"
    if chown -R "$(id -un):$(id -gn)" "${d}" 2>/dev/null; then
        return 0
    fi
    sudo chown -R "$(id -un):$(id -gn)" "${d}"
}

# Sync one clone. Returns 0 on success, 1 on failure (prints to stderr).
# Git steps run in a subshell with errexit so one repo's failure does not abort the whole script.
update_one_nested_repo() {
    local name="$1"

    nested_chown_repo "${ROOT}/${name}"
    export UPDATE_NESTED_RESET_HARD
    if ! (
        set -euo pipefail
        cd "${ROOT}/${name}" || exit 1

        local br
        local oref
        local head_ref

        git fetch origin --prune
        git remote set-head origin -a 2>/dev/null || true

        br="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
        if [ -z "${br}" ] || ! git show-ref --verify --quiet "refs/remotes/origin/${br}"; then
            br=
        fi
        if [ -z "${br}" ]; then
            if git show-ref --verify --quiet refs/remotes/origin/main; then
                br=main
            elif git show-ref --verify --quiet refs/remotes/origin/master; then
                br=master
            else
                echo "  skip: could not determine default branch" >&2
                exit 0
            fi
        fi

        oref="refs/remotes/origin/${br}"

        if [ "${UPDATE_NESTED_RESET_HARD}" = 1 ]; then
            # Already on ${br}: reset --hard clears dirty tracked files without checkout.
            head_ref="$(git symbolic-ref -q HEAD 2>/dev/null || true)"
            if [ "${head_ref}" = "refs/heads/${br}" ]; then
                git reset --hard "${oref}"
                exit 0
            fi
            if git checkout -f "${br}" 2>/dev/null; then
                git reset --hard "${oref}"
                exit 0
            fi
            if git checkout -B "${br}" -f "${oref}"; then
                git reset --hard "${oref}"
                exit 0
            fi
            if git checkout -f --detach "${oref}"; then
                git branch -f "${br}" HEAD
                git checkout -f "${br}"
                git reset --hard "${oref}"
                exit 0
            fi
            echo "  error: could not force-sync to ${oref}" >&2
            exit 1
        fi

        if ! git checkout "${br}" 2>/dev/null; then
            echo "  checkout failed (local changes?). Re-run with --reset-hard to discard them." >&2
            exit 1
        fi
        git pull --ff-only origin "${br}" || git pull origin "${br}" --no-rebase
        exit 0
    ); then
        return 1
    fi
    return 0
}

shopt -s nullglob
for repo in userver-*/; do
    [ -d "${repo}/.git" ] || continue
    name="${repo%/}"
    echo "Updating ${name}..."
    if ! update_one_nested_repo "${name}"; then
        echo "  warn: ${name} update failed (see messages above)." >&2
    fi
done
echo "Done."
