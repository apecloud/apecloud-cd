---
name: cloud-deploy
description: >
  ApeCloud / KubeBlocks Cloud multi-cluster deployment and cleanup: deploy-cloud.yml,
  cloud-cluster-clear.yml, IDC cleanup, terraform-init.yml, terraform-destroy.yml.
  Use when deploying to cloud environments, cleaning up IDC/IDC1/IDC2/IDC4 clusters,
  or debugging deployment failures.
---

# Cloud Deploy

This skill covers **cloud environment deployment and cleanup**: multi-cluster deployment, IDC/IDC1/IDC2/IDC4 environment cleanup, and terraform cluster create/destroy.

## Related Files

### Workflows

| Workflow | Purpose |
|---|---|
| [`.github/workflows/deploy-cloud.yml`](../../.github/workflows/deploy-cloud.yml) | Main cloud multi-cluster deployment workflow |
| [`.github/workflows/deploy-cloud-2.yml`](../../.github/workflows/deploy-cloud-2.yml) | Second cloud deployment entry point |
| [`.github/workflows/cloud-cluster-clear.yml`](../../.github/workflows/cloud-cluster-clear.yml) | Clean up IDC/IDC1/IDC2/IDC4 environments |
| [`.github/workflows/terraform-init.yml`](../../.github/workflows/terraform-init.yml) | Create cloud K8s cluster (also in e2e-testing) |
| [`.github/workflows/terraform-destroy.yml`](../../.github/workflows/terraform-destroy.yml) | Destroy cloud K8s cluster (also in e2e-testing) |

### Utils

| Script | Purpose |
|---|---|
| [`.github/utils/cloud_e2e_installer.sh`](../../.github/utils/cloud_e2e_installer.sh) | Install cloud E2E environment |

## deploy-cloud.yml Key Inputs

- `cloud_env_name`: target environment name.
- `cloud_org_name`: target organization.
- `version`: deployment version.
- Other inputs control image, cluster, skip flags, etc.

## cloud-cluster-clear.yml

Supports cleanup of the following environments:

- `idc`
- `idc1`
- `idc2`
- `idc4`

When modifying, pay attention to selectors and `if` conditions to avoid accidentally cleaning non-target clusters.

## Call Chain

```
deploy-cloud.yml
   └── multi-cluster Helm / kubectl apply

cloud-cluster-clear.yml
   └── cleanup scripts / kubectl delete
```

## Common Tasks

### 1. Add a new deployment target cluster

1. Add the target environment as an input or matrix entry in `deploy-cloud.yml`.
2. Make sure the corresponding KUBECONFIG secret is configured.
3. After deployment, verify pod/helm release status.

### 2. Change environment cleanup scope

`cloud-cluster-clear.yml` selects cleanup targets via `cloud_env_name`. Recommendations:

- Do not default to cleaning production environments.
- Add `if` guards so deletion only runs with explicit input.

### 3. Debug deployment failures

- Verify `IDC_KUBECONFIG` is correct.
- Check that the target cluster's helm repo and chart version exist.
- Review step outputs in `deploy-cloud.yml` logs.

## Related Skills

- [e2e-testing](../e2e-testing/SKILL.md) — terraform cluster create/destroy
- [release-operations](../release-operations/SKILL.md) — version releases and rollbacks
