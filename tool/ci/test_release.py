import copy
import datetime as dt
import unittest
import json
import os
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch
from ios_signing import validate_profile, cleanup
from validate_release import validate


class ReleaseValidationTest(unittest.TestCase):
    def setUp(self):
        self.values = {'GITHUB_REF': 'refs/heads/main', 'GITHUB_EVENT_NAME': 'workflow_dispatch',
                       'OPERATION': 'testflight', 'RELEASE_VERSION': '1.0.0', 'RELEASE_BUILD_NUMBER': '12'}

    def test_main_manual_beta_allowed(self):
        validate(self.values)

    def test_nonmain_or_automatic_rejected(self):
        for key, value in [('GITHUB_REF', 'refs/heads/feature'), ('GITHUB_EVENT_NAME', 'push'),
                           ('OPERATION', 'release_now'), ('RELEASE_VERSION', '$(bad)'),
                           ('RELEASE_BUILD_NUMBER', '1;bad'), ('RELEASE_BUILD_NUMBER', '10000')]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                validate({**self.values, key: value})

    def test_appstore_submission_requires_device_confirmation(self):
        values = {**self.values, 'OPERATION': 'submit_for_review'}
        with self.assertRaises(ValueError):
            validate(values)
        validate({**values, 'IPHONE_SMOKE_TEST_CONFIRMED': 'true'})


class ProvisioningValidationTest(unittest.TestCase):
    def setUp(self):
        self.now = dt.datetime(2030, 1, 1, tzinfo=dt.timezone.utc)
        self.profile = {
            'UUID': '12345678-1234-1234-1234-123456789abc', 'Name': 'Example App Store',
            'TeamIdentifier': ['ABC123DE45'], 'ApplicationIdentifierPrefix': ['ABC123DE45'],
            'ExpirationDate': dt.datetime(2031, 1, 1),
            'Entitlements': {'application-identifier': 'ABC123DE45.com.orangeone.app', 'get-task-allow': False},
        }

    def test_valid_production_store_profile(self):
        self.assertEqual(validate_profile(self.profile, 'ABC123DE45', self.now)[1], 'Example App Store')

    def test_wrong_team_expired_or_nonstore_profiles_rejected(self):
        for change in [
            {'TeamIdentifier': ['OTHER12345']}, {'ExpirationDate': dt.datetime(2029, 1, 1)},
            {'ProvisionedDevices': ['fixture']}, {'ProvisionsAllDevices': True},
            {'UUID': '../../escape'}, {'Name': 'bad\nvalue'},
            {'Entitlements': {'application-identifier': 'ABC123DE45.com.orangeone.app.dev', 'get-task-allow': False}},
            {'Entitlements': {'application-identifier': 'ABC123DE45.com.orangeone.app', 'get-task-allow': True}},
        ]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                validate_profile({**copy.deepcopy(self.profile), **change}, 'ABC123DE45', self.now)


class CleanupTest(unittest.TestCase):
    def test_a_cleanup_failure_does_not_skip_other_secret_deletions(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / 'home'
            root = Path(temporary) / 'orangeone-signing'
            root.mkdir()
            profile = home / 'Library/MobileDevice/Provisioning Profiles/12345678-1234-1234-1234-123456789abc.mobileprovision'
            profile.parent.mkdir(parents=True)
            profile.write_bytes(b'fixture')
            (root / 'signing.keychain-db').write_bytes(b'fixture')
            (root / 'AuthKey.p8').write_bytes(b'fixture')
            (root / 'state.json').write_text(json.dumps({'previous': [], 'profile': str(profile)}))
            with patch.dict(os.environ, {'RUNNER_TEMP': temporary}), patch('ios_signing.Path.home', return_value=home), \
                    patch('ios_signing.run', side_effect=[subprocess.CalledProcessError(1, 'security'), b'']) as command:
                with self.assertRaises(ValueError):
                    cleanup()
                self.assertEqual(command.call_count, 2)
            self.assertFalse(root.exists())
            self.assertFalse(profile.exists())

if __name__ == '__main__':
    unittest.main()

