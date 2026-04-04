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

Upstream repos now use **`main`** as the default branch. Existing clones on `master` are switched automatically on the next `./run.sh` (or `clone_repo`) **fetch + checkout + pull** to `origin/HEAD` (or `main` / `master` fallback).

## Compose v2

Scripts use `docker compose` when available and fall back to `docker-compose`. Volume and network names are determined by the project directory and compose file; avoid renaming `userver-*` folders arbitrarily if you rely on default project names.

## New: userver-eventmgr

Adding EventMgr does not migrate data from other services. It creates new broker state under `userver-eventmgr/` bind mounts. Set `USERVER_EVENTMGR_*` in `.env` and run `./deploy_userver_eventmgr.sh` or full `./run.sh`.
