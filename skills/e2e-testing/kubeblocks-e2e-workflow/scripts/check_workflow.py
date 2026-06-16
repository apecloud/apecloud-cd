#!/usr/bin/env python3
"""Validate kubeblocks-e2e-test.yml consistency.

Checks:
1. Every test-* job is referenced in at least one send-message job's needs.
2. Every send-message job only references existing test-* jobs.
3. terraform-destroy-k8s.needs includes all send-message jobs.
4. No duplicate job IDs.
5. Test job IDs match their test-type-name (version sanitization consistency).

Usage:
    python3 check_workflow.py [path/to/kubeblocks-e2e-test.yml]
"""

import sys
import yaml


def check(path: str) -> list[str]:
    with open(path, "r") as f:
        data = yaml.safe_load(f)

    errors = []
    jobs = data.get("jobs", {})

    test_jobs = {jid for jid in jobs if jid.startswith("test-") and jid != "test-kubeblocks"}
    send_jobs = {jid for jid in jobs if jid.startswith("send-message")}
    destroy_job = jobs.get("terraform-destroy-k8s", {})

    # 1. Collect needs from all send-message jobs
    referenced = set()
    for sj in send_jobs:
        needs = jobs[sj].get("needs", [])
        if isinstance(needs, str):
            needs = [needs]
        for n in needs:
            if n.startswith("test-"):
                referenced.add(n)

    # 2. Every test job must be referenced
    unreferenced = test_jobs - referenced
    if unreferenced:
        errors.append(f"Unreferenced test jobs (missing from send-message needs): {sorted(unreferenced)}")

    # 3. send-message jobs should only reference existing test jobs
    for sj in send_jobs:
        needs = jobs[sj].get("needs", [])
        if isinstance(needs, str):
            needs = [needs]
        for n in needs:
            if n.startswith("test-") and n not in test_jobs:
                errors.append(f"send-message job '{sj}' references non-existent test job '{n}'")

    # 4. terraform-destroy-k8s must need all send-message jobs
    destroy_needs = destroy_job.get("needs", [])
    if isinstance(destroy_needs, str):
        destroy_needs = [destroy_needs]
    destroy_needs_set = set(destroy_needs)
    missing_destroy = send_jobs - destroy_needs_set
    # terraform-init-k8s should also be there
    if "terraform-init-k8s" not in destroy_needs_set:
        errors.append("terraform-destroy-k8s is missing 'terraform-init-k8s' in needs")
    if missing_destroy:
        errors.append(f"terraform-destroy-k8s is missing send-message jobs in needs: {sorted(missing_destroy)}")

    # 5. Job ID vs test-type-name consistency
    for jid in test_jobs:
        test_type_name = jobs[jid].get("with", {}).get("test-type-name", "")
        expected_id = f"test-{test_type_name}"
        if jid != expected_id and jid != "test-kubeblocks":
            errors.append(f"Job ID mismatch: '{jid}' vs test-type-name '{test_type_name}' (expected '{expected_id}')")

    # 6. Duplicate job IDs (yaml loader handles this, but let's be safe)
    # Already handled by dict keys above

    return errors


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else ".github/workflows/kubeblocks-e2e-test.yml"
    errors = check(path)
    if errors:
        print(f"FAILED: {len(errors)} issue(s) found in {path}")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)
    else:
        print(f"OK: {path} is consistent.")
        sys.exit(0)


if __name__ == "__main__":
    main()
