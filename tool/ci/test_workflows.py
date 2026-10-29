"""Guard the CI trigger policy and the unchanged signing protections.

Text based on purpose: no YAML dependency, so it runs on a bare runner.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / '.github/workflows'
INTEGRATION = '[main, develop, staging]'
CI = ('android.yaml', 'ios.yaml', 'license_check.yaml', 'flutter_tests.yml')


def read(name):
    return (DIRECTORY / name).read_text().replace('\r\n', '\n')


def on_block(text):
    match = re.search(r'^on:\n(.*?)(?=^\S)', text, re.S | re.M)
    assert match, 'workflow has no on: block'
    return match.group(1)


def trigger(text, name):
    """The indented lines of one trigger (empty string when it has none)."""
    match = re.search(rf'^  {name}:[^\n]*\n((?:    .*\n|\n)*)', on_block(text), re.M)
    return match.group(1) if match else None


def jobs(text):
    body = text.split('\njobs:\n', 1)[1]
    parts = re.split(r'^  ([A-Za-z0-9_-]+):\n', body, flags=re.M)
    return dict(zip(parts[1::2], parts[2::2]))


class TriggerPolicyTest(unittest.TestCase):
    def test_commits_run_each_workflow_once(self):
        for name in CI:
            with self.subTest(workflow=name):
                text = read(name)
                push = trigger(text, 'push')
                self.assertIsNotNone(push, 'push trigger missing')
                self.assertIn(f'branches: {INTEGRATION}', push,
                              'push must be limited to the integration branches, '
                              'else a PR commit runs on push and on pull_request')
                self.assertIsNotNone(trigger(text, 'pull_request'))
                self.assertIn(f'branches: {INTEGRATION}', trigger(text, 'merge_group'))

    def test_native_and_license_pull_requests_target_integration_branches(self):
        for name in ('android.yaml', 'ios.yaml', 'license_check.yaml'):
            with self.subTest(workflow=name):
                self.assertIn(f'branches: {INTEGRATION}', trigger(read(name), 'pull_request'))

    def test_unprotected_triggers_are_never_used(self):
        for path in DIRECTORY.glob('*.y*ml'):
            with self.subTest(workflow=path.name):
                text = path.read_text()
                self.assertNotIn('pull_request_target', text)
                self.assertNotIn('workflow_run:', text)

    def test_only_manual_dispatch_can_sign_or_upload(self):
        # Stage 1 adds no branch, tag or release trigger to the signing jobs.
        ios = read('ios.yaml')
        self.assertIn('workflow_dispatch:', on_block(ios))
        self.assertNotIn('release:', on_block(ios))
        self.assertNotIn('tags:', on_block(ios))
        for name, body in jobs(ios).items():
            if 'environment:' in body:
                with self.subTest(job=name):
                    self.assertIn("github.event_name == 'workflow_dispatch'", body)


def branches(text, name):
    """Branch filter of a trigger: a list, or None when every branch matches."""
    block = trigger(text, name)
    if block is None:
        return []
    match = re.search(r'branches: \[([^\]]*)\]', block)
    return [item.strip() for item in match.group(1).split(',')] if match else None


def runs(name, event, branch):
    allowed = branches(read(name), event)
    return allowed is None or branch in allowed


class EventSimulationTest(unittest.TestCase):
    """Replays the events GitHub sends for typical pushes and pull requests."""

    def count(self, name, events):
        return sum(runs(name, event, branch) for event, branch in events)

    def test_a_pull_request_commit_runs_every_workflow_exactly_once(self):
        # Pushing a feature branch emits `push` (feature/x) and then
        # `pull_request` (base main, develop or staging).
        for base in ('main', 'develop', 'staging'):
            for name in CI:
                with self.subTest(workflow=name, base=base):
                    self.assertEqual(
                        1, self.count(name, [('push', 'feature/x'), ('pull_request', base)]))

    def test_integration_branch_pushes_run_every_workflow_once(self):
        for branch in ('main', 'develop', 'staging'):
            for name in CI:
                with self.subTest(workflow=name, branch=branch):
                    self.assertEqual(1, self.count(name, [('push', branch)]))

    def test_feature_pushes_without_a_pull_request_run_nothing(self):
        for name in CI:
            with self.subTest(workflow=name):
                self.assertEqual(0, self.count(name, [('push', 'feature/x')]))

    def test_dependabot_branches_run_once_through_their_pull_request(self):
        for name in CI:
            with self.subTest(workflow=name):
                self.assertEqual(1, self.count(name, [
                    ('push', 'dependabot/pub/go_router-18.1.1'), ('pull_request', 'main')]))


class SecurityTest(unittest.TestCase):
    def test_workflows_are_read_only_by_default(self):
        for name in CI:
            with self.subTest(workflow=name):
                self.assertRegex(read(name), r'(?m)^permissions:\n  contents: read\n')

    def test_secrets_exist_only_in_protected_environment_jobs(self):
        for name in CI:
            text = read(name)
            for job, body in jobs(text).items():
                if 'secrets.' in body:
                    with self.subTest(workflow=name, job=job):
                        self.assertEqual(name, 'ios.yaml')
                        self.assertRegex(body, r'(?m)^    environment: ios-(production|app-store)$')
        for name in ('android.yaml', 'flutter_tests.yml', 'license_check.yaml'):
            with self.subTest(workflow=name):
                self.assertNotIn('secrets.', read(name))

    def test_signing_protections_of_ios_are_unchanged(self):
        ios = jobs(read('ios.yaml'))
        self.assertEqual(set(ios), {
            'ios', 'release_checks', 'candidate', 'beta', 'distribute_existing', 'submit'})
        self.assertNotIn('secrets.', ios['candidate'])
        self.assertNotIn('environment:', ios['candidate'])
        self.assertNotIn('environment:', ios['ios'])
        self.assertIn('persist-credentials: false', ios['candidate'])
        self.assertIn('cache: false', ios['candidate'])
        self.assertIn('environment: ios-production', ios['beta'])
        self.assertIn('environment: ios-production', ios['distribute_existing'])
        self.assertIn('environment: ios-app-store', ios['submit'])
        for job in ('beta', 'distribute_existing', 'submit'):
            self.assertIn("github.ref == 'refs/heads/main'", ios[job])
        self.assertIn('cancel-in-progress: ${{ github.event_name != \'workflow_dispatch\' }}',
                      read('ios.yaml'))


class ReliabilityTest(unittest.TestCase):
    def test_every_job_has_a_timeout_and_every_workflow_a_concurrency_group(self):
        for name in CI:
            text = read(name)
            with self.subTest(workflow=name):
                self.assertRegex(text, r'(?m)^concurrency:')
            for job, body in jobs(text).items():
                if 'uses:' in body.split('\n', 1)[0] or re.search(r'(?m)^    uses:', body):
                    continue  # reusable workflow call
                with self.subTest(workflow=name, job=job):
                    self.assertRegex(body, r'(?m)^    timeout-minutes: \d+')

    def test_flavors_are_built_by_android_and_unsigned_ios(self):
        for name, job in (('android.yaml', 'android'), ('ios.yaml', 'ios')):
            with self.subTest(workflow=name):
                body = jobs(read(name))[job]
                self.assertIn('flavor: [development, staging, production]', body)
                self.assertIn('fail-fast: false', body)
                self.assertIn('lib/main_${{ matrix.flavor }}.dart', body)
                self.assertIn('config/${{ matrix.flavor }}.example.json', body)

    def test_one_flutter_version_is_used_everywhere(self):
        versions = set()
        for path in DIRECTORY.glob('*.y*ml'):
            versions |= set(re.findall(r"flutter[-_]version: '([^']+)'", path.read_text()))
        self.assertEqual(len(versions), 1, versions)
        pubspec = (ROOT / 'pubspec.yaml').read_text()
        self.assertIn(f"flutter: '>={versions.pop()} <4.0.0'", pubspec)

    def test_unsigned_ios_builds_run_only_outside_manual_dispatch(self):
        self.assertIn("if: github.event_name != 'workflow_dispatch'", jobs(read('ios.yaml'))['ios'])

    def test_workflows_are_linted_in_ci(self):
        self.assertIn('rhysd/actionlint:', read('flutter_tests.yml'))

    def test_required_status_names_are_stable(self):
        # Branch rulesets require these exact contexts; renaming a job or its
        # matrix key would silently stop them from being reported.
        self.assertIn('name: Format, analyze and test', read('flutter_tests.yml'))
        self.assertIn('  android:', read('android.yaml'))
        self.assertIn('  ios:', read('ios.yaml'))
        self.assertIn('  license_check:', read('license_check.yaml'))


if __name__ == '__main__':
    unittest.main()
