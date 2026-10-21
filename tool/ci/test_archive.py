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


def candidate(root):
    (root / 'Info.plist').parent.mkdir(parents=True, exist_ok=True)
    (root / 'Info.plist').write_bytes(plistlib.dumps({'ApplicationProperties': {'ApplicationPath': 'Applications/Runner.app'}}))
    app = root / 'Products/Applications/Runner.app'
    app.mkdir(parents=True, exist_ok=True)
    data = {'CFBundleIdentifier': 'ch.orangepos.productscanner', 'CFBundleShortVersionString': '1.0.0',
            'CFBundleVersion': '12', 'CFBundleExecutable': 'Runner'}
    (app / 'Info.plist').write_bytes(plistlib.dumps(data))
    (app / 'Runner').write_bytes(b'fixture executable')
    return app


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
            data = {'CFBundleIdentifier': 'ch.orangepos.productscanner', 'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '12', 'CFBundleExecutable': 'Runner'}
            (app / 'Runner').write_bytes(b'fixture executable')
            path.write_bytes(plistlib.dumps(data))
            validate_app(root, '1.0.0', '12')
            for key, value in [('CFBundleIdentifier', 'ch.orangepos.productscanner.dev'), ('CFBundleVersion', '13'), ('CFBundleShortVersionString', '2.0.0')]:
                path.write_bytes(plistlib.dumps({**data, key: value}))
                with self.assertRaises(ValueError):
                    validate_app(root, '1.0.0', '12')

    def test_signing_runner_only_exports_never_compiles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate(root / 'candidate/Runner.xcarchive')
            def export_only(command, **kwargs):
                self.assertEqual(command[:2], ['/usr/bin/xcodebuild', '-exportArchive'])
                self.assertNotIn('archive', command)
                self.assertNotIn('-workspace', command)
                (root / 'build/ios/ipa/Runner.ipa').write_bytes(b'fixture')
            with patch.dict(os.environ, {'RUNNER_TEMP': directory, 'APPLE_TEAM_ID': 'ABC123DE45', 'IOS_PROFILE_NAME': 'fixture', 'RELEASE_VERSION': '1.0.0', 'RELEASE_BUILD_NUMBER': '12'}), \
                    patch('export_ipa.Path.cwd', return_value=root), \
                    patch('export_ipa.subprocess.run', side_effect=export_only):
                export()
            options = plistlib.loads((root / 'store-export.plist').read_bytes())
            self.assertEqual(options['provisioningProfiles'], {'ch.orangepos.productscanner': 'fixture'})
            self.assertEqual(options['method'], 'app-store-connect')

    def test_missing_archive_never_reaches_export_tool(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(os.environ, {'RUNNER_TEMP': directory, 'RELEASE_VERSION': '1.0.0', 'RELEASE_BUILD_NUMBER': '12'}), patch('export_ipa.subprocess.run') as command:
                with self.assertRaises(OSError):
                    export()
                command.assert_not_called()

    def test_missing_or_empty_executable_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = candidate(root)
            for value in [b'', None]:
                if value is None:
                    (app / 'Runner').unlink()
                else:
                    (app / 'Runner').write_bytes(value)
                with self.assertRaises(ValueError):
                    validate_app(root, '1.0.0', '12')

    def test_invalid_zip_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'candidate.zip'
            path.write_bytes(b'not a zip')
            with self.assertRaises(zipfile.BadZipFile):
                validate_zip(path)

    def test_export_rejects_missing_empty_or_multiple_ipa_outputs(self):
        for outputs in [[], [('Runner.ipa', b'')], [('one.ipa', b'a'), ('two.ipa', b'b')]]:
            with self.subTest(outputs=outputs), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                candidate(root / 'candidate/Runner.xcarchive')
                def produce(*args, **kwargs):
                    for name, content in outputs:
                        (root / 'build/ios/ipa' / name).write_bytes(content)
                with patch.dict(os.environ, {'RUNNER_TEMP': directory, 'APPLE_TEAM_ID': 'ABC123DE45',
                                             'IOS_PROFILE_NAME': 'fixture', 'RELEASE_VERSION': '1.0.0', 'RELEASE_BUILD_NUMBER': '12'}), patch('export_ipa.Path.cwd', return_value=root), patch('export_ipa.subprocess.run', side_effect=produce):
                    with self.assertRaises(SystemExit):
                        export()


if __name__ == '__main__':
    unittest.main()
