"""Flavor and trust-boundary regressions without Apple services or credentials."""
import datetime as dt
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
import zipfile
from unittest.mock import patch

from release_flavors import BUNDLES, GROUPS, bundle_id, target_group
from validate_release import validate
from ios_signing import validate_profile, validate_certificate, validate_entitlements, verify_export
from prepare_archive import validate_app
from test_archive import candidate
from export_ipa import export


class FlavorReleaseTest(unittest.TestCase):
    def test_shared_production_identity_and_group_allowlist(self):
        self.assertEqual(BUNDLES, {'production': 'ch.orangepos.productscanner'})
        self.assertEqual(GROUPS, {'dev': 'Dev Testers', 'staging': 'Staging Testers', 'production': 'Production Testers'})
        fastfile = (Path(__file__).resolve().parents[2] / 'fastlane/Fastfile').read_text()
        helper = (Path(__file__).with_name('testflight_groups.rb')).read_text()
        self.assertIn('testflight_targets.json', helper)
        self.assertIn('app_identifier: OrangeoneTestflight::BUNDLE_ID', fastfile)
        self.assertNotIn('bundles =', fastfile)
        self.assertEqual(target_group(), 'Production Testers')
        for invalid in ('', 'development', 'Dev Testers', 'group-id', 'production;bad'):
            with self.assertRaises(ValueError):
                target_group(invalid)

    def test_export_mapping_for_each_flavor_and_certificate(self):
        for flavor, bundle in BUNDLES.items():
            with self.subTest(flavor=flavor), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                app = candidate(root / 'candidate/Runner.xcarchive')
                info = plistlib.loads((app / 'Info.plist').read_bytes())
                info['CFBundleIdentifier'] = bundle
                (app / 'Info.plist').write_bytes(plistlib.dumps(info))
                def produce(command, **kwargs):
                    self.assertEqual(command[:2], ['/usr/bin/xcodebuild', '-exportArchive'])
                    (root / 'build/ios/ipa/Runner.ipa').write_bytes(b'fixture')
                values = {'RUNNER_TEMP': directory, 'RELEASE_FLAVOR': flavor, 'APPLE_TEAM_ID': 'ABC123DE45',
                          'IOS_PROFILE_NAME': 'selected-profile', 'IOS_CERTIFICATE_SHA1': 'A' * 40,
                          'RELEASE_VERSION': '1.0.0', 'RELEASE_BUILD_NUMBER': '12'}
                with patch.dict(os.environ, values), patch('export_ipa.Path.cwd', return_value=root), \
                        patch('export_ipa.subprocess.run', side_effect=produce), patch('export_ipa.verify_export') as verify:
                    export()
                    verify.assert_called_once()
                options = plistlib.loads((root / 'store-export.plist').read_bytes())
                self.assertEqual(options['provisioningProfiles'], {bundle: 'selected-profile'})
                self.assertEqual(options['signingCertificate'], 'A' * 40)

    def test_export_verifies_signature_profile_and_entitlements_for_each_flavor(self):
        for flavor, bundle in BUNDLES.items():
            with self.subTest(flavor=flavor), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'orangeone-signing').mkdir()
                ipa = root / 'fixture.ipa'
                with zipfile.ZipFile(ipa, 'w') as archive:
                    archive.writestr('Payload/Runner.app/Info.plist', plistlib.dumps({
                        'CFBundleIdentifier': bundle, 'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '12'}))
                entitlements = {'application-identifier': 'ABC123DE45.' + bundle,
                                'com.apple.developer.team-identifier': 'ABC123DE45',
                                'keychain-access-groups': ['ABC123DE45.' + bundle], 'get-task-allow': False}
                profile = {'UUID': '12345678-1234-1234-1234-123456789abc', 'Name': 'Fixture',
                           'TeamIdentifier': ['ABC123DE45'], 'ApplicationIdentifierPrefix': ['ABC123DE45'],
                           'ExpirationDate': dt.datetime(2040, 1, 1), 'Entitlements': entitlements}
                values = {'RUNNER_TEMP': directory, 'RELEASE_FLAVOR': flavor, 'APPLE_TEAM_ID': 'ABC123DE45',
                          'IOS_PROFILE_UUID': profile['UUID'], 'RELEASE_VERSION': '1.0.0', 'RELEASE_BUILD_NUMBER': '12'}
                with patch.dict(os.environ, values), patch('ios_signing.run', side_effect=[
                        b'', b'', plistlib.dumps(profile), plistlib.dumps(entitlements)]) as command:
                    verify_export(ipa)
                    self.assertIn('--verify', command.call_args_list[1].args)
                # A mismatched embedded profile must fail before entitlement acceptance.
                wrong = {**profile, 'UUID': '87654321-1234-1234-1234-123456789abc'}
                shutil.rmtree(root / 'orangeone-signing/export-check')
                with patch.dict(os.environ, values), patch('ios_signing.run', side_effect=[b'', b'', plistlib.dumps(wrong)]):
                    with self.assertRaises(ValueError):
                        verify_export(ipa)

    def test_default_and_invalid_flavors(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(bundle_id(), BUNDLES['production'])
        for value in ('', 'development', 'staging', 'Production', '../production', 'unknown'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                bundle_id(value)

    def test_each_flavor_accepts_only_matching_archive_and_profile(self):
        for flavor, bundle in BUNDLES.items():
            with self.subTest(flavor=flavor), patch.dict(os.environ, {'RELEASE_FLAVOR': flavor}):
                profile = {
                    'UUID': '12345678-1234-1234-1234-123456789abc', 'Name': 'Fixture',
                    'TeamIdentifier': ['ABC123DE45'], 'ApplicationIdentifierPrefix': ['ABC123DE45'],
                    'ExpirationDate': dt.datetime(2040, 1, 1),
                    'Entitlements': {'application-identifier': 'ABC123DE45.' + bundle,
                                     'get-task-allow': False,
                                     'keychain-access-groups': ['ABC123DE45.*']},
                }
                validate_profile(profile, 'ABC123DE45')
                validate_entitlements({'keychain-access-groups': ['ABC123DE45.' + bundle]}, profile, 'ABC123DE45')
                with tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    app = candidate(root)
                    info = plistlib.loads((app / 'Info.plist').read_bytes())
                    info['CFBundleIdentifier'] = bundle
                    (app / 'Info.plist').write_bytes(plistlib.dumps(info))
                    validate_app(root, '1.0.0', '12')
                for request in ({'get-task-allow': True}, {'com.apple.security.application-groups': ['unexpected']},
                                {'keychain-access-groups': ['ABC123DE45.other']},
                                {'com.apple.developer.team-identifier': 'OTHER12345'}):
                    with self.assertRaises(ValueError):
                        validate_entitlements(request, profile, 'ABC123DE45')

    def test_certificate_must_belong_to_profile(self):
        certificate = b'fixture DER bytes'
        identity = (b'  1) ' + hashlib.sha1(certificate).hexdigest().upper().encode()
                    + b' "Apple Distribution: Fixture (ABC123DE45)"\n  1 valid identities found\n')
        validate_certificate({'DeveloperCertificates': [certificate]}, identity)
        for profile in ({}, {'DeveloperCertificates': [b'other']}):
            with self.assertRaises(ValueError):
                validate_certificate(profile, identity)

    def test_release_protection_for_all_groups(self):
        values = {'GITHUB_REF': 'refs/heads/main', 'GITHUB_EVENT_NAME': 'workflow_dispatch',
                  'OPERATION': 'testflight', 'RELEASE_VERSION': '1.0.0', 'RELEASE_BUILD_NUMBER': '12'}
        for group in GROUPS:
            selected = {**values, 'TARGET_GROUP': group}
            validate(selected)
            self.assertEqual(bundle_id(), 'ch.orangepos.productscanner')
            for change in ({'GITHUB_REF': 'refs/heads/feature'}, {'GITHUB_EVENT_NAME': 'pull_request'},
                           {'RELEASE_FLAVOR': 'development'}, {'RELEASE_FLAVOR': 'staging'}):
                with self.assertRaises(ValueError):
                    validate({**selected, **change})
        for group in ('', 'Development', 'Dev Testers', 'unknown'):
            with self.assertRaises(ValueError):
                validate({**values, 'TARGET_GROUP': group})
        with self.assertRaises(ValueError):
            validate({**values, 'OPERATION': 'submit_for_review', 'TARGET_GROUP': 'production'})

    def test_nonproduction_archives_and_profiles_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = candidate(root)
            original = plistlib.loads((app / 'Info.plist').read_bytes())
            for suffix in ('.dev', '.stg'):
                (app / 'Info.plist').write_bytes(plistlib.dumps({**original,
                    'CFBundleIdentifier': 'ch.orangepos.productscanner' + suffix}))
                with self.assertRaises(ValueError):
                    validate_app(root, '1.0.0', '12')
                profile = {
                    'UUID': '12345678-1234-1234-1234-123456789abc', 'Name': 'Fixture',
                    'TeamIdentifier': ['ABC123DE45'], 'ApplicationIdentifierPrefix': ['ABC123DE45'],
                    'ExpirationDate': dt.datetime(2040, 1, 1),
                    'Entitlements': {'application-identifier': 'ABC123DE45.ch.orangepos.productscanner' + suffix,
                                     'get-task-allow': False},
                }
                with self.assertRaises(ValueError):
                    validate_profile(profile, 'ABC123DE45')

    def test_workflow_keeps_candidate_secret_free_and_signing_trusted(self):
        workflow = (Path(__file__).resolve().parents[2] / '.github/workflows/ios.yaml').read_text()
        candidate_job = workflow.split('\n  candidate:')[1].split('\n  beta:')[0]
        beta_job = workflow.split('\n  beta:')[1].split('\n  submit:')[0]
        self.assertNotIn('secrets.', candidate_job)
        self.assertNotIn('environment:', candidate_job)
        self.assertIn('--flavor production --target lib/main_production.dart', candidate_job)
        self.assertIn('ref: ${{ github.sha }}', beta_job)
        self.assertNotIn('flutter build', beta_job)
        self.assertIn('environment: ios-production', beta_job)
        self.assertNotIn('inputs.flavor', workflow)
        self.assertIn('options: [dev, staging, production]', workflow)
        self.assertIn('TARGET_GROUP:', beta_job)
        self.assertIn('if: always()', beta_job)
        self.assertIn('default: production', workflow)
