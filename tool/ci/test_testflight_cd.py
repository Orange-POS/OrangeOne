"""DEV/STG TestFlight delivery: channels, gating, archive identity and workflow guards.

No Apple, GitHub or macOS access: everything runs on synthetic data.
"""
import json
from pathlib import Path
import plistlib
import re
import tempfile
import unittest

import archive_flavor
import testflight_channels as channels
import wait_for_checks
from release_flavors import BUNDLES
from test_workflows import jobs, on_block, read, trigger

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = 'ios-testflight.yaml'


class ChannelTest(unittest.TestCase):
    def test_develop_is_dev_and_staging_is_staging_only(self):
        for event in ('push', 'workflow_dispatch'):
            dev = channels.channel_for('refs/heads/develop', event)
            self.assertEqual((dev['flavor'], dev['group'], dev['environment']),
                             ('development', 'dev', 'ios-development'))
            stg = channels.channel_for('refs/heads/staging', event)
            self.assertEqual((stg['flavor'], stg['group'], stg['environment']),
                             ('staging', 'staging', 'ios-staging'))

    def test_no_other_branch_or_event_can_deliver(self):
        for ref in ('refs/heads/main', 'refs/heads/feature/x', 'refs/heads/develop-2',
                    'refs/tags/v1.0.0', 'refs/pull/1/merge', ''):
            with self.subTest(ref=ref):
                with self.assertRaises(ValueError):
                    channels.channel_for(ref, 'push')
        for event in ('pull_request', 'release', 'workflow_run', 'schedule', ''):
            with self.subTest(event=event):
                with self.assertRaises(ValueError):
                    channels.channel_for('refs/heads/develop', event)

    def test_production_group_and_environments_are_unreachable(self):
        for channel in channels.CHANNELS.values():
            self.assertNotEqual(channel['group'], 'production')
            self.assertNotIn('production', channel['environment'])
            self.assertNotIn('app-store', channel['environment'])
            self.assertIn(channel['group'], json.loads(
                (ROOT / 'tool/ci/testflight_targets.json').read_text())['groups'])

    def test_real_uploads_need_the_repository_switch(self):
        for event in ('push', 'workflow_dispatch'):
            for requested in ('', 'true', 'false'):
                self.assertTrue(channels.is_dry_run(event, requested, ''))
                self.assertTrue(channels.is_dry_run(event, requested, 'false'))
                self.assertTrue(channels.is_dry_run(event, requested, 'TRUE'))
        self.assertFalse(channels.is_dry_run('push', '', 'true'))
        self.assertFalse(channels.is_dry_run('workflow_dispatch', 'false', 'true'))
        self.assertTrue(channels.is_dry_run('workflow_dispatch', 'true', 'true'))
        self.assertTrue(channels.is_dry_run('workflow_dispatch', '', 'true'))

    def test_plan_selects_flavor_group_environment_and_version(self):
        plan = channels.plan({'GITHUB_REF': 'refs/heads/staging', 'GITHUB_EVENT_NAME': 'push'})
        self.assertEqual(plan['flavor'], 'staging')
        self.assertEqual(plan['group'], 'staging')
        self.assertEqual(plan['environment'], 'ios-staging')
        self.assertEqual(plan['dry_run'], 'true')
        self.assertRegex(plan['version'], r'^\d+\.\d+\.\d+$')
        enabled = channels.plan({'GITHUB_REF': 'refs/heads/develop', 'GITHUB_EVENT_NAME': 'push',
                                 'TESTFLIGHT_CD_ENABLED': 'true'})
        self.assertEqual(enabled['dry_run'], 'false')

    def test_every_channel_flavor_selects_its_own_environment_and_no_backend_url(self):
        for channel in channels.CHANNELS.values():
            values = channels.validate_flavor_configuration(channel['flavor'])
            self.assertEqual(values['APP_ENVIRONMENT'], channel['flavor'])
            self.assertNotIn('ODOO_BASE_URL', values)
        production = json.loads((ROOT / 'config/production.example.json').read_text())
        self.assertEqual(production['APP_ENVIRONMENT'], 'production')

    def test_flavor_configuration_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / 'config').mkdir()
            (Path(folder) / 'config/staging.example.json').write_text('{"APP_ENVIRONMENT": "production"}')
            with self.assertRaises(ValueError):
                channels.validate_flavor_configuration('staging', folder)
            (Path(folder) / 'config/staging.example.json').write_text(
                '{"APP_ENVIRONMENT": "staging", "ODOO_BASE_URL": "https://x.example"}')
            with self.assertRaises(ValueError):
                channels.validate_flavor_configuration('staging', folder)

    def test_all_flavors_share_the_one_production_bundle_id(self):
        self.assertEqual(channels.BUNDLE_ID, 'ch.orangepos.productscanner')
        self.assertEqual(channels.BUNDLE_ID, BUNDLES['production'])
        targets = json.loads((ROOT / 'tool/ci/testflight_targets.json').read_text())
        self.assertEqual(targets['bundle_id'], channels.BUNDLE_ID)


