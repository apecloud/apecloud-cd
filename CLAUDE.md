# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository is the **ApeCloud CD** tooling repository - it manages CI/CD workflows, deployment scripts, and utility tools for the ApeCloud Kubernetes platform. The project is focused on maintaining the `.github` directory only, which contains all the active development code.

## Directory Structure

```
.github/
├── workflows/                  # CI/CD workflows for deployments, releases, and testing
└── utils/                      # Shared utility scripts for chart and deployment management
```

## Key Utilities in `utils/`

The `utils` directory contains 47 different utility scripts for managing the deployment and release process. Call scripts with `./.github/utils/<script.sh>` or `./.github/utils/utils.sh --type <number>`.

### Main Utility Categories

| Type | Purpose | Key Scripts |
|------|---------|-------------|
| **Chart Release** | Package, release, and index charts | `helm_release.sh`, `helm_package.sh`, `helm_release_update_index.sh` |
| **Image Management** | Check and push images | `helm_image_check.sh`, `manifests_images_push.sh`, `push_images.sh` |
| **Version Control** | Update versions and release metadata | `manifests_version_update.sh`, `update_chart_values.sh`, `update_chart_annotations.sh` |
| **Cloud Deployment** | Deploy to cloud environments | `cloud_e2e_installer.sh` |
| **Testing** | Run e2e tests | `kbcli-test-pre.sh` |
| **Manifests** | Manage addon charts from manifests | `manifests_charts_addon_upgrade.sh`, `manifests_charts_image_check.sh`, `manifests_charts_save.sh` |
| **Registry Sync** | Sync images between registries | `skopeo_copy_to_docker.sh`, `skopeo_sync_to_aliyun.sh` |
| **Git Operations** | Release handling and reporting | `release_gitlab.sh`, `renew-issue.yml`, `update-release-notes.yml` |
| **Cleanup** | Delete releases, runners, caches | Various scripts in utils |

## Common Commands

### Chart Release Process

The `helm_release.sh` script handles the complete chart release workflow:
```bash
# Package and release charts to GitHub releases
./.github/utils/helm_release.sh \
    -v v1.6.1 \
    -o apecloud \
    -r helm-charts \
    -gr apecloud/helm-charts
```

### Update Chart Metadata

Update chart values and annotations with release information:
```bash
# Update values.yaml files with commit info
./.github/utils/update_chart_values.sh \
    -cd addons|addons-cluster \
    -bv chart-values/release-values.yaml \
    -rn <branch-name>

# Update Chart.yaml annotations
./.github/utils/update_chart_annotations.sh \
    -cd addons|addons-cluster \
    -bc chart-values/release-annotations.yaml \
    -rn <branch-name>
```

### Image Validation

Check that Helm charts use valid images with correct architecture support:
```bash
# Check images in packaged charts
./.github/utils/helm_image_check.sh .cr-release-packages "kubeblocks|kblib-loadbalancer"

# Check images in manifests
./.github/utils/manifests_charts_image_check.sh <manifests-file> "true"

# Check and upgrade addon charts in cluster
./.github/utils/manifests_charts_addon_upgrade.sh
```

### Cloud Deployment

The `deploy-cloud.yml` workflow handles multi-cluster deployments:
```bash
# Trigger deployment workflow
# Uses workflow_call pattern with inputs for cloud_env_name, cloud_org_name, version, etc.
```

### Utility Script

The `utils.sh` script provides 47 different operations for versioning, image management, release handling, and test result parsing. Call it with `--type <number>`:
```bash
./.github/utils/utils.sh --type 28 --version <version> --branch-name <branch>
```

### Manifest Image Upgrade

Check and upgrade charts from a manifests file:
```bash
# Add chart repos and upgrade addons
./.github/utils/manifests_charts_addon_upgrade.sh
```

## Key Scripts and Their Purpose

| Script | Purpose |
|--------|---------|
| `helm_release.sh` | Chart packaging, GitHub release, and index updates |
| `helm_package.sh` | Package Helm charts |
| `helm_release_update_index.sh` | Update Helm chart index |
| `update_chart_values.sh` | Inject release metadata (releaseTime, releaseBranch, commitId, commitTime) into values.yaml |
| `update_chart_annotations.sh` | Add release annotations (commit-id, commit-time, release-time, release-branch) to Chart.yaml |
| `helm_image_check.sh` | Validate chart images exist and have amd64/arm64 architecture |
| `manifests_charts_image_check.sh` | Check images referenced in helm manifests files |
| `manifests_charts_addon_upgrade.sh` | Add chart repos and upgrade deployed addons in cluster |
| `manifests_charts_save.sh` | Save manifests and charts |
| `manifests_images_push.sh` | Push images referenced in manifests |
| `manifests_version_update.sh` | Update chart versions from a manifests file |
| `cloud_e2e_installer.sh` | Install cloud E2E environments |
| `push_images.sh` / `push_images_docker.sh` / `push_images_sealos.sh` | Push images to various registries |
| `skopeo_copy_to_docker.sh` / `skopeo_copy_to_docker_new_tag.sh` | Copy images using skopeo |
| `skopeo_sync_to_aliyun.sh` / `skopeo_sync_to_aliyun_new.sh` | Sync images to Aliyun registry |
| `manifests_charts_image_check.sh` | Check images in helm manifests files |
| `release_gitlab.sh` | Release handling in GitLab |

