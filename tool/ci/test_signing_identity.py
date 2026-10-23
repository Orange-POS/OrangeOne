"""Signing identity regression tests: no credentials or Apple services required."""
import base64
import contextlib
import datetime as dt
import hashlib
import io
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import ios_signing as signing

CERT = b'fixture DER certificate'
SHA = hashlib.sha1(CERT).hexdigest().upper()
TEAM = 'ABC123DE45'


def listing(*records):
    return ('\n'.join(f'  {i}) {sha} "{name}"' for i, (sha, name) in enumerate(records, 1))
            + f'\n  {len(records)} valid identities found\n').encode()


def profile():
    return {'UUID': '12345678-1234-1234-1234-123456789012', 'Name': 'Fixture',
            'TeamIdentifier': [TEAM], 'ApplicationIdentifierPrefix': [TEAM],
            'ExpirationDate': dt.datetime(2040, 1, 1), 'DeveloperCertificates': [CERT],
            'Entitlements': {'application-identifier': TEAM + '.ch.orangepos.productscanner',
                             'get-task-allow': False, 'keychain-access-groups': [TEAM + '.*']}}


class IdentityTests(unittest.TestCase):
    def test_distribution_names_and_case(self):
        for name in ('Apple Distribution: Fixture', 'iPhone Distribution: Fixture',
                     'Apple Distribution: Company "Quoted"'):
            self.assertEqual(signing.validate_certificate(profile(), listing((SHA.lower(), name))), SHA)

    def test_development_and_unrelated_names_rejected(self):
        for name in ('Apple Development: Fixture', 'iPhone Developer: Fixture',
                     'Developer ID Application: Fixture', 'Other Apple Distribution: Fixture',
                     'Apple Distribution: '):
            with self.subTest(name=name), self.assertRaises(ValueError):
                signing.validate_certificate(profile(), listing((SHA, name)))

    def test_matching_development_cannot_borrow_distribution_name(self):
        with self.assertRaises(ValueError):
            signing.validate_certificate(profile(), listing((SHA, 'Apple Development: Fixture'),
                                         ('A' * 40, 'Apple Distribution: Other')))

    def test_profile_membership_required(self):
        for data in ({}, {'DeveloperCertificates': [b'other']}):
            with self.assertRaises(ValueError):
                signing.validate_certificate(data, listing((SHA, 'iPhone Distribution: Fixture')))

    def test_exact_profile_identity_selected(self):
        self.assertEqual(signing.validate_certificate(profile(), listing(
            ('A' * 40, 'Apple Distribution: Other'), (SHA, 'iPhone Distribution: Fixture'))), SHA)

    def test_invalid_or_missing_records(self):
        valid = listing((SHA, 'Apple Distribution: Fixture'))
        for data in (b'', SHA.encode(), listing(), valid.replace(b'1 valid', b'2 valid'),
                     valid.replace(b'"\n', b'" (CSSMERR_TP_CERT_EXPIRED)\n'),
                     valid + b'  1 valid identities found\n',
                     listing((SHA, 'Apple Distribution: Fixture'), (SHA, 'Apple Distribution: Duplicate')),
                     valid.replace(SHA.encode(), SHA[:-1].encode())):
            with self.subTest(data=data), self.assertRaises(ValueError):
                signing.validate_certificate(profile(), data)


