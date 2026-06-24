---
name: image-management
description: >
  Container image build, check, push, and manifest management: release-image.yml, buildx,
  multi-arch amd64 arm64 manifest, helm_image_check.sh, manifests_image_check.sh, skopeo sync,
  image cache, push_images.sh. Use when image release fails, a new engine image is added,
  manifest image check fails, or amd64/arm64 platform support is missing.
---

# Image Management

This skill covers the **full image lifecycle** for KubeBlocks and related components: checking, building, pushing, and manifest generation.

## Related Files

### Workflows

| Workflow | Purpose |
|---|---|
| [`.github/workflows/release-image.yml`](../../.github/workflows/release-image.yml) | Main image build/push workflow, supports buildx, multi-platform, submodules |
| [`.github/workflows/release-image-check.yml`](../../.github/workflows/release-image-check.yml) | Image build check (qemu, buildx, docker build) |
| [`.github/workflows/release-image-manifest.yml`](../../.github/workflows/release-image-manifest.yml) | Generate and push multi-arch manifests to docker.io and Aliyun |
| [`.github/workflows/manifests-image-check.yml`](../../.github/workflows/manifests-image-check.yml) | Check images listed in a manifests file |
| [`.github/workflows/manifests-charts-image-check.yml`](../../.github/workflows/manifests-charts-image-check.yml) | Check chart images referenced in helm manifests |
| [`.github/workflows/release-image-cache.yml`](../../.github/workflows/release-image-cache.yml) | Build and cache image (first variant) |
| [`.github/workflows/release-image-cache2.yml`](../../.github/workflows/release-image-cache2.yml) | Build and cache image (second variant) |
| [`.github/workflows/release-image-cache-sync.yml`](../../.github/workflows/release-image-cache-sync.yml) | Build image cache and sync to Aliyun |
| [`.github/workflows/release-image-no-cache.yml`](../../.github/workflows/release-image-no-cache.yml) | Build/push image without cache |
| [`.github/workflows/release-image-self-hosted.yml`](../../.github/workflows/release-image-self-hosted.yml) | Build/push image on self-hosted runner |

### Utils

| Script | Purpose |
|---|---|
| [`.github/utils/helm_image_check.sh`](../../.github/utils/helm_image_check.sh) | Scan packaged `.tgz` charts and verify image existence and amd64/arm64 architecture |
| [`.github/utils/manifests_charts_image_check.sh`](../../.github/utils/manifests_charts_image_check.sh) | Parse helm manifests and check chart images per serviceVersion |
| [`.github/utils/manifests_image_check.sh`](../../.github/utils/manifests_image_check.sh) | Check whether images in a manifests file can be pulled from the registry |
| [`.github/utils/manifests_images_push.sh`](../../.github/utils/manifests_images_push.sh) | Sync images in manifests to a target registry via skopeo |
| [`.github/utils/manifests_images_save.sh`](../../.github/utils/manifests_images_save.sh) | Pull and save images from manifests as tar archives |
| [`.github/utils/push_images.sh`](../../.github/utils/push_images.sh) | Generic image push (auto-detects docker/sealos) |
| [`.github/utils/push_images_docker.sh`](../../.github/utils/push_images_docker.sh) | docker load + tag + push for local image files |
| [`.github/utils/push_images_sealos.sh`](../../.github/utils/push_images_sealos.sh) | Push images using sealos |
| [`.github/utils/get_scan_images.sh`](../../.github/utils/get_scan_images.sh) | Collect image lists for trivy scanning |
| [`.github/utils/images-list.txt`](../../.github/utils/images-list.txt) | Example image list used by skopeo sync scripts |

## Call Chain

```
release-image.yml
   └── make push-image / docker buildx

release-image-manifest.yml
   └── docker manifest push (docker.io & aliyun)

manifests-charts-image-check.yml
   └── manifests_charts_image_check.sh <manifests-file> true

helm release image check:
   release-charts.yml ──> helm_image_check.sh .cr-release-packages "kubeblocks|kblib-loadbalancer"
```

## Image Registry Conventions

