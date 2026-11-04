#!/usr/bin/env python3
"""Offline contract tests using real Helm/yq and disposable local Charts."""
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('manifests_charts_image_check.sh').resolve()
HELM = shutil.which('helm')
YQ = shutil.which('yq')


@unittest.skipUnless(HELM and YQ, 'helm and mikefarah/yq are required')
class CloudChartCheckTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='manifest-chart-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.make_cloud('source', '1.2.0')
        self.published = self.make_cloud('published', '1.1.0')
        self.other = self.root / 'other'
        self.make_chart(self.other, 'other', 'image: docker.io/apecloud/other:1.0.0\n')
        self.manifest = {
            'kubeblocks-cloud': [{
                'version': 'v9.1.0', 'isEnterprise': True,
                'images': ['apecloud/dms:1.2.0', 'apecloud/apiserver:v9.1.0'],
            }],
        }
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.log = self.root / 'helm.log'
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        REAL_HELM=HELM, HELM_TEST_LOG=str(self.log),
                        PUBLISHED_CHART=str(self.published), OTHER_CHART=str(self.other),
                        CLOUD_CHART_PATH='', CLOUD_CHART_VERSION='')
        self.write_executable(self.bin / 'sleep', '#!/bin/sh\nexit 0\n')
        self.write_executable(self.bin / 'helm', '''#!/usr/bin/env python3
import json, os, subprocess, sys
args = sys.argv[1:]
with open(os.environ['HELM_TEST_LOG'], 'a') as f:
    f.write(json.dumps(args) + '\\n')
if args[:2] == ['dependency', 'build'] and os.getenv('FAIL_BUILD'):
    sys.exit(1)
if args[:2] == ['dependency', 'build']:
    args.append('--skip-refresh')
if args and args[0] == 'repo':
    sys.exit(0)
if args and args[0] == 'template':
    if args[1] == 'kubeblocks-cloud':
        if os.getenv('FAIL_RENDER'):
            sys.stderr.write('render failed\\n'); sys.exit(1)
        if os.getenv('EMPTY_RENDER'):
            sys.exit(0)
        if not os.path.isdir(args[2]):
            if os.getenv('MISSING_PUBLISHED'):
                sys.stderr.write('chart not found in repository\\n'); sys.exit(1)
            args[2] = os.environ['PUBLISHED_CHART']
    else:
        args[2] = os.environ['OTHER_CHART']
sys.exit(subprocess.call([os.environ['REAL_HELM'], *args]))
''')

    def write_executable(self, path, content):
        path.write_text(content)
        path.chmod(0o755)

    def make_chart(self, path, name, template, version='1.0.0'):
        (path / 'templates').mkdir(parents=True)
        (path / 'Chart.yaml').write_text(f'apiVersion: v2\nname: {name}\nversion: {version}\n')
        (path / 'templates' / 'pod.yaml').write_text(
            'apiVersion: v1\nkind: Pod\nmetadata:\n  name: test\nspec:\n  containers:\n  - name: test\n    ' + template)

    def make_cloud(self, name, dms_version):
        directory = self.root / name
        chart = directory / 'cloud'
        self.make_chart(chart, 'kubeblocks-cloud',
                        'image: "docker.io/apecloud/apiserver:{{ .Values.appTag }}"\n', '9.1.0')
        (chart / 'values.yaml').write_text('appTag: v9.1.0\n')
        self.make_chart(directory / 'dms', 'dms',
                        f'image: docker.io/apecloud/dms:{dms_version}\n', dms_version)
        with (chart / 'Chart.yaml').open('a') as f:
            f.write(f'dependencies:\n- name: dms\n  version: {dms_version}\n  repository: file://../dms\n')
        subprocess.run([HELM, 'dependency', 'update', str(chart), '--skip-refresh'], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        return chart

    def run_check(self, source=True, version='', **env):
        path = self.root / 'manifest.yaml'
        path.write_text(json.dumps(self.manifest))
        check_env = dict(self.env, CLOUD_CHART_PATH=str(self.source) if source else '',
                         CLOUD_CHART_VERSION=version, **env)
        result = subprocess.run(['bash', str(SCRIPT), str(path), 'false',
                                 str(self.root / 'check-engine.py')], cwd=self.root,
                                env=check_env, text=True, capture_output=True)
        self.output = result.stdout + result.stderr
        return result.returncode

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def assert_passes(self, **kwargs):
        self.assertEqual(self.run_check(**kwargs), 0, self.output)

    def assert_fails(self, message, **kwargs):
        self.assertNotEqual(self.run_check(**kwargs), 0, self.output)
        self.assertIn(message, self.output)

    def test_source_uses_locked_current_chart_not_published_cloud(self):
        self.assert_passes()
        self.assertIn(['dependency', 'build', str(self.source)], self.calls())
        templates = [c for c in self.calls() if c[0] == 'template' and c[1] == 'kubeblocks-cloud']
        self.assertTrue(templates)
        self.assertTrue(all(c[2] == str(self.source) and '--version' not in c for c in templates))

    def test_source_missing_image_fails(self):
        self.manifest['kubeblocks-cloud'][0]['images'].remove('apecloud/dms:1.2.0')
        self.assert_fails('image:apecloud/dms:1.2.0')

    def test_source_requires_lock(self):
        (self.source / 'Chart.lock').unlink()
        self.assert_fails('requires Chart.yaml and Chart.lock')

    def test_source_rejects_dependency_version_drift_from_lock(self):
        chart = self.source / 'Chart.yaml'
        chart.write_text(chart.read_text().replace('version: 1.2.0', 'version: 1.2.1'))
        self.assert_fails('out of sync')
        self.assertFalse(any(c[0] == 'template' for c in self.calls()))

    def test_source_preserves_aliyun_registry_mapping(self):
        template = self.source.parent / 'dms' / 'templates' / 'pod.yaml'
        template.write_text(template.read_text().replace('docker.io/', 'apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/'))
        self.assert_passes()
        self.assertIn('check image: apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/dms:1.2.0', self.output)

    def test_source_dependency_failure_does_not_fallback(self):
        self.assert_fails('', FAIL_BUILD='1')
        self.assertFalse(any(c[0] == 'template' for c in self.calls()))

    def test_source_render_failure_does_not_fallback(self):
        self.assert_fails('helm template failed after 10 retries', FAIL_RENDER='1')
        self.assertTrue(all(c[2] == str(self.source) for c in self.calls() if c[0] == 'template'))

    def test_source_empty_render_fails(self):
        self.assert_fails('no images extracted after 10 retries', EMPTY_RENDER='1')

    def test_source_preserves_other_chart_checks(self):
        self.manifest['other'] = [{'version': '1.0.0', 'images': ['apecloud/other:1.0.0']}]
        self.assert_passes()
        self.assertTrue(any(c[0:2] == ['template', 'other'] and '--version' in c for c in self.calls()))
        self.manifest['other'][0]['images'] = []
        self.assert_fails('image:apecloud/other:1.0.0')

    def test_source_preserves_engine_and_addon_image_checks(self):
        self.manifest['engine'] = [{'version': '1.0.0', 'type': 'engine',
                                  'serviceVersions': ['1.0'], 'images': ['apecloud/engine:1.0']}]
        (self.root / 'check-engine.py').write_text(
            "from pathlib import Path\nPath('images-engine-1.0.0.yaml').write_text('engine:\\n- images: [apecloud/engine:1.0]\\n')\n")
        self.assert_fails('apecloud/apecloud-addon-charts:engine-1.0.0')
        self.manifest['kubeblocks-cloud'][0]['images'].append('apecloud/apecloud-addon-charts:engine-1.0.0')
        self.assert_passes()
        self.assertIn('check engine image (engine 1.0.0)', self.output)

    def test_source_and_published_modes_are_exclusive(self):
        self.assert_fails('mutually exclusive', version='v9.1.0')

    def test_published_requires_matching_manifest_version(self):
        self.assert_fails('does not match manifest version', source=False, version='v9.1.1')

    def test_published_missing_chart_fails_instead_of_skipping(self):
        self.assert_fails('chart version not found', source=False, version='v9.1.0', MISSING_PUBLISHED='1')
        self.assertNotIn('skipping', self.output)

    def test_default_published_cloud_missing_chart_also_fails(self):
        self.assert_fails('chart version not found', source=False, MISSING_PUBLISHED='1')

    def test_published_old_dms_fails(self):
        self.assert_fails('image:apecloud/dms:1.1.0', source=False, version='v9.1.0')

    def test_published_checks_core_defaults_and_registry_mapping(self):
        self.env['PUBLISHED_CHART'] = str(self.source)
        self.assert_passes(source=False, version='v9.1.0')
        (self.source / 'values.yaml').write_text('appTag: v9.0.0\n')
        self.assert_fails('image:apecloud/apiserver:v9.0.0', source=False, version='v9.1.0')
        self.assertFalse(any(any('images.apiserver.tag' in x for x in c) for c in self.calls()))

    def test_explicit_mode_requires_cloud_manifest_entry(self):
        self.manifest = {}
        self.assert_fails('exactly one kubeblocks-cloud')

    def test_source_rejects_invalid_manifest_versions_before_rendering(self):
        for version in ('', None, '  ', 'v9.1.0 v9.2.0', '|', 'v9.1.0|v9.2.0', [], {}, 91):
            with self.subTest(version=version):
                self.manifest['kubeblocks-cloud'][0]['version'] = version
                self.assert_fails('nonempty string manifest version')
                self.assertFalse(any(c[0] == 'template' for c in self.calls()))
        del self.manifest['kubeblocks-cloud'][0]['version']
        self.assert_fails('nonempty string manifest version')


class WorkflowContractTests(unittest.TestCase):
    def test_modes_are_exposed_for_both_workflow_entrypoints(self):
        workflow = SCRIPT.parent.parent / 'workflows' / 'manifests-charts-image-check.yml'
        content = workflow.read_text()
        self.assertEqual(len(re.findall(r'^      CLOUD_CHART_PATH:', content, re.M)), 2)
        self.assertEqual(len(re.findall(r'^      CLOUD_CHART_VERSION:', content, re.M)), 2)
        self.assertIn('CLOUD_CHART_PATH: ${{ inputs.CLOUD_CHART_PATH }}', content)
        self.assertIn('CLOUD_CHART_VERSION: ${{ inputs.CLOUD_CHART_VERSION }}', content)

    def test_release_can_publish_the_checked_source_ref(self):
        workflow = SCRIPT.parent.parent / 'workflows' / 'release-version.yml'
        content = workflow.read_text()
        self.assertEqual(content.count('      SOURCE_REF:'), 2)
        self.assertIn('ref: ${{ inputs.SOURCE_REF || env.CUR_BRANCH }}', content)
        self.assertIn('ref: ${{ inputs.SOURCE_REF || github.ref_name }}', content)


if __name__ == '__main__':
    unittest.main()
