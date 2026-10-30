import base64
import contextlib
import io
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import unittest
import zipfile

import firebase_config as fc
import upload_flutter_symbols as symbols
from test_workflows import jobs, read

ROOT = Path(__file__).resolve().parents[2]
NON = 'orangeone-nonprod'
PROD = 'orangeone-prod'
ENV = {'FIREBASE_PROJECT_ID_NONPRODUCTION': NON, 'FIREBASE_PROJECT_ID_PRODUCTION': PROD}
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


class ConfigWriteTest(unittest.TestCase):
    def write(self, platform, flavor, data, extra=None):
        env = {**ENV, f'FIREBASE_{platform.upper()}_{flavor.upper()}_B64': b64(data), **(extra or {})}
        with tempfile.TemporaryDirectory() as root:
            target = fc.write(platform, flavor, env, root)
            return target.read_bytes(), target.relative_to(root).as_posix()

    def test_every_flavor_and_platform_uses_its_own_project(self):
        cases = {'development': (NON, 'com.orangeone.app.dev'), 'staging': (NON, 'com.orangeone.app.stg'),
                 'production': (PROD, 'com.orangeone.app')}
        for flavor, (project, package) in cases.items():
            data, path = self.write('android', flavor, android_json(project, package))
            self.assertEqual(f'android/app/src/{flavor}/google-services.json', path)
            self.assertIn(project.encode(), data)
            _, path = self.write('ios', flavor, ios_plist(project))
            self.assertEqual(f'ios/config/{flavor}/GoogleService-Info.plist', path)

    def test_non_production_and_production_cannot_be_mixed(self):
        for flavor, wrong in (('development', PROD), ('staging', PROD), ('production', NON)):
            with self.assertRaises(fc.ConfigError):
                self.write('ios', flavor, ios_plist(wrong))
            with self.assertRaises(fc.ConfigError):
                self.write('android', flavor, android_json(wrong, fc.FLAVORS[flavor][1]))

    def test_ios_always_uses_the_app_store_bundle_id(self):
        with self.assertRaises(fc.ConfigError):
            self.write('ios', 'development', ios_plist(NON, 'ch.orangepos.productscanner.dev'))

    def test_android_needs_the_flavor_package(self):
        with self.assertRaises(fc.ConfigError):
            self.write('android', 'staging', android_json(NON, 'com.orangeone.app.dev'))

    def test_missing_or_malformed_configuration_fails(self):
        with tempfile.TemporaryDirectory() as root:
            for env in (ENV,
                        {**ENV, 'FIREBASE_IOS_DEVELOPMENT_B64': '%%%'},
                        {**ENV, 'FIREBASE_IOS_DEVELOPMENT_B64': b64(b'not a plist')},
                        {'FIREBASE_IOS_DEVELOPMENT_B64': b64(ios_plist(NON))},
                        {**ENV, 'FIREBASE_PROJECT_ID_PRODUCTION': NON,
                         'FIREBASE_IOS_DEVELOPMENT_B64': b64(ios_plist(NON))}):
                with self.assertRaises(fc.ConfigError):
                    fc.write('ios', 'development', env, root)
            with self.assertRaises(fc.ConfigError):
                fc.expected_project('qa', ENV)

    def test_cli_reports_a_fixed_reason_without_contents(self):
        env = {**ENV, 'FIREBASE_IOS_DEVELOPMENT_B64': b64(ios_plist(PROD))}
        error, output = io.StringIO(), io.StringIO()
        with tempfile.TemporaryDirectory() as root, contextlib.redirect_stderr(error), \
                contextlib.redirect_stdout(output):
            import os
            from unittest.mock import patch
            with patch.dict(os.environ, env, clear=True), patch.object(fc, 'ROOT', Path(root)), \
                    patch.object(fc, 'destination', lambda p, f, r=Path(root): fc.Path(r) / 'x'):
                self.assertEqual(1, fc.main(['write', 'ios', 'development']))
                self.assertEqual(1, fc.main(['bogus']))
                self.assertEqual(1, fc.main([]))
        self.assertNotIn(SENTINEL, error.getvalue() + output.getvalue())
        self.assertIn('another Firebase project', error.getvalue())


