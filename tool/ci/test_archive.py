import os
from pathlib import Path
import plistlib
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from prepare_archive import validate_zip, validate_app
from export_ipa import export


class ArchiveTest(unittest.TestCase):
    def test_rejects_escaping_paths_and_symlinks(self):
        for name, target in [('evil', None), ('../evil', None),
                             ('Runner.xcarchive/../../evil', None),
                             ('Runner.xcarchive/link', '/tmp/evil'),
                             ('Runner.xcarchive/link', '../../evil')]:
            with self.subTest(name=name, target=target), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'candidate.zip'
                with zipfile.ZipFile(path, 'w') as archive:
                    entry = zipfile.ZipInfo(name)
                    if target is not None:
                        entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                    archive.writestr(entry, target or 'fixture')
                with self.assertRaises(ValueError):
                    validate_zip(path)

    def test_accepts_internal_framework_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'candidate.zip'
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('Runner.xcarchive/Info.plist', 'fixture')
                entry = zipfile.ZipInfo('Runner.xcarchive/Products/Applications/Runner.app/Frameworks/Foo.framework/Versions/Current')
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(entry, 'A')
            validate_zip(path)

    def test_candidate_must_match_requested_production_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'Info.plist').write_bytes(plistlib.dumps({'ApplicationProperties': {'ApplicationPath': 'Applications/Runner.app'}}))
            app = root / 'Products/Applications/Runner.app'
            app.mkdir(parents=True)
            path = app / 'Info.plist'
            data = {'CFBundleIdentifier': 'com.orangeone.app', 'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '12'}
            path.write_bytes(plistlib.dumps(data))
            validate_app(root, '1.0.0', '12')
            for key, value in [('CFBundleIdentifier', 'com.orangeone.app.dev'), ('CFBundleVersion', '13'), ('CFBundleShortVersionString', '2.0.0')]:
                path.write_bytes(plistlib.dumps({**data, key: value}))
                with self.assertRaises(ValueError):
                    validate_app(root, '1.0.0', '12')

    def test_signing_runner_only_exports_never_compiles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def export_only(command, **kwargs):
                self.assertEqual(command[:2], ['/usr/bin/xcodebuild', '-exportArchive'])
                self.assertNotIn('archive', command)
                self.assertNotIn('-workspace', command)
                (root / 'build/ios/ipa/Runner.ipa').write_bytes(b'fixture')
            with patch.dict(os.environ, {'RUNNER_TEMP': directory, 'APPLE_TEAM_ID': 'ABC123DE45', 'IOS_PROFILE_NAME': 'fixture'}), \
                    patch('export_ipa.Path.cwd', return_value=root), \
                    patch('export_ipa.subprocess.run', side_effect=export_only):
                export()
            options = plistlib.loads((root / 'store-export.plist').read_bytes())
            self.assertEqual(options['provisioningProfiles'], {'com.orangeone.app': 'fixture'})
            self.assertEqual(options['method'], 'app-store-connect')


if __name__ == '__main__':
    unittest.main()
