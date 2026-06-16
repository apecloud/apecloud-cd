---
name: auxiliary-operations
description: >
  Handle auxiliary CI/CD workflows in apecloud-cd: workflow trigger, database migration,
  OpenShift preflight, Red Hat certification. Use for migrate-database.yml, openshift-preflight.yml,
  or other workflows that do not fit into chart, image, e2e, or release domains.
---

# Auxiliary Operations

This skill covers **miscellaneous auxiliary workflows** that are not tightly coupled to a single main domain.

## Related Files

### Workflows

| Workflow | Purpose |
|---|---|
| [`.github/workflows/migrate-database.yml`](../../.github/workflows/migrate-database.yml) | Run golang-migrate against a PostgreSQL service container |
| [`.github/workflows/openshift-preflight.yml`](../../.github/workflows/openshift-preflight.yml) | Red Hat OpenShift certification preflight checks for container images |

## migrate-database.yml

Runs database migrations using the `migrate` CLI in a GitHub Actions job with a PostgreSQL sidecar.

Key inputs:

- `MIGRATE_PATH`: path to migration files.
- `MIGRATE_COMMAND`: migrate command, default `up`.
- `POSTGRESQL_VERSION`: PostgreSQL version for the service container, default `14.12`.
- `REPEAT_MIGRATE`: whether to repeat migration.
- `MIGRATE_VERSION`: target `schema_migrations` version.

Common use case: apply schema migrations for cloud-control or other Go services before release.

## openshift-preflight.yml

Runs Red Hat's `preflight` tool against a container image to validate OpenShift certification requirements.

Key inputs:

- `IMAGE`: image to check, e.g. `docker.io/apecloud/kubeblocks:1.0.1-certified`.
- `SUBMIT`: whether to submit results to Red Hat, default `false`.
- `COMPONENT_ID`: Red Hat certification component ID.

Environment variables:

- `PFLT_PYXIS_API_TOKEN`: Red Hat API key.
- `PFLT_CERTIFICATION_COMPONENT_ID`: component ID fallback.
- `PFLT_VERSION`: preflight tool version, default `1.16.0`.

## Related Skills

- [image-management](../image-management/SKILL.md) — the image being preflight-checked
- [release-operations](../release-operations/SKILL.md) — certification is often part of release
