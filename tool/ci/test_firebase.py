import base64
import contextlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import unittest
import zipfile

import firebase_config as fc
import release_tags
import testflight_channels as channels
import upload_flutter_symbols as symbols
from test_workflows import jobs, read

ROOT = Path(__file__).resolve().parents[2]
DEV = 'orangeone-development'
PROD = 'orangeone-production'
SENTINEL = 'PRIVATE_API_KEY_SENTINEL'


def android_json(project, package, app_id='1:1:android:abc'):
    return json.dumps({
        'project_info': {'project_id': project},
        'client': [{'client_info': {'mobilesdk_app_id': app_id,
                                    'android_client_info': {'package_name': package}}}],
        'api_key': SENTINEL,
    }).encode()


def ios_plist(project, bundle=fc.IOS_BUNDLE_ID):
    return plistlib.dumps({'PROJECT_ID': project, 'BUNDLE_ID': bundle,
                           'GOOGLE_APP_ID': '1:1:ios:abc', 'API_KEY': SENTINEL})


def b64(data):
    return base64.b64encode(data).decode()


def env(project, data=None, production=PROD):
    values = {'FIREBASE_PROJECT_ID': project, 'FIREBASE_PRODUCTION_PROJECT_ID': production}
    if data is not None:
        values['FIREBASE_CONFIG_BASE64'] = b64(data)
    return values


class ConfigTest(unittest.TestCase):
    def write(self, platform, flavor, environ):
        with tempfile.TemporaryDirectory() as root:
            target = fc.write(platform, flavor, environ, root)
            return target.read_bytes(), target.relative_to(root).as_posix()

    def test_every_flavor_and_platform_uses_its_environment_project(self):
        cases = {'development': (DEV, 'com.orangeone.app.dev'), 'staging': (DEV, 'com.orangeone.app.stg'),
                 'production': (PROD, 'com.orangeone.app')}
        for flavor, (project, package) in cases.items():
            data, path = self.write('android', flavor, env(project, android_json(project, package)))
            self.assertEqual(f'android/app/src/{flavor}/google-services.json', path)
            self.assertIn(project.encode(), data)
            _, path = self.write('ios', flavor, env(project, ios_plist(project)))
            self.assertEqual(f'ios/config/{flavor}/GoogleService-Info.plist', path)

    def test_production_firebase_can_never_reach_development_or_staging(self):
        for flavor in ('development', 'staging'):
            for platform, data in (('ios', ios_plist(PROD)),
                                   ('android', android_json(PROD, fc.ANDROID_PACKAGES[flavor]))):
                with self.assertRaises(fc.ConfigError, msg=(flavor, platform)):
                    fc.validated(platform, flavor, env(PROD, data))
        with self.assertRaises(fc.ConfigError):
            fc.expected_project('staging', env(PROD))

    def test_production_must_use_the_production_project(self):
        with self.assertRaises(fc.ConfigError):
            fc.validated('ios', 'production', env(DEV, ios_plist(DEV)))
        fc.validated('ios', 'production', env(PROD, ios_plist(PROD)))

    def test_the_file_must_match_the_environment_variable(self):
        for platform, data in (('ios', ios_plist(PROD)), ('android', android_json(PROD, 'com.orangeone.app.dev'))):
            with self.assertRaises(fc.ConfigError):
                fc.validated(platform, 'development', env(DEV, data))

    def test_ios_always_uses_the_app_store_bundle_id(self):
        with self.assertRaises(fc.ConfigError):
            fc.validated('ios', 'development', env(DEV, ios_plist(DEV, 'ch.orangepos.productscanner.dev')))

    def test_android_needs_the_flavor_package(self):
        with self.assertRaises(fc.ConfigError):
            fc.validated('android', 'staging', env(DEV, android_json(DEV, 'com.orangeone.app.dev')))

    def test_missing_or_malformed_configuration_is_detected(self):
        bad = (
            env(DEV),
            {**env(DEV), 'FIREBASE_CONFIG_BASE64': '%%%'},
            env(DEV, b'not a plist'),
            {'FIREBASE_CONFIG_BASE64': b64(ios_plist(DEV)), 'FIREBASE_PRODUCTION_PROJECT_ID': PROD},
            {'FIREBASE_CONFIG_BASE64': b64(ios_plist(DEV)), 'FIREBASE_PROJECT_ID': DEV},
        )
        for values in bad:
            with self.assertRaises(fc.ConfigError):
                fc.validated('ios', 'development', values)
        with self.assertRaises(fc.ConfigError):
            fc.validated('web', 'development', env(DEV, ios_plist(DEV)))
        with self.assertRaises(fc.ConfigError):
            fc.expected_project('qa', env(DEV))

    def test_export_hands_one_validated_line_to_the_build_job(self):
        data = ios_plist(DEV)
        config, project = fc.export('ios', 'development', env(DEV, data))
        self.assertEqual(data, base64.b64decode(config))
        self.assertEqual(DEV, project)
        self.assertNotIn('\n', config)
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'out'
            values = {**env(DEV, data), 'GITHUB_OUTPUT': str(output)}
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(0, fc.main(['export', 'ios', 'development'], values))
            self.assertEqual([f'config={config}', f'project_id={DEV}'], output.read_text().splitlines())

    def test_cli_reports_a_fixed_reason_without_contents(self):
        error, output = io.StringIO(), io.StringIO()
        values = {**env(PROD, ios_plist(PROD)), 'GITHUB_OUTPUT': os.devnull}
        with contextlib.redirect_stderr(error), contextlib.redirect_stdout(output):
            self.assertEqual(1, fc.main(['export', 'ios', 'development'], values))
            self.assertEqual(1, fc.main(['bogus'], {}))
            self.assertEqual(1, fc.main([], {}))
        self.assertNotIn(SENTINEL, error.getvalue() + output.getvalue())
        self.assertIn('must not use the production Firebase project', error.getvalue())


