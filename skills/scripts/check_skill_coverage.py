#!/usr/bin/env python3
"""Check that every workflow and util is referenced by at least one skill.

Usage:
    python3 skills/scripts/check_skill_coverage.py

Exit codes:
    0  all covered
    1  uncovered workflows or utils exist
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILLS_DIR = ROOT / "skills"
WORKFLOWS_DIR = ROOT / ".github" / "workflows"
UTILS_DIR = ROOT / ".github" / "utils"

WORKFLOW_RE = re.compile(r"\.github/workflows/([\w.-]+\.(?:yml|yaml))")
UTIL_RE = re.compile(r"\.github/utils/([\w_.-]+)")


def main() -> int:
    referenced_workflows: set[str] = set()
    referenced_utils: set[str] = set()

    for md in sorted(SKILLS_DIR.rglob("*.md")):
        text = md.read_text()
        referenced_workflows.update(m.group(1) for m in WORKFLOW_RE.finditer(text))
        referenced_utils.update(m.group(1) for m in UTIL_RE.finditer(text))

    all_workflows = {p.name for p in WORKFLOWS_DIR.iterdir() if p.suffix in (".yml", ".yaml")}
    all_utils = {p.name for p in UTILS_DIR.iterdir() if p.is_file() and not p.name.startswith("__")}

    uncovered_wf = sorted(all_workflows - referenced_workflows)
    uncovered_ut = sorted(all_utils - referenced_utils)

    print(f"Workflows: {len(all_workflows) - len(uncovered_wf)}/{len(all_workflows)} referenced")
    print(f"Utils:     {len(all_utils) - len(uncovered_ut)}/{len(all_utils)} referenced")

    if uncovered_wf:
        print("\nUNCOVERED WORKFLOWS:")
        for w in uncovered_wf:
            print(f"  - {w}")

    if uncovered_ut:
        print("\nUNCOVERED UTILS:")
        for u in uncovered_ut:
            print(f"  - {u}")

    if uncovered_wf or uncovered_ut:
        return 1

    print("\nOK: all workflows and utils are covered by at least one skill.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