class BuildNumberTest(unittest.TestCase):
    def test_floor_is_above_every_used_build_and_the_pubspec(self):
        ledger = json.loads((ROOT / 'tool/ci/release_versions.json').read_text())
        used = max(e['build'] for e in ledger['published'] + ledger['reserved'])
        _, pubspec_build = channels.pubspec_version()
        floor = channels.build_floor()
        self.assertGreaterEqual(floor, used)
        self.assertGreaterEqual(floor, pubspec_build - 1)
        self.assertTrue(channels.valid_build_number(floor + 1))

    def test_build_number_format(self):
        for good in ('1', '35', '9999', 36):
            self.assertTrue(channels.valid_build_number(good))
        for bad in ('0', '10000', '-1', '1.5', '', 'abc', '01', None):
            self.assertFalse(channels.valid_build_number(bad))

    def test_ruby_allocation_is_wired_to_app_store_connect(self):
        source = (ROOT / 'tool/ci/testflight_build_number.rb').read_text()
        self.assertIn('Spaceship::ConnectAPI::Build.all', source)
        self.assertIn('[highest, Integer(floor)].max + 1', source)


class CheckGateTest(unittest.TestCase):
    required = ['a', 'b']

    def runs(self, **conclusions):
        return [{'id': index, 'name': name, 'status': 'completed', 'conclusion': conclusion}
                for index, (name, conclusion) in enumerate(conclusions.items())]

    def test_all_required_checks_must_succeed(self):
        self.assertEqual(('passed', []), wait_for_checks.evaluate(
            self.runs(a='success', b='success'), self.required))

    def test_skipped_or_neutral_checks_never_satisfy_the_gate(self):
        for inconclusive in ('skipped', 'neutral'):
            state, problems = wait_for_checks.evaluate(
                self.runs(a='success', b=inconclusive), self.required)
            self.assertEqual('pending', state, inconclusive)
            self.assertIn('b', problems[0])

    def test_a_later_skipped_run_does_not_hide_a_real_success_or_failure(self):
        # ios.yaml skips its matrix on a manual dispatch of the same commit.
        for real, expected in (('success', 'passed'), ('failure', 'failed')):
            runs = [{'id': 1, 'name': 'a', 'status': 'completed', 'conclusion': 'success'},
                    {'id': 2, 'name': 'b', 'status': 'completed', 'conclusion': real},
                    {'id': 9, 'name': 'b', 'status': 'completed', 'conclusion': 'skipped'}]
            self.assertEqual(expected, wait_for_checks.evaluate(runs, self.required)[0])

    def test_failed_cancelled_or_timed_out_checks_block(self):
        for bad in ('failure', 'cancelled', 'timed_out', 'action_required', 'stale'):
            state, problems = wait_for_checks.evaluate(self.runs(a='success', b=bad), self.required)
            self.assertEqual('failed', state, bad)
            self.assertIn('b', problems[0])

    def test_unfinished_or_missing_checks_wait(self):
        running = [{'id': 1, 'name': 'a', 'status': 'in_progress', 'conclusion': None},
                   {'id': 2, 'name': 'b', 'status': 'completed', 'conclusion': 'success'}]
        self.assertEqual('pending', wait_for_checks.evaluate(running, self.required)[0])
        self.assertEqual('pending', wait_for_checks.evaluate([], self.required)[0])
        self.assertEqual('pending', wait_for_checks.evaluate(
            self.runs(a='success'), self.required)[0])

    def test_failure_wins_over_pending_and_rerun_replaces_old_failure(self):
        mixed = [{'id': 1, 'name': 'a', 'status': 'completed', 'conclusion': 'failure'}]
        self.assertEqual('failed', wait_for_checks.evaluate(mixed, self.required)[0])
        rerun = mixed + [{'id': 5, 'name': 'a', 'status': 'completed', 'conclusion': 'success'},
                         {'id': 6, 'name': 'b', 'status': 'completed', 'conclusion': 'success'}]
        self.assertEqual('passed', wait_for_checks.evaluate(rerun, self.required)[0])

    def test_unrelated_checks_are_ignored(self):
        extra = self.runs(a='success', b='success', c='failure')
        self.assertEqual('passed', wait_for_checks.evaluate(extra, self.required)[0])

    def test_wait_polls_until_done_and_times_out(self):
        states = iter([[], self.runs(a='success'), self.runs(a='success', b='success')])
        ticks = []
        result = wait_for_checks.wait(lambda: next(states), timeout=100, interval=10,
                                      clock=lambda: len(ticks) * 10, sleeper=ticks.append,
                                      required=self.required)
        self.assertEqual('passed', result[0])
        self.assertEqual([10, 10], ticks)
        clock = {'now': 0}

        def advance(seconds):
            clock['now'] += seconds

        timed = wait_for_checks.wait(lambda: [], timeout=25, interval=10,
                                     clock=lambda: clock['now'], sleeper=advance, required=self.required)
        self.assertEqual('timeout', timed[0])

    def test_required_contexts_match_the_workflow_job_names(self):
        contexts = wait_for_checks.REQUIRED
        for flavor in ('development', 'staging', 'production'):
            self.assertIn(f'android ({flavor})', contexts)
            self.assertIn(f'ios ({flavor})', contexts)
        self.assertIn('Format, analyze and test', contexts)
        self.assertIn('license_check / build', contexts)
        self.assertEqual(len(contexts), 8)
        self.assertIn('name: Format, analyze and test', read('flutter_tests.yml'))


