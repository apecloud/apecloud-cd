#!/usr/bin/env python3
"""Consume the Web E2E summary contract for notifications and GitHub Issues."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Iterable, Mapping
from urllib.parse import quote

import requests


API_ROOT = "https://api.github.com"


def _int(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _stored_rate(counts: Mapping[str, Any], name: str) -> str:
    value = counts.get(name)
    if value is None:
        return ""
    try:
        return f"{float(value):.1f}%"
    except (TypeError, ValueError):
        return ""


def _execution_rate(counts: Mapping[str, Any]) -> str:
    stored = _stored_rate(counts, "execution_pass_rate")
    if stored:
        return stored
    passed = _int(counts.get("passed"))
    failed = _int(counts.get("failed"))
    executable = passed + failed
    return f"{passed / executable * 100:.1f}%" if executable else "0.0%"


def _effective_rate(counts: Mapping[str, Any]) -> str:
    stored = _stored_rate(counts, "effective_pass_rate")
    if stored:
        return stored
    passed = _int(counts.get("passed"))
    denominator = (
        passed
        + _int(counts.get("failed"))
        + _int(counts.get("broken"))
        + _int(counts.get("blocked"))
        + _int(counts.get("not_reached"))
    )
    return f"{passed / denominator * 100:.1f}%" if denominator else "0.0%"


def _rate_pair(counts: Mapping[str, Any]) -> str:
    return f"{_execution_rate(counts)} / {_effective_rate(counts)}"


def _safe_field(value: Any) -> str:
    return str(value or "").replace("|", "/").replace("#", "").replace("@", "")


def notification_fragment(
    summary: Mapping[str, Any],
    report_url: str = "",
    issue_url: str = "",
) -> str:
    run = summary.get("run") if isinstance(summary.get("run"), Mapping) else {}
    totals = summary.get("counts") if isinstance(summary.get("counts"), Mapping) else {}
    engine = _safe_field(run.get("engine") or "unknown")
    rows = []
    for result in summary.get("results") or []:
        if not isinstance(result, Mapping):
            continue
        counts = result.get("counts") if isinstance(result.get("counts"), Mapping) else {}
        row_engine = _safe_field(result.get("engine") or engine)
        spec = _safe_field(
            result.get("spec")
            or "/".join(filter(None, [
                str(result.get("mode") or ""),
                str(result.get("engine_version") or ""),
            ]))
            or "default"
        )
        failed = _int(counts.get("failed"))
        broken = _int(counts.get("broken"))
        blocked = _int(counts.get("blocked"))
        not_reached = _int(counts.get("not_reached"))
        status = (
            "FAILED"
            if failed
            else "BROKEN"
            if broken or blocked or not_reached
            else "PASSED"
        )
        rows.append("|".join([
            row_engine,
            spec,
            _rate_pair(counts),
            status,
            str(_int(counts.get("passed"))),
            str(failed),
            str(_int(counts.get("skipped"))),
            str(broken),
            str(blocked),
            str(_int(counts.get("unsupported"))),
            str(not_reached),
        ]))

    # Initialization failures may terminate the run before any test case starts,
    # leaving results empty. Top-level counts/status still identify a framework
    # interruption, so the notification must not contain an empty summary.
    if not rows:
        failed = _int(totals.get("failed"))
        broken = _int(totals.get("broken"))
        blocked = _int(totals.get("blocked"))
        not_reached = _int(totals.get("not_reached"))
        top_status = str(summary.get("status") or "").lower()
        status = (
            "FAILED"
            if failed
            else "BROKEN"
            if broken or blocked or not_reached or top_status == "broken"
            else "PASSED"
        )
        rows.append("|".join([
            engine,
            "run",
            _rate_pair(totals),
            status,
            str(_int(totals.get("passed"))),
            str(failed),
            str(_int(totals.get("skipped"))),
            str(broken),
            str(blocked),
            str(_int(totals.get("unsupported"))),
            str(not_reached),
        ]))

    failed_subjects = []
    for failure in summary.get("failures") or []:
        if not isinstance(failure, Mapping):
            continue
        subject = (
            failure.get("step_name")
            or failure.get("case_name")
            or failure.get("code")
        )
        if subject and subject not in failed_subjects:
            failed_subjects.append(str(subject))
    fail_ops = ",".join(failed_subjects[:10])
    if issue_url:
        fail_ops = (
            f"{fail_ops} " if fail_ops else ""
        ) + f"<a href='{issue_url}'>Issue</a>"
    data = "##".join(rows)
    return (
        f"###{engine}###{_effective_rate(totals)}###{report_url}"
        f"@@@{data}@@@{_safe_field(fail_ops)}"
    )


def _add_notification_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--summary", required=True)
    parser.add_argument("--report-url", default="")
    parser.add_argument("--issue-url", default="")


def run_notification(args: argparse.Namespace) -> int:
    summary = json.loads(Path(args.summary).read_text(encoding="utf-8"))
    print(notification_fragment(summary, args.report_url, args.issue_url), end="")
    return 0


def _clean(value: Any) -> str:
    return str(value or "").strip()


def eligible_candidates(summary: Mapping[str, Any]) -> list[dict[str, Any]]:
    candidates = summary.get("issue_candidates")
    if not isinstance(candidates, list):
        candidates = summary.get("failures") or []
    return [
        dict(candidate)
        for candidate in candidates
        if isinstance(candidate, Mapping)
        and candidate.get("failure_type") == "functional"
        and int(candidate.get("consecutive_failures") or 0) >= 2
    ]


def issue_marker(signature: str) -> str:
    return f"<!-- e2e-signature:{signature} -->"


def issue_title(candidate: Mapping[str, Any]) -> str:
    engine = _clean(candidate.get("engine")) or "unknown"
    subject = (
        _clean(candidate.get("step_name"))
        or _clean(candidate.get("case_name"))
        or _clean(candidate.get("code"))
        or "functional failure"
    )
    return f"[E2E][{engine}] {subject}"[:250]


def _links_markdown(links: Mapping[str, str]) -> str:
    items = [
        f"- [{label}]({url})"
        for label, url in links.items()
        if _clean(url)
    ]
    return "\n".join(items) if items else "- No external artifact URL"


def occurrence_body(
    candidate: Mapping[str, Any],
    summary: Mapping[str, Any],
    links: Mapping[str, str],
) -> str:
    run = summary.get("run") if isinstance(summary.get("run"), Mapping) else {}
    signature = _clean(candidate.get("signature"))
    scope = _clean(
        candidate.get("scope")
        or candidate.get("spec")
        or candidate.get("mode")
    )
    message = _clean(candidate.get("message"))[:4000]
    return f"""### Automated E2E occurrence

