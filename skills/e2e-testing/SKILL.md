---
name: e2e-testing
description: >
  KubeBlocks E2E testing infrastructure: kbcli-test.yml reusable workflow, kbcli-test-k8s.yml,
  cloud-e2e-*.yml, terraform-init, terraform-destroy, test-type, random-suffix.
  Use when adjusting kbcli-test parameters, adding E2E entry points, or changing cloud-e2e / terraform
  cluster lifecycle.
---

# E2E Testing

This skill covers **generic E2E testing infrastructure**: the `kbcli-test` reusable workflow, cloud-e2e trigger chains, and terraform cluster create/destroy.

## Related Files

### Workflows

| Workflow | Purpose |
|---|---|
| [`.github/workflows/kbcli-test.yml`](../../.github/workflows/kbcli-test.yml) | Core reusable workflow: run kbcli tests on an existing K8s cluster |
| [`.github/workflows/kbcli-test-k8s.yml`](../../.github/workflows/kbcli-test-k8s.yml) | kbcli test entry point that creates the K8s cluster first |
| [`.github/workflows/kbcli-pre-test-k8s.yml`](../../.github/workflows/kbcli-pre-test-k8s.yml) | K8s pre-test |
| [`.github/workflows/kbcli-test-pre.yml`](../../.github/workflows/kbcli-test-pre.yml) | kbcli pre-test preparation |
| [`.github/workflows/cloud-e2e-engine.yml`](../../.github/workflows/cloud-e2e-engine.yml) | Engine E2E on cloud |
| [`.github/workflows/cloud-e2e-api.yml`](../../.github/workflows/cloud-e2e-api.yml) | API E2E on cloud |
| [`.github/workflows/cloud-e2e-web.yml`](../../.github/workflows/cloud-e2e-web.yml) | Web E2E on cloud |
| [`.github/workflows/cloud-e2e-installer.yml`](../../.github/workflows/cloud-e2e-installer.yml) | Installer E2E on cloud |
| [`.github/workflows/cloud-e2e-schedule-dev.yml`](../../.github/workflows/cloud-e2e-schedule-dev.yml) | Scheduled E2E for dev environment |
| [`.github/workflows/cloud-e2e-schedule-idc.yml`](../../.github/workflows/cloud-e2e-schedule-idc.yml) | Scheduled E2E for IDC |
| [`.github/workflows/cloud-e2e-schedule-web.yml`](../../.github/workflows/cloud-e2e-schedule-web.yml) | Scheduled Web E2E |
| [`.github/workflows/terraform-init.yml`](../../.github/workflows/terraform-init.yml) | Create cloud K8s cluster (also in cloud-deploy) |
| [`.github/workflows/terraform-destroy.yml`](../../.github/workflows/terraform-destroy.yml) | Destroy cloud K8s cluster (also in cloud-deploy) |

### Utils

| Script | Purpose |
|---|---|
| [`.github/utils/cloud_e2e_installer.sh`](../../.github/utils/cloud_e2e_installer.sh) | Install cloud E2E environment |

## kbcli-test.yml Key Inputs

- `test-type`: test type number, e.g. `0` (install), `2` (postgresql), `5` (redis).
- `test-type-name`: display name for job/reports.
- `test-args`: arguments passed to kbcli-test, commonly `--service-version`, `--topology`, `--replicas`.
- `release-version`: KubeBlocks version.
- `k8s-cluster-name` / `artifact-name` / `random-suffix`: cluster and artifact correlation.

## Call Chain

```
kbcli-test-k8s.yml
   ├── terraform-init.yml
   └── kbcli-test.yml

kubeblocks-e2e-test.yml
   ├── terraform-init.yml
   ├── test-kubeblocks (test-type 0)
   ├── kbcli-test.yml (per engine/version)
   ├── send-message-* jobs
   └── terraform-destroy.yml
```

## Common Tasks

### 1. Add a standalone E2E entry point

1. Decide whether a new K8s cluster is needed: reuse `kbcli-test-k8s.yml` if yes, otherwise reuse `kbcli-test.yml`.
2. Determine the `test-type` number (add in kbcli-test code if necessary).
3. Write a workflow that calls `kbcli-test.yml` with the correct `test-args`.
4. If scheduled, add a `cloud-e2e-schedule-*.yml`.

### 2. Modify K8s cluster creation logic

`terraform-init.yml` creates the cluster via terraform and outputs `k8s-cluster-name`. When modifying:

- Keep inputs consistent: `cloud-provider`, `region`, `cluster-version`, `instance-type`.
- `terraform-destroy.yml` is usually orchestrated to run with `always()`.

### 3. Adjust kbcli-test arguments

`test-args` can be freely combined:

```yaml
test-args: "--service-version 8.4.3 ${{ inputs.ARGS }}"
test-args: "--service-version 4.2 --topology distribution --replicas 3 ${{ inputs.ARGS }}"
```

### 4. Test result aggregation

`utils.sh --type 36` aggregates test results (used in `kubeblocks-e2e-test.yml` send-message jobs). See [kubeblocks-e2e-workflow](kubeblocks-e2e-workflow/SKILL.md) for details.


## Troubleshooting

### Engine job never starts
- Check `inputs.TEST_TYPE` filtering. The `if` condition uses `contains(..., '<engine>|')` and
  `endsWith(..., '<engine>')`; for sub-variants (`mongodb` + `mongodb-shard`) both must be listed.
- Ensure the prerequisite wave completed successfully. A Wave 2 job needs Wave 1 jobs in `needs`.

### `kbcli-test.yml` fails with missing inputs
- Any required input added to `kbcli-test.yml` must also be added to all callers,
  including `kubeblocks-e2e-test.yml`, `kbcli-test-k8s.yml`, and `cloud-e2e-*.yml`.

### Test result is empty in send-message job
- Confirm the engine job ID in the send-message `needs` matches the actual test job ID.
- Verify the engine job actually sets `outputs.test-result` and `outputs.test-result-report`.
- Check that `utils.sh --type 36` receives the expected `TEST_RESULT` format.

### Cluster creation fails in `terraform-init.yml`
- Validate `CLOUD_PROVIDER`, `REGION`, `CLUSTER_VERSION`, and `INSTANCE_TYPE` inputs.
- Ensure cloud credentials and terraform state backend are configured for the target provider.

### `terraform-destroy-k8s` runs before send-message
- Add the missing `send-message-*` job to `terraform-destroy-k8s.needs`.
- The destroy job uses `if: always()`, so it will run as soon as all explicit `needs` complete,
  including failed jobs.

## Related Skills

- [kubeblocks-e2e-workflow](kubeblocks-e2e-workflow/SKILL.md) — maintain the large engine matrix in `kubeblocks-e2e-test.yml`
- [cloud-deploy](../cloud-deploy/SKILL.md) — terraform cluster lifecycle
- [utils-common](../utils-common/SKILL.md) — full `utils.sh` usage
