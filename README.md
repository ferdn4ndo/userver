# uServer

Docker-based hosting stack: reverse proxy, TLS, data layer, mail, auth, files, and **event messaging** (MQTT + RabbitMQ). Services are pulled in as separate repositories and started with shell scripts and Compose.

**Note:** This meta-repo is still evolving; pin versions in production and review each service’s own README.

Architecture overview: [`docs/userver_main_diagram.drawio`](docs/userver_main_diagram.drawio) (open in [diagrams.net](https://app.diagrams.net/); export to PNG for presentations if needed).

## Services (typical deploy order)

1. **[userver-web](https://github.com/ferdn4ndo/userver-web)** — HTTP/HTTPS edge: `nginx-proxy`, Let’s Encrypt companion, Netdata-style monitoring.
2. **[userver-logger](https://github.com/ferdn4ndo/userver-logger)** — Loki / Grafana / Promtail (or equivalent) for logs and metrics.
3. **[userver-datamgr](https://github.com/ferdn4ndo/userver-datamgr)** — PostgreSQL, Redis, Adminer, DB backups.
4. **[userver-eventmgr](https://github.com/ferdn4ndo/userver-eventmgr)** — **Mosquitto (MQTT)** and **RabbitMQ** on the shared `nginx-proxy` network (cloned into `userver-eventmgr/`).
5. **[userver-mailer](https://github.com/ferdn4ndo/userver-mailer)** — SMTP/IMAP/POP, backups, webmail. PostfixAdmin **`custom-entrypoint.sh`** / **`setup.sh`** live in that repo under **`postfixadmin/`**; this orchestration repo keeps the same files under **`patches/userver-mailer/postfixadmin/`** only as a fallback for old clones missing them.
6. **[userver-auth](https://github.com/ferdn4ndo/userver-auth)** — Flask JWT auth API (cloned into `userver-auth/`).
7. **[userver-filemgr](https://github.com/ferdn4ndo/userver-filemgr)** — Django REST file manager with S3 integration (cloned into `userver-filemgr/`).

Cloned `userver-*` directories are **gitignored** here; they are plain Git checkouts of the upstream repos. **`./run.sh`** clones or **updates** them (default branch: `origin/HEAD`, else `main` / `master`). To refresh all existing clones without a full orchestration run, use **`./scripts/update_nested_services.sh`**. On servers where Docker left root-owned files or you have accidental local edits in a clone, use **`./scripts/update_nested_services.sh --chown --reset-hard`** (see **`docs/MIGRATION.md`**).

## Data and upgrades

See **[docs/MIGRATION.md](docs/MIGRATION.md)** for bind mounts, Postgres, switching to `main`, and adding **userver-eventmgr** without losing volumes.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with **Compose v2** (`docker compose`). The scripts still fall back to `docker-compose` if the plugin is missing.
- A single Docker network named **`nginx-proxy`** (created automatically by `run.sh` if absent).

## Local setup

1. Copy `.env.template` to `.env` and set at least `USERVER_VIRTUAL_HOST`, secrets, and database credentials.
2. For **EventMgr**, set `USERVER_EVENTMGR_*` variables (see `.env.template`). If `USERVER_EVENTMGR_MQTT_USER` / `USERVER_EVENTMGR_MQTT_PASS` are empty, a **dev-only** MQTT user `localdev=localdev` is appended; set real credentials for production.
3. Run:

   ```bash
   ./run.sh
   ```

   Wait until `=========  SETUP FINISHED! =========`.

4. Stop the stack:

   ```bash
   ./stop.sh
   ```

5. Remove containers, volumes, and cloned service directories (destructive):

   ```bash
   ./remove.sh
   ```

## AWS EC2 (legacy notes)

The steps in earlier revisions (Amazon Linux 2, `yum`, PEM SSH) still apply in spirit: install Docker, clone this repo, configure `.env`, run `./run.sh`. Prefer the current [Docker on EC2](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/docker-basics.html) documentation for package names on your AMI.

Open **80**, **443**, mail ports as needed, and **22** for SSH from a trusted source.

## CI

GitHub Actions in `.github/workflows/`:

- **Compose validation** — matrix over **all seven stacks** (`userver-web`, `userver-logger`, `userver-datamgr`, `userver-eventmgr`, `userver-mailer`, `userver-auth`, `userver-filemgr`): shallow clone, seed `**/.env` from `**/.env.template`, then validate the Compose file.
- **Validate EventMgr stack** — clone + seed **userver-eventmgr**, then `docker compose up --wait` and smoke checks (`.github/actions/deploy_local`).
- **ShellCheck** and **Gitleaks** on the orchestration repo.

CI clones live under **`ci/stacks/<repo>/`** (gitignored). `scripts/ci-prepare.sh` still clones and seeds **only userver-eventmgr** for quick local smoke tests.

## Testing (local)

**Parent orchestration**

```bash
# Shell syntax
bash -n run.sh stop.sh remove.sh functions.sh scripts/*.sh deploy_userver_*.sh

# Same compose validation as CI (requires Docker)
./scripts/ci-validate-compose-all.sh

# Or one stack:
./scripts/ci-clone-one-stack.sh userver-web
./scripts/ci-seed-stack-env.sh ci/stacks/userver-web
( cd ci/stacks/userver-web && docker compose -f docker-compose.yml config --quiet )
```

**Nested services** (run inside each clone; see their READMEs / `.github/workflows/`):

- **userver-auth:** CI builds the image and runs `flask test` with Postgres (see `userver-auth/.github/workflows/test_ut_e2e.yaml`). Locally: `docker build -t userver-auth:local ./userver-auth` then `docker run … userver-auth:local bash -lc "flask test"` with the same env vars as that workflow, plus a reachable Postgres.
- **userver-filemgr:** follow upstream tests (Django / Docker) in that repository.

## Contributors

[Fernando Constantino (ferdn4ndo)](https://github.com/ferdn4ndo)

Contributions welcome via issues and pull requests.
