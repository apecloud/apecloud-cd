---
name: manifests
description: >
  Helm manifests-driven addon operations: deploy-manifests.yaml, deploy-values.yaml,
  manifests_charts_addon_upgrade.sh, manifests_charts_save.sh, manifests_version_update.sh,
  addons_version_check.sh. Use when upgrading addons from manifests, saving offline packages,
  aligning chart versions, or checking addon versions.
---

# Manifests

This skill covers **manifests files** throughout the release flow: parsing, upgrading, saving, and version alignment.

## Related Files

### Workflows

| Workflow | Purpose |
|---|---|
| [`.github/workflows/manifests-charts-save.yml`](../../.github/workflows/manifests-charts-save.yml) | Save charts and images according to manifests |
| [`.github/workflows/manifests-charts-image-check.yml`](../../.github/workflows/manifests-charts-image-check.yml) | Check images required by charts in manifests |
| [`.github/workflows/check-addon-version.yml`](../../.github/workflows/check-addon-version.yml) | Compare addon versions across kubeblocks-addons and apecloud-addons |
| [`.github/workflows/check-addon-version-weekly.yml`](../../.github/workflows/check-addon-version-weekly.yml) | Weekly scheduled addon version checks |

### Utils

| Script | Purpose |
|---|---|
| [`.github/utils/manifests_charts_addon_upgrade.sh`](../../.github/utils/manifests_charts_addon_upgrade.sh) | Add chart repos and helm upgrade deployed addon charts in cluster |
| [`.github/utils/manifests_charts_save.sh`](../../.github/utils/manifests_charts_save.sh) | Pull charts and images from manifests and save them |
| [`.github/utils/manifests_version_update.sh`](../../.github/utils/manifests_version_update.sh) | Update chart versions from manifests |
| [`.github/utils/manifests_charts_image_check.sh`](../../.github/utils/manifests_charts_image_check.sh) | Check chart images in manifests (also in image-management) |
| [`.github/utils/manifests_images_push.sh`](../../.github/utils/manifests_images_push.sh) | Push images from manifests (also in image-management) |
| [`.github/utils/manifests_images_save.sh`](../../.github/utils/manifests_images_save.sh) | Save images from manifests (also in image-management) |
| [`.github/utils/addons_version_check.sh`](../../.github/utils/addons_version_check.sh) | Addon version check |

## Manifests File Conventions

The manifests flow is typically driven by two files:

- `deploy-manifests.yaml` — defines addon chart versions and corresponding images
- `deploy-values.yaml` — toggles addon enablement (`enable: true/false`)

## Call Chain

```
Release preparation
   ├── manifests_version_update.sh   # update chart versions
   ├── manifests_charts_save.sh      # save charts & images
   ├── manifests_images_save.sh      # save image tars
   └── manifests_charts_image_check.sh  # image existence/architecture check

Cluster upgrade
   └── manifests_charts_addon_upgrade.sh
```

## Common Tasks

### 1. Add a new addon to manifests

1. Add the addon entry to `deploy-manifests.yaml`, specifying chart version and images.
2. If needed, set `enable: true` in `deploy-values.yaml`.
3. Run the check script:
   ```bash
   ./.github/utils/manifests_charts_image_check.sh deploy-manifests.yaml true
   ```
4. After it passes, save charts/images or trigger the release.

### 2. Fix addon upgrade failures

```bash
./.github/utils/manifests_charts_addon_upgrade.sh
```

- The script automatically adds/updates `kubeblocks` and `kubeblocks-enterprise` helm repos.
- Common failures: repo authentication failure, chart version missing, existing release conflict.

### 3. Update chart versions

```bash
./.github/utils/manifests_version_update.sh <args>
```

This reads version info from manifests and batch-updates version numbers in chart directories. Before changing, confirm the mapping between manifests and chart directories.

### 4. Save offline packages

```bash
./.github/utils/manifests_charts_save.sh <manifests-file> <values-file> <version>
```

## Related Skills

- [image-management](../image-management/SKILL.md) — image check and push for manifests
- [chart-release](../chart-release/SKILL.md) — chart version release
- [registry-sync](../registry-sync/SKILL.md) — cross-registry image sync