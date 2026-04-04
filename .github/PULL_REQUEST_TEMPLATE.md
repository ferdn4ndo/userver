## Scope

<!-- Brief bullets describing the change. -->

## Checklist

- [ ] Shell scripts follow existing style; ShellCheck is clean where applicable
- [ ] If CI or deploy paths changed: `scripts/ci-clone-one-stack.sh`, `scripts/ci-seed-stack-env.sh`, `.github/workflows/test_compose.yml` matrix, `.github/actions/deploy_local`, or service `docker-compose.yml` are consistent
- [ ] Nested apps (`userver-auth`, `userver-filemgr`): dependencies and Dockerfiles still build
- [ ] Workflows and README badges remain accurate for this repository

Thank you!
