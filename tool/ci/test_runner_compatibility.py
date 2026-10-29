"""Every job must run on a runner that supports the tools it calls.

The DEV allocation job once ran ios_signing.py (macOS only) on Ubuntu and failed
at startup. These checks fail such a change before it reaches GitHub.
"""
import contextlib
import io
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import apple_api_key as api_key
import ios_signing

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / '.github/workflows'
# Tools that exist only on macOS runners.
MACOS_ONLY = ('ios_signing.py', 'xcodebuild', 'ditto ', 'codesign', 'archive_flavor.py',
              'prepare_archive.py', 'export_ipa.py', 'fastlane ios testflight_channel',
              'fastlane ios beta', 'fastlane ios submit')
# Operations that must stay API-only so they can run on Linux.
LINUX_API_LANES = ('fastlane ios allocate_build',)


def jobs(path):
    text = path.read_text(encoding='utf-8').replace('\r\n', '\n')
    section = text.split('\njobs:\n', 1)[1]
    parts = re.split(r'(?m)^  ([a-z_][a-z0-9_-]*):\n', section)
    return dict(zip(parts[1::2], parts[2::2]))


def runner(body):
    return re.search(r'(?m)^    runs-on: (\S+)', body)[1]


class WorkflowRunnerTests(unittest.TestCase):
    def test_macos_only_tools_run_only_on_macos(self):
        for path in sorted(WORKFLOWS.glob('*.y*ml')):
            for name, body in jobs(path).items():
                if 'runs-on:' not in body:
                    continue
                used = [tool for tool in MACOS_ONLY if tool in body]
                if used:
                    self.assertTrue(runner(body).startswith('macos'),
                                    f'{path.name}:{name} runs {used} on {runner(body)}')

    def test_api_only_jobs_run_on_linux_without_the_signing_script(self):
        for workflow in ('ios-testflight.yaml', 'ios-release.yaml'):
            body = jobs(WORKFLOWS / workflow)['allocate']
            self.assertTrue(runner(body).startswith('ubuntu'), workflow)
            for lane in LINUX_API_LANES:
                self.assertIn(lane, body)
            self.assertIn('python3 tool/ci/apple_api_key.py api-key', body)
            self.assertRegex(body, r'if: always\(\)\n\s+run: python3 tool/ci/apple_api_key.py cleanup')
            self.assertNotIn('ios_signing.py', body)
            for secret in ('IOS_CERTIFICATE', 'IOS_PROVISION_PROFILE', 'APPLE_TEAM_ID'):
                self.assertNotIn(secret, body)

    def test_signing_jobs_stay_on_macos_with_their_cleanup(self):
        for workflow in ('ios-testflight.yaml', 'ios-release.yaml'):
            for name in ('archive', 'deliver'):
                self.assertTrue(runner(jobs(WORKFLOWS / workflow)[name]).startswith('macos'), name)
            deliver = jobs(WORKFLOWS / workflow)['deliver']
            self.assertRegex(deliver, r'if: always\(\)\n\s+run: python3 tool/ci/ios_signing.py cleanup')

    def test_lane_commands_are_not_hard_wired_to_macos(self):
        fastfile = (ROOT / 'fastlane/Fastfile').read_text(encoding='utf-8')
        lane = fastfile.split('lane :allocate_build do', 1)[1].split('\n  end\n', 1)[0]
        for forbidden in ('/usr/bin', 'security ', 'xcodebuild', 'codesign', 'keychain'):
            self.assertNotIn(forbidden, lane)
        self.assertIn('x86_64-linux', (ROOT / 'Gemfile.lock').read_text(encoding='utf-8'))


class AppleApiKeyTests(unittest.TestCase):
    def execute(self, operation='api-key', key='cHJpdmF0ZQ==', failure=None):
        with tempfile.TemporaryDirectory() as directory:
            env_file = Path(directory) / 'env'
            values = {'RUNNER_TEMP': directory, 'GITHUB_ENV': str(env_file),
                      'APP_STORE_CONNECT_KEY_BASE64': key}
            error = io.StringIO()
            checked = subprocess.CompletedProcess([], 0, b'', b'')

            def fake(*args, **kwargs):
                if failure:
                    raise subprocess.CalledProcessError(1, 'openssl')
                return checked

            with patch.dict(os.environ, values), \
                    patch.object(api_key.shutil, 'which', return_value='/usr/bin/openssl'), \
                    patch.object(api_key.subprocess, 'run', side_effect=fake), \
                    contextlib.redirect_stderr(error):
                result = api_key.main([operation])
                exists = (Path(directory) / 'orangeone-signing').exists()
                exported = env_file.read_text() if env_file.exists() else ''
            return result, error.getvalue(), exported, exists

    def test_installs_key_without_any_macos_tools(self):
        result, output, exported, _ = self.execute()
        self.assertEqual((result, output), (0, ''))
        self.assertIn('APP_STORE_CONNECT_KEY_FILE=', exported)
        self.assertNotIn('cHJpdmF0ZQ', exported)

    def test_cleanup_removes_the_key_folder(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'RUNNER_TEMP': directory}):
            (Path(directory) / 'orangeone-signing').mkdir()
            (Path(directory) / 'orangeone-signing/AuthKey.p8').write_text('x')
            self.assertEqual(api_key.main(['cleanup']), 0)
            self.assertFalse((Path(directory) / 'orangeone-signing').exists())
            self.assertEqual(api_key.main(['cleanup']), 0)

    def test_failures_name_only_the_stage(self):
        for kwargs, stage in (({'key': '%%%'}, 'api-key-decode'), ({'failure': True}, 'api-key-validation')):
            result, output, _, _ = self.execute(**kwargs)
            self.assertEqual(result, 1)
            self.assertEqual(output, 'Apple API key operation failed at stage: ' + stage + '.\n')
        result, output, _, _ = self.execute(operation='install')
        self.assertEqual((result, output), (1, 'Apple API key operation failed at stage: startup.\n'))

    def test_signing_script_names_the_platform_stage_off_macos(self):
        output = io.StringIO()
        with patch.object(ios_signing.sys, 'platform', 'linux'), contextlib.redirect_stderr(output):
            self.assertEqual(ios_signing.main(['api-key']), 1)
        self.assertEqual(output.getvalue(), 'Apple signing operation failed at stage: platform-check.\n')


if __name__ == '__main__':
    unittest.main()
