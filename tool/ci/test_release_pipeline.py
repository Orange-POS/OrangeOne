"""Production release management: release tags, Android APK identity and workflow guards.

No GitHub, Apple or Android signing access: everything runs on synthetic data.
"""
import json
from pathlib import Path
import re
import tempfile
import types
import unittest

import android_apk
import release_tags
from test_workflows import jobs, on_block, read, trigger

ROOT = Path(__file__).resolve().parents[2]
SHA = 'a' * 40
FINGERPRINT = ':'.join(['AB'] * 32)
OTHER = ':'.join(['CD'] * 32)


def event(tag='v1.1.0', **release):
    return {'action': 'published', 'release': {'tag_name': tag, 'draft': False, 'prerelease': False, **release}}


def pubspec_root(folder, version='1.1.0+35'):
    root = Path(folder)
    (root / 'tool/ci').mkdir(parents=True)
    (root / 'config').mkdir()
    (root / 'pubspec.yaml').write_text(f'name: x\nversion: {version}\n')
    (root / 'tool/ci/release_versions.json').write_text(json.dumps({
        'published': [{'version': '1.0.9', 'build': 10, 'evidence': 'x'}], 'reserved': []}))
    (root / 'config/production.example.json').write_text(json.dumps({'APP_ENVIRONMENT': 'production'}))
    return root