class ArchiveTest(unittest.TestCase):
    def make_archive(self, folder, bundle=channels.BUNDLE_ID, name='[DEV] OrangeONE',
                     version='1.1.0', build='36'):
        root = Path(folder) / 'Runner.xcarchive'
        app = root / 'Products/Applications/Runner.app'
        app.mkdir(parents=True)
        (root / 'Info.plist').write_bytes(plistlib.dumps(
            {'ApplicationProperties': {'ApplicationPath': 'Applications/Runner.app'}}))
        (app / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': bundle, 'CFBundleDisplayName': name,
            'CFBundleShortVersionString': version, 'CFBundleVersion': build,
            'CFBundleExecutable': 'Runner'}))
        (app / 'Runner').write_bytes(b'binary')
        return root

    def test_commands_select_flavor_and_override_only_the_runner_bundle_setting(self):
        for flavor in ('development', 'staging'):
            configure, archive = archive_flavor.commands(flavor, '1.1.0', '36')
            self.assertEqual(['flutter', 'build', 'ios', '--config-only'], configure[:4])
            self.assertIn(f'lib/main_{flavor}.dart', configure)
            self.assertIn(f'--dart-define-from-file=config/{flavor}.example.json', configure)
            self.assertIn('--build-name=1.1.0', configure)
            self.assertIn('--build-number=36', configure)
            self.assertEqual(flavor, archive[archive.index('-scheme') + 1])
            self.assertEqual(f'Release-{flavor}', archive[archive.index('-configuration') + 1])
            self.assertIn('FLAVOR_BUNDLE_ID=ch.orangepos.productscanner', archive)
            self.assertFalse([a for a in archive if a.startswith('PRODUCT_BUNDLE_IDENTIFIER')],
                             'must not override the identifier of plugin frameworks')
            self.assertIn('CODE_SIGNING_ALLOWED=NO', archive)

    def test_production_unknown_flavors_and_bad_build_numbers_are_refused(self):
        for flavor in ('production', 'unknown', ''):
            with self.assertRaises(ValueError):
                archive_flavor.commands(flavor, '1.1.0', '36')
        for number in ('0', '10000', 'x', ''):
            with self.assertRaises(ValueError):
                archive_flavor.commands('development', '1.1.0', number)

    def test_verify_accepts_the_expected_archive(self):
        with tempfile.TemporaryDirectory() as folder:
            archive_flavor.verify('development', '1.1.0', '36', self.make_archive(folder))
        with tempfile.TemporaryDirectory() as folder:
            archive_flavor.verify('staging', '1.1.0', '36', self.make_archive(folder, name='[STG] OrangeONE'))

    def test_verify_rejects_wrong_bundle_flavor_or_identity(self):
        cases = [
            dict(bundle='ch.orangepos.productscanner.dev'),
            dict(name='OrangeONE'),
            dict(name='[STG] OrangeONE'),
            dict(version='1.0.0'),
            dict(build='35'),
        ]
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as folder:
                with self.assertRaises(ValueError):
                    archive_flavor.verify('development', '1.1.0', '36', self.make_archive(folder, **case))

    def test_main_runs_both_commands_in_the_repository_then_verifies(self):
        recorded = []
        with tempfile.TemporaryDirectory() as folder:
            archive = self.make_archive(folder)
            original = archive_flavor.verify
            try:
                archive_flavor.verify = lambda *a, **k: original(*a, archive=archive)
                archive_flavor.main(
                    {'FLAVOR': 'development', 'RELEASE_VERSION': '1.1.0', 'RELEASE_BUILD_NUMBER': '36'},
                    run=lambda command, **options: recorded.append((command[0], options)))
            finally:
                archive_flavor.verify = original
        self.assertEqual(['flutter', 'xcodebuild'], [name for name, _ in recorded])
        for _, options in recorded:
            self.assertTrue(options['check'])
            self.assertEqual(archive_flavor.ROOT, options['cwd'])