class InstallationTests(unittest.TestCase):
    def execute(self, failure=None, data=None, identities=None):
        commands = []
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = {'RUNNER_TEMP': directory, 'GITHUB_ENV': str(root / 'env'),
                   'RELEASE_FLAVOR': 'production', 'APPLE_TEAM_ID': TEAM,
                   'IOS_CERTIFICATE_PASSWORD': 'PRIVATE_SENTINEL'}
            for key in ('IOS_CERTIFICATE_BASE64', 'IOS_PROVISION_PROFILE_BASE64',
                        'APP_STORE_CONNECT_KEY_BASE64'):
                env[key] = base64.b64encode(b'fixture').decode()

            def run(*args):
                commands.append(args)
                if args[1] == failure:
                    raise subprocess.CalledProcessError(1, ['PRIVATE_SENTINEL'],
                                                        output=b'PRIVATE_SENTINEL', stderr=b'PRIVATE_SENTINEL')
                if args[1] == 'cms':
                    return plistlib.dumps(profile() if data is None else data)
                if args[1] == 'find-identity':
                    return listing((SHA, 'iPhone Distribution: Fixture')) if identities is None else identities
                return b''

            output = io.StringIO()
            with patch.dict(os.environ, env, clear=True), patch.object(signing.sys, 'platform', 'darwin'), \
                    patch.object(Path, 'home', return_value=root / 'home'), \
                    patch.object(signing, 'run', side_effect=run), contextlib.redirect_stderr(output):
                result = signing.main(['install'])
                metadata = (root / 'env').read_text() if (root / 'env').exists() else ''
                self.assertEqual(signing.main(['cleanup']), 0)
                self.assertFalse((root / 'orangeone-signing').exists())
                self.assertFalse(list((root / 'home').rglob('*.mobileprovision')))
            self.assertNotIn('PRIVATE_SENTINEL', output.getvalue())
            return result, output.getvalue(), metadata, commands

    def test_legacy_install_preserves_export_fingerprint_and_import(self):
        result, output, metadata, commands = self.execute()
        self.assertEqual((result, output), (0, ''))
        self.assertIn('IOS_CERTIFICATE_SHA1=' + SHA, metadata)
        self.assertIn('APP_STORE_CONNECT_KEY_FILE=', metadata)
        imported = next(c for c in commands if c[1] == 'import')
        self.assertIn('pkcs12', imported)
        self.assertIn('PRIVATE_SENTINEL', imported)
        self.assertTrue(any(c[1:5] == ('find-identity', '-v', '-p', 'codesigning') for c in commands))

    def test_native_failures_report_only_stage_and_cleanup(self):
        for command, stage in [('cms', 'profile-validation'), ('create-keychain', 'keychain-setup'),
                               ('import', 'certificate-import'), ('set-key-partition-list', 'keychain-access'),
                               ('find-identity', 'identity-discovery'), ('pkey', 'api-key-validation')]:
            with self.subTest(command=command):
                result, output, _, _ = self.execute(failure=command)
                self.assertEqual(result, 1)
                self.assertEqual(output, 'Apple signing operation failed at stage: ' + stage + '.\n')

    def test_wrong_team_and_bundle_fail_before_import(self):
        for key, value in [('TeamIdentifier', ['OTHER12345']),
                           ('Entitlements', {'application-identifier': TEAM + '.wrong', 'get-task-allow': False})]:
            data = profile()
            data[key] = value
            result, output, _, commands = self.execute(data=data)
            self.assertEqual(result, 1)
            self.assertIn('profile-validation', output)
            self.assertFalse(any(c[1] == 'import' for c in commands))

    def test_identity_failure_stages(self):
        for identities, stage in [(listing(), 'identity-validation'),
                                  (listing(('A' * 40, 'Apple Distribution: Other')), 'profile-certificate-match')]:
            result, output, _, _ = self.execute(identities=identities)
            self.assertEqual(result, 1)
            self.assertIn(stage, output)

    def test_malformed_base64_reports_decode_stage(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.dict(os.environ, {'RUNNER_TEMP': directory, 'IOS_CERTIFICATE_BASE64': '%%%'}), \
                patch.object(signing.sys, 'platform', 'darwin'):
            output = io.StringIO()
            with contextlib.redirect_stderr(output):
                self.assertEqual(signing.main(['install']), 1)
            self.assertEqual(output.getvalue(), 'Apple signing operation failed at stage: decode-secrets.\n')

    def test_unexpected_exception_never_leaks_traceback(self):
        with patch.object(signing.sys, 'platform', 'darwin'), \
                patch.object(signing, 'folder', side_effect=TypeError('PRIVATE_SENTINEL')):
            for operation, stage in [('install', 'decode-secrets'), ('api-key', 'api-key-validation')]:
                output = io.StringIO()
                with contextlib.redirect_stderr(output):
                    self.assertEqual(signing.main([operation]), 1)
                self.assertEqual(output.getvalue(), 'Apple signing operation failed at stage: ' + stage + '.\n')


if __name__ == '__main__':
    unittest.main()
