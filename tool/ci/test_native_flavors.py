"""Check repository flavor wiring without Gradle, Xcode or distribution secrets."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
FLAVORS = ('development', 'staging', 'production')


class NativeFlavorTest(unittest.TestCase):
    def test_all_entrypoints_configs_and_gradle_flavors_exist(self):
        gradle = (ROOT / 'android/app/build.gradle.kts').read_text()
        for flavor in FLAVORS:
            with self.subTest(flavor=flavor):
                self.assertTrue((ROOT / f'lib/main_{flavor}.dart').is_file())
                self.assertTrue((ROOT / f'config/{flavor}.example.json').is_file())
                self.assertIn(f'create("{flavor}")', gradle)

    def test_shared_xcode_schemes_archive_matching_release_configuration(self):
        project = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        for flavor in FLAVORS:
            with self.subTest(flavor=flavor):
                scheme = ET.parse(ROOT / f'ios/Runner.xcodeproj/xcshareddata/xcschemes/{flavor}.xcscheme')
                self.assertEqual(scheme.find('ArchiveAction').get('buildConfiguration'), f'Release-{flavor}')
                self.assertIn(f'Release-{flavor}', project)

    def test_native_workflows_keep_flavor_matrices_and_merge_queue_coverage(self):
        for name in ('android.yaml', 'ios.yaml'):
            with self.subTest(workflow=name):
                workflow = (ROOT / '.github/workflows' / name).read_text()
                self.assertIn('flavor: [development, staging, production]', workflow)
                self.assertIn('  push:', workflow)
                self.assertIn('  pull_request:', workflow)
                self.assertIn('  merge_group:', workflow)
                self.assertIn('lib/main_${{ matrix.flavor }}.dart', workflow)


if __name__ == '__main__':
    unittest.main()