class NativeIdentityTest(unittest.TestCase):
    def test_flavor_configurations_resolve_to_their_ids_and_override_one_setting(self):
        project = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        blocks = re.findall(r'/\* ([^*]+) \*/ = \{\s*isa = XCBuildConfiguration;(.*?)\n\t\t\};', project, re.S)
        seen = {}
        for configuration, body in blocks:
            bundle = re.search(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', body)
            if not bundle or bundle.group(1).endswith('.RunnerTests'):
                continue
            default = re.search(rf'{channels.BUNDLE_SETTING} = ([^;]+);', body)
            if configuration.endswith(('development', 'staging')):
                self.assertEqual(f'"$({channels.BUNDLE_SETTING})"', bundle.group(1), configuration)
                self.assertIsNotNone(default, configuration)
                suffix = '.dev' if configuration.endswith('development') else '.stg'
                self.assertEqual(channels.BUNDLE_ID + suffix, default.group(1), configuration)
                seen[configuration] = True
            else:
                self.assertEqual(channels.BUNDLE_ID, bundle.group(1), configuration)
                self.assertIsNone(default, 'production must not be overridable')
        self.assertEqual(6, len(seen))

    def test_only_the_runner_target_reads_the_override_setting(self):
        project = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        self.assertEqual(6, project.count(f'"$({channels.BUNDLE_SETTING})"'))
        self.assertNotIn('PRODUCT_BUNDLE_IDENTIFIER = ch.orangepos.productscanner.dev;', project)

    def test_every_flavor_plist_carries_the_same_export_compliance_declaration(self):
        production = plistlib.loads((ROOT / 'ios/Runner/Info.plist').read_bytes())
        development = plistlib.loads((ROOT / 'ios/Runner/Info-development.plist').read_bytes())
        for key in ('ITSAppUsesNonExemptEncryption', 'ITSEncryptionExportComplianceCode'):
            self.assertEqual(key in production, key in development, key)
            self.assertEqual(production.get(key), development.get(key), key)
        self.assertIs(development['ITSAppUsesNonExemptEncryption'], False)

    def test_flavor_names_and_icons_distinguish_the_builds(self):
        project = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        for name in ('[DEV] OrangeONE', '[STG] OrangeONE'):
            self.assertIn(f'FLAVOR_APP_NAME = "{name}"', project)
        self.assertEqual({c['display_name'] for c in channels.CHANNELS.values()},
                         {'[DEV] OrangeONE', '[STG] OrangeONE'})


class WorkflowTest(unittest.TestCase):
    text = read(WORKFLOW)
    parts = jobs(text)

    def test_triggers_are_exactly_develop_staging_pushes_and_manual_dispatch(self):
        block = on_block(self.text)
        self.assertIn('branches: [develop, staging]', trigger(self.text, 'push'))
        self.assertIn('workflow_dispatch:', block)
        for forbidden in ('pull_request', 'release', 'tags:', 'schedule', 'workflow_run', 'merge_group'):
            self.assertNotIn(forbidden, block)

    def test_job_graph_gates_signing_behind_the_checks_and_allocation(self):
        self.assertEqual({'plan', 'checks', 'allocate', 'archive', 'deliver'}, set(self.parts))
        self.assertIn('needs: plan', self.parts['checks'])
        self.assertIn('needs: [plan, checks]', self.parts['allocate'])
        self.assertIn('needs: [plan, allocate]', self.parts['archive'])
        self.assertIn('needs: [plan, allocate, archive]', self.parts['deliver'])
        self.assertIn('python3 tool/ci/wait_for_checks.py', self.parts['checks'])
        self.assertIn('checks: read', self.parts['checks'])

    def test_secrets_and_environments_exist_only_where_credentials_are_needed(self):
        for name, body in self.parts.items():
            has_secrets = 'secrets.' in body
            self.assertEqual(name in ('allocate', 'deliver'), has_secrets, name)
            self.assertEqual(name in ('allocate', 'deliver'),
                             '    environment: ${{ needs.plan.outputs.environment }}' in body, name)
        self.assertNotIn('secrets.', self.text.split('\njobs:\n')[0])

    def test_the_secret_free_build_has_no_credentials_and_no_cache(self):
        archive = self.parts['archive']
        self.assertNotIn('secrets.', archive)
        self.assertNotIn('environment:', archive)
        self.assertIn('cache: false', archive)
        self.assertIn('python3 tool/ci/archive_flavor.py', archive)
        self.assertNotIn('flutter build ipa', archive)

    def test_production_credentials_and_group_are_unreachable(self):
        self.assertNotIn('ios-production', self.text)
        self.assertNotIn('ios-app-store', self.text)
        self.assertNotIn('submit_for_review', self.text)
        self.assertIn('RELEASE_FLAVOR: production', self.parts['deliver'])  # signing identity only
        self.assertNotIn('target_group', self.text)

    def test_checkouts_never_persist_credentials(self):
        for name, body in self.parts.items():
            self.assertEqual(body.count('actions/checkout@v4'), body.count('persist-credentials: false'), name)

    def test_real_uploads_default_to_off(self):
        self.assertIn('vars.TESTFLIGHT_CD_ENABLED', self.text)
        self.assertIn('default: true', self.text)
        self.assertIn('DRY_RUN: ${{ needs.plan.outputs.dry_run }}', self.parts['deliver'])

    def test_deliveries_are_serialized_and_never_cancelled(self):
        self.assertIn('group: testflight-cd', self.text)
        self.assertIn('cancel-in-progress: false', self.text)

    def test_cleanup_always_runs_in_credential_jobs(self):
        for name, script in (('allocate', 'apple_api_key.py'), ('deliver', 'ios_signing.py')):
            self.assertRegex(self.parts[name], r'if: always\(\)\n\s+run: python3 tool/ci/' + script + ' cleanup')

    def test_production_workflow_is_not_affected(self):
        ios = read('ios.yaml')
        for marker in ('testflight_channel', 'allocate_build', 'archive_flavor', 'ios-testflight', 'FLAVOR_BUNDLE_ID'):
            self.assertNotIn(marker, ios)
        self.assertIn('environment: ios-production', ios)

    def test_fastlane_channel_map_matches_the_python_map(self):
        fastfile = read('../../fastlane/Fastfile')
        for ref, channel in channels.CHANNELS.items():
            self.assertIn(f"'{ref}' => %w[{channel['flavor']} {channel['group']}]", fastfile)
        self.assertNotIn("'refs/heads/main' =>", fastfile)
        self.assertIn('lane :allocate_build', fastfile)
        self.assertIn('lane :testflight_channel', fastfile)


if __name__ == '__main__':
    unittest.main()
