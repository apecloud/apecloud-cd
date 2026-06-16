---
name: utils-common
description: >
  Swiss-army utilities in apecloud-cd: utils.sh --type operations, webhook_utils.sh,
  send_mesage.py, remove_ansi.py. Use as a reference when unsure which script/type to use,
  combining delete/release/test helpers, or adding new generic helper functions.
---

# Utils Common

This skill is the **overview entry** for `.github/utils`, explaining the multi-purpose design of `utils.sh`.

## Related Files

| Script | Purpose |
|---|---|
| [`.github/utils/utils.sh`](../../.github/utils/utils.sh) | 47+ operation entry points, invoked via `--type <number>` |
| [`.github/utils/webhook_utils.sh`](../../.github/utils/webhook_utils.sh) | Webhook/message notification helpers |
| [`.github/utils/send_mesage.py`](../../.github/utils/send_mesage.py) | Message sending script |
| [`.github/utils/remove_ansi.py`](../../.github/utils/remove_ansi.py) | Remove ANSI color codes |
| [`.github/utils/remove_ansi_file.py`](../../.github/utils/remove_ansi_file.py) | File-level ANSI color code cleanup |

## Complete utils.sh Type Reference

Invocation:

```bash
./.github/utils/utils.sh --type <number> [options]
```