class VerifyBuildTest(unittest.TestCase):
    def test_ios_archive_must_carry_its_environments_plist(self):
        with tempfile.TemporaryDirectory() as root:
            app = Path(root) / 'Products/Applications/Runner.app'
            app.mkdir(parents=True)
            with self.assertRaises(fc.ConfigError):
                fc.verify_ios(root, 'development', env(DEV))
            (app / 'GoogleService-Info.plist').write_bytes(ios_plist(DEV))
            fc.verify_ios(root, 'development', env(DEV))
            fc.verify_ios(app, 'staging', env(DEV))
            with self.assertRaises(fc.ConfigError):
                fc.verify_ios(root, 'production', env(PROD))
            (app / 'GoogleService-Info.plist').write_bytes(ios_plist(PROD))
            with self.assertRaises(fc.ConfigError):
                fc.verify_ios(root, 'staging', env(DEV))

    def apk(self, folder, resources):
        path = Path(folder) / 'app.apk'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('resources.arsc', resources)
        return path

    def test_android_apk_names_its_project_and_non_production_never_production(self):
        with tempfile.TemporaryDirectory() as folder:
            fc.verify_android(self.apk(folder, PROD.encode()), 'production', env(PROD))
            fc.verify_android(self.apk(folder, DEV.encode('utf-16-le')), 'development', env(DEV))
            for resources, flavor, project in ((b'nothing', 'production', PROD), (DEV.encode(), 'production', PROD),
                                               (PROD.encode(), 'staging', DEV),
                                               (DEV.encode() + PROD.encode(), 'development', DEV)):
                with self.assertRaises(fc.ConfigError, msg=(resources, flavor)):
                    fc.verify_android(self.apk(folder, resources), flavor, env(project))
            with self.assertRaises(fc.ConfigError):
                fc.verify_android(Path(folder) / 'missing.apk', 'production', env(PROD))


class SymbolUploadTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        root = Path(self.folder.name)
        (root / 'symbols').mkdir()
        (root / 'symbols/app.symbols').write_text('x')
        self.config = root / 'GoogleService-Info.plist'
        self.config.write_bytes(ios_plist(DEV))
        self.symbols = root / 'symbols'

    def test_without_the_service_account_it_warns_and_does_not_fail(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = symbols.main([str(self.symbols), str(self.config)], {}, run=self.fail)
        self.assertEqual(0, code)
        self.assertIn('::warning::', output.getvalue())

    def test_upload_is_pinned_scoped_to_the_build_and_removes_credentials(self):
        seen = {}

        def run(command, **options):
            seen['command'], seen['env'] = command, options['env']
            seen['file'] = Path(options['env']['GOOGLE_APPLICATION_CREDENTIALS'])
            seen['content'] = seen['file'].read_text()
            return subprocess.CompletedProcess(command, 0)

        with contextlib.redirect_stdout(io.StringIO()):
            code = symbols.main([str(self.symbols), str(self.config)],
                                {'FIREBASE_SERVICE_ACCOUNT_JSON': SENTINEL}, run=run)
        self.assertEqual(0, code)
        self.assertEqual(['npx', '--yes', symbols.FIREBASE_TOOLS, 'crashlytics:symbols:upload',
                          '--app=1:1:ios:abc', str(self.symbols)], seen['command'])
        self.assertRegex(symbols.FIREBASE_TOOLS, r'^firebase-tools@\d+\.\d+\.\d+$')
        self.assertEqual(SENTINEL, seen['content'])
        self.assertFalse(seen['file'].exists())
        self.assertNotIn(SENTINEL, ' '.join(seen['command']))

    def test_failures_name_only_the_stage(self):
        def run(command, **options):
            raise subprocess.CalledProcessError(1, command, output=SENTINEL.encode())

        error = io.StringIO()
        with contextlib.redirect_stderr(error):
            code = symbols.main([str(self.symbols), str(self.config)],
                                {'FIREBASE_SERVICE_ACCOUNT_JSON': SENTINEL}, run=run)
            missing = symbols.main([str(Path(self.folder.name) / 'none'), str(self.config)], {}, run=run)
        self.assertEqual((1, 1), (code, missing))
        self.assertNotIn(SENTINEL, error.getvalue())

    def test_android_app_id_comes_from_google_services_json(self):
        path = Path(self.folder.name) / 'google-services.json'
        path.write_bytes(android_json(PROD, 'com.orangeone.app', app_id='1:9:android:zz'))
        self.assertEqual('1:9:android:zz', symbols.app_id(path))

    def fail(self, *args, **kwargs):
        raise AssertionError('must not run')


def step(job, name):
    """The text of one named step of a job."""
    return job.split(f'- name: {name}')[1].split('\n      - ')[0]


class EnvironmentMappingTest(unittest.TestCase):
    """Which GitHub environment supplies which Firebase project."""

    def jobs(self, name):
        return jobs(read(name))

    def test_ios_environments_come_from_the_validated_plan(self):
        for name in ('ios-testflight.yaml', 'ios-release.yaml'):
            allocate = self.jobs(name)['allocate']
            self.assertIn('environment: ${{ needs.plan.outputs.environment }}', allocate)
            firebase = step(allocate, "Validate this environment's Firebase configuration")
            for variable in ('FIREBASE_CONFIG_BASE64', 'FIREBASE_PROJECT_ID', 'FIREBASE_PRODUCTION_PROJECT_ID'):
                self.assertIn(f'{variable}: ${{{{ vars.{variable} }}}}', firebase)
            self.assertNotIn('secrets.', firebase)
            self.assertIn('firebase_config: ${{ steps.firebase.outputs.config }}', allocate)
        self.assertIn('firebase_config.py export ios "$CHANNEL_FLAVOR"', read('ios-testflight.yaml'))
        self.assertIn('firebase_config.py export ios production', read('ios-release.yaml'))
        # develop -> ios-development, staging -> ios-staging, releases -> ios-production
        self.assertEqual('ios-development', channels.CHANNELS['refs/heads/develop']['environment'])
        self.assertEqual('ios-staging', channels.CHANNELS['refs/heads/staging']['environment'])
        self.assertEqual('ios-production', release_tags.ENVIRONMENT)

    def test_android_environments(self):
        production = self.jobs('android-release.yaml')['apk']
        self.assertIn('environment: android-production', production)
        self.assertEqual('android-production', release_tags.ANDROID_ENVIRONMENT)
        self.assertIn('FIREBASE_CONFIG_BASE64: ${{ vars.FIREBASE_CONFIG_BASE64 }}', production)
        development_text = read('android-development.yaml')
        development = self.jobs('android-development.yaml')['apk']
        self.assertIn('environment: android-development', development)
        self.assertIn('FIREBASE_CONFIG_BASE64: ${{ vars.FIREBASE_CONFIG_BASE64 }}', development)
        self.assertIn('firebase_config.py write android development', development)
        self.assertRegex(development_text, r'(?m)^    branches: \[develop\]$')
        self.assertNotIn('release:', development_text.split('jobs:')[0])
        for part in jobs(development_text).values():
            self.assertIn("github.ref == 'refs/heads/develop'", part)

    def test_android_jobs_never_receive_apple_credentials(self):
        for name in ('android-release.yaml', 'android-development.yaml'):
            text = read(name)
            for secret in ('IOS_', 'APPLE_', 'APP_STORE_CONNECT', 'PROVISION'):
                self.assertNotIn(secret, text, name)
        self.assertNotIn('ANDROID_KEYSTORE', read('android-development.yaml'))
        self.assertNotIn('FIREBASE_SERVICE_ACCOUNT_JSON', read('android-development.yaml'))

    def test_development_never_sees_production_environments(self):
        text = read('android-development.yaml')
        for forbidden in ('android-production', 'ios-production', 'secrets.'):
            self.assertNotIn(forbidden, text)
        self.assertNotIn('ios-production', read('ios-testflight.yaml'))
        self.assertNotIn('ios-staging', read('ios-release.yaml'))

    def test_archive_jobs_stay_credential_free_and_get_the_config_from_allocate(self):
        for name in ('ios-testflight.yaml', 'ios-release.yaml'):
            archive = self.jobs(name)['archive']
            self.assertNotIn('secrets.', archive, name)
            self.assertNotRegex(archive, r'(?m)^    environment:')
            self.assertIn('FIREBASE_CONFIG_BASE64: ${{ needs.allocate.outputs.firebase_config }}', archive)
            self.assertIn('FIREBASE_PROJECT_ID: ${{ needs.allocate.outputs.firebase_project_id }}', archive)
            self.assertIn('vars.FIREBASE_PRODUCTION_PROJECT_ID', archive)
            self.assertNotIn('vars.FIREBASE_CONFIG_BASE64', archive)
        legacy = self.jobs('ios.yaml')
        self.assertIn('environment: ios-production', legacy['firebase'])
        self.assertIn("github.ref == 'refs/heads/main'", legacy['firebase'])
        self.assertIn('needs: [release_checks, firebase]', legacy['candidate'])
        self.assertIn('needs.firebase.outputs.config', legacy['candidate'])
        self.assertNotRegex(legacy['candidate'], r'(?m)^    environment:')

    def test_distributable_builds_write_verify_and_fail_without_configuration(self):
        release = self.jobs('ios-release.yaml')['archive']
        self.assertLess(release.index('firebase_config.py write ios production'), release.index('flutter build ipa'))
        self.assertLess(release.index('flutter build ipa'), release.index('firebase_config.py verify-ios'))
        android = self.jobs('android-release.yaml')['apk']
        self.assertIn("FIREBASE_CONFIG_REQUIRED: 'true'", android)
        self.assertLess(android.index('firebase_config.py write android production'), android.index('flutter build apk'))
        self.assertLess(android.index('flutter build apk'), android.index('firebase_config.py verify-android'))
        development = self.jobs('android-development.yaml')['apk']
        self.assertIn("FIREBASE_CONFIG_REQUIRED: 'true'", development)
        self.assertLess(development.index('write android development'), development.index('flutter build apk'))
        self.assertLess(development.index('flutter build apk'), development.index('verify-android'))
        legacy = read('ios.yaml')
        self.assertLess(legacy.index('firebase_config.py write ios production'), legacy.index('Archive selected source'))
        self.assertIn('firebase_config.py verify-ios', legacy)

    def test_symbols_upload_only_for_real_deliveries(self):
        for name in ('ios-testflight.yaml', 'ios-release.yaml'):
            jobs_ = self.jobs(name)
            self.assertIn("needs.plan.outputs.dry_run == 'false' && 'true' || 'false'",
                          jobs_['archive'], 'dSYMs only for non-dry-runs')
            deliver = jobs_['deliver']
            upload = deliver.split('Upload the Dart symbols')[1].split('- name')[0]
            self.assertIn("if: needs.plan.outputs.dry_run == 'false'", upload)
            self.assertIn('secrets.FIREBASE_SERVICE_ACCOUNT_JSON', upload)
            self.assertLess(deliver.index('Upload the Dart symbols'), deliver.index('fastlane ios testflight_channel'))

    def test_credentials_are_not_persisted_and_service_account_stays_in_signing_jobs(self):
        for name in ('ios-testflight.yaml', 'ios-release.yaml', 'android-release.yaml', 'android-development.yaml'):
            text = read(name)
            self.assertEqual(text.count('actions/checkout@v4'), text.count('persist-credentials: false'), name)
        for name in ('ios-testflight.yaml', 'ios-release.yaml'):
            for job in ('plan', 'checks', 'allocate', 'archive'):
                self.assertNotIn('FIREBASE_SERVICE_ACCOUNT_JSON', self.jobs(name)[job], (name, job))


class NativeWiringTest(unittest.TestCase):
    def test_ios_project_copies_config_and_uploads_symbols_for_the_runner_only(self):
        project = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        runner = re.search(r'/\* Runner \*/ = \{\s*isa = PBXNativeTarget;.*?buildPhases = \((.*?)\);', project, re.S)[1]
        self.assertIn('[OrangeONE] Firebase Configuration', runner)
        self.assertIn('[OrangeONE] Crashlytics Symbols', runner)
        tests = re.search(r'/\* RunnerTests \*/ = \{\s*isa = PBXNativeTarget;.*?buildPhases = \((.*?)\);', project, re.S)[1]
        self.assertNotIn('OrangeONE', tests)
        self.assertIn('config/${flavor}/GoogleService-Info.plist', project)
        self.assertIn('CRASHLYTICS_UPLOAD_SYMBOLS', project)
        self.assertIn('PLATFORM_NAME', project)

    def test_ios_deployment_target_meets_firebase(self):
        project = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        targets = {float(v) for v in re.findall(r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);', project)}
        self.assertEqual({15.0}, targets)
        self.assertIn('<string>15.0</string>', (ROOT / 'ios/Flutter/AppFrameworkInfo.plist').read_text())

    def test_android_applies_firebase_only_with_a_configuration_or_when_required(self):
        gradle = (ROOT / 'android/app/build.gradle.kts').read_text()
        self.assertIn('FIREBASE_CONFIG_REQUIRED', gradle)
        self.assertRegex(gradle, r'if \(firebaseRequired \|\| firebaseConfigPresent\) \{\s*apply\(plugin = "com\.google\.gms\.google-services"\)')
        self.assertIn('com.google.firebase.crashlytics', gradle)
        settings = (ROOT / 'android/settings.gradle.kts').read_text()
        self.assertRegex(settings, r'com\.google\.gms\.google-services"\) version "[\d.]+" apply false')
        self.assertRegex(settings, r'com\.google\.firebase\.crashlytics"\) version "[\d.]+" apply false')

    def test_configuration_files_are_ignored_and_not_tracked(self):
        ignore = (ROOT / '.gitignore').read_text()
        self.assertIn('android/app/src/*/google-services.json', ignore)
        self.assertIn('ios/config/*/GoogleService-Info.plist', ignore)
        tracked = subprocess.run(['git', 'ls-files'], cwd=ROOT, capture_output=True, text=True).stdout
        self.assertNotRegex(tracked, r'google-services\.json|GoogleService-Info\.plist')
        self.assertNotRegex(tracked, r'firebase_app_id_file\.json|firebase_options\.dart')


if __name__ == '__main__':
    unittest.main()
