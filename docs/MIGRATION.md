# Migrating an existing uServer deployment

This document applies to the **orchestration repo** only. Service images and databases live in Docker volumes/bind mounts and in cloned **`userver-*`** trees (except **`userver-auth`** and **`userver-filemgr`**, which ship here and use **Docker Hub** images).

## Preserving data

- **Do not run `./remove.sh`** if you want to keep databases, mail spools, or uploaded files. That script runs `docker compose rm -fsv` in each stack (removes **named volumes** in those compose files), deletes **cloned** service trees, and for **auth / filemgr** removes only **`.env`** and **`userver-filemgr/local`** (plus legacy **`logs`** / **`tmp`** if present; compose files stay in this repo).
- **Bind-mounted directories** on the host (for example `userver-eventmgr/mosquitto/data`, `userver-eventmgr/rabbitmq/data`, **`userver-filemgr/local`**) keep their files across image upgrades as long as you do not delete those folders and the compose paths stay the same.
- After pulling a newer **userver-eventmgr** layout, if upstream renames a volume or mount path, copy data once from the old path to the new path while containers are stopped, then start again.

## PostgreSQL (auth, filemgr, mailer, webmail)

- Schema changes are applied by each app’s own **migrations** (Go services use embedded migrations in `setup.sh`; others may use Alembic / Django) when their containers start. Back up databases before major upgrades (`pg_dump`).
- If you only rebuild images and keep the same Postgres volume and database names, existing data is reused.

### Postgres TLS (userver-datamgr)

Upstream **userver-datamgr** enables TLS on **`userver-postgres`** via **`postgres/docker-ensure-tls.sh`**: either **Let’s Encrypt** files from **userver-web** (`../userver-web/certs` when **`USERVER_MODE=prod`** and **`USERVER_VIRTUAL_HOST`** is set) or **self-signed** files from **`userver-datamgr/postgres/ssl/`** (dev). **`deploy_userver_datamgr.sh`** runs **`postgres/generate-ssl.sh`** automatically in dev when **openssl** is available and those files are missing. For production, deploy **userver-web** before DataMgr so ACME can issue certs; the Postgres entrypoint waits for **`${POSTGRES_SSL_CERT_BASENAME}.{crt,key}`**. Apps on the Docker network can use **`sslmode=require`** (e.g. set **`USERVER_AUTH_ENV_MODE=prod`** for userver-auth and **`USERVER_FILEMGR_ENV_MODE=prod`** for userver-filemgr when using this stack in prod).

### `User "postgres" does not have a valid SCRAM secret`

If **`userver-postgres`** logs show **FATAL** with **does not have a valid SCRAM secret** (for **`postgres`**, **`webmail`**, **`postfix`**, etc.), TCP clients cannot authenticate with SCRAM even when the password in `.env` looks right. That usually means the role has **no usable password verifier** in the catalog (often after a **major PostgreSQL upgrade** on an existing data directory).

1. Ensure **`USERVER_DB_USER`** and **`USERVER_DB_PASSWORD`** in the orchestration **`.env`** match the Postgres superuser (**`POSTGRES_USER`** / **`POSTGRES_PASSWORD`** in **`userver-datamgr/postgres/.env`**).
2. From the orchestration repo root, run:

   **`./scripts/fix_postgres_superuser_scram.sh`**

   It runs **`ALTER USER … WITH PASSWORD …`** for **`USERVER_DB_USER`** over a **local socket** inside the container using **`USERVER_DB_PASSWORD`**.

3. If **mailer** DB users still log the same error, connect as **`postgres`** with that password and set their passwords again, or re-run mailer deploy so **`CREATE USER` / `ALTER USER`** run from a working superuser session.

## Default Git branch (`main` vs `master`)

Upstream repos use **`main`** as the default branch. Older checkouts may still have **`refs/remotes/origin/HEAD` → `master`** even after GitHub dropped `master`, which caused `fatal: couldn't find remote ref master` on pull. **`./run.sh`** now runs **`git fetch origin --prune`**, **`git remote set-head origin -a`** (refresh default branch), then picks **`main`** or **`master`** only if that remote-tracking ref exists. Run **`./scripts/update_nested_services.sh`** for the same logic on all clones.

## Permission denied / dirty `userver-*` checkouts

If Git reports **`unable to unlink`** / **`Permission denied`** under a cloned service, or **`would be overwritten by checkout`**, containers have often written **root-owned** or **locally modified** files into bind-mounted paths inside those repos.

- One-off sync: **`./scripts/update_nested_services.sh --chown --reset-hard`** (uses `sudo` for chown when your user cannot fix ownership).
- Ongoing deploy host: set **`USERVER_REPO_SUDO_CHOWN=true`** in **`.env`** so **`./run.sh`** chowns before pull; set **`USERVER_REPO_GIT_RESET_HARD=true`** only if you accept discarding any local drift in service repos so they always match **`origin`**.

## Compose v2

Scripts use `docker compose` when available and fall back to `docker-compose`. Volume and network names are determined by the project directory and compose file; avoid renaming `userver-*` folders arbitrarily if you rely on default project names.

## Mailer: `OVERRIDE_HOSTNAME` and `MAIL_FQDN` (docker-mailserver + Let’s Encrypt)

docker-mailserver resolves TLS under `/etc/letsencrypt/live/<FQDN>/` from the **container hostname**, not from **`LETSENCRYPT_HOST`**. Upstream **`userver-mailer`** expects **`OVERRIDE_HOSTNAME`** in **`mail/.env`** and **`MAIL_FQDN`** in **`.env` next to `docker-compose.yml`** to match your real mail FQDN (and nginx-proxy certs).

After upgrading **userver-mailer** and this orchestration repo, run **`./deploy_userver_mailer.sh`** (or **`./run.sh`**) so **`deploy_userver_mailer.sh`** updates both; or set **`OVERRIDE_HOSTNAME`** and **`MAIL_FQDN`** manually to the same value (typically **`${USERVER_MAIL_HOSTNAME}.${USERVER_VIRTUAL_HOST}`**).

## New: userver-eventmgr

Adding EventMgr does not migrate data from other services. It creates new broker state under `userver-eventmgr/` bind mounts. Set `USERVER_EVENTMGR_*` in `.env` and run `./deploy_userver_eventmgr.sh` or full `./run.sh`.