| Type | Operation | Common params | Example |
|---|---|---|---|
| 1 | Strip leading `v` from version | `--tag-name` | `bash ./.github/utils/utils.sh --type 1 --tag-name v0.4.0` |
| 2 | Replace `-` with `.` in version | `--tag-name` | `bash ./.github/utils/utils.sh --type 2 --tag-name 0-4-0` |
| 3 | Get release asset upload URL | `--github-repo, --tag-name, --github-token` | `bash ./.github/utils/utils.sh --type 3 --github-repo apecloud/helm-charts --tag-name v0.4.0 --github-token $TOKEN` |
| 4 | Get latest release tag | `--github-repo, --github-token` | `bash ./.github/utils/utils.sh --type 4 --github-repo apecloud/kubeblocks --github-token $TOKEN` |
| 5 | Set release as latest | `--github-repo, --tag-name, --github-token` | `bash ./.github/utils/utils.sh --type 5 --github-repo apecloud/kubeblocks --tag-name v0.4.0 --github-token $TOKEN` |
| 6 | Get trigger mode | `--github-repo, --branch-name, --github-token` | `bash ./.github/utils/utils.sh --type 6 --github-repo apecloud/kubeblocks --branch-name main --github-token $TOKEN` |
| 7 | Trigger repo workflow | `--github-repo, --workflow-id, --branch-name, --github-token` | `bash ./.github/utils/utils.sh --type 7 --github-repo apecloud/kubeblocks --workflow-id release.yml --branch-name main --github-token $TOKEN` |
| 8 | Delete GitHub release | `--github-repo, --tag-name, --github-token, --delete-force` | `bash ./.github/utils/utils.sh --type 8 --github-repo apecloud/kubeblocks --tag-name v0.4.0 --github-token $TOKEN` |
| 9 | Delete KubeBlocks release charts | `--tag-name` | `bash ./.github/utils/utils.sh --type 9 --tag-name v0.4.0` |
| 10 | Delete Docker images | `--tag-name, --user, --password, --images` | `bash ./.github/utils/utils.sh --type 10 --tag-name v0.4.0 --user $USER --password $PASS` |
| 11 | Delete Aliyun images | `--tag-name, --user, --password` | `bash ./.github/utils/utils.sh --type 11 --tag-name v0.4.0 --user $USER --password $PASS` |
| 12 | Get test result | `--github-repo, --github-token, --test-result, --run-id` | `bash ./.github/utils/utils.sh --type 12 --github-repo apecloud/kubeblocks --test-result "$TEST_RESULT" --run-id $RUN_ID --github-token $TOKEN` |
| 13 | helm dependency update | `--chart-path` | `bash ./.github/utils/utils.sh --type 13 --chart-path deploy` |
| 14 | Get alpha/beta releases to delete | `--github-repo, --tag-name, --github-token, --delete-force` | `bash ./.github/utils/utils.sh --type 14 --github-repo apecloud/kubeblocks --tag-name v0.4.0 --github-token $TOKEN` |
| 15 | Comment on issue | `--github-repo, --issue-number, --issue-comment, --github-token` | `bash ./.github/utils/utils.sh --type 15 --github-repo apecloud/kubeblocks --issue-number 123 --issue-comment "hello" --github-token $TOKEN` |
| 16 | Delete runner | `--github-repo, --github-token` | `bash ./.github/utils/utils.sh --type 16 --github-repo apecloud/kubeblocks --github-token $TOKEN` |
| 17 | Get job URL | `--github-repo, --github-token, --run-id, --job-name` | `bash ./.github/utils/utils.sh --type 17 --github-repo apecloud/kubeblocks --run-id 123 --job-name test --github-token $TOKEN` |
| 18 | Delete Aliyun images (new domain) | `--tag-name, --user, --password` | `bash ./.github/utils/utils.sh --type 18 --tag-name v0.4.0 --user $USER --password $PASS` |
| 19 | Delete chart index | `--github-repo, --github-token` | `bash ./.github/utils/utils.sh --type 19 --github-repo apecloud/helm-charts --github-token $TOKEN` |
| 20 | Get incremental chart package | `--github-repo, --github-token, --branch-name` | `bash ./.github/utils/utils.sh --type 20 --github-repo apecloud/helm-charts --branch-name main --github-token $TOKEN` |
| 21 | Set PR size label | `--github-repo, --github-token, --pr-number` | `bash ./.github/utils/utils.sh --type 21 --github-repo apecloud/kubeblocks --pr-number 123 --github-token $TOKEN` |
| 22 | Set PR milestone | `--github-repo, --github-token, --pr-number` | `bash ./.github/utils/utils.sh --type 22 --github-repo apecloud/kubeblocks --pr-number 123 --github-token $TOKEN` |
| 23 | Set issue milestone | `--github-repo, --github-token, --issue-number` | `bash ./.github/utils/utils.sh --type 23 --github-repo apecloud/kubeblocks --issue-number 123 --github-token $TOKEN` |
| 24 | Move PR/issue to next milestone | `--github-repo, --github-token, --pr-number, --issue-number` | `bash ./.github/utils/utils.sh --type 24 --github-repo apecloud/kubeblocks --pr-number 123 --issue-number 456 --github-token $TOKEN` |
| 25 | Delete runner (alt) | `--github-repo, --runner-name, --github-token` | `bash ./.github/utils/utils.sh --type 25 --github-repo apecloud/kubeblocks --runner-name runner1 --github-token $TOKEN` |
| 26 | Set image list | `--images-list` | `bash ./.github/utils/utils.sh --type 26 --images-list images.txt` |
| 27 | Generate image YAML | `--github-repo, --github-token, --version` | `bash ./.github/utils/utils.sh --type 27 --github-repo apecloud/kubeblocks --version 0.4.0 --github-token $TOKEN` |
| 28 | Get release branch | `--version, --branch-name` | `bash ./.github/utils/utils.sh --type 28 --version 0.4.0 --branch-name main` |
| 29 | Delete tag | `--github-repo, --github-token, --tag-name` | `bash ./.github/utils/utils.sh --type 29 --github-repo apecloud/kubeblocks --tag-name v0.4.0 --github-token $TOKEN` |
| 30 | Delete actions cache | `--github-repo, --github-token` | `bash ./.github/utils/utils.sh --type 30 --github-repo apecloud/kubeblocks --github-token $TOKEN` |
| 31 | Check release version | `--version` | `bash ./.github/utils/utils.sh --type 31 --version v0.4.0` |
| 32 | Generate apecloud image YAML | `--github-repo, --version` | `bash ./.github/utils/utils.sh --type 32 --github-repo apecloud/kubeblocks --version 0.4.0` |
| 33 | Set label | `--github-repo, --github-token, --pr-number, --label-name, --label-ops` | `bash ./.github/utils/utils.sh --type 33 --github-repo apecloud/kubeblocks --pr-number 123 --label-name bug --label-ops add --github-token $TOKEN` |
| 34 | Get cloud E2E test result | `--github-repo, --github-token, --test-result, --run-id` | `bash ./.github/utils/utils.sh --type 34 --github-repo apecloud/kubeblocks --test-result "$R" --run-id 123 --github-token $TOKEN` |
| 35 | Bump chart version | `--branch-name` | `bash ./.github/utils/utils.sh --type 35 --branch-name main` |
| 36 | Parse test result | `--test-result, --test-ret, --test-type-name` | `bash ./.github/utils/utils.sh --type 36 --test-result "$R" --test-ret "0" --test-type-name postgresql` |
| 37 | Update k3d coredns configmap | `--version` | `bash ./.github/utils/utils.sh --type 37 --version 0.4.0` |
| 38 | Get cloud test result | `--github-repo, --github-token, --test-result` | `bash ./.github/utils/utils.sh --type 38 --github-repo apecloud/kubeblocks --test-result "$R" --github-token $TOKEN` |
| 39 | Get cloud pre-version | `--github-repo, --github-token` | `bash ./.github/utils/utils.sh --type 39 --github-repo apecloud/kubeblocks --github-token $TOKEN` |
| 40 | Get ginkgo test result | `--test-result, --test-ret` | `bash ./.github/utils/utils.sh --type 40 --test-result "$R" --test-ret "0"` |
| 41 | Get ginkgo test result total | `--test-result` | `bash ./.github/utils/utils.sh --type 41 --test-result "$R"` |
| 42 | Set API coverage result URL | `--github-repo, --github-token, --coverage-result, --run-id` | `bash ./.github/utils/utils.sh --type 42 --github-repo apecloud/kubeblocks --coverage-result "$R" --run-id 123 --github-token $TOKEN` |
| 43 | Set engine summary result URL | `--github-repo, --github-token, --test-result, --run-id` | `bash ./.github/utils/utils.sh --type 43 --github-repo apecloud/kubeblocks --test-result "$R" --run-id 123 --github-token $TOKEN` |
| 44 | Get GitHub Actions job URL | `--github-repo, --github-token, --run-id, --job-name` | `bash ./.github/utils/utils.sh --type 44 --github-repo apecloud/kubeblocks --run-id 123 --job-name test --github-token $TOKEN` |
| 45 | Set engine summary result URL v2 | `--github-repo, --github-token, --test-result, --run-id` | `bash ./.github/utils/utils.sh --type 45 --github-repo apecloud/kubeblocks --test-result "$R" --run-id 123 --github-token $TOKEN` |
| 46 | Get playwright test result | `--test-result` | `bash ./.github/utils/utils.sh --type 46 --test-result "$R"` |
| 47 | Get playwright test result total | `--test-result` | `bash ./.github/utils/utils.sh --type 47 --test-result "$R"` |
| 48 | Get cloud releases to delete | `--github-repo, --github-token` | `bash ./.github/utils/utils.sh --type 48 --github-repo apecloud/kubeblocks --github-token $TOKEN` |
| 49 | Delete release charts all | `--github-repo, --github-token, --tag-name` | `bash ./.github/utils/utils.sh --type 49 --github-repo apecloud/kubeblocks --tag-name v0.4.0 --github-token $TOKEN` |
| 50 | Delete cloud Docker images | `--tag-name, --user, --password` | `bash ./.github/utils/utils.sh --type 50 --tag-name v0.4.0 --user $USER --password $PASS` |
| 51 | Delete cloud Aliyun images | `--tag-name, --user, --password` | `bash ./.github/utils/utils.sh --type 51 --tag-name v0.4.0 --user $USER --password $PASS` |

## Common Command Templates

```bash
# Get release branch
./.github/utils/utils.sh --type 28 --version 0.4.0 --branch-name main

# Bump chart version
./.github/utils/utils.sh --type 35 --branch-name <branch>

# Parse E2E test result (send-message)
./.github/utils/utils.sh --type 36 \
    --test-result "..." \
    --test-ret "..." \
    --test-type-name "..."
```

## When to Use This Skill

- You want to "delete something" but are unsure whether to use type 8/10/11/18/19/29/30/49.
- You want to add a new generic utility function and need to pick a type range.
- You need to combine multiple types to complete a cleanup/release/test task.

## Design Conventions

- `utils.sh` parses long options in `parse_command_line` and dispatches via `case $TYPE` in `main`.
- The script detects `uname -s` to distinguish Linux/macOS, using `sed -i` vs `sed -i ''`.
- Delete operations usually have a `--delete-force` guard to avoid accidental stable release deletion.

## Related Skills

- [chart-release](../chart-release/SKILL.md)
- [image-management](../image-management/SKILL.md)
- [release-operations](../release-operations/SKILL.md)
- [ci-auxiliary](../ci-auxiliary/SKILL.md)
- [e2e-testing](../e2e-testing/SKILL.md)