| Registry | Purpose |
|---|---|
| `docker.io/apecloud/...` | Default public registry |
| `apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/...` | Legacy Aliyun registry |
| `infracreate-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/...` | New Aliyun registry |

## Common Tasks

### 1. Add a new engine image and verify it

1. Declare the image in manifests or chart values.
2. Run the image check script:
   ```bash
   ./.github/utils/manifests_charts_image_check.sh deploy-manifests.yaml true
   ```
3. If the image is missing, build/push it via `release-image.yml` or push it manually.
4. Re-run the check until it passes.

### 2. Fix helm chart image check failures

```bash
./.github/utils/helm_image_check.sh .cr-release-packages "kubeblocks|kblib-loadbalancer"
```

- Common failures: image not pushed, missing arm64 layer, wrong tag.
- The script supports `SKIP_CHECK_IMAGES` to exclude known-not-ready images.

### 3. Push manifest images

```bash
./.github/utils/manifests_images_push.sh \
    deploy-manifests.yaml \
    deploy-values.yaml \
    docker.io \
    $DOCKER_USER \
    $DOCKER_PASSWORD
```

### 4. Generate multi-arch manifests

`release-image-manifest.yml` generates `linux/amd64,linux/arm64` manifests and pushes them to docker.io and both Aliyun registries. When modifying:

- `REMOVE_PREFIX`: whether to strip the leading `v` from the version.
- `IMG` and `VERSION`: full image name and tag for manifest generation.

### 5. Pass BuildKit secrets to cached image builds

`release-image-cache2.yml` supports optional BuildKit secret inputs:

- `BUILDX_SECRETS`: values passed to `docker/build-push-action` `secrets`
- `BUILDX_SECRET_ID`: BuildKit secret id for the optional named workflow secret
- `BUILDX_SECRET_NAME`: GitHub Actions secret name to pass as the BuildKit secret
- `BUILDX_SECRET_FILES`: file mappings passed to `secret-files`

Use `secrets: inherit`, then set both the BuildKit secret id and the inherited GitHub Actions
secret name:

```yaml
with:
  BUILDX_SECRET_ID: addon_runtime_seed
  BUILDX_SECRET_NAME: ADDON_RUNTIME_KEY_SEED
secrets: inherit
```

## Common Commands

```bash
# Check images after packaging charts
./.github/utils/helm_image_check.sh .cr-release-packages "kubeblocks|kblib-loadbalancer"

# Check images in a manifests file
./.github/utils/manifests_image_check.sh deploy-manifests.yaml

# Check helm manifest chart images
./.github/utils/manifests_charts_image_check.sh deploy-manifests.yaml true
```


## Troubleshooting

### `helm_image_check.sh` reports "image not found"
1. Verify the tag exists: `docker manifest inspect <image>`.
2. If only one architecture exists, check `BUILDX_PLATFORMS` in the matching `release-image*.yml`.
3. As a temporary bypass while the image is being published, add the image to `SKIP_CHECK_IMAGES`.

### `manifests_image_check.sh` / `manifests_charts_image_check.sh` fails
- Ensure the manifests file path is correct and the registry is reachable.
- For chart checks, confirm the helm repo has the requested chart version (`helm search repo`).
- Check `deploy-values.yaml` for `enable: false`; disabled addons are skipped.

### Multi-arch manifest push fails
- `release-image-manifest.yml` pushes to docker.io and both Aliyun registries. If one registry fails,
  check the corresponding secrets (`DOCKER_REGISTRY_*`, `ALIYUN_REGISTRY_*`, `ALIYUN_*_NEW`).
- Verify `REMOVE_PREFIX` matches the expected tag format.

### Image cache workflow not producing cache
- `release-image-cache*.yml` uses buildx cache exporters. Confirm `BUILDX_ARGS` includes the correct
  cache-to/cache-from flags if the caller overrides defaults.

## Related Skills

- [chart-release](../chart-release/SKILL.md) — image checks before chart release
- [registry-sync](../registry-sync/SKILL.md) — sync existing images across registries
- [manifests](../manifests/SKILL.md) — manifest-driven addon upgrades
- [security-scan](../security-scan/SKILL.md) — image vulnerability scanning
