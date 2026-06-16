---
name: release-operations
description: >
  GitHub release lifecycle: release create/delete, release notes, release branch selection,
  version check, trigger workflow, publish kbcli to Chocolatey/Scoop/WinGet, utils.sh type 8/10/11.
  Use when a release pipeline fails, rolling back a release, publishing kbcli packages,
  or validating release versions.
---

# Release Operations

This skill covers **release lifecycle and metadata management**: create, delete, notes, version checks, and branch selection.

## Related Files

### Workflows

| Workflow | Purpose |
|---|---|
| [`.github/workflows/release-create.yml`](../../.github/workflows/release-create.yml) | Create GitHub release (pre/RC/stable) |
| [`.github/workflows/release-delete.yml`](../../.github/workflows/release-delete.yml) | Delete GitHub release, charts, images |
| [`.github/workflows/release-delete-cloud.yml`](../../.github/workflows/release-delete-cloud.yml) | Delete cloud release |
| [`.github/workflows/release-delete-schedule.yml`](../../.github/workflows/release-delete-schedule.yml) | Scheduled release deletion |
| [`.github/workflows/release-notes.yml`](../../.github/workflows/release-notes.yml) | Generate release notes |
| [`.github/workflows/update-release-notes.yml`](../../.github/workflows/update-release-notes.yml) | Update release notes |
| [`.github/workflows/release-version.yml`](../../.github/workflows/release-version.yml) | Release version handling |
| [`.github/workflows/check-release-version.yml`](../../.github/workflows/check-release-version.yml) | Check release version number |
| [`.github/workflows/release-branch.yml`](../../.github/workflows/release-branch.yml) | Get release branch for a version |
| [`.github/workflows/get-version.yml`](../../.github/workflows/get-version.yml) | Get version number |
| [`.github/workflows/trigger-release.yml`](../../.github/workflows/trigger-release.yml) | Trigger release workflow |
| [`.github/workflows/publish-kbcli-choco.yml`](../../.github/workflows/publish-kbcli-choco.yml) | Publish kbcli to Chocolatey |
| [`.github/workflows/publish-kbcli-scoop.yml`](../../.github/workflows/publish-kbcli-scoop.yml) | Publish kbcli to Scoop bucket |
| [`.github/workflows/publish-kbcli-winget.yml`](../../.github/workflows/publish-kbcli-winget.yml) | Publish kbcli to WinGet |
| [`.github/workflows/trigger-workflow.yml`](../../.github/workflows/trigger-workflow.yml) | Trigger a workflow in another repo |

### Utils

| Script | Purpose |
|---|---|
| [`.github/utils/utils.sh`](../../.github/utils/utils.sh) | Swiss-army knife: delete release (type 8), delete images (types 10/11/18), get latest tag (type 4), etc. |
| [`.github/utils/release_gitlab.sh`](../../.github/utils/release_gitlab.sh) | GitLab/Jihulab release operations |
| [`.github/utils/generate_release_notes.py`](../../.github/utils/generate_release_notes.py) | Generate release notes |
| [`.github/utils/is_rc_or_stable_release_version.py`](../../.github/utils/is_rc_or_stable_release_version.py) | Determine RC or stable release |
| [`.github/utils/parse_time.py`](../../.github/utils/parse_time.py) | Time parsing helper |

## utils.sh Type Quick Reference

| Type | Operation |
|---|---|
| 1 | Strip leading `v` from version |
| 2 | Replace `-` with `.` in version |
| 4 | Get latest release tag |
| 8 | Delete GitHub release |
| 10 | Delete Docker images |
| 11 | Delete Aliyun images |
| 14 | Get alpha/beta releases to delete |
| 18 | Delete Aliyun images (new domain) |
| 31 | Check release version |
| 35 | Bump chart version |

## Common Tasks

### 1. Delete an accidental release

```bash
# Delete GitHub release
bash ./.github/utils/utils.sh --type 8 \
    --github-repo apecloud/kubeblocks \
    --tag-name v0.4.0 \
    --github-token $GITHUB_TOKEN
```

### 2. Delete docker.io images

```bash
bash ./.github/utils/utils.sh --type 10 \
    --tag-name v0.4.0 \
    --docker-user $DOCKER_USER \
    --docker-password $DOCKER_PASSWORD
```

### 3. Get release branch

`release-branch.yml` automatically selects the release branch based on version number. When changing rules, keep it consistent with `get-version.yml`.

### 4. Generate release notes

`release-notes.yml` typically works with `generate_release_notes.py`. When modifying templates/formats, update both the script and workflow output.


## Troubleshooting

### `release-create.yml` creates a draft instead of a real release
- A pre-release is created when release notes are not found for the repo.
- For `apecloud/apecloud`, the workflow looks for `release-notes-<tag>.md` artifact/cache.

### `release-delete.yml` skipped deleting stable release
- `utils.sh --type 8` refuses to delete stable releases unless `--delete-force true` is passed.
- This protection is intentional; use force only when rolling back an accidental release.

### `release-branch.yml` returns the wrong branch
- The branch selection logic depends on the version prefix (`v` stripping) and current branches.
- If the rule changes, keep it in sync with `get-version.yml` and `release-version.yml`.

### kbcli publish fails on Windows runner
- `publish-kbcli-choco.yml` runs on `windows-2019`. Chocolatey package updates can fail due to
  upstream bucket changes; check the `apecloud-inc/chocolatey-packages` repository.

### `trigger-workflow.yml` did not trigger the target workflow
- Verify `WORKFLOW_ID` and `GITHUB_REPO` inputs.
- The target repo must have the requested workflow on the specified `BRANCH_NAME`.
- Check `GITHUB_TOKEN` permissions (needs `actions:write`).

## Related Skills

- [chart-release](../chart-release/SKILL.md) — chart release flow
- [image-management](../image-management/SKILL.md) — image check/push during release
- [utils-common](../utils-common/SKILL.md) — full `utils.sh` usage