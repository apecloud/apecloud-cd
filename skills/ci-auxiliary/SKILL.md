---
name: ci-auxiliary
description: >
  GitHub repository automation: PR label, PR size label, PR milestone, issue milestone,
  auto cherry-pick, comment issue, GitHub Actions runner enable/delete, actions cache cleanup,
  feishu-message, webhook_utils.sh Use when changing label rules, milestone policies,
  cherry-pick targets, runner management, or bot message formats.
---

# CI Auxiliary

This skill covers **PR / issue / milestone / cherry-pick** automation.

## Related Files

### Workflows

| Workflow | Purpose |
|---|---|
| [`.github/workflows/pull-request-label.yml`](../../.github/workflows/pull-request-label.yml) | Set PR labels |
| [`.github/workflows/pull-request-label-check.yml`](../../.github/workflows/pull-request-label-check.yml) | Validate PR labels |
| [`.github/workflows/pull-request-label-pick.yml`](../../.github/workflows/pull-request-label-pick.yml) | Pick by label |
| [`.github/workflows/pull-request-label-size.yml`](../../.github/workflows/pull-request-label-size.yml) | Set size label based on PR diff size |
| [`.github/workflows/pull-request-milestone.yml`](../../.github/workflows/pull-request-milestone.yml) | Set PR milestone |
| [`.github/workflows/pull-request-cherry-pick-auto.yml`](../../.github/workflows/pull-request-cherry-pick-auto.yml) | Auto cherry-pick |
| [`.github/workflows/pull-request-cherry-pick-usage.yml`](../../.github/workflows/pull-request-cherry-pick-usage.yml) | Cherry-pick usage instructions |
| [`.github/workflows/issue-milestone.yml`](../../.github/workflows/issue-milestone.yml) | Set issue milestone |
| [`.github/workflows/milestone-move.yml`](../../.github/workflows/milestone-move.yml) | Migrate milestones |
| [`.github/workflows/comment-issue.yml`](../../.github/workflows/comment-issue.yml) | Issue comment bot |
| [`.github/workflows/renew-issue.yml`](../../.github/workflows/renew-issue.yml) | Renew/reopen issues |
| [`.github/workflows/update-release-notes.yml`](../../.github/workflows/update-release-notes.yml) | Update release notes (also in release-operations) |
| [`.github/workflows/feishui-message.yml`](../../.github/workflows/feishui-message.yml) | Feishu message push |
| [`.github/workflows/delete-runner.yml`](../../.github/workflows/delete-runner.yml) | Delete a GitHub Actions runner by repo |
| [`.github/workflows/enable-self-runner.yml`](../../.github/workflows/enable-self-runner.yml) | Enable/disable self-hosted runners in a cluster |

### Utils

| Script | Purpose |
|---|---|
| [`.github/utils/utils.sh`](../../.github/utils/utils.sh) | Includes comment_issue (type 15), set_size_label (type 21), set_pr_milestone (type 22), set_issue_milestone (type 23), move_pr_issue_to_next_milestone (type 24), delete_actions_cache (type 30), get_job_url (type 44) |
| [`.github/utils/webhook_utils.sh`](../../.github/utils/webhook_utils.sh) | Webhook message helpers |
| [`.github/utils/send_mesage.py`](../../.github/utils/send_mesage.py) | Message sending |

## utils.sh Type Quick Reference

| Type | Operation |
|---|---|
| 15 | Comment on issue |
| 21 | Set PR size label |
| 22 | Set PR milestone |
| 23 | Set issue milestone |
| 24 | Move PR/issue to next milestone |
| 30 | Delete actions cache |
| 44 | Get GitHub Actions job URL |

## Common Tasks

### 1. Change PR size label rules

```bash
bash ./.github/utils/utils.sh --type 21 \
    --github-repo "${{ github.repository }}" \
    --github-token "${{ env.GITHUB_TOKEN }}" \
    --pr-number "${{ github.event.pull_request.number }}"
```

The rule logic lives in `utils.sh` function `set_size_label`, typically classifying diffs into `size/XS` through `size/XXL`.

### 2. Add a new cherry-pick target branch

Configure target branches and trigger labels in `pull-request-cherry-pick-auto.yml`. Notes:

- Trigger labels usually look like `cherry-pick release-x.y`.
- On failure, the workflow creates a comment to alert maintainers.

### 3. Adjust issue auto-comments

`comment-issue.yml` calls `utils.sh --type 15`. To change comment content, update the `comment_issue` function or workflow parameters.

### 4. Delete actions cache

```bash
bash ./.github/utils/utils.sh --type 30 \
    --github-repo <repo> \
    --github-token <token>
```

## Related Skills

- [utils-common](../utils-common/SKILL.md) — full `utils.sh` guide
- [release-operations](../release-operations/SKILL.md) — release notes updates