- Run: `{_clean(run.get("run_id"))}`
- Suite: `{_clean(summary.get("suite_type"))}`
- Environment: `{_clean(run.get("environment"))}`
- Cloud version: `{_clean(run.get("cloud_version"))}`
- Engine: `{_clean(candidate.get("engine"))}`
- Scope: `{scope}`
- Failure type: `{_clean(candidate.get("failure_type"))}`
- Consecutive failures: `{int(candidate.get("consecutive_failures") or 0)}`

**Failure**

```text
{message}
```

**Artifacts**

{_links_markdown(links)}

{issue_marker(signature)}
"""


class GitHubIssueClient:
    def __init__(self, *, repository: str, token: str, session=None):
        self.repository = repository
        self.session = session or requests.Session()
        self.headers = {
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        }

    def _request(self, method: str, path: str, **kwargs):
        response = self.session.request(
            method,
            f"{API_ROOT}{path}",
            headers=self.headers,
            timeout=30,
            **kwargs,
        )
        if response.status_code >= 400:
            raise RuntimeError(
                f"GitHub API {method} {path} failed: "
                f"{response.status_code} {response.text[:500]}"
            )
        return response.json() if response.text else {}

    def find(self, signature: str) -> dict[str, Any] | None:
        marker = f"e2e-signature:{signature}"
        query = quote(f'repo:{self.repository} is:issue "{marker}" in:body')
        result = self._request("GET", f"/search/issues?q={query}&per_page=10")
        items = result.get("items") or []
        return dict(items[0]) if items else None

    def create(self, title: str, body: str) -> dict[str, Any]:
        return self._request(
            "POST",
            f"/repos/{self.repository}/issues",
            json={"title": title, "body": body},
        )

    def comment(self, issue_number: int, body: str) -> None:
        self._request(
            "POST",
            f"/repos/{self.repository}/issues/{issue_number}/comments",
            json={"body": body},
        )

    def reopen(self, issue_number: int) -> None:
        self._request(
            "PATCH",
            f"/repos/{self.repository}/issues/{issue_number}",
            json={"state": "open"},
        )


def process_candidates(
    *,
    summary: Mapping[str, Any],
    repository: str,
    token: str,
    links: Mapping[str, str],
    client: GitHubIssueClient | None = None,
) -> list[dict[str, Any]]:
    github = client or GitHubIssueClient(repository=repository, token=token)
    outcomes = []
    for candidate in eligible_candidates(summary):
        signature = _clean(candidate.get("signature"))
        if not signature:
            continue
        body = occurrence_body(candidate, summary, links)
        existing = github.find(signature)
        if existing:
            number = int(existing["number"])
            if existing.get("state") == "closed":
                github.reopen(number)
            github.comment(number, body)
            outcomes.append({
                "action": "updated",
                "number": number,
                "url": existing.get("html_url", ""),
                "signature": signature,
            })
        else:
            created = github.create(issue_title(candidate), body)
            outcomes.append({
                "action": "created",
                "number": created.get("number"),
                "url": created.get("html_url", ""),
                "signature": signature,
            })
    return outcomes


def _add_issue_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--summary", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--action-url", default="")
    parser.add_argument("--report-url", default="")
    parser.add_argument("--summary-url", default="")
    parser.add_argument("--output", default="")


def run_issue(args: argparse.Namespace) -> int:
    summary = json.loads(Path(args.summary).read_text(encoding="utf-8"))
    outcomes = process_candidates(
        summary=summary,
        repository=args.repository,
        token=args.token,
        links={
            "GitHub Action": args.action_url,
            "HTML report": args.report_url,
            "summary.json": args.summary_url,
        },
    )
    if args.output:
        Path(args.output).write_text(
            json.dumps(outcomes, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    for outcome in outcomes:
        if outcome.get("url"):
            print(f"[E2E-ISSUE-URL]{outcome['url']}")
    print(json.dumps({
        "eligible": len(eligible_candidates(summary)),
        "processed": len(outcomes),
    }, ensure_ascii=False))
    return 0


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    notification_parser = subparsers.add_parser(
        "notification",
        help="Convert summary.json to the Feishu notification fragment.",
    )
    _add_notification_arguments(notification_parser)
    notification_parser.set_defaults(handler=run_notification)
    issue_parser = subparsers.add_parser(
        "issue",
        help="Create or update deduplicated GitHub Issues.",
    )
    _add_issue_arguments(issue_parser)
    issue_parser.set_defaults(handler=run_issue)
    args = parser.parse_args(list(argv) if argv is not None else None)
    return args.handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