## Notable Utility Script Operations (Type Numbers)

| Type | Operation |
|------|-----------|
| 1 | Remove v prefix from version |
| 2 | Replace '-' with '.' in version |
| 3 | Get release asset upload URL |
| 4 | Get latest release tag |
| 10 | Delete Docker images |
| 11 | Delete Aliyun images |
| 13 | Helm dep update |
| 14 | Get delete alpha/beta release |
| 15 | Comment issue |
| 18 | Delete Aliyun images new |
| 19 | Delete helm-charts index |
| 20 | Get incremental chart package |
| 21 | Set PR size label |
| 22 | Set PR milestone |
| 23 | Set issue milestone |
| 25 | Delete runner |
| 27 | Generate image yaml |
| 28 | Get release branch |
| 30 | Delete actions cache |
| 31 | Check release version |
| 35 | Bump chart version |
| 44 | Get GitHub Actions job URL |

## Key Workflows in `.github/workflows/`

| Workflow | Purpose |
|----------|---------|
| `deploy-cloud.yml` | Multi-cluster cloud deployment orchestration |
| `release-branch.yml` | Get appropriate release branch for a version |
| `cloud-cluster-clear.yml` | Clean up cloud cluster environments (idc/idc1/idc2/idc4) |
| `release-image-cache.yml` / `release-image-cache2.yml` | Image caching for releases |
| `release-image-sync*.yml` | Sync images between registries |
| `manifests-charts-image-check.yml` | CI check for chart images |
| `cloud-e2e-engine.yml` / `cloud-e2e-schedule-dev.yml` | E2E testing orchestration |
| `release-image-manifest.yml` / `release-image-check.yml` | Image manifest generation and validation |
| `trivy-scan-repo.yml` / `trivy-scan-daily.yml` | Security scanning |

## Dependencies

- **chart-releaser**: Chart release tool (`cr` command) - typically version v1.6.1
- **Helm**: For chart templating and management
- **yq**: For YAML parsing in manifest processing scripts
- **docker/buildx**: For image validation
- **skopeo**: For image copying and syncing between registries

## Notable Patterns

- **sed on macOS vs Linux**: Scripts detect OS (`uname -s`) and use `-i ''` (macOS) or `-i` (Linux) for in-place edits
- **Branch ref sanitization**: Forward slashes in branch names are escaped with backslashes for sed
- **Multi-registry support**: Handles docker.io, apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com, infracreate-registry.cn-zhangjiakou.cr.aliyuncs.com
- **Error handling**: Scripts use `set -o errexit`, `set -o nounset`, `set -o pipefail`
- **Sleep loops**: Image checks use 1-second sleep loops with retry counts (5-10 retries)

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `CR_TOKEN` | GitHub token for chart releases |
| `GH_TOKEN` | GitHub personal access token |
| `PERSONAL_ACCESS_TOKEN` | GitHub PAT |
| `CHART_ACCESS_TOKEN` | Jihulab chart access token |
| `CHART_ACCESS_USER` | Jihulab chart access user |
| `CHART_PROJECT_ID` | Jihulab chart project ID |
| `IDC_KUBECONFIG` | Kubernetes config for IDC clusters |
| `JIHULAB_ACCESS_TOKEN` | Jihulab access token |
| `JIHULAB_ACCESS_USER` | Jihulab access user |

## Dependencies

- **chart-releaser**: Chart release tool (`cr` command) - typically version v1.6.1
- **Helm**: For chart templating and management
- **yq**: For YAML parsing in manifest processing scripts
- **docker/buildx**: For image validation

## Notable Patterns

- **sed on macOS vs Linux**: Scripts detect OS (`uname -s`) and use `-i ''` (macOS) or `-i` (Linux) for in-place edits
- **Branch ref sanitization**: Forward slashes in branch names are escaped with backslashes for sed
- **Multi-registry support**: Handles docker.io, apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com, infracreate-registry.cn-zhangjiakou.cr.aliyuncs.com
