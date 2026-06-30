---
name: registry-sync
description: >
  Cross-registry image mirroring and copy: skopeo sync, skopeo copy, docker.io,
  apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com, infracreate-registry.cn-zhangjiakou.cr.aliyuncs.com,
  ECR, set_registry_and_repo.sh. Use when syncing images to Aliyun, copying images between registries,
  retagging images, or preparing offline image packages.
---

# Registry Sync

This skill covers **image synchronization between registries**: docker.io ↔ Aliyun (legacy and new domains), single-image copy, and bulk sync.

## Related Files

### Workflows

| Workflow | Purpose |
|---|---|
| [`.github/workflows/skopeo-sync-images-docker.yml`](../../.github/workflows/skopeo-sync-images-docker.yml) | Bulk sync images to docker.io |
| [`.github/workflows/skopeo-sync-images-aliyun.yml`](../../.github/workflows/skopeo-sync-images-aliyun.yml) | Bulk sync images to legacy Aliyun |
| [`.github/workflows/skopeo-sync-images-aliyun-and-docker.yml`](../../.github/workflows/skopeo-sync-images-aliyun-and-docker.yml) | Sync to both Aliyun and docker.io |
| [`.github/workflows/skopeo-sync-images-aliyun-to-aliyun.yml`](../../.github/workflows/skopeo-sync-images-aliyun-to-aliyun.yml) | Sync between Aliyun domains |
| [`.github/workflows/skopeo-copy-image-docker-new-tag.yml`](../../.github/workflows/skopeo-copy-image-docker-new-tag.yml) | Copy image to docker.io with a new tag |
| [`.github/workflows/release-image-sync.yml`](../../.github/workflows/release-image-sync.yml) | Image sync during release |
| [`.github/workflows/release-image-sync2.yml`](../../.github/workflows/release-image-sync2.yml) | Another image sync entry point |
| [`.github/workflows/release-image-sync-self-hosted.yml`](../../.github/workflows/release-image-sync-self-hosted.yml) | Sync on self-hosted runners |
| [`.github/workflows/release-image-arm-sync.yml`](../../.github/archive/20260630/workflows/release-image-arm-sync.yml) | arm64 image sync |

### Utils

| Script | Purpose |
|---|---|
| [`.github/utils/skopeo_copy_to_docker.sh`](../../.github/utils/skopeo_copy_to_docker.sh) | Copy a single image to docker.io/apecloud, supports ECR/Aliyun source |
| [`.github/utils/skopeo_copy_to_docker_new_tag.sh`](../../.github/utils/skopeo_copy_to_docker_new_tag.sh) | Copy to docker.io with a replaced tag |
| [`.github/utils/skopeo_copy_to_aliyun.sh`](../../.github/utils/skopeo_copy_to_aliyun.sh) | Copy a single image to legacy Aliyun |
| [`.github/utils/skopeo_copy_to_aliyun_new.sh`](../../.github/utils/skopeo_copy_to_aliyun_new.sh) | Copy a single image to new Aliyun |
| [`.github/utils/skopeo_sync_to_docker.sh`](../../.github/utils/skopeo_sync_to_docker.sh) | Bulk sync to docker.io |
| [`.github/utils/skopeo_sync_to_aliyun.sh`](../../.github/utils/skopeo_sync_to_aliyun.sh) | Bulk sync to legacy Aliyun |
| [`.github/utils/skopeo_sync_to_aliyun_new.sh`](../../.github/utils/skopeo_sync_to_aliyun_new.sh) | Bulk sync to new Aliyun |
| [`.github/utils/skopeo_sync_aliyun_to_aliyun_new.sh`](../../.github/utils/skopeo_sync_aliyun_to_aliyun_new.sh) | Sync legacy Aliyun to new Aliyun |
| [`.github/utils/copy_image.sh`](../../.github/utils/copy_image.sh) | Generic single-image copy entry point |
| [`.github/utils/set_registry_and_repo.sh`](../../.github/utils/set_registry_and_repo.sh) | Batch-set registry/repository in chart values |

## Registry Conventions

| Registry | Script/variable keyword |
|---|---|
| docker.io | `DOCKER_REGISTRY_URL`, `docker.io` |
| Legacy Aliyun | `apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com`, `aliyun` |
| New Aliyun | `infracreate-registry.cn-zhangjiakou.cr.aliyuncs.com`, `aliyun-new` |
| ECR | AWS temporary credentials, `ECR_USER=AWS` in scripts |

## Call Chain

```
skopeo-sync-images-*.yml
   └── skopeo_sync_to_*.sh <user> <pass> <image-list-file> [registry]

release-image-sync.yml
   └── manifests_images_push.sh / skopeo_copy_to_*.sh
```

## Common Tasks

### 1. Bulk sync images to Aliyun

1. Prepare an image list file with one full image name per line (without registry prefix).
2. Trigger the workflow or run locally:
   ```bash
   ./.github/utils/skopeo_sync_to_aliyun.sh \
       $DOCKER_USER $DOCKER_PASSWORD \
       $ALIYUN_USER $ALIYUN_PASSWORD \
       images-list.txt docker.io
   ```

### 2. Migrate legacy Aliyun to new Aliyun

```bash
./.github/utils/skopeo_sync_aliyun_to_aliyun_new.sh \
    $ALIYUN_USER $ALIYUN_PASSWORD \
    $ALIYUN_USER_NEW $ALIYUN_PASSWORD_NEW \
    images-list.txt
```

### 3. Copy a single image with a new tag

```bash
./.github/utils/skopeo_copy_to_docker_new_tag.sh \
    $DOCKER_USER $DOCKER_PASSWORD \
    old-image:tag new-image:tag
```

### 4. Change chart default registry

```bash
./.github/utils/set_registry_and_repo.sh docker.io addons
```

This sets `registry:` to `docker.io` in `addons/*/values.yaml` and normalizes `repository:` under `apecloud/`.

## Notes

- All skopeo scripts retry (usually 10 times, sleep 1 second).
- ECR copies automatically use `ECR_USER=AWS` + temporary password.
- Image list file format matters; keep one full image path per line.

## Related Skills

- [image-management](../image-management/SKILL.md) — image build, check, manifest
- [manifests](../manifests/SKILL.md) — bulk image handling driven by manifests
