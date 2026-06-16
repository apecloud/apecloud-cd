---
name: chart-release
description: >
  Helm chart release workflow: helm package, chart-releaser cr, gh-pages index update,
  Jihulab chart upload, update_chart_values.sh, update_chart_annotations.sh, bump chart version.
  Use when packaging charts, publishing to helm-charts release, fixing chart index failures,
  or injecting release metadata into values.yaml and Chart.yaml.
---

# Chart Release

This skill covers everything related to **Helm chart releases** in apecloud-cd.

## Related Files

### Workflows

| Workflow | Purpose |
|---|---|
| [`.github/workflows/release-charts.yml`](../../.github/workflows/release-charts.yml) | Main workflow: dependency update, image check, package, GitHub release upload, Jihulab sync |
| [`.github/workflows/release-charts-check.yml`](../../.github/workflows/release-charts-check.yml) | Pre-release chart checks |
| [`.github/workflows/release-charts-enterprise.yml`](../../.github/workflows/release-charts-enterprise.yml) | Enterprise chart release |
| [`.github/workflows/release-charts-jihu.yml`](../../.github/workflows/release-charts-jihu.yml) | Release charts to Jihulab |
| [`.github/workflows/release-charts-jihu-enterprise.yml`](../../.github/workflows/release-charts-jihu-enterprise.yml) | Enterprise Jihulab release |
| [`.github/workflows/upload-chart.yml`](../../.github/workflows/upload-chart.yml) | Upload a single chart |

### Utils

| Script | Purpose |
|---|---|
| [`.github/utils/helm_release.sh`](../../.github/utils/helm_release.sh) | Full chart release: delete old packages, helm package, cr upload, index update |
| [`.github/utils/helm_package.sh`](../../.github/utils/helm_package.sh) | Package one or more charts, supports helm or chart-releaser |
| [`.github/utils/helm_release_update_index.sh`](../../.github/utils/helm_release_update_index.sh) | Update gh-pages index with cr and sync to Jihulab |
| [`.github/utils/update_chart_values.sh`](../../.github/utils/update_chart_values.sh) | Inject releaseTime/releaseBranch/commitId/commitTime into values.yaml |
| [`.github/utils/update_chart_annotations.sh`](../../.github/utils/update_chart_annotations.sh) | Inject commit-id/commit-time/release-time/release-branch into Chart.yaml |
| [`.github/utils/update_chart_notes.sh`](../../.github/utils/update_chart_notes.sh) | Update Chart notes |

## Call Chain

```
release-charts.yml
   ├── helm_package.sh / cr
   ├── helm_image_check.sh
   ├── helm_release.sh
   └── helm_release_update_index.sh

Pre-release preparation:
   update_chart_values.sh
   update_chart_annotations.sh
```

## Common Tasks

### 1. Add a new chart to the release flow

1. Place the chart directory in the correct location (commonly `deploy/` or addons-related directories).
2. Confirm `CHART_DIR` and `CHART_NAME` in the `release-charts.yml` call.
3. If there are dependency repos, configure them in the `DEP_REPO` input.
4. To skip certain image checks, use `SKIP_CHECK_IMAGES` or disable `CHECK_ENABLE`.

### 2. Change chart release version rules

- `release-charts.yml` strips the `v` prefix by default (`REMOVE_PREFIX: true`).
- `helm_release.sh` uses `CR_TOKEN` to call the GitHub API.
- If you need to keep the `v` prefix, update both the workflow and the script consistently.

### 3. Fix chart index update failures

- Check whether `helm_release_update_index.sh` has a conflict pulling the `gh-pages` branch.
- The script retries up to 5 times comparing remote/local commits.
- If the index is not synced to Jihulab, verify `CHART_ACCESS_TOKEN` / `CHART_ACCESS_USER` / `CHART_PROJECT_ID`.

### 4. Inject release metadata

```bash
# values.yaml
./.github/utils/update_chart_values.sh \
    -cd addons \
    -bv chart-values/release-values.yaml \
    -rn release-1.6

# Chart.yaml annotations
./.github/utils/update_chart_annotations.sh \
    -cd addons \
    -bc chart-values/release-annotations.yaml \
    -rn release-1.6
```

## Common Commands

```bash
# Full local chart release
./.github/utils/helm_release.sh \
    -v v1.6.1 \
    -o apecloud \
    -r helm-charts \
    -gr apecloud/helm-charts

# Local packaging
./.github/utils/helm_package.sh \
    -d deploy \
    -rv 0.4.0 \
    -av 0.4.0
```

## Environment Variables

| Variable | Purpose |
|---|---|
| `CR_TOKEN` | GitHub API token for chart-releaser |
| `CHART_ACCESS_TOKEN` / `CHART_ACCESS_USER` / `CHART_PROJECT_ID` | Jihulab chart upload |

## Related Skills

- [image-management](../image-management/SKILL.md) — image checks before chart release
- [manifests](../manifests/SKILL.md) — manifest-driven addon chart upgrades
- [release-operations](../release-operations/SKILL.md) — GitHub release create/delete
