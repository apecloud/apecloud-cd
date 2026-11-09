"""Run the checker with deterministic Helm and registry inspection responses."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


CHECKER = Path(__file__).resolve().parents[1] / "helm_image_check.sh"
REGISTRY = "apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud"
DIGEST = "sha256:" + "a" * 64
SINGLE_MANIFEST = "Name: example\nMediaType: application/vnd.oci.image.manifest.v1+json\nDigest: " + DIGEST + "\n"
MULTI_MANIFEST = SINGLE_MANIFEST + "Platform: linux/amd64\nPlatform: linux/arm64\n"


class HelmImageCheckTest(unittest.TestCase):
    def check_image(self, reference, output, expected_status, inspect_status=0):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bins = root / "bin"
            bins.mkdir()
            charts = root / "charts"
            charts.mkdir()
            (charts / "polardb-mysql.tgz").touch()
            programs = {
                "helm": '#!/bin/sh\nprintf "image: %s\\n" "$TEST_IMAGE"\n',
                "docker": """#!/usr/bin/env python3
import json
import os
import sys
with open(os.environ["TEST_CALLS"], "a") as calls:
    calls.write(json.dumps(sys.argv[1:]) + "\\n")
sys.stdout.write(os.environ["TEST_INSPECTION"])
sys.exit(int(os.environ["TEST_INSPECTION_STATUS"]))
""",
                "sleep": "#!/bin/sh\nexit 0\n",
                "tput": "#!/bin/sh\nexit 0\n",
            }
            for name, content in programs.items():
                path = bins / name
                path.write_text(content)
                path.chmod(0o755)
            calls_path = root / "calls.jsonl"
            env = dict(os.environ, PATH=str(bins) + os.pathsep + os.environ["PATH"],
                       TEST_IMAGE=reference, TEST_INSPECTION=output,
                       TEST_INSPECTION_STATUS=str(inspect_status), TEST_CALLS=str(calls_path))
            result = subprocess.run(["bash", str(CHECKER), str(charts)], cwd=root,
                                    env=env, text=True, capture_output=True, timeout=15)
            self.assertEqual(result.returncode, expected_status, result.stdout + result.stderr)
            calls = [json.loads(line) for line in calls_path.read_text().splitlines()]
            self.assertTrue(calls)
            # In particular, lookup must still use the complete digest-pinned reference.
            self.assertTrue(all(call == ["buildx", "imagetools", "inspect", reference]
                                for call in calls), calls)

    def test_architecture_tags_with_digest_accept_single_manifest(self):
        for registry in (REGISTRY, "docker.io/apecloud"):
            for arch in ("amd64", "arm64"):
                with self.subTest(registry=registry, arch=arch):
                    self.check_image(registry + "/polardb-mysql:8.0.2.2.31.1-" + arch + "@" + DIGEST,
                                     SINGLE_MANIFEST, 0)

    def test_architecture_tags_without_digest_keep_existing_behavior(self):
        for arch in ("amd64", "arm64"):
            with self.subTest(arch=arch):
                self.check_image(REGISTRY + "/polardb-mysql:8.0.2.2.31.1-" + arch,
                                 SINGLE_MANIFEST, 0)

    def test_generic_tags_still_require_both_architectures(self):
        for suffix in ("", "@" + DIGEST):
            reference = REGISTRY + "/polardb-mysql:8.0.2.2.31.1" + suffix
            for output, status in ((MULTI_MANIFEST, 0), (SINGLE_MANIFEST, 1),
                                   (SINGLE_MANIFEST + "Platform: linux/amd64\n", 1)):
                with self.subTest(reference=reference, output=output):
                    self.check_image(reference, output, status)

    def test_digest_without_tag_does_not_infer_architecture_from_repository(self):
        reference = REGISTRY + "/polardb-mysql-amd64@" + DIGEST
        self.check_image(reference, MULTI_MANIFEST, 0)
        self.check_image(reference, SINGLE_MANIFEST, 1)

    def test_missing_pinned_image_still_fails(self):
        self.check_image(REGISTRY + "/polardb-mysql:8.0.2.2.31.1-amd64@" + DIGEST,
                         "", 1, inspect_status=1)


if __name__ == "__main__":
    unittest.main()