class VerifyBuildTest(unittest.TestCase):
    def test_ios_archive_must_carry_its_flavors_plist(self):
        with tempfile.TemporaryDirectory() as root:
            app = Path(root) / 'Products/Applications/Runner.app'
            app.mkdir(parents=True)
            with self.assertRaises(fc.ConfigError):
                fc.verify_ios(root, 'development', ENV)
            (app / 'GoogleService-Info.plist').write_bytes(ios_plist(NON))
            fc.verify_ios(root, 'development', ENV)
            fc.verify_ios(app, 'staging', ENV)
            with self.assertRaises(fc.ConfigError):
                fc.verify_ios(root, 'production', ENV)

    def apk(self, folder, resources):
        path = Path(folder) / 'app.apk'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('resources.arsc', resources)
        return path

    def test_android_apk_must_name_only_its_project(self):
        with tempfile.TemporaryDirectory() as folder:
            fc.verify_android(self.apk(folder, PROD.encode()), 'production', ENV)
            fc.verify_android(self.apk(folder, NON.encode('utf-16-le')), 'development', ENV)
            for resources, flavor in ((b'nothing', 'production'), (NON.encode(), 'production'),
                                      (PROD.encode(), 'staging'), (NON.encode() + PROD.encode(), 'production')):
                with self.assertRaises(fc.ConfigError, msg=(resources, flavor)):
                    fc.verify_android(self.apk(folder, resources), flavor, ENV)
            with self.assertRaises(fc.ConfigError):
                fc.verify_android(Path(folder) / 'missing.apk', 'production', ENV)


class SymbolUploadTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        root = Path(self.folder.name)
        (root / 'symbols').mkdir()
        (root / 'symbols/app.symbols').write_text('x')
        self.config = root / 'GoogleService-Info.plist'
        self.config.write_bytes(ios_plist(NON))
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


class WorkflowWiringTest(unittest.TestCase):
    def jobs(self, name):
        return jobs(read(name))

    def test_distributable_builds_write_verify_and_fail_without_configuration(self):
        release = self.jobs('ios-release.yaml')['archive']
        self.assertLess(release.index('firebase_config.py write ios production'), release.index('flutter build ipa'))
        self.assertLess(release.index('flutter build ipa'), release.index('firebase_config.py verify-ios'))
        android = self.jobs('android-release.yaml')['apk']
        self.assertIn("FIREBASE_CONFIG_REQUIRED: 'true'", android)
        self.assertLess(android.index('firebase_config.py write android production'), android.index('flutter build apk'))
        self.assertLess(android.index('flutter build apk'), android.index('firebase_config.py verify-android'))
        testflight = read('ios-testflight.yaml')
        self.assertIn('FIREBASE_IOS_DEVELOPMENT_B64', testflight)
        self.assertIn('FIREBASE_IOS_STAGING_B64', testflight)
        self.assertNotIn('FIREBASE_IOS_PRODUCTION_B64', testflight)
        legacy = read('ios.yaml')
        self.assertLess(legacy.index('firebase_config.py write ios production'), legacy.index('Archive selected source'))
        self.assertIn('firebase_config.py verify-ios', legacy)

    def test_archive_jobs_stay_secret_free_and_use_variables(self):
        for name in ('ios-testflight.yaml', 'ios-release.yaml'):
            archive = self.jobs(name)['archive']
            self.assertNotIn('secrets.', archive, name)
            self.assertNotRegex(archive, r'(?m)^    environment:')
            self.assertIn('vars.FIREBASE_PROJECT_ID_NONPRODUCTION', archive)
            self.assertIn('vars.FIREBASE_PROJECT_ID_PRODUCTION', archive)
            self.assertIn('--split-debug-info' if name == 'ios-release.yaml' else 'archive_flavor.py', archive)

    def test_symbols_upload_only_for_real_deliveries(self):
        for name in ('ios-testflight.yaml', 'ios-release.yaml'):
            jobs_ = self.jobs(name)
            self.assertIn("needs.plan.outputs.dry_run == 'false' && 'true' || 'false'",
                          jobs_['archive'], 'dSYMs only for non-dry-runs')
            deliver = jobs_['deliver']
            step = deliver.split('Upload the Dart symbols')[1].split('- name')[0]
            self.assertIn("if: needs.plan.outputs.dry_run == 'false'", step)
            self.assertIn('secrets.FIREBASE_SERVICE_ACCOUNT_JSON', step)
            self.assertLess(deliver.index('Upload the Dart symbols'), deliver.index('fastlane ios testflight_channel'))

    def test_no_new_workflow_job_exposes_credentials_or_changes_triggers(self):
        for name in ('ios-testflight.yaml', 'ios-release.yaml', 'android-release.yaml'):
            text = read(name)
            self.assertEqual(text.count('actions/checkout@v4'), text.count('persist-credentials: false'), name)
        self.assertNotIn('FIREBASE_SERVICE_ACCOUNT_JSON', self.jobs('ios-testflight.yaml')['archive'])
        self.assertNotIn('FIREBASE_SERVICE_ACCOUNT_JSON', self.jobs('ios-testflight.yaml')['allocate'])


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