class ReleaseTagTest(unittest.TestCase):
    def test_only_exact_version_tags_are_accepted(self):
        self.assertEqual('1.2.3', release_tags.parse_tag('v1.2.3'))
        for tag in ('1.2.3', 'v1.2', 'v1.2.3-rc1', 'V1.2.3', 'release-1', 'v1.2.3.4', 'v01.2.3x', '', None):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release_tags.parse_tag(tag)

    def test_drafts_prereleases_and_other_actions_are_not_approved_releases(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pubspec_root(folder)
            ref = 'refs/tags/v1.1.0'
            self.assertEqual('1.1.0', release_tags.validate_release(event(), ref, SHA, root))
            for bad in (event(draft=True), event(prerelease=True), {**event(), 'action': 'created'},
                        {**event(), 'action': 'edited'}, {}, None):
                with self.subTest(bad=bad), self.assertRaises(ValueError):
                    release_tags.validate_release(bad, ref, SHA, root)

    def test_the_ref_commit_and_pubspec_must_agree_with_the_tag(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pubspec_root(folder)
            for ref, sha in (('refs/heads/main', SHA), ('refs/tags/v1.1.1', SHA),
                             ('refs/tags/v1.1.0', 'abc'), ('refs/tags/v1.1.0', '')):
                with self.subTest(ref=ref, sha=sha), self.assertRaises(ValueError):
                    release_tags.validate_release(event(), ref, sha, root)
            with self.assertRaises(ValueError):
                release_tags.validate_release(event('v1.2.0'), 'refs/tags/v1.2.0', SHA, root)

    def test_the_version_cannot_be_below_one_already_uploaded(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pubspec_root(folder)
            release_tags.require_version_not_below_published('1.0.9', root)
            release_tags.require_version_not_below_published('2.0.0', root)
            with self.assertRaises(ValueError):
                release_tags.require_version_not_below_published('1.0.8', root)

    def test_the_tagged_commit_must_be_on_main(self):
        seen = []
        ok = lambda command, **kw: seen.append(command) or types.SimpleNamespace(returncode=0)
        release_tags.require_on_main(SHA, ok)
        self.assertEqual(['git', 'merge-base', '--is-ancestor', SHA, 'origin/main'], seen[0])
        with self.assertRaises(ValueError):
            release_tags.require_on_main(SHA, lambda *a, **k: types.SimpleNamespace(returncode=1))

    def test_the_android_version_code_must_exceed_every_earlier_release(self):
        files = {'v1.0.9': 'version: 1.0.9+10\n', 'v1.1.0': 'version: 1.1.0+35\n', 'v1.0.8': 'version: 1.0.8+9\n'}

        def git(arguments):
            if arguments[:2] == ['tag', '--list']:
                return 'v1.0.9 v1.1.0 v1.0.8 not-a-release\n'
            return files[arguments[1].split(':')[0]]

        self.assertEqual([10, 9], release_tags.earlier_builds('v1.1.0', git))
        release_tags.require_new_version_code('v1.1.0', 11, git)
        for build in (10, 9, 1):
            with self.assertRaises(ValueError):
                release_tags.require_new_version_code('v1.1.0', build, git)
        release_tags.require_new_version_code('v1.1.0', 1, lambda a: '' if a[0] == 'tag' else '')

    def test_plan_selects_production_and_defaults_to_a_dry_run(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pubspec_root(folder)
            path = Path(folder) / 'event.json'
            path.write_text(json.dumps(event()))
            environ = {'GITHUB_EVENT_NAME': 'release', 'GITHUB_EVENT_PATH': str(path),
                       'GITHUB_REF': 'refs/tags/v1.1.0', 'GITHUB_SHA': SHA}
            git = lambda arguments: '' if arguments[0] == 'tag' else ''
            run = lambda *a, **k: types.SimpleNamespace(returncode=0)
            result = release_tags.plan(environ, root, git, run)
            self.assertEqual('production', result['group'])
            self.assertEqual('ios-production', result['environment'])
            self.assertEqual('1.1.0', result['version'])
            self.assertEqual('35', result['android_version_code'])
            self.assertEqual('34', result['build_floor'])
            self.assertEqual('true', result['dry_run'])
            enabled = release_tags.plan({**environ, 'PRODUCTION_RELEASE_ENABLED': 'true'}, root, git, run)
            self.assertEqual('false', enabled['dry_run'])
            for event_name in ('push', 'workflow_dispatch', 'pull_request', ''):
                with self.subTest(event=event_name), self.assertRaises(ValueError):
                    release_tags.plan({**environ, 'GITHUB_EVENT_NAME': event_name}, root, git, run)

    def test_the_real_repository_state_is_a_valid_release_candidate_shape(self):
        version, build = release_tags.pubspec_version(ROOT)
        self.assertEqual(version, release_tags.parse_tag(f'v{version}'))
        release_tags.validate_flavor_configuration('production', ROOT)
        release_tags.require_version_not_below_published(version, ROOT)
        self.assertGreater(build, release_tags.build_floor(ROOT) - 1)


SIGNATURE = """Verifies
Verified using v1 scheme (JAR signing): false
Verified using v2 scheme (APK Signature Scheme v2): true
Verified using v3 scheme (APK Signature Scheme v3): true
Number of signers: 1
Signer #1 certificate DN: CN=OrangeONE
Signer #1 certificate SHA-256 digest: %s
"""
BADGING = "package: name='com.orangeone.app' versionCode='35' versionName='1.1.0' platformBuildVersionName='15'\n"


def tools(fingerprint=FINGERPRINT, badging=BADGING, signature=SIGNATURE, status=0):
    def run(command, **options):
        if 'apksigner' in command[0]:
            return types.SimpleNamespace(returncode=status, stdout=signature % fingerprint.replace(':', '').lower())
        return types.SimpleNamespace(returncode=0, stdout=badging)
    return {'apksigner': 'apksigner', 'aapt': 'aapt', 'run': run}


class AndroidApkTest(unittest.TestCase):
    def test_fingerprints_are_normalized_and_validated(self):
        self.assertEqual(FINGERPRINT, android_apk.normalize_fingerprint('ab' * 32))
        self.assertEqual(FINGERPRINT, android_apk.normalize_fingerprint(FINGERPRINT.lower()))
        for bad in ('', 'abc', 'zz' * 32, 'ab' * 31, None):
            with self.assertRaises(ValueError):
                android_apk.normalize_fingerprint(bad)

    def keystore_run(self, fingerprint=FINGERPRINT, code=0):
        calls = []

        def run(command, **options):
            calls.append((command, options))
            return types.SimpleNamespace(returncode=code, stdout=f'Certificate fingerprints:\n\t SHA256: {fingerprint}\n')
        return run, calls

    def test_the_keystore_must_open_and_hold_the_pinned_identity(self):
        run, calls = self.keystore_run()
        environ = {'ANDROID_KEYSTORE_PASSWORD': 'never-printed'}
        self.assertEqual(FINGERPRINT, android_apk.verify_keystore('k.jks', 'alias', FINGERPRINT.lower(), environ, run))
        command = calls[0][0]
        self.assertIn('-storepass:env', command)
        self.assertNotIn('never-printed', ' '.join(command))
        run, _ = self.keystore_run(OTHER)
        with self.assertRaises(ValueError) as caught:
            android_apk.verify_keystore('k.jks', 'alias', FINGERPRINT, environ, run)
        self.assertNotIn('never-printed', str(caught.exception))
        run, _ = self.keystore_run(code=1)
        with self.assertRaises(ValueError):
            android_apk.verify_keystore('k.jks', 'alias', FINGERPRINT, environ, run)

    def test_a_correct_apk_passes_and_reports_its_identity(self):
        details = android_apk.verify_apk('a.apk', '1.1.0', 35, FINGERPRINT, **tools())
        self.assertEqual(35, details['version_code'])
        self.assertEqual(FINGERPRINT, details['fingerprint'])
        self.assertTrue(details['schemes'] & {2, 3})

    def test_wrong_identity_package_version_or_debug_builds_are_refused(self):
        cases = {
            'another signer': dict(fingerprint=OTHER),
            'other package': dict(badging=BADGING.replace('com.orangeone.app', 'com.other')),
            'other code': dict(badging=BADGING.replace("versionCode='35'", "versionCode='34'")),
            'other name': dict(badging=BADGING.replace("'1.1.0'", "'1.0.0'")),
            'debuggable': dict(badging=BADGING + 'application-debuggable\n'),
            'rejected': dict(status=1),
            'v1 only': dict(signature=SIGNATURE.replace('v2 scheme (APK Signature Scheme v2): true', 'v2 scheme (APK Signature Scheme v2): false')
                            .replace('v3 scheme (APK Signature Scheme v3): true', 'v3 scheme (APK Signature Scheme v3): false')),
            'two signers': dict(signature=SIGNATURE.replace('signers: 1', 'signers: 2')),
        }
        for name, options in cases.items():
            with self.subTest(case=name), self.assertRaises(ValueError):
                android_apk.verify_apk('a.apk', '1.1.0', 35, FINGERPRINT, **tools(**options))

    def test_updates_need_the_same_signer_and_a_higher_version_code(self):
        old = android_apk.inspect('a.apk', **tools())
        newer = {**old, 'version_code': 36}
        self.assertTrue(android_apk.check_upgrade(old, newer))
        for change in ({'version_code': 35}, {'version_code': 34}, {'fingerprint': OTHER}, {'package': 'com.other'}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                android_apk.check_upgrade(old, {**newer, **change})

    def test_manifest_records_the_hash_and_identity(self):
        with tempfile.TemporaryDirectory() as folder:
            apk = Path(folder) / 'app.apk'
            apk.write_bytes(b'apk')
            details = android_apk.verify_apk(apk, '1.1.0', 35, FINGERPRINT, **tools())
            manifest = android_apk.write_manifest(apk, details, Path(folder) / 'm.json')
            self.assertEqual(android_apk.sha256_file(apk), manifest['sha256'])
            self.assertEqual(manifest, json.loads((Path(folder) / 'm.json').read_text()))
            self.assertEqual(FINGERPRINT, manifest['signing_certificate_sha256'])

    def test_gradle_keeps_the_existing_keystore_wiring_and_fails_closed(self):
        gradle = (ROOT / 'android/app/build.gradle.kts').read_text()
        for name in ('ANDROID_KEYSTORE_PATH', 'ANDROID_KEYSTORE_ALIAS',
                     'ANDROID_KEYSTORE_PRIVATE_KEY_PASSWORD', 'ANDROID_KEYSTORE_PASSWORD'):
            self.assertIn(name, gradle)
        release = gradle.split('getByName("release")', 1)[1].split('getByName("debug")', 1)[0]
        self.assertIn('signingConfigs.getByName("release")', release)
        self.assertNotIn('"debug"', release, 'a release build must never fall back to the debug key')
        self.assertEqual(android_apk.PACKAGE, 'com.orangeone.app')
        self.assertIn(f'applicationId = "{android_apk.PACKAGE}"', gradle)


class ReleaseWorkflowTest(unittest.TestCase):
    NAMES = ('ios-release.yaml', 'android-release.yaml')

    def test_triggers_are_exactly_published_releases(self):
        for name in self.NAMES:
            text = read(name)
            with self.subTest(workflow=name):
                block = on_block(text)
                self.assertEqual('  release:\n    types: [published]\n', block)
                for forbidden in ('push', 'pull_request', 'workflow_dispatch', 'schedule', 'tags:', 'branches:'):
                    self.assertNotIn(forbidden, block)

    def test_no_other_workflow_can_start_on_a_tag_or_release(self):
        for path in (ROOT / '.github/workflows').glob('*.y*ml'):
            if path.name in self.NAMES:
                continue
            with self.subTest(workflow=path.name):
                block = on_block(path.read_text().replace('\r\n', '\n'))
                self.assertNotIn('release:', block)
                self.assertNotIn('tags:', block)

    def test_every_job_is_gated_by_the_release_validation(self):
        for name in self.NAMES:
            text = read(name)
            with self.subTest(workflow=name):
                self.assertIn('run: python3 tool/ci/release_tags.py', text)
                body = jobs(text)
                self.assertEqual({'plan', 'checks'}, {'plan', 'checks'} & set(body))
                for job in set(body) - {'plan'}:
                    self.assertIn('plan', body[job].split('steps:')[0], job)
                self.assertIn('tool/ci/wait_for_checks.py', body['checks'])
                self.assertIn('fetch-depth: 0', body['plan'])
                self.assertNotIn('secrets.', body['plan'] + body['checks'])

    def test_workflows_are_read_only_and_never_persist_credentials(self):
        for name in self.NAMES:
            text = read(name)
            with self.subTest(workflow=name):
                self.assertRegex(text, r'(?m)^permissions:\n  contents: read\n')
                self.assertNotIn('contents: write', text)
                self.assertEqual(text.count('actions/checkout@v4'), text.count('persist-credentials: false'))
                for job, body in jobs(text).items():
                    self.assertRegex(body, r'(?m)^    timeout-minutes: \d+', job)

    def test_ios_release_goes_to_production_testers_only_and_defaults_to_a_dry_run(self):
        text = read('ios-release.yaml')
        body = jobs(text)
        self.assertEqual({'plan', 'checks', 'allocate', 'archive', 'deliver'}, set(body))
        self.assertIn('PRODUCTION_RELEASE_ENABLED', body['plan'])
        self.assertIn('vars.PRODUCTION_RELEASE_ENABLED', body['deliver'])
        self.assertNotIn('vars.TESTFLIGHT_CD_ENABLED', text)
        self.assertIn('group: testflight-cd', text, 'serialized with the DEV/STG build numbers')
        self.assertIn('cancel-in-progress: false', text)
        for job in ('allocate', 'deliver'):
            self.assertIn('environment: ${{ needs.plan.outputs.environment }}', body[job])
        for job in ('plan', 'checks', 'archive'):
            self.assertNotRegex(body[job], r'(?m)^    environment:')
            self.assertNotIn('secrets.', body[job])
        self.assertIn('cache: false', body['archive'])
        self.assertIn('--flavor production', body['archive'])
        self.assertIn('fastlane ios testflight_channel', body['deliver'])
        self.assertNotIn('submit', text.replace('Submission', '').replace('submission', ''))
        self.assertIn('if: always()', body['deliver'].split('ios_signing.py cleanup')[0].rsplit('- name', 1)[1])

    def test_production_environment_and_group_come_from_the_validated_plan(self):
        self.assertEqual('ios-production', release_tags.ENVIRONMENT)
        self.assertEqual('production', release_tags.GROUP)
        self.assertNotIn('ios-app-store', read('ios-release.yaml'))

    def test_android_release_uses_the_existing_keystore_and_stays_private(self):
        text = read('android-release.yaml')
        body = jobs(text)
        self.assertEqual({'plan', 'checks', 'apk'}, set(body))
        self.assertIn('environment: android-production', body['apk'])
        for secret in ('ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEYSTORE_ALIAS',
                       'ANDROID_KEYSTORE_PRIVATE_KEY_PASSWORD', 'ANDROID_SIGNING_CERT_SHA256'):
            self.assertIn(f'secrets.{secret}', body['apk'])
        self.assertLess(text.index('android_apk.py keystore'), text.index('flutter build apk'))
        self.assertLess(text.index('flutter build apk'), text.index('android_apk.py verify'))
        self.assertLess(text.index('android_apk.py verify'), text.index('upload-artifact'))
        self.assertIn('--release --flavor production', text)
        for public in ('gh release', 'softprops', 'action-gh-release', 'upload-release-asset', 'contents: write'):
            self.assertNotIn(public, text)
        self.assertIn('if: always()', body['apk'].rsplit('- name', 1)[1])
        self.assertNotIn('secrets.', body['plan'] + body['checks'])

    def test_production_deploys_never_start_from_branch_pushes(self):
        for name in ('ios.yaml', 'ios-testflight.yaml'):
            with self.subTest(workflow=name):
                text = read(name)
                self.assertNotIn('release:', on_block(text))
                for job, content in jobs(text).items():
                    if 'environment: ios-production' in content:
                        self.assertIn("github.event_name == 'workflow_dispatch'", content)
        self.assertNotIn('ios-production', read('ios-testflight.yaml'))
        self.assertIsNone(trigger(read('ios-release.yaml'), 'push'))

    def test_fastlane_release_ref_pattern_matches_the_python_tag_rule(self):
        fastfile = (ROOT / 'fastlane/Fastfile').read_text()
        self.assertIn(r"RELEASE_REF = %r{\Arefs/tags/v\d+\.\d+\.\d+\z}", fastfile)
        self.assertRegex('v1.2.3', release_tags.TAG)


if __name__ == '__main__':
    unittest.main()
