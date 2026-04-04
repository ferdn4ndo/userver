# Migrating an existing uServer deployment

This document applies to the **orchestration repo** only. Service images and databases live in the cloned `userver-*` directories and in Docker volumes/bind mounts defined by each service’s `docker-compose.yml`.

## Preserving data

- **Do not run `./remove.sh`** if you want to keep databases, mail spools, or uploaded files. That script deletes cloned service trees and runs `docker compose rm -fsv` in each stack, which removes **named volumes** declared in those compose files.
- **Bind-mounted directories** on the host (for example `userver-eventmgr/mosquitto/data`, `userver-eventmgr/rabbitmq/data`, `userver-filemgr/local`, `userver-filemgr/logs`) keep their files across image upgrades as long as you do not delete those folders and the compose paths stay the same.
- After pulling a newer **userver-eventmgr** layout, if upstream renames a volume or mount path, copy data once from the old path to the new path while containers are stopped, then start again.

## PostgreSQL (auth, filemgr, mailer, webmail)

- Schema changes are applied by each app’s own **migrations** (Alembic / Django) when their containers start (`setup.sh` / entrypoints). Back up databases before major upgrades (`pg_dump`).
- If you only rebuild images and keep the same Postgres volume and database names, existing data is reused.

## Default Git branch (`main` vs `master`)

Upstream repos use **`main`** as the default branch. Older checkouts may still have **`refs/remotes/origin/HEAD` → `master`** even after GitHub dropped `master`, which caused `fatal: couldn't find remote ref master` on pull. **`./run.sh`** now runs **`git fetch origin --prune`**, **`git remote set-head origin -a`** (refresh default branch), then picks **`main`** or **`master`** only if that remote-tracking ref exists. Run **`./scripts/update_nested_services.sh`** for the same logic on all clones.

## Permission denied / dirty `userver-*` checkouts

If Git reports **`unable to unlink`** / **`Permission denied`** under a cloned service, or **`would be overwritten by checkout`**, containers have often written **root-owned** or **locally modified** files into bind-mounted paths inside those repos.

- One-off sync: **`./scripts/update_nested_services.sh --chown --reset-hard`** (uses `sudo` for chown when your user cannot fix ownership).
- Ongoing deploy host: set **`USERVER_REPO_SUDO_CHOWN=true`** in **`.env`** so **`./run.sh`** chowns before pull; set **`USERVER_REPO_GIT_RESET_HARD=true`** only if you accept discarding any local drift in service repos so they always match **`origin`**.

## Compose v2

Scripts use `docker compose` when available and fall back to `docker-compose`. Volume and network names are determined by the project directory and compose file; avoid renaming `userver-*` folders arbitrarily if you rely on default project names.

## New: userver-eventmgr

Adding EventMgr does not migrate data from other services. It creates new broker state under `userver-eventmgr/` bind mounts. Set `USERVER_EVENTMGR_*` in `.env` and run `./deploy_userver_eventmgr.sh` or full `./run.sh`.
