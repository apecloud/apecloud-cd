#!/usr/bin/env python3
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/release-image-cache-sync.yml"
VALID_DIGEST_A = "sha256:" + "a" * 64
VALID_DIGEST_B = "sha256:" + "b" * 64


def load_workflow() -> dict:
    workflow = yaml.safe_load(WORKFLOW.read_text())
    workflow_on = workflow.get("on", workflow.get(True))
    if not isinstance(workflow_on, dict):
        raise AssertionError("workflow must define an on mapping")
    workflow["on"] = workflow_on
    return workflow


def step_by_id(workflow: dict, step_id: str) -> dict:
    steps = workflow["jobs"]["release-image"]["steps"]
    matches = [step for step in steps if step.get("id") == step_id]
    if len(matches) != 1:
        raise AssertionError(f"expected one step with id {step_id}, got {len(matches)}")
    return matches[0]


class ReleaseImageCacheSyncContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = load_workflow()
        cls.selector = step_by_id(cls.workflow, "select_image_index_digest")

    def test_reusable_and_job_outputs_are_additive_and_exact(self) -> None:
        workflow_outputs = self.workflow["on"]["workflow_call"]["outputs"]
        self.assertEqual(
            workflow_outputs["image-index-digest"]["value"],
            "${{ jobs.release-image.outputs.image-index-digest }}",
        )

        job_outputs = self.workflow["jobs"]["release-image"]["outputs"]
        self.assertEqual(
            job_outputs["tag-name"], "${{ steps.get_tag_name.outputs.TAG-NAME }}"
        )
        self.assertEqual(
            job_outputs["image-index-digest"],
            "${{ steps.select_image_index_digest.outputs.image-index-digest }}",
        )

    def test_both_build_branches_export_direct_digest_and_disable_attestations(
        self,
    ) -> None:
        steps = self.workflow["jobs"]["release-image"]["steps"]
        token_build = step_by_id(self.workflow, "build_with_args_token")
        plain_build = step_by_id(self.workflow, "build_without_args_token")
        build_steps = [
            step for step in steps if step.get("uses") == "docker/build-push-action@v5"
        ]

        self.assertEqual(build_steps, [token_build, plain_build])
        self.assertLess(steps.index(token_build), steps.index(self.selector))
        self.assertLess(steps.index(plain_build), steps.index(self.selector))
        self.assertIn("inputs.ARGS_TOKEN", token_build["if"])
        self.assertIn("! inputs.ARGS_TOKEN", plain_build["if"])
        for build in (token_build, plain_build):
            self.assertEqual(build["uses"], "docker/build-push-action@v5")
            self.assertIs(build["with"]["push"], True)
            self.assertIs(build["with"]["provenance"], False)
            self.assertIs(build["with"]["sbom"], False)

        self.assertEqual(
            self.selector["env"],
            {
                "DIGEST_WITH_ARGS_TOKEN": "${{ steps.build_with_args_token.outputs.digest }}",
                "DIGEST_WITHOUT_ARGS_TOKEN": "${{ steps.build_without_args_token.outputs.digest }}",
            },
        )

    def run_selector(
        self, token_digest: str = "", plain_digest: str = ""
    ) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "github-output"
            env = os.environ.copy()
            env.update(
                {
                    "DIGEST_WITH_ARGS_TOKEN": token_digest,
                    "DIGEST_WITHOUT_ARGS_TOKEN": plain_digest,
                    "GITHUB_OUTPUT": str(output),
                }
            )
            result = subprocess.run(
                ["bash", "-c", self.selector["run"]],
                check=False,
                capture_output=True,
                text=True,
                env=env,
            )
            result.github_output = output.read_text() if output.exists() else ""
            return result

    def test_token_build_digest_is_selected(self) -> None:
        result = self.run_selector(token_digest=VALID_DIGEST_A)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.github_output, f"image-index-digest={VALID_DIGEST_A}\n")

    def test_plain_build_digest_is_selected(self) -> None:
        result = self.run_selector(plain_digest=VALID_DIGEST_B)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.github_output, f"image-index-digest={VALID_DIGEST_B}\n")

    def test_missing_duplicate_and_malformed_digests_fail_closed(self) -> None:
        cases = (
            ("", ""),
            (VALID_DIGEST_A, VALID_DIGEST_B),
            ("sha256:" + "A" * 64, ""),
            ("sha256:1234", ""),
            ("not-a-digest", ""),
        )
        for token_digest, plain_digest in cases:
            with self.subTest(token_digest=token_digest, plain_digest=plain_digest):
                result = self.run_selector(token_digest, plain_digest)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.github_output, "")

    def test_selector_has_no_mutable_tag_lookup_fallback(self) -> None:
        script = self.selector["run"]
        forbidden = (
            "docker manifest",
            "imagetools",
            "skopeo",
            "crane",
            "TAG-NAME",
            "tag-name",
        )
        self.assertFalse([needle for needle in forbidden if needle in script])


if __name__ == "__main__":
    unittest.main()
