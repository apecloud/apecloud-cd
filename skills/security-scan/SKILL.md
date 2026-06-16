---
name: security-scan
description: >
  Trivy security scanning: trivy-scan.yml, trivy-scan-cloud.yml, container image vulnerability,
  CVE check, get_scan_images.sh, kubeblocks-addons. Use when vulnerability scans fail,
  scan scope needs adjustment, or image/addon scan reports need formatting changes.
---

# Security Scan

This skill covers **Trivy image/repository security scanning**: triggering, execution, and report aggregation.

## Related Files

### Workflows

| Workflow | Purpose |
|---|---|
| [`.github/workflows/trivy-scan.yml`](../../.github/workflows/trivy-scan.yml) | Main Trivy scanning workflow |
| [`.github/workflows/trivy-scan-cloud.yml`](../../.github/workflows/trivy-scan-cloud.yml) | Scan cloud-related images |
| [`.github/workflows/trivy-scan-daily.yml`](../../.github/workflows/trivy-scan-daily.yml) | Daily scan |
| [`.github/workflows/trivy-scan-repo.yml`](../../.github/workflows/trivy-scan-repo.yml) | Scan repository code |
| [`.github/workflows/trivy-scan-weekly.yml`](../../.github/workflows/trivy-scan-weekly.yml) | Weekly scan |

### Utils

| Script | Purpose |
|---|---|
| [`.github/utils/get_scan_images.sh`](../../.github/utils/get_scan_images.sh) | Collect images to scan |

## trivy-scan.yml Key Inputs

- `ITEM`: scan target name.
- `IMAGES`: directly specify image list.
- `ADDON`: whether to scan KubeBlocks addons.
- `KBADDON_REF`: kubeblocks-addons branch.
- `LOGIN_DOCKER`: whether to log in to Docker Hub.

## Common Tasks

### 1. Add an image to scan

- If the image is already declared in manifests or charts, `get_scan_images.sh` usually discovers it automatically.
- For one-off scans, pass it in the `IMAGES` input.

### 2. Exclude a false positive

Maintain an exclude list in the workflow or script (e.g. CVE IDs or image names). When modifying:

- Clearly comment the reason for exclusion.
- Keep an audit trail; avoid silent waivers without explanation.

### 3. Scan Addons

When `ADDON: true`, the workflow clones `kubeblocks-addons` and scans images declared there. Update `KBADDON_REF` if the branch or addon source changes.

### 4. Output total-vulnerabilities

`trivy-scan.yml` outputs `total-vulnerabilities`, which upstream workflows can use as a gate. If you change this output key, update callers accordingly.

## Related Skills

- [image-management](../image-management/SKILL.md) — image lists and manifests
- [manifests](../manifests/SKILL.md) — addon image sources